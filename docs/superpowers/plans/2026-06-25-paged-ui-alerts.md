# Paged UI + Escalating Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the T-Display S3's single Mango dashboard into a 5-page paged UI (Usage, Model health, History, Device & network, Big clock) with escalating visual alerts, without changing any other board.

**Architecture:** A `currentPage` index in `main.cpp` plus a `uiRenderPage()` switch in `ui.cpp` that reuses the existing imperative draw helpers — no new framework. Everything is gated behind a new `PAGED_UI` compile flag (`MANGO_UI && BOARD_TDISPLAY_S3`) so M5StickC Plus and the Clarity boards keep their current single dashboard byte-for-byte. Alerts are visual only (the S3 has no buzzer/LED).

**Tech Stack:** ESP32-S3 / Arduino framework / PlatformIO, TFT_eSPI, C++11. Spec: [`../specs/2026-06-25-paged-ui-alerts-design.md`](../specs/2026-06-25-paged-ui-alerts-design.md).

## Global Constraints

- **Board scope:** every change is gated behind `PAGED_UI` (≡ `defined(MANGO_UI) && defined(BOARD_TDISPLAY_S3)`). M5StickC Plus (`MANGO_UI`, non-S3) and Clarity boards (no `MANGO_UI`) must compile and behave exactly as before.
- **Do not touch** `api.cpp`, `crypto.cpp`, `certs.cpp` — the 2026-06-25 security audit (egress/TLS/token handling) depends on them being unchanged. No new network egress; no new credential surface.
- **Device contacts only** `api.anthropic.com`, `status.claude.com`, NTP. This plan adds none.
- **Thresholds & timezone are hardcoded** in `config.h` (`ALERT_WARN_PCT 50`, `ALERT_CRIT_PCT 80`, UTC+7) — not portal fields. Green `<50`, amber `50–79`, red `≥80`.
- **Default GFX font is ASCII-only** (codepoints 32–126). Do not draw Unicode glyphs (▲, •, ◕) as text — use ASCII or drawn primitives (`fillCircle`, `drawLine`).
- **Naming:** complete words for functions/variables (project rule). Header title string is exactly `ARMNO'S CLAUDEOMETER`.
- **Commits require the user's explicit go-ahead** (project git rule). Commit messages are one line, no `Co-Authored-By`. The commit step in each task is the *intended* commit — run it only once the user approves.

## Testing reality

This repo has **no unit-test harness**; firmware is verified on hardware. The board is **not yet ordered**, so:

- **Per-task hard gate:** `pio run -e tdisplay-s3` compiles cleanly (needs no board). Also build one non-paged board to prove isolation: `pio run -e m5stick-cplus` (or the env present in `platformio.ini`).
- **On-device verification is deferred** until the board arrives. Each task lists the manual checks to run then; they map to the spec's Verification section.

## File structure

| File | Responsibility | Change |
| ---- | -------------- | ------ |
| `src/config.h` | Build flags, thresholds, version | Add `PAGED_UI`, `ALERT_*`; bump `FW_VERSION` |
| `src/ui.h` | UI public interface | Add `UiPage` enum + paged/alert function decls (under `PAGED_UI`) |
| `src/ui.cpp` | All rendering | Add page functions + dispatchers; rework S3 mascots to 2×2; extend `barColor`; alert header; remove dead S3 branches from `uiDashboard`/`uiDashboardClock` |
| `src/main.cpp` | Boot, loop, button handling, refresh | `currentPage` state; new button handler; page-aware blink + 10s tick; alert level + edge flash; UTC+7 |
| `src/history.h` / `src/history.cpp` | RAM ring buffer of 5h utilization + 7d trend | **New module** (Task 3) |

---

## Task 1: Paging foundation + Usage / Model split (Phase 1)

Delivers: on the S3, Button A pages between **Usage (0)** and **Model health (1)**; usage and mascots no longer share a screen; the mascots render as a larger 2×2 grid on their own page. No new data sources. After this task the firmware is shippable as `2.2.0`.

**Files:**
- Modify: `src/config.h` (add `PAGED_UI`, bump `FW_VERSION`)
- Modify: `src/ui.h` (enum + decls)
- Modify: `src/ui.cpp` (2×2 mascots; new page block; remove dead S3 branches)
- Modify: `src/main.cpp` (`currentPage`, button handler, blink gate, 10s tick, refresh render)

**Interfaces:**
- Consumes (existing, unchanged): `drawBar`, `drawStatusPanel`, `drawResetRow`, `drawResetValues`, `drawHeaderRight`, `drawMascot`, `mascotEdge`, `fmtCountdown`, `uiToggleRotation`, `uiSetModelStatus`, `uiBlinkTick`, `halClear`, `halFlush`, `halBatPercent`, `UsageData`, `ModelStatus`.
- Produces (new public API in `ui.h`, all under `PAGED_UI`):
  - `enum UiPage { UI_PAGE_USAGE, UI_PAGE_MODELS, UI_PAGE_COUNT };`
  - `void uiRenderPage(uint8_t page, const UsageData& data, unsigned long lastFetchMs, int rssi, int batPct);`
  - `void uiRenderPageClock(uint8_t page, const UsageData& data, unsigned long lastFetchMs, int rssi);`
  - `uint8_t uiPageCount();` — returns `UI_PAGE_COUNT`.

- [ ] **Step 1: Add the `PAGED_UI` flag + alert thresholds, and bump the version in `config.h`**

In `src/config.h`, change the version line (line 4):

```c
#define FW_VERSION              "2.2.0"  // Mango — shown on the Mango boot screen
```

Then add, immediately after the existing feature-flags comment block (after line 65, the end of the `MANGO_UI` comment):

```c
// PAGED_UI — multi-page navigation + escalating alerts, T-Display S3 only.
// Implies MANGO_UI. Gates every paged-UI / alert change so M5StickC Plus and the
// Clarity boards keep their single dashboard unchanged.
// See docs/superpowers/specs/2026-06-25-paged-ui-alerts-design.md
#if defined(MANGO_UI) && defined(BOARD_TDISPLAY_S3)
  #define PAGED_UI
#endif

// ── Alerts (paged UI) ────────────────────────────────────
// Utilization bands: green < WARN, amber WARN..CRIT-1, red >= CRIT. Defined in the
// foundation because both the alert logic (Task 2) and the Device readout (Task 4) read
// them. WARN=50 mirrors the compact-at-50% habit on a 1M-context session; CRIT=80 = act now.
#define ALERT_WARN_PCT          50
#define ALERT_CRIT_PCT          80
```

