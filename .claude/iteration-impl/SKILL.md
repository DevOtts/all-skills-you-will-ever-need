---
name: iteration-impl
description: >
  Implement an iteration on top of a /launch-light scaffold (or any minimal NestJS / Next.js project).
  Two modes auto-detected: API iteration (domain layer on Nest) and FRONTEND iteration (Next.js/Vite UI
  built from HTML/Figma/image mockups, consuming an existing API). Reads the problem statement, locks
  2-4 ambiguities, runs a simplicity governor that aggressively cuts ceremony, AUTHORS RED tests on the
  load-bearing logic IN THE MAIN THREAD (not the agents — provenance matters), then fans the implementation
  build across 3-4 parallel subagents in one message. The RED tests are the verdict; agent "done" claims
  are not. Iteration-aware: detects existing state and runs deltas on v2+. Use when the user says
  "/iteration-impl", "build the iteration", "implement v1 / v2 / v3 of <feature>", "add the domain",
  "build the nextjs frontend", "implement the UI from <mockup>", or hands you a problem statement after
  /launch-light. Defaults skewed toward NO ceremony. Common typos handled: "/implement-impl", "/impl",
  "/iter-impl".
author: DevOtts
author_url: https://github.com/DevOtts
---

# iteration-impl

Build the next iteration on top of a freshly-scaffolded (or in-progress) project. **Speed matters.** This skill exists because a 1-hour interview / take-home / spike doesn't get to spend 30 minutes on DI plumbing, validation pipes, state-management ceremony, or LangSmith wiring. It builds the thing that matters and narrates the scope cuts.

**TDD-first is structural, not optional.** When load-bearing logic exists in the iteration, the RED tests are authored in the main thread *before* agents are dispatched. The agents implement against tests they did not write, and the test result — not the agent's "done" claim — is the verdict at hand-off. This is what makes delegated agentic work safe at speed: the test is the evidence, the agent's confidence is the claim, and the structure is arranged so the evidence wins.

Two modes, auto-detected:

- **API mode** — domain entities, endpoints, business logic on NestJS. The original use case.
- **Frontend mode** — Next.js/Vite UI built from HTML/Figma/image mockups that consumes the existing API. Activated when the user says "frontend", "UI", "nextjs", or references a mockup folder.

It also knows iterations stack — v1 today, v2 tomorrow, v3 when something breaks. Phase 0 detects state and runs deltas instead of rewrites when called repeatedly.

## When to use vs not to use

| Use this | Don't |
|---|---|
| Build a domain iteration (entities + CRUD + the real business logic) on a Nest scaffold | Initial scaffold — use `/launch-light` first |
| Build a frontend iteration (pages + components + API client) from a mockup | Pure Figma-to-design-system (use `/design` or `/ui-styling`) |
| 1-hour interview / take-home / weekend spike | Production code with real validation + auth + persistence |
| Clear scope, one iteration at a time | Big multi-feature delivery (use `/launch` with features tracker) |
| Problem statement given as natural-language prose | Pure refactor of existing code (use Agent directly) |

If the user wants Docker, Postgres, Redis, queues, real persistence → STOP and recommend `/launch-scratch-project` first. This skill assumes the JSON-file DB pattern (API mode) or Vite/Next proxy (frontend mode) is enough.

## Composition

```
/launch-light            → /iteration-impl v1 (api)    → /iteration-impl v2 (frontend from mockup)    → ...
   bootstrap (60s)         API domain implementation     UI built on top, consuming the API
```

For infra-heavy projects swap `/launch-light` → `/launch-scratch-project`. The iteration-impl half doesn't change.

## Phase 0 — Detect mode and iteration

Two things to detect before planning anything: **which mode** (api / frontend / fullstack) and **which iteration** (v1 / v2+).

### 0.1 Detect mode

Look at what's already in the repo:

```
Glob: apps/api/**/*.controller.ts        → API exists
Glob: apps/web/**/*  OR  web/**/*         → Frontend exists
Glob: src/main.ts                         → Standalone NestJS (older layout, no workspace)
```

Then look at the user's prompt for signals:

