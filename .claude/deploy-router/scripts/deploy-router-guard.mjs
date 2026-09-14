#!/usr/bin/env node
// deploy-router-guard.mjs — PreToolUse enforcement layer (L3) per CONTRACT.md v1.0 §6.2.
//
// Denies a deploy-shaped Bash command ONLY when a live, unexpired lock on the same resource
// is held by a DIFFERENT session in the shared coordination root's .taskstate/deploy-router/
// locks/. Everything else is allowed, and the ENTIRE body is fail-open: any error, missing
// dir, non-gated repo, or unparseable payload → allow. This hook must never break non-deploy
// work. (Structural template: plan-it's planit-guard.mjs.)
//
// v2 (2026-08-24 production post-mortem):
//   - locksDir = the OUTERMOST ancestor carrying .taskstate/deploy-router (was: nearest —
//     a stray sub-repo namespace split-brained the guard exactly like detect.sh/lock.sh).
//   - AUTO-REFRESH: on EVERY Bash call in a gated repo, the guard heartbeats the caller's
//     own live locks (payload.session_id vs lock sessionUuid) before any verdict. Manual
//     refresh discipline failed in production — two sessions hand-built their own refreshers.
//   - git-main enforcement: `git push …main/master` and `gh pr merge` now fingerprint to
//     git-main:<repo> (78% of production claims had zero guard coverage). Merges done
//     outside this machine (web UI) remain invisible — git-main is enforced here, not proven.
//   - Deny reason states the honest lock state; a command that BUNDLES `lock.sh release`
//     with the deploy step gets an explicit "run the release alone first" hint instead of
//     a silent wholesale deny.

import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { dirname, join, basename } from "node:path";

const allow = () => process.exit(0); // no output = proceed
const deny = (reason) => {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  }));
  process.exit(0); // decision travels in the JSON, never the exit code
};

