# WiFi-only Re-provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the device change WiFi network without wiping or re-entering the OAuth token/PIN, and replace the connect-fail reboot loop with a WiFi setup portal.

**Architecture:** A new WiFi-only captive portal writes only `ssid`/`wifipass` to NVS and reboots, never touching the encrypted token `blob`. It is reached two ways from `setup()`: a hold-B-at-boot gesture, and an automatic fallback when WiFi connection fails. Portal scaffolding (softAP/DNS/web server loop) is shared with the existing first-run portal.

**Tech Stack:** ESP32-S3 Arduino framework, PlatformIO (`tdisplay-s3` env), WebServer + DNSServer + Preferences (NVS). No automated test harness exists; each task is verified by a compile gate (`pio run -e tdisplay-s3`) and the final task by on-device manual checks.

## Global Constraints

- **Board scope:** `tdisplay-s3` only. Don't change behavior for other board `#ifdef` paths.
- **Security (must hold):** the WiFi-only flow must NEVER read, write, or display the token `blob`, the PIN, or any decrypted token. It writes only NVS keys `ssid` and `wifipass`.
- **No changes** to `src/api.cpp` or `src/certs.cpp` (keeps the prior egress/TLS audit valid).
- **NVS namespace:** `NVS_NAMESPACE` (from `config.h`). NVS keys are exactly `"ssid"`, `"wifipass"`.
- **Verification per code task:** `pio run -e tdisplay-s3` must end with `[SUCCESS]`.
- **Git:** work on branch `wifi-reprovisioning`. Commit messages end with the trailer
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

### Task 1: Extract `makeApCredentials()` helper (pure refactor)

Deduplicates the AP-name + random-password generation that the first-run portal uses, so the two new trigger sites (Task 3) don't copy-paste it. No behavior change.

**Files:**
- Modify: `src/main.cpp` (add helper before `setup()`; replace block at `main.cpp:136-153`)

**Interfaces:**
- Produces: `static void makeApCredentials(char* apName, size_t nameLen, char* apPass, size_t passLen)` — fills `apName` with `ClaudeMonitor-XXXX` (last 2 MAC bytes) and `apPass` with an 8-char random password (empty on `BOARD_ESP32C3_OLED`).

- [ ] **Step 1: Add the helper** just above `void setup()` in `src/main.cpp`:

```cpp
// Builds the captive-portal AP name (ClaudeMonitor-XXXX, from the last 2 MAC bytes)
// and a random 8-char password into caller buffers. The C3-OLED has no readable
// display during setup, so it uses an open AP (empty password).
static void makeApCredentials(char* apName, size_t nameLen, char* apPass, size_t passLen) {
    (void)passLen;
    uint8_t mac[6];
    esp_efuse_mac_get_default(mac);
    snprintf(apName, nameLen, "ClaudeMonitor-%02X%02X", mac[4], mac[5]);
#ifdef BOARD_ESP32C3_OLED
    apPass[0] = '\0';
#else
    static const char alphabet[] = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    uint8_t rnd[8];
    esp_fill_random(rnd, sizeof(rnd));
    for (int i = 0; i < 8; i++) apPass[i] = alphabet[rnd[i] % (sizeof(alphabet) - 1)];
    apPass[8] = '\0';
#endif
}
```

- [ ] **Step 2: Replace the inline block** in the `if (!provisioned)` branch. Delete these lines (currently `main.cpp:136-153`):

```cpp
        uint8_t mac[6];
        esp_efuse_mac_get_default(mac);
        char apName[24];
        snprintf(apName, sizeof(apName), "ClaudeMonitor-%02X%02X", mac[4], mac[5]);

#ifdef BOARD_ESP32C3_OLED
        // No readable display during setup — use open AP so password isn't needed
        const char* apPass = "";
        Serial.printf("[SETUP] AP: %s (open)\n", apName);
#else
        static const char alphabet[] = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        uint8_t rnd[8];
        esp_fill_random(rnd, sizeof(rnd));
        char apPass[9];
        for (int i = 0; i < 8; i++) apPass[i] = alphabet[rnd[i] % (sizeof(alphabet) - 1)];
        apPass[8] = '\0';
#endif
        runProvisioningPortal(apName, apPass);
        return;
```