| User says | Mode |
|---|---|
| "build the domain", "add entities", "implement v1 of <feature>", references to controllers/services | **api** |
| "build the nextjs frontend", "implement the UI", "consume the api", "from <mockup>", references to .html/.png/figma/docs/ui/ | **frontend** |
| "build everything", "fullstack" | **fullstack** (api first, frontend after) |
| Ambiguous AND no apps/api exists | **api** (build the backbone first) |
| Ambiguous AND apps/api exists | Ask: "API iteration or frontend iteration?" |

**If frontend mode, additionally scan for mockup sources:**

```
Glob: docs/**/mockup*/**/*.html
Glob: docs/**/mockup*/**/*.png  OR  *.jpg  OR  *.svg
Glob: docs/**/ui/**/*
Glob: any path or URL the user provided
```

**The mockup is the spec.** If multiple HTML files exist in the mockup folder, list them in the plan and ask which is the source of truth when they disagree. Never paraphrase the mockup; agents read the files directly.

### 0.2 Detect iteration

```
Glob: apps/api/src/**/*.entity.ts        # existing api entities
Glob: apps/api/src/**/*.controller.ts    # existing endpoints
Glob: apps/api/src/**/*.spec.ts          # existing tests
Glob: apps/web/app/**/*.tsx              # existing pages (Next App Router)
Glob: apps/web/src/**/*.tsx              # existing pages/components (Vite/older layout)
Glob: db/*.json, apps/api/db/*.json      # data files
Glob: http/*.http                         # http examples
```

State up front:
- **Greenfield**: "No prior iteration detected. Starting v1 in `<mode>` mode."
- **Existing**: "Detected v<N> `<mode>`: entities=[…], endpoints=[…], pages=[…], tests=[N]. Are we (a) adding to it, (b) modifying flow, (c) cutting v<N+1> from scratch?"

On v2+, the plan becomes a **delta** — what's added, what's changed, what's removed — not a full rebuild. The build phase still fans out to subagents, but each agent gets the relevant pre-existing files as context.

## Phase 1 — Plan (the most important phase)

Three things to produce, in order:

### 1.1 Extract the scope

From the user's problem statement, pull:

**API mode:**
- **Entities** (typically 2-5 for a 1-hour exercise)
- **Endpoints** (HTTP verb + path + 1-line purpose)
- **The load-bearing logic** — the matching, the workflow transition, the calculation, the rule, the validation predicate. Everything else is plumbing.
- **State / status semantics** — what states do entities pass through, what triggers transitions

**Frontend mode:**
- **Screens / routes** — one per mockup file (e.g. `/<route>/page.tsx`)
- **Components** — the discrete reusable pieces visible in the mockup (cards, badges, tables, forms)
- **API surface to consume** — read `apps/api/src/**/*.controller.ts` to derive the exact endpoints and return shapes. Don't guess.
- **The load-bearing client logic** — the user flow that makes the UI non-trivial: state transitions, optimistic-update + rollback, derived state, form validation rule, routing decision. Display-only screens have none; non-trivial UIs always have some.
- **Design tokens** — colors, fonts, spacing from the mockup's design-system folder if present

### 1.2 Lock 2-4 forced-choice ambiguities

Read the problem statement adversarially. Where is meaning underspecified? Forced-choice (a)/(b)/(c) is faster than open questions. The cost of one clarifying round-trip is much smaller than the cost of rebuilding after a misread.

**API ambiguity examples (generic shapes — substitute your domain):**

- "Status `<X>` means: (a) committed assignment, (b) waiting pool, (c) fallback when auto-pick fails — which?"
- "Multiple candidates + empty hint → (a) random, (b) highest-ranked, (c) leave pending — which?"
- "Persistence: in-memory only, or JSON file (survives restart but not concurrent writes)?"
- "<Entity> created on (a) initial event, (b) confirmation event — which?"
- "Boundary value (e.g. zero, empty, max): which side of the predicate?"

**Frontend ambiguity examples:**

- "Two mockups disagree on <element> (compact vs expanded) — which is canonical?"
- "Route shape: (a) `/<resource>/:id`, (b) `/<parent>/<resource>/:id`, (c) flat — what's the URL design?"
- "After a successful mutation, do we (a) optimistic-update the row, (b) refetch the record, (c) refetch the whole list?"
- "Empty state: (a) blank, (b) illustration + helper text, (c) skeleton placeholders — which?"
- "Polling vs manual refresh vs SSE — does the view auto-update or only on user action?"
- "Mockup shows desktop only — do we ship mobile breakpoints in v1 or skip them?"

