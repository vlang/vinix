/* SPDX-License-Identifier: ISC */
#if defined(__APPLE__)
#define ABI_SYMBOL(name) _##name
#else
#define ABI_SYMBOL(name) name
#endif
.text
.globl ABI_SYMBOL(test_open)
ABI_SYMBOL(test_open):
#if defined(__aarch64__) || defined(__arm64__)
    b ABI_SYMBOL(wifi_ctl_open_entry)
#elif defined(__x86_64__)
    jmp ABI_SYMBOL(wifi_ctl_open_entry)
#else
#error unsupported native variadic ABI
#endif
.globl ABI_SYMBOL(test_ioctl)
ABI_SYMBOL(test_ioctl):
#if defined(__aarch64__) || defined(__arm64__)
#if defined(__APPLE__)
    ldr x2, [sp]
#endif
    b ABI_SYMBOL(wifi_ctl_ioctl_entry)
#elif defined(__x86_64__)
    jmp ABI_SYMBOL(wifi_ctl_ioctl_entry)
#endif
#if !defined(__APPLE__)
.section .note.GNU-stack,"",@progbits
#endif
