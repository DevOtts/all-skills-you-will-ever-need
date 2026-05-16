---
name: cicd-deploy-builder
description: "Generates a complete, project-specific CI/CD deploy skill. Discovers services by reading the repo (package.json, railway.toml, vercel.json, Dockerfile, fly.toml, .env.example), interviews the user for anything it can't infer, then produces two files: a cicd.yaml config (the editable source of truth) and a .deploy-credentials template. The generated config is immediately consumed by /cicd-deploy \u2014 no manual editing required to do the first deploy. Trigger when the user says \"generate a deploy skill\", \"set up cicd for this project\", \"create a deploy pipeline\", or \"/cicd-deploy-builder\"."
---

# /cicd-deploy-builder

You are the CI/CD skill generator. Your job is to interview a project once, then produce two files that make every future deploy fully automated via `/cicd-deploy`.

**Output:**
1. `<repo-root>/cicd.yaml` — the deploy config, editable source of truth
2. `<repo-root>/.deploy-credentials` — secrets file (never committed)
3. Add `.deploy-credentials` to `.gitignore` if not already there


## How to start

Ask the user ONE question to get oriented:

> "What's the path to the project repo? (e.g. ~/Workspace/myproject)"

Everything else you discover automatically or ask in the interview.


## PHASE 1 — DISCOVERY

Read the repo. Spawn an Explore subagent for this — hand it the repo path and ask it to return a structured summary. Do not read every file yourself.

### What to look for

**Platforms in use** — check for these files:
| File | Implies |
|------|---------|
| `vercel.json` or `.vercel/` | Vercel deployment |
| `railway.toml` | Railway deployment |
| `fly.toml` | Fly.io deployment |
| `Dockerfile` | Container-based (Railway, Fly, GCP, etc.) |
| `serverless.yml` / `serverless.ts` | AWS Lambda / Serverless Framework |
| `amplify.yml` | AWS Amplify |
| `.github/workflows/*.yml` | GitHub Actions (check what it deploys to) |
| `netlify.toml` | Netlify |

**Services** — for each platform found:
- Vercel: read `vercel.json` for project name; list `apps/*/` in monorepos
- Railway: read `railway.toml` → `[deploy].startCommand`, `healthcheckPath`; also check `nixpacks.toml`
- Fly.io: read `fly.toml` → `app`, `[http_service]`

**Auth systems** — check for:
- Supabase: `.env*` files contain `SUPABASE_URL` / `SUPABASE_PROJECT_REF`
- Firebase: `firebase.json` or `FIREBASE_*` env vars
- Auth0, Clerk, etc.

**Monorepo signals**:
- `pnpm-workspace.yaml` / `turbo.json` → monorepo, look in `apps/`
- Single `package.json` at root → single app

**Health endpoints** — scan for:
```
/health  /healthz  /api/health  /api/v1/health  /__health  /ping
```
Look in route files, `main.ts`, `app.py`, `server.js`.

**Test credentials** — look in `.env.example`, `.env.test`, `README.md` for sample email/password pairs.

**Existing credentials files** — if `.deploy-credentials` already exists, load it and skip those questions.

### Explore subagent prompt template
```
Explore the project at <repo_path>. I need a structured summary for CI/CD setup.

Return JSON with this shape:
{
  "repo_path": "...",
  "monorepo": true/false,
  "branch": "main or master",
  "platforms": ["vercel", "railway", ...],
  "services": [
    {
      "name": "web",
      "platform": "vercel",
      "config_file": "vercel.json",
      "project_name": "...",
      "url_hint": "...",
      "healthcheck_path": null
    },
    {
      "name": "engine",
      "platform": "railway",
      "config_file": "apps/engine/railway.toml",
      "start_command": "node dist/main.js",
      "healthcheck_path": "/health",
      "is_cron": false
    }
  ],
  "auth_system": "supabase | firebase | none",
  "supabase_project_ref": "...",
  "supabase_url": "...",
  "test_email_hint": "...",
  "test_password_hint": "...",
  "env_var_hints": {
    "VERCEL_TOKEN": "found in .env? yes/no",
    "RAILWAY_TOKEN": "...",
    "SUPABASE_SERVICE_ROLE_KEY": "..."
  }
}

Read: vercel.json, railway.toml, fly.toml, nixpacks.toml, package.json, 
any .env.example, .env.test, apps/*/railway.toml, apps/*/vercel.json.
Do not read node_modules or .git.
```


## PHASE 2 — INTERVIEW

After discovery, you know most things. Ask only what you couldn't infer.

Work through this checklist. Skip any item you already have from discovery.

### Always ask

**Q1 — Project name**
> "What should this deploy skill be called? (e.g. `myproject-cicd-deploy`)"

