# Dim After Idle — Design

**Date:** 2026-07-02
**Board scope:** T-Display S3 only (`BOARD_TDISPLAY_S3`)
**Goal:** Extend battery runtime by dimming the backlight and pausing cosmetic
redraws when nobody has touched the device for a while.

## Motivation

On the 602040 (~500mAh) cell the device draws ~100mA average: CPU always on,
backlight at a bright level, periodic WiFi polls. The backlight is the largest
easily-reducible share (~25-35mA at the default brightness). The device is an
ambient dashboard — buttons are pressed rarely — so it can spend most of its
battery life dimmed without losing usefulness.

## Behavior

- **Idle timeout:** 2 minutes (`DIM_TIMEOUT_SEC 120`) since the last button
  press. Boot counts as the start of an idle period.
- **Dim action:** backlight PWM drops to a faint glow (`DIM_BACKLIGHT_PWM 20`,
  out of 255). Screen content remains visible up close / in a dim room.
- **While dimmed:**
  - Mascot blink animation paused (no `uiBlinkTick`).
  - 10-second clock/countdown repaint paused.
  - Periodic `refresh()` polls continue unchanged: data, history persistence,
    and alert evaluation stay live. The post-refresh full render draws at the
    dim backlight level.
- **Wake on button:** any press of A or B restores the user's chosen
  brightness level, resets the idle timer, and is swallowed — a wake press
  must not also flip the page, cycle brightness, or force a refresh.
- **Wake on critical alert:** when `refresh()` detects the OK/warn → crit
  crossing (5h usage ≥ `ALERT_CRIT_PCT`), the screen wakes *before*
  `uiAlertFlash()` fires so the flash plays at full brightness. Alert wake is
  identical to button wake (idle timer resets; blink/clock resume).
- **Interaction with manual brightness:** if the user has cycled brightness to
  level 0 (screen off), dimming is skipped — PWM 20 would be *brighter* than
  the user's explicit choice.
- **Power source:** applies on USB and battery alike. The board cannot
  reliably distinguish USB from battery power (the battery-sense node reads
  charger float voltage on USB, overlapping with a full cell), and a
  button-press wake is cheap.

## Implementation

- `src/config.h`: add `DIM_TIMEOUT_SEC` and `DIM_BACKLIGHT_PWM`.
- `src/hal.h` / `src/hal.cpp`: add `halSetBacklightRaw(uint8_t pwm)` —
  T-Display S3 implementation is `ledcWrite(0, pwm)`. Not added to other
  board sections; the dim feature is compiled only for this board.
- `src/main.cpp`:
  - File-static dim state: `s_lastInteraction` (millis of last button press)
    and `s_dimmed` flag, plus a `wakeScreen()` helper
    (`halSetBrightness(brightness)`, clear flag, reset timer).
  - Top of the button-handling block: if dimmed and either button was
    pressed, consume the press events (the `halBtn*WasPressed()` getters
    clear their flags on read) and call `wakeScreen()`; skip the rest of the
    button logic for that iteration.
  - Every handled button action also refreshes `s_lastInteraction`.
  - Dim check in `loop()`: idle past timeout, not already dimmed, and
    `brightness > 0` → set flag, `halSetBacklightRaw(DIM_BACKLIGHT_PWM)`.
  - Blink block: `blinkActive` additionally requires `!s_dimmed`.
  - Clock repaint block: skipped while `s_dimmed`.
  - `refresh()`: on the crit crossing, call `wakeScreen()` immediately before
    `uiAlertFlash()`.
- `millis()` rollover (~49 days) is ignored, consistent with all existing
  timing code in the project.

## Non-goals

- No runtime configurability of timeout or dim level (constants only).
- No screen-fully-off stage, no staged dimming.
- No light sleep / CPU power management.
- No support for other boards in this pass.

## Expected outcome

Roughly 25-35% longer battery runtime (backlight share of the ~100mA average
draw), unchanged data freshness, alerts still impossible to miss.

## Verification

1. Flash; leave untouched 2 minutes → screen dims, blink and clock updates
   stop.
2. Press B while dimmed → screen returns at previous brightness; brightness
   did *not* cycle.
3. Press A while dimmed → screen wakes; page did *not* change.
4. After wake, blink and clock updates resume; 2 minutes later it dims again.
5. Alert wake: temporarily set `ALERT_CRIT_PCT` low (e.g. 1), flash, drive
   usage over it, confirm the dimmed screen wakes + flashes red; revert.
   (Optional — code-review of the ordering may suffice.)

## Open questions (assumed defaults, adjust if wrong)

- Timeout 2 min, dim PWM 20, alert-wake enabled were chosen while you were
  AFK — all three are one-line constants / small tweaks to change.
