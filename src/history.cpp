#include "history.h"

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