**Q2 — Production URLs** (for services where you couldn't infer the URL)
> "What's the production URL for `<service_name>`? (e.g. https://myapp.vercel.app)"

### Ask only if not found in discovery

**Q3 — Vercel token** (if Vercel detected and not in credentials file)
> "Vercel token? Find it at: `cat ~/Library/Application\ Support/com.vercel.cli/auth.json`"

**Q4 — Vercel team/org** (if Vercel detected)
> "Vercel team slug or ID? Run `vercel teams list` to find it. Leave blank if personal account."

**Q5 — Vercel project IDs** (for each Vercel service)
> "Vercel project ID for `<service>`? Run: `cat <repo>/<app>/.vercel/project.json`"

**Q6 — Railway project name** (if Railway detected)
> "Railway project name? Run `railway project list` to find it."

**Q7 — Supabase project ref** (if Supabase detected and not found)
> "Supabase project ref? Run `supabase projects list` to find it."

**Q8 — Test credentials** (if auth system detected and not found in .env.test)
> "Test account email + password for smoke tests? (A real account that exists in production)"

**Q9 — Cron services**
> "Any services that run as cron jobs (exit 0 after finishing)? These show as STOPPED in Railway — that's healthy, not a failure."

**Q10 — Custom smoke tests**
> "Any critical flows to test after deploy? (e.g. 'login', 'create an order', 'search for X'). I'll generate curl tests for them."

### Batch the questions
Don't ask one at a time. Group unanswered questions into a single message:

> "Discovery found: Vercel (web, admin), Railway (engine, backend, scraper). A few things I need:
> 1. Skill name?
> 2. Production URLs for web and admin?
> 3. Vercel token (from auth.json)?
> 4. Vercel team ID?
> 5. Test email + password?"


## PHASE 3 — GENERATE `cicd.yaml`

Write `<repo-root>/cicd.yaml`. This is the live config `/cicd-deploy` reads at runtime.

### Schema

```yaml
# cicd.yaml — generated by /cicd-deploy-builder
# Edit freely. /cicd-deploy reads this file on every run.
# DO NOT store secrets here — put them in .deploy-credentials

skill_name: <project>-cicd-deploy   # used to name the generated skill
project: <project-name>
repo: <absolute-path-to-monorepo-or-repo-root>
credentials: <absolute-path-to-.deploy-credentials>
branch: main                          # branch that triggers production deploy

# ── Services ─────────────────────────────────────────────────────────────────
services:

  # Vercel service
  - name: web
    platform: vercel                  # vercel | railway | fly | custom
    project_id: prj_xxx               # Vercel project ID
    url: https://myapp.vercel.app
    healthy_when: readyState == "READY"
    # Optional: team_id override (defaults to VERCEL_TEAM_ID from credentials)

  # Railway long-running service
  - name: engine
    platform: railway
    service: my-engine                # Railway service name
    url: https://my-engine-production.up.railway.app
    healthcheck: /health              # GET this path after deploy
    healthy_when: status == "SUCCESS"

  # Railway cron job (exits after running — STOPPED is healthy)
  - name: scraper
    platform: railway
    service: my-scraper
    is_cron: true                     # STOPPED = healthy, no healthcheck ping
    healthy_when: status == "STOPPED"

  # Fly.io service
  - name: worker
    platform: fly
    app: my-worker-app
    url: https://my-worker-app.fly.dev
    healthcheck: /health
    healthy_when: status == "running"

  # Custom / any HTTP service
  - name: lambda
    platform: custom
    url: https://api.myapp.com
    healthcheck: /health
    deploy_command: "serverless deploy --stage prod"
    healthy_when: http_status == 200

# ── Auth (for getting JWT in smoke tests) ────────────────────────────────────
auth:
  type: supabase                      # supabase | firebase | none
  # Values come from .deploy-credentials at runtime
  # supabase: uses SUPABASE_URL, SUPABASE_ANON_KEY, TEST_EMAIL, TEST_PASSWORD
  # firebase: uses FIREBASE_API_KEY, TEST_EMAIL, TEST_PASSWORD
  # none: smoke tests run without auth

# ── Smoke Tests ───────────────────────────────────────────────────────────────
smoke_tests:

  - name: Engine health
    method: GET
    url: "{{services.engine.url}}/health"
    expect_status: 200
    expect_body_contains: '"status":"ok"'

  - name: List items
    method: GET
    url: "{{services.engine.url}}/api/v1/items"
    auth: bearer_jwt                  # bearer_jwt | none | api_key
    expect_status: 200

  - name: Create item (critical path)
    method: POST
    url: "{{services.engine.url}}/api/v1/items"
    auth: bearer_jwt
    body: '{"name":"test-item"}'
    expect_status: 201
    expect_no_field: error            # fail if response has "error" key

  - name: Frontend loads
    method: GET
    url: "{{services.web.url}}"
    expect_status: 200

# ── Known failure modes (project-specific gotchas) ───────────────────────────
known_issues:
  - symptom: "Railway FAILED on build"
    check: "railway logs --build <id>"
    likely_cause: "Security CVE in dependencies"
    fix: "Upgrade the flagged package, regenerate lockfile"

  - symptom: "Vercel build ERROR with Zod validation"
    likely_cause: "Trailing \\n in env var value"
    fix: "vercel env rm KEY prod && printf 'value' | vercel env add KEY production"
```

### Template rules
- `{{services.X.url}}` — resolved at runtime from the services list
- `{{TEST_ACCOUNT_ID}}` — resolved from `.deploy-credentials`
- `{{SUPABASE_URL}}` etc. — all UPPER_SNAKE env vars resolved from credentials file


## PHASE 4 — GENERATE `.deploy-credentials`

Write `<repo-root>/.deploy-credentials`. Only include sections relevant to the platforms detected.

```bash
# .deploy-credentials — <project-name>
# Used exclusively by /cicd-deploy. DO NOT COMMIT.

# ── Vercel (if detected) ──────────────────────────────────────────────────────
VERCEL_TOKEN=<from user>
VERCEL_TEAM_ID=<from user or blank>

# ── Railway (if detected) ─────────────────────────────────────────────────────
# Railway CLI token auto-read from ~/.railway/config.json
# No token needed here — the CLI handles auth

# ── Fly.io (if detected) ──────────────────────────────────────────────────────
FLY_API_TOKEN=<from user>

# ── Supabase (if detected) ────────────────────────────────────────────────────
SUPABASE_PROJECT_REF=<ref>
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<from user>
SUPABASE_ANON_KEY=<from user>

# ── Test credentials ──────────────────────────────────────────────────────────
TEST_EMAIL=<from user>
TEST_PASSWORD=<from user>
TEST_ACCOUNT_ID=<from user or leave blank>

# ── Production URLs ───────────────────────────────────────────────────────────
# (mirrored from cicd.yaml for convenience in smoke test scripts)
<for each service>
<SERVICE_NAME_URL>=<url>
```


## PHASE 5 — GITIGNORE

Ensure `.deploy-credentials` is ignored. Check both the repo root and any sub-repo `.gitignore`.

```bash
# Check
grep -r "\.deploy-credentials" <repo>/.gitignore <repo>/*/.gitignore 2>/dev/null

# Add if missing
echo ".deploy-credentials" >> <repo>/.gitignore
```


## PHASE 6 — GENERATE THE PROJECT SKILL

Write `~/.claude/skills/<skill_name>/SKILL.md` — a thin wrapper that calls `/cicd-deploy` with the project's config path.

```markdown
name: <skill_name>
description: CI/CD deploy pipeline for <project>. Runs preflight, pushes to <branch>, deploys to <platforms>, monitors all services, and optionally runs smoke tests. Generated by /cicd-deploy-builder. Trigger: "deploy <project>", "ship it", "push to prod", "/cicd-deploy-builder".

# /<skill_name>

This is a generated CI/CD skill for **<project>**.
Config: `<repo-root>/cicd.yaml`
Credentials: `<repo-root>/.deploy-credentials`

Run the full pipeline by invoking the generic `/cicd-deploy` skill with this project's config:

**Config path:** `<repo-root>/cicd.yaml`

Invoke `/cicd-deploy` now, passing it the config path above.
All phases (preflight, push, deploy, monitor, QA, report) are defined in that skill.
```

This keeps the project skill tiny — all the logic lives in `/cicd-deploy`.


## PHASE 7 — VALIDATION RUN

After generating both files, immediately run Phase 0 (preflight) of `/cicd-deploy` to confirm everything works before the user needs to deploy for real.

```
Running preflight validation to confirm the generated config works...
```

If preflight fails → diagnose which credential or URL is wrong, fix the `.deploy-credentials` or `cicd.yaml`, re-run.


## Final output to user

```
## Generated CI/CD skill for <project>

### Files created
- `<repo>/cicd.yaml` — deploy config (edit freely)
- `<repo>/.deploy-credentials` — secrets (never committed)
- `~/.claude/skills/<skill_name>/SKILL.md` — your new deploy skill

### Services configured
| Service | Platform | URL | Healthy when |
|---------|----------|-----|--------------|
| web     | Vercel   | https://... | READY |
| engine  | Railway  | https://... | SUCCESS |

### Smoke tests configured
- T1: Engine health
- T2: ...

### How to deploy
Just say: "deploy <project>" or run `/<skill_name>`

### Preflight result
✓ All credentials verified
✓ All services reachable
✓ Ready to deploy
```


## Rules for the generator

- **Never store secrets in `cicd.yaml`** — that file can be committed. Secrets go only in `.deploy-credentials`.
- **Never ask for a secret that can be read from a file** — read `~/.railway/config.json`, `~/Library/Application Support/com.vercel.cli/auth.json`, `.env.test` before asking the user.
- **Batch all interview questions into one message** — don't ping-pong.
- **If you can't infer something and it's not critical, leave it blank with a comment** — the user can fill it in later. Don't block on optional fields.
- **The generated project skill is intentionally thin** — it just points to `cicd.yaml`. All logic lives in `/cicd-deploy`. This way, fixing `/cicd-deploy` improves every project at once.
