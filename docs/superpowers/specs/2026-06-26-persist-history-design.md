# Persist History Across Reboots — Design

**Date:** 2026-06-26
**Repo:** armno/claude-usage-stick (fork of oauramos/claude-usage-stick)
**Board scope:** LILYGO T-Display S3 (`tdisplay-s3` env), `PAGED_UI` only. Other boards unaffected — see Compatibility.
**Status:** Approved design, pending implementation plan.
**Supersedes:** the "History: RAM-only, lost on reboot" decision in
[`2026-06-25-paged-ui-alerts-design.md`](2026-06-25-paged-ui-alerts-design.md) (§Decisions 2,
§Out of scope) and the matching backlog item in [`../BACKLOG.md`](../BACKLOG.md).

## Problem / Goal

The History page (page 2) draws a 5h-utilization sparkline from a RAM ring buffer
(`history.cpp`, `HISTORY_CAP` 100). It is **RAM-only**, so every reboot — firmware reflash,
power blip, accidental unplug — wipes ~3.3h of accumulated samples and the sparkline restarts
empty.

Goal: **survive a reboot** by checkpointing the buffer to NVS and restoring it on boot —
without ever showing *misleading* data. If the device was off long enough that the 5h window
rolled over while it was down, the restored samples belong to a past window and must be
discarded, not stitched onto fresh ones.

Non-goal: extending coverage. The buffer stays 100 samples (~3.3h). A longer window or a real
7d sparkline is a separate backlog item; this change must not touch History-page rendering.

## Scope

T-Display S3, `PAGED_UI` only (history exists only there). The persisted blob lives in the
existing `Preferences` namespace `"claude"` (`config.h:58`) alongside the WiFi creds, encrypted
token, and config — a new key, no namespace change. `api.cpp` / `crypto.cpp` / `certs.cpp` are
not touched.

## Architecture

Two responsibilities, kept apart:

- **`history.cpp` stays pure** — it owns the ring buffer and knows nothing about NVS. It gains
  serialize / restore / reset entry points operating on a plain struct.
- **`main.cpp` owns persistence** — it already holds the `Preferences` object and the NVS
  load/save plumbing (`main.cpp:218-225`, `main.cpp:243`). It reads/writes the blob and makes
  the freshness decision.

This keeps `history.cpp` testable in isolation and confines flash I/O to where it already lives.

### Snapshot struct (`history.h`)

```c
struct HistorySnapshot {       // ~120 bytes incl. struct padding, POD
    uint8_t  version;          // = HISTORY_SNAPSHOT_VERSION (1); guards layout changes
    uint8_t  buf[HISTORY_CAP]; // the 5h-utilization ring buffer
    uint16_t head;
    uint16_t count;
    float    prev7d;
    float    cur7d;
    uint8_t  have7d;
    uint32_t h5ResetEpoch;     // the 5h window these samples belong to (UsageData.h5ResetEpoch)
};

void historySnapshot(HistorySnapshot& out, uint32_t h5ResetEpoch); // copy RAM state out + stamp window
void historyRestore(const HistorySnapshot& in);                    // load struct into RAM
void historyReset();                                               // clear (head=count=0, have7d=false)
```

`historySnapshot`/`historyRestore` are a straight copy of the file-static state already in
`history.cpp` (`s_buf`, `s_head`, `s_count`, `s_have7d`, `s_prev7d`, `s_cur7d`). `historyReset`
is the stale-data escape hatch.

### Freshness check — "same 5h window?"

`UsageData` already carries `h5ResetEpoch` (`api.h:7`), the absolute epoch of the upcoming 5h
reset. It is constant within a window and jumps forward by ~5h at each reset. So:

> samples are valid to restore **iff** their saved `h5ResetEpoch` equals the current fetch's
> `h5ResetEpoch`.

This is a data-value comparison — no wall-clock, no NTP-at-save dependency, no fixed time
threshold to tune. Any rollover (even multiple resets across a long off-period) changes the
value and triggers a discard.

## Control flow (restore-then-validate)

Order within `refresh()`: fetch → (first success only) validate/discard → `historyPush` →
checkpoint. Validation must run **before** the push, so the stale-window reset never throws away
the freshly pushed post-boot sample.

**1. setup() — load immediately.** After the existing NVS load block (`main.cpp:225`), read
the blob into a module-static `pendingHist`:

```
got = prefs.getBytes("hist", &pendingHist, sizeof(pendingHist));
havePending = (got == sizeof(pendingHist) && pendingHist.version == HISTORY_SNAPSHOT_VERSION);
if (havePending) historyRestore(pendingHist);   // show saved data right away
```

