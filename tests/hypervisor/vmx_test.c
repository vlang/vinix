/* SPDX-License-Identifier: GPL-2.0-only */
/* Independent C caller for the production V VMX control and unsupported ABI. */
#include "vmx.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

_Static_assert(sizeof(struct vinix_vmx_descriptor) == 10, "descriptor ABI");
_Static_assert(offsetof(struct vinix_vmx_descriptor, base) == 2, "packed base");
_Static_assert(sizeof(struct vinix_vmx_registers) == 120, "guest register ABI");
_Static_assert(offsetof(struct vinix_vmx_registers, r15) == 112, "last guest register");

#ifdef VMX_TEST_PORTS
static unsigned expected_operation, calls;
static uint64_t expected_operand, expected_value, read_result;
static unsigned char status;

unsigned char vinix_vmx_test_instruction(unsigned operation, uint64_t operand,
                                        uint64_t value, uint64_t *result)
{
    assert(operation == expected_operation);
    assert(operand == expected_operand && value == expected_value);
    assert(++calls == 1);
    if (operation == 5) {
        assert(result);
        /* Even an adapter that writes on failure cannot corrupt the caller. */
        *result = read_result;
    } else {
        assert(!result);
    }
    return status;
}

static void control_tests(void)
{
    unsigned cases = 0;
    const uint64_t operands[] = {0, 1, UINT64_C(0x6c14), UINT64_MAX,
                                UINT64_C(0x8000000012345000)};
    for (unsigned failure = 0; failure < 256; failure++) {
        status = failure;
        for (unsigned i = 0; i < sizeof(operands) / sizeof(operands[0]); i++) {
            for (unsigned op = 0; op < 6; op++) {
                expected_operation = op;
                expected_operand = op == 1 ? 0 : operands[i];
                expected_value = op == 4 ? ~operands[i] : 0;
                read_result = ~operands[i];
                calls = 0;
                int result = 1;
                struct { uint64_t before, value, after; } output = {17, 23, 29};
                switch (op) {
                case 0: result = vinix_vmx_on(operands[i]); break;
                case 1: result = vinix_vmx_off(); break;
                case 2: result = vinix_vmx_clear(operands[i]); break;
                case 3: result = vinix_vmx_load(operands[i]); break;
                case 4: result = vinix_vmx_write(operands[i], expected_value); break;
                case 5: result = vinix_vmx_read(operands[i], &output.value); break;
                }
                assert(result == (status ? -1 : 0) && calls == 1);
                assert(output.before == 17 && output.after == 29);
                assert(output.value == (op == 5 && !status ? read_result : 23));
                cases++;
            }
        }
    }
    printf("VMX CONTROL PASS: %u C ABI cases, failure status and guarded VMREAD\n", cases);
}
#else
static void unsupported_tests(void)
{
    unsigned char buffer[512], original[512];
    memset(buffer, 0xa5, sizeof(buffer));
    memcpy(original, buffer, sizeof(buffer));
    struct vinix_vmx_descriptor descriptor = {0x1234, UINT64_MAX};
    struct vinix_vmx_registers registers;
    memset(&registers, 0x5a, sizeof(registers));
    struct vinix_vmx_registers saved = registers;
    uint64_t value = UINT64_MAX;
    assert(vinix_vmx_on(0) == -1 && vinix_vmx_off() == -1);
    assert(vinix_vmx_clear(UINT64_MAX) == -1 && vinix_vmx_load(0) == -1);
    assert(vinix_vmx_write(UINT64_MAX, 0) == -1);
    assert(vinix_vmx_read(0, &value) == -1 && value == UINT64_MAX);
    assert(vinix_vmx_read(0, NULL) == -1);
    assert(vinix_vmx_enter(&registers) == -1 && !memcmp(&registers, &saved, sizeof(saved)));
    assert(vinix_vmx_enter(NULL) == -1);
    vinix_vmx_fxsave(buffer);
    vinix_vmx_fxrstor(buffer);
    vinix_vmx_fxsave(NULL);
    vinix_vmx_fxrstor(NULL);
    assert(!memcmp(buffer, original, sizeof(buffer)));
    vinix_vmx_sgdt(&descriptor);
    vinix_vmx_sidt(&descriptor);
    vinix_vmx_sgdt(NULL);
    vinix_vmx_sidt(NULL);
    assert(descriptor.limit == 0x1234 && descriptor.base == UINT64_MAX);
    assert(!vinix_vmx_read_cs() && !vinix_vmx_read_ss() && !vinix_vmx_read_ds());
    assert(!vinix_vmx_read_es() && !vinix_vmx_read_fs() && !vinix_vmx_read_gs());
    assert(!vinix_vmx_read_tr());
    puts("VMX UNSUPPORTED PASS: C ABI, no output mutation, null no-ops");
}
#endif

int main(void)
{
#ifdef VMX_TEST_PORTS
    control_tests();
#else
    unsupported_tests();
#endif
    return 0;
}
