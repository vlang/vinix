/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "speculation.h"

static uint32_t features, reads, writes, last_msr;
static uint64_t caps, spec_ctrl, last_value;
uint32_t vinix_spec_test_leaf7(void) { return features; }
uint64_t vinix_spec_test_rdmsr(uint32_t msr)
{
    ++reads;
    if (msr == 0x10a) {
        assert(features & (UINT32_C(1) << 29));
        return caps;
    }
    assert(msr == 0x48);
    assert(features & ((UINT32_C(1) << 26) | (UINT32_C(1) << 27) | (UINT32_C(1) << 31)));
    return spec_ctrl;
}
void vinix_spec_test_wrmsr(uint32_t msr, uint64_t value)
{
    assert(msr == 0x48 || msr == 0x49);
    ++writes; last_msr = msr; last_value = value;
    if (msr == 0x49) { assert(features & (UINT32_C(1) << 26)); assert(value == 1); }
    else spec_ctrl = value;
}

int main(void)
{
    for (unsigned bits = 0; bits < 16; ++bits) {
        features = ((bits & 1) ? UINT32_C(1) << 26 : 0)
                 | ((bits & 2) ? UINT32_C(1) << 27 : 0)
                 | ((bits & 4) ? UINT32_C(1) << 29 : 0)
                 | ((bits & 8) ? UINT32_C(1) << 31 : 0);
        for (unsigned enhanced = 0; enhanced < 2; ++enhanced) {
            caps = enhanced ? 2 : 0;
            reads = writes = 0;
            /* Firmware controls are preserved even if not selected by us. */
            spec_ctrl = UINT64_C(0x100);
            uint64_t expected = ((bits & 1) ? VINIX_SPEC_IBPB : 0)
                              | (((bits & 1) && (bits & 4) && enhanced) ? 1 : 0)
                              | ((bits & 2) ? 2 : 0) | ((bits & 8) ? 4 : 0);
            assert(vinix_speculation_select(features, caps) == expected);
            uint64_t policy = vinix_speculation_init(0);
            assert(policy == expected);
            assert(reads == !!(bits & 4) + !!(bits & 11));
            assert(writes == !!(bits & 11));
            assert(spec_ctrl == (UINT64_C(0x100) | (expected & 7)));
            unsigned old_writes = writes;
            vinix_speculation_switch(policy);
            assert(writes == old_writes + !!(bits & 1));
            if (bits & 1) assert(last_msr == 0x49 && last_value == 1);
        }
    }
    puts("SPECULATION POLICY PASS");
}
