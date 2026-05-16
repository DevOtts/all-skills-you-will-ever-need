---
name: landing-page-builder
description: Build premium landing pages that don't smell like AI slop — concept-first atmosphere, real proof points, motion that respects users, and JSON-LD that gets you cited by Google rich results and AI search engines. Use when building a marketing site or landing page from scratch (Next.js / Tailwind / shadcn), iterating on a hero that feels generic or "Bootstrap-y", launching a SaaS / B2B / agency single-page offer, or requesting dark + light hero variants for A/B feel.
metadata:
  author: DevOtts
  author_url: https://github.com/DevOtts
---

# Landing Page Builder

Build premium landing pages that don't smell like AI slop — concept-first atmosphere, real proof points, motion that respects users, and JSON-LD that gets you cited by Google rich results and AI search engines.

---

## When to use

Trigger this skill when the user (or any user) is:

- Building a new marketing site / landing page from scratch (Next.js, Tailwind, shadcn)
- Iterating on a hero or above-the-fold and the current state feels "generic", "AI slop", "vanilla", or "Bootstrap-y"
- Launching a SaaS, AI product, B2B service, agency, or POC offer that needs a single high-conversion page
- Mentioning "hero section", "conversion", "lead capture", "lead modal", "above the fold", "premium feel", or "marketing site"
- Asking for a side-by-side dark + light hero variant so they can A/B feel
- Adding structured data / JSON-LD / GEO (Generative Engine Optimization) coverage to an existing site

Do **not** trigger for app/dashboard UI work, internal tooling, or component libraries — that's `ui-styling` or `ui-ux-pro-max` territory without the LP framing.

---

## 1. Skill dependencies & orchestration

This skill is a conductor, not a soloist. **Invoke these in order:**

1. **`/ui-ux-pro-max` — FIRST, always.** Pull design intelligence for the product type before you write a line of JSX. It returns typography pairings, color systems, layout rules, and product-type-specific UX patterns (SaaS LP ≠ portfolio LP ≠ agency LP). Skipping this step is how you end up with "AI slop": generic gradient + 3-up feature grid + bare CTA.

2. **`mcp__magic__21st_magic_component_inspiration`** — Pull hero, pricing, CTA, FAQ section ideas from the 21st.dev gallery. Use early, during the "what does this look like" phase. Returns curated component refs, often with code.

3. **`mcp__magic__21st_magic_component_builder` / `_refiner`** — Once you've picked a direction, use the builder to scaffold a section and the refiner to evolve it. Don't reach for these before step 1 + 2.

4. **`/chrome-cdp-control` or headless Playwright** — Capture screenshots of reference sites (see Section 4). Real visual study beats remembered impressions. CDP if the user has it running; otherwise a one-shot `playwright screenshot` script.

5. **`/favicon-builder`** — At handoff time, generate the favicon set from the product logomark. Never ship the full horizontal marketing logo as a favicon — it renders as a 2-pixel smear.

6. **`/banner-design` (optional)** — When you need OG images, social cards, or hero illustrations beyond what shadcn provides.

7. **`/design`** (optional) — Brand identity / CIP work if the project is greenfield.

The unhappy path: jumping straight to writing `<HeroSection>` without `/ui-ux-pro-max`. Every time you do this, the result is "AI slop." Don't.

---

## 2. Reference sites — capture, then steal

Open each in Chrome (CDP) or headless Playwright, screenshot above-the-fold + scroll halfway + scroll to footer. Save to a `references/` folder in the project. Study before you build.

