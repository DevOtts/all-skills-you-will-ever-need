---
name: launch-light
description: Lightweight productivity bootstrap for greenfield TypeScript projects — pnpm workspace with apps/api/ (NestJS) by default, BFF-ready so adding apps/web/ later requires zero restructuring. OpenRouter + LangSmith env slots, a colored start-services.sh launcher that hard-fails when a service doesn't come up, README, and .env.example. NO Docker, NO Postgres, NO infra. Generates a runnable scaffold in seconds without asking domain questions. Use when the user says "/launch-light", "init", "init setup", "bootstrap minimal", "spin up Nest", "give me a scratch Nest app". Hands off to /launch-scratch-project the moment Docker/Postgres/Redis/queues/multi-service enter the picture.
author: DevOtts
author_url: https://github.com/DevOtts
---

# launch-light

Fast, opinionated bootstrap for a greenfield TypeScript service. **Always BFF-ready**: scaffolds a pnpm workspace with `apps/api/` (NestJS) on day 1, so when someone later asks for a frontend it's just `apps/web/` dropped in next to it — no restructuring, no shared-tsconfig surprises, no "the API tsconfig swept the React code" failure modes.

**No Docker. No databases. No queues.** The moment the user needs any of those, hand off to `/launch-scratch-project`.

## Soft reminder (not a gate)

If this scaffold is for a graded exercise (interview, take-home, coaching session), spend a minute framing the problem out loud first — the scaffold is intentionally trivial so the graded thinking happens after, not during. But this skill will *not* refuse to run if you skip the framing — that's the user's call.

## When to use this skill vs `/launch-scratch-project`

| Use `launch-light` | Use `/launch-scratch-project` |
|---|---|
| NestJS API (and optionally a Next.js/Vite app later) | Need Postgres/Redis/MongoDB/RabbitMQ/MinIO/etc. |
| In-memory state or JSON-file DB | Need a docker-compose stack |
| Single-shot scaffold, no questionnaire | Want the multi-service questionnaire + plan-approval flow |
| `start-services.sh` for `pnpm dev` | `init.sh` for `docker compose up` + per-service docs |
| < 5 minutes of bootstrap | Multi-service spike or interview build |

If the user mentions any of: **Postgres, Redis, MongoDB, RabbitMQ, Kafka, MinIO, MailHog, ClickHouse, docker, queue, broker, persistence, multi-service** → STOP and say:

> "That needs `/launch-scratch-project` — it has the questionnaire for picking services and generates the docker-compose stack. `/launch-light` is no-infra by design."

Don't extend `launch-light` with Docker — that's the explicit boundary.

## Decoding the user's prompt

There's only one mode: pnpm workspace with `apps/api/`. Parse for these optional flags:

| User says | Effect |
|---|---|
| `/launch-light`, `init`, `init setup`, `bootstrap`, just NestJS | default workspace + apps/api |
| `with frontend`, `with web`, `BFF`, `+ web`, `+ Next` | ALSO scaffold `apps/web/` (Next.js 15) on the same pass |
| `--skip-llm` or `no openrouter` | drop OpenRouter env + helper |
| `--skip-langsmith` or `no tracing` | drop LangSmith env + package |

Don't ask a questionnaire. Generate, hand back. If the user later wants a frontend, `/iteration-impl` will drop `apps/web/` in alongside `apps/api/` — the workspace shape never has to change.

## What it generates

