/* SPDX-License-Identifier: GPL-2.0-only */
/* Keep this first: a prior kernel.h include would conceal missing dependencies
 * of the unchanged DRM header's LUT rounding and clamp implementation. */
#include <drm/drm_color_mgmt.h>
#include <assert.h>

int main(void)
{
    const struct {
        u32 input;
        int precision;
        u32 expected;
    } cases[] = {
        { 0x0000, 1, 0 }, { 0x3fff, 1, 0 }, { 0x4000, 1, 1 },
        { 0x8000, 1, 1 }, { 0xc000, 1, 1 }, { 0xffff, 1, 1 },
        { 0x0000, 8, 0 }, { 0x007f, 8, 0 }, { 0x0080, 8, 1 },
        { 0x8000, 8, 128 }, { 0xff7f, 8, 255 }, { 0xff80, 8, 255 },
        { 0xffff, 8, 255 },
        { 0x0000, 10, 0 }, { 0x001f, 10, 0 }, { 0x0020, 10, 1 },
        { 0x8000, 10, 512 }, { 0xffdf, 10, 1023 }, { 0xffe0, 10, 1023 },
        { 0xffff, 10, 1023 },
        { 0x0000, 12, 0 }, { 0x0007, 12, 0 }, { 0x0008, 12, 1 },
        { 0x8000, 12, 2048 }, { 0xfff7, 12, 4095 }, { 0xfff8, 12, 4095 },
        { 0xffff, 12, 4095 },
        { 0x0000, 16, 0 }, { 0x0001, 16, 1 }, { 0x8000, 16, 32768 },
        { 0xffff, 16, 65535 }, { 0x10000, 16, 65535 }, { 0xffffffff, 16, 65535 },
    };
    for (unsigned int i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        /* Force the real runtime precision branch, including half-step ties
         * and rounding into the high clamp. Expected results are fixed values. */
        volatile u32 input = cases[i].input;
        volatile int precision = cases[i].precision;
        assert(drm_color_lut_extract(input, precision) == cases[i].expected);
    }

    /* Full precision retains every value the u16 userspace LUT can carry. */
    for (u32 input = 0; input <= 0xffff; input++)
        assert(drm_color_lut_extract(input, 16) == input);
    return 0;
}
