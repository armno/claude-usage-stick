# Paged UI + Escalating Alerts — Design

**Date:** 2026-06-25
**Repo:** armno/claude-usage-stick (fork of oauramos/claude-usage-stick)
**Board scope:** LILYGO T-Display S3 (`tdisplay-s3` env), Mango UI only. Other boards unaffected — see Compatibility.
**Status:** Approved design, pending implementation plan.

## Problem / Goal

Today the Mango dashboard is a single fixed screen: `uiDashboard()` (`ui.cpp:862`) draws the
header, the 5h/7d bars, the reset row, and the model-status mascot panel all at once. Two
limitations:

- **No room to grow.** Everything competes for one 320×170 screen, so model health and usage
  crowd each other and there's nowhere to surface history or device info.
- **The device is passive.** It shows state but never grabs attention — you only learn you're
  near a rate-limit cap if you happen to be looking at the Usage screen at the right moment.

Goals:
1. Turn the single dashboard into a **5-page paged UI** navigated with Button A.
2. Add **escalating visual alerts** so an approaching cap is visible from any page and
   unmissable at critical.

## Scope

T-Display S3 (tier L, `MANGO_UI` + `BOARD_TDISPLAY_S3`) only. M5StickC Plus (tier S) and the
Clarity boards are untouched and keep their current single dashboard. Alerts are **visual
only** — the T-Display S3 has no buzzer or user LED; sound is a future port concern.

## Architecture

Page-enum + switch, reusing the existing draw helpers — not a new framework.

- `main.cpp` holds a `currentPage` index (0–4). Button A advances it (wraps 4→0) and
  redraws. The existing Mango button handler (`main.cpp:256-273`) is remapped (see Navigation).
- `ui.cpp` gains one `uiPageX()` draw function per page. Today's `uiDashboard()` body becomes
  `uiPageUsage()`; the existing helpers (`drawBar` `ui.cpp:359`, `barColor` `ui.cpp:333`,
  `drawResetRow` `ui.cpp:482`, `drawStatusPanel` `ui.cpp:492`, `drawMascot` `ui.cpp:421`,
  `drawHeaderRight` `ui.cpp:622`) are reused as-is or lightly extended.
- A shared header (battery, WiFi, **alert dot**) renders on every page via `drawHeaderRight`.
- Rejected alternative: a function-pointer page registry / generic carousel driver — overkill
  for 5 fixed pages and against the project's simplicity rule.

## The 5 pages

Landing page after unlock is **Usage (page 0)**. Idle does not change the page — it stays
where you left it.

```
0 USAGE      [hdr ........•]   1 MODELS     [hdr ........•]   2 HISTORY    [hdr ........•]
  5h ███████░░ 82%  ~47m          HAIKU   SONNET                5h ▁▂▃▅▆▇█  82%
  7d ████░░░░░ 41%  3d 4h         ◕‿◕    ◕‿◕                   7d 41%  ▲ trend
  bars recolor by threshold       OPUS    FABLE                 5h sparkline from ring buffer
                                  ◕‿◕    ✕_✕ DOWN              7d shown as value + arrow

3 DEVICE     [hdr ........•]   4 CLOCK      [hdr ........•]
  IP    192.168.1.42
  WiFi  -58 dBm                       14:32      <- big + bold
  Up    3d 4h                      Bangkok · UTC+7
  Heap  210k · PSRAM 7.9M          5h resets 15:19
  Alerts 50/80%
  FW    2.2.0 Mango
```

- **0 · Usage** — 5h/7d bars + reset countdowns. Bars recolor green/amber/red by threshold
  (the alert mechanism, below). This is the refactored current dashboard minus the mascot
  panel.
- **1 · Model health** — the four mascots from `drawStatusPanel`/`drawMascot`, now owning the
  whole page so they can render larger, with room for a status/incident text line. Blink
  behavior (`uiBlinkTick` `ui.cpp:512`) preserved.
- **2 · History** — a 5h-utilization **sparkline** drawn from a RAM ring buffer, plus the
  current 7d value with a trend arrow (▲/▼/▶). Deliberately simple: no 7d sparkline.
- **3 · Device & network** — IP (`WiFi.localIP`), RSSI (`WiFi.RSSI`), uptime (`millis`), free
  heap (`ESP.getFreeHeap`) and PSRAM (`ESP.getFreePsram`), battery (`halBatPercent`), SSID,
  firmware (`FW_VERSION`), and the **configured alert thresholds** (`WARN/CRIT`) so the values
  in effect are visible at a glance without reflashing.
