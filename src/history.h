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