- **<https://supahero.io/>** — Curated hero gallery. Composition study: how columns split, where eyebrow/headline/sub/CTA stack, how product imagery is framed. Use as a mood board before picking a direction.
- **<https://shadcnstudio.com/blocks/marketing-ui/hero-section>** — shadcn-native marketing blocks. Source these when the project is already on shadcn — the components drop in with zero theme reconciliation.
- **<https://sentine-lp.vercel.app/>** — Minimalist dark hero, perfect ratio of negative space to content. Steal the proof-pill row pattern and the subtle aurora atmosphere.
- **<https://www.redentia.com.br/>** — The reference for the 2-column dark-pitch + light-form lead capture modal we shipped. Mimic the panel ratio, the value-prop bullets on the dark side, the form density on the light side.
- **<https://betterstack.com/>** — Premium SaaS polish. Watch how every element has a faint shadow, a hairline border, and a single accent color carrying the brand. The discipline is in what's *missing*.
- **<https://wope.com/>** — Motion-heavy reference. Scroll-orchestrated reveals, sticky transforms, animated counters tied to viewport position. Pull pacing ideas, not the entire choreography.
- **<https://www.dialedweb.com/>** — Typography-first. Oversized headlines, tight leading, gradient on one word only. The opposite of "huge hero image" — let type carry the page.

Rule: never copy 1:1. Steal a *pattern* (column split, atmosphere recipe, reveal cadence), reskin it with the project's brand tokens.

---

## 3. Page structure — the canonical 7 sections

Every premium LP we've shipped collapses to this skeleton. Build each as its own file under `components/marketing/landing/`. Use the Next.js App Router route group `(marketing)` so the marketing site shares no layout chrome with the authenticated app.

```
app/
  (marketing)/
    layout.tsx        # marketing-only chrome (different header/footer)
    page.tsx          # the LP itself — composes the 7 sections
    robots.ts
    sitemap.ts
components/marketing/
  landing/
    HeroSection.tsx          # 1. Hero (dark variant)
    HeroCleanSection.tsx     # 1b. Hero (light variant) — A/B swap
    TrustStrip.tsx           # 2. logos / press / social proof bar
    ProblemSection.tsx       # 3. the pain you solve
    SolutionSection.tsx      # 4. how the product works
    OfferSection.tsx         # 5. price / POC / what they get
    FAQSection.tsx           # 6. answer-first Q&A
    CTASection.tsx           # 7. final ask
    LeadCaptureModal.tsx     # 2-column lead modal
    LeadModalProvider.tsx    # context: openLeadModal()
    primitives/
      AnimatedCounter.tsx
      ScrollReveal.tsx
      ParticleField.tsx
      smoothScrollTo.ts
  StructuredData.tsx         # all JSON-LD components
```

`page.tsx` composes the 7 sections and wraps inner anchors with `scroll-mt-24` so the sticky header doesn't eat the headline on hash navigation:

```tsx
<main className="flex flex-col min-h-screen">
  <HeroSection />
  <TrustStrip />
  <div id="problem" className="scroll-mt-24"><ProblemSection /></div>
  <div id="solution" className="scroll-mt-24"><SolutionSection /></div>
  <div id="offer" className="scroll-mt-24"><OfferSection /></div>
  <div id="faq" className="scroll-mt-24"><FAQSection /></div>
  <CTASection />
</main>
```

Each section file owns its own background, padding, and theme tokens — never one giant `page.tsx` doing it all.

---

## 4. Tech stack patterns

- **Next.js 15 App Router** — Server Components by default; only `"use client"` on motion + interactive bits.
- **Tailwind v4** — Theme via CSS variables in `globals.css`. shadcn tokens (`bg-background`, `text-foreground`, `bg-card`, `ring-border`) so dark/light swap is one root-class change.
- **shadcn/ui** — `Button`, `Dialog`, `Input`, `Label`, `Accordion` as the foundation. Never re-roll these.
- **`motion@^12+`** (the Framer Motion successor, package name `motion`) — `import { motion, useReducedMotion, useInView, animate } from "motion/react"`. Always import from `motion/react`, not `framer-motion`.
- **lucide-react** for icons. 1.5px stroke (`strokeWidth={1.5}`) at most sizes; 2px only for chunky 24px+ icons.
- **JSON-LD structured data** — Organization, WebSite, SoftwareApplication, FAQPage, LandingWebPage, BreadcrumbList. Cross-link via stable `@id` URLs (e.g. `${baseUrl}/#organization`) so engines resolve the graph.
- **AI bot allowlist in `app/robots.ts`** — explicit `allow: "/"` for: `GPTBot`, `ChatGPT-User`, `OAI-SearchBot`, `ClaudeBot`, `anthropic-ai`, `Claude-Web`, `PerplexityBot`, `Perplexity-User`, `CCBot`, `Google-Extended`, `GoogleOther`, `Applebot-Extended`, `Bytespider`, `Amazonbot`, `Meta-ExternalAgent`, `FacebookBot`. Being absent from these crawlers' allowlists is being invisible in AI search.
- **`app/sitemap.ts`** — generated from a small URL list, includes `lastModified` per route.

