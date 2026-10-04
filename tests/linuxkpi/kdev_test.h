/* SPDX-License-Identifier: GPL-2.0-only */
/* Test the unchanged Linux kernel device-number helpers. Native device
 * registration and conversion to Vinix's u64 Stat fields are separate APIs. */
#include <linux/types.h>
#include <linux/kdev_t.h>
#include <linux/array_size.h>
#include <linux/string.h>
#include <vinix/format.h>
#include <assert.h>

_Static_assert(sizeof(__kernel_dev_t) == 4 && sizeof(dev_t) == 4,
               "Linux internal device numbers are 32 bits");
_Static_assert((dev_t)-1 > 0, "Linux internal device numbers are unsigned");
_Static_assert(MINORBITS == 20 && MINORMASK == 0xfffffU,
               "Linux internal device numbers have 20 minor bits");
#ifdef VINIX_LINUXKPI_HOST_TEST
/* host_types.h imports libc's distinct type before defining kernel dev_t. */
_Static_assert(!__builtin_types_compatible_p(dev_t, vinix_linuxkpi_host_dev_t),
               "the libc device type must remain distinct from kernel dev_t");
_Static_assert(sizeof(((struct stat *)0)->st_dev) == sizeof(vinix_linuxkpi_host_dev_t),
               "the host stat layout must keep libc's device width");
_Static_assert(__builtin_types_compatible_p(__typeof__(&mknod),
               int (*)(const char *, mode_t, vinix_linuxkpi_host_dev_t)),
               "the host mknod declaration must keep libc's device type");
#endif

static void kdev_tests(void)
{
    /* Public kernel and on-disk encodings are deliberately different once
     * either part extends beyond eight bits. These are fixed ABI goldens,
     * including actual character-device numbers and both upper boundaries. */
    static const struct {
        unsigned int major, minor;
        u32 kernel, encoded;
        bool old_valid, sysv_valid;
        const char *text;
    } vectors[] = {
        {0, 0, 0x00000000, 0x00000000, true, true, "0:0"},
        {0, 1, 0x00000001, 0x00000001, true, true, "0:1"},
        {1, 3, 0x00100003, 0x00000103, true, true, "1:3"},
        {4, 64, 0x00400040, 0x00000440, true, true, "4:64"},
        {226, 128, 0x0e200080, 0x0000e280, true, true, "226:128"},
        {255, 255, 0x0ff000ff, 0x0000ffff, true, true, "255:255"},
        {256, 0, 0x10000000, 0x00010000, false, true, "256:0"},
        {0, 256, 0x00000100, 0x00100000, false, true, "0:256"},
        {4095, 255, 0xfff000ff, 0x000fffff, false, true, "4095:255"},
        {0, 262143, 0x0003ffff, 0x3ff000ff, false, true, "0:262143"},
        {0, 262144, 0x00040000, 0x40000000, false, false, "0:262144"},
        {4095, 262143, 0xfff3ffff, 0x3fffffff, false, true, "4095:262143"},
        {0, 1048575, 0x000fffff, 0xfff000ff, false, false, "0:1048575"},
        {4095, 1048575, 0xffffffff, 0xffffffff, false, false, "4095:1048575"},
        {2748, 913153, 0xabcdef01, 0xdefabc01, false, false, "2748:913153"},
    };
    for (unsigned int i = 0; i < ARRAY_SIZE(vectors); i++) {
        dev_t device = MKDEV(vectors[i].major, vectors[i].minor);
        assert(device == vectors[i].kernel);
        assert(MAJOR(device) == vectors[i].major && MINOR(device) == vectors[i].minor);
        assert(old_valid_dev(device) == vectors[i].old_valid);
        assert(sysv_valid_dev(device) == vectors[i].sysv_valid);
        assert(new_encode_dev(device) == vectors[i].encoded);
        assert(new_decode_dev(vectors[i].encoded) == device);
        assert(huge_encode_dev(device) == vectors[i].encoded);
        assert(huge_decode_dev((u64)vectors[i].encoded) == device);
        /* This helper intentionally narrows to the low 32 bits. A native
         * userspace/device bridge must validate its u64 input separately. */
        assert(huge_decode_dev(0xa5a5a5a500000000ULL | vectors[i].encoded) == device);
        if (vectors[i].old_valid) {
            assert(old_encode_dev(device) == vectors[i].encoded);
            assert(old_decode_dev(old_encode_dev(device)) == device);
        }
        if (vectors[i].sysv_valid) {
            u32 encoded = sysv_encode_dev(device);
            assert(sysv_major(encoded) == vectors[i].major);
            assert(sysv_minor(encoded) == vectors[i].minor);
        }
        char text[24];
        assert(format_dev_t(text, device) == text);
        assert(!strcmp(text, vectors[i].text));
        size_t length = strlen(vectors[i].text);
        assert(print_dev_t(text, device) == (int)length + 1);
        assert(!memcmp(text, vectors[i].text, length));
        assert(text[length] == '\n' && !text[length + 1]);
    }

    /* Each internal bit has an independently specified on-disk position.
     * Round trips alone would miss matching mistakes in encode and decode. */
    static const unsigned char disk_bit[32] = {
        0, 1, 2, 3, 4, 5, 6, 7,
        20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
        8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    };
    for (unsigned int bit = 0; bit < ARRAY_SIZE(disk_bit); bit++) {
        dev_t device = 1U << bit;
        u32 encoded = 1U << disk_bit[bit];
        assert(new_encode_dev(device) == encoded && new_decode_dev(encoded) == device);
        assert(new_encode_dev(~device) == ~encoded && new_decode_dev(~encoded) == ~device);
    }

    /* Every legacy 8:8 disk identifier remains valid and agrees with the
     * low 16 bits of the modern disk layout, without truncating its parts. */
    for (unsigned int encoded = 0; encoded <= 0xffffU; encoded++) {
        dev_t device = old_decode_dev((u16)encoded);
        assert(old_valid_dev(device));
        assert(old_encode_dev(device) == encoded);
        assert(new_encode_dev(device) == encoded);
    }
    assert(sysv_encode_dev(MKDEV(1U, 3U)) == 0x00040003);
    assert(sysv_encode_dev(MKDEV(226U, 128U)) == 0x03880080);
    assert(sysv_encode_dev(MKDEV(4095U, 262143U)) == 0x3fffffff);
    assert(sysv_major(0xffffffffU) == 16383 && sysv_minor(0xffffffffU) == 262143);

    unsigned int major = 7, minor = 9;
    dev_t device = MKDEV(major++, minor++);
    assert(major == 8 && minor == 10 && device == 0x00700009);
    assert(MAJOR(device++) == 7 && device == 0x0070000a);
    assert(MINOR(device++) == 10 && device == 0x0070000b);
    assert(new_encode_dev(device++) == 0x0000070b && device == 0x0070000c);
}