Replace with:

```cpp
        char apName[24], apPass[9];
        makeApCredentials(apName, sizeof(apName), apPass, sizeof(apPass));
        runProvisioningPortal(apName, apPass);
        return;
```

(This drops one OLED-only `Serial.printf` debug line — intentional, out of board scope.)

- [ ] **Step 3: Compile**

Run: `pio run -e tdisplay-s3`
Expected: `[SUCCESS]`

- [ ] **Step 4: Commit**

```bash
git add src/main.cpp
git commit -m "refactor: extract makeApCredentials() AP-setup helper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: WiFi-only portal in `provision.cpp`

Adds the stripped portal page, its save handler, and a `runWiFiPortal()` entry that shares scaffolding with the existing portal. Compiles standalone; not yet wired to any trigger.

**Files:**
- Modify: `src/provision.cpp`
- Modify: `src/provision.h`

**Interfaces:**
- Consumes: existing file-static `webServer`, `dnsServer`, `prefs`, `DNS_PORT`, `handleNotFound`, `uiSetupScreen`, `NVS_NAMESPACE`.
- Produces: `void runWiFiPortal(const char* apName, const char* apPass)` — blocking; serves a WiFi-only form, writes `ssid`/`wifipass`, reboots.

- [ ] **Step 1: Add `WIFI_HTML`** in `src/provision.cpp` immediately after the closing `)rawhtml";` of `SETUP_HTML`:

```cpp
static const char WIFI_HTML[] PROGMEM = R"rawhtml(<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>Change WiFi</title>
<style>
  :root{--bg:#191919;--card:#252525;--border:#3a3a3a;--text:#e0e0e0;
        --dim:#888;--accent:#e8733a;--cyan:#f0a050;--red:#f66}
  *{box-sizing:border-box;margin:0;font-family:system-ui,-apple-system,sans-serif}
  body{background:var(--bg);color:var(--text);padding:8px;min-height:100vh}
  .card{background:var(--card);border:1px solid var(--border);border-radius:12px;
        padding:14px 18px;max-width:420px;margin:0 auto}
  h1{color:var(--accent);font-size:1.4em;margin-bottom:2px}
  .sub{color:var(--dim);font-size:.85em;margin-bottom:12px}
  .field{margin-bottom:10px}
  label{display:block;font-size:.85em;color:var(--dim);margin-bottom:4px}
  input{width:100%;padding:8px 10px;border:1px solid var(--border);
        border-radius:8px;background:var(--bg);color:var(--text);font-size:1em;outline:0}
  input:focus{border-color:var(--cyan)}
  input[type=password]{font-family:monospace;letter-spacing:1px}
  button{margin-top:12px;width:100%;padding:10px;border:none;border-radius:8px;
         background:var(--accent);color:var(--bg);font-weight:700;font-size:1em;cursor:pointer}
  button:active{opacity:.8}
  button:disabled{opacity:.5;cursor:wait}
  #status{margin-top:8px;font-size:.9em;text-align:center;min-height:1.2em}
  .ok{color:#4f4} .err{color:var(--red)}
  .section-label{font-size:.75em;color:var(--dim);text-transform:uppercase;
                 letter-spacing:1px;margin-bottom:10px}
</style>
</head>
<body>
<div class="card">
  <h1>Change WiFi</h1>
  <p class="sub">Updates the WiFi network only. Your saved token and PIN are kept.</p>
  <form id="f">
    <div class="section-label">WiFi Network (2.4 GHz only)</div>
    <div class="field">
      <label for="ssid">SSID</label>
      <input id="ssid" name="ssid" required maxlength="32" autocomplete="off"
             placeholder="Your WiFi network name">
    </div>
    <div class="field">
      <label for="wifipass">Password</label>
      <input id="wifipass" name="wifipass" type="password" maxlength="64"
             autocomplete="off" placeholder="Leave empty for open network">
    </div>
    <button type="submit" id="btn">Save & Reboot</button>
    <div id="status"></div>
  </form>
</div>
<script>
document.getElementById('f').addEventListener('submit',async(e)=>{
  e.preventDefault();
  const btn=document.getElementById('btn'),st=document.getElementById('status');
  btn.disabled=true;st.className='';st.textContent='Saving...';
  try{
    const r=await fetch('/wifiupdate',{method:'POST',
      headers:{'Content-Type':'application/x-www-form-urlencoded'},
      body:new URLSearchParams(new FormData(e.target))});
    if(r.ok){st.className='ok';st.textContent='Saved! Device rebooting now...';}
    else{st.className='err';st.textContent='Error: '+await r.text();btn.disabled=false;}
  }catch(x){st.className='ok';st.textContent='Device rebooting (connection closed).';}
});
</script>
</body>
</html>)rawhtml";
```

