#!/bin/bash
# deploy-router detect.sh — mechanical scans for the detection ladder (D0/D1).
# READ-ONLY: never writes, never messages, never SSHes. macOS bash 3.2 safe (logic in python3).
#
# Usage:
#   detect.sh d0        [repo_root]   fast scan: live locks + foreign in-repo claude processes
#   detect.sh enumerate [repo_root]   full D1 union: processes + per-config-root transcript sweep
#
# Output: one JSON object on stdout. Exit 0 always (scan errors surface inside the JSON).
#
# v2 root resolution (the "false clear" fix, 2026-08-24 production post-mortem): the
# coordination root is NOT the caller's git toplevel — every service repo under Engine-Core
# is its own git repo, so a sub-repo cwd used to scan an empty nested namespace and answer
# "clear — proceeding" while 5 real peers were live (hit independently by two production
# sessions). Now the root is the OUTERMOST ancestor of cwd that carries a
# `.deploy-router-root` marker, else the outermost with `.taskstate/deploy-router`, else
# the outermost git toplevel (never / or $HOME). Every verdict names the root it scanned:
# "clear" is not an answer; "clear: scanned X" is.
#
# v2 lock states (honest states): FREE (released) / LIVE (heartbeat within TTL) /
# EXPIRED (heartbeat beyond TTL). An EXPIRED lock whose holder was still active in the
# last 15 min is flagged `_holder_active` and still BLOCKS the d0 clear verdict —
# heartbeat age alone was measured wrong 4/4 in production.
#
# v2.1 (2026-09-14, F-3 production post-mortem): "still active" is measured from the
# holder's OWN turn traffic (last assistant tool_use/text, or a user/tool_result line),
# NOT raw transcript file mtime — an inbound cross-session message appended to an idle
# holder's transcript used to bump its mtime and read as ACTIVE. Falls back to mtime only
# when no own-turn line exists, and names that fallback via `_holder_liveness_method`
# ("activity" | "mtime-fallback" | null). Kept in sync BY HAND with lock.sh's identical
# copy of `holder_transcript_age()` — no shared module. Test: tests/test_liveness.sh.

MODE="${1:-d0}"
ROOT="${2:-}"

exec python3 - "$MODE" "$ROOT" <<'PY'
import calendar, json, os, re, subprocess, sys, time, glob

mode, root_arg = sys.argv[1], sys.argv[2]
now = time.time()

HOME = os.path.expanduser("~")
def resolve_root(explicit):
    if explicit:
        return os.path.realpath(explicit)
    marker, ts, git = [], [], []
    p = os.path.realpath(os.getcwd())
    while True:
        if p not in ("/", HOME):
            if os.path.exists(os.path.join(p, ".deploy-router-root")): marker.append(p)
            if os.path.isdir(os.path.join(p, ".taskstate", "deploy-router")): ts.append(p)
            if os.path.exists(os.path.join(p, ".git")): git.append(p)
        parent = os.path.dirname(p)
        if parent == p: break
        p = parent
    for hits in (marker, ts, git):   # ancestors appended inner→outer; outermost wins
        if hits: return hits[-1]
    return os.path.realpath(os.getcwd())