### 1.3 Run the simplicity governor

Print the block matching the current mode. **Defaults skewed toward NO.** Each YES needs a one-sentence justification.

**API mode — defaults are NO (except where noted):**

```
[ ] @nestjs/config              → NO (use `import 'dotenv/config'` in main.ts)
[ ] @Inject tokens / DbModule   → NO (inline JsonCollection in service constructor)
[ ] Validation pipes            → NO (controller @Body() is `any` or a plain type)
[ ] Multiple test suites        → NO (one critical-path spec on the business logic)
[X] RED-first tests on load-bearing logic → YES (authored in Phase 1.5, BEFORE agents dispatch)
[ ] Observability (LangSmith)   → NO unless asked; narrate as scope-cut in README
[ ] "Just in case" optional fields → NO
[ ] Generic Repository pattern  → NO (services own JsonCollection directly)
[ ] Nest Logger                 → NO (console.warn is fine)
[ ] OpenAPI / Swagger           → NO (the .http files document the API)
[ ] Auth / RBAC                 → NO unless asked
[ ] Concurrent-write safety     → NO (JSON files, single-process — narrate the limit)
```

**Frontend mode — defaults are NO (except where noted):**

```
[ ] State library (Redux, Zustand, Jotai)   → NO (useState + useReducer cover v1)
[ ] Data-fetching library (TanStack Query)  → NO unless 3+ refetch/cache scenarios actually justify it
[ ] CSS framework (Tailwind)                → NO unless already in package.json (plain CSS + CSS modules)
[ ] UI kit (shadcn/ui, MUI, Chakra)         → NO (build the components the mockup shows; reach later)
[ ] Form library (react-hook-form, Formik)  → NO (controlled inputs + useState are fine for <5 fields)
[ ] Animation library (Framer Motion)       → NO (CSS transitions cover v1)
[ ] i18n library (next-intl, react-i18next) → NO unless multi-language is in scope
[ ] Auth client                              → NO (assume API is internal in v1)
[ ] Error boundary library                   → NO (one inline ErrorBoundary if needed)
[ ] Mobile breakpoints                       → NO unless the mockup explicitly shows them
[ ] Storybook                                → NO (the mockup is the visual spec)
[ ] Backend CORS changes                     → NO (use Vite/Next proxy, same-origin in dev)
[ ] E2E tests (Playwright, Cypress)          → NO (manual click-through + the http/ files cover v1)
[~] RED-first tests on load-bearing client logic → YES IF non-trivial client logic exists (state machine,
                                                  optimistic updates, form validation rule, derived
                                                  state); NO if the iteration is pure display
```

### 1.4 Print plan, wait for green light

Bundle scope, ambiguity questions, and simplicity decisions into one screen. End with:

> Lock the ambiguities and confirm — `go` to start Phase 1.5 (RED tests) followed by the parallel build. `change X` to redirect.

**Do not write code or tests until the user types `go` (or equivalent).**

## Phase 1.5 — Author RED tests (you, not the agents)

**Non-skippable when load-bearing logic exists in this iteration.** Load-bearing = the part where being wrong matters: the rule, the workflow transition, the calculation, the validation predicate, the state-machine guard, the derived state. CRUD plumbing and display surfaces don't qualify; the business rule does.

The agents are about to write the implementation in parallel. They will report "done" regardless of correctness. The test written here is the verdict that survives the agent's confidence.

### Three properties this phase must guarantee

1. **You wrote the test, not an agent.** The test encodes *your* intent from the locked plan, not an agent's interpretation of it. Provenance is what makes the boundary load-bearing.
2. **The test fails for the right reason BEFORE Phase 2 dispatches.** A test you've never seen fail proves nothing. Run it. See the failure. Confirm the failure message reflects the *absence of the behavior* (e.g. `function not defined`, `expected X got undefined`), not an unrelated wiring problem (`module not found because of a typo`).
3. **The test is hard to game.** A single input/output pair is gameable with `if (input === <case>) return <answer>`. Three varied inputs covering the same underlying rule, plus one shape/edge-case check, is roughly as expensive to game as it is to actually implement.

### Mechanics