```
.
├── apps/
│   └── api/                       # NestJS — :3001 — the single-app default
│       ├── src/
│       │   ├── main.ts            # bootstrap, listens on :3001
│       │   ├── app.module.ts
│       │   ├── app.controller.ts  # GET /health → { ok: true }
│       │   ├── app.controller.spec.ts # seed failing test (intentional RED)
│       │   └── llm/
│       │       └── openrouter.ts  # configured OpenAI-SDK client → OpenRouter
│       ├── package.json           # "name": "api", nest start, vitest
│       ├── tsconfig.json          # scoped: include src/**/*.ts, exclude dist/node_modules
│       ├── vitest.config.ts
│       └── nest-cli.json
├── .env                           # symlinked into each app by start-services.sh
├── .env.example                   # OPENROUTER_*, LANGSMITH_*, PORT
├── .gitignore
├── package.json                   # workspace root (pnpm -r dev, no app deps here)
├── pnpm-workspace.yaml            # packages: ["apps/*"]
├── start-services.sh              # chmod +x — runs whatever apps it finds, hard-fails on unhealthy
└── README.md
```

If the user invoked with `+ web` / BFF, ALSO scaffold:

```
└── apps/
    └── web/                       # Next.js 15 App Router — :3000
        ├── app/page.tsx           # calls API via /api proxy
        ├── app/api/health/route.ts
        ├── next.config.ts         # rewrites /api/* → http://localhost:3001/*
        ├── package.json
        └── tsconfig.json          # scoped to its own dir, "jsx": "preserve"
```

The workspace shape is the load-bearing decision. Adding `apps/web/` later (manually or via `/iteration-impl`) requires no restructuring because each app already has its own `package.json` and `tsconfig.json` — they were never coupled.

In all cases:
- **Vitest** is the test runner (not Jest — faster, consistent across web + api)
- **One seed failing test** so TDD has a RED to start from
- **`start-services.sh`** is the canonical launcher; `pnpm -r --parallel dev` works too
- **`.runtime/`** holds process logs (gitignored)

## Phase 1 — Confirm and dispatch

Print a one-screen confirmation (no questionnaire):

```
## launch-light bootstrap

Layout:      pnpm workspace — apps/api/ [+ apps/web/ if requested]
LLM:         OpenRouter (env slot + apps/api/src/llm/openrouter.ts helper)  [or "skipped"]
Tracing:     LangSmith (env slot + langsmith package)                       [or "skipped"]
Runner:      start-services.sh (colored, port preflight, watchdog, hard-fails on API/Web not ready)
Tests:       Vitest with one seed failing test

Files I'll write:
  - package.json (workspace root), pnpm-workspace.yaml
  - apps/api/{package.json, tsconfig.json, vitest.config.ts, nest-cli.json}
  - apps/api/src/{main.ts, app.module.ts, app.controller.ts (+ spec)}
  - apps/api/src/llm/openrouter.ts (if LLM enabled)
  - apps/web/* (only if + web was requested)
  - .env.example, .gitignore
  - start-services.sh (chmod +x)
  - README.md

Proceed? (y/n)
```

If `y` → write everything in one pass. If `n` → ask what to change.

## Phase 2 — Generate

### 2.1 Workspace root

`pnpm-workspace.yaml`:
```yaml
packages:
  - "apps/*"
```

`package.json` (workspace root):
```json
{
  "name": "<project>",
  "private": true,
  "scripts": {
    "dev": "pnpm -r --parallel dev",
    "build": "pnpm -r build",
    "test": "pnpm -r test"
  },
  "devDependencies": {
    "typescript": "^5.6.0"
  }
}
```

### 2.2 `apps/api/package.json`

```json
{
  "name": "api",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "dev": "nest start --watch",
    "build": "nest build",
    "start": "node dist/main.js",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@nestjs/common": "^10.4.0",
    "@nestjs/core": "^10.4.0",
    "@nestjs/platform-express": "^10.4.0",
    "dotenv": "^16.4.0",
    "openai": "^4.70.0",
    "langsmith": "^0.2.0",
    "reflect-metadata": "^0.2.2",
    "rxjs": "^7.8.1"
  },
  "devDependencies": {
    "@nestjs/cli": "^10.4.0",
    "@nestjs/testing": "^10.4.0",
    "@types/node": "^22.0.0",
    "typescript": "^5.6.0",
    "vitest": "^2.1.0",
    "vite-tsconfig-paths": "^5.0.0"
  }
}
```