---

## 5. Animation primitives — build these once, reuse forever

These four primitives carry every premium LP we've shipped. Put them in `components/marketing/landing/primitives/` and never re-implement.

### `AnimatedCounter`

```ts
<AnimatedCounter to={1_847_320} duration={2.6} className="text-5xl font-bold" />
```

Animates from `from` (default 0) to `to` over `duration` seconds. Triggers when the element enters the viewport via `useInView`. Locale-aware via `Intl.NumberFormat` (default `pt-BR`, easy to swap). **Respects `useReducedMotion`** — snaps to the final value instead of animating. Wraps in a `font-tabular` span so the number doesn't jitter mid-count.

Critical detail from our real code:

```tsx
const intlBR = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });
// inside the effect:
const controls = animate(from, to, {
    duration,
    ease: [0.16, 1, 0.3, 1],
    onUpdate: (latest) => setDisplay(format(latest)),
});
```

### `ScrollReveal`, `ScrollRevealGroup`, `ScrollRevealItem`

```tsx
<ScrollReveal direction="up" delay={0.1}>...</ScrollReveal>

<ScrollRevealGroup staggerChildren={0.08}>
  <ScrollRevealItem>...</ScrollRevealItem>
  <ScrollRevealItem>...</ScrollRevealItem>
</ScrollRevealGroup>
```

`ScrollReveal` is the atomic entrance primitive — `opacity 0 → 1` plus a directional offset (`up`/`down`/`left`/`right`/`none`). Uses `motion`'s `whileInView` with `viewport={{ once: true, amount: 0.2 }}` so each block fires once when 20% visible. `Group` + `Item` is for orchestrated staggers — feature grids, FAQ accordions, value-prop lists. Always honors `useReducedMotion`.

### `ParticleField`

```tsx
<ParticleField count={36} color="text-emerald-300" seed={11} className="-z-10 opacity-70" />
```

CSS-only floating particle dots for hero atmosphere. **SSR-safe**: positions are computed via a seeded `mulberry32` PRNG so server-rendered HTML matches the first client render (no hydration mismatch warnings). Each particle floats via `animate-float-y` with negative animation delays so the field is already in motion on mount instead of all starting from `y: 0`.

```ts
function mulberry32(seed: number) {
    return () => {
        seed |= 0;
        seed = (seed + 0x6d2b79f5) | 0;
        let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}
```

Layer two fields (emerald + blue, different seeds) for richer texture.

### `smoothScrollTo`

```tsx
<a href="#problem" onClick={smoothScrollTo("problem")}>How it works</a>
```

`onClick` factory that prevents the default browser jump, calls `el.scrollIntoView({ behavior: "smooth", block: "start" })`, and syncs the URL hash via `history.replaceState`. Native smooth scrolling honors `prefers-reduced-motion` automatically in Safari/Firefox.