- Author 2-4 tests in the appropriate spec file for the load-bearing module — wherever the code under test will live (`apps/api/src/<area>/<feature>.spec.ts`, `apps/web/src/lib/<feature>.spec.ts`, etc.).
- **Per behavior under test, prefer 3 varied inputs over 1 representative pair.** Vary along the dimensions of the rule, not along irrelevant axes.
- Include at least **1 shape/property/edge-case test** the agent can't trivially memorize. Generic patterns:
  - "Result must always be a member of the closed set { … }" — catches any case the agent didn't enumerate
  - "Given empty / null / zero / max input, the function takes the spec-defined path rather than throwing"
  - "At a boundary value, the predicate returns the spec-defined side (inclusive vs exclusive)"
  - "Side effects (writes, external calls, mutations) happen at most once per invocation"
  - "Invariants hold across the state transition (e.g. ids preserved, monotonic counters not regressed)"
- Run the file (`pnpm --filter api test <file>`, or scoped equivalent). Confirm RED with a failure message that matches the *absence of the behavior*.
- State out loud: "Tests are RED for the right reason — dispatching agents now."

### Three-layer guardrail summary

Option A (show tests in agent prompts) is the practical choice on a 1-hour clock. What makes it safe enough:

| Layer | What it prevents |
|---|---|
| **Provenance** — you wrote the test, the agent didn't | The agent can't quietly weaken the contract during authoring |
| **Tamper-detect** — Phase 3 checks `git diff` against the test files | The agent can't quietly weaken the contract during implementation |
| **Multi-input gaming cost** — 3+ varied cases + 1 shape check per behavior | Gaming the test letter costs roughly as much as implementing the rule |

None of the three is sufficient alone. All three together are good enough for the interview clock.

### Agent prompt addition (carried into Phase 2)

Every agent prompt that touches the load-bearing module includes:

```
EXISTING TEST FILES (human-authored, READ-ONLY — do not modify or delete):
  - <absolute path to spec file 1>
  - <absolute path to spec file 2>
  - …

Your job is to make these tests go GREEN by writing the implementation.
You MAY add NEW spec files alongside them for your own confidence.
You MAY NOT modify, delete, or weaken any of the human-authored files above.
If `git diff` shows any of these files changed in your output, that is a HARD FAIL.

Also: the tests are sample probes of correctness, not the full spec. Implement the
underlying rule from the locked plan — do not hard-code per-test-case branches.
```

## Phase 2 — Parallel build

ONE message. 3-4 Agent calls in parallel. The plan from Phase 1 + the RED tests from Phase 1.5 are the shared context. Each agent gets the locked plan + simplicity decisions + their slice + the read-only test file paths + a "report back in under 150 words" constraint.

### API agent split (when mode = api)

**Agent A — Data layer**
- Entity types (`apps/api/src/<area>/<entity>.entity.ts`)
- `JsonCollection<T>` if not already present in `apps/api/src/db/`
- Seed file(s) at `apps/api/db/<entity>.json` (or root `db/`) with realistic test data
- Optional `db/seed.ts` reset script

**Agent B — Services + Controllers + HTTP examples**
- One service per entity (CRUD via JsonCollection, in-constructor)
- One controller per entity (`GET /`, `GET /:id`, `POST /`, `PATCH /:id`, `DELETE /:id`)
- One `http/<entity>.http` file per entity with concrete example requests
- **No DTOs, no validation pipes** — `@Body() body: any` or a plain TS type

**Agent C — Load-bearing logic implementation (make the RED tests green)**
- Implements the load-bearing module so the human-authored RED tests in Phase 1.5 pass
- MAY write additional tests alongside the human ones for own confidence
- MAY NOT modify or delete the human-authored test files (hard fail if it does)
- Must implement the *rule* from the locked plan, not memorize the test cases
- Mocks external dependencies (LLM clients, network); never hits live APIs from tests

**Agent D — Wiring + docs**
- Update `apps/api/src/app.module.ts` to register new controllers + services
- `apps/api/package.json` scripts (e.g., `db:seed`) if seed script exists
- `README.md` update: endpoint table, status semantics table, **and a "Scope cuts" section** narrating every NO from the simplicity governor

### Frontend agent split (when mode = frontend)

