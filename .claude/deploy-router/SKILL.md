---
name: deploy-router
description: Pre-deploy coordination gate for parallel Claude Code sessions — run BEFORE /engine-deploy, /deploy-brain-app, or ANY command that mutates shared deploy infrastructure (terraform on the tenants box, box tenants.json, ghcr pushes, kubectl mutations, apps-box compose). Detects other active sessions across ALL subscriptions, classifies them (DEPLOYING-NOW / ABOUT-TO-DEPLOY / PROD-DATA-WRITER / UNRELATED), negotiates via SendMessage, claims resource-scoped locks + the box-wide apply-mutex, re-reads the live tenant set, and hands the deploy a coordination context block. This skill NEVER deploys anything itself. Trigger with "/deploy-router", "route the deploy", "coordinate the deploy", "check for parallel deploys", "who else is deploying", or as step 0 whenever the user says "ship it", "deploy this", "push to prod" and more than one session may be active.
author: DevOtts
author_url: https://github.com/DevOtts
---

# /deploy-router

Coordination gate born from a real incident: on 2026-08-23 a parallel session decommissioned
the `aivivum` tenant mid-overnight-run, and the same evening produced a human-caught
terraform-apply collision and two silent last-write-wins overwrites. The box terraform
backend has **no state locking**; box `tenants.json` is one unversioned file written by ≥5
skills. Full evidence: `Engine-Core/docs/implementation/deploy-router/` (research + CONTRACT
v1.0 — the law this skill implements; decisions D1–D7 are locked, do not re-litigate).

**Hard constraints:**
- **Main loop only.** Subagents cannot call `ListAgents`/`notify_when_idle` — run the ladder
  in the main conversation; delegate only pure file/process scans.
- **This skill never mutates anything remote.** Box access is read-only (+F check). No
  terraform, no kubectl writes, no docker push, no edits to /engine-deploy or
  /deploy-brain-app, no GitHub-Actions mechanisms.
- **Session identity is REQUIRED and must be resolved, never guessed.** F18 (found
  2026-09-02): the "newest transcript jsonl" fallback below picks a SIBLING session's
  transcript for a forked/child worker — a child's own transcript is not necessarily the
  most-recently-written file in its config dir when a sibling is also active, so the guess
  silently claims locks under the wrong identity. `$CLAUDE_CODE_SESSION_ID` is set
  reliably (unlike `$CODEX_COMPANION_SESSION_ID`/`$CLAUDE_SESSION_ID`, which are NOT
  exported in most subscriptions) and always names YOUR OWN session, forked or not — check
  it first and only fall back to the guess when it's unset:
  ```bash
  SID=${CLAUDE_CODE_SESSION_ID:-${CODEX_COMPANION_SESSION_ID:-${CLAUDE_SESSION_ID:-}}}
  [ -z "$SID" ] && SID=$(basename "$(ls -t ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/*/*.jsonl | head -1)" .jsonl)
  ```
  (the fallback's assumption — your own transcript is the most-recently-written one in YOUR
  config dir — only holds for a lone top-level session; a forked/child worker must rely on
  `$CLAUDE_CODE_SESSION_ID` instead). `lock.sh claim` refuses to run without identity: two
  `"unknown"` sessions once matched as the same owner and released each other's locks.
- **Run from anywhere — the coordination root auto-resolves.** Every service repo under
  Engine-Core is its own git repo; the scripts resolve the OUTERMOST ancestor with a
  `.deploy-router-root` marker / `.taskstate/deploy-router` / git toplevel, so a sub-repo
  cwd can no longer scan an empty nested namespace and answer a false "clear" (the
  2026-08-24 production bug, hit by two sessions independently). Corollary: **"clear" is
  not an answer; "clear: scanned X" is** — always relay the `scanned` line.