```ts
export function smoothScrollTo(targetId: string) {
    return (e: MouseEvent<HTMLAnchorElement>) => {
        const el = document.getElementById(targetId);
        if (!el) return;
        e.preventDefault();
        el.scrollIntoView({ behavior: "smooth", block: "start" });
        history.replaceState(null, "", `#${targetId}`);
    };
}
```

---

## 6. CSS utilities — add to `globals.css`

These are the brushes the hero uses to paint atmosphere. Add once, reach for everywhere.

```css
/* === Background utilities === */
.bg-mesh-aurora {
    background:
        radial-gradient(at 20% 30%, rgba(56,189,248,0.15) 0%, transparent 50%),
        radial-gradient(at 80% 20%, rgba(16,185,129,0.15) 0%, transparent 50%),
        radial-gradient(at 50% 90%, rgba(139,92,246,0.10) 0%, transparent 50%);
}
.bg-mesh-aurora-dense {
    background:
        radial-gradient(at 15% 25%, rgba(56,189,248,0.25) 0%, transparent 45%),
        radial-gradient(at 85% 15%, rgba(16,185,129,0.22) 0%, transparent 45%),
        radial-gradient(at 50% 95%, rgba(139,92,246,0.15) 0%, transparent 45%);
}
.bg-grid-dots {
    background-image: radial-gradient(circle, currentColor 1px, transparent 1px);
    background-size: 22px 22px;
}

/* === Keyframes === */
@keyframes shimmer {
    0% { background-position: -200% 0; }
    100% { background-position: 200% 0; }
}
@keyframes scan-beam {
    0%, 100% { transform: translateY(0); opacity: 0; }
    50% { opacity: 1; }
    100% { transform: translateY(100%); }
}
@keyframes profit-pulse {
    0%, 100% { transform: scale(1); opacity: 0.7; }
    50% { transform: scale(1.6); opacity: 0; }
}
@keyframes float-y {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-8px); }
}
@keyframes mesh-drift {
    0%, 100% { background-position: 0% 0%; }
    50% { background-position: 100% 100%; }
}

.animate-shimmer { animation: shimmer 3s linear infinite; }
.animate-scan-beam { animation: scan-beam 4s ease-in-out infinite; }
.animate-profit-pulse { animation: profit-pulse 2s ease-in-out infinite; }
.animate-float-y { animation: float-y 6s ease-in-out infinite; }
.animate-mesh-drift { animation: mesh-drift 20s ease-in-out infinite; }

/* === Tabular numerals — counter stability === */
.font-tabular { font-variant-numeric: tabular-nums; }

/* === Global reduced-motion neutralizer === */
@media (prefers-reduced-motion: reduce) {
    *, *::before, *::after {
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
        transition-duration: 0.01ms !important;
        scroll-behavior: auto !important;
    }
}
```

The global neutralizer means primitives don't each need to feature-detect `prefers-reduced-motion` — they all collapse to instant transitions at the CSS layer. Components still check `useReducedMotion()` to *skip* JS-driven animations entirely (saves CPU + battery).

---

## 7. Hero patterns

The hero is 70% of the impression. Build it with care.

### Atmosphere layers (back → front)

```
1. Aurora mesh        → bg-mesh-aurora-dense (z: -30)
2. Radial glow        → center hot-spot via inline radial-gradient (z: -30)
3. Godrays            → conic-gradient from the top, blur-40 (z: -20)
4. Subtle grid        → 60px line-grid masked to a center ellipse (z: -20)
5. Particles          → two ParticleField layers, different seeds (z: -10)
6. Vignette           → bottom linear-gradient back to surface (z: -10)
```

Each layer is `aria-hidden`, absolutely positioned, and one negative z-index step closer to the content than the last. **This stack is the difference between "premium" and "AI slop."** Without it the hero is just text on a flat color.

Reference snippet from `HeroSection.tsx`:

```tsx
<div aria-hidden className="absolute inset-0 -z-30 bg-mesh-aurora-dense opacity-50" />
<div aria-hidden className="absolute inset-0 -z-30 opacity-90" style={{
    background: "radial-gradient(60% 50% at 50% 30%, rgba(56,189,248,0.18) 0%, rgba(16,185,129,0.10) 35%, rgba(0,0,0,0) 70%)",
}} />
<div aria-hidden className="absolute inset-x-0 top-0 h-[420px] -z-20 opacity-50 mix-blend-screen" style={{
    background: "conic-gradient(from 200deg at 50% -10%, transparent 0deg, rgba(56,189,248,0.18) 35deg, transparent 60deg, ...)",
    filter: "blur(40px)",
}} />
<ParticleField count={36} color="text-emerald-300" seed={11} className="-z-10 opacity-70" />
<ParticleField count={24} color="text-blue-300" seed={42} className="-z-10 opacity-60" />
```

### Grid layout

12-column grid above `lg`. **Headline column gets 7, product mockup gets 5** (or 8/4 for type-first heroes). Don't split 50/50 — it feels stagnant.

```tsx
<div className="grid lg:grid-cols-12 gap-12 lg:gap-8 items-center max-w-7xl mx-auto">
    <div className="lg:col-span-7 relative">...headline...</div>
    <div className="lg:col-span-5 relative">...product card...</div>