root = resolve_root(root_arg)
out = {"mode": mode, "repo": root, "scanned_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "errors": []}

def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except Exception as e:
        out["errors"].append(f"{' '.join(cmd)}: {e}")
        return ""

# ---- self-identification: walk ancestry to the claude process running THIS scan
def ancestors():
    pid, chain = os.getppid(), []
    for _ in range(20):
        if pid <= 1: break
        chain.append(pid)
        s = run(["ps", "-o", "ppid=", "-p", str(pid)]).strip()
        if not s.isdigit(): break
        pid = int(s)
    return chain
anc = set(ancestors())

# ---- live claude CLI processes → cwd, config dir, sse port
procs = []
for line in run(["ps", "-axo", "pid=,args="]).splitlines():
    line = line.strip()
    m = re.match(r"(\d+)\s+(.*)", line)
    if not m: continue
    pid, args = int(m.group(1)), m.group(2)
    if not re.search(r"(^|/)claude( |$)", args): continue
    if "detect.sh" in args: continue
    cwd = ""
    for f in run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"]).splitlines():
        if f.startswith("n"): cwd = f[1:]
    env = run(["ps", "eww", "-o", "command=", "-p", str(pid)])
    cfg = (re.search(r"CLAUDE_CONFIG_DIR=(\S+)", env) or [None, os.path.expanduser("~/.claude")])[1]
    port = (re.search(r"CLAUDE_CODE_SSE_PORT=(\d+)", env) or [None, ""])[1]
    procs.append({"pid": pid, "cwd": cwd, "config_dir": cfg, "sse_port": port,
                  "self": pid in anc, "in_repo": cwd == root or cwd.startswith(root + "/")})
out["processes"] = procs
out["foreign_in_repo"] = sum(1 for p in procs if p["in_repo"] and not p["self"])

# ---- holder liveness: seconds since the lock holder's transcript last moved (None = unknown)
def _own_turn_ts(j):
    # A line is the holder's OWN turn traffic — an assistant line (tool_use/text/
    # thinking) or a user line carrying a tool_result block (the RESULT of a tool
    # call the holder itself issued). A plain "user" line whose content is a bare
    # string — a human prompt, OR an inbound cross-session/teammate message (the
    # 2026-09-13 confound: `<cross-session-message ...>` is delivered as exactly
    # this shape) — is NEVER own-turn traffic: receiving a message proves the file
    # was WRITTEN TO, not that the holder acted.
    if j.get("type") == "assistant":
        pass
    elif j.get("type") == "user":
        msg = j.get("message")
        content = msg.get("content") if isinstance(msg, dict) else None
        if not (isinstance(content, list) and
                any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content)):
            return None
    else:
        return None
    ts = j.get("timestamp")
    if not ts: return None
    try: return calendar.timegm(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S"))
    except Exception: return None

def _last_own_turn_ts(path):
    # Scan the transcript JSONL from the TAIL for the last own-turn line, growing
    # the read window (128KiB → 8MiB) until a match is found or the file is
    # exhausted — bounded, but correct even past a run of huge attachment blobs.
    try: size = os.path.getsize(path)
    except Exception: return None
    window = 131072
    while True:
        try:
            with open(path, "rb") as f:
                f.seek(max(0, size - window)); chunk = f.read()
        except Exception: return None
        lines = chunk.split(b"\n")
        if size - window > 0: lines = lines[1:]  # first fragment may be a partial line
        for raw in reversed(lines):
            raw = raw.strip()
            if not raw: continue
            try: j = json.loads(raw)
            except Exception: continue
            ts = _own_turn_ts(j)
            if ts is not None: return ts
        if window >= size: return None
        window = min(window * 4, 1 << 23) if window < (1 << 23) else size
        if window >= size: window = size

def holder_transcript_age(d):
    # Returns (age_seconds, method): method "activity" = parsed from the holder's
    # own last assistant/tool_result turn (immune to inbound cross-session/system
    # messages, which only bump the file's mtime, not its own-turn content — the
    # 2026-09-13 production confound: a courtesy takeover notice appended to an
    # idle holder's transcript made `lock.sh claim` read it as ACTIVE). method
    # "mtime-fallback" = no own-turn line found in the transcript (empty/odd file)
    # so the file's mtime is used instead — always disclosed by this method value,
    # never silently substituted. (None, None) = no transcript file at all.
    cand = []
    tp = d.get("transcript")
    if tp and os.path.isfile(os.path.expanduser(tp)): cand = [os.path.expanduser(tp)]
    else:
        u = d.get("sessionUuid") or ""
        if u and u != "unknown":
            cfg = os.path.expanduser(d.get("configDir") or "~/.claude")
            cand = glob.glob(os.path.join(cfg, "projects", "*", u + ".jsonl"))
    if not cand: return None, None
    try: path = max(cand, key=os.path.getmtime)
    except Exception: return None, None
    ts = _last_own_turn_ts(path)
    if ts is not None: return time.time() - ts, "activity"
    try: return time.time() - os.path.getmtime(path), "mtime-fallback"
    except Exception: return None, None

# ---- locks: FREE / LIVE / EXPIRED (+ holder liveness on EXPIRED — never pid; CONTRACT §4)
locks_dir = os.path.join(root, ".taskstate", "deploy-router", "locks")
live, expired, free = [], [], []
for f in glob.glob(os.path.join(locks_dir, "*.lock.json")):
    try:
        d = json.load(open(f))
        hb = d.get("heartbeat") or d.get("startedAt") or "1970-01-01T00:00:00Z"
        # timegm not mktime: UTC timestamps parsed as local made ages negative (see lock.sh)
        age = now - calendar.timegm(time.strptime(hb[:19], "%Y-%m-%dT%H:%M:%S"))
        d["_file"], d["_heartbeat_age_s"] = f, int(age)
        if d.get("released"):
            free.append(d)
        elif age <= d.get("ttlSeconds", 1800):
            live.append(d)
        else:
            ta, method = holder_transcript_age(d)  # method: "activity" | "mtime-fallback" | None
            d["_holder_transcript_age_s"] = None if ta is None else int(ta)
            d["_holder_liveness_method"] = method
            d["_holder_active"] = ta is not None and ta < 900
            expired.append(d)
    except Exception as e:
        out["errors"].append(f"lock {f}: {e}")
out["live_locks"], out["expired_locks"], out["released_locks"] = live, expired, free
blocking = live + [d for d in expired if d.get("_holder_active")]
out["blocking_locks"] = len(blocking)
out["scanned"] = (f"root={root}; {len(procs)} processes ({out['foreign_in_repo']} foreign in-repo); "
                  f"locks: {len(live)} live, {len(expired)} expired "
                  f"({sum(1 for d in expired if d.get('_holder_active'))} holder-active), {len(free)} released")

if mode == "d0":
    out["verdict"] = "clear" if (out["foreign_in_repo"] == 0 and not blocking) else "peers"
    print(json.dumps(out, indent=1)); sys.exit(0)

# ---- enumerate: per-config-root transcript sweep (fresh = mtime < 30 min)
roots = sorted(set(
    [os.path.expanduser(p) for p in
     ["~/.claude", "~/.claude-8ftools", "~/.claude-loudr", "~/.claude-anm", "~/.claude-8fai"]]
    + ([os.environ["CLAUDE_CONFIG_DIR"]] if os.environ.get("CLAUDE_CONFIG_DIR") else [])))
out["config_roots"] = roots
enc = root.replace("/", "-").replace(".", "-")
sessions = []
for cr in roots:
    pdir = os.path.join(cr, "projects", enc)
    if not os.path.isdir(pdir): continue
    for f in glob.glob(os.path.join(pdir, "*.jsonl")):
        try:
            age = now - os.path.getmtime(f)
            if age > 1800: continue
            title = ""
            with open(f, "rb") as fh:
                head = fh.read(8192)
                fh.seek(0, 2); size = fh.tell()
                fh.seek(max(0, size - 65536)); tail = fh.read()
            for blob in (tail, head):  # last rename wins
                ms = re.findall(rb'"customTitle":"([^"]+)"', blob)
                if ms: title = ms[-1].decode("utf-8", "replace"); break
            # metadata: walk tail lines from the END until each field is found (the last
            # line alone is intermittent — only some line types carry cwd/gitBranch)
            meta = {}
            for l in reversed([l for l in tail.splitlines() if l.strip()][-50:]):
                if len(meta) == 3: break
                try: j = json.loads(l)
                except Exception: continue
                for k in ("cwd", "gitBranch", "timestamp"):
                    if k not in meta and j.get(k): meta[k] = j[k]
            sessions.append({"config_dir": cr, "file": f, "title": title,
                             "mtime_age_s": int(age), "uuid": os.path.basename(f)[:-6], "last": meta})
        except Exception as e:
            out["errors"].append(f"transcript {f}: {e}")
out["fresh_sessions"] = sorted(sessions, key=lambda s: s["mtime_age_s"])
print(json.dumps(out, indent=1))
PY