Drop `langsmith` if `--skip-langsmith`. Drop `openai` if `--skip-llm`.

### 2.3 `apps/api/tsconfig.json` — scoped from day 1

```json
{
  "compilerOptions": {
    "module": "commonjs",
    "declaration": true,
    "removeComments": true,
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true,
    "allowSyntheticDefaultImports": true,
    "target": "ES2021",
    "sourceMap": true,
    "outDir": "./dist",
    "baseUrl": "./",
    "incremental": true,
    "skipLibCheck": true,
    "strictNullChecks": true,
    "noImplicitAny": true,
    "strictBindCallApply": true,
    "forceConsistentCasingInFileNames": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*.ts", "scripts/**/*.ts"],
  "exclude": ["node_modules", "dist"]
}
```

**Why explicit `include`/`exclude`:** without them, `tsc --watch` (spawned by `nest start --watch`) sweeps the whole project tree. If a sibling folder ever appears (e.g. `apps/web/`, `evals/`, a scaffolded mockup) and the tsconfig is unscoped, tsc tries to compile its `.ts`/`.tsx` files, fails on JSX or React types, and **Nest never boots cleanly — the API silently dies and the only symptom is `Internal Server Error` from a frontend proxy.** Ship the tsconfig scoped from day 1; it costs nothing.

### 2.4 NestJS source files (`apps/api/src/`)

**`main.ts`**
```typescript
import 'dotenv/config'; // MUST be first — populates process.env before any module that reads env at load time (e.g. an OpenAI/LangSmith client constructed at module scope). nest start does NOT auto-load .env.
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const port = Number(process.env.PORT ?? 3001);
  await app.listen(port);
  console.log(`API listening on http://localhost:${port}`);
}

bootstrap();
```

**`app.module.ts`**
```typescript
import { Module } from '@nestjs/common';
import { AppController } from './app.controller';

@Module({
  controllers: [AppController],
})
export class AppModule {}
```

**`app.controller.ts`**
```typescript
import { Controller, Get } from '@nestjs/common';

@Controller()
export class AppController {
  @Get('health')
  health() {
    return { ok: true };
  }
}
```

**`app.controller.spec.ts`** (seed failing test — intentional RED)
```typescript
import { describe, it, expect } from 'vitest';
import { AppController } from './app.controller';

describe('AppController', () => {
  it('health returns ok=true', () => {
    const c = new AppController();
    expect(c.health()).toEqual({ ok: true });
  });

  it('TODO: replace this with the real first feature test', () => {
    expect.fail('Seed RED — delete or rewrite this test as your first real failing test.');
  });
});
```

The first test passes; the second is the deliberate RED that the TDD loop starts from.

### 2.5 OpenRouter helper (if LLM enabled)

**`apps/api/src/llm/openrouter.ts`**
```typescript
import OpenAI from 'openai';
import { wrapOpenAI } from 'langsmith/wrappers';

const apiKey = process.env.OPENROUTER_API_KEY;
if (!apiKey) {
  throw new Error('OPENROUTER_API_KEY is missing — see .env.example');
}

// `wrapOpenAI` emits LangSmith runs with token counts + cost estimates for every
// `chat.completions.create` call.
//
// Two enhancements you almost always want on top of the bare wrapper:
//
// 1. NAME EVERY CALL. By default each run shows up in LangSmith as "ChatOpenAI",
//    which is useless when one request fires 3+ LLM calls. Pass a descriptive
//    `name` via `langsmithExtra` on each call — see `lsExtra` helper below.
//
// 2. WRAP THE CALLER WITH `traceable` TO GET A WATERFALL. Without a parent span
//    every `chat.completions.create` is a top-level run — flat list, no chain
//    of thought. Wrapping the function that makes the calls creates a parent
//    span; nested wrapOpenAI calls auto-attach as children via AsyncLocalStorage.
//    See "LangSmith tracing waterfall" below for the pattern.
//
// COST CAVEAT: LangSmith computes cost from its built-in price table for the
// un-prefixed model id (e.g. `claude-sonnet-4-5`, not the OpenRouter slug
// `anthropic/claude-sonnet-4.5`). OpenRouter adds margin on top, so the "cost"
// number is directional, not your actual OpenRouter bill. Token counts are
// correct.
export const openrouter = wrapOpenAI(
  new OpenAI({
    apiKey,
    baseURL: 'https://openrouter.ai/api/v1',
    defaultHeaders: {
      'HTTP-Referer': process.env.OPENROUTER_SITE_URL ?? 'http://localhost:3001',
      'X-Title': process.env.OPENROUTER_APP_NAME ?? '<project>',
    },
  }),
);