- **4 · Big clock** — local time as the page's focus, in large bold type, with the next 5h
  reset below it. The 7d reset is **not** repeated here (it lives on the Usage page). Doubles
  as a desk clock.

## Navigation

| Input | Action |
| ----- | ------ |
| `A` (tap) | Next page (0→1→2→3→4→0) |
| `B` (tap) | Cycle brightness |
| `A+B` | Force refresh |
| long-press `A` (~600ms) | Flip screen 180° (`uiToggleRotation` `ui.cpp:391`) |

Boot gestures are **unchanged**: A+B held ~2s = factory reset (`main.cpp:127`); B held ~2s =
WiFi-only portal (`main.cpp:151`).

Reworks the current Mango map (`main.cpp:256-273`) where a bare A = flip and A+B = refresh.
Flip moves to a long-press on A; a short A tap becomes "next page." Gesture resolution on A:
if B joins within the existing ~350ms combo window → refresh; else, on A release before the
hold threshold (~600ms) → next page; if A is still held past ~600ms → flip. So A is resolved
on release (tap) or at the hold threshold (flip), B within the window pre-empts both.

## Alerts (escalating)

Utilization here is the rate-limit **utilization** of a window (0–100%) read from the Anthropic
response headers — the fraction of that window's cap already consumed. Thresholds are hardcoded
in `config.h`. The two bands mirror my workflow: on a 1M-context session I clear/compact around
50% to keep context healthy, so green→amber at 50% is the "start watching" line and amber→red at
80% is "act now."

```
#define ALERT_WARN_PCT  50
#define ALERT_CRIT_PCT  80
```

Two things consume the thresholds, and they differ in **scope**:

- **Bars (Usage page).** Each of the 5h and 7d bars colors itself by its *own* utilization —
  green `< 50`, amber `50–79`, red `≥ 80`.
- **Header dot + flash (every page).** Driven by the **5h window only**. The 7d window is not
  surfaced globally — it lives on its own bar on the Usage page; scroll there to see it.

| Level | 5h utilization | Presentation |
| ----- | -------------- | ------------ |
| OK | `< WARN` (50) | Green 5h bar. No header dot. |
| Warn | `≥ WARN` (50) | Amber 5h bar **+ header alert dot on every page**. |
| Critical | `≥ CRIT` (80) | Red 5h bar + **one** full-screen flash on the crossing (edge-triggered), then settles to the persistent header dot. |

- The header dot and the flash reflect the **5h** level only. The 7d bar still recolors on the
  Usage page but never drives the dot or the flash.
- The critical flash is **edge-triggered**: it fires once when 5h first crosses CRIT, not on
  every poll while it stays critical. Track the previous 5h level in `main.cpp` to detect the
  OK/warn→crit transition.
- `barColor` (`ui.cpp:333`, currently a near-stub) is extended to map utilization →
  green/amber/red at the WARN/CRIT thresholds. Both Usage-page bars use it directly.
- **Model-down** also lights the header indicator (a distinct glyph/color from the usage dot)
  so a downed model is visible from **every page**, not just the Model health page. No
  full-screen takeover for incidents — they're less urgent than your own cap.

## History module (new)

- A single `uint8_t` ring buffer of 5h utilization (0–100), one sample appended on each
  successful `refresh()` (`main.cpp:77`). Width sized to the sparkline plot (~100 samples ≈
  ~3.3h at the 120s default poll — covers most of the 5h window).
- **RAM-only.** Resets on reboot; not persisted to NVS (avoids flash wear; the device is
  desk-powered and rarely reboots).
- The 7d trend arrow compares the current 7d utilization to the previous sample's value — a
  single retained float, no second buffer.
- Lives in a small new module (e.g. `history.cpp/h`) or, if trivial, file-static state in
  `ui.cpp`; defer the exact home to the plan.

## Data / plumbing changes

- `main.cpp`: `currentPage` state; remapped button handler; previous 5h alert-level tracking
  for the edge-triggered flash; push a history sample in `refresh()`.
- `syncTime()` (`main.cpp:70`): set the GMT offset to **UTC+7** (`configTime(7*3600, 0, …)`)
  so `getLocalTime()` returns Bangkok time for the Clock page. Reset countdowns are epoch
  deltas (`fmtCountdown` `ui.cpp:7`) and stay correct regardless of display offset.
- No changes to `api.cpp`, `crypto.cpp`, or `certs.cpp` → the 2026-06-25 security audit
  (egress/TLS/token handling) remains valid; no re-audit needed.
- `FW_VERSION` (`config.h:4`) → `2.2.0` (still Mango).