**Agent A — Routing + layout shell**
- Top-level routing — Next App Router `apps/web/app/<route>/page.tsx`, OR React Router routes for Vite
- Layout shell (header, nav, footer) matching the mockup
- Page skeletons for each mockup screen with placeholder content + correct route params
- Theme/typography setup if the mockup has a design-system folder

**Agent B — Components from mockup**
- One component per discrete UI element in the mockup (cards, badges, tables, forms, modals)
- Plain CSS or CSS modules — match the mockup's visual exactly
- Inline TypeScript types
- No state logic yet — just structural JSX + styles

**Agent C — API client + load-bearing client logic (make the RED tests green if any)**
- Typed fetch wrapper at `apps/web/lib/api.ts` (or `src/lib/api.ts`) mirroring the existing API controllers — **read the API source, don't guess return shapes**
- Hooks/utilities for each endpoint
- Wire the pages from Agent A to use the hooks/client
- **If Phase 1.5 produced RED tests** (optimistic-update logic, form validation rule, derived state, state machine): implement the logic so those tests pass; do not modify the test files
- Error and loading states (red banner on 4xx/5xx, skeleton on loading)
- Vite/Next proxy config for `/api/*` → API port (already present from `/launch-light` web scaffold)

**Agent D — Design tokens + glue**
- Extract colors, spacing, typography from the mockup's design-system folder into CSS variables (`:root` in a global stylesheet)
- Apply tokens to the components from Agent B
- Update `apps/web/README.md` (or root README) with the route table, the proxy contract, and the **"Scope cuts" section** narrating every NO from the simplicity governor

### Agent prompt template

Each Agent prompt MUST include:

```
You are building [slice] for [api / frontend] iteration of [project].

LOCKED PLAN:
[paste plan from Phase 1]

SIMPLICITY DECISIONS (do NOT violate these):
[paste the simplicity governor block, with YES/NO per item]

YOUR SLICE:
[A / B / C / D scope from above]

[IF LOAD-BEARING LOGIC EXISTS IN THIS ITERATION — for the agent owning that slice]
EXISTING TEST FILES (human-authored, READ-ONLY — do not modify or delete):
  - <absolute path to spec file 1>
  - <absolute path to spec file 2>
Make these tests go GREEN. You may add new spec files alongside them. You may NOT
modify the human-authored files — if `git diff` shows any of them changed, hard fail.
Implement the rule from the plan; do not hard-code per-test-case branches.

[FRONTEND MODE ONLY]
MOCKUP SOURCE OF TRUTH — read these files before writing any code:
- /absolute/path/to/docs/.../mockup-files

CRITICAL CONSTRAINTS:
- Do not introduce DI tokens, ConfigModule, validation pipes, or Logger unless explicitly YES above [api]
- Do not introduce state libraries, CSS frameworks, or UI kits unless explicitly YES above [frontend]
- Do not enable backend CORS [frontend] — proxy handles same-origin in dev
- Do not paraphrase the mockup [frontend] — read the HTML/CSS files directly
- Do not add "just in case" optional fields; if v1 doesn't use it, drop it
- Inline simple things; only abstract if there are 3+ duplications
- console.warn over Nest Logger [api]

Report back in under 150 words: what you created/changed (paths + 1-line purpose).
```

### Why 4 agents and not more

3-4 covers the natural seams. More agents = more context-priming overhead than parallelism saves. The seams (data / wire / logic / docs OR routing / components / api / styling) are mostly independent so they don't block each other; finer splits would create cross-agent coordination needs.

## Phase 3 — Hand-off

After all agents return:

### 3.1 Verify test integrity (before anything else)

Run `git diff --stat -- '**/*.spec.ts' '**/*.test.ts'` (or scoped to the human-authored test paths from Phase 1.5).

- If any human-authored test file shows in the diff: **hard fail.** Restore those files (`git checkout -- <path>`) and re-dispatch the violating agent with a stricter constraint. Don't run the tests yet — the agent's modifications might be making them pass dishonestly.
- If only NEW test files appear (agent added its own alongside the human ones): fine, proceed.

### 3.2 Run the tests

`pnpm test` (or scoped equivalent). The test result is the verdict. The agent's "done" claim is not.

- All green: proceed.
- Anything red: surface tersely (which test, which assertion, what was returned). Decide: small fix-up in main thread (1-2 min), or re-dispatch Agent C with the failing test message as the next constraint.

### 3.3 Status report