export const DEFAULT_MODEL = process.env.OPENROUTER_MODEL ?? 'anthropic/claude-sonnet-4.5';

// LangSmith's pricing table keys on un-prefixed canonical model ids
// (e.g. `claude-sonnet-4-5`, not the OpenRouter slug `anthropic/claude-sonnet-4.5`).
export function toLangSmithModelName(openrouterModelId: string): string {
  return openrouterModelId.replace(/^[^/]+\//, '').replace(/\./g, '-');
}

/**
 * Convenience builder for the `langsmithExtra` arg of `chat.completions.create`.
 * Combines a descriptive run name (so LangSmith shows "orchestrator_step" or
 * "flag_judge" instead of the default "ChatOpenAI") with the model-name
 * override needed for cost tracking. Add metadata/tags via `extra` as needed.
 */
export function lsExtra(name: string, model: string = DEFAULT_MODEL, extra: Record<string, unknown> = {}) {
  return {
    name,
    metadata: {
      ls_model_name: toLangSmithModelName(model),
      ...extra,
    },
  };
}
```

#### Calling the LLM — name every call

When `openaiClient` is typed as the wrapped `typeof openrouter` (e.g. you imported `openrouter` directly), TypeScript knows about `langsmithExtra`:

```typescript
const resp = await openrouter.chat.completions.create(
  { model: DEFAULT_MODEL, messages: [...], temperature: 0 },
  { langsmithExtra: lsExtra('my_feature_step', DEFAULT_MODEL, { iteration: 0 }) },
);
```

When the client is passed in as `OpenAI` (raw type — e.g. a function takes the client as a parameter for testability), `langsmithExtra` isn't visible to TS but is consumed at runtime. Add `@ts-expect-error`:

```typescript
// @ts-expect-error langsmithExtra is a LangSmith-wrapper extension not in OpenAI's RequestOptions type.
const resp = await openaiClient.chat.completions.create(
  { model, messages: [...], temperature: 0 },
  { langsmithExtra: lsExtra('flag_judge', model) },
);
```

#### LangSmith tracing waterfall — wrap callers with `traceable`

A single request that fires 3 LLM calls without `traceable` shows up as 3 top-level runs in LangSmith's Runs list — no parent, no chain of thought visible. Wrapping the orchestrating function with `traceable` creates a parent span; the wrapped client's child calls auto-attach to it via AsyncLocalStorage.

```typescript
import { traceable } from 'langsmith/traceable';
import { openrouter, DEFAULT_MODEL, lsExtra } from '../llm/openrouter';

// Each chat.completions.create inside this function becomes a CHILD of the
// `orchestrate_claim` span, ordered as a waterfall by start time.
// Nested traceable functions become children of THIS function. Result:
//   orchestrate_claim                  (parent span)
//   ├── orchestrator_step (iter 0)     (child LLM call)
//   ├── orchestrator_step (iter 1)
//   │   └── flag_judge                 (LLM call inside a nested traceable)
//   └── orchestrator_step (iter 2)
export const orchestrateClaim = traceable(
  async (input: ClaimInput) => {
    for (let iteration = 0; iteration < MAX; iteration++) {
      const resp = await openrouter.chat.completions.create(
        { model: DEFAULT_MODEL, messages, tools, temperature: 0 },
        { langsmithExtra: lsExtra('orchestrator_step', DEFAULT_MODEL, { iteration }) },
      );
      // ... handle tool calls; may invoke other traceable functions like the policy decision
    }
  },
  { name: 'orchestrate_claim' },
);
```

**Trace a function whenever it (a) makes multiple LLM calls, (b) makes one LLM call but also dispatches non-LLM work worth seeing in the waterfall, or (c) is itself called by another traced function (so the nesting shows).** Tests don't need to mock `traceable` — when `LANGSMITH_TRACING` is unset it's a transparent no-op.

### 2.6 `apps/web/` (only if `+ web` was requested)

Standard Next.js 15 App Router + TypeScript scaffold. Key files:
- `apps/web/package.json` — `"name": "web"`, scripts: `dev` (`next dev -p 3000`), `build`, `start`, `test`.
- `apps/web/tsconfig.json` — Next's default + `"jsx": "preserve"`. Scoped to its own dir; never cross-contaminates with API.
- `apps/web/next.config.ts` — rewrites `/api/*` → `http://localhost:3001/*` so the browser never needs CORS.
- `apps/web/app/page.tsx` — minimal page that fetches `/api/health` and renders the result.
- `apps/web/app/api/health/route.ts` — Next-side health endpoint for the launcher to wait on.

The `/api` rewrite is the standard play. **Do not enable CORS on the Nest side** in v1 — the proxy makes it same-origin from the browser's perspective.

### 2.7 `.env.example` (workspace root)

```bash
# Server
PORT=3001

# OpenRouter — https://openrouter.ai/keys
OPENROUTER_API_KEY=CHANGE_ME
OPENROUTER_MODEL=anthropic/claude-sonnet-4.5
OPENROUTER_SITE_URL=http://localhost:3001
OPENROUTER_APP_NAME=<project>

# LangSmith — https://smith.langchain.com/settings
# JS SDK quirk: project name is read from LANGCHAIN_PROJECT (not LANGSMITH_PROJECT).
# Set both for forward-compat; without LANGCHAIN_PROJECT, traces land in "default".
LANGSMITH_TRACING=true
LANGSMITH_ENDPOINT=https://api.smith.langchain.com
LANGSMITH_API_KEY=CHANGE_ME
LANGSMITH_PROJECT=<project>
LANGCHAIN_PROJECT=<project>
```

Strip LLM/LangSmith blocks if their flags were passed. Always include `PORT`. The root `.env` is symlinked into each app by `start-services.sh` so each app's cwd sees it.

### 2.8 `.gitignore`

```
node_modules/
dist/
.next/
.env
.env.local
.runtime/
*.log
.DS_Store
```

### 2.9 `start-services.sh` (chmod +x) — loud-failing, apps-aware

Starts whatever apps it finds under `apps/`. **No silent `|| true`** after readiness checks — if a service doesn't come up cleanly in the timeout, the script exits non-zero with a red banner and the log tail. This is the difference between "the API is dead but the script said Up." (worst-of-both UX) and "the API is dead, here's why, fix it now."

```bash
#!/bin/bash
# <project> — start the apps for local dev.
#
# Usage:
#   ./start-services.sh
#
# Port map:
#   apps/api (Nest)   3001   pnpm --filter api dev
#   apps/web (Next)   3000   pnpm --filter web dev   (proxies /api → :3001)
#
# Logs:
#   tail -f .runtime/api.log
#   tail -f .runtime/web.log
#
# Stop: Ctrl+C

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; DIM='\033[2m'; NC='\033[0m'

echo -e "${BLUE}>> <project> — local dev${NC}"
echo "===================================="

if [ ! -f "package.json" ] || [ ! -d "apps" ]; then
  echo -e "${RED}Run this from the workspace root (the one with apps/).${NC}"; exit 1
fi

HAVE_API=0; [ -d "apps/api" ] && HAVE_API=1
HAVE_WEB=0; [ -d "apps/web" ] && HAVE_WEB=1

check_port() { lsof -Pi :"$1" -sTCP:LISTEN -t >/dev/null 2>&1; }

free_port_or_abort() {
  local port="$1" name="$2"
  if check_port "$port"; then
    echo -e "  ${RED}busy${NC} :$port ($name)"
    printf "${YELLOW}Kill it? [y/N] ${NC}"; read -r REPLY
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
      lsof -ti :"$port" | xargs kill -9 2>/dev/null || true; sleep 1
    else
      echo -e "${RED}Aborting.${NC}"; exit 1
    fi
  fi
}

wait_for_url() {
  local url="$1" name="$2" max="${3:-45}" i=0
  while [ "$i" -lt "$max" ]; do
    if curl -sf -o /dev/null -w '%{http_code}' "$url" 2>/dev/null | grep -qE '^(200|301|302|307|401|404)$'; then
      echo -e " ${GREEN}OK${NC} $name ready"; return 0
    fi
    printf "."; sleep 1; i=$((i + 1))
  done
  echo ""; return 1
}

cleanup() {
  echo ""
  echo -e "${YELLOW}Stopping...${NC}"
  [ -n "${WEB_PID:-}" ] && kill "$WEB_PID" 2>/dev/null || true
  [ -n "${API_PID:-}" ] && kill "$API_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p .runtime

echo -e "${BLUE}Checking ports...${NC}"
[ "$HAVE_API" = 1 ] && free_port_or_abort 3001 api
[ "$HAVE_WEB" = 1 ] && free_port_or_abort 3000 web

if [ ! -f ".env" ]; then
  if [ -f ".env.example" ]; then
    echo -e "${YELLOW}.env missing — copying from .env.example (edit the placeholders!)${NC}"
    cp .env.example .env
  else
    echo -e "${RED}.env missing and no .env.example to copy.${NC}"; exit 1
  fi
fi

# Symlink root .env into each app so dotenv (api) and Next.js (web) pick it up from their cwd.
[ "$HAVE_API" = 1 ] && [ ! -e apps/api/.env ] && (cd apps/api && ln -s ../../.env .env)
[ "$HAVE_WEB" = 1 ] && [ ! -e apps/web/.env.local ] && (cd apps/web && ln -s ../../.env .env.local)

if [ ! -d "node_modules" ]; then
  echo -e "${BLUE}Installing deps...${NC}"
  pnpm install 2>/dev/null || npm install
fi

if [ "$HAVE_API" = 1 ]; then
  echo ""
  echo -e "${BLUE}Starting API (:3001)...${NC}"
  pnpm --filter api dev >.runtime/api.log 2>&1 &
  API_PID=$!
  echo -e "  ${GREEN}started${NC} (PID $API_PID)"
  echo -n "  "
  if ! wait_for_url "http://localhost:3001/health" "API" 30; then
    echo -e "${RED}!! API never became ready. Last 20 lines of .runtime/api.log:${NC}"
    tail -20 .runtime/api.log
    exit 1
  fi
fi

if [ "$HAVE_WEB" = 1 ]; then
  echo -e "${BLUE}Starting Web (:3000)...${NC}"
  pnpm --filter web dev >.runtime/web.log 2>&1 &
  WEB_PID=$!
  echo -e "  ${GREEN}started${NC} (PID $WEB_PID)"
  echo -n "  "
  if ! wait_for_url "http://localhost:3000" "Web" 30; then
    echo -e "${RED}!! Web never became ready. Last 20 lines of .runtime/web.log:${NC}"
    tail -20 .runtime/web.log
    exit 1
  fi
fi

echo ""
echo -e "${GREEN}Up.${NC}"
[ "$HAVE_WEB" = 1 ] && echo "  • Web:     http://localhost:3000"
[ "$HAVE_API" = 1 ] && echo "  • API:     http://localhost:3001/health"
echo "  • Logs:    tail -f .runtime/*.log"
echo "  • Stop:    Ctrl+C"
echo ""

while true; do
  if [ "$HAVE_API" = 1 ] && ! kill -0 "$API_PID" 2>/dev/null; then
    echo -e "${RED}API died — tail .runtime/api.log${NC}"
    tail -20 .runtime/api.log
    break
  fi
  if [ "$HAVE_WEB" = 1 ] && [ -n "${WEB_PID:-}" ] && ! kill -0 "$WEB_PID" 2>/dev/null; then
    echo -e "${RED}Web died — tail .runtime/web.log${NC}"
    tail -20 .runtime/web.log
    break
  fi
  sleep 5
done
```

The script is **future-proof for adding `apps/web/` later** without changes — it auto-detects what's present. `/iteration-impl` can drop in a frontend and the launcher just picks it up.

### 2.10 `README.md`

```markdown
# <project>

Lightweight TypeScript service bootstrapped with `/launch-light`. NestJS in `apps/api/`, optional Next.js frontend in `apps/web/`, no Docker. OpenRouter for LLM calls, LangSmith for tracing.

## Quick start

1. Copy env: `cp .env.example .env` (or let `start-services.sh` do it on first run)
2. Fill in `OPENROUTER_API_KEY` (get one at https://openrouter.ai/keys)
3. Fill in `LANGSMITH_API_KEY` (get one at https://smith.langchain.com/settings) — or set `LANGSMITH_TRACING=false` to skip
4. `pnpm install` (first run only)
5. `./start-services.sh`

## Layout

```
apps/
├── api/        NestJS — :3001 — the always-present API
└── web/        Next.js 15 — :3000 — added on `+ web` invocation or later via /iteration-impl
```

## Endpoints

| Method | Path     | App | Returns         |
|--------|----------|-----|-----------------|
| GET    | /health  | api | `{ ok: true }`  |

## Environment variables

| Var | Required | Purpose |
|---|---|---|
| `PORT` | no (3001) | API port |
| `OPENROUTER_API_KEY` | yes | OpenRouter — https://openrouter.ai/keys |
| `OPENROUTER_MODEL` | no | Defaults to `anthropic/claude-sonnet-4.5` |
| `OPENROUTER_SITE_URL` | no | Sent as `HTTP-Referer` to OpenRouter |
| `OPENROUTER_APP_NAME` | no | Sent as `X-Title` to OpenRouter |
| `LANGSMITH_TRACING` | no | `true` to enable tracing |
| `LANGSMITH_API_KEY` | if tracing | https://smith.langchain.com/settings |
| `LANGSMITH_PROJECT` | no | Project name (forward-compat; current JS SDK ignores it for trace routing) |
| `LANGCHAIN_PROJECT` | no | Project name actually read by the langsmith JS SDK at trace time. Without this, traces land in `default`. |

## Scripts

| Command | What |
|---|---|
| `pnpm -r --parallel dev` | All apps in watch mode (Nest watch + Next dev) |
| `pnpm --filter api dev` | API only |
| `pnpm --filter web dev` | Web only |
| `pnpm -r test` | All vitest suites |
| `pnpm -r build` | Compile everything |
| `./start-services.sh` | Runner with port preflight, watchdog, hard-fails if a service doesn't come up, logs in `.runtime/` |

## TDD

`apps/api/src/app.controller.spec.ts` has a deliberate failing test as the TDD seed (RED). Delete or rewrite it as your first real failing test, then GREEN → REFACTOR.

## Not included (by design)

No Docker, no Postgres, no Redis, no queue, no auth. If you need any of those, re-bootstrap with `/launch-scratch-project` — it has the docker-compose questionnaire.
```

## Phase 3 — Hand off

After files land:

```
## Bootstrap done

Layout:   pnpm workspace — apps/api/ [+ apps/web/ if requested]
LLM:      [OpenRouter wired in apps/api/src/llm/openrouter.ts | skipped]
Tracing:  [LangSmith env slot present | skipped]

Next:
  1. Fill .env with real keys (OPENROUTER_API_KEY at minimum)
  2. ./start-services.sh
  3. Hit http://localhost:3001/health [and http://localhost:3000 if web/]
  4. Open apps/api/src/app.controller.spec.ts — the second test is your seed RED
  5. Ready to build the domain? Invoke `/iteration-impl <problem statement>`
     — plans + locks ambiguities + fans the build across parallel subagents,
     with a simplicity governor that aggressively cuts ceremony.
  6. Want to add a frontend later? `/iteration-impl nextjs frontend from <mockup path>`
     — drops apps/web/ in next to apps/api/, no restructuring.

Need persistence/queues/Docker? Re-bootstrap with /launch-scratch-project.
```

## Anti-patterns

- **Don't ask a questionnaire.** The mode is fixed (workspace + apps/api). Parse the `+ web` / flags from the prompt.
- **Don't add Docker / databases.** That's the explicit boundary — hand off to `/launch-scratch-project` instead.
- **Don't pick Jest.** Vitest is the convention here (faster, consistent across web + api).
- **Don't generate controllers/services/modules layers for a 4-endpoint exercise.** Inline in `app.controller.ts` is fine — layering is for when the shape demands it.
- **Don't commit real keys to `.env.example`.** Placeholders only (`CHANGE_ME`).
- **Don't skip the seed failing test.** TDD needs a RED to start from; one is included on purpose.
- **Don't omit `dotenv/config`.** `nest start` does NOT auto-load `.env` — without an explicit `import 'dotenv/config'` as the first line of `main.ts`, env-dependent code (LLM clients, LangSmith tracing) silently fails with empty `process.env`. Confusing because `.env` exists and looks right.
- **Don't ship the tsconfig without `include` and `exclude`.** An unscoped tsconfig sweeps the whole tree; the moment a sibling folder appears (apps/web, evals, mockup-frontend), tsc/nest fails on JSX or React types and the API silently never boots. Each app's tsconfig must be scoped to its own dir.
- **Don't put `|| true` after `wait_for_url` in `start-services.sh`.** A failed readiness check must surface — "Up." printed while the API is actually dead is the worst-of-both UX. Hard exit with the log tail.
- **Don't enable CORS on the Nest side** when adding a frontend. The Next/Vite proxy makes the browser see same-origin; CORS is for cross-domain prod deploys, not local dev.
- **Don't collapse the workspace back to a single package** "to save a directory level." The workspace layout is what makes BFF additions trivial and what prevents tsconfig sweep bugs. The cost (one extra dir) is paid once; the benefit recurs every iteration.
- **Don't bind-mount or use named volumes** — there's no Docker here. If you reach for one, you're in the wrong skill.
- **Don't fire multiple `chat.completions.create` calls per request without naming them and without wrapping the caller in `traceable`.** With `wrapOpenAI` alone, LangSmith shows every call as a top-level run named "ChatOpenAI" — flat list, no chain of thought. A request that orchestrates 3+ tool calls becomes a confusing pile of sibling entries. Use `lsExtra(name, model)` on every call AND wrap the orchestrating function with `traceable({ name: '...' })` so the nested calls render as a waterfall. See section 2.5 for the full pattern. This costs nothing when `LANGSMITH_TRACING` is off (no-op) and changes a useless trace view into a debugging tool.

## Hand-off triggers (explicit)

If at any point the user says any of the following, STOP and recommend `/launch-scratch-project`:

- "add Postgres" / "I need a database"
- "add Redis" / "I need a cache"
- "add a queue" / RabbitMQ / Kafka
- "add docker" / "containerize"
- "with auth" / "with a real DB"
- "make this production-ready"

Say:

> "That's outside `/launch-light`'s scope — it's deliberately no-infra. `/launch-scratch-project` has the questionnaire for picking services and generates the docker-compose stack. Want me to switch?"

Then back out without writing.

---

_Authored by [DevOtts](https://github.com/DevOtts)._
