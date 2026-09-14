#!/bin/bash
# deploy-router lock.sh — RUNLOCK-v2 claims per CONTRACT.md §3–§5.
# Atomic claim (link-publish), heartbeat refresh, owner-only release, rename-not-delete
# takeover, append-only journal. v2 (2026-08-24 production post-mortem):
#   - IDENTITY IS REQUIRED at claim time. "unknown" == "unknown" once matched two DIFFERENT
#     sessions as the same owner (chemott released chat-manages-everything-w0's lock → the
#     night's one real incident). An unresolved identity now fails LOUDLY, and two
#     unresolved identities are never treated as the same session.
#   - ROOT is the shared coordination root (outermost marker / .taskstate/deploy-router /
#     git toplevel — never the caller's sub-repo), same resolution as detect.sh. Locks
#     claimed from a sub-repo cwd used to land in an invisible nested namespace.
#   - HONEST STATES: FREE (released) / LIVE / EXPIRED. Claiming over a FREE lock is a
#     RECLAIM (logged as such, with the release line) — not a "takeover" with a false
#     "heartbeat > ttl" reason (10 of 19 overnight "takeovers" were reclaims of cleanly
#     released locks). TAKEOVER of an EXPIRED lock first checks the holder's transcript
#     liveness: heartbeat-age-alone was wrong 4/4 in production; a holder still active in
#     the last 15 min is NOT taken over.
#   - v2.1 (2026-09-14, F-3 production post-mortem): liveness is the holder's OWN turn
#     traffic (last assistant tool_use/text, or a user/tool_result line), NOT raw file
#     mtime — an inbound cross-session message appended to an idle holder's transcript
#     used to bump its mtime and make a genuinely dead holder read as ACTIVE, refusing a
#     legitimate takeover. Falls back to mtime only if the transcript has no own-turn
#     line at all, and always names that fallback (`_holder_liveness_method`). See
#     SKILL.md Phase 2 and tests/test_liveness.sh.
#
# Usage:
#   lock.sh claim   <resource-key> --owner <title> [--session <uuid>] [--ttl 1800] [--phase build] [--urgency routine] [--scope '<json>'] [--root <repo>]
#   lock.sh refresh <resource-key> --owner <title> [--session <uuid>] [--root <repo>]
#   lock.sh release <resource-key> --owner <title> [--session <uuid>] [--outcome "<text>"] [--root <repo>]
#   lock.sh journal --owner <title> --line "<entry>" [--root <repo>]
#   lock.sh sweep   [--gc] [--age-h 24] [--root <repo>]
# Exit: 0 success/acquired · 1 held-by-other (holder JSON on stdout) · 2 usage/error.
# Identity: --session flag, else $CODEX_COMPANION_SESSION_ID / $CLAUDE_SESSION_ID.
# Refreshes are counted in the lock body (`refreshes`), not journaled — the guard hook
# auto-refreshes on every Bash call, which would flood the journal.

exec python3 - "$@" <<'PY'
import calendar, glob, json, os, re, sys, time

args = sys.argv[1:]
if not args: print("usage: see header", file=sys.stderr); sys.exit(2)
cmd = args[0]; rest = args[1:]
def opt(name, default=None):
    return rest[rest.index(name)+1] if name in rest else default
key = rest[0] if rest and not rest[0].startswith("--") else None

HOME = os.path.expanduser("~")
def resolve_root(explicit):
    if explicit: return os.path.realpath(explicit)
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
    for hits in (marker, ts, git):   # outermost ancestor wins
        if hits: return hits[-1]
    return os.path.realpath(os.getcwd())

root = resolve_root(opt("--root"))
base = os.path.join(root, ".taskstate", "deploy-router")
locks, journal = os.path.join(base, "locks"), os.path.join(base, "journal")
owner = opt("--owner", "unnamed-session")
uuid = opt("--session") or os.environ.get("CODEX_COMPANION_SESSION_ID") or os.environ.get("CLAUDE_SESSION_ID") or ""
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
def jpath(): return os.path.join(journal, time.strftime("%Y-%m-%d", time.gmtime()) + "-" + re.sub(r"[^A-Za-z0-9._-]", "-", owner) + ".md")
def jlog(line):
    os.makedirs(journal, exist_ok=True)
    with open(jpath(), "a") as f:
        if f.tell() == 0: f.write(f"# journal — {owner} — {time.strftime('%Y-%m-%d', time.gmtime())}\n\n")
        f.write(f"- {now} {line}\n")
