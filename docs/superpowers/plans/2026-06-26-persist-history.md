# Persist History Across Reboots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Checkpoint the History page's 5h-utilization ring buffer to NVS so it survives a reboot, discarding the data only if the 5h window rolled over while the device was off.

**Architecture:** `history.cpp` stays pure (no NVS) and gains serialize/restore/reset entry points over a plain `HistorySnapshot` struct, unit-tested on the host via a new PlatformIO `native` env. `main.cpp` owns all NVS I/O: it loads + restores the blob on boot, validates freshness on the first successful fetch (comparing the saved `h5ResetEpoch` to the current one), and checkpoints after every poll.

**Tech Stack:** C++ (Arduino / ESP32), PlatformIO, ESP32 `Preferences` (NVS), Unity (native unit tests). Board: LILYGO T-Display S3 (`tdisplay-s3` env).

**Spec:** [`../specs/2026-06-26-persist-history-design.md`](../specs/2026-06-26-persist-history-design.md)

## Global Constraints

- All new firmware behavior is gated under `PAGED_UI` (`= MANGO_UI && BOARD_TDISPLAY_S3`, `config.h:71`). The `m5stick-cplus` and other non-paged builds must compile and behave exactly as before.
- Do NOT touch `src/api.cpp`, `src/crypto.cpp`, or `src/certs.cpp` — this preserves the 2026-06-25 security audit.
- Persistence store: NVS via the existing `Preferences` object, namespace `NVS_NAMESPACE` (`"claude"`, `config.h:58`), new key `"hist"`. One fixed-size key, overwritten in place.
- `HISTORY_CAP` stays `100`; no changes to History-page rendering (`ui.cpp`).
- `HISTORY_SNAPSHOT_VERSION = 1`; guard restores with a `version` byte **and** an exact-`sizeof` check.
- Checkpoint cadence: every poll. No thresholds, no coalescing.
- Restore-then-validate: restore on boot for instant display; validate (and discard if stale) on the first successful fetch, **before** that poll's `historyPush`.

---

### Task 1: Pure snapshot/restore/reset logic + native unit tests

`history.cpp` has no Arduino dependencies (it includes only `history.h` → `<stdint.h>`), so its logic is unit-testable on the host. This task adds the `HistorySnapshot` struct and three pure functions, driven by Unity tests in a new `native` env. No `main.cpp` or NVS changes here.

**Files:**
- Modify: `src/history.h` (add `HISTORY_CAP`, `HISTORY_SNAPSHOT_VERSION`, `HistorySnapshot`, 3 declarations)
- Modify: `src/history.cpp` (move the `HISTORY_CAP` define to the header; add 3 definitions)
- Modify: `platformio.ini` (add `[env:native]`)
- Test: `test/test_history/test_history.cpp` (create)

**Interfaces:**
- Consumes: existing file-static state in `history.cpp` — `s_buf[HISTORY_CAP]`, `s_head`, `s_count`, `s_have7d`, `s_prev7d`, `s_cur7d`; and existing `historyPush`, `historyCount`, `historyAt`, `historyTrend`.
- Produces (relied on by Task 2):
  - `struct HistorySnapshot { uint8_t version; uint8_t buf[HISTORY_CAP]; uint16_t head; uint16_t count; float prev7d; float cur7d; uint8_t have7d; uint32_t h5ResetEpoch; };`
  - `void historySnapshot(HistorySnapshot& out, uint32_t h5ResetEpoch);`
  - `void historyRestore(const HistorySnapshot& in);`
  - `void historyReset();`
  - macros `HISTORY_CAP` (100) and `HISTORY_SNAPSHOT_VERSION` (1).

- [ ] **Step 1: Add the `native` test env to `platformio.ini`**

Append to `platformio.ini` (compile only `history.cpp` from `src/` so the Arduino-dependent files are excluded from the host build):

```ini

[env:native]
platform = native
test_framework = unity
build_src_filter = -<*> +<history.cpp>
test_build_src = yes
```

- [ ] **Step 2: Add the struct, macros, and declarations to `src/history.h`**

Replace the entire contents of `src/history.h` with:

