/* SPDX-License-Identifier: GPL-2.0-only */
/* Exercise the linked, unchanged Linux 6.6.157 DSC QP lookup functions. */
#include <display/intel_qp_tables.h>
#include <drm/display/drm_dsc.h>
#include <linux/build_bug.h>
#include <linux/array_size.h>
#include <assert.h>

_Static_assert(DSC_NUM_BUF_RANGES == 15, "Pinned DSC tables contain 15 ranges");

static void qp_table_tests(void)
{
    size_t pages = live_pages;
    u64 irq = vinix_linuxkpi_irq_flags();
    unsigned int depth = vinix_linuxkpi_preempt_count();
    /* Fixed values include each family, both index boundaries, independent
     * interior rows, and the 420 column mapping. No expected value is
     * calculated by invoking another copy of the lookup implementation. */
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
        assert(intel_lookup_range_min_qp(goldens[i].bpc, goldens[i].row,
                    goldens[i].column, goldens[i].is_420) == goldens[i].minimum);
        assert(intel_lookup_range_max_qp(goldens[i].bpc, goldens[i].row,
                    goldens[i].column, goldens[i].is_420) == goldens[i].maximum);
    }
    static const struct { int bpc, columns; bool is_420; } families[] = {
        { 8, 37, false }, { 10, 49, false }, { 12, 61, false },
        { 8, 17, true }, { 10, 23, true }, { 12, 29, true },
    };
    /* Both helpers directly index their private tables; invalid bpc/row/
     * column probes would test misuse, rather than a supported interface. */
    for (unsigned int i = 0; i < ARRAY_SIZE(families); i++)
        for (int row = 0; row < DSC_NUM_BUF_RANGES; row++)
            for (int column = 0; column < families[i].columns; column++) {
                u8 minimum = intel_lookup_range_min_qp(families[i].bpc, row,
                        column, families[i].is_420);
                u8 maximum = intel_lookup_range_max_qp(families[i].bpc, row,
                        column, families[i].is_420);
                assert(minimum <= maximum && maximum <= 23);
            }
    /* Verify the production integer-bpp index formulas at both ends.
     * 420 PPS bpp is doubled, so its caller subtracts 8 without a factor. */
    for (int bpc = 8; bpc <= 12; bpc += 2) {
        int last_444_column = 2 * (3 * bpc - 6);
        int last_420_column = 3 * bpc - 8;
        assert(intel_lookup_range_min_qp(bpc, 14, 2 * (6 - 6), false) == bpc * 2 - 2);
        assert(intel_lookup_range_max_qp(bpc, 14, last_444_column, false) == 4);
        assert(intel_lookup_range_min_qp(bpc, 14, 8 - 8, true) == bpc * 2 - 3);
        assert(intel_lookup_range_max_qp(bpc, 14, last_420_column, true) == (bpc == 8 ? 4 : 5));
    }
    assert(live_pages == pages && vinix_linuxkpi_irq_flags() == irq &&
           vinix_linuxkpi_preempt_count() == depth);
}
