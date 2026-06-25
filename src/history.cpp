#include "history.h"

// ~100 samples ~= 3.3h at the 120s default poll — covers most of the 5h window.
#define HISTORY_CAP 100

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