```c
#pragma once
#include <stdint.h>

// ~100 samples ~= 3.3h at the 120s default poll — covers most of the 5h window.
#define HISTORY_CAP 100
#define HISTORY_SNAPSHOT_VERSION 1

// Serializable mirror of the ring-buffer state, for persisting across reboots.
struct HistorySnapshot {
    uint8_t  version;            // = HISTORY_SNAPSHOT_VERSION
    uint8_t  buf[HISTORY_CAP];
    uint16_t head;
    uint16_t count;
    float    prev7d;
    float    cur7d;
    uint8_t  have7d;
    uint32_t h5ResetEpoch;       // the 5h window these samples belong to
};

// 5h-utilization ring buffer plus a 7d trend, for the History page. The 7d trend
// retains just the previous 7d value — no second buffer.
void     historyPush(float h5pct, float d7pct);
uint16_t historyCount();
uint8_t  historyAt(uint16_t i);   // 0 = oldest retained .. count-1 = newest
int      historyTrend();          // -1 falling, 0 flat, +1 rising

void historySnapshot(HistorySnapshot& out, uint32_t h5ResetEpoch); // copy RAM state out
void historyRestore(const HistorySnapshot& in);                    // load into RAM
void historyReset();                                               // clear all state
```

Then remove the now-duplicate define from `src/history.cpp`. Change the top of the file from:

```c
#include "history.h"

// ~100 samples ~= 3.3h at the 120s default poll — covers most of the 5h window.
#define HISTORY_CAP 100

static uint8_t  s_buf[HISTORY_CAP];
```

to:

```c
#include "history.h"

static uint8_t  s_buf[HISTORY_CAP];
```

- [ ] **Step 3: Write the failing test**

Create `test/test_history/test_history.cpp`:

```c
#include <unity.h>
#include "history.h"

void setUp(void)    { historyReset(); }
void tearDown(void) {}

// Snapshot then restore reproduces the exact sample sequence and count.
void test_snapshot_restore_roundtrip(void) {
    historyPush(10, 50);
    historyPush(20, 51);
    historyPush(30, 52);

    HistorySnapshot snap;
    historySnapshot(snap, 1234);

    TEST_ASSERT_EQUAL_UINT8(HISTORY_SNAPSHOT_VERSION, snap.version);
    TEST_ASSERT_EQUAL_UINT32(1234, snap.h5ResetEpoch);

    historyReset();
    TEST_ASSERT_EQUAL_UINT16(0, historyCount());

    historyRestore(snap);
    TEST_ASSERT_EQUAL_UINT16(3, historyCount());
    TEST_ASSERT_EQUAL_UINT8(10, historyAt(0));
    TEST_ASSERT_EQUAL_UINT8(20, historyAt(1));
    TEST_ASSERT_EQUAL_UINT8(30, historyAt(2));
}

// Round-trip survives ring-buffer wrap-around (head != 0, count saturated at CAP).
void test_roundtrip_after_wraparound(void) {
    for (int i = 0; i < HISTORY_CAP + 5; i++) historyPush((float)(i % 100), 0);

    uint16_t cnt    = historyCount();
    uint8_t  oldest = historyAt(0);
    uint8_t  newest = historyAt(cnt - 1);

    HistorySnapshot snap;
    historySnapshot(snap, 7);
    historyReset();
    historyRestore(snap);

    TEST_ASSERT_EQUAL_UINT16(HISTORY_CAP, historyCount());
    TEST_ASSERT_EQUAL_UINT16(cnt, historyCount());
    TEST_ASSERT_EQUAL_UINT8(oldest, historyAt(0));
    TEST_ASSERT_EQUAL_UINT8(newest, historyAt(historyCount() - 1));
}

// Reset clears the buffer.
void test_reset_clears_state(void) {
    historyPush(42, 99);
    historyReset();
    TEST_ASSERT_EQUAL_UINT16(0, historyCount());
}

// The 7d trend (prev/cur) is part of the snapshot and survives a restore.
void test_trend_survives_restore(void) {
    historyPush(0, 40);   // have7d -> true, prev=cur=40
    historyPush(0, 45);   // prev=40, cur=45 -> rising
    TEST_ASSERT_EQUAL_INT(1, historyTrend());

    HistorySnapshot snap;
    historySnapshot(snap, 0);
    historyReset();
    TEST_ASSERT_EQUAL_INT(0, historyTrend());   // reset -> flat

    historyRestore(snap);
    TEST_ASSERT_EQUAL_INT(1, historyTrend());   // restored -> rising
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_snapshot_restore_roundtrip);
    RUN_TEST(test_roundtrip_after_wraparound);
    RUN_TEST(test_reset_clears_state);
    RUN_TEST(test_trend_survives_restore);
    return UNITY_END();
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `pio test -e native`
Expected: build/link FAILS with undefined references to `historySnapshot`, `historyRestore`, `historyReset` (declared in the header in Step 2, not yet defined in `history.cpp`).

- [ ] **Step 5: Implement the three functions**

Append to `src/history.cpp`:

```c
void historySnapshot(HistorySnapshot& out, uint32_t h5ResetEpoch) {
    out.version = HISTORY_SNAPSHOT_VERSION;
    for (uint16_t i = 0; i < HISTORY_CAP; i++) out.buf[i] = s_buf[i];
    out.head         = s_head;
    out.count        = s_count;
    out.prev7d       = s_prev7d;
    out.cur7d        = s_cur7d;
    out.have7d       = s_have7d ? 1 : 0;
    out.h5ResetEpoch = h5ResetEpoch;
}

