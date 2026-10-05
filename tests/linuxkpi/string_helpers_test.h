/* SPDX-License-Identifier: GPL-2.0-only */
/* Fixed caller-facing vectors for the pinned Linux string helper contracts. */
#ifndef VINIX_STRING_HELPERS_TEST_H
#define VINIX_STRING_HELPERS_TEST_H
#include <linux/string.h>
#include <linux/build_bug.h>
#include <linux/errno.h>
#include <vinix/runtime.h>
#include <assert.h>
#include <sys/mman.h>
#include <unistd.h>

static void string_helpers_tests(void)
{
    static const struct { const char *a, *b; bool equal; } pairs[] = {
        { "", "", true }, { "", "\n", true }, { "\n", "", true },
        { "\n", "\n", true }, { "a", "a\n", true }, { "a\n", "a", true },
        { "a\n", "a\n", true }, { "a\nb", "a\nb", true },
        { "a\nb", "a", false }, { "a", "\n", false },
        { "a\n\n", "a\n", true }, { "a\n\n", "a", false },
        { "a\n\n", "a\n\n", true },
        { "abc", "ab", false }, { " abc", "abc", false },
        { "\200", "\200\n", true }, { "A", "a", false },
    };
    static const char * const sources[] = {
        "none", "auto", "pipe", "plane", "pipe", NULL, "behind",
    };
    static const struct {
        size_t count;
        const char *query;
        int exact, sysfs;
    } matches[] = {
        { 0, "none", -EINVAL, -EINVAL }, { 1, "none", 0, 0 },
        { 1, "auto", -EINVAL, -EINVAL }, { 2, "auto", 1, 1 },
        { 4, "pipe", 2, 2 }, { 7, "pipe", 2, 2 },
        { 7, "pipe\n", -EINVAL, 2 }, { 7, "Pipe", -EINVAL, -EINVAL },
        { 7, "behind", -EINVAL, -EINVAL },
        { (size_t)-1, "behind", -EINVAL, -EINVAL },
        { (size_t)-1, "plane", 3, 3 }, { 7, "", -EINVAL, -EINVAL },
    };
    static const char * const newline_entries[] = { "a\n", "a", "", NULL };

    /* Guard both the sentinel array and a borrowed string. Stopping at NULL
     * or NUL must not inspect the inaccessible following page, even for -1. */
    long page_size = sysconf(_SC_PAGESIZE);
    assert(page_size > 0 && (size_t)page_size >= 3 * sizeof(char *));
    size_t mapping_size = (size_t)page_size * 3;
    unsigned char *string_mapping = mmap(NULL, mapping_size, PROT_NONE,
            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    unsigned char *array_mapping = mmap(NULL, mapping_size, PROT_NONE,
            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(string_mapping != MAP_FAILED && array_mapping != MAP_FAILED);
    assert(!mprotect(string_mapping + page_size, (size_t)page_size,
                PROT_READ | PROT_WRITE));
    assert(!mprotect(array_mapping + page_size, (size_t)page_size,
                PROT_READ | PROT_WRITE));
    char *borrowed = (char *)string_mapping + 2 * page_size - 3;
    memcpy(borrowed, "a\n", 3);
    const char **guarded_array = (const char **)(array_mapping +
            2 * page_size - 3 * sizeof(char *));
    guarded_array[0] = borrowed;
    guarded_array[1] = "auto";
    guarded_array[2] = NULL;
    assert(!mprotect(array_mapping + page_size, (size_t)page_size, PROT_READ));

    size_t pages = live_pages;
    unsigned int original_depth = vinix_linuxkpi_preempt_count();
    u64 original_irq = vinix_linuxkpi_irq_flags();
    bool allocation_failure = fail_allocation;
    fail_allocation = true;
    u64 flags = vinix_linuxkpi_irq_save();
    vinix_linuxkpi_preempt_disable();
    vinix_linuxkpi_preempt_disable();
    unsigned int depth = vinix_linuxkpi_preempt_count();
    u64 irq = vinix_linuxkpi_irq_flags();
    for (size_t i = 0; i < sizeof(pairs) / sizeof(pairs[0]); i++)
        assert(sysfs_streq(pairs[i].a, pairs[i].b) == pairs[i].equal);
    for (size_t i = 0; i < sizeof(matches) / sizeof(matches[0]); i++) {
        assert(match_string(sources, matches[i].count, matches[i].query) == matches[i].exact);
        assert(__sysfs_match_string(sources, matches[i].count, matches[i].query) == matches[i].sysfs);
    }
    assert(match_string(newline_entries, 4, "a") == 1);
    assert(__sysfs_match_string(newline_entries, 4, "a") == 0);
    assert(sysfs_match_string(newline_entries, "\n") == 2);
    assert(match_string(newline_entries, 4, "\n") == -EINVAL);
    assert(match_string(NULL, 0, NULL) == -EINVAL);
    assert(__sysfs_match_string(NULL, 0, NULL) == -EINVAL);
    assert(sysfs_streq(borrowed, "a") && sysfs_streq("a", borrowed));
    assert(sysfs_streq(borrowed + 2, "\n"));
    assert(match_string(guarded_array, (size_t)-1, "a\n") == 0);
    assert(__sysfs_match_string(guarded_array, (size_t)-1, "a") == 0);
    assert(match_string(guarded_array, (size_t)-1, "auto") == 1);
    assert(match_string(guarded_array, (size_t)-1, "missing") == -EINVAL);
    assert(__sysfs_match_string(guarded_array, (size_t)-1, "missing") == -EINVAL);
    /* The synchronous call retains neither the borrowed array nor bytes. */
    borrowed[0] = 'b';
    assert(__sysfs_match_string(guarded_array, (size_t)-1, "a") == -EINVAL);
    assert(__sysfs_match_string(guarded_array, (size_t)-1, "b") == 0);

    struct { unsigned char before; char text[32]; unsigned char after; } name = {
        .before = 0xa5, .text = "i915_0000:03:00.0", .after = 0x5a,
    };
    assert(strreplace(name.text, ':', '_') == name.text);
    assert(!strcmp(name.text, "i915_0000_03_00.0"));
    assert(strreplace(name.text, 'x', 'y') == name.text);
    assert(strreplace(name.text, '_', '_') == name.text);
    assert(strreplace(name.text, '\0', 'x') == name.text);
    assert(!strcmp(name.text, "i915_0000_03_00.0"));
    assert(name.before == 0xa5 && name.after == 0x5a);
    char empty[] = "";
    assert(strreplace(empty, 'a', 'b') == empty && !empty[0]);
    char nul_replacement[] = { 'x', 'x', ':', 'x', 0 };
    const char nul_expected[] = { 0, 0, ':', 0, 0 };
    assert(strreplace(nul_replacement, 'x', 0) == nul_replacement);
    assert(!memcmp(nul_replacement, nul_expected, sizeof(nul_expected)));
    char existing_nul[] = { 'a', 0, 'a', 0 };
    const char existing_expected[] = { 'b', 0, 'a', 0 };
    assert(strreplace(existing_nul, 'a', 'b') == existing_nul);
    assert(!memcmp(existing_nul, existing_expected, sizeof(existing_expected)));
    char high_byte[] = { (char)0xff, ':', (char)0xff, 0 };
    assert(strreplace(high_byte, (char)0xff, '_') == high_byte);
    assert(!strcmp(high_byte, "_:_"));

    assert(live_pages == pages && vinix_linuxkpi_preempt_count() == depth &&
           vinix_linuxkpi_irq_flags() == irq);
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_irq_restore(flags);
    fail_allocation = allocation_failure;
    assert(vinix_linuxkpi_preempt_count() == original_depth &&
           vinix_linuxkpi_irq_flags() == original_irq && live_pages == pages);
    assert(!munmap(string_mapping, mapping_size));
    assert(!munmap(array_mapping, mapping_size));
    assert(sysfs_streq("after", "after\n"));
    assert(match_string(sources, 7, "auto") == 1);
}
#endif