</div>
```

### Headline rules

- One `<h1>` per page. Multi-line via `<span className="block">`.
- **Gradient on ONE key phrase only** — the rest stays solid. Gradient-on-everything reads as "AI generated."
- `text-balance` on the headline so line breaks land on phrase boundaries.
- Eyebrow micro-line above the H1 in muted color, smaller weight.

```tsx
<h1 className="font-bold tracking-tight leading-[0.95] text-balance mb-7">
    <span className="block text-2xl md:text-3xl font-medium text-muted-foreground mb-4">
        Eyebrow micro-line
    </span>
    <span className="block text-5xl md:text-6xl lg:text-7xl">
        Solid statement line
    </span>
    <span className="block text-5xl md:text-6xl lg:text-7xl mt-1">
        <span className="text-muted-foreground/70 font-medium">or </span>
        <span className="bg-gradient-to-r from-emerald-300 via-blue-400 to-emerald-300 bg-clip-text text-transparent italic">
            the killer phrase?
        </span>
    </span>
</h1>
```

### CTAs

Always **two**: primary (solid, branded shadow glow) and secondary (outline/ghost, anchors to `#problem` or `#solution`).

```tsx
<Button size="lg" onClick={openLeadModal} className="h-14 px-7 rounded-full ...">
    <Sparkles className="mr-2 h-5 w-5" />
    Apply for POC
    <ArrowRight className="ml-2 h-5 w-5 transition-transform group-hover:translate-x-1" />
</Button>
<Button asChild variant="ghost" size="lg" className="h-14 px-7 rounded-full ...">
    <a href="#problem" onClick={smoothScrollTo("problem")}>How it works</a>
</Button>
```

### Proof pills (3-up grid)

Below the CTAs. Each pill: icon + value + label. **The icon MUST reinforce the label's semantic** — `<Clock />` for time units, `<TrendingUp />` for growth, `<BarChart3 />` for analytics, `<Percent />` for percentages of a static base. We shipped `<Percent />` next to "<8 weeks" by accident — that's exactly the kind of mismatch that screams "AI slop."

```tsx
<ProofPill icon={<TrendingUp className="h-3.5 w-3.5" />} value="+1.7%" label="margin"  tone="emerald" />
<ProofPill icon={<BarChart3  className="h-3.5 w-3.5" />} value="+4%"   label="profit"  tone="emerald" highlight />
<ProofPill icon={<Clock      className="h-3.5 w-3.5" />} value="<8 wk" label="POC"     tone="blue" />
```

Render value + label on separate lines so the value font-weight doesn't have to fight the label tracking. The pill shape is `rounded-xl ring-1 backdrop-blur-sm` with a tone-driven ring color.

### Floating product card (right column)

The "wow" element. Anchor with a halo glow behind it, then layer:
- **Live indicator chip** — pulsing dot + "powered by..." pill at top-left, floating with `animate-float-y` (offset animation-delay).
- **Big counter** — `<AnimatedCounter>` with currency prefix, large + colored + drop-shadow glow.
- **Sparkline bars** — 12 bars, heights from a static array, each bar's `height` animated in with `0.04s * i` stagger.
- **KPI strip** — 2-col grid below a `border-t`, mini-counters for secondary metrics.
- **Floating result chip** — "+R$ 4.200 / mo — Beer X" pill at bottom-right, also floating.

Both floating chips use `animate-float-y` with `animationDelay: "-2s"` on one of them so they're out-of-sync.

### Scroll-down hint — placement gotcha

