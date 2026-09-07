/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_APPLE_DISPLAY_HOTPLUG_H
#define VINIX_APPLE_DISPLAY_HOTPLUG_H

#include <stddef.h>
#include <stdint.h>

/* The CD321x Type-C controller reports cable presence separately from its
 * negotiated data mode and DisplayPort hot-plug level.  First attach must not
 * wait for HPD: HPD can remain low until an external DCP has been started,
 * which is exactly what the firmware-assisted reboot is meant to arrange.
 * Treat physical presence plus a negotiated display-capable mode as attached
 * and debounce that combined value. This small core is deliberately free of
 * MMIO, allocation, locks and timing primitives so it can be tested on the
 * host and driven by the kernel's polling worker.
 */
enum vinix_display_hotplug_event {
    VINIX_DISPLAY_HOTPLUG_NONE = 0,
    VINIX_DISPLAY_HOTPLUG_CONNECTED = 1,
    VINIX_DISPLAY_HOTPLUG_DISCONNECTED = 2,
};

/* Action selected after a debounced event.  The only cold-attach recovery
 * currently available on a base M1 is to let iBoot/m1n1 retrain the link on a
 * warm boot.  Restrict that recovery to the M1 Air's exact built-in panel
 * mode; an unknown or already-external framebuffer must never be rebooted. */
enum vinix_display_hotplug_action {
    VINIX_DISPLAY_HOTPLUG_IGNORE = 0,
    VINIX_DISPLAY_HOTPLUG_REPAINT = 1,
    VINIX_DISPLAY_HOTPLUG_REBOOT = 2,
};

enum {
    VINIX_CD321X_STATUS_PLUG_PRESENT = 1u << 0,
    VINIX_CD321X_DATA_CONNECTION = 1u << 0,
    VINIX_CD321X_DATA_DP_CONNECTION = 1u << 8,
    VINIX_CD321X_DATA_TBT_CONNECTION = 1u << 16,
    VINIX_CD321X_DATA_HPD_LEVEL = 1u << 15,
    VINIX_CD321X_DATA_USB4_CONNECTION = 1u << 23,
};

struct vinix_display_hotplug_state {
    uint64_t candidate_since_ms;
    uint32_t status;
    uint32_t data_status;
    uint8_t stable;
    uint8_t candidate;
    uint8_t initialized;
};

size_t vinix_display_hotplug_state_size(void);
void vinix_display_hotplug_reset(struct vinix_display_hotplug_state *state);
int vinix_display_hotplug_sample(struct vinix_display_hotplug_state *state,
                                 uint32_t status, uint32_t data_status,
                                 uint64_t now_ms, uint64_t debounce_ms);
int vinix_display_hotplug_connected(const struct vinix_display_hotplug_state *state);
int vinix_display_hotplug_candidate(uint32_t status, uint32_t data_status);
int vinix_display_hotplug_choose_action(int connected, int reboot_enabled,
                                        int reboot_attempted,
                                        uint64_t framebuffer_width,
                                        uint64_t framebuffer_height);

#endif