void historyRestore(const HistorySnapshot& in) {
    for (uint16_t i = 0; i < HISTORY_CAP; i++) s_buf[i] = in.buf[i];
    s_head   = in.head;
    s_count  = in.count;
    s_prev7d = in.prev7d;
    s_cur7d  = in.cur7d;
    s_have7d = in.have7d != 0;
}

void historyReset() {
    s_head   = 0;
    s_count  = 0;
    s_have7d = false;
    s_prev7d = 0.0f;
    s_cur7d  = 0.0f;
}
```

(No bounds-clamping on restore: NVS CRC-validates each entry on read and Task 2's `version` + exact-`sizeof` check reject any non-matching blob, so a same-layout blob with out-of-range fields is not a reachable state.)

- [ ] **Step 6: Run the test to verify it passes**

Run: `pio test -e native`
Expected: PASS — `4 Tests 0 Failures 0 Ignored` / `OK`.

- [ ] **Step 7: Commit**

```bash
git add src/history.h src/history.cpp platformio.ini test/test_history/test_history.cpp
git commit -m "feat: history snapshot/restore/reset + native unit tests"
```

---

### Task 2: Wire NVS persistence into `main.cpp`

Load + restore the snapshot on boot, validate freshness on the first successful fetch, and checkpoint after every poll. All edits are gated under `PAGED_UI`. Verified by building both the paged and non-paged firmware and by on-device checks (the NVS/boot wiring can't be exercised on the host).

**Files:**
- Modify: `src/main.cpp` — statics block (`main.cpp:38-40`), `setup()` NVS load (`main.cpp:218-225`), `refresh()` (`main.cpp:101-103`)

**Interfaces:**
- Consumes (from Task 1): `HistorySnapshot`, `historySnapshot`, `historyRestore`, `historyReset`, `HISTORY_SNAPSHOT_VERSION`. (`history.h` is already included at `main.cpp:23`.)
- Consumes (existing): `Preferences prefs` (`main.cpp:29`), `NVS_NAMESPACE` (`config.h:58`), `UsageData usage` with `usage.ok`, `usage.h5`, `usage.d7`, `usage.h5ResetEpoch` (`api.h:4-11`), `historyPush` (`main.cpp:102`).
- Produces: no new public interface; behavior change only.

- [ ] **Step 1: Add the boot-state statics**

In `src/main.cpp`, inside the existing `#ifdef PAGED_UI` block (currently `main.cpp:38-40`), change:

```c
#ifdef PAGED_UI
static uint8_t currentPage = 0;   // UI_PAGE_* — Button A cycles, refresh() redraws
#endif
```

to:

```c
#ifdef PAGED_UI
static uint8_t currentPage = 0;   // UI_PAGE_* — Button A cycles, refresh() redraws
static HistorySnapshot pendingHist;            // snapshot loaded from NVS on boot
static bool            havePendingHist = false; // pendingHist holds a valid blob
static bool            histValidated   = false; // first-fetch staleness check done?
#endif
```

- [ ] **Step 2: Load + restore the snapshot in `setup()`**

In `setup()`, the NVS read block is currently (`main.cpp:218-225`):

```c
    prefs.begin(NVS_NAMESPACE, true);
    String ssid = prefs.getString("ssid", "");
    String pass = prefs.getString("wifipass", "");
    EncryptedBlob blob;
    prefs.getBytes("blob", &blob, sizeof(blob));
    pollMs     = prefs.getInt("poll_sec", DEFAULT_POLL_SEC) * 1000;
    brightness = prefs.getInt("brightness", DEFAULT_BRIGHTNESS);
    prefs.end();
```

Replace it with (reads the blob while NVS is already open, then restores after closing):

