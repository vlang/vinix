/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_STRING_TOKENS_TEST_H
#define VINIX_STRING_TOKENS_TEST_H
#include <linux/string.h>
#include <vinix/runtime.h>
#include <assert.h>
#include <sys/mman.h>
#include <unistd.h>

/* Volatile calls prevent compiler libc builtins from replacing the backend
 * under test with a folded result for these fixed input strings. */
static char *string_tokens_pbrk(const char *text, const char *set)
{
    char *(*volatile call)(const char *, const char *) = strpbrk;
    return call(text, set);
}
static char *string_tokens_chr(const char *text, int character)
{
    char *(*volatile call)(const char *, int) = strchr;
    return call(text, character);
}
static char *string_tokens_sep(char **cursor, const char *set)
{
    char *(*volatile call)(char **, const char *) = strsep;
    return call(cursor, set);
}
static char *string_tokens_skip(const char *text)
{
    char *(*volatile call)(const char *) = skip_spaces;
    return call(text);
}
static char *string_tokens_trim(char *text)
{
    char *(*volatile call)(char *) = strim;
    return call(text);
}

struct string_tokens_case {
    const char *text, *set, *mutated;
    size_t bytes, count;
    struct { size_t offset; ptrdiff_t next; const char *value; } tokens[5];
};
static void string_tokens_check_sequence(char *text, const struct string_tokens_case *test)
{
    char *cursor = text;
    for (size_t i = 0; i < test->count; i++) {
        char *token = string_tokens_sep(&cursor, test->set);
        assert(token == text + test->tokens[i].offset);
        assert(!strcmp(token, test->tokens[i].value));
        if (test->tokens[i].next < 0) assert(!cursor);
        else assert(cursor == text + test->tokens[i].next);
    }
    assert(!cursor && !string_tokens_sep(&cursor, test->set) && !cursor);
    assert(!memcmp(text, test->mutated, test->bytes));
}

