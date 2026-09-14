#!/bin/bash
# Mini test contract for the holder-liveness fix (drain-2026-09-14 L1).
# Usage: test_liveness.sh <path-to-lock.sh-under-test>
set -uo pipefail
LOCK_SH="${1:?usage: test_liveness.sh <path-to-lock.sh>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(mktemp -d /tmp/deploy-router-liveness-test.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT

python3 "$HERE/build_fixtures.py" "$ROOT" >/dev/null

OUT="$(bash "$LOCK_SH" sweep --root "$ROOT")"
if [ -z "$OUT" ]; then
  echo "FAIL: sweep produced no output"; exit 2
fi

echo "=== raw sweep output (expired locks) ==="
python3 -c "
import json
d = json.loads('''$OUT''')
for x in d.get('expired', []):
    print(x.get('resource'), '_holder_transcript_age_s=', x.get('_holder_transcript_age_s'),
          '_holder_active=', x.get('_holder_active'),
          '_holder_liveness_method=', x.get('_holder_liveness_method', '<absent>'))
"

python3 - "$OUT" <<'PYEOF'
import json, sys
out = json.loads(sys.argv[1])
byres = {d["resource"]: d for d in out.get("expired", [])}
fails = []

def get(res, field):
    d = byres.get(res)
    if d is None:
        return None
    return d.get(field)

# --- T-L1-01: last assistant line 3h old, last 3 lines are fresh inbound
# cross-session messages. Correct liveness = ~3h (NOT fresh, i.e. _holder_active
# must be False and age_s must be close to 10800, not close to 0).
age = get("t-l1-01", "_holder_transcript_age_s")
active = get("t-l1-01", "_holder_active")
method = get("t-l1-01", "_holder_liveness_method")
ok = age is not None and 10700 <= age <= 10900 and active is False
print(f"T-L1-01: age_s={age} active={active} method={method} -> {'PASS' if ok else 'FAIL'}")
if not ok: fails.append("T-L1-01")

# --- T-L1-02: last assistant line 1 min old -> fresh (_holder_active True),
# age_s close to 60.
age = get("t-l1-02", "_holder_transcript_age_s")
active = get("t-l1-02", "_holder_active")
method = get("t-l1-02", "_holder_liveness_method")
ok = age is not None and 40 <= age <= 180 and active is True
print(f"T-L1-02: age_s={age} active={active} method={method} -> {'PASS' if ok else 'FAIL'}")
if not ok: fails.append("T-L1-02")

# --- T-L1-03: empty transcript (no own-turn line) -> falls back to file mtime
# (age_s close to 300s) AND the fallback must be NAMED (method field present and
# equal to "mtime-fallback" -- the pre-fix code has no such field at all).
age = get("t-l1-03", "_holder_transcript_age_s")
method = get("t-l1-03", "_holder_liveness_method")
ok = age is not None and 250 <= age <= 400 and method == "mtime-fallback"
print(f"T-L1-03: age_s={age} method={method!r} -> {'PASS' if ok else 'FAIL'}")
if not ok: fails.append("T-L1-03")

if fails:
    print(f"RESULT: RED -- failing: {', '.join(fails)}")
    sys.exit(1)
else:
    print("RESULT: GREEN -- all 3 cases pass")
    sys.exit(0)
PYEOF
exit $?
