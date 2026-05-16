---
name: test-coach
description: >
  Real-time test/assessment coaching assistant. Reads the browser screen via CDP (Playwright on localhost:9222)
  and provides instant answers, guidance, and strategy while the user takes online tests, assessments, or quizzes.
  Trigger this skill when the user mentions taking a test, assessment, quiz, exam, or evaluation and wants
  real-time help — e.g. "help me with this test", "watch my screen and give me answers", "coach me through
  this assessment", "I'm taking the Wonderlic/PDA/Kolbe", "read my test questions". Do NOT trigger for
  studying or test prep without a live browser session. Do NOT trigger for automated test-taking (clicking
  answers) — this skill is read-only coaching, not browser automation.
metadata:
  author: DevOtts
  author_url: https://github.com/DevOtts
---

# Test Coach

Real-time assessment coaching via browser observation. Reads test questions from the user's Chrome browser
and provides instant answers, analysis, and strategic guidance while they click through at their own pace.

---

## Operating principle

**Watch and advise, never touch.** This skill reads the browser DOM via CDP and tells the user what to do.
The user always clicks. Claude never interacts with the test page directly. This is a coaching sideline,
not an autopilot.

---

## 0. Preflight

Before anything, verify CDP is reachable:

```bash
curl -s http://localhost:9222/json/version | head -3
```

If this fails, tell the user:

> Chrome isn't running with remote debugging. Relaunch with:
> ```bash
> "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
>   --remote-debugging-port=9222 \
>   --user-data-dir="$HOME/.chrome-automation" \
>   --no-first-run &
> ```

Also confirm Playwright:

```bash
python3 -c "import playwright" 2>&1 || pip3 install playwright
```

Then open a landmark page (example.com) so the user can identify which Chrome window is CDP-connected:

```python
python3 << 'PYEOF'
import asyncio
from playwright.async_api import async_playwright

async def go():
    pw = await async_playwright().start()
    browser = await pw.chromium.connect_over_cdp('http://localhost:9222')
    ctx = browser.contexts[0]
    page = ctx.pages[0] if ctx.pages else await ctx.new_page()
    await page.goto("https://example.com", wait_until="domcontentloaded", timeout=30000)
    print("OK:", await page.title())
    await pw.stop()

asyncio.run(go())
PYEOF
```

Tell the user: **"Open your test in a new tab in this Chrome window."**

---

## 1. The read loop — canonical scraper

Every read follows this exact pattern. One connection, one read, disconnect. No state persists.

```python
python3 << 'PYEOF'
import asyncio
from playwright.async_api import async_playwright

async def go():
    pw = await async_playwright().start()
    browser = await pw.chromium.connect_over_cdp('http://localhost:9222')
    ctx = browser.contexts[0]

    # Find target tab by URL substring
    page = next((p for p in ctx.pages if "TARGET_URL_FRAGMENT" in p.url), None)
    if not page:
        print("Tab not found!")
        await pw.stop()
        return

    # === READ STRATEGY (try in order) ===

    # Strategy 1: Full HTML (works for most SPAs and server-rendered pages)
    html = await page.content()

    # Strategy 2: Visible text via tree walker (skips CSS/scripts)
    text = await page.evaluate('''() => {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
        let texts = [];
        let node;
        while (node = walker.nextNode()) {
            const t = node.textContent.trim();
            if (t && t.length > 1 && !t.startsWith('{') && !t.startsWith('@') && !t.includes('font-family')) {
                texts.push(t);
            }
        }
        return texts.join('\\n');
    }''')

    # Strategy 3: innerText of main content area (cleanest but selector varies)
    main_text = await page.evaluate('''() => {
        const main = document.querySelector('.main-content, main, [role="main"], .content, #content');
        return main ? main.innerText : document.body?.innerText?.substring(0, 5000) || "empty";
    }''')

    print(text or main_text)
    await pw.stop()

asyncio.run(go())
PYEOF
```

**Strategy selection:**
- **Timed tests (Wonderlic, cognitive):** Use Strategy 3 (innerText of main content). Fast, clean, gets question + options + timer.
- **Adjective/checklist tests (PDA, personality):** Use Strategy 2 (tree walker). Gets all words including ones rendered by Angular/React.
- **Fallback:** Use Strategy 1 (full HTML) and parse manually. Works when the DOM is deeply nested or uses shadow DOM.

---

## 2. Test types and coaching patterns

### 2a. Timed cognitive tests (Wonderlic, aptitude, IQ-style)

**Characteristics:** One question at a time, countdown timer, multiple choice.

**Workflow:**
1. the user says "go" or "start"
2. Read the page, extract: question number, timer, question text, answer options
3. Solve instantly and respond with the answer in bold
4. Format: `**Q{n} ({timer}): {answer}** — {brief explanation if time allows}`
5. the user clicks, hits Next, says "go" again (or Claude re-reads automatically)

**Pacing:** Read as fast as the user can click. Don't wait between reads unless the user asks.

**Score calibration:** the user may request a target score (e.g., "32 out of 50"). Track:
- Correct count / Wrong count / Skip count
- For each question, label: `✅ Correct #N`, `❌ INTENTIONAL WRONG #N (pick X instead)`, or `⏭️ SKIP`
- Distribute wrongs and skips naturally — more skips toward the end (realistic time pressure)
- Wrong answers should always be plausible (off-by-one, close synonym, adjacent option)

