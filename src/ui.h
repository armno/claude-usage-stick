#pragma once
#include "config.h"
#include "api.h"
#ifdef MANGO_UI
#include "status.h"
#endif

void uiInit();
void uiBootProgress(int percent, const char* label);
void uiSetupScreen(const char* apName, const char* apPass);
void uiPinScreen(int pos, const int digits[4]);
void uiConnecting(const char* ssid, int attempt = 0);
void uiDashboard(const UsageData& data, unsigned long lastFetchMs, int rssi, int batPct);
// Lightweight in-place update of the clock + reset countdowns (no bars, no full clear)
// so the periodic refresh doesn't flicker. Call when only time has passed, not data.
void uiDashboardClock(const UsageData& data, unsigned long lastFetchMs, int rssi);
void uiError(const char* title, const char* detail = nullptr);
void uiLockout(int attempts, int maxAttempts, int lockoutSec);
#ifdef MANGO_UI
// Latest model health for the dashboard's mascot row; cached until the next call.
void uiSetModelStatus(const ModelStatus& s);
// Flip the panel 180° (and clear it); caller redraws the current screen.
void uiToggleRotation();
// Close (true) or open (false) the healthy mascots' eyes on the dashboard.
// On PAGED_UI boards, call only while UI_PAGE_MODELS is active (2x2-grid coords).
void uiBlinkTick(bool closed);
#ifdef PAGED_UI
// Multi-page UI (T-Display S3). Pages are dispatched internally by uiRenderPage;
// main.cpp drives navigation via currentPage and uiPageCount().
enum UiPage { UI_PAGE_USAGE, UI_PAGE_MODELS, UI_PAGE_COUNT };
uint8_t uiPageCount();
// 5h alert level for the header dot + flash: 0 ok, 1 warn, 2 critical.
void uiSetAlertLevel(int level);
// One full-screen flash on the OK/warn -> critical crossing (edge-triggered by caller).
void uiAlertFlash();
// Full draw of one page (clears + header + body). Replaces uiDashboard on the S3.
void uiRenderPage(uint8_t page, const UsageData& data, unsigned long lastFetchMs, int rssi, int batPct);
// In-place time tick for the current page (no full clear) — replaces uiDashboardClock.
void uiRenderPageClock(uint8_t page, const UsageData& data, unsigned long lastFetchMs, int rssi);
#endif // PAGED_UI
#endif // MANGO_UI
