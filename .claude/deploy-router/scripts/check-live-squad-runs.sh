#!/bin/bash
# deploy-router check-live-squad-runs.sh — pre-deploy check for the
# deploy-router-blind-to-live-squad-runs gap (backlog drain 2026-08-24,
# discovery-g6 #17): a brain-api-core/brain-agent deploy mid-squad-run silently
# orphans the run forever (status stays "running", $0 spend, no error — measured
# live 2026-08-26, run 2026-08-26-0336-e4nqu1, org alimento-diario). Nothing in
# the router's existing D2 table classifies THIS resource — a live squad run has
# no Claude Code session, no lock file, no git activity to detect.
#
# READ-ONLY, SSH EXCEPTION: unlike detect.sh (never SSHes), this script DOES
# SSH to the tenants box — mirrors the existing "+F freshness check" in
# SKILL.md Phase 3, which already reads box state over SSH before an apply.
# It queries ONLY (`db.pipeline_runs.countDocuments`/`.find` with a `.project`
# — never a mutating call, never `updateOne`/`deleteOne`).
#
# Usage:
#   check-live-squad-runs.sh <tenant-slug> [<tenant-slug> ...]
#
# Output: one JSON object per tenant on stdout (newline-delimited), plus a
# final summary line. Exit code: 0 if EVERY tenant is clear (0 running runs),
# 1 if ANY tenant has ≥1 running run (the router's block signal — Phase 3
# treats a non-zero exit the same as a blocking lock: negotiate/hold before
# deploying brain-api-core or brain-agent to that tenant).
#
# Bind before believing it: proven able to fail by seeding one fake
# `status:"running"` pipeline_runs row on a scratch tenant and confirming
# this script exits 1 and names it — never trust a check that has only ever
# returned 0.

set -euo pipefail

VPS="${DEPLOY_ROUTER_TENANTS_VPS:-167.86.98.85}"
if [ "$#" -eq 0 ]; then
  echo '{"error":"usage: check-live-squad-runs.sh <tenant-slug> [<tenant-slug> ...]"}' >&2
  exit 2
fi

OVERALL_EXIT=0

for TENANT in "$@"; do
  NS="processor-${TENANT}"
  POD=$(ssh -o ConnectTimeout=10 "root@${VPS}" \
    "kubectl -n ${NS} get pod -l app=brain-api-core -o jsonpath='{.items[0].metadata.name}'" 2>/dev/null || true)

  if [ -z "$POD" ]; then
    python3 -c "import json,sys; print(json.dumps({'tenant': sys.argv[1], 'ok': False, 'error': 'no brain-api-core pod found in ' + sys.argv[2]}))" "$TENANT" "$NS"
    OVERALL_EXIT=1
    continue
  fi

  RESULT=$(ssh -o ConnectTimeout=10 "root@${VPS}" \
    "kubectl -n ${NS} exec ${POD} -- node -e \"
      const { MongoClient } = require('mongodb');
      (async () => {
        const client = new MongoClient(process.env.MONGODB_URI);
        await client.connect();
        const db = client.db(process.env.MONGODB_DB);
        const col = db.collection('pipeline_runs');
        const count = await col.countDocuments({ status: 'running' });
        const sample = await col.find({ status: 'running' })
          .project({ _id: 1, squad_id: 1, org_slug: 1, current_step: 1, started_at: 1 })
          .limit(5).toArray();
        console.log(JSON.stringify({ count, sample }));
        await client.close();
      })().catch(e => { console.log(JSON.stringify({ error: e.message })); process.exit(1); });
    \"" 2>/dev/null || echo '{"error":"exec failed"}')

  python3 -c "
import json, sys
tenant, ns, raw = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    parsed = json.loads(raw)
except Exception as e:
    print(json.dumps({'tenant': tenant, 'namespace': ns, 'ok': False, 'error': f'unparseable result: {e}', 'raw': raw[:500]}))
    sys.exit(1)
if 'error' in parsed:
    print(json.dumps({'tenant': tenant, 'namespace': ns, 'ok': False, 'error': parsed['error']}))
    sys.exit(1)
count = parsed.get('count', 0)
verdict = 'clear' if count == 0 else 'LIVE-SQUAD-RUN'
print(json.dumps({'tenant': tenant, 'namespace': ns, 'ok': True, 'verdict': verdict, 'running_count': count, 'sample': parsed.get('sample', [])}))
sys.exit(0 if count == 0 else 1)
" "$TENANT" "$NS" "$RESULT" || OVERALL_EXIT=1
done

exit $OVERALL_EXIT