- [ ] **Step 2: Add the two handlers** just after the existing `handleNotFound()` function:

```cpp
static void handleWiFiRoot() {
    webServer.send(200, "text/html", FPSTR(WIFI_HTML));
}

static void handleWiFiUpdate() {
    String ssid     = webServer.arg("ssid");
    String wifipass = webServer.arg("wifipass");

    if (ssid.isEmpty()) {
        webServer.send(400, "text/plain", "SSID is required.");
        return;
    }

    // Write ONLY the WiFi keys. The encrypted token blob and every other setting
    // are deliberately left untouched so the device unlocks with the same PIN.
    prefs.begin(NVS_NAMESPACE, false);
    prefs.putString("ssid", ssid);
    prefs.putString("wifipass", wifipass);
    prefs.end();

    webServer.send(200, "text/plain", "OK");
    delay(1500);
    ESP.restart();
}
```

- [ ] **Step 3: Refactor `runProvisioningPortal` into a shared `servePortal`.** Replace the entire existing `runProvisioningPortal(...)` function (currently `provision.cpp:192-211`) with:

```cpp
static void servePortal(const char* apName, const char* apPass, bool wifiOnly) {
    WiFi.mode(WIFI_AP);
    WiFi.softAP(apName, apPass);
    delay(100);

    dnsServer.start(DNS_PORT, "*", WiFi.softAPIP());

    if (wifiOnly) {
        webServer.on("/", HTTP_GET, handleWiFiRoot);
        webServer.on("/wifiupdate", HTTP_POST, handleWiFiUpdate);
    } else {
        webServer.on("/", HTTP_GET, handleRoot);
        webServer.on("/provision", HTTP_POST, handleProvision);
    }
    webServer.onNotFound(handleNotFound);
    webServer.begin();

    uiSetupScreen(apName, apPass);

    while (true) {
        dnsServer.processNextRequest();
        webServer.handleClient();
        delay(2);
    }
}

void runProvisioningPortal(const char* apName, const char* apPass) {
    servePortal(apName, apPass, false);
}

void runWiFiPortal(const char* apName, const char* apPass) {
    servePortal(apName, apPass, true);
}
```

- [ ] **Step 4: Declare `runWiFiPortal`** in `src/provision.h`, after the existing declaration:

```cpp
// Same as runProvisioningPortal but serves a WiFi-only form: updates ssid/wifipass
// in NVS and reboots, leaving the encrypted token and all other settings intact.
void runWiFiPortal(const char* apName, const char* apPass);
```

- [ ] **Step 5: Compile**

Run: `pio run -e tdisplay-s3`
Expected: `[SUCCESS]`

- [ ] **Step 6: Commit**

```bash
git add src/provision.cpp src/provision.h
git commit -m "feat: add WiFi-only re-provisioning portal

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Wire the two triggers in `main.cpp`

Adds the hold-B boot gesture and replaces the connect-fail reboot loop. After this task the feature is fully functional.

**Files:**
- Modify: `src/main.cpp` (insert after the factory-reset block ~`main.cpp:125`; replace connect-fail branch ~`main.cpp:200-204`)

**Interfaces:**
- Consumes: `makeApCredentials()` (Task 1), `runWiFiPortal()` (Task 2), existing `halUpdate`, `halBtnAIsPressed`, `halBtnBIsPressed`, `uiBootProgress`, `uiError`.

- [ ] **Step 1: Add the hold-B boot gesture.** Insert immediately after the factory-reset block's closing brace (the line before `// Check provisioned`, ~`main.cpp:126`):

