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
