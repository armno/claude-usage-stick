# Build & Setup Runbook — Claude Usage Stick on LILYGO T-Display S3

Step-by-step to get `oauramos/claude-usage-stick` running on the T-Display S3.
Commands are for macOS (Apple Silicon / M2). See [`CLAUDE.md`](./CLAUDE.md) for
the why behind each choice.

Repo: https://github.com/oauramos/claude-usage-stick

---

## What you need

- LILYGO T-Display S3 (ESP32-S3) board.
- A **USB-C data cable** (not charge-only).
- A Mac with VS Code (or just the PlatformIO CLI).
- Claude Code installed + a Claude subscription (for `claude setup-token`).
- Your 2.4 GHz WiFi name + password.
- Optional: a small LiPo battery on the board's JST connector for cordless use.

---

## Phase 0 — Prep while the board ships (no hardware needed)

Compiling needs no board; only flashing and the live test do. Knock these out
in advance:

1. **Install PlatformIO.**
   - Easiest: install VS Code, then the "PlatformIO IDE" extension.
   - Or CLI only: `pip install platformio` (or `brew install platformio`).

2. **Install Rosetta** (avoids the `uploadfs` "Bad CPU type" surprise later):
   ```bash
   softwareupdate --install-rosetta
   ```

3. **Get your Claude Code OAuth token:**
   ```bash
   claude setup-token
   ```
   Save the token somewhere safe for the config step. It's a sensitive
   credential — treat it like a password.

4. **Clone and review the project** (it handles your token, so read it):
   ```bash
   git clone https://github.com/oauramos/claude-usage-stick.git
   cd claude-usage-stick
   ```
   Skim `src/api.cpp` and `src/crypto.cpp`. Confirm the device only ever talks to
   `api.anthropic.com` and that the token is encrypted, not phoned anywhere else.

5. **Compile it** (proves your toolchain works, no board required):
   ```bash
   pio run -e tdisplay-s3
   ```

6. *(Optional)* Mock up the UI in [Wokwi](https://docs.wokwi.com/guides/esp32)
   if you want to tweak the layout before hardware arrives.

---

## Phase 1 — Flash the board (when it arrives)

1. Plug the board into your Mac with the USB-C **data** cable.

2. Upload the firmware:
   ```bash
   pio run -e tdisplay-s3 -t upload
   ```

3. Upload the filesystem image (the web setup UI):
   ```bash
   pio run -e tdisplay-s3 -t uploadfs
   ```
   **If this fails with "Bad CPU type"** (Apple Silicon), use the fallback:
   ```bash
   python3 upload_data.py
   ```

---

## Phase 2 — Configure the device (captive portal)

1. On first boot the device creates a WiFi access point named
   `ClaudeMonitor-XXXX`. Its password is shown on the device screen.
2. Connect your phone or laptop to that network.
3. Open `http://192.168.4.1` in a browser.
4. Enter: your WiFi credentials, the OAuth token from `claude setup-token`, and a
   4–8 digit **encryption PIN**.
5. Hit **Save & Reboot**. The device encrypts the token with your PIN and
   connects to your WiFi.

---

## Phase 3 — Daily use

On each boot, unlock with your PIN using the two buttons:

- **Button A** — cycle the current digit (0–9)
- **Button B** — confirm and move to the next digit

Once unlocked, the dashboard appears and auto-refreshes.

| Button | Dashboard action |
| --- | --- |
| A | Cycle brightness (off → dim → normal → bright) |
| B | Force an immediate refresh |
| A + B held on boot | Factory reset (wipes all stored data) |

---

## Customizing (later)

- All the LCD drawing lives in `src/ui.cpp` — start there for layout/colors.
- Tunables (poll interval, timeouts, PIN attempts) are in `src/config.h`.
- There's an optional local caching proxy at `server/usage_proxy.py` that can
  read the token from the macOS Keychain if you'd rather not store it on-device.

---

## Troubleshooting

- **`uploadfs` → "Bad CPU type":** install Rosetta or run `python3 upload_data.py`.
- **Board not detected / no serial port:** the S3 has native USB; if it doesn't
  appear, try a different (data) cable, or hold the **BOOT** button while
  plugging in to force the bootloader.
- **WiFi won't connect:** must be **2.4 GHz**; the ESP32 doesn't do 5 GHz.
- **Forgot PIN:** hold **A + B** on boot to factory reset, then reconfigure.
- **10 wrong PIN attempts:** the device wipes credentials and returns to setup
  mode (by design).