```c
    prefs.begin(NVS_NAMESPACE, true);
    String ssid = prefs.getString("ssid", "");
    String pass = prefs.getString("wifipass", "");
    EncryptedBlob blob;
    prefs.getBytes("blob", &blob, sizeof(blob));
    pollMs     = prefs.getInt("poll_sec", DEFAULT_POLL_SEC) * 1000;
    brightness = prefs.getInt("brightness", DEFAULT_BRIGHTNESS);
#ifdef PAGED_UI
    size_t histBytes = prefs.getBytes("hist", &pendingHist, sizeof(pendingHist));
    havePendingHist  = (histBytes == sizeof(pendingHist) &&
                        pendingHist.version == HISTORY_SNAPSHOT_VERSION);
#endif
    prefs.end();

#ifdef PAGED_UI
    if (havePendingHist) historyRestore(pendingHist);  // show saved data immediately
#endif
```

- [ ] **Step 3: Validate-then-push-then-checkpoint in `refresh()`**

In `refresh()`, replace (`main.cpp:101-103`):

```c
#ifdef PAGED_UI
    if (usage.ok) historyPush(usage.h5, usage.d7);
#endif
```

with:

```c
#ifdef PAGED_UI
    if (usage.ok) {
        if (!histValidated) {
            // First good fetch after boot: if the 5h window rolled over while we
            // were off, the restored samples are stale — drop them.
            if (havePendingHist && pendingHist.h5ResetEpoch != usage.h5ResetEpoch)
                historyReset();
            histValidated = true;
        }
        historyPush(usage.h5, usage.d7);

        HistorySnapshot snap;
        historySnapshot(snap, usage.h5ResetEpoch);
        prefs.begin(NVS_NAMESPACE, false);
        prefs.putBytes("hist", &snap, sizeof(snap));
        prefs.end();
    }
#endif
```

- [ ] **Step 4: Build the paged firmware**

Run: `pio run -e tdisplay-s3`
Expected: `SUCCESS` (compiles and links; flash/RAM usage reported).

- [ ] **Step 5: Build a non-paged firmware to confirm no regression**

Run: `pio run -e m5stick-cplus`
Expected: `SUCCESS`. `m5stick-cplus` defines neither `MANGO_UI`+`BOARD_TDISPLAY_S3`, so `PAGED_UI` is undefined and every change above is excluded — the build is byte-for-behavior unchanged.

- [ ] **Step 6: Flash and verify on-device**

Run: `pio run -e tdisplay-s3 -t upload`
Then check on the device:
1. **Persist across reboot (same window):** open the History page, let several polls accumulate samples, unplug/replug (or press reset). After unlock the History sparkline returns **populated** (not empty) and keeps filling.
2. **Discard when stale:** with saved history present, force a window change — easiest is to wait past a real 5h reset while powered off, or temporarily flash a build whose fetched `h5ResetEpoch` differs. On the first fetch after boot the sparkline **clears** and restarts.
3. **First-ever boot:** on a device with no `"hist"` key (e.g. after a factory reset, A+B held at boot), the History page starts **empty** with no error on the serial monitor.
4. **No regression:** PIN unlock, WiFi connect, factory reset (A+B at boot), and the WiFi portal (B at boot) all behave as before.

- [ ] **Step 7: Commit**

```bash
git add src/main.cpp
git commit -m "feat: persist history to NVS, discard on 5h window rollover"
```

---

## Notes for the implementer

- The `native` env exists only for `pio test`; it is not a firmware target. If `pio test -e native` can't find the host toolchain, ensure Xcode Command Line Tools are installed (`xcode-select --install`).
- **If the failing run in Task 1 Step 4 reports `historyPush`/`historyCount` (the *existing* functions) as undefined too**, then `src/` wasn't compiled — your PlatformIO version uses a different option name. Replace `test_build_src = yes` with `test_build_project_src = yes` (the pre-6.x name) and re-run. The expected failure names only the three *new* functions.
- The freshness comparison itself (`pendingHist.h5ResetEpoch != usage.h5ResetEpoch`) lives in `main.cpp` and is a trivial `uint32_t` inequality, so it is verified on-device (Task 2 Step 6 check 2), not in the native unit tests. The error-prone serialization it gates *is* unit-tested in Task 1.
- The checkpoint write (`putBytes`) is intentionally unchecked: history is best-effort, a failed write must never crash or block `refresh()`, and at one fixed ~120-byte key in a 20 KB NVS partition a write failure is not a reachable state. This satisfies the spec's "best-effort, never fatal" handling.
- `prefs` is a single shared `Preferences` object; every `prefs.begin(...)` must be paired with a `prefs.end()`. The checkpoint in Task 2 Step 3 opens RW and closes within the same block, matching the existing pattern at `main.cpp:95-98`.
- Validation runs once per boot (`histValidated`), and only on a successful fetch — so a boot with no network keeps showing the restored data until the first fetch lands, then validates.
