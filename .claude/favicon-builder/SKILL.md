---
name: favicon-builder
description: 
---

## 1. Implementation patterns (Next.js 15 App Router)

Next.js App Router auto-detects icon files in `src/app/` and emits the correct `<link rel="icon">` tags into `<head>`. You do not write the link tag yourself — and if you do, you'll get duplicates or conflicts.

**File placement:**

```
src/app/
├── icon.svg          ← favicon, all sizes (Next resamples)
├── apple-icon.svg    ← Apple touch icon (canonical 180×180, same SVG works)
└── layout.tsx        ← do NOT add <link rel="icon"> here
```

That's it. No `public/favicon.ico` needed. No manifest changes. No metadata config.

**SVG conventions for crisp rendering:**

- `viewBox="0 0 256 256"` — clean math, divides evenly into 16/32/64/128
- `role="img"` and `aria-label="<Brand Name>"` for screen readers and Lighthouse
- One `<svg>` element, no external references, no embedded raster images
- Inline everything (gradients, masks) inside `<defs>` — no external CSS

**`apple-icon.svg`:** the canonical size is 180×180, but the same SVG file works because Next resamples it. You can keep one source of truth for both files (or symlink them if you're feeling clever — but a plain copy is fine and survives `git mv` operations better).

**Working code example** — the favicon shipped for Profits Guru:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" role="img" aria-label="Profits Guru">
  <!-- Brand round background -->
  <circle cx="128" cy="128" r="128" fill="#0F172A"/>

  <!-- Subtle inner highlight -->
  <circle cx="128" cy="118" r="116" fill="url(#hi)" opacity="0.18"/>

  <defs>
    <linearGradient id="hi" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#10B981"/>
      <stop offset="100%" stop-color="#10B981" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="arrowGrad" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0%" stop-color="#10B981"/>
      <stop offset="100%" stop-color="#34D399"/>
    </linearGradient>
  </defs>

  <!-- Chart line (white) connecting data points -->
  <path d="M 60 180 L 100 150 L 132 170 L 168 118"
        stroke="#FFFFFF"
        stroke-width="11"
        stroke-linecap="round"
        stroke-linejoin="round"
        fill="none"/>

  <!-- White data point dots -->
  <circle cx="60"  cy="180" r="11" fill="#FFFFFF"/>
  <circle cx="100" cy="150" r="11" fill="#FFFFFF"/>
  <circle cx="132" cy="170" r="11" fill="#FFFFFF"/>

  <!-- Green arrow stem going up-right (gradient for life) -->
  <path d="M 168 118 L 210 76"
        stroke="url(#arrowGrad)"
        stroke-width="22"
        stroke-linecap="round"
        fill="none"/>

  <!-- Arrow head (chevron) -->
  <path d="M 182 76 L 212 76 L 212 106"
        stroke="url(#arrowGrad)"
        stroke-width="22"
        stroke-linecap="round"
        stroke-linejoin="round"
        fill="none"/>
</svg>
```

Notice: the chart-line stroke is `11` (4.3% of 256, the minimum that survives 16px), the arrow stroke is `22` (8.6%, much safer). The arrow is the dominant element on purpose — at 16px the chart line nearly disappears, but the chevron still reads as "up and to the right."


## 2. Design rules

These are not opinions. These are the rules that decide whether your favicon reads at 16×16 or turns into a gray smudge.

**ONE recognizable element from the brand mark.** Pick the most distinctive shape and drop everything else. An arrow. A chart spike. A single dot. A letterform. Full logos with wordmarks die at 16px — they become a horizontal smear of pixels.

**Round background = strong visual containment.** A filled circle gives the icon a clean silhouette against any browser chrome (light Safari toolbar, dark Chrome incognito, Firefox sidebar). Square-rounded works too. Avoid transparent backgrounds — they look weak on light chrome and disappear on dark.

**Stroke widths must be substantial.** Target 8–10% of the viewBox dimension. For `viewBox="0 0 256 256"`, that's strokes between 20 and 25. Anything below 11px will visually vanish at 16×16 — the rasterizer rounds it to under a pixel. If you must use a thin stroke for a secondary detail (like the Profits Guru chart line at 11), make sure the primary element is at 8%+ so the icon still reads when the thin stroke disappears.

**NEVER text.** Not initials. Not a single letter. Not even a stylized monogram. By the time the browser rasterizes it to 16px, the letter shapes are mush. Use the brand's logomark instead, or a geometric stand-in.

**2–3 colors max.** Brand color + background + one accent. More than that and the favicon looks like a Christmas ornament at small sizes.

**Linear gradients OK** for life and dimension — 2 stops max, kept inside a single shape. Gradients survive rasterization better than fine details because the eye reads the color shift even if individual pixels blur.

**Test at 16×16 and 32×32.** Open the SVG in a browser, zoom out, squint. If you can't tell what it is at 16px from arm's length, redesign.


## 3. Common pitfalls

- **Shipping the full marketing logo as a PNG** — wordmarks unreadable, file 50× bigger than needed
- **Stroke widths under 8% of viewBox** — primary shapes vanish at 16px
- **Too many elements** — five icons stacked into one space, all illegible
- **Text inside the favicon** — initials, "A", any letterform, any abbreviation
- **Missing `aria-label`** — Lighthouse accessibility warning, screen readers announce nothing
- **Manual `<link rel="icon">` in `layout.tsx` `<head>`** — conflicts with App Router auto-detection, sometimes the manual one wins, sometimes the auto one does, you don't know until production
- **Transparent backgrounds** — looks weak on light browser chrome, vanishes against dark sidebar UIs
- **Leaving the Next.js default `favicon.ico` in `src/app/`** — it has higher precedence than `icon.svg` in some Next versions; delete it
- **Using `viewBox="0 0 100 100"` or odd dimensions** — pixel math gets fractional, edges look fuzzy. Stick with 256.


## 4. Workflow when invoked

1. **Read the user's brand mark** — ask for the logo file, or look in `public/`, `assets/`, or the design system. If there's no brand mark yet, ask for brand colors and one concept word ("data", "speed", "trust", "growth").
2. **Identify ONE distinctive shape** — the silhouette that survives if you strip everything else. An arrow direction, a unique angle, a dot pattern. Verbalize the choice to the user before drawing.
3. **Pick the background style:**
   - Round dark — premium, finance, B2B SaaS, dashboards
   - Round light — consumer, friendly, lifestyle
   - Square rounded — playful, app-like, often with a strong color block
4. **Sketch SVG with `viewBox="0 0 256 256"`** — single `<svg>` element, inline defs, no external refs
5. **Write to `src/app/icon.svg`** — confirm the path before writing; if it's a non-standard Next layout (e.g., `app/` at repo root, or `frontend/src/app/`), adapt
6. **Create matching `apple-icon.svg`** — same content, same file. Copy, don't symlink (better git/deploy behavior)
7. **Remove any old manual `<link rel="icon">` tags** — grep `layout.tsx`, `_document.tsx`, `app.tsx`, `index.html` and rip out any manual icon links so App Router auto-detection wins cleanly
8. **Remove leftover `favicon.ico`** — if there's a default one in `src/app/` or `public/`, delete it (it'll override the SVG in some Next versions)
9. **Take a screenshot at 32×32** if a browser or rasterizer is available — open the SVG, zoom to 32×32, capture. Otherwise just open it in the browser tab and squint
10. **Report to user** — list the files written, paste the design rationale ("we used X shape from your mark because Y"), and prompt them to hard-refresh their dev server (browsers cache favicons aggressively — `Cmd+Shift+R` or open in incognito)


## 5. Reference: the Profits Guru build

**Design:** round dark background (`#0F172A`, the same slate used across the LP), three white dots connected by a thin white chart line rising left to right, then an emerald gradient (`#10B981 → #34D399`) arrow chevron breaking out of the chart and pointing up-right.

**Concept in one sentence:** "Data → growth" in one shape. The dots and line establish the data context; the arrow chevron is the payoff. At 16×16 the chart line nearly disappears, but the round dark badge with a green arrow chevron is still unmistakably "this is the growth-up thing," which is the brand promise.

**Why it works:**
- Dark round badge gives strong containment on any chrome
- The arrow is the dominant element (22px stroke, 8.6% of viewBox), so it survives 16px
- The chart line is intentionally secondary (11px stroke) — it adds richness at 32px+ where it's visible, and disappearing at 16px is fine because the arrow still reads
- Two colors plus white — emerald, slate, white. No noise.
- The subtle top highlight (`#10B981` at 18% opacity, fading down) gives the badge a hint of dimension without becoming a "3D" cliché

This is the canonical example for the skill. When you're stuck, mimic the structure: round dark badge + one strong geometric shape + minimal secondary detail.


## 6. Hard rules — never violate

- ❌ Don't include text, letters, initials, or monograms in the favicon
- ❌ Don't use strokes thinner than 8% of the viewBox for the primary element
- ❌ Don't manually add `<link rel="icon">` in a Next.js App Router project — let auto-detection handle it
- ❌ Don't ship without testing at 16×16 (browser zoom out + squint test)
- ❌ Don't leave the default `favicon.ico` in `src/app/` when you add `icon.svg` — delete it
- ❌ Don't use transparent backgrounds for production favicons — they look weak on light chrome
- ❌ Don't use more than 3 colors or more than 2 gradient stops
- ✅ Always use SVG over PNG for favicons in modern Next.js — smaller, sharper, scalable
- ✅ Always include `role="img"` + `aria-label="<Brand Name>"` on the root `<svg>`
- ✅ Always simplify to ONE recognizable element from the brand mark
- ✅ Always use `viewBox="0 0 256 256"` unless there's a specific reason not to
- ✅ Always copy `icon.svg` to `apple-icon.svg` so iOS Safari and Add-to-Home-Screen get a clean asset


## Sibling skill

`/landing-page-builder` is a sibling skill that includes a favicon step as part of the full LP shipping checklist. If you're building a landing page end-to-end, start there and this skill will be invoked at the right moment. If you only need to fix or design the favicon on an existing site, invoke this skill directly.
