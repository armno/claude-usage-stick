# ESP32 Claude Code Usage Dashboard

A small desktop gadget that shows my **Claude Code rate-limit usage** (the 5-hour
session window and the 7-day/weekly window) on a tiny screen, with reset
countdowns. Hobby project, low budget. Wired or battery — fine either way.

> Context handed off from a planning conversation on **2026-06-25**. See
> [`SETUP.md`](./SETUP.md) for the step-by-step build/flash runbook.

## Decisions made

- **Board: LILYGO T-Display S3** (ESP32-S3, 1.9" IPS 170×320, USB-C, 2 buttons).
  Chosen over the cheaper "Cheap Yellow Display" (CYD / ESP32-2432S028R) for the
  sharper IPS panel and the big memory headroom (16 MB flash / 8 MB PSRAM vs the
  CYD's 4 MB / 520 KB), which keeps an animated LVGL UI smooth. CYD is the
  fallback if I want touch, a bigger screen, or to buy locally — a USB-C CYD is
  on Shopee TH (Airepair) for ~฿370 with free Bangkok shipping.
- **Software: use the community project, don't build from scratch (yet).**
  → `oauramos/claude-usage-stick` — https://github.com/oauramos/claude-usage-stick
  It already supports the T-Display S3 (`tdisplay-s3` PlatformIO env) and, more
  importantly, already solved the hard part: where the usage data comes from.
  Plan is to flash it as-is, then fork and customize the UI later.
- **Toolchain: PlatformIO** (VS Code extension or `pio` CLI). The repo ships a
  `platformio.ini` with the board env, libraries, and a filesystem image, so the
  build is reproducible. Arduino IDE is only for quick throwaway experiments.

## How it works (the data path)

1. The device makes a minimal `max_tokens: 1` request to the Anthropic Messages
   endpoint using a **Claude Code OAuth token** (NOT an API key).
2. It reads the `anthropic-ratelimit-unified-5h-utilization` and
   `anthropic-ratelimit-unified-7d-utilization` response headers.
3. It draws the two usage bars + reset countdowns, refreshing every 30s–5min.

The OAuth token comes from `claude setup-token` and is tied to my Claude Code
subscription — that's why an API key won't work here (only the subscription
token carries the unified session/weekly rate-limit headers).

## Key constraints & gotchas

- **OAuth token, not API key.** Generated with `claude setup-token`. Requires
  Claude Code + a Claude subscription. No separate API credits needed.
- **Apple Silicon (M2):** the firmware filesystem upload (`uploadfs`) can fail
  with "Bad CPU type". Fix: `softwareupdate --install-rosetta`, or use the repo's
  `python3 upload_data.py` fallback.
- **Security:** the OAuth token is a sensitive credential (acts as my Claude Code
  identity, can consume my plan quota). The project encrypts it on-device
  (AES-256-GCM, PIN-derived key, never stored in plaintext, never leaves the
  device). Before flashing, skim `src/api.cpp` and `src/crypto.cpp` and confirm
  the device only ever contacts `api.anthropic.com`. Small single-author repo
  (~77 stars, v2.1.1) so review matters.
- **Security audit done 2026-06-25 — verdict: safe to flash (T-Display S3).** No
  malware/backdoor/telemetry/hidden egress; token never hits screen/Serial/NVS in
  plaintext, only leaves as a Bearer header to `api.anthropic.com` over
  cert-validated TLS (3 legit roots, no `setInsecure`). Don't re-audit unless the
  code changes — re-skim `api.cpp`/`certs.cpp` after a `git pull`. Caveats: PIN is
  anti-casual not anti-theft (4-digit + MAC-salted KDF, flash not encrypted → token
  recoverable with physical access, so rotate via `claude setup-token` if lost);
  WiFi password stored plaintext in NVS; also contacts `status.claude.com` + NTP
  (no secrets); if running the Mac proxy, bind it to `127.0.0.1`.
- WiFi must be **2.4 GHz**.

## Environment

- Machine: MacBook Air M2 (Apple Silicon).
- I'm new to ESP32 but comfortable with MCUs/firmware (built a Corne split
  keyboard with nice!nano), so build-system-driven workflows are familiar.

## Status / next steps

- [ ] Order the T-Display S3 (or grab the local CYD as fallback).
- [ ] Prep while waiting: install VS Code + PlatformIO, install Rosetta, install
      Claude Code, run `claude setup-token`, clone + skim the repo, get it to
      compile. (Compiling needs no board; only flashing/live test does.)
- [ ] When board arrives: flash, configure over the captive portal, verify live
      numbers.
- [ ] Fork and customize the UI (`src/ui.cpp`).

Full instructions: [`SETUP.md`](./SETUP.md).

## Reference links

- Community project: https://github.com/oauramos/claude-usage-stick
- T-Display S3: https://lilygo.cc/products/t-display-s3
- CYD overview: https://randomnerdtutorials.com/cheap-yellow-display-esp32-2432s028r/
- Local CYD (Shopee TH): https://shopee.co.th/product/1245365897/26285515819
- PlatformIO: https://platformio.org/install
- Wokwi (optional UI simulator): https://docs.wokwi.com/guides/esp32