Restoring up front means the sparkline is populated the moment the History page is first
opened, instead of waiting a poll cycle.

**2. refresh(), first successful fetch only — validate, discard if stale.** A `static bool
histValidated = false` runs this once:

```
if (!histValidated && usage.ok) {
    if (havePending && pendingHist.h5ResetEpoch != usage.h5ResetEpoch)
        historyReset();        // window rolled over while off → drop stale samples
    histValidated = true;
}
```

Validation deferred to first fetch (not setup) because that is when the *current*
`h5ResetEpoch` is known. The worst case — briefly showing stale data on the non-default History
page in the seconds between boot and first fetch — is corrected the instant a fetch lands.

**3. refresh(), every poll after `historyPush` — checkpoint.** Right after the existing
`historyPush(usage.h5, usage.d7)` (`main.cpp:102`):

```
HistorySnapshot snap;
historySnapshot(snap, usage.h5ResetEpoch);
prefs.begin(NVS_NAMESPACE, false);
prefs.putBytes("hist", &snap, sizeof(snap));
prefs.end();
```

Cadence is every poll (~120s default). At ~116 bytes overwritten under a single key, NVS
garbage collection / wear-leveling yields ~20+ year flash life — no reason to coalesce or add a
threshold.

## Error handling — best-effort, never fatal

- **First-ever boot / no key:** `getBytes` returns 0 ≠ `sizeof` → `havePending=false` → fresh
  start.
- **Layout change across a firmware update:** size mismatch *or* `version` mismatch → treated as
  no data → fresh start. (Bump `HISTORY_SNAPSHOT_VERSION` when the struct changes.)
- **`putBytes` failure (NVS full / error):** log at debug level, ignore. History is
  non-critical; a failed checkpoint must never crash or block the refresh loop.

## Compatibility

- All new code gated under `PAGED_UI`. The `m5stick-cplus` and other non-paged builds compile
  and behave exactly as before.
- `api.cpp` / `crypto.cpp` / `certs.cpp` untouched → the 2026-06-25 security audit (egress,
  TLS, token handling) stays valid; no re-audit needed.
- No new partition / `platformio.ini` changes. NVS partition (`default.csv`, 20 KB) has ample
  headroom for one ~120-byte key.

## Decisions (resolved)

1. **Persistence store:** NVS (`Preferences`), key `"hist"`, namespace `"claude"`. Single
   fixed-size key overwritten in place → storage stays bounded, no app-level cleanup needed.
2. **Staleness:** discard if the saved `h5ResetEpoch` ≠ the current one (window rolled over
   while off). Restore-then-validate so valid data shows instantly.
3. **Cadence:** checkpoint every poll. No threshold, no coalescing.
4. **Scope:** buffer stays 100 samples (~3.3h). No History-page rendering changes.
5. **7d trend:** the `prev7d`/`cur7d`/`have7d` state is persisted too (it rides in the same
   struct, free).
6. **Layout safety:** `version` byte + exact-size check guard against loading incompatible
   blobs after a firmware change.

## Out of scope (YAGNI)

- Extending coverage beyond ~3.3h (longer window / decimated 7d sparkline) — separate backlog
  item.
- SPIFFS-file history log (days/weeks). Not needed; would add pruning + fragmentation concerns
  the ring-buffer-in-NVS approach avoids.
- Runtime-configurable cadence or staleness threshold.

## Verification (manual, on-device)

No unit-test harness exists for the firmware; verified on hardware. (If a native test env is
added during planning, the `historySnapshot`→`historyRestore` round-trip and the
`h5ResetEpoch` comparison are pure logic and can be covered there.)

1. **Builds:** `pio run -e tdisplay-s3` succeeds; `m5stick-cplus` still builds unchanged.
2. **Persist across reboot (same window):** let the History page accumulate several samples,
   reboot, confirm the sparkline comes back populated (not empty) — and continues filling.
3. **Discard when stale:** simulate a window rollover (e.g. a fetch whose `h5ResetEpoch`
   differs from the saved one, or wait past a real 5h reset while powered off) → on the first
   fetch after boot the sparkline clears and restarts fresh.
4. **First-ever boot:** with no `"hist"` key present, boot starts with an empty sparkline and no
   error.
5. **No regression:** PIN unlock, WiFi connect, factory reset (A+B at boot), and the WiFi
   portal (B at boot) all behave as before — the new key shares the namespace without disturbing
   existing keys.
