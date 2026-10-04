/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(VINIX_LINUXKPI) && !defined(VINIX_LINUXKPI_HOST_TEST)
#include <i915_config.h>
#include <display/intel_qp_tables.h>
#include <drm/display/drm_dsc.h>
#include <linux/array_size.h>
#include <linux/errno.h>
#include <linux/jiffies.h>
#include <linux/kdev_t.h>
#include <linux/sprintf.h>
#include <linux/string.h>
#include <vinix/runtime.h>

_Static_assert(HZ == 1000 && CONFIG_DRM_I915_FENCE_TIMEOUT == 10000,
               "Use the pinned i915 fence timeout policy at native HZ");
_Static_assert(sizeof(dev_t) == 4 && (dev_t)-1 > 0 && MINORBITS == 20,
               "Linux internal dev_t is unsigned 12:20, not Vinix Stat.dev");
_Static_assert(DSC_NUM_BUF_RANGES == 15, "Pinned DSC tables contain 15 ranges");

#define POLICY_EXPECT(condition) do { if (!(condition)) return -EIO; } while (0)

static int native_i915_qp_tables(void)
{
    /* Literal values from Linux 6.6.157's tables, including first/last rows
     * and columns. The original functions, rather than copied tables, run. */
    static const struct {
        int bpc, row, column;
        bool is_420;
        u8 minimum, maximum;
    } goldens[] = {
        { 8, 0, 0, false, 0, 4 }, { 8, 0, 36, false, 0, 0 },
        { 8, 14, 0, false, 14, 15 }, { 8, 14, 36, false, 3, 4 },
        { 8, 3, 2, false, 2, 7 }, { 8, 7, 18, false, 2, 4 },
        { 8, 10, 34, false, 1, 2 }, { 8, 13, 6, false, 7, 11 },
        { 10, 0, 0, false, 0, 8 }, { 10, 0, 48, false, 0, 0 },
        { 10, 14, 0, false, 18, 19 }, { 10, 14, 48, false, 3, 4 },
        { 10, 3, 2, false, 6, 11 }, { 10, 7, 24, false, 5, 7 },
        { 10, 10, 46, false, 1, 2 }, { 10, 13, 6, false, 12, 15 },
        { 12, 0, 0, false, 0, 12 }, { 12, 0, 60, false, 0, 0 },
        { 12, 14, 0, false, 22, 23 }, { 12, 14, 60, false, 3, 4 },
        { 12, 3, 2, false, 10, 15 }, { 12, 7, 30, false, 7, 8 },
        { 12, 10, 58, false, 1, 2 }, { 12, 13, 6, false, 15, 19 },
        { 8, 0, 0, true, 0, 4 }, { 8, 0, 16, true, 0, 0 },
        { 8, 14, 0, true, 13, 14 }, { 8, 14, 16, true, 3, 4 },
        { 8, 3, 2, true, 1, 6 }, { 8, 7, 8, true, 2, 4 },
        { 8, 10, 14, true, 2, 3 }, { 8, 13, 6, true, 7, 9 },
        { 10, 0, 0, true, 0, 8 }, { 10, 0, 22, true, 0, 0 },
        { 10, 14, 0, true, 17, 18 }, { 10, 14, 22, true, 4, 5 },
        { 10, 3, 2, true, 5, 10 }, { 10, 7, 11, true, 5, 7 },
        { 10, 10, 20, true, 2, 3 }, { 10, 13, 6, true, 11, 13 },
        { 12, 0, 0, true, 0, 11 }, { 12, 0, 28, true, 0, 0 },
        { 12, 14, 0, true, 21, 22 }, { 12, 14, 28, true, 4, 5 },
        { 12, 3, 2, true, 9, 13 }, { 12, 7, 14, true, 8, 9 },
        { 12, 10, 26, true, 2, 3 }, { 12, 13, 6, true, 15, 17 },
    };
    for (unsigned int i = 0; i < ARRAY_SIZE(goldens); i++) {
        POLICY_EXPECT(intel_lookup_range_min_qp(goldens[i].bpc, goldens[i].row,
                    goldens[i].column, goldens[i].is_420) == goldens[i].minimum);
        POLICY_EXPECT(intel_lookup_range_max_qp(goldens[i].bpc, goldens[i].row,
                    goldens[i].column, goldens[i].is_420) == goldens[i].maximum);
    }
    static const struct { int bpc, columns; bool is_420; } families[] = {
        { 8, 37, false }, { 10, 49, false }, { 12, 61, false },
        { 8, 17, true }, { 10, 23, true }, { 12, 29, true },
    };
    /* All storage-valid table indices, including half-step columns. The
     * 4:4:4 caller uses 2*(bpp-6); 4:2:0 uses doubled PPS bpp minus 8.
     * Neither helper checks indices; never probe outside these bounds. */
    for (unsigned int i = 0; i < ARRAY_SIZE(families); i++)
        for (int row = 0; row < DSC_NUM_BUF_RANGES; row++)
            for (int column = 0; column < families[i].columns; column++) {
                u8 minimum = intel_lookup_range_min_qp(families[i].bpc, row,
                        column, families[i].is_420);
                u8 maximum = intel_lookup_range_max_qp(families[i].bpc, row,
                        column, families[i].is_420);
                POLICY_EXPECT(minimum <= maximum);
                POLICY_EXPECT(maximum <= 23);
            }
    return 0;
}