def lpath(k): return os.path.join(locks, re.sub(r"[^A-Za-z0-9._-]", "-", k) + ".lock.json")
def age_s(d):
    hb = (d.get("heartbeat") or d.get("startedAt") or "1970-01-01T00:00:00Z")[:19]
    # calendar.timegm, NOT time.mktime: timestamps are UTC ("Z"); mktime reads them as LOCAL
    # (UTC-3 here) making every heartbeat look 3h in the future → nothing ever stale (T-E2-02).
    return time.time() - calendar.timegm(time.strptime(hb, "%Y-%m-%dT%H:%M:%S"))
def own_transcript():
    if not uuid: return None
    for cr in glob.glob(os.path.join(HOME, ".claude*")):
        hits = glob.glob(os.path.join(cr, "projects", "*", uuid + ".jsonl"))
        if hits: return hits[0]
    return None
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
def state_of(d):
    if d.get("released"): return "FREE"
    return "LIVE" if age_s(d) <= d.get("ttlSeconds", 1800) else "EXPIRED"

if cmd == "journal":
    jlog(opt("--line", "(empty)")); sys.exit(0)

if cmd == "sweep":
    res = {"root": root, "live": [], "expired": [], "free": []}
    for f in (os.listdir(locks) if os.path.isdir(locks) else []):
        if not f.endswith(".lock.json"): continue
        try:
            d = json.load(open(os.path.join(locks, f))); d["_file"] = f; d["_age_s"] = int(age_s(d))
            if d.get("released") is None and state_of(d) == "EXPIRED":
                ta, method = holder_transcript_age(d)
                d["_holder_transcript_age_s"] = None if ta is None else int(ta)
                d["_holder_liveness_method"] = method  # "activity" | "mtime-fallback" | None
                d["_holder_active"] = ta is not None and ta < 900
            res[{"FREE": "free", "LIVE": "live", "EXPIRED": "expired"}[state_of(d)]].append(d)
        except Exception as e: res.setdefault("errors", []).append(f"{f}: {e}")
    if "--gc" in rest:
        # rename-not-delete: FREE/EXPIRED(-and-holder-gone) locks + debris older than --age-h
        # move into locks/archive/. Live locks and active holders are never touched.
        cutoff = time.time() - float(opt("--age-h", "24")) * 3600
        arch = os.path.join(locks, "archive"); moved = []
        for d in res["free"] + [x for x in res["expired"] if not x.get("_holder_active")]:
            f = os.path.join(locks, d["_file"])
            if os.path.getmtime(f) < cutoff:
                os.makedirs(arch, exist_ok=True); os.rename(f, os.path.join(arch, d["_file"])); moved.append(d["_file"])
        for f in glob.glob(os.path.join(locks, "*.lock.json.*")):  # .stale-/.released-/.corrupt- debris
            if os.path.getmtime(f) < cutoff:
                os.makedirs(arch, exist_ok=True); os.rename(f, os.path.join(arch, os.path.basename(f))); moved.append(os.path.basename(f))
        res["gc_moved"] = moved
        if moved: jlog(f"GC {len(moved)} lock file(s) → locks/archive/ ({', '.join(moved[:6])}{'…' if len(moved) > 6 else ''})")
    print(json.dumps(res, indent=1)); sys.exit(0)

if not key: print("resource-key required", file=sys.stderr); sys.exit(2)
p = lpath(key)