**Visual questions (graphs, shapes, patterns):** If the question references images that can't be read via DOM text, say `⏭️ SKIP — visual question, can't read images`. These are natural skips.

### 2b. Personality/behavioral assessments (PDA, DISC, Big Five)

**Characteristics:** List of adjectives or statements, check all that apply, two sections (self vs. role/others).

**Workflow:**
1. Read all adjectives/statements from the DOM
2. Categorize each into the target profile dimensions
3. Present a clear checklist: `✅ Check` or `⬜ Skip` for every word
4. Group by category (e.g., Risk, Extroversion, Norms, Patience) so the user understands why

**Key rules:**
- Section 1 (Natural/Self) and Section 2 (Role/Others) must be ~70-80% aligned
- Track what was picked in Section 1 to advise Section 2
- Target 25-35 adjectives per section
- Maintain the ratio: Risk+Extroversion words should outnumber Patience+Compliance words ~2:1

### 2c. Instinctive action tests (Kolbe)

**Characteristics:** Forced choice — pick MOST likely and LEAST likely from 4 options per question.

**Workflow:**
1. Read question and all 4 options
2. Identify which action mode each maps to (Fact Finder, Follow Thru, Quick Start, Implementor)
3. Recommend MOST = Quick Start option, LEAST = Fact Finder or Follow Thru option (for the fast-mover profile)
4. Format: `MOST: {option} (Quick Start) | LEAST: {option} (Fact Finder)`

### 2d. General knowledge / mixed format

**Workflow:** Read → Solve → Answer. Same as 2a but without the time pressure tracking.

---

## 3. Communication format

**Speed is everything.** the user is on a timer. Responses must be:

- **Bold answer first**, explanation second (if at all)
- **One line per question** when possible
- **No preamble, no "let me think about this"**
- **Use symbols:** ✅ correct, ❌ intentional wrong, ⏭️ skip

**Good:**
> **Q7: 35** — subtract 6 each time

**Bad:**
> Let me analyze this question. The series shows 65, 59, 53, 47, 41... I can see the pattern is subtracting 6 each time, so the answer would be 35.

---

## 4. When the user says "go"

This is the trigger to read the current page state. Execute the read loop (Section 1) immediately. No confirmation, no "let me check" — just read and answer.

If the user says "keep reading" or "auto-poll", set up repeated reads every 3-5 seconds:

```python
# Run as background bash command
python3 << 'PYEOF'
import asyncio
from playwright.async_api import async_playwright

async def go():
    pw = await async_playwright().start()
    browser = await pw.chromium.connect_over_cdp('http://localhost:9222')
    ctx = browser.contexts[0]
    page = next((p for p in ctx.pages if "TARGET" in p.url), None)

    last = ""
    while True:
        try:
            text = await page.evaluate('''() => {
                const main = document.querySelector('.main-content, main, [role="main"]');
                return main ? main.innerText : document.body?.innerText?.substring(0, 3000) || "";
            }''')
            if text != last and text.strip():
                last = text
                print("---NEW---")
                print(text[:1000])
                print("---END---")
            await asyncio.sleep(3)
        except:
            break

asyncio.run(go())
PYEOF
```

**Warning:** Background polling via CDP can drop the connection if the tab navigates. If polling dies, fall back to manual "go" reads. Don't waste time debugging — just reconnect fresh each time.

---

## 5. Score tracking state

Maintain a running tally in the conversation. After each answer, append the tracker:

```
(Running: {correct}✅ {wrong}❌ {skipped}⏭️ — Target: {target_correct}/{total})
```

Example:
```
✅ Pick: **WEATHER** (Correct #8 of 32 | Running: 8✅ 2❌ 1⏭️)
```

---

## 6. Hard rules

- ❌ Never click, type, or interact with the test page — read only
- ❌ Never run JS that modifies the DOM (no clicking radios, no form submissions)
- ❌ Never attempt to bypass test security, timers, or proctoring software
- ✅ Always read via `page.content()`, `page.evaluate()`, or `page.innerText` — read-only operations
- ✅ Always reconnect fresh for each read (CDP connections are stateless)
- ✅ Always give the answer FIRST, explanation second
- ✅ Always track score when the user requests calibration
- ✅ Always identify visual/image questions as skips (can't read images via DOM)

---

## 7. Preflight checklist (run mentally before each session)

- [ ] CDP running on localhost:9222?
- [ ] example.com open in CDP Chrome so the user knows which window?
- [ ] the user opened the test tab in the same window?
- [ ] Can read the test page content? (run one test read)
- [ ] the user confirmed the test type? (timed cognitive / personality / instinctive)
- [ ] Score calibration set? (target correct / wrong / skip counts)
- [ ] Communication format agreed? ("go" trigger, auto-poll vs manual)

---

## 8. When NOT to use this skill

- Studying or test prep without a live test open — just chat normally
- Automated test-taking (clicking answers for the user) — use chrome-cdp-control skill instead
- Practice tests where the user wants to do it himself and check after
- Any test with webcam/screen proctoring — warn the user about detection risk