(The defines are unused until Task 2 wires them in — harmless to land them now.)

- [ ] **Step 2: Declare the paged-UI interface in `ui.h`**

In `src/ui.h`, inside the existing `#ifdef MANGO_UI` block (before its `#endif // MANGO_UI` at line 25), add:

```c
#ifdef PAGED_UI
// Multi-page UI (T-Display S3). Pages are dispatched internally by uiRenderPage;
// main.cpp drives navigation via currentPage and uiPageCount().
enum UiPage { UI_PAGE_USAGE, UI_PAGE_MODELS, UI_PAGE_COUNT };
uint8_t uiPageCount();
// Full draw of one page (clears + header + body). Replaces uiDashboard on the S3.
void uiRenderPage(uint8_t page, const UsageData& data, unsigned long lastFetchMs, int rssi, int batPct);
// In-place time tick for the current page (no full clear) — replaces uiDashboardClock.
void uiRenderPageClock(uint8_t page, const UsageData& data, unsigned long lastFetchMs, int rssi);
#endif // PAGED_UI
```

- [ ] **Step 3: Rework the S3 mascot geometry to a 2×2 grid in `ui.cpp`**

The S3 mascots currently render as a single bottom row (the leftover space under the bars). Page 1 gives them the whole screen as a 2×2 grid. `drawStatusPanel` and `uiBlinkTick` both derive geometry from these constants, so they stay in sync.

In `src/ui.cpp`, **replace** the mascot-geometry defines (lines 458–465, from `#define MASCOT_W` through `#define MASCOT_X(i) ...`; **keep** `RESET_CAP_Y`/`RESET_VAL_Y` at 456–457 untouched) with:

```c
// Page 1 (Model health): the four Clawds own the whole screen as a 2x2 grid,
// each larger than the old dashboard row. drawStatusPanel + uiBlinkTick share
// these so their coordinates never drift apart.
#define MASCOT_W        70                // fractional ~3.9px cells via mascotEdge
#define MASCOT_RH       8                 // row height -> 40px tall
#define MASCOT_COL0_CX  80                // left-column centre
#define MASCOT_COL1_CX  240               // right-column centre
#define MASCOT_ROW0_Y   34                // top-row mascot top
#define MASCOT_ROW1_Y   104               // bottom-row mascot top
#define MASCOT_NAME_DY  46                // name baseline, below the mascot top
static inline int mascotCol(int i) { return (i % 2 == 0) ? MASCOT_COL0_CX : MASCOT_COL1_CX; }
static inline int mascotRow(int i) { return (i < 2)      ? MASCOT_ROW0_Y  : MASCOT_ROW1_Y;  }
#define MASCOT_X(i) (mascotCol(i) - MASCOT_W / 2)
```

Then **replace** `drawStatusPanel` (the S3 version, lines 492–508) with:

```c
static void drawStatusPanel(TFT_eSPI& g) {
    static const char* names[4] = {"HAIKU", "SONNET", "OPUS", "FABLE"};
    bool up[4] = {s_modelStatus.haikuUp, s_modelStatus.sonnetUp,
                  s_modelStatus.opusUp,  s_modelStatus.fableUp};
    bool anyDown = false;
    for (int i = 0; i < 4; i++) {
        int cx = mascotCol(i), my = mascotRow(i);
        // Unknown (never fetched) renders gray without X eyes, so a status-page
        // outage is never mistaken for a model outage.
        bool dead = s_modelStatus.ok && !up[i];
        anyDown = anyDown || dead;
        uint16_t col = (!s_modelStatus.ok || dead) ? C_DIM : MASCOT_COLORS[i];
        drawMascot(g, cx - MASCOT_W / 2, my, MASCOT_W, MASCOT_RH, col, dead);
        g.setTextColor(C_DIM, C_BG);
        g.setTextSize(1);
        g.setCursor(cx - (int)strlen(names[i]) * 3, my + MASCOT_NAME_DY);
        g.print(names[i]);
    }
    const char* summary = !s_modelStatus.ok ? "status unknown"
                        : anyDown            ? "incident: model affected"
                                             : "all models operational";
    g.setTextColor(C_DIM, C_BG);
    g.setTextSize(1);
    g.setCursor((SCREEN_W - (int)strlen(summary) * 6) / 2, 160);
    g.print(summary);
}
```

Then **replace** the S3 `uiBlinkTick` (lines 512–530) with the 2×2-aware version:

```c
void uiBlinkTick(bool closed) {
    bool up[4] = {s_modelStatus.haikuUp, s_modelStatus.sonnetUp,
                  s_modelStatus.opusUp,  s_modelStatus.fableUp};
    for (int i = 0; i < 4; i++) {
        if (!s_modelStatus.ok || !up[i]) continue;   // dead/unknown don't blink
        int mx = mascotCol(i) - MASCOT_W / 2;
        int ey = mascotRow(i) + MASCOT_RH;            // eye row 1
        for (int e = 0; e < 2; e++) {
            int ex = mx + mascotEdge(CLAWD_EYE_COLS[e], MASCOT_W);
            int ew = mascotEdge(CLAWD_EYE_COLS[e] + 1, MASCOT_W) -
                     mascotEdge(CLAWD_EYE_COLS[e], MASCOT_W);
            if (closed) {
                lcd.fillRect(ex, ey, ew, MASCOT_RH, MASCOT_COLORS[i]);     // lid down
                lcd.fillRect(ex, ey + MASCOT_RH / 2 - 1, ew, 2, C_BG);     // shut line
            } else {
                lcd.fillRect(ex, ey, ew, MASCOT_RH, C_BG);                 // eye open
            }
        }
    }
}
```

- [ ] **Step 4: Add the page functions + dispatchers in `ui.cpp`**

Insert this block immediately **before** `#endif // MANGO_UI` (line 646). At this point every helper it uses is already defined and, under `PAGED_UI` (⟹ `BOARD_TDISPLAY_S3`), the S3 versions of `drawStatusPanel`/`drawResetRow`/`drawResetValues` are the ones compiled.

