#pragma once
#include <stdint.h>

// 5h-utilization ring buffer (RAM only; lost on reboot) plus a 7d trend, for the
// History page. The 7d trend retains just the previous 7d value — no second buffer.
void     historyPush(float h5pct, float d7pct);
uint16_t historyCount();
uint8_t  historyAt(uint16_t i);   // 0 = oldest retained .. count-1 = newest
int      historyTrend();          // -1 falling, 0 flat, +1 rising