```cpp
    // Hold Button B alone for 2s at boot → WiFi-only re-provisioning portal.
    // Changes the WiFi network without touching the encrypted token or PIN.
    // Checked AFTER the A+B factory-reset block, so B-alone never wipes NVS.
    halUpdate();
    if (halBtnBIsPressed() && !halBtnAIsPressed()) {
        uiBootProgress(40, "Hold B 2s: WiFi");
        bool held = true;
        for (int i = 0; i < 20 && held; i++) {
            delay(100);
            halUpdate();
            if (!halBtnBIsPressed() || halBtnAIsPressed()) held = false;
        }
        if (held) {
            char apName[24], apPass[9];
            makeApCredentials(apName, sizeof(apName), apPass, sizeof(apPass));
            runWiFiPortal(apName, apPass);   // blocking; reboots on save
            return;
        }
    }
```

- [ ] **Step 2: Replace the connect-fail branch.** Find (currently `main.cpp:200-204`):

```cpp
    if (!connectWiFi(ssid.c_str(), pass.c_str())) {
        uiError("WIFI FAILED", ssid.c_str());
        delay(5000);
        ESP.restart();
    }
```

Replace with:

```cpp
    if (!connectWiFi(ssid.c_str(), pass.c_str())) {
        uiError("WIFI FAILED", "Starting WiFi setup");
        delay(2500);
        char apName[24], apPass[9];
        makeApCredentials(apName, sizeof(apName), apPass, sizeof(apPass));
        runWiFiPortal(apName, apPass);   // blocking; reboots on save
        return;
    }
```

- [ ] **Step 3: Compile**

Run: `pio run -e tdisplay-s3`
Expected: `[SUCCESS]`

- [ ] **Step 4: Commit**

```bash
git add src/main.cpp
git commit -m "feat: trigger WiFi portal via hold-B boot gesture and connect-fail fallback

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: On-device verification (manual)

No code. Flash and confirm behavior on the physical T-Display S3. Requires a provisioned device with a known-good token.

**Files:** none.

- [ ] **Step 1: Flash firmware**

Run: `pio run -e tdisplay-s3 -t upload`
Expected: upload completes, hash verified.

- [ ] **Step 2: Manual trigger + token preserved**

On the running dashboard, power-cycle while holding **Button B** (the brightness button, GPIO14) — keep it held ~2s through boot. Expect the `ClaudeMonitor-XXXX` AP + the "Change WiFi" page at `192.168.4.1`. Submit a new SSID/password.
Expected: device reboots → **PIN screen unlocks the existing token** (proves the `blob` was untouched) → dashboard shows live numbers on the new network.

- [ ] **Step 3: Connect-fail fallback**

Either provision a bad/unreachable SSID, or power the device on out of range of the saved network.
Expected: after the connect timeout, the device shows "WIFI FAILED / Starting WiFi setup" and opens the WiFi portal — it does NOT reboot-loop.

- [ ] **Step 4: No regression**

- Hold **A+B** together ~2s at boot → still factory-resets ("NVS WIPED").
- Hold **B alone** at boot → opens the WiFi portal, does NOT wipe.
- Normal boot (no buttons) → normal PIN unlock + dashboard.

---

## Notes for the implementer

- The portal functions block forever and reboot on save, so the `return;` after each `runWiFiPortal(...)` call is only reached if the portal ever exits (it doesn't) — it's there for clarity/safety.
- Button B is GPIO14 (not the BOOT/strapping pin GPIO0), so holding it at boot is safe and won't enter USB download mode. Holding A at boot is reserved/unsafe and is intentionally NOT a trigger.
- Keep `prefs` usage matched: every `prefs.begin(...)` in the new handler is paired with `prefs.end()`.