struct string_tokens_mapping {
    unsigned char *mapping;
    char *text;
};
static struct string_tokens_mapping string_tokens_map(const char *source,
        size_t page_size, bool readonly, bool left_edge)
{
    unsigned char *mapping = mmap(NULL, 3 * page_size, PROT_NONE,
            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(mapping != MAP_FAILED);
    assert(!mprotect(mapping + page_size, page_size, PROT_READ | PROT_WRITE));
    memset(mapping + page_size, 0xa5, page_size);
    size_t bytes = strlen(source) + 1;
    assert(bytes < page_size);
    char *text = (char *)mapping + (left_edge ? page_size : 2 * page_size - bytes);
    memcpy(text, source, bytes);
    if (readonly) assert(!mprotect(mapping + page_size, page_size, PROT_READ));
    return (struct string_tokens_mapping){ .mapping = mapping, .text = text };
}

static void string_tokens_tests(void)
{
    static const struct { const char *text; int character; ptrdiff_t offset; } characters[] = {
        { "", 0, 0 }, { "", 'x', -1 }, { "abc", 'a', 0 },
        { "abc", 'b', 1 }, { "abca", 'a', 0 }, { "abc", 'c', 2 },
        { "abc", 0, 3 }, { "abc", 256, 3 }, { "abc", 'z', -1 },
        { "abc\0behind", 'h', -1 },
        { "\377:\200", 255, 0 }, { "\377:\200", -1, 0 },
        { "\377:\200", 511, 0 }, { "\377:\200", 128, 2 },
        { "\377:\200", 384, 2 }, { "\377:\200", 129, -1 },
    };
    static const struct { const char *text, *set; ptrdiff_t offset; } searches[] = {
        { "", "", -1 }, { "", "x", -1 }, { "abc", "", -1 },
        { "abc", "cba", 0 }, { "abc", "zcb", 1 }, { "abca", "a", 0 },
        { "abc", "c", 2 }, { "abc", "xyz", -1 },
        { "abc\0behind", "h", -1 }, { "aX", "\0X", -1 },
        { "a,b;c", ";,", 1 }, { "a,b;c", ";", 3 },
        { "\377:\200", "\200\377", 0 }, { "\377:\200", "\200", 2 },
        { "\377:\200", "\201", -1 },
    };
    static const struct string_tokens_case sequences[] = {
        { "", ",", "", 1, 1, { { 0, -1, "" } } },
        { "a", ",", "a", 2, 1, { { 0, -1, "a" } } },
        { "a,b", ",", "a\0b", 4, 2, { { 0, 2, "a" }, { 2, -1, "b" } } },
        { ",a", ",", "\0a", 3, 2, { { 0, 1, "" }, { 1, -1, "a" } } },
        { "a,", ",", "a\0", 3, 2, { { 0, 2, "a" }, { 2, -1, "" } } },
        { ",,", ",", "\0\0", 3, 3,
            { { 0, 1, "" }, { 1, 2, "" }, { 2, -1, "" } } },
        { "a,,b,", ",", "a\0\0b\0", 6, 4,
            { { 0, 2, "a" }, { 2, 3, "" }, { 3, 5, "b" }, { 5, -1, "" } } },
        { "a:b;c,", ",:;", "a\0b\0c\0", 7, 4,
            { { 0, 2, "a" }, { 2, 4, "b" }, { 4, 6, "c" }, { 6, -1, "" } } },
        { "xyz", "", "xyz", 4, 1, { { 0, -1, "xyz" } } },
        { ",", "", ",", 2, 1, { { 0, -1, "," } } },
        { "abcb", "bb", "a\0c\0", 5, 3,
            { { 0, 2, "a" }, { 2, 4, "c" }, { 4, -1, "" } } },
        { "ab", "ab", "\0\0", 3, 3,
            { { 0, 1, "" }, { 1, 2, "" }, { 2, -1, "" } } },
        { "\377,\200:", ",:", "\377\0\200\0", 5, 3,
            { { 0, 2, "\377" }, { 2, 4, "\200" }, { 4, -1, "" } } },
        { "abc\0hidden", ",", "abc\0hidden", 11, 1, { { 0, -1, "abc" } } },
        { "9a49,,!1234,", ",", "9a49\0\0!1234\0", 13, 4,
            { { 0, 5, "9a49" }, { 5, 6, "" }, { 6, 12, "!1234" }, { 12, -1, "" } } },
    };
    static const struct { const char *text; size_t offset; } spaces[] = {
        { "", 0 }, { "word", 0 }, { " word", 1 }, { "\t\n\v\f\r word", 6 },
        { " \t\r\n", 4 }, { "\240\tword", 2 }, { "\200 word", 0 },
        { "\205 word", 0 }, { "\377 word", 0 }, { " \0behind", 1 },
    };
    static const struct { const char *text, *mutated; size_t bytes, offset; } trims[] = {
        { "", "", 1, 0 }, { "abc", "abc", 4, 0 },
        { " abc", " abc", 5, 1 }, { "abc ", "abc\0", 5, 0 },
        { " \tabc \r\n", " \tabc\0\r\n", 9, 2 },
        { " \t\r\n", "\0\t\r\n", 5, 0 },
        { "\t\n\v\f\r ", "\0\n\v\f\r ", 7, 0 },
        { "a b", "a b", 4, 0 },
        { "\240abc\240 ", "\240abc\0 ", 7, 1 },
        { "\200abc\240", "\200abc\0", 6, 0 },
        { "\240\377\240", "\240\377\0", 4, 1 },
        { "\205 ", "\205\0", 3, 0 },
        { " \0behind ", "\0\0behind ", 10, 0 },
        { "x\0hidden\t", "x\0hidden\t", 10, 0 },
    };
    static const struct {
        const char *text, *set;
        ptrdiff_t match;
        size_t skip;
    } guarded[] = {
        { "", ",", -1, 0 }, { "\240\tabc,", ",;", 5, 2 },
        { "\377 \200", "\200\377", 0, 0 }, { " \t\r\n", "", -1, 4 },
    };
    long host_page_size = sysconf(_SC_PAGESIZE);
    assert(host_page_size > 0 && (size_t)host_page_size > 64);
    size_t page_size = (size_t)host_page_size;
    struct string_tokens_mapping readonly_text[sizeof(guarded) / sizeof(guarded[0])];
    struct string_tokens_mapping readonly_set[sizeof(guarded) / sizeof(guarded[0])];
    for (size_t i = 0; i < sizeof(guarded) / sizeof(guarded[0]); i++) {
        readonly_text[i] = string_tokens_map(guarded[i].text, page_size, true, false);
        readonly_set[i] = string_tokens_map(guarded[i].set, page_size, true, false);
    }
    struct string_tokens_mapping writable_tokens = string_tokens_map("a,,b,", page_size, false, false);
    struct string_tokens_mapping writable_trim = string_tokens_map(" \tword \240", page_size, false, false);
    struct string_tokens_mapping writable_empty = string_tokens_map("", page_size, false, false);
    struct string_tokens_mapping left_spaces = string_tokens_map(" \t\r\n", page_size, false, true);

    size_t pages = live_pages;
    unsigned int original_depth = vinix_linuxkpi_preempt_count();
    unsigned int original_cpu = current_cpu;
    u64 original_irq = vinix_linuxkpi_irq_flags();
    bool allocation_failure = fail_allocation;
    fail_allocation = true;
    u64 flags = vinix_linuxkpi_irq_save();
    vinix_linuxkpi_preempt_disable();
    vinix_linuxkpi_preempt_disable();
    unsigned int depth = vinix_linuxkpi_preempt_count();
    u64 irq = vinix_linuxkpi_irq_flags();

    for (size_t i = 0; i < sizeof(characters) / sizeof(characters[0]); i++) {
        char *match = string_tokens_chr(characters[i].text, characters[i].character);
        assert(match == (characters[i].offset < 0 ? NULL : characters[i].text + characters[i].offset));
    }
    for (size_t i = 0; i < sizeof(searches) / sizeof(searches[0]); i++) {
        char *match = string_tokens_pbrk(searches[i].text, searches[i].set);
        assert(match == (searches[i].offset < 0 ? NULL : searches[i].text + searches[i].offset));
    }
    for (size_t i = 0; i < sizeof(sequences) / sizeof(sequences[0]); i++) {
        struct { unsigned char before; char text[64]; unsigned char after; } input;
        memset(&input, 0xa5, sizeof(input));
        input.after = 0x5a;
        assert(sequences[i].bytes <= sizeof(input.text));
        memcpy(input.text, sequences[i].text, sequences[i].bytes);
        string_tokens_check_sequence(input.text, &sequences[i]);
        assert(input.before == 0xa5 && input.after == 0x5a);
        for (size_t byte = sequences[i].bytes; byte < sizeof(input.text); byte++)
            assert((unsigned char)input.text[byte] == 0xa5);
    }
    char *null_cursor = NULL;
    assert(!string_tokens_sep(&null_cursor, ",") && !null_cursor);
    for (size_t i = 0; i < sizeof(spaces) / sizeof(spaces[0]); i++)
        assert(string_tokens_skip(spaces[i].text) == spaces[i].text + spaces[i].offset);
    for (size_t i = 0; i < sizeof(trims) / sizeof(trims[0]); i++) {
        struct { unsigned char before; char text[64]; unsigned char after; } input;
        memset(&input, 0xa5, sizeof(input));
        input.after = 0x5a;
        assert(trims[i].bytes <= sizeof(input.text));
        memcpy(input.text, trims[i].text, trims[i].bytes);
        assert(string_tokens_trim(input.text) == input.text + trims[i].offset);
        assert(!memcmp(input.text, trims[i].mutated, trims[i].bytes));
        assert(input.before == 0xa5 && input.after == 0x5a);
        for (size_t byte = trims[i].bytes; byte < sizeof(input.text); byte++)
            assert((unsigned char)input.text[byte] == 0xa5);
    }
    /* Linux's immutable table classifies NBSP0xa0 as whitespace. These fixed
     * seven byte values are independent of libc locale and the runtime table. */
    for (unsigned int byte = 0; byte <= 255; byte++) {
        bool whitespace = byte == 9 || byte == 10 || byte == 11 || byte == 12 ||
                          byte == 13 || byte == 32 || byte == 160;
        char source[] = { (char)byte, 'x', 0 };
        assert(string_tokens_skip(source) == source + (whitespace ? 1 : 0));
        char single[] = { (char)byte, 0, 'z', 0 };
        assert(string_tokens_trim(single) == single);
        assert((unsigned char)single[0] == (whitespace ? 0 : byte));
        assert(!single[1] && single[2] == 'z' && !single[3]);
    }
    for (size_t i = 0; i < sizeof(guarded) / sizeof(guarded[0]); i++) {
        const char *text = readonly_text[i].text;
        assert(string_tokens_chr(text, 0) == text + strlen(text));
        assert(string_tokens_chr(text, 256) == text + strlen(text));
        assert(!string_tokens_chr(text, 'z'));
        char *match = string_tokens_pbrk(text, readonly_set[i].text);
        assert(match == (guarded[i].match < 0 ? NULL : text + guarded[i].match));
        assert(string_tokens_skip(text) == text + guarded[i].skip);
        assert(!memcmp(text, guarded[i].text, strlen(guarded[i].text) + 1));
        assert(!memcmp(readonly_set[i].text, guarded[i].set, strlen(guarded[i].set) + 1));
    }
    string_tokens_check_sequence(writable_tokens.text, &sequences[6]);
    assert((unsigned char)writable_tokens.text[-1] == 0xa5);
    assert(string_tokens_trim(writable_trim.text) == writable_trim.text + 2);
    assert(!memcmp(writable_trim.text, " \tword\0\240", 9));
    assert((unsigned char)writable_trim.text[-1] == 0xa5);
    assert(string_tokens_trim(writable_empty.text) == writable_empty.text);
    assert(string_tokens_skip(writable_empty.text) == writable_empty.text);
    char *empty_cursor = writable_empty.text;
    assert(string_tokens_sep(&empty_cursor, "") == writable_empty.text && !empty_cursor);
    assert((unsigned char)writable_empty.text[-1] == 0xa5);
    /* The leading guard catches an all-whitespace backward under-read. */
    assert(string_tokens_trim(left_spaces.text) == left_spaces.text);
    assert(!memcmp(left_spaces.text, "\0\t\r\n", 5));
    assert((unsigned char)left_spaces.text[5] == 0xa5);
    char alias[] = " \tvalue \n";
    assert(strstrip(alias) == alias + 2 && !strcmp(alias + 2, "value"));

    assert(live_pages == pages && vinix_linuxkpi_preempt_count() == depth &&
           vinix_linuxkpi_irq_flags() == irq && current_cpu == original_cpu);
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_preempt_enable_no_resched();
    vinix_linuxkpi_irq_restore(flags);
    fail_allocation = allocation_failure;
    assert(vinix_linuxkpi_preempt_count() == original_depth &&
           vinix_linuxkpi_irq_flags() == original_irq && live_pages == pages);
    for (size_t i = 0; i < sizeof(guarded) / sizeof(guarded[0]); i++) {
        assert(!munmap(readonly_text[i].mapping, 3 * page_size));
        assert(!munmap(readonly_set[i].mapping, 3 * page_size));
    }
    assert(!munmap(writable_tokens.mapping, 3 * page_size));
    assert(!munmap(writable_trim.mapping, 3 * page_size));
    assert(!munmap(writable_empty.mapping, 3 * page_size));
    assert(!munmap(left_spaces.mapping, 3 * page_size));
    const char *after = " after";
    assert(string_tokens_skip(after) == after + 1);
}
#endif