```c
#ifdef PAGED_UI
// ── Paged UI (T-Display S3) ─────────────────────────────────────────────────
// Each page clears, draws the shared top bar, draws its body, and flushes. The S3
// draws straight to the panel (no off-screen sprite — that path is CrowPanel only).

uint8_t uiPageCount() { return UI_PAGE_COUNT; }

// Orange header band: title on the left, status cluster (wifi/batt/ago) on the right.
static void drawTopBar(TFT_eSPI& g, int rssi, unsigned long ago, int batPct) {
    g.fillRect(0, 0, SCREEN_W, SY(18), C_HEAD);
    g.setTextColor(C_TEXT, C_HEAD);
    g.setTextSize(TS(1));
    g.setCursor(SX(4), SY(5));
    g.print("ARMNO'S CLAUDEOMETER");
    drawHeaderRight(g, rssi, ago, batPct);
}

static void uiPageUsage(const UsageData& data, unsigned long lastFetchMs, int rssi, int batPct) {
    auto& g = lcd;
    halClear(C_BG);
    unsigned long ago = (millis() - lastFetchMs) / 1000;
    drawTopBar(g, rssi, ago, batPct);

    if (!data.ok) {
        g.setTextColor(C_CRIT, C_BG);
        g.setTextSize(TS(2));
        g.setCursor(SX(10), SY(35));
        g.print("ERROR");
        g.setTextSize(TS(1));
        g.setTextColor(C_DIM, C_BG);
        g.setCursor(SX(10), SY(60));
        g.print(data.error);
        g.setCursor(SX(10), SY(80));
        g.print("retrying automatically...");
        halFlush();
        return;
    }

    int barW = SCREEN_W - SX(20);
    char h5rst[16], d7rst[16];
    fmtCountdown(data.h5ResetEpoch, h5rst, sizeof(h5rst));
    fmtCountdown(data.d7ResetEpoch, d7rst, sizeof(d7rst));
    drawBar(g, SX(10), SY(24), barW, SY(10), data.h5, "5-HOUR");
    drawBar(g, SX(10), SY(52), barW, SY(10), data.d7, "7-DAY");
    drawResetRow(g, h5rst, d7rst);
    halFlush();
}

static void uiPageModels(const UsageData& data, unsigned long lastFetchMs, int rssi, int batPct) {
    auto& g = lcd;
    halClear(C_BG);
    unsigned long ago = (millis() - lastFetchMs) / 1000;
    drawTopBar(g, rssi, ago, batPct);
    drawStatusPanel(g);   // 2x2 grid + summary line
    halFlush();
}

void uiRenderPage(uint8_t page, const UsageData& data, unsigned long lastFetchMs, int rssi, int batPct) {
    switch (page) {
        case UI_PAGE_MODELS: uiPageModels(data, lastFetchMs, rssi, batPct); break;
        case UI_PAGE_USAGE:
        default:             uiPageUsage(data, lastFetchMs, rssi, batPct);  break;
    }
}

void uiRenderPageClock(uint8_t page, const UsageData& data, unsigned long lastFetchMs, int rssi) {
    auto& g = lcd;
    unsigned long ago = (millis() - lastFetchMs) / 1000;
    // Repaint the right half of the header band in place (the ago counter ticks).
    g.fillRect(SCREEN_W / 2, 0, SCREEN_W / 2, SY(18), C_HEAD);
    drawHeaderRight(g, rssi, ago, halBatPercent());
    if (page == UI_PAGE_USAGE && data.ok) {
        char h5rst[16], d7rst[16];
        fmtCountdown(data.h5ResetEpoch, h5rst, sizeof(h5rst));
        fmtCountdown(data.d7ResetEpoch, d7rst, sizeof(d7rst));
        drawResetValues(g, h5rst, d7rst);
    }
    halFlush();
}
#endif // PAGED_UI
```

- [ ] **Step 5: Remove the now-dead S3 branches from `uiDashboard` and `uiDashboardClock`**

On the S3, `main.cpp` now calls `uiRenderPage`/`uiRenderPageClock`, so the `BOARD_TDISPLAY_S3` branches inside `uiDashboard`/`uiDashboardClock` are dead. Remove them so there's one home for each layout (these are orphans this task created).

In `uiDashboard`, **replace** lines 913–925 (the `#ifdef MANGO_UI` … `drawStatusPanel(g);` … `#else`) with:

```c
#ifdef MANGO_UI
    // Tier S (M5StickC Plus): each reset countdown rides on its bar's label row.
    drawBar(g, SX(10), SY(24), barW, SY(10), data.h5, "5-HOUR", h5rst);
    drawBar(g, SX(10), SY(52), barW, SY(10), data.d7, "7-DAY",  d7rst);
    drawStatusPanel(g);
#else
```

In `uiDashboardClock`, **replace** lines 982–991 (the `#ifdef MANGO_UI` / `#ifdef BOARD_TDISPLAY_S3` … `#endif` / `#else`) with:

```c
#ifdef MANGO_UI
    // Tier S: the countdowns live on the bar rows; refresh just those slots.
    int barW = SCREEN_W - SX(20);
    drawResetSlot(g, SX(10), barW, SY(24), h5rst);
    drawResetSlot(g, SX(10), barW, SY(52), d7rst);
#else
```