One short table:
- What's wired (endpoints + load-bearing logic + tests count, OR routes + components + API hooks)
- Where the demo lives (the `.http` file or the URL to open first)
- What was deliberately skipped (the NO items from simplicity governor, with one-line "if you need it, add via: …")

### 3.4 Spec-validity reminder (always print this)

> Green tests prove the implementation matches **your spec**. They do not prove the **spec is correct**. Before declaring done, do a 30-second sanity check: does the locked plan match the original problem statement? Are the entities, the rule, and the success metric the ones the user actually asked for? Tests can be green while the spec measured the wrong thing — that's the failure TDD does *not* catch.

### 3.5 v2 suggestions

2-3 concrete next iterations the user can pick from. Examples:
- **API:** "v2: add LangSmith tracing — wrap the LLM client with `wrapOpenAI`, add `langsmithExtra.metadata.ls_model_name`"
- **API:** "v2: persist beyond restart — move from JSON files to SQLite via `better-sqlite3`"
- **API:** "v2: external API hardening — add `class-validator` DTOs + `ValidationPipe` global, return 400 on shape errors"
- **Frontend:** "v2: optimistic mutations + rollback on error"
- **Frontend:** "v2: skeleton + suspense boundaries instead of `loading...` text"

### 3.6 Next command

Tell the user how to invoke the next iteration: `/iteration-impl v2 — add X to the existing project`.

## Patterns to keep (defaults that survived past sessions)

| Pattern | Why |
|---|---|
| `.http` files in `http/<entity>.http` | Manual integration test artifact; works in REST Client + IntelliJ HTTP runner |
| `db/<entity>.json` per file (not one combined db.json) | Easier git diffs, easier targeted reseeds |
| Single generic `JsonCollection<T>` at `apps/api/src/db/json-collection.ts` | One shared utility, no per-entity boilerplate |
| Lean controllers — `@Body() body: any` (or plain type), no DTOs | Saves real time on a 1-hour exercise |
| **RED tests authored in main thread before agent dispatch** | Provenance — the agent didn't write the contract that constrains it |
| **3+ varied inputs per RED test + 1 shape/edge check** | Gaming the test costs as much as implementing the rule |
| **`git diff` check on test files at hand-off** | Tamper-detect — the agent can't quietly weaken the contract during implementation |
| `db/seed.ts` script that resets all JSON files | Lets the demo replay cleanly |
| Flat `@Module` — no `@Global` tokens, no DbModule | Avoids `@Inject(<TOKEN>)`-style ceremony |
| `import 'dotenv/config'` as line 1 of `apps/api/src/main.ts` | Already in `/launch-light`'s template; assume it's there |
| Frontend: typed `apps/web/lib/api.ts` derived from API controllers' return shapes | Single source of truth; type drift is the most common frontend bug |
| Frontend: Vite/Next proxy for `/api/*` → API port | Same-origin in browser, no CORS work, no env config |
| Frontend: plain CSS + design tokens in `:root` | Matches mockup exactly without forcing Tailwind/shadcn ceremony |
| Frontend: pass mockup file paths to subagents | "Read this HTML/CSS" beats "build something like X" — zero paraphrase loss |
| Frontend: scoped per-app tsconfig | Prevents API tsc from sweeping frontend code — the silent-death bug |

## Anti-patterns

**General — TDD-as-guardrail discipline:**

- **Don't let an agent write the tests that constrain its own implementation.** A test the implementer authored is a contract the implementer interpreted twice — once when writing the test, once when writing the code. Both interpretations match by construction. The test only constrains when authored by someone *other* than the implementer. Phase 1.5 happens in the main thread, not in a subagent.
- **Don't accept the agent's "done" claim without running the tests.** Self-reports are not evidence. Self-reports are claims. The test result is the evidence. Structure your hand-off so the test runs *before* you write the status report — green/red, not "done."
- **Don't write a single I/O pair as your RED test.** One input/output pair is gameable with `if (x === <case>) return <answer>`. Three varied inputs + one shape check costs the agent roughly as much to game as it does to implement. Tests under that floor are theater.
- **Don't skip the "see it fail for the right reason" step.** A test that has only ever been green is worth nothing — you don't know if it *can* fail. Run the RED test in Phase 1.5 and check the failure message reflects the absence of behavior (not an unrelated wiring error).
- **Don't write code before the user confirms the plan.** Phase 1's green light is a hard gate. Even on v2+.
- **Don't spawn 8 agents** when 3-4 cover the work. More agents = more context priming than work saved.
- **Don't reimplement utilities** that already exist in the repo. Phase 0 detects them; reuse.