## Delivery phases

Each phase is independently shippable and verifiable on-device. Build in order — Phase 1 is
the foundation everything else hangs off. The page count **grows per phase**: in Phase 1
Button A wraps across just the two pages that exist; each later phase appends its page and
widens the wrap, so A only ever cycles real pages.

**Phase 1 — Paging foundation + Usage / Model split** *(the headline ask)*
- Add `currentPage` + the page switch in `main.cpp`; remap buttons (tap A = next, hold A =
  flip, B = brightness, A+B = refresh) per Navigation.
- Refactor `uiDashboard()` into the shared header + `uiPageUsage()` (page 0).
- Move the mascot panel onto its own `uiPageModels()` (page 1), rendered larger.
- Ships: usage and model health no longer share a screen. No new data sources.

**Phase 2 — Escalating alerts**
- Extend `barColor` for the WARN/CRIT thresholds; add the header alert dot (**5h only**) on
  every page; edge-triggered critical flash (5h); model-down header glyph.
- Depends on Phase 1 only. Ships: proactive alerts on the existing pages.

**Phase 3 — History page**
- New RAM ring buffer sampled in `refresh()`; `uiPageHistory()` (page 2) — 5h sparkline + 7d
  trend arrow.

**Phase 4 — Device & network page**
- `uiPageDevice()` (page 3) — read-only stats from existing APIs (IP, RSSI, uptime, heap,
  PSRAM, battery, SSID, firmware) plus the configured alert thresholds.

**Phase 5 — Big clock page**
- `syncTime()` → UTC+7; `uiPageClock()` (page 4) — large bold local time + the 5h reset.

Phases 3–5 are mutually independent and may be reordered or parallelized; only Phase 2 has a
hard dependency (Phase 1).

## Decisions (resolved)

1. **Timezone:** hardcoded UTC+7. (Not a portal field.)
2. **History:** RAM-only, lost on reboot.
3. **7d history:** 5h sparkline + 7d trend arrow only — no second buffer.
4. **Thresholds:** hardcoded 50 / 80 in `config.h` (green `<50`, amber `50–79`, red `≥80`).
   The header dot + flash track the **5h window only**; the 7d level shows only on its
   Usage-page bar. Both also surface read-only on the Device page. (Not portal fields.)
5. **Model-down:** header indicator on every page.
6. **Idle:** stay on the current page; no auto-return.

## Out of scope (YAGNI)

Deferred, not dropped — these are parked in [`../BACKLOG.md`](../BACKLOG.md) so nothing is lost:

- Burn-rate / time-to-cap projection page (not selected).
- Auto-rotating carousel or hybrid navigation (manual paging chosen).
- Audio/haptic alerts; any buzzer or LED wiring.
- Persisting history across reboots.
- Surfacing thresholds or timezone in the setup portal.
- M5StickC Plus (tier S) and Clarity boards — single dashboard retained; a tier-S port is a
  later effort.

## Compatibility

All changes gated to `MANGO_UI` + `BOARD_TDISPLAY_S3`. Tier S and Clarity boards compile and
behave exactly as before. The paging button scheme assumes the S3's two-button layout.

## Verification (manual, on-device)

No unit-test harness exists; firmware is verified on hardware.

1. **Builds:** `pio run -e tdisplay-s3` succeeds.
2. **Paging:** after PIN unlock, lands on Usage; tapping A walks 0→1→2→3→4→0; B still cycles
   brightness; A+B forces a refresh; long-press A flips the screen.
3. **Pages render:** each of the 5 pages draws correctly on the 320×170 panel without clipping;
   the shared header appears on all five; the Device page lists the configured alert
   thresholds (50/80%).
4. **Alerts:** with 5h usage below 50% the 5h bar is green and no header dot shows; crossing
   50% (verify with a real or simulated high-utilization response) turns the 5h bar amber and
   shows the header dot on every page; crossing 80% turns it red and flashes the screen
   **once**, after which the dot persists without re-flashing on subsequent polls. The 7d bar
   recolors on its own value but never drives the dot or the flash.
5. **Model-down:** a downed model (reuse the `STATUS_TEST_DOWN` build flag, `status.cpp:49`)
   shows the X-eyes mascot on the Model page **and** the model indicator in the header on every
   other page.
6. **Clock:** the Clock page shows Bangkok local time (UTC+7) in large bold type and the
   correct 5h next-reset time (no 7d line).
7. **History:** the sparkline fills over successive polls and resets to empty after a reboot.
8. **No regression:** A+B held at boot still factory-resets; B held at boot still opens the
   WiFi portal.