(`drawResetRow`/`drawResetValues` stay defined under `BOARD_TDISPLAY_S3` — they're now called by the page functions instead.)

- [ ] **Step 6: Wire `currentPage`, the button handler, blink gate, and 10s tick in `main.cpp`**

Add the page-state global. After `static uint8_t brightness = DEFAULT_BRIGHTNESS;` (line 36):

```c
#ifdef PAGED_UI
static uint8_t currentPage = 0;   // UI_PAGE_* — Button A cycles, refresh() redraws
#endif
```

In `refresh()`, **replace** the final draw call (line 90, `uiDashboard(...)`) with:

```c
#ifdef PAGED_UI
    uiRenderPage(currentPage, usage, lastFetch, WiFi.RSSI(), halBatPercent());
#else
    uiDashboard(usage, lastFetch, WiFi.RSSI(), halBatPercent());
#endif
```

In `loop()`, **replace** the button block (lines 252–287, the whole `#ifdef MANGO_UI` … `#else` (Clarity) … `#endif`) with a three-way split that adds the paged handler and leaves the other two verbatim:

```c
#ifdef PAGED_UI
    // Tap A = next page; hold A (~600ms) = flip; B = brightness; A+B = refresh.
    // A solo action commits only after the combo window so B can still join; A is
    // then resolved on release (tap -> next) or at the hold threshold (flip).
    static unsigned long aPressAt = 0, bPressAt = 0;
    static bool aHandled = false;
    const unsigned long comboWindowMs = 350;
    const unsigned long holdMs = 600;
    if (halBtnAWasPressed()) { aPressAt = millis(); aHandled = false; }
    if (halBtnBWasPressed()) bPressAt = millis();

    if ((aPressAt && (bPressAt || halBtnBIsPressed())) ||
        (bPressAt && halBtnAIsPressed())) {
        aPressAt = bPressAt = 0;
        aHandled = true;
        refresh();
    } else if (aPressAt && !aHandled && millis() - aPressAt > holdMs) {
        aHandled = true;
        aPressAt = 0;
        uiToggleRotation();
        uiRenderPage(currentPage, usage, lastFetch, WiFi.RSSI(), halBatPercent());
    } else if (aPressAt && !aHandled && !halBtnAIsPressed() &&
               millis() - aPressAt > comboWindowMs) {
        aPressAt = 0;
        currentPage = (currentPage + 1) % uiPageCount();
        uiRenderPage(currentPage, usage, lastFetch, WiFi.RSSI(), halBatPercent());
    } else if (bPressAt && millis() - bPressAt > comboWindowMs) {
        bPressAt = 0;
        brightness = (brightness + 1) % 4;
        halSetBrightness(brightness);
    }
#elif defined(MANGO_UI)
    // A flips the screen 180°, B cycles brightness, A+B together = force refresh
    // (the Clarity Button-B action). A single press only commits after a short
    // window so the other button can still join to form the combo.
    static unsigned long aPressAt = 0, bPressAt = 0;
    const unsigned long comboWindowMs = 350;
    if (halBtnAWasPressed()) aPressAt = millis();
    if (halBtnBWasPressed()) bPressAt = millis();

    if ((aPressAt && (bPressAt || halBtnBIsPressed())) ||
        (bPressAt && halBtnAIsPressed())) {
        aPressAt = bPressAt = 0;
        refresh();
    } else if (aPressAt && millis() - aPressAt > comboWindowMs) {
        aPressAt = 0;
        uiToggleRotation();
        uiDashboard(usage, lastFetch, WiFi.RSSI(), halBatPercent());
    } else if (bPressAt && millis() - bPressAt > comboWindowMs) {
        bPressAt = 0;
        brightness = (brightness + 1) % 4;
        halSetBrightness(brightness);
    }
#else
    if (halBtnAWasPressed()) {
#ifdef BOARD_ESP32C3_OLED
        brightness = (brightness + 1) % 2; // on/off only — contrast change imperceptible
#else
        brightness = (brightness + 1) % 4;
#endif
        halSetBrightness(brightness);
    }

    if (halBtnBWasPressed()) {
        refresh();
    }
#endif
```

In `loop()`, **replace** the blink block (lines 293–305) so the mascots only blink on the Model page (their eye coordinates exist only there):

```c
#ifdef MANGO_UI
    // Healthy mascots blink every 2s (eyes shut for 150ms) to show liveness.
    static unsigned long lastBlink = 0;
    static bool eyesClosed = false;
#ifdef PAGED_UI
    bool blinkActive = (currentPage == UI_PAGE_MODELS);
#else
    bool blinkActive = true;
#endif
    if (eyesClosed && blinkActive && millis() - lastBlink > 150) {
        uiBlinkTick(false);
        eyesClosed = false;
    } else if (eyesClosed && !blinkActive) {
        eyesClosed = false;   // navigated away mid-blink: reset without drawing
    } else if (!eyesClosed && blinkActive && usage.ok && millis() - lastBlink > 2000) {
        uiBlinkTick(true);
        eyesClosed = true;
        lastBlink = millis();
    }
#endif
```

In `loop()`, **replace** the 10s redraw block (lines 307–313) with:

```c
    static unsigned long lastRedraw = 0;
    if (millis() - lastRedraw > 10000) {
        // Only time passed (not data) — update the clock/countdowns in place.
#ifdef PAGED_UI
        uiRenderPageClock(currentPage, usage, lastFetch, WiFi.RSSI());
#else
        uiDashboardClock(usage, lastFetch, WiFi.RSSI());
#endif
        lastRedraw = millis();
    }
```

- [ ] **Step 7: Compile both the paged board and a non-paged board**

Run: `pio run -e tdisplay-s3`
Expected: `SUCCESS`.

Run: `pio run -e m5stick-cplus` (use whichever non-S3 Mango/Clarity env exists in `platformio.ini`)
Expected: `SUCCESS` — proves the `PAGED_UI` gating left other boards untouched.

- [ ] **Step 8: Commit** *(only with the user's go-ahead)*

```bash
git add src/config.h src/ui.h src/ui.cpp src/main.cpp
git commit -m "feat: paged UI foundation + Usage/Model split (T-Display S3)"
```

**On-device verification (deferred until the board arrives) — spec items 2, 3, 8:**
- After PIN unlock the device lands on Usage (page 0).
- Tapping A walks Usage → Models → Usage. B still cycles brightness. A+B forces a refresh. Long-press A (~600ms) flips the screen.
- Both pages draw without clipping on 320×170; the orange header (title + wifi/batt/ago) shows on both.
- The four mascots render as a 2×2 grid on the Model page; healthy ones blink; the summary line reads "all models operational".
- A+B held at boot still factory-resets; B held at boot still opens the WiFi portal.

---

## Task 2: Escalating alerts (Phase 2)

Delivers: usage bars recolor green/amber/red by threshold (50/80); a header alert dot driven by the **5h window only** shows on **every** page; a downed model lights a distinct header marker on every page; crossing 80% (5h) flashes the screen once. Thresholds live in `config.h` from Task 1. Depends on Task 1 only.

**Files:**
- Modify: `src/ui.h` (alert decls)
- Modify: `src/ui.cpp` (`barColor` thresholds; alert state + flash; header dot/glyph)
- Modify: `src/main.cpp` (compute 5h level, set it, edge-triggered flash)

**Interfaces:**
- Consumes: `ALERT_WARN_PCT`/`ALERT_CRIT_PCT` (config.h, Task 1), `s_modelStatus` (file-static in `ui.cpp`), `C_OK`/`C_WARN`/`C_CRIT`, `drawHeaderRight`, `halClear`, `halFlush`.
- Produces (new public API in `ui.h`, under `PAGED_UI`):
  - `void uiSetAlertLevel(int level);` — 0 ok, 1 warn, 2 critical (5h level only).
  - `void uiAlertFlash();` — one full-screen red flash; the next `uiRenderPage` repaints over it.

- [ ] **Step 1: Declare the alert interface in `ui.h`**

Inside the `#ifdef PAGED_UI` block in `ui.h` (added in Task 1), add:

```c
// 5h alert level for the header dot + flash: 0 ok, 1 warn, 2 critical.
void uiSetAlertLevel(int level);
// One full-screen flash on the OK/warn -> critical crossing (edge-triggered by caller).
void uiAlertFlash();
```

- [ ] **Step 2: Make `barColor` threshold-aware in `ui.cpp`**

`barColor` is shared by all TFT boards, so the threshold behaviour is gated to `PAGED_UI`; every other board keeps the flat `C_TEXT`. **Replace** `barColor` (lines 333–335):

```c
static uint16_t barColor(float pct) {
#ifdef PAGED_UI
    if (pct >= ALERT_CRIT_PCT) return C_CRIT;
    if (pct >= ALERT_WARN_PCT) return C_WARN;
    return C_OK;
#else
    (void)pct;
    return C_TEXT;
#endif
}
```

- [ ] **Step 3: Add alert state + flash in `ui.cpp`**

After `s_modelStatus` is defined (line 385, inside `#ifdef MANGO_UI`), add:

```c
#ifdef PAGED_UI
static int s_alertLevel = 0;   // 0 ok, 1 warn, 2 critical
void uiSetAlertLevel(int level) { s_alertLevel = level; }
void uiAlertFlash() {
    halClear(C_CRIT);
    halFlush();
    delay(150);
    // The caller's next uiRenderPage repaints the page over this flash.
}
#endif
```

- [ ] **Step 4: Draw the header dot + model-down marker in `drawHeaderRight`**

`drawHeaderRight` runs on every page and is repainted on the 10s tick, so the dot stays fresh. At the **end** of `drawHeaderRight`, **replace** the ago print (lines 641–644):

```c
    char as[12];
    snprintf(as, sizeof(as), "%lus", ago);
    int agoX = x - 6 - (int)strlen(as) * 6;
    g.setCursor(agoX, 5);
    g.print(as);

#ifdef PAGED_UI
    // Usage alert dot (5h level only), left of the ago counter.
    int dotX = agoX - 12;
    if (s_alertLevel >= 2)      g.fillCircle(dotX, 9, 4, C_CRIT);
    else if (s_alertLevel >= 1) g.fillCircle(dotX, 9, 4, C_WARN);
    // Model-down marker — distinct from the usage dot, visible on every page.
    bool anyDown = s_modelStatus.ok &&
        (!s_modelStatus.haikuUp || !s_modelStatus.sonnetUp ||
         !s_modelStatus.opusUp  || !s_modelStatus.fableUp);
    if (anyDown) {
        g.setTextColor(C_CRIT, C_HEAD);
        g.setTextSize(1);
        g.setCursor(dotX - 18, 5);
        g.print("!M");
    }
#endif
```

- [ ] **Step 5: Compute the 5h level + edge-triggered flash in `main.cpp`**

Add a helper above `refresh()` (after `syncTime()`, before line 77):

```c
#ifdef PAGED_UI
static int alertLevelFor(float pct) {
    if (pct >= ALERT_CRIT_PCT) return 2;
    if (pct >= ALERT_WARN_PCT) return 1;
    return 0;
}
#endif
```

In `refresh()`, **insert** between `lastFetch = millis();` (line 89) and the render call added in Task 1:

```c
#ifdef PAGED_UI
    // Dot + flash track the 5h window only; the 7d bar colors itself on the Usage page.
    static int prevAlertLevel = 0;
    int level = usage.ok ? alertLevelFor(usage.h5) : 0;
    uiSetAlertLevel(level);
    if (level >= 2 && prevAlertLevel < 2) uiAlertFlash();   // fires once on the crossing
    prevAlertLevel = level;
#endif
```

(So `refresh()` now reads: `fetchUsage` → model status → `lastFetch = millis()` → 5h alert level + flash → `uiRenderPage`.)

- [ ] **Step 6: Compile**

Run: `pio run -e tdisplay-s3`
Expected: `SUCCESS`.

Run: `pio run -e m5stick-cplus`
Expected: `SUCCESS` (bars still flat `C_TEXT`; no dot).

- [ ] **Step 7: Commit** *(only with the user's go-ahead)*

```bash
git add src/ui.h src/ui.cpp src/main.cpp
git commit -m "feat: escalating visual alerts (bars, header dot, crit flash)"
```

**On-device verification (deferred) — spec items 4, 5:**
- Below 50% (5h): bars green, no header dot.
- Crossing 50% (5h): bar amber + amber dot on every page.
- Crossing 80% (5h): bar red, one full-screen flash, then a persistent red dot (no re-flash on later polls at the same level). Use a real/simulated high-utilization response.
- A downed model (build with `-D STATUS_TEST_DOWN='"opus"'`) shows X-eyes on the Model page **and** the `!M` marker in the header on every other page.

---

## Task 3: History page (Phase 3)

Delivers: a new page 2 with a 5h-utilization sparkline from a RAM ring buffer, the current 7d value, and a 7d trend arrow. Independent of Tasks 2/4/5.

**Files:**
- Create: `src/history.h`, `src/history.cpp`
- Modify: `src/ui.h` (enum: insert `UI_PAGE_HISTORY`)
- Modify: `src/ui.cpp` (`uiPageHistory`, dispatch case)
- Modify: `src/main.cpp` (push a sample in `refresh()`)

**Interfaces:**
- Produces (`history.h`):
  - `void historyPush(float h5pct, float d7pct);`
  - `uint16_t historyCount();`
  - `uint8_t historyAt(uint16_t i);` — `i` from 0 (oldest retained) to `count-1` (newest).
  - `int historyTrend();` — `-1` falling, `0` flat, `+1` rising (latest 7d vs previous 7d).
- Consumes: `historyCount`/`historyAt`/`historyTrend`, `drawTopBar`, `C_HEAD`/`C_HEAD_DK`/`C_DIM`/`C_TEXT`.

- [ ] **Step 1: Create `src/history.h`**

```c
#pragma once
#include <stdint.h>

// 5h-utilization ring buffer (RAM only; lost on reboot) plus a 7d trend, for the
// History page. The 7d trend retains just the previous 7d value — no second buffer.
void     historyPush(float h5pct, float d7pct);
uint16_t historyCount();
uint8_t  historyAt(uint16_t i);   // 0 = oldest retained .. count-1 = newest
int      historyTrend();          // -1 falling, 0 flat, +1 rising
```

- [ ] **Step 2: Create `src/history.cpp`**

```c
#include "history.h"

// ~100 samples ~= 3.3h at the 120s default poll — covers most of the 5h window.
#define HISTORY_CAP 100

static uint8_t  s_buf[HISTORY_CAP];
static uint16_t s_head  = 0;       // next write index
static uint16_t s_count = 0;
static bool     s_have7d = false;
static float    s_prev7d = 0.0f, s_cur7d = 0.0f;

static uint8_t clampPct(float p) {
    if (p < 0)   p = 0;
    if (p > 100) p = 100;
    return (uint8_t)(p + 0.5f);
}

void historyPush(float h5pct, float d7pct) {
    s_buf[s_head] = clampPct(h5pct);
    s_head = (s_head + 1) % HISTORY_CAP;
    if (s_count < HISTORY_CAP) s_count++;
    s_prev7d = s_have7d ? s_cur7d : d7pct;
    s_cur7d  = d7pct;
    s_have7d = true;
}

uint16_t historyCount() { return s_count; }

uint8_t historyAt(uint16_t i) {
    uint16_t start = (s_head + HISTORY_CAP - s_count) % HISTORY_CAP;  // oldest sample
    return s_buf[(start + i) % HISTORY_CAP];
}

int historyTrend() {
    float d = s_cur7d - s_prev7d;
    if (d >  0.5f) return 1;
    if (d < -0.5f) return -1;
    return 0;
}
```

- [ ] **Step 3: Insert `UI_PAGE_HISTORY` into the enum in `ui.h`**

**Replace** the enum line:

```c
enum UiPage { UI_PAGE_USAGE, UI_PAGE_MODELS, UI_PAGE_HISTORY, UI_PAGE_COUNT };
```

(`uiPageCount()` returns `UI_PAGE_COUNT`, which is now 3 — Button A's wrap widens automatically.)

- [ ] **Step 4: Add `uiPageHistory` + dispatch case in `ui.cpp`**

Add `#include "history.h"` near the top of `ui.cpp` (after `#include "hal.h"`, line 3).

Inside the `#ifdef PAGED_UI` block, add `uiPageHistory` (place it after `uiPageModels`):

```c
static void uiPageHistory(const UsageData& data, unsigned long lastFetchMs, int rssi, int batPct) {
    auto& g = lcd;
    halClear(C_BG);
    unsigned long ago = (millis() - lastFetchMs) / 1000;
    drawTopBar(g, rssi, ago, batPct);

    const int px = SX(10), py = SY(28), pw = SCREEN_W - SX(20), ph = SY(80);
    g.drawRect(px, py, pw, ph, C_HEAD_DK);

    uint16_t n = historyCount();
    if (n < 2) {
        g.setTextColor(C_DIM, C_BG);
        g.setTextSize(1);
        g.setCursor(px + 8, py + ph / 2 - 4);
        g.print("collecting samples...");
    } else {
        int prevX = 0, prevY = 0;
        for (uint16_t i = 0; i < n; i++) {
            int x = px + (int)((uint32_t)i * (pw - 1) / (n - 1));
            int y = py + ph - 1 - (int)((uint32_t)historyAt(i) * (ph - 2) / 100);
            if (i > 0) g.drawLine(prevX, prevY, x, y, C_HEAD);
            prevX = x; prevY = y;
        }
    }

    // 5h current value, and 7d value with an ASCII trend arrow (default font is ASCII-only).
    char buf[32];
    int tr = historyTrend();
    const char* arrow = (tr > 0) ? "^" : (tr < 0) ? "v" : "-";
    g.setTextSize(1);
    g.setTextColor(C_TEXT, C_BG);
    g.setCursor(px, py + ph + 8);
    snprintf(buf, sizeof(buf), "5H %.0f%%", data.h5);
    g.print(buf);
    g.setCursor(SCREEN_W / 2, py + ph + 8);
    snprintf(buf, sizeof(buf), "7D %.0f%% %s", data.d7, arrow);
    g.print(buf);

    halFlush();
}
```

In `uiRenderPage`, add the case (before the `default`):

```c
        case UI_PAGE_HISTORY: uiPageHistory(data, lastFetchMs, rssi, batPct); break;
```

- [ ] **Step 5: Push a sample on each successful refresh in `main.cpp`**

Add `#include "history.h"` after `#include "api.h"` (line 22) in `main.cpp`.

In `refresh()`, after `fetchUsage(token, usage);` (line 84):

```c
#ifdef PAGED_UI
    if (usage.ok) historyPush(usage.h5, usage.d7);
#endif
```

- [ ] **Step 6: Compile**

Run: `pio run -e tdisplay-s3`
Expected: `SUCCESS`.

- [ ] **Step 7: Commit** *(only with the user's go-ahead)*

```bash
git add src/history.h src/history.cpp src/ui.h src/ui.cpp src/main.cpp
git commit -m "feat: history page with 5h sparkline + 7d trend"
```

**On-device verification (deferred) — spec item 7:**
- A walks Usage → Models → History → Usage.
- History shows "collecting samples..." at first, then a sparkline that fills over successive polls; it resets to empty after a reboot. The 7d value shows with a `^`/`v`/`-` trend arrow.

---

## Task 4: Device & network page (Phase 4)

Delivers: a new page 3 of read-only stats, including the configured alert thresholds so the values in effect are visible without reflashing. Independent of Tasks 2/3/5 (the thresholds it shows live in `config.h` from Task 1).

**Files:**
- Modify: `src/ui.h` (enum: insert `UI_PAGE_DEVICE`)
- Modify: `src/ui.cpp` (`uiPageDevice`, dispatch case, `<WiFi.h>` include)

**Interfaces:**
- Consumes: `WiFi.localIP()`, `WiFi.SSID()`, `WiFi.RSSI()` (passed in as `rssi`), `millis()`, `ESP.getFreeHeap()`, `ESP.getFreePsram()`, `halBatPercent()` (passed in as `batPct`), `FW_VERSION`, `ALERT_WARN_PCT`/`ALERT_CRIT_PCT` (config.h, Task 1).

- [ ] **Step 1: Insert `UI_PAGE_DEVICE` into the enum in `ui.h`**

**Replace** the enum line:

```c
enum UiPage { UI_PAGE_USAGE, UI_PAGE_MODELS, UI_PAGE_HISTORY, UI_PAGE_DEVICE, UI_PAGE_COUNT };
```

- [ ] **Step 2: Add `uiPageDevice` + a key/value helper in `ui.cpp`**

Add `#include <WiFi.h>` near the top of `ui.cpp` (after `#include <time.h>`, line 4) so `WiFi.localIP()`/`SSID()` resolve.

Inside the `#ifdef PAGED_UI` block, add a row helper and the page (place after `uiPageHistory`):

```c
static int drawKV(TFT_eSPI& g, int y, const char* key, const char* val) {
    g.setTextSize(1);
    g.setTextColor(C_DIM, C_BG);  g.setCursor(SX(10), y); g.print(key);
    g.setTextColor(C_TEXT, C_BG); g.setCursor(SX(78), y); g.print(val);
    return y + SY(16);   // 9 rows from y=26 -> last at 154, clears the 170px panel
}

static void uiPageDevice(const UsageData& data, unsigned long lastFetchMs, int rssi, int batPct) {
    (void)data;
    auto& g = lcd;
    halClear(C_BG);
    unsigned long ago = (millis() - lastFetchMs) / 1000;
    drawTopBar(g, rssi, ago, batPct);

    char buf[40];
    int y = SY(26);
    y = drawKV(g, y, "IP",   WiFi.localIP().toString().c_str());
    snprintf(buf, sizeof(buf), "%d dBm", rssi);                 y = drawKV(g, y, "WiFi", buf);
    y = drawKV(g, y, "SSID", WiFi.SSID().c_str());
    unsigned long s = millis() / 1000;
    snprintf(buf, sizeof(buf), "%lud %luh %lum", s / 86400, (s % 86400) / 3600, (s % 3600) / 60);
    y = drawKV(g, y, "Up", buf);
    snprintf(buf, sizeof(buf), "%uk free", (unsigned)(ESP.getFreeHeap() / 1024));   y = drawKV(g, y, "Heap", buf);
    snprintf(buf, sizeof(buf), "%.1fM free", ESP.getFreePsram() / 1048576.0);       y = drawKV(g, y, "PSRAM", buf);
    if (batPct >= 0) { snprintf(buf, sizeof(buf), "%d%%", batPct); y = drawKV(g, y, "Bat", buf); }
    snprintf(buf, sizeof(buf), "%d/%d%%", ALERT_WARN_PCT, ALERT_CRIT_PCT); y = drawKV(g, y, "Alerts", buf);
    drawKV(g, y, "FW", FW_VERSION " Mango");

    halFlush();
}
```

In `uiRenderPage`, add the case (before the `default`):

```c
        case UI_PAGE_DEVICE: uiPageDevice(data, lastFetchMs, rssi, batPct); break;
```

- [ ] **Step 3: Compile**

Run: `pio run -e tdisplay-s3`
Expected: `SUCCESS`.

- [ ] **Step 4: Commit** *(only with the user's go-ahead)*

```bash
git add src/ui.h src/ui.cpp
git commit -m "feat: device & network info page"
```

**On-device verification (deferred) — spec item 3:**
- A reaches the Device page; it shows IP, RSSI, SSID, uptime, free heap, free PSRAM, battery, `Alerts 50/80%`, and `FW 2.2.0 Mango`, no clipping on 320×170.

---

## Task 5: Big clock page (Phase 5)

Delivers: page 4 — large bold local time (UTC+7) plus the next 5h reset as a wall-clock time (no 7d). Independent of Tasks 2/3/4.

**Files:**
- Modify: `src/ui.h` (enum: insert `UI_PAGE_CLOCK`)
- Modify: `src/ui.cpp` (`drawClockBody`, `uiPageClock`, dispatch case, clock-tick case)
- Modify: `src/main.cpp` (`syncTime()` → UTC+7)

**Interfaces:**
- Consumes: `getLocalTime()`, `localtime_r()`, `UsageData::h5ResetEpoch`, `drawTopBar`.
- Produces: `static void drawClockBody(TFT_eSPI& g, const UsageData& data);` (shared by the full draw and the 10s tick).

- [ ] **Step 1: Set the clock to UTC+7 in `main.cpp`**

**Replace** `syncTime()` (lines 70–74):

```c
static void syncTime() {
#ifdef PAGED_UI
    configTime(7 * 3600, 0, "pool.ntp.org", "time.nist.gov");  // UTC+7 for the Clock page
#else
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");
#endif
    struct tm t;
    getLocalTime(&t, 5000);
}
```

(Reset countdowns use epoch deltas via `fmtCountdown`, so they stay correct regardless of the display offset.)

- [ ] **Step 2: Insert `UI_PAGE_CLOCK` into the enum in `ui.h`**

**Replace** the enum line:

```c
enum UiPage { UI_PAGE_USAGE, UI_PAGE_MODELS, UI_PAGE_HISTORY, UI_PAGE_DEVICE, UI_PAGE_CLOCK, UI_PAGE_COUNT };
```

- [ ] **Step 3: Add `drawClockBody` + `uiPageClock` in `ui.cpp`**

Inside the `#ifdef PAGED_UI` block, add **before** `uiRenderPageClock` (so the tick can call it). Place it after `uiPageDevice`:

```c
// Big bold local time + the next 5h reset (no 7d here). Shared by the full page
// draw and the 10s tick; it wipes its own regions so the tick doesn't flicker.
static void drawClockBody(TFT_eSPI& g, const UsageData& data) {
    struct tm tm;
    char tbuf[8] = "--:--";
    if (getLocalTime(&tm, 50)) snprintf(tbuf, sizeof(tbuf), "%02d:%02d", tm.tm_hour, tm.tm_min);

    g.setTextSize(TS(6));
    g.setTextColor(C_TEXT, C_BG);
    int tw = (int)strlen(tbuf) * 6 * TS(6);
    g.fillRect(0, SY(40), SCREEN_W, SY(60), C_BG);            // wipe prior time
    g.setCursor((SCREEN_W - tw) / 2, SY(48));
    g.print(tbuf);

    g.setTextSize(1);
    g.setTextColor(C_DIM, C_BG);
    const char* loc = "Bangkok  UTC+7";
    g.setCursor((SCREEN_W - (int)strlen(loc) * 6) / 2, SY(110));
    g.print(loc);

    char rbuf[24] = "5h reset --:--";
    if (data.ok && data.h5ResetEpoch) {
        time_t e = (time_t)data.h5ResetEpoch;
        struct tm rt;
        localtime_r(&e, &rt);
        snprintf(rbuf, sizeof(rbuf), "5h reset %02d:%02d", rt.tm_hour, rt.tm_min);
    }
    g.setTextColor(C_TEXT, C_BG);
    g.fillRect(0, SY(126), SCREEN_W, SY(16), C_BG);
    g.setCursor((SCREEN_W - (int)strlen(rbuf) * 6) / 2, SY(128));
    g.print(rbuf);
}

static void uiPageClock(const UsageData& data, unsigned long lastFetchMs, int rssi, int batPct) {
    auto& g = lcd;
    halClear(C_BG);
    unsigned long ago = (millis() - lastFetchMs) / 1000;
    drawTopBar(g, rssi, ago, batPct);
    drawClockBody(g, data);
    halFlush();
}
```

In `uiRenderPage`, add the case (before the `default`):

```c
        case UI_PAGE_CLOCK: uiPageClock(data, lastFetchMs, rssi, batPct); break;
```

In `uiRenderPageClock`, add a branch so the clock advances on the 10s tick. **Replace** the existing `if (page == UI_PAGE_USAGE && data.ok) { ... }` with:

```c
    if (page == UI_PAGE_USAGE && data.ok) {
        char h5rst[16], d7rst[16];
        fmtCountdown(data.h5ResetEpoch, h5rst, sizeof(h5rst));
        fmtCountdown(data.d7ResetEpoch, d7rst, sizeof(d7rst));
        drawResetValues(g, h5rst, d7rst);
    } else if (page == UI_PAGE_CLOCK) {
        drawClockBody(g, data);
    }
```

- [ ] **Step 4: Compile**

Run: `pio run -e tdisplay-s3`
Expected: `SUCCESS`.

- [ ] **Step 5: Commit** *(only with the user's go-ahead)*

```bash
git add src/ui.h src/ui.cpp src/main.cpp
git commit -m "feat: big clock page (UTC+7) + 5h reset"
```

**On-device verification (deferred) — spec items 2, 6:**
- A walks all five pages: Usage → Models → History → Device → Clock → Usage.
- The Clock page shows Bangkok local time (UTC+7) in large bold type and the correct 5h next-reset time; the minute advances on the 10s tick; there is no 7d line.

---

## Self-review

**Spec coverage:**
- 5-page paged UI navigated by A — Tasks 1, 3, 4, 5 (enum grows; `uiPageCount` widens the wrap). ✓
- Usage/Model split, mascots larger — Task 1 (2×2 grid). ✓
- Escalating alerts (bar color at 50/80, header dot driven by 5h only on every page, edge-triggered crit flash, model-down header marker) — Task 2. ✓
- History sparkline + 7d trend arrow, RAM-only — Task 3. ✓
- Device & network read-only stats, incl. configured alert thresholds — Task 4. ✓
- Big bold clock UTC+7 + 5h reset, no 7d — Task 5. ✓
- Navigation map (tap A next / hold A flip / B brightness / A+B refresh; boot gestures unchanged) — Task 1 (the `loop()` boot-gesture blocks at `main.cpp:127`/`151` are untouched). ✓
- Hardcoded thresholds 50/80 (`config.h`, Task 1; consumed by alerts in Task 2, shown on the Device page in Task 4) and UTC+7 (Task 5, `syncTime`). ✓
- Idle stays on the current page — no auto-return code is added. ✓
- `FW_VERSION` → 2.2.0 — Task 1. ✓
- No changes to `api.cpp`/`crypto.cpp`/`certs.cpp` — none of the tasks touch them. ✓
- Compatibility: all changes gated by `PAGED_UI` — every task; Task 1/Task 2 build a non-paged env to prove isolation. ✓

**Type consistency:** `uiRenderPage`/`uiRenderPageClock`/`uiPageCount`/`uiSetAlertLevel`/`uiAlertFlash` signatures match between `ui.h` decls and `ui.cpp` defs and all `main.cpp` call sites. The `UiPage` enum is the single source for page indices (`UI_PAGE_MODELS` in the blink gate, `UI_PAGE_COUNT` in the wrap). `historyPush(float,float)`/`historyCount`/`historyAt(uint16_t)`/`historyTrend()` match between `history.h`, `history.cpp`, and both call sites. `drawClockBody`/`drawTopBar`/`drawKV`/`alertLevelFor` are file-static, used only where defined.

**Placeholder scan:** every code step contains complete, compilable code; no TBD/TODO/"handle edge cases".

**Open dependency to confirm at execution:** the exact non-paged PlatformIO env name (`m5stick-cplus` is assumed in the compile steps) — substitute whatever `platformio.ini` actually defines.
