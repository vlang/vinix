/* SPDX-License-Identifier: GPL-2.0-only */
#include "apple_display_hotplug.h"

size_t vinix_display_hotplug_state_size(void)
{
    return sizeof(struct vinix_display_hotplug_state);
}

void vinix_display_hotplug_reset(struct vinix_display_hotplug_state *state)
{
    if (!state)
        return;
    *state = (struct vinix_display_hotplug_state){0};
}

int vinix_display_hotplug_candidate(uint32_t status, uint32_t data_status)
{
    const uint32_t display_mode = VINIX_CD321X_DATA_DP_CONNECTION |
                                  VINIX_CD321X_DATA_TBT_CONNECTION |
                                  VINIX_CD321X_DATA_USB4_CONNECTION;

    return !!((status & VINIX_CD321X_STATUS_PLUG_PRESENT) &&
              (data_status & VINIX_CD321X_DATA_CONNECTION) &&
              (data_status & display_mode) &&
              (data_status & VINIX_CD321X_DATA_HPD_LEVEL));
}

int vinix_display_hotplug_sample(struct vinix_display_hotplug_state *state,
                                 uint32_t status, uint32_t data_status,
                                 uint64_t now_ms, uint64_t debounce_ms)
{
    if (!state)
        return VINIX_DISPLAY_HOTPLUG_NONE;

    int connected = vinix_display_hotplug_candidate(status, data_status);
    state->status = status;
    state->data_status = data_status;

    if (!state->initialized) {
        state->initialized = 1;
        state->stable = (uint8_t)connected;
        state->candidate = (uint8_t)connected;
        state->candidate_since_ms = now_ms;
        return VINIX_DISPLAY_HOTPLUG_NONE;
    }

    if ((int)state->candidate != connected) {
        state->candidate = (uint8_t)connected;
        state->candidate_since_ms = now_ms;
        return VINIX_DISPLAY_HOTPLUG_NONE;
    }

    if (state->stable == state->candidate)
        return VINIX_DISPLAY_HOTPLUG_NONE;

    /* Unsigned subtraction also behaves correctly across a counter wrap. */
    if (now_ms - state->candidate_since_ms < debounce_ms)
        return VINIX_DISPLAY_HOTPLUG_NONE;

    state->stable = state->candidate;
    return state->stable ? VINIX_DISPLAY_HOTPLUG_CONNECTED
                         : VINIX_DISPLAY_HOTPLUG_DISCONNECTED;
}

int vinix_display_hotplug_connected(const struct vinix_display_hotplug_state *state)
{
    return state && state->initialized && state->stable;
}

int vinix_display_hotplug_choose_action(int connected, int reboot_enabled,
                                        int reboot_attempted,
                                        uint64_t framebuffer_width,
                                        uint64_t framebuffer_height)
{
    if (!connected)
        return VINIX_DISPLAY_HOTPLUG_IGNORE;

    if (reboot_enabled && !reboot_attempted &&
        framebuffer_width == UINT64_C(2560) &&
        framebuffer_height == UINT64_C(1600))
        return VINIX_DISPLAY_HOTPLUG_REBOOT;

    return VINIX_DISPLAY_HOTPLUG_REPAINT;
}
