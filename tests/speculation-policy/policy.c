/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "speculation.h"

static uint32_t max_leaf, max_subleaf, features, features2;
static uint32_t queries, reads, writes, last_msr;
static uint64_t caps, spec_ctrl, last_value;

void vinix_spec_test_cpuid(uint32_t leaf, uint32_t subleaf,
                           uint32_t *a, uint32_t *b, uint32_t *c, uint32_t *d)
{
    ++queries;
    *a = *b = *c = *d = 0;
    if (leaf == 0) {
        assert(queries == 1 && subleaf == 0);
        *a = max_leaf;
        return;
    }
    assert(leaf == 7 && max_leaf >= 7);
    if (subleaf == 0) {
        assert(queries == 2);
        *a = max_subleaf;
        *d = features;
        return;
    }
    /* Querying an unadvertised subleaf is an error, even if a test CPU
     * happens to return the BHI feature there. */
    assert(subleaf == 2 && max_subleaf >= 2 && queries == 3);
    *d = features2;
}

static uint64_t supported_ctrl(void)
{
    if (max_leaf < 7) return 0;
    return ((features & (UINT32_C(1) << 26)) ? 1 : 0)
         | ((features & (UINT32_C(1) << 27)) ? 2 : 0)
         | ((features & (UINT32_C(1) << 31)) ? 4 : 0)
         | ((max_subleaf >= 2 && (features2 & (UINT32_C(1) << 4)))
            ? UINT64_C(1) << 10 : 0);
}

uint64_t vinix_spec_test_rdmsr(uint32_t msr)
{
    ++reads;
    if (msr == 0x10a) {
        assert(max_leaf >= 7 && (features & (UINT32_C(1) << 29)));
        return caps;
    }
    assert(msr == 0x48 && supported_ctrl());
    return spec_ctrl;
}
void vinix_spec_test_wrmsr(uint32_t msr, uint64_t value)
{
    assert(msr == 0x48 || msr == 0x49);
    ++writes; last_msr = msr; last_value = value;
    if (msr == 0x49) {
        assert(max_leaf >= 7 && (features & (UINT32_C(1) << 26)));
        assert(value == 1);
    } else {
        uint64_t supported = supported_ctrl();
        assert(supported);
        /* Firmware bits may be preserved, but no unsupported bit may be
         * changed and no pre-existing protection may be cleared. */
        assert((value & ~supported) == (spec_ctrl & ~supported));
        assert((value & spec_ctrl) == spec_ctrl);
        spec_ctrl = value;
    }
}

static void check(unsigned bits, unsigned enhanced, unsigned bhi,
                  unsigned bhi_no, uint64_t firmware)
{
    /* Unrelated advertised features must never enable a SPEC_CTRL bit. */
    features = ((bits & 1) ? UINT32_C(1) << 26 : 0)
             | ((bits & 2) ? UINT32_C(1) << 27 : 0)
             | ((bits & 4) ? UINT32_C(1) << 29 : 0)
             | ((bits & 8) ? UINT32_C(1) << 31 : 0)
             | (UINT32_C(1) << 10);
    features2 = (bhi ? UINT32_C(1) << 4 : 0) | 7;
    caps = (enhanced ? 2 : 0) | (bhi_no ? UINT64_C(1) << 20 : 0);
    queries = reads = writes = 0;
    spec_ctrl = firmware;
    uint64_t selected = ((bits & 1) ? VINIX_SPEC_IBPB : 0)
                      | (((bits & 1) && (bits & 4) && enhanced) ? 1 : 0)
                      | ((bits & 2) ? 2 : 0) | ((bits & 8) ? 4 : 0)
                      | ((bhi && !((bits & 4) && bhi_no))
                         ? UINT64_C(1) << 10 : 0);
    assert(VINIX_SPEC_BHI_DIS_S == UINT64_C(1) << 10);
    assert(vinix_speculation_select(features, features2, caps) == selected);

    /* The initializer must discard feature data beyond CPUID maxima. */
    uint64_t expected = max_leaf >= 7 ? selected : 0;
    if (max_subleaf < 2) expected &= ~(UINT64_C(1) << 10);
    uint64_t policy = vinix_speculation_init(0);
    assert(policy == expected);
    assert(queries == 1 + (max_leaf >= 7) * (1 + (max_subleaf >= 2)));
    unsigned arch_reads = max_leaf >= 7 && (bits & 4);
    unsigned ctrl_reads = !!supported_ctrl();
    assert(reads == arch_reads + ctrl_reads);
    assert(writes == ctrl_reads);
    assert(spec_ctrl == (firmware | (expected & UINT64_C(0x407))));
    unsigned old_writes = writes;
    vinix_speculation_switch(policy);
    unsigned barrier = max_leaf >= 7 && (bits & 1);
    assert(writes == old_writes + barrier);
    if (barrier) assert(last_msr == 0x49 && last_value == 1);
}

int main(void)
{
    const uint32_t leaf_maxima[] = {0, 6, 7, UINT32_MAX};
    const uint32_t subleaf_maxima[] = {0, 1, 2, UINT32_MAX};
    /* Include a pre-enabled BHI_DIS_S and unrelated firmware controls. */
    const uint64_t firmware_values[] = {0, UINT64_C(0x100),
                                       UINT64_C(0x1000000000000407)};
    unsigned cases = 0;
    for (unsigned leaf = 0; leaf < 4; ++leaf)
        for (unsigned subleaf = 0; subleaf < 4; ++subleaf)
            for (unsigned bits = 0; bits < 16; ++bits)
                for (unsigned enhanced = 0; enhanced < 2; ++enhanced)
                    for (unsigned bhi = 0; bhi < 2; ++bhi)
                        for (unsigned bhi_no = 0; bhi_no < 2; ++bhi_no)
                            for (unsigned firmware = 0; firmware < 3; ++firmware) {
                                max_leaf = leaf_maxima[leaf];
                                max_subleaf = subleaf_maxima[subleaf];
                                check(bits, enhanced, bhi, bhi_no,
                                      firmware_values[firmware]);
                                ++cases;
                            }
    printf("SPECULATION POLICY PASS (%u cases)\n", cases);
    return 0;
}