**API mode:**

- **Don't write CRUD tests for every controller.** The data-layer spec covers JsonCollection; the `.http` files cover the wire. Spend test budget on the load-bearing logic.
- **Don't add `@nestjs/config`** for a single LLM key. Plain `dotenv/config` is enough; mention `@nestjs/config` only in the v2 suggestions if typed config would actually help.
- **Don't add validation pipes** (`class-validator`, `ValidationPipe`) unless the user explicitly asks. External APIs need them; 1-hour interview code doesn't.
- **Don't build a DbModule + provider tokens** for one file. Construct collections inline in the service constructor.
- **Don't write observability code** unless asked. Mention it as a scope cut. Hand the user a v2 stub.
- **Don't add "just in case" fields.** No optional `<extraThing>?: <type>` unless the v1 flow actively uses it.
- **Don't reach for `Logger.warn`** in fallback paths. `console.warn` is fine. Save Logger for when there's a real observability story.

**Frontend mode:**

- **Don't reach for a UI kit on v1** when the mockup is clean enough to implement directly. shadcn/MUI are valuable when the mockup is unopinionated; here the mockup IS the opinion.
- **Don't add Tailwind retroactively** if the scaffold ships plain CSS. The cost of mixing two CSS systems isn't worth it on a one-shot iteration.
- **Don't paraphrase the mockup** in the agent prompts — always pass the file paths. "Inbox screen with a sidebar" is the wrong abstraction; the mockup HTML has the exact layout.
- **Don't enable backend CORS** to make `fetch` work. Use the proxy. Backend CORS is for cross-domain prod, not local dev.
- **Don't type the API by guessing.** Read `apps/api/src/**/*.controller.ts` and mirror the return shapes in the frontend's `lib/api.ts`. Drift between API and FE types is the #1 frontend iteration bug.
- **Don't build mobile responsive layouts** unless the mockup shows them. Desktop-only is fine for v1 if the mockup is desktop-only.
- **Don't write a state-management layer** until you've actually felt the pain. `useState` + props gets you further than Junior-FE-Twitter suggests.

## Iteration-awareness rules

Built for being called repeatedly:

- **v1** (greenfield): full build, all 4 agents, Phase 1.5 RED tests on the load-bearing piece.
- **v2** (extend): one or two agents only — usually B (new endpoints) + C (changed logic) for API, or B (new components) + C (new API hooks) for frontend — with existing files as context. Skip A and D unless the change touches them. **Phase 1.5 still runs** if the v2 change touches load-bearing logic — new RED tests for the new behavior, not a rewrite of the v1 tests.
- **v3+** (refactor / fix): often a single Agent with surgical edits. Phase 1's plan is a one-screen diff description. If the refactor preserves behavior, the existing tests are still the contract; no new Phase 1.5 needed. If the refactor *changes* behavior, write the new RED tests first.
- **Mode switch** (api → frontend, or frontend → api): treat as a new v1 in the other mode. Phase 0 detects the existing other-mode work and uses it as context (e.g. frontend mode reads existing API controllers to type the client).
- **Always** re-print the simplicity governor in the plan, even on v2+. Ceremony tends to creep in as iterations stack.

State this explicitly in the plan: "This is v2 frontend; reusing the existing API at apps/api/, adding [X] pages. Not touching the API. Phase 1.5: new RED tests for the optimistic-update logic only."

## One-liners the user can paste

API v1:
```
/iteration-impl Build [domain]. Entities: [a, b, c]. Main flow: [the load-bearing thing]. Iteration 1.
```

API v2 (extend):
```
/iteration-impl v2 on this project — add [feature]. Keep everything else.
```

Frontend v1 from mockup:
```
/iteration-impl nextjs frontend from docs/ui/mockup-frontend/ — consume the existing api.
```

Frontend v2 (polish):
```
/iteration-impl v2 frontend — add optimistic updates + skeleton states. Don't restructure routes.
```

---

_Authored by [DevOtts](https://github.com/DevOtts)._
