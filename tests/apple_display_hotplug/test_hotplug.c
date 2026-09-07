#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "../../kernel/c/apple_display_hotplug.h"

#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "check failed at line %d: %s\n", __LINE__, #x); \
    return 1; \
} } while (0)

static uint32_t display_status(uint32_t transport)
{
    return VINIX_CD321X_DATA_CONNECTION |
           VINIX_CD321X_DATA_HPD_LEVEL | transport;
}

int main(void)
{
    struct vinix_display_hotplug_state state;
    CHECK(vinix_display_hotplug_state_size() == sizeof(state));
    CHECK(vinix_display_hotplug_sample(NULL, 0, 0, 0, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(!vinix_display_hotplug_connected(NULL));
    vinix_display_hotplug_reset(&state);

    CHECK(!vinix_display_hotplug_candidate(0, 0));
    CHECK(!vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT,
          display_status(0)));
    CHECK(!vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT,
          VINIX_CD321X_DATA_CONNECTION | VINIX_CD321X_DATA_DP_CONNECTION));
    CHECK(vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT,
          display_status(VINIX_CD321X_DATA_DP_CONNECTION)));
    CHECK(vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT,
          display_status(VINIX_CD321X_DATA_TBT_CONNECTION)));
    CHECK(vinix_display_hotplug_candidate(VINIX_CD321X_STATUS_PLUG_PRESENT,
          display_status(VINIX_CD321X_DATA_USB4_CONNECTION)));

    CHECK(vinix_display_hotplug_sample(&state, 0, 0, 100, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(!vinix_display_hotplug_connected(&state));

    uint32_t data = display_status(VINIX_CD321X_DATA_TBT_CONNECTION);
    CHECK(vinix_display_hotplug_sample(&state,
          VINIX_CD321X_STATUS_PLUG_PRESENT, data, 200, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(vinix_display_hotplug_sample(&state,
          VINIX_CD321X_STATUS_PLUG_PRESENT, data, 699, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(vinix_display_hotplug_sample(&state,
          VINIX_CD321X_STATUS_PLUG_PRESENT, data, 700, 500) ==
          VINIX_DISPLAY_HOTPLUG_CONNECTED);
    CHECK(vinix_display_hotplug_connected(&state));

    /* A short HPD pulse must not disconnect a working display. */
    CHECK(vinix_display_hotplug_sample(&state,
          VINIX_CD321X_STATUS_PLUG_PRESENT,
          data & ~VINIX_CD321X_DATA_HPD_LEVEL, 800, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(vinix_display_hotplug_sample(&state,
          VINIX_CD321X_STATUS_PLUG_PRESENT, data, 900, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(vinix_display_hotplug_connected(&state));

    CHECK(vinix_display_hotplug_sample(&state, 0, 0, 1000, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(vinix_display_hotplug_sample(&state, 0, 0, 1500, 500) ==
          VINIX_DISPLAY_HOTPLUG_DISCONNECTED);
    CHECK(!vinix_display_hotplug_connected(&state));

    /* A connection that disappears inside the debounce window is ignored. */
    CHECK(vinix_display_hotplug_sample(&state,
          VINIX_CD321X_STATUS_PLUG_PRESENT, data, 1600, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(vinix_display_hotplug_sample(&state, 0, 0, 1900, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(!vinix_display_hotplug_connected(&state));

    /* Debouncing uses modulo time so a monotonic counter wrap is harmless. */
    vinix_display_hotplug_reset(&state);
    CHECK(vinix_display_hotplug_sample(&state, 0, 0, UINT64_MAX - 300, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(vinix_display_hotplug_sample(&state,
          VINIX_CD321X_STATUS_PLUG_PRESENT, data, UINT64_MAX - 200, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(vinix_display_hotplug_sample(&state,
          VINIX_CD321X_STATUS_PLUG_PRESENT, data, 298, 500) ==
          VINIX_DISPLAY_HOTPLUG_NONE);
    CHECK(vinix_display_hotplug_sample(&state,
          VINIX_CD321X_STATUS_PLUG_PRESENT, data, 299, 500) ==
          VINIX_DISPLAY_HOTPLUG_CONNECTED);

    /* First attach recovery is deliberately narrow and one-shot. */
    CHECK(vinix_display_hotplug_choose_action(0, 1, 0, 2560, 1600) ==
          VINIX_DISPLAY_HOTPLUG_IGNORE);
    CHECK(vinix_display_hotplug_choose_action(1, 0, 0, 2560, 1600) ==
          VINIX_DISPLAY_HOTPLUG_REPAINT);
    CHECK(vinix_display_hotplug_choose_action(1, 1, 0, 2560, 1600) ==
          VINIX_DISPLAY_HOTPLUG_REBOOT);
    CHECK(vinix_display_hotplug_choose_action(1, 1, 1, 2560, 1600) ==
          VINIX_DISPLAY_HOTPLUG_REPAINT);
    CHECK(vinix_display_hotplug_choose_action(1, 1, 0, 5120, 2880) ==
          VINIX_DISPLAY_HOTPLUG_REPAINT);
    CHECK(vinix_display_hotplug_choose_action(1, 1, 0, 0, 0) ==
          VINIX_DISPLAY_HOTPLUG_REPAINT);

    puts("apple display hotplug state tests passed");
    return 0;
}