Anchor the chevron to the **outer `<section>`**, NOT to the inner grid container. If it's inside the grid, it absolutely-positions over the proof pills on shorter viewports. We just hit this bug — calling it out.

```tsx
<section className="relative isolate ...">
    <div className="container mx-auto ..."> ...content... </div>

    {/* OUTSIDE the inner container */}
    <motion.a href="#problem" onClick={smoothScrollTo("problem")}
        className="hidden md:flex absolute left-1/2 -translate-x-1/2 bottom-5 z-10 ...">
        <span>Scroll to discover</span>
        <ChevronDown className={reduce ? "" : "animate-float-y"} />
    </motion.a>
</section>
```

### Ship dark AND light variants

Build `HeroSection.tsx` (dark) and `HeroCleanSection.tsx` (light) in parallel. Same structure, same atmosphere vocabulary, different surface tokens. Switching between them is a one-line import change in `page.tsx`:

```tsx
// import { HeroSection } from "@/components/marketing/landing/HeroSection";
import { HeroCleanSection as HeroSection } from "@/components/marketing/landing/HeroCleanSection";
```

This is the single fastest A/B feel switch. Don't skip it.

---

## 8. Lead capture pattern — the Redentia 2-column

The modal that converts. Built on shadcn `<Dialog>`, lives in `LeadCaptureModal.tsx`, opened via a `LeadModalProvider` context that exposes `openLeadModal()`.

### Layout

`<DialogContent>` uses `grid md:grid-cols-[1.05fr_1fr]`:

- **Left (dark pitch panel)** — Same atmosphere vocabulary as the hero (aurora + radial glow + grid). Badge → headline → description → 4 value props (icon + title + 1-line description) → bottom trust strip ("3 of 5 seats remaining" / "4–8 weeks").
- **Right (light form panel)** — Compact mobile-only header (since the pitch panel is `hidden md:flex`), then a 5-field form: Name, Company, Volume (number), WhatsApp (formatted), Email. Two-column grid for Volume + WhatsApp; the others span full width.

### Form mechanics

- Inline phone formatting on input (`formatPhone` reducer that emits `(##) #####-####`).
- Per-field `validate(form)` returning a `Partial<Record<keyof FormState, string>>` errors map.
- `<Field>` wrapper component owning label + input + error message, with `aria-invalid`.
- POST JSON to a webhook (`process.env.NEXT_PUBLIC_N8N_WEBHOOK_URL` in our build — we used n8n). Include `source: "landing"` and `submitted_at: new Date().toISOString()`.
- `status: "idle" | "submitting" | "success" | "error"` state machine.

### Anti-scrape phone numbers

**Critical pattern.** Never embed your support WhatsApp number as a contiguous string in the source. Scrapers crawl the rendered HTML before any user submits. Split it into parts and only join after success:

```tsx
// Split — scrapers reading the source/HTML pre-submit see nothing useful.
const WA_PARTS = ["55", "21", "9XXXX", "XXXX"];

// Only in SuccessView, after status === "success":
const number = WA_PARTS.join("");
const display = `(${WA_PARTS[1]}) ${WA_PARTS[2]}-${WA_PARTS[3]}`;
<a href={`https://wa.me/${number}?text=${encodeURIComponent(message)}`}>
    Conversar no WhatsApp {display}
</a>
```

The `SuccessView` is its own brand-aligned panel (full-modal dark surface, atmosphere layers, big checkmark, gradient headline, WhatsApp CTA in WhatsApp brand green `#25D366`). Don't bounce the user back to the form on success.

---

## 9. SEO / GEO metadata

Both classical SEO and GEO (AI search visibility) lean on the same structured-data scaffolding. Every premium LP gets all of this.

### Per-page metadata

```tsx
export const metadata: Metadata = {
    title: { absolute: "Product — Killer hook in <60 chars including brand" },
    description: "1–2 sentence pitch that includes the primary metric and the offer (e.g. 'POC in 8 weeks').",
    alternates: { canonical: "/" },
    openGraph: {
        title: "Different-angle title (the social pitch)",
        description: "Conversion-leaning OG copy, not the dry one.",
        type: "website",
        locale: "pt_BR", // or the target market
    },
    twitter: { title: "...", description: "..." },
};
```

