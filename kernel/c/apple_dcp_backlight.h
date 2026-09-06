/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef VINIX_APPLE_DCP_BACKLIGHT_H
#define VINIX_APPLE_DCP_BACKLIGHT_H

#include <stddef.h>
#include <stdint.h>

/* These select verified wire layouts, NOT a >= firmware-version test. */
enum vinix_dcp_bl_layout {
    VINIX_DCP_BL_LAYOUT_12_3 = 1,
    VINIX_DCP_BL_LAYOUT_13_3 = 2,
};

enum vinix_dcp_bl_result {
    VINIX_DCP_BL_OK = 0,
    VINIX_DCP_BL_IDLE = 1,
    VINIX_DCP_BL_INVALID = -1,
    VINIX_DCP_BL_UNSUPPORTED = -2,
    VINIX_DCP_BL_OFFLINE = -3,
    VINIX_DCP_BL_BUSY = -4,
    VINIX_DCP_BL_STALE = -5,
    VINIX_DCP_BL_OVERFLOW = -6,
};

#define VINIX_DCP_BL_MIN_NITS 2U
/* The upstream calibration is used strictly below its 510-nit endpoint. */
#define VINIX_DCP_BL_MAX_NITS 509U
#define VINIX_DCP_BL_TEXT_CAPACITY 192U
#define VINIX_DCP_BL_WRITE_LIMIT 16U
#define VINIX_DCP_BL_PROPERTY_NITS 15U

/* Opaque, caller-owned, normally aligned storage. No allocation or MMIO here.
 * Serialize ALL calls for one instance; this module does not own a lock.
 * Initialise once per lifetime, not once per firmware restart. */
struct vinix_dcp_bl;
size_t vinix_dcp_bl_state_size(void);
int vinix_dcp_bl_init(struct vinix_dcp_bl *bl, unsigned layout,
                      uint32_t panel_max_nits, uint32_t brightness_scale,
                      uint32_t initial_raw_nits, int initial_valid);

/* Must be driven by a real DCP transport. Offline cancels the in-flight
 * token, invalidates actual brightness and preserves the user's request.
 * Online requeues that request, but never changes the boot brightness
 * merely because the driver was registered. Old callbacks stay stale. */
int vinix_dcp_bl_set_online(struct vinix_dcp_bl *bl, int online);
int vinix_dcp_bl_request(struct vinix_dcp_bl *bl, uint32_t nits);
int vinix_dcp_bl_write(struct vinix_dcp_bl *bl, const void *text, size_t length);

/* Called with the real version-selected dcp_swap at the start of a real
 * swap_submit request, NOT Vinix's simplified IomfbSwapDesc. Only the 13
 * backlight bytes change. Caller owns the complete RPC, DMA visibility,
 * callback dispatch, bounded timeouts, and preservation of scanout surfaces.
 * IDLE means no modification; token is only written on OK. */
int vinix_dcp_bl_prepare(struct vinix_dcp_bl *bl, void *swap, size_t length,
                         uint64_t *token);
/* accepted != 0 only after a matching, successful firmware response.
 * A timeout must first fault/quiesce the transport before another RPC is
 * attempted. Clearing a software token does not make a channel reusable. */
int vinix_dcp_bl_complete(struct vinix_dcp_bl *bl, uint64_t token, int accepted);
/* Consume IOMFB_PROPERTY_NITS, divided by the firmware's Brightness_Scale.
 * Neither queueing a request nor a successful RPC fabricates this value. */
int vinix_dcp_bl_publish(struct vinix_dcp_bl *bl, uint32_t raw_nits);
int vinix_dcp_bl_format(const struct vinix_dcp_bl *bl, char *text, size_t capacity);

/* Pure helpers, exported for protocol/golden-vector tests. */
int vinix_dcp_bl_nits_to_dac(uint32_t nits, uint32_t *dac);
int vinix_dcp_bl_parse(const void *text, size_t length, uint32_t *nits);
int vinix_dcp_bl_patch_swap(unsigned layout, uint32_t nits,
                            void *swap, size_t length);

#endif