Scripts (this skill's `scripts/`, all safe to re-run):
- `detect.sh d0|enumerate [repo_root]` — read-only scans, JSON out. Locks report in three
  honest states: LIVE / EXPIRED (with holder-transcript liveness) / FREE (released).
- `lock.sh claim|refresh|release|journal|sweep [--gc]` — RUNLOCK-v2 locks + append-only
  journal; `sweep --gc` archives released/dead lock files >24h old into `locks/archive/`.
- `deploy-router-guard.mjs` — the PreToolUse enforcement hook (installed by
  `install-hook.sh`, not invoked manually). Besides denying conflicting deploy commands,
  it AUTO-REFRESHES this session's own live locks on every Bash call.
- `tests/test_liveness.sh <path-to-lock.sh>` — mini test contract (T-L1-01/02/03, added
  2026-09-14) proving the holder-liveness parser below correctly ignores inbound messages;
  run it against a candidate `lock.sh` before touching the liveness logic again.

## Phase 0 — D0 fast scan (the common case: pass through in seconds)

```bash
~/.claude/skills/deploy-router/scripts/detect.sh d0
```
- `verdict: "clear"` (no foreign in-repo claude processes AND no blocking locks — blocking
  = LIVE, or EXPIRED with `_holder_active: true`) → relay the JSON's `scanned` line
  verbatim — `router: clear — <scanned> — proceeding` — and hand off to the deploy skill.
  Never say bare "clear" without what was scanned. **No messages, no files written, no
  questions.** Done.
- `verdict: "peers"` → Phase 1. A blocking foreign lock in the output short-circuits
  straight to negotiation (Phase 2) with that holder.

## Phase 1 — Detect & classify (D1–D3)

**D1 — enumerate:** `detect.sh enumerate` unions three sources: live processes (machine-wide,
with per-pid `config_dir` — **cross-subscription peers appear here and ONLY here**),
fresh transcripts per config root (title + last-line `cwd`/`gitBranch`/`timestamp`), and —
for same-subscription peers — `ListAgents` (busy/idle + names for messaging). Dedupe by
uuid/title. Ignore sessions in other repos UNLESS their evidence touches a shared host
(the apps box `75.119.153.239` and tenants box `167.86.98.85` are shared across projects).

**D2 — classify each in-repo peer.** Title and busy/idle are NEVER decisive (proven to
misclassify in both directions). Read only the transcript **tail** (≤50KB, bounded) and
judge by actual recent tool calls. **Cheap path:** D2 is the expensive step and its answer
is stable — journal each classification with the peer's transcript `mtime_age_s`; on a
later routing in the same session, re-classify a peer ONLY if its transcript mtime moved
since your last recorded classification (unchanged mtime = unchanged verdict, reuse it):

| Verdict | Decisive evidence in the tail |
|---|---|
| `DEPLOYING-NOW` | mutating calls within ~15 min: `terraform apply/destroy`, `docker push`, box tenants.json writes, `kubectl apply/set/rollout/scale`, box `compose up` |
| `ABOUT-TO-DEPLOY` | merge to a service repo main not yet pinned; deploy skill loaded AND branch/PR/build activity; stated deploy intent |
| `PROD-DATA-WRITER` | direct prod DB writes (mongosh/psql), no pipeline — no lock conflict; flag it in the context block |
| `UNRELATED` | **no shared-resource fingerprint at all** — no mutating call, no deploy-adjacent branch/PR/build work, no stated deploy intent. Covers BOTH the in-repo research/reading peer AND the different-repo peer (for the latter, the shared-host exception still overrides: a peer touching `75.119.153.239` or `167.86.98.85` is never UNRELATED, whatever repo it sits in) |
| `UNKNOWN` | frozen/unreadable → treat as `ABOUT-TO-DEPLOY` |
| `LIVE-SQUAD-RUN` | **not a Claude Code peer at all** — a live `pipeline_runs` doc with `status:"running"` on the deploy's TARGET tenant, found by `check-live-squad-runs.sh` (below). No session, no lock file, no git activity names this resource, so D1/D2's peer-scan misses it entirely; it needs its own check. |

**D3 — interrogate** (same-subscription `DEPLOYING-NOW`/`ABOUT-TO-DEPLOY`/`UNKNOWN` peers
only — cross-subscription peers are unreachable by SendMessage; their D2 verdict + lock
files stand). Send the proven 3-question probe:

> 1. STATUS: deployed / mid-deploy / planning? Which repos, tenants, resources?
> 2. Next 2h: any deploy or prod mutation planned?
> 3. Could you comply with a hold, and what is your current safe hold point?

Bounded wait: **5 minutes** (D6). Timeout → journal
`proceeding-despite-silence(<peer>)`, keep the D2 verdict, continue under locks.

## Phase 2 — Negotiate & claim (L2 + L1)

**Negotiation intents** (plain prose carrying these fields): `ANNOUNCE` scope+phase ·
`QUERY` (the probe) · `HOLD-REQUEST` resource+duration+reason+urgency · `HOLD-ACK` /
`HOLD-REFUSE` (+counter-proposed hold point) · `RELEASE`. **Priority rule (D4): the
less-urgent session holds.** Urgency ladder: `outage-fix > overnight-dod > routine >
quick-win` — self-declare honestly; disputes/ties go to Fernando, nothing else does.
Holds land at **hold points** only: `pre-build`, `post-push-pre-pin`, `post-verify` —
never mid-step. Cross-subscription negotiation happens through the journal + locks alone.

**Claim locks** (resource keys per CONTRACT §3), least-scope first — `--session "$SID"`
(resolved per Hard constraints) is REQUIRED, claims fail loudly without it:
```bash
S=~/.claude/skills/deploy-router/scripts
$S/lock.sh claim git-main:brain-api-core --owner "<my session title>" --session "$SID" \
  --phase build --urgency routine --ttl 1800 \
  --scope '{"repos":["brain-api-core"],"tenants":["praxya"]}'
# … one claim per resource the deploy will touch; and for the plan→apply span ONLY:
$S/lock.sh claim apply-mutex --owner "<title>" --session "$SID" --phase apply --ttl 1800
```
- `exit 1` = held by another session (holder JSON on stdout) → negotiate with that owner
  (or wait for its hold point/TTL). Never delete a lock. `claim` itself handles the rest,
  with three honest states: a **FREE** (released) lock is **RECLAIMed** (renamed
  `.released-<ts>`, journaled with the release line); an **EXPIRED** one (heartbeat age >
  TTL) is **TAKEN OVER only if the holder's transcript is also idle ≥15 min** — heartbeat
  age alone was wrong 4/4 in production; a holder who is still active is not taken over,
  the claim refused with that evidence. Never judged by pid.
  - **Liveness is measured from the holder's OWN turn traffic, never raw file mtime**
    (fixed 2026-09-14, F-3: on 2026-09-13 a courtesy takeover notice — a
    `SendMessage`/`<cross-session-message>` — appended to an idle holder's transcript
    bumped the file's mtime, and `lock.sh claim` read that as "holder transcript moved
    6s ago — ACTIVE", refusing a legitimate takeover of a genuinely dead 2h-idle holder).
    `holder_transcript_age()` now scans the transcript JSONL from the tail and takes the
    timestamp of the last line that is the holder's **own** turn — an `assistant` line
    (`tool_use`/`text`/`thinking`) or a `user` line carrying a `tool_result` block (the
    RESULT of a tool call the holder itself issued) — and explicitly **ignores** `user`
    lines whose content is a bare string: a plain human prompt or an inbound
    cross-session/system message, either of which proves the file was written to, not
    that the holder acted. Only when the transcript has **no** such own-turn line at all
    (empty/odd file) does it fall back to the file's mtime — and that fallback is always
    **named**, never silent: the result carries `_holder_liveness_method` (`"activity"` |
    `"mtime-fallback"` | `null`=no transcript found), and a refused `claim`'s `note` /
    a `TAKEOVER` journal line spells out which basis it used. `detect.sh` carries an
    identical copy of the function (kept in sync by hand — there is no shared module);
    a change to one requires the same change to the other. Contract + fixtures:
    `tests/test_liveness.sh`.
- **Heartbeat duty is automatic:** the guard hook refreshes YOUR live locks on every Bash
  call (counted in the lock body's `refreshes` field — refreshes are not journaled).
  Manual `lock.sh refresh <key> --owner "<title>" --session "$SID"` is only needed before
  a long stretch with no Bash calls (pure reading/analysis). The transcript-liveness check
  above is the backstop if you go quiet anyway.
- `apply-mutex` is claimed just before the terraform plan and released right after the
  apply — minutes, not the whole run. It serializes ALL box applies (one state serial,
  no backend locking) even across different tenants.
- **`git-main:<repo>` enforcement scope:** the guard fingerprints `git push …main/master`
  and `gh pr merge` on this machine (it didn't before 2026-08-24 — 78% of production
  claims had zero enforcement). Merges made OUTSIDE this machine (GitHub web UI, another
  box) remain invisible — treat `git-main:*` as enforced-locally, advisory-globally.

**Journal** every event: `$S/lock.sh journal --owner "<title>" --line "..."` — one
append-only file per session per day in `.taskstate/deploy-router/journal/`. Never write
another session's file; never write the legacy `DEPLOY-COORDINATION-*.md` (last-write-wins
by construction — read-only during sunset).

## Phase 3 — Pre-flight checks + handoff

**Stale-tree eviction check** (before pinning any image): built commit must equal the
repo's CURRENT `origin/main` HEAD (`git fetch origin main && git rev-parse origin/main`).
Behind → a sibling merged since the build → **rebuild before pinning**. Never pin an image
whose tree predates a sibling's merge.

**Live-squad-run check** (`deploy-router-blind-to-live-squad-runs`, discovery-g6 #17 —
required before rolling out `brain-api-core` or `brain-agent` to any tenant; skip for
other repos). A deploy mid-squad-run silently orphans the run forever: the executor's
`setImmediate` fire-and-forget has no resume/lock, so a `status:"running"` `pipeline_runs`
doc left behind by a killed pod never advances again — no error, $0 further spend, and
nothing in this skill's peer-scan can see it (it's not a Claude Code session). Run, per
target tenant, BEFORE the rollout:
```bash
~/.claude/skills/deploy-router/scripts/check-live-squad-runs.sh <tenant> [<tenant> ...]
```
- Exit 0 (`verdict: "clear"` for every tenant) → proceed.
- Exit 1 (`verdict: "LIVE-SQUAD-RUN"` for any tenant, `running_count` ≥ 1, `sample[]`
  names the run(s)) → **hold** the same way a blocking lock would: this is the D2 table's
  `LIVE-SQUAD-RUN` verdict, no negotiation possible (it's not a session) — wait for the
  run to reach a terminal status (`done`/`failed`/`cancelled`/`refused_ceiling`/
  `awaiting_checkpoint`, the last only if the rollout can tolerate a paused-not-running
  run) or get the run's owner to confirm it's abandoned before rolling.
- This is a **minimum** check (counts + names `status:"running"` only) — the bigger fix
  (a resumable lock + orphan sweep in `src/squads/`) is a separate, bigger item, not this
  gate.

**+F freshness check** (immediately before any apply/rollout loop — catches the aivivum
class, which no lock can): read the live tenant key set from the box (read-only SSH; creds
`new_contabo_vps_tenants` from `Engine-Core/.secrets/.full.credentials` — NOT the repo root;
engine-deploy §6's root path is stale — read each time, never echo):
```bash
$SSH "python3 -c 'import json;print(sorted(json.load(open(\"/opt/processor/infrastructure/terraform/tenants.json\")).keys()))'"
```
Diff against the deploy's target list. Drift (tenant gone/added) → report state
`stopped-tenant-set-drift`: STOP, journal, re-scope the targets, then continue with the
corrected list and say so in the run report.

**Hand off** to the deploy skill with this block (the deploy run carries it):
```
── deploy-router coordination context ─────────────────────────
locks held: <key (phase, TTL left)> …          heartbeat duty: refresh at each step
holds: granted <to whom, until> / received <from whom>
ordering: <e.g. rebuild-if-main-moves for brain-api-core; peer X pins after me>
tenant set: <sorted keys> read at <ts> — re-verified pre-apply
peers: <classified list, one line each>
release duty: lock.sh release <keys> after verify; journal close
───────────────────────────────────────────────────────────────
```

## Phase 4 — Release

After the deploy's verify step: `lock.sh release <key> --owner "<title>" --session "$SID"
--outcome "<one line>"` for every held lock (TTL is only the crash backstop, not the
release mechanism), journal the outcome, and send `RELEASE` to any peer that was holding
for you. Opportunistic hygiene: `lock.sh sweep --gc` archives dead lock files >24h old.

## Failure states (all first-class, none silent)

| State | Behavior |
|---|---|
| Peer unresponsive | 5-min wait → journal + proceed under locks; never block on a peer indefinitely. Covers busy peers, idle interactive peers (no tool round until their user returns), AND probes held for the peer user's approval (sessions not in bypass mode hold inbound cross-session messages — a delivery notice tells you; the held message can also EXPIRE undelivered; treat both as silence, don't wait) |
| Released lock | reclaimed by `claim` as `RECLAIM` (rename `.released-<ts>` + journal with the release line) — an honest event, never logged as a takeover |
| Stale lock | heartbeat age > TTL AND the holder's own last assistant/tool_result turn (not raw file mtime — see Phase 2) is idle ≥15 min → `claim` takes over (rename `.stale-<ts>` + journal with BOTH evidences); still-active-by-that-measure = holder ACTIVE, claim refused; never pid, never delete |
| Deploy outside Claude entirely | out of reach — residual risk; optional paranoid pre-apply probe: box-side `ps aux | grep terraform` (read-only) |
| Cross-subscription peer | unreachable by SendMessage — locks + journal ARE the handshake |
| Router racing router | atomic link-publish claim + tiebreak (earlier `startedAt`, then lexicographic sessionUuid) |
| No peers | Phase 0 pass-through, seconds, zero friction |

## Report

End every routed deploy with exactly one state — `clear-passthrough` ·
`negotiated-proceed` · `holding(<for-whom>,<until>)` · `taken-over-stale-lock` ·
`proceeding-despite-silence(<peer>)` · `stopped-tenant-set-drift` — plus: the `scanned`
line (root + counts — every verdict names what it looked at), peers found and their
verdicts, locks claimed/released, holds exchanged, and the tenant-set snapshot used.
Honest states only; a hold or a stop is a SUCCESS of the gate, not a failure of the run.

---
_Authored by [DevOtts](https://github.com/DevOtts)._
