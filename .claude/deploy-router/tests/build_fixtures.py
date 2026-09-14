#!/usr/bin/env python3
"""Build the T-L1-01/02/03 fixtures (lock files + transcript jsonl) under a fresh
tmp root, ready for `lock.sh sweep --root <root>`. Run once per test invocation
(this file is idempotent — always rebuilds the same 3 fixtures)."""
import json, os, sys, time, calendar

root = sys.argv[1]
locks = os.path.join(root, ".taskstate", "deploy-router", "locks")
fixtures = os.path.join(root, "fixtures")
os.makedirs(locks, exist_ok=True)
os.makedirs(fixtures, exist_ok=True)

def ts(secs_ago):
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - secs_ago))

def write_jsonl(path, lines):
    with open(path, "w") as f:
        for j in lines:
            f.write(json.dumps(j) + "\n")

def lockfile(key, transcript_path, heartbeat_age_s=7200, ttl=60):
    return {
        "schema": "runlock-v2", "owner": "orig-holder", "sessionUuid": "holder-uuid-" + key,
        "configDir": "~/.claude", "transcript": transcript_path,
        "host": "test-host", "startedAt": ts(heartbeat_age_s + 30), "heartbeat": ts(heartbeat_age_s),
        "refreshes": 0, "ttlSeconds": ttl, "resource": key, "scope": {},
        "phase": "build", "urgency": "routine", "released": None,
    }

# ---- T-L1-01: last 3 lines are inbound cross-session messages (fresh), but the
# last assistant line is 3h old. Correct liveness = 3h (NOT fresh).
t1 = os.path.join(fixtures, "t1.jsonl")
write_jsonl(t1, [
    {"type": "assistant", "timestamp": ts(3 * 3600), "message": {"role": "assistant",
        "content": [{"type": "tool_use", "id": "x1", "name": "Bash", "input": {}}]}},
    {"type": "user", "timestamp": ts(10), "message": {"role": "user",
        "content": "Another Claude session sent a message:\n<cross-session-message from=\"uds:/tmp/x.sock\" from-name=\"peer-A\">takeover notice 1</cross-session-message>"}},
    {"type": "user", "timestamp": ts(5), "message": {"role": "user",
        "content": "Another Claude session sent a message:\n<cross-session-message from=\"uds:/tmp/x.sock\" from-name=\"peer-A\">takeover notice 2</cross-session-message>"}},
    {"type": "user", "timestamp": ts(1), "message": {"role": "user",
        "content": "Another Claude session sent a message:\n<cross-session-message from=\"uds:/tmp/x.sock\" from-name=\"peer-A\">takeover notice 3</cross-session-message>"}},
])
with open(os.path.join(locks, "t-l1-01.lock.json"), "w") as f:
    json.dump(lockfile("t-l1-01", t1), f, indent=1)

# ---- T-L1-02: last assistant line is 1 min old. Correct liveness = fresh.
t2 = os.path.join(fixtures, "t2.jsonl")
write_jsonl(t2, [
    {"type": "assistant", "timestamp": ts(60), "message": {"role": "assistant",
        "content": [{"type": "text", "text": "working on it"}]}},
])
with open(os.path.join(locks, "t-l1-02.lock.json"), "w") as f:
    json.dump(lockfile("t-l1-02", t2), f, indent=1)

# ---- T-L1-03: empty/unknown transcript (no own-turn line at all) → must fall
# back to file mtime, and the fallback must be NAMED in the result.
t3 = os.path.join(fixtures, "t3.jsonl")
open(t3, "w").close()
back = time.time() - 300  # mtime = 5 min ago
os.utime(t3, (back, back))
with open(os.path.join(locks, "t-l1-03.lock.json"), "w") as f:
    json.dump(lockfile("t-l1-03", t3), f, indent=1)

print(f"fixtures built under {root}")