static int native_i915_device_numbers(void)
{
    static const struct {
        unsigned int major, minor;
        u32 internal, encoded;
    } goldens[] = {
        { 0, 0, 0x00000000U, 0x00000000U },
        { 0, 255, 0x000000ffU, 0x000000ffU },
        { 0, 256, 0x00000100U, 0x00100000U },
        { 255, 255, 0x0ff000ffU, 0x0000ffffU },
        { 256, 0, 0x10000000U, 0x00010000U },
        { 0xabc, 0x12345, 0xabc12345U, 0x123abc45U },
        { 0x123, 0xabcde, 0x123abcdeU, 0xabc123deU },
        { 0xfff, 0xfffff, 0xffffffffU, 0xffffffffU },
    };
    for (unsigned int i = 0; i < ARRAY_SIZE(goldens); i++) {
        dev_t device = MKDEV(goldens[i].major, goldens[i].minor);
        POLICY_EXPECT(device == goldens[i].internal);
        POLICY_EXPECT(MAJOR(device) == goldens[i].major && MINOR(device) == goldens[i].minor);
        POLICY_EXPECT(new_encode_dev(device) == goldens[i].encoded);
        POLICY_EXPECT(new_decode_dev(goldens[i].encoded) == goldens[i].internal);
        POLICY_EXPECT(huge_encode_dev(device) == (u64)goldens[i].encoded);
        POLICY_EXPECT(huge_decode_dev(goldens[i].encoded) == goldens[i].internal);
    }
    POLICY_EXPECT(old_valid_dev(MKDEV(255U, 255U)));
    POLICY_EXPECT(!old_valid_dev(MKDEV(256U, 0U)));
    POLICY_EXPECT(!old_valid_dev(MKDEV(0U, 256U)));
    POLICY_EXPECT(old_encode_dev(MKDEV(255U, 255U)) == 0xffffU);
    POLICY_EXPECT(old_decode_dev(0xffffU) == 0x0ff000ffU);
    POLICY_EXPECT(sysv_valid_dev(MKDEV(0xfffU, 0x3ffffU)));
    POLICY_EXPECT(!sysv_valid_dev(MKDEV(0U, 0x40000U)));
    POLICY_EXPECT(sysv_encode_dev(MKDEV(0xabcU, 0x12345U)) == 0x2af12345U);
    POLICY_EXPECT(sysv_major(0x2af12345U) == 0xabcU && sysv_minor(0x2af12345U) == 0x12345U);
    char text[32];
    POLICY_EXPECT(format_dev_t(text, MKDEV(0xabcU, 0x12345U)) == text);
    POLICY_EXPECT(!strcmp(text, "2748:74565"));
    POLICY_EXPECT(print_dev_t(text, MKDEV(0xabcU, 0x12345U)) == 11);
    POLICY_EXPECT(!strcmp(text, "2748:74565\n"));
    return 0;
}

int vinix_linuxkpi_i915_policy_native_selftest(void)
{
    u64 irq = vinix_linuxkpi_irq_flags();
    unsigned int depth = vinix_linuxkpi_preempt_count();
    POLICY_EXPECT(i915_fence_context_timeout(NULL, 0) == 0);
    POLICY_EXPECT(i915_fence_context_timeout(NULL, 1) == 10001);
    POLICY_EXPECT(i915_fence_context_timeout(NULL, 1ULL << 32) == 10001);
    POLICY_EXPECT(i915_fence_context_timeout(NULL, U64_MAX) == 10001);
    POLICY_EXPECT(i915_fence_timeout(NULL) == 10001);
    POLICY_EXPECT(!native_i915_device_numbers());
    POLICY_EXPECT(!native_i915_qp_tables());
    POLICY_EXPECT(vinix_linuxkpi_irq_flags() == irq && vinix_linuxkpi_preempt_count() == depth);
    return 0;
}
#undef POLICY_EXPECT
#endif
