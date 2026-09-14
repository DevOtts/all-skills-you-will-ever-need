#!/bin/bash
# deploy-router install-hook.sh — wires deploy-router-guard.mjs as a PreToolUse hook into
# every Claude subscription's settings.json on this machine. APPEND-ONLY and idempotent:
# existing hook entries (e.g. `rtk hook claude`) are preserved untouched; re-running is a
# no-op. Backs up each file to settings.json.bak-<UTCts> before the first edit.
#
# Usage: install-hook.sh [--check]     --check = report status per config dir, edit nothing.
# Note: ~/.claude-anm and ~/.claude-loudr settings.json are SYMLINKS to ~/.claude's — the
# installer follows realpath and edits each REAL file exactly once.

exec python3 - "$@" <<'PY'
import json, os, sys, time

check = "--check" in sys.argv
GUARD = os.path.expanduser("~/.claude/skills/deploy-router/scripts/deploy-router-guard.mjs")
ENTRY = {"matcher": "Bash", "hooks": [{"type": "command", "command": f"node {GUARD}"}]}
dirs = ["~/.claude", "~/.claude-8ftools", "~/.claude-8fai", "~/.claude-anm", "~/.claude-loudr"]
if os.environ.get("CLAUDE_CONFIG_DIR"): dirs.append(os.environ["CLAUDE_CONFIG_DIR"])

seen, results = set(), []
for d in dirs:
    p = os.path.join(os.path.expanduser(d), "settings.json")
    if not os.path.exists(p):
        results.append((d, "no settings.json — skipped")); continue
    real = os.path.realpath(p)
    if real in seen:
        results.append((d, f"symlink to already-handled file — covered")); continue
    seen.add(real)
    try:
        cfg = json.load(open(real))
    except Exception as e:
        results.append((d, f"UNREADABLE ({e}) — skipped, fix manually")); continue
    pre = cfg.setdefault("hooks", {}).setdefault("PreToolUse", [])
    installed = any(GUARD in h.get("command", "")
                    for e in pre if isinstance(e, dict)
                    for h in e.get("hooks", []) if isinstance(h, dict))
    if installed:
        results.append((d, "already installed")); continue
    if check:
        results.append((d, "NOT installed")); continue
    bak = real + ".bak-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    import shutil; shutil.copy2(real, bak)
    pre.append(ENTRY)
    with open(real, "w") as f: json.dump(cfg, f, indent=2); f.write("\n")
    results.append((d, f"INSTALLED (backup: {os.path.basename(bak)})"))

for d, r in results: print(f"{d}: {r}")
sys.exit(0)
PY