try {
  const payload = JSON.parse(readFileSync(0, "utf8"));
  if (payload.tool_name !== "Bash") allow();
  const cmd = String(payload.tool_input?.command ?? "");
  if (!cmd) allow();

  // ---- locate the gated coordination root: walk up from payload cwd; OUTERMOST wins
  let p = payload.cwd || process.cwd();
  let locksDir = null;
  for (let i = 0; i < 24 && p && p !== "/"; i++, p = dirname(p)) {
    const cand = join(p, ".taskstate", "deploy-router", "locks");
    if (existsSync(cand)) locksDir = cand; // keep walking — outermost match wins
  }

  const self = payload.session_id || payload.sessionId || "";

  // ---- AUTO-REFRESH own live locks (best-effort, per-file fail-open) before any verdict
  if (locksDir && self) {
    for (const f of readdirSync(locksDir)) {
      if (!f.endsWith(".lock.json")) continue;
      try {
        const fp = join(locksDir, f);
        const d = JSON.parse(readFileSync(fp, "utf8"));
        if (d.released || !d.sessionUuid || d.sessionUuid === "unknown" || d.sessionUuid !== self) continue;
        d.heartbeat = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
        d.refreshes = (d.refreshes ?? 0) + 1;
        writeFileSync(fp, JSON.stringify(d, null, 1));
      } catch { /* fail-open per lock */ }
    }
  }

  // ---- COMMAND-POSITION segmentation (false-positive fix, found live during T-E4-01):
  // a fingerprint counts only when its binary is the FIRST word of a shell segment — not
  // merely a substring. Otherwise any command QUOTING a deploy string (a prompt passed to
  // `claude -p`, an `echo`, a commit message) gets denied while a lock is live.
  // Segments: split on ; & | newline $( ` — then, for ssh/sshpass wrappers, the quoted
  // remote command's own segments are recursively included.
  // Quote-aware splitter: ; & | newline $( ` break segments only OUTSIDE quotes, so text
  // inside a quoted argument (a commit message, a prompt) never starts a segment. Quoted
  // remote commands are opened deliberately — and only — by the ssh/scp expansion below.
  const segsOf = (s) => {
    const out = []; let cur = "", q = null;
    for (let i = 0; i < s.length; i++) {
      const c = s[i];
      if (q) { cur += c; if (c === q && s[i - 1] !== "\\") q = null; continue; }
      if (c === '"' || c === "'") { q = c; cur += c; continue; }
      if (c === ";" || c === "&" || c === "|" || c === "\n" || c === "`" || (c === "$" && s[i + 1] === "(")) {
        if (c === "$") i++;
        out.push(cur); cur = ""; continue;
      }
      cur += c;
    }
    out.push(cur);
    return out.map((x) => x.trim()).filter(Boolean);
  };
  const segments = [];
  const expand = (seg, depth) => {
    if (depth > 3) return;
    // strip leading env assignments / sudo / timeout / nohup
    let t = seg.replace(/^(?:\w+=\S*\s+|sudo\s+|nohup\s+|timeout\s+\S+\s+)*/, "");
    segments.push(t);
    if (/^(sshpass\b|ssh\b|scp\b)/.test(t)) {
      for (const q of t.match(/"([^"]*)"|'([^']*)'/g) ?? []) {
        for (const inner of segsOf(q.slice(1, -1))) expand(inner, depth + 1);
      }
    }
  };
  for (const s of segsOf(cmd)) expand(s, 0);
  const cmdPos = (re) => segments.some((t) => re.test(t));

  // ---- fingerprint → wanted resource keys (anchored: ^ = start of a segment)
  const wanted = new Set();
  if (cmdPos(/^terraform\s+(-\S+\s+)*(apply|destroy)\b/)) {
    wanted.add("apply-mutex");
    for (const m of cmd.matchAll(/module\.tenant\[\\?["']([\w-]+)\\?["']\]/g)) wanted.add(`tenant:${m[1]}`);
  }
  if (cmdPos(/^docker\s+push\b/)) {
    const m = cmd.match(/ghcr\.io\/[\w-]+\/([\w.-]+)/);
    wanted.add(m ? `ghcr:${m[1]}` : "ghcr:*");
  }
  if (/tenants\.json/.test(cmd) &&
      (cmdPos(/^(scp\b|sed\s+-i\b|tee\b|python3?\s+-|cp\b|mv\b)/) || />\s*\S*tenants\.json/.test(cmd))) {
    wanted.add("tenants-json"); // write-shaped touch of the box file (read-only cats don't match)
  }
  if (cmdPos(/^kubectl\b/) && /\b(apply|set|rollout|scale|delete|patch)\b/.test(cmd)) {
    const m = cmd.match(/-n\s+processor-([\w-]+)/);
    wanted.add(m ? `tenant:${m[1]}` : "k8s");
  }
  if (cmdPos(/^docker\s+compose\b.*\bup\b/) || (cmdPos(/^docker\b/) && /compose[\s\S]*\bup\b/.test(cmd) && cmdPos(/^docker\s+compose\b/))) {
    const m = cmd.match(/\b(\d{1,3}(?:\.\d{1,3}){3})\b/);
    wanted.add(m ? `host:${m[1]}` : "compose");
  }
  // git-main:<repo> — push touching main/master, or a PR merge. Repo = -C dir, else cwd.
  const gitSeg = segments.find((t) => /^git\s+(-C\s+\S+\s+)?push\b/.test(t) && /\b(main|master)\b/.test(t));
  const mergeSeg = segments.find((t) => /^gh\s+pr\s+merge\b/.test(t));
  if (gitSeg || mergeSeg) {
    const mC = (gitSeg || mergeSeg).match(/-C\s+(\S+)/) || (mergeSeg || "").toString().match(/--repo\s+\S*?\/([\w.-]+)/);
    const repo = basename(mC ? mC[1] : (payload.cwd || process.cwd()));
    wanted.add(`git-main:${repo}`);
  }
  if (wanted.size === 0) allow(); // not deploy-shaped — the common case, cost ≈ regex only

  if (!locksDir) allow(); // repo not gated → inert

  // ---- any LIVE FOREIGN lock on a wanted resource?
  for (const f of readdirSync(locksDir)) {
    if (!f.endsWith(".lock.json")) continue;
    let d;
    try { d = JSON.parse(readFileSync(join(locksDir, f), "utf8")); } catch { continue; } // corrupt → ignore (fail-open)
    if (d.released) continue; // FREE
    const hb = Date.parse(d.heartbeat || d.startedAt || 0); // Date.parse handles Z as UTC
    const ttl = (d.ttlSeconds ?? 1800) * 1000;
    if (!hb || Date.now() - hb > ttl) continue; // EXPIRED — takeover liveness is lock.sh's job
    if (d.sessionUuid && self && d.sessionUuid === self) continue; // own lock (auto-refreshed above)
    const res = String(d.resource || "");
    const hit = wanted.has(res) ||
      (res === "apply-mutex" && wanted.has("apply-mutex")) ||
      (res.startsWith("ghcr:") && wanted.has("ghcr:*")) ||
      (wanted.has("k8s") && res.startsWith("tenant:"));
    if (hit) {
      const ageS = Math.round((Date.now() - hb) / 1000);
      const ttlLeft = Math.max(0, Math.round((ttl - (Date.now() - hb)) / 1000));
      const bundled = /lock\.sh\s+(release|refresh)\b/.test(cmd)
        ? ` NOTE: your command BUNDLES lock.sh release/refresh with the deploy step — the guard denies the whole ` +
          `bundle; run the lock.sh command ALONE first, then re-run the deploy step separately.`
        : "";
      deny(
        `deploy-router: resource "${res}" is LIVE-locked by session "${d.owner}" ` +
        `(phase=${d.phase ?? "?"}, urgency=${d.urgency ?? "?"}, heartbeat ${ageS}s ago, TTL expires in ~${ttlLeft}s). ` +
        `Do NOT bypass. Options: (1) SendMessage to "${d.owner}" to negotiate a hold point ` +
        `(less-urgent session holds — CONTRACT D4); (2) wait for release/TTL; ` +
        `(3) if you believe this lock is abandoned, run the deploy-router stale-takeover (lock.sh claim — it ` +
        `checks the holder's transcript liveness), never a manual delete. Locks: ${locksDir}.${bundled}`
      );
    }
  }
  allow();
} catch {
  allow(); // FAIL-OPEN BY DESIGN — a broken guard must never block work
}
