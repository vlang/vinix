/* Independent callers for console policy, chunk boundaries and native va_list. */
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

int fixture_printf(const char *, ...);
int fixture_panic(char *, ...);
int fixture_kprintf(const char *, ...);
int fixture_benchmark(const char *, ...);
int fixture_fprintf(void *, const char *, ...);

static unsigned char serial[4096], terminal[4096];
static size_t serial_len, terminal_len, chunks, largest;
static unsigned acquired, released;
void fixture_serial(unsigned char byte, int panic) {
    (void)panic;
    assert(serial_len < sizeof(serial));
    serial[serial_len++] = byte;
}
void fixture_terminal(char *text, uint64_t length) {
    assert(length <= sizeof(terminal) - terminal_len);
    memcpy(terminal + terminal_len, text, length);
    terminal_len += length;
}
void fixture_kwrite(char *text, uint64_t length) {
    assert(length > 0 && length <= 256);
    chunks++;
    if (length > largest) largest = length;
    fixture_terminal(text, length);
}
void fixture_acquire(void) { acquired++; }
void fixture_release(void) { released++; }
static void reset(void) {
    serial_len = terminal_len = chunks = largest = 0;
    acquired = released = 0;
}
int main(void) {
    char data[1026];
    memset(data, 'x', sizeof(data));
    data[sizeof(data) - 1] = 0;
    for (int n = 0; n <= 1025; n++) {
        reset();
        assert(fixture_kprintf("%.*s", n, data) == n);
        assert(terminal_len == (size_t)n && !serial_len);
        assert(!memcmp(terminal, data, n));
        assert(chunks == ((size_t)n + 255) / 256);
        assert(largest == (n > 256 ? 256 : (size_t)n));
        assert(!acquired && !released);
    }
    reset();
    assert(fixture_kprintf("[%llu,%lld,%llx,%c]", (unsigned long long)UINT64_MAX,
                           (long long)INT64_MIN, (unsigned long long)UINT64_C(0xfeed), 0) == 50);
    static char expected[] = "[18446744073709551615,-9223372036854775808,feed,\0]";
    assert(terminal_len == sizeof(expected) - 1);
    assert(!memcmp(terminal, expected, sizeof(expected) - 1));
    reset();
    int ordinary = fixture_printf("%s:%u", "serial", 17U);
#ifdef PROD
    assert(ordinary == 0 && !serial_len && !acquired && !released);
#else
    assert(ordinary == 9 && serial_len == 9 && acquired == 1 && released == 1);
    assert(!memcmp(serial, "serial:17", 9));
#endif
    assert(!terminal_len);
    reset();
    assert(fixture_panic("%s:%u", "panic", 23U) == 8);
    assert(serial_len == 8 && terminal_len == 8);
    assert(!memcmp(serial, "panic:23", 8) && !memcmp(serial, terminal, 8));
    assert(!acquired && !released);
    reset();
    assert(fixture_benchmark("%s:%u", "benchmark", 31U) == 12);
    assert(serial_len == 12 && !terminal_len && !acquired && !released);
    assert(!memcmp(serial, "benchmark:31", 12));
    reset();
    assert(fixture_fprintf(NULL, "%s!\n", "assert") == 0);
    assert(serial_len == 8 && terminal_len == 8);
    assert(!memcmp(serial, "assert!\n", 8) && !memcmp(serial, terminal, 8));
    reset();
    assert(fixture_fprintf(NULL, "%.*s!", 3, "assert") == 0);
    assert(serial_len == 4 && !memcmp(serial, "ass!", 4));
    assert(!memcmp(serial, terminal, 4));
    reset();
    assert(fixture_fprintf(NULL, "%.*s!", -1, "unused") == 0);
    assert(serial_len == 1 && serial[0] == '!');
    reset();
    assert(fixture_fprintf(NULL, "literal") == 0);
    assert(serial_len == 7 && !memcmp(serial, "literal", 7));
    return 0;
}
