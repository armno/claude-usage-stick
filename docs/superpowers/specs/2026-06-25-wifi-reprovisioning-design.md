# WiFi-only Re-provisioning — Design

**Date:** 2026-06-25
**Repo:** armno/claude-usage-stick (fork of oauramos/claude-usage-stick)
**Board scope:** LILYGO T-Display S3 (`tdisplay-s3` env). Other boards unaffected by default — see Compatibility.
**Status:** Approved design, pending implementation plan.

## Problem

The firmware can only be provisioned once. The captive-portal setup runs only at boot
when the `provisioned` NVS flag is false (`main.cpp:132`). There is no way to change the
WiFi network afterward except a factory reset (hold A+B 2s at boot → `prefs.clear()`,
`main.cpp:108-125`), which wipes *everything* — including the encrypted OAuth token —
forcing a full re-setup (token + PIN). Worse, if the saved network becomes unreachable,
boot hits `WIFI FAILED → restart` (`main.cpp:200-204`) and reboot-loops, never reaching
any setup UI.

Goal: change the WiFi network without re-entering the OAuth token or PIN, and without
reboot-looping when the saved network is gone.

## Key insight

The OAuth token is stored AES-256-GCM-encrypted in its own NVS key (`blob`), independent
of `ssid`/`wifipass`. A flow that writes only `ssid`/`wifipass` and never touches `blob`
lets the user change networks with no token re-entry and no PIN. The token stays encrypted
at rest throughout, and (unlike first-run provisioning) never crosses the plain-HTTP AP
form — strictly lower exposure.

## Behavior

A new **WiFi-only setup portal** is reachable two ways:

1. **Automatic fallback.** In `setup()`, when `connectWiFi()` fails, launch the WiFi portal
   instead of the current `WIFI FAILED → delay → restart` (`main.cpp:200-204`). Fixes the
   reboot-loop trap when the device is moved out of range or the network is gone.
2. **Manual boot gesture.** Hold **Button B (GPIO14) for ~2s** during boot. Checked in
   `setup()` immediately after the A+B factory-reset block, before the provisioned/PIN
   logic, so **no PIN is required** to change WiFi.

Both launch the same portal. On **Save**: write only `ssid` + `wifipass` to NVS, then
`ESP.restart()`. Next boot follows the normal path → PIN unlock decrypts the existing
token → connects to the new network.

### Why hold B (not A)

Button A = GPIO0 = the BOOT strapping pin (`hal.cpp:64`). Holding it during power-on drops
the board into USB download mode before our code runs, so a boot gesture on A is
impossible. Button B = GPIO14 is a normal pin (`hal.cpp:65`) — safe to sample at boot.

### Trigger collision

Factory reset checks `halBtnAIsPressed() && halBtnBIsPressed()` first (`main.cpp:108`).
Holding B alone fails that test and falls through to the new "B held ~2s" check. No
collision.

## Components

### provision.cpp

- **`WIFI_HTML`** (new PROGMEM string): a stripped setup page — SSID (required) + password
  + "Save & Reboot" — reusing the existing form's CSS/markup. Drops the Claude-credentials
  and Preferences sections.
- **`handleWiFiUpdate()`** (new handler): reads `ssid`/`wifipass`; rejects empty `ssid`
  with 400; writes only `prefs.putString("ssid", …)` and `prefs.putString("wifipass", …)`;
  `send(200)`; `delay`; `ESP.restart()`. Never touches `blob`, `poll_sec`, `brightness`,
  `dev_name`, or `provisioned`.
- **`runWiFiPortal(apName, apPass)`** (new entry): same softAP + DNS + WebServer scaffolding
  and blocking loop as `runProvisioningPortal()`, but routes `/` → WiFi page and the POST
  route → `handleWiFiUpdate()`.
  - Implementation choice (defer to plan): a standalone function vs. a `bool wifiOnly`
    parameter on `runProvisioningPortal()` that swaps the root HTML + POST handler. Behavior
    is identical either way; prefer whichever minimizes duplication of the softAP/DNS/while
    scaffolding.

### main.cpp

- Add a **B-held-~2s** sample after the factory-reset block, mirroring its 20×100ms
  debounced loop. On hold → build AP credentials → `runWiFiPortal(...)` → `return`.
- Replace the **connect-fail** branch (`main.cpp:200-204`) with: build AP credentials →
  `runWiFiPortal(...)`.
- **Refactor in scope:** the AP-name + random-password generation (`main.cpp:136-153`) is
  now needed in three places (existing first-run provisioning, the boot gesture, the
  connect-fail fallback). Extract it into a small helper rather than copy-pasting. This is a
  targeted cleanup of code the change already touches — not unrelated refactoring.

### ui.cpp / ui.h

- Reuse `uiSetupScreen(apName, apPass)` to display the AP name + password. Optionally
  pass/branch a "WiFi Setup" title to distinguish from first-run. No new screen is required.

## Security

(Posture unchanged from the 2026-06-25 audit; no re-audit needed.)

- The token `blob` is never read, written, or displayed by this flow → remains encrypted at
  rest; no PIN entry; no plaintext exposure. Lower exposure than first-run provisioning (the
  token never crosses the AP form).
- WiFi password remains plaintext in NVS — same as today, not regressed.
- The portal AP is short-lived, local, and served over plain HTTP — identical to the
  existing first-run portal. No new network attack surface.
- No changes to `api.cpp` or `certs.cpp` → the egress/TLS audit remains valid.

## Out of scope (YAGNI)

- A runtime (non-boot) gesture to open the portal.
- Changing the token, PIN, poll interval, brightness, or device name at runtime (factory
  reset still covers token/PIN changes).
- mDNS / captive-portal redirect niceties beyond what already ships.
- Other boards. The triggers rely on the S3's two-button layout; behavior on single-button
  boards (e.g. ESP32-C3-OLED) is left as-is and addressed only if those boards are targeted.

## Compatibility

Implementation is gated to the S3 path. The connect-fail fallback could apply to all boards,
but the boot gesture assumes a usable Button B that isn't a strapping pin; verify per board
before enabling. Default: enable for `tdisplay-s3` only.

## Verification (manual, on-device)

No unit-test harness exists in the repo; firmware is verified on hardware.

1. **Builds:** `pio run -e tdisplay-s3` succeeds.
2. **Manual trigger + token preserved:** on a working, provisioned device, hold B ~2s at
   boot → WiFi portal AP (`ClaudeMonitor-XXXX`) appears → connect a phone, submit a new
   SSID/password → device reboots → PIN screen unlocks the **existing** token (proves `blob`
   untouched) → device joins the new network.
3. **Fallback:** provision with an unreachable SSID (or power on out of range) → device
   drops into the WiFi portal instead of reboot-looping.
4. **No regression:** A+B held at boot still factory-resets; B alone at boot does **not**
   trigger factory reset.