`title.absolute` bypasses the `template` suffix set in the root layout — critical so your LP doesn't read "Product · Brand · Brand" when the root template is `%s · Brand`.

Set `metadataBase` once in the root layout (`new URL("https://example.com")`) so OG image paths resolve correctly.

### JSON-LD — 6 schemas, cross-linked via `@id`

Render these as Server Components inside `page.tsx`:

```tsx
<LandingWebPageSchema />
<SoftwareApplicationSchema />
<FAQPageSchema />
<BreadcrumbSchema />
```

(`OrganizationSchema` + `WebSiteSchema` live in the root layout so they apply to every page.)

Every schema has a stable `@id` URL (`${baseUrl}/#organization`, `${baseUrl}/#website`, `${baseUrl}/#profit-scan`, etc.) and cross-references the others by `@id`:

```ts
{
    "@type": "WebPage",
    "@id": `${baseUrl}/#webpage`,
    isPartOf: { "@id": `${baseUrl}/#website` },
    about: { "@id": `${baseUrl}/#profit-scan` },
    publisher: { "@id": `${baseUrl}/#organization` },
}
```

This linking is what gets you cited in ChatGPT / Perplexity / Claude / Google AI Overviews — they parse the graph, resolve identities, and treat your FAQPage as an answer source.

Set `inLanguage` on every schema (`"pt-BR"` for our market). Set `areaServed` on `Organization`. Set `audience` + `offers` on `SoftwareApplication`. The richer the schema, the higher the citation rate.

### robots.txt — AI allowlist

See `app/robots.ts` — explicit `allow: "/"` for every AI crawler. Absent rules sometimes get treated as blocks by paranoid crawlers; explicit allows close the door on accidents.

### sitemap.ts

```ts
export default function sitemap(): MetadataRoute.Sitemap {
    const baseUrl = appConfig.url.replace(/\/$/, "");
    return [
        { url: `${baseUrl}/`, lastModified: new Date(), changeFrequency: "weekly", priority: 1 },
        // ...other routes
    ];
}
```

---

## 10. Common pitfalls — the "AI slop" smells

If your LP has any of these, it reads as AI-generated. Hunt them down.

- **Generic gradient backgrounds with no concept.** A single `bg-gradient-to-br from-purple-500 to-blue-500` shouts "Tailwind tutorial." Replace with a layered atmosphere stack (Section 7).
- **No proof points.** Numbers, citations, customer logos, animated counters. If the LP has zero hard numbers above the fold, it has zero credibility.
- **Single hero variant.** Can't switch feel without rewriting. Always ship dark + light in parallel.
- **Bare `<a href="#x">` instead of `smoothScrollTo`.** The jarring instant-jump kills the premium feel in one click.
- **Mismatched icons.** `<Percent />` next to a time-unit, `<Clock />` next to a percentage. Icons must reinforce the label's semantic — we just shipped a fix for this exact bug.
- **Tiny stroke widths on icons.** lucide defaults are fine; never go below `strokeWidth={1}` — icons disappear at small sizes.
- **Pills that split value + suffix into mis-sized spans.** `+1.7<span class="text-xs">%</span>` looks broken on the proof bar. Render the whole value as one span; if you want a suffix smaller, give it `align-baseline` and a deliberate weight.
- **Full horizontal marketing logo as favicon.** Unreadable at 16x16. Generate a square logomark via `/favicon-builder` and ship all the sizes.
- **No `prefers-reduced-motion` respect.** Accessibility miss and CPU waste. Both the global CSS neutralizer and `useReducedMotion()` in JS.
- **No JSON-LD.** Invisible to Google rich results and to AI search citations. Free signal, leave it on the table at your peril.
- **Footer disclaimer placed below an empty `<div>`.** Always render a real `<footer>` with at least: legal name + CNPJ/EIN, contact email, privacy/terms links, copyright year, social icons. Empty footers smell.
- **One CTA only.** Two is the minimum (primary + secondary). Three is fine if one is "ghost" tier.
- **All gradient text everywhere.** Gradient on the headline keyword only. Solid for everything else.

---

## 11. Workflow when invoked

Follow this sequence end-to-end. Don't skip steps.

1. **Discover the brand + product type.** Ask: industry, target market, primary metric (margin? conversion? signups?), brand colors / mood, locale. If anything's missing, ask before coding.
2. **Invoke `/ui-ux-pro-max`** with the product type and brand mood. Save the returned design intelligence (typography, palette, layout rules) as the project's design tokens.
3. **Capture reference sites** (Section 4) via `/chrome-cdp-control` or headless Playwright. Drop screenshots into `references/` for visual study.
4. **Pull inspiration** via `mcp__magic__21st_magic_component_inspiration` — hero, pricing, FAQ. Pick a direction.
5. **Scaffold the 7 sections** as empty files under `components/marketing/landing/`. Set up the `(marketing)` route group with `layout.tsx` and `page.tsx`.
6. **Build the primitives** — `AnimatedCounter`, `ScrollReveal*`, `ParticleField`, `smoothScrollTo`. Once. Reuse across every section.
7. **Add CSS utilities** to `globals.css` — aurora meshes, keyframes, `font-tabular`, the reduced-motion neutralizer.
8. **Build the hero** with the full atmosphere stack (Section 7). Ship dark AND light variants.
9. **Wire the lead modal** — `LeadCaptureModal.tsx` + `LeadModalProvider.tsx`, POST to webhook, anti-scrape WhatsApp split, success view with deeplink.
10. **Build the remaining 6 sections** with `ScrollReveal` orchestration and `AnimatedCounter` wherever there's a hard number.
11. **Add structured data** — `StructuredData.tsx` with all 6 schemas, cross-linked via `@id`. Render the page-level ones in `page.tsx`, the org-level ones in root `layout.tsx`.
12. **Add `robots.ts` + `sitemap.ts`** — full AI bot allowlist.
13. **Generate the favicon set** via `/favicon-builder` from the product logomark.
14. **Iterate per section** using `mcp__magic__21st_magic_component_refiner` and the user's eyeball test. Capture before/after screenshots via Chrome CDP for comparison.
15. **Type-check + lint** at the end: `npx tsc --noEmit && npx next lint`. Fix every error. No `any`. No unused imports.
16. **Handoff** — print the file tree, the env vars required (`NEXT_PUBLIC_N8N_WEBHOOK_URL`, etc.), and the one-line import swap for dark/light hero.

---

## 12. Hard rules

- ✅ ALWAYS invoke `/ui-ux-pro-max` before writing the first section.
- ✅ ALWAYS build dark + light hero variants in parallel.
- ✅ ALWAYS use the 6-layer atmosphere stack on the hero (aurora → glow → godrays → grid → particles → vignette).
- ✅ ALWAYS use `smoothScrollTo` for in-page anchors — never bare `<a href="#x">`.
- ✅ ALWAYS render JSON-LD with cross-linked `@id` references on every LP.
- ✅ ALWAYS allowlist all major AI crawlers in `robots.ts`.
- ✅ ALWAYS split WhatsApp / phone numbers in source code and join post-submit.
- ✅ ALWAYS honor `useReducedMotion` in JS AND ship the global CSS reduced-motion neutralizer.
- ✅ ALWAYS run `npx tsc --noEmit` before handing off.
- ❌ NEVER ship a single hero variant — you lose the fastest A/B feel switch.
- ❌ NEVER apply gradient text to more than one phrase in the headline.
- ❌ NEVER place the scroll-down hint inside the inner grid container (it overlaps content).
- ❌ NEVER mismatch icon semantics (Percent for time, Clock for percentages, etc.).
- ❌ NEVER use the full horizontal marketing logo as the favicon — call `/favicon-builder`.
- ❌ NEVER skip `metadata.title.absolute` — your LP will inherit the template suffix.
- ❌ NEVER reach for `framer-motion` — the package is `motion`, imports from `motion/react`.
