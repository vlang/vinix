/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

void vinix_stack_guard_message(const char *message);
void vinix_stack_guard_diagnostic(uint64_t sp, uint64_t pc, uint64_t address);

static char captured[1024];
static size_t length;

#ifdef VINIX_STACK_ARM
void aarch64__uart__putc(uint8_t value)
#else
void serial__panic_out(uint8_t value)
#endif
{
    assert(length < sizeof(captured));
    captured[length++] = (char)value;
}

static void diagnostic(uint64_t sp, uint64_t pc, uint64_t address)
{
    char expected[128];
    int count = snprintf(expected, sizeof(expected),
        "STACK-GUARD state sp=0x%016llx pc=0x%016llx address=0x%016llx\n",
        (unsigned long long)sp, (unsigned long long)pc, (unsigned long long)address);
    assert(count > 0 && (size_t)count < sizeof(expected));
    length = 0;
    vinix_stack_guard_diagnostic(sp, pc, address);
    assert(length == (size_t)count && !memcmp(captured, expected, length));
}

int main(void)
{
    const char bytes[] = { 'a', (char)0x80, (char)0xff, '\n', 0, 'x', 0 };
    length = 0;
    vinix_stack_guard_message("");
    assert(!length);
    vinix_stack_guard_message(bytes);
    assert(length == 4 && !memcmp(captured, bytes, 4));
    diagnostic(0, 0, 0);
    diagnostic(UINT64_MAX, UINT64_MAX, UINT64_MAX);
    diagnostic(UINT64_C(0x0123456789abcdef), UINT64_C(0xfedcba9876543210), UINT64_C(0x8000000000000000));
    uint64_t random = UINT64_C(0x64a30fb4c16ace80);
    for (unsigned i = 0; i < 2000; i++) {
        random ^= random << 13;
        random ^= random >> 7;
        random ^= random << 17;
        diagnostic(random, random ^ UINT64_MAX, random >> (i % 64));
    }
    puts("STACK DIAGNOSTICS PASS: C ABI, exact serial bytes, 2003 hex fault records");
    return 0;
}