if cmd == "claim":
    if not uuid:
        print(json.dumps({"acquired": False, "error":
            "IDENTITY REQUIRED: no --session and neither $CODEX_COMPANION_SESSION_ID nor "
            "$CLAUDE_SESSION_ID is set. Pass --session <this session's transcript uuid> "
            "(never a made-up value). Refusing to write sessionUuid=\"unknown\" — two "
            "'unknown' sessions once matched as the same owner and released each other's locks."}))
        sys.exit(2)
    os.makedirs(locks, exist_ok=True)
    body = {"schema": "runlock-v2", "owner": owner, "sessionUuid": uuid,
            "configDir": os.environ.get("CLAUDE_CONFIG_DIR", "~/.claude"),
            "transcript": own_transcript(),
            "host": os.uname().nodename, "startedAt": now, "heartbeat": now, "refreshes": 0,
            "ttlSeconds": int(opt("--ttl", "1800")), "resource": key,
            "scope": json.loads(opt("--scope", "{}") or "{}"),
            "phase": opt("--phase", "build"), "urgency": opt("--urgency", "routine"), "released": None}
    # Publish pattern: write the FULL body to a private temp file, then os.link() it to the
    # final name. link() is atomic and fails EEXIST like O_EXCL, but — unlike open+write —
    # a lock that is visible is always COMPLETE, so a racing reader can never see partial
    # JSON and mis-take a fresh lock for corrupt/stale (defect caught live by T-E2-01).
    tmp = os.path.join(locks, f".tmp-{os.getpid()}-{int(time.time()*1000)}")
    with open(tmp, "w") as f: json.dump(body, f, indent=1)
    for attempt in (1, 2):
        try:
            os.link(tmp, p); os.unlink(tmp)
            jlog(f"CLAIM {key} (phase={body['phase']}, ttl={body['ttlSeconds']}s)")
            print(json.dumps({"acquired": True, "lock": p})); sys.exit(0)
        except FileExistsError:
            try: d = json.load(open(p))
            except Exception: d = None
            if d is None:  # corrupt → rename, never delete
                cn = p + ".corrupt-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
                os.rename(p, cn); jlog(f"CORRUPT-EVICT {key}: unparseable lock → {os.path.basename(cn)}")
                continue
            st = state_of(d)
            if st == "FREE":  # honest reclaim of a cleanly released lock — NOT a takeover
                rn = p + ".released-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
                os.rename(p, rn)
                jlog(f"RECLAIM {key}: previous lock was RELEASED by {d.get('owner','?')} ({d.get('released')}) → {os.path.basename(rn)}")
                continue
            if st == "EXPIRED":
                ta, method = holder_transcript_age(d)  # method: "activity" | "mtime-fallback" | None
                if ta is not None and ta < 900:  # holder's OWN turn traffic (or, absent that, the
                    # transcript file's mtime) is moving → ACTIVE, no takeover. An inbound
                    # cross-session/system message alone does NOT count (2026-09-13 production
                    # confound: a courtesy takeover notice appended to an idle holder's
                    # transcript bumped its mtime and made a dead holder read as ACTIVE).
                    d["_age_s"], d["_holder_transcript_age_s"], d["_holder_liveness_method"] = int(age_s(d)), int(ta), method
                    os.unlink(tmp)
                    basis = ("holder transcript's own last assistant/tool_result turn" if method == "activity"
                             else "holder transcript FILE MTIME (fallback — no own-turn line found in the transcript)")
                    print(json.dumps({"acquired": False, "holder": d, "note":
                        f"heartbeat expired ({int(age_s(d))}s > ttl {d.get('ttlSeconds', 1800)}s) but {basis} "
                        f"moved {int(ta)}s ago — holder is ACTIVE; negotiate or wait, no takeover."}))
                    sys.exit(1)
                if ta is None:
                    ev = "no transcript found for holder"
                elif method == "mtime-fallback":
                    ev = f"holder transcript idle {int(ta)}s (MTIME FALLBACK — no own-turn line found)"
                else:
                    ev = f"holder transcript idle {int(ta)}s (own last assistant/tool_result turn)"
                sn = p + ".stale-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
                os.rename(p, sn)
                jlog(f"TAKEOVER {key}: EXPIRED lock from {d.get('owner','?')} (heartbeat age {int(age_s(d))}s > ttl {d.get('ttlSeconds', 1800)}s; {ev}) → {os.path.basename(sn)}")
                continue
            d["_age_s"] = int(age_s(d))
            os.unlink(tmp)
            print(json.dumps({"acquired": False, "holder": d})); sys.exit(1)
    os.unlink(tmp)
    print(json.dumps({"acquired": False, "error": "takeover loop exhausted"})); sys.exit(1)

try: d = json.load(open(p))
except Exception as e: print(json.dumps({"error": f"no such lock: {e}"})); sys.exit(2)
held_uuid = d.get("sessionUuid") or ""
# Ownership = resolved-uuid equality ONLY. "unknown"/empty NEVER matches anything (the
# production incident); owner-title equality is no longer an ownership proof.
mine = bool(uuid) and uuid != "unknown" and held_uuid == uuid
if cmd == "refresh":
    if not mine:
        why = ("lock has legacy sessionUuid='unknown' — not refreshable by anyone; if stale, claim will take it over"
               if held_uuid in ("", "unknown") else "not owner")
        print(json.dumps({"refused": why, "holder": d})); sys.exit(1)
    d["heartbeat"] = now; d["refreshes"] = int(d.get("refreshes", 0)) + 1
    json.dump(d, open(p, "w"), indent=1); print('{"refreshed": true}'); sys.exit(0)
if cmd == "release":
    if not mine:
        why = ("lock has legacy sessionUuid='unknown' — identity can't be proven, refusing (a session once "
               "released a DIFFERENT session's 'unknown' lock); if stale, claim will take it over"
               if held_uuid in ("", "unknown") else "not owner")
        print(json.dumps({"refused": why, "holder": d})); sys.exit(1)
    d["released"] = f"{now} {opt('--outcome', 'done')}"
    json.dump(d, open(p, "w"), indent=1); jlog(f"RELEASE {key}: {d['released']}")
    print('{"released": true}'); sys.exit(0)
print("unknown command", file=sys.stderr); sys.exit(2)
PY
