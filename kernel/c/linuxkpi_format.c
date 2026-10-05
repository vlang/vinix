/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Native Linux 6.6.157 formatting subset. Number, string and pointer rules
 * derive from Linux lib/vsprintf.c, Copyright (C) 1991, 1992 Linus Torvalds;
 * Lars Wirzenius and Linus Torvalds. The imported upstream source is unchanged.
 *
 * This supplies the actual i915 conversions without pretending to implement
 * network, dentry/RCU, credentials, symbols, clocks, firmware or trace tables.
 * KALLSYMS and SYMBOLIC_ERRNAME are disabled; kptr_restrict policy is zero.
 */
#ifdef VINIX_LINUXKPI
#include <vinix/format.h>
#include <vinix/runtime.h>
#include <linux/err.h>
#include <linux/errno.h>
#include <linux/ioport.h>
#include <linux/limits.h>
#include <linux/printk.h>
#include <linux/siphash.h>
#include <linux/string.h>

#if defined(CONFIG_KALLSYMS) || defined(CONFIG_SYMBOLIC_ERRNAME)
#error "Native formatter requires the real symbol/errno services before enabling their configuration"
#endif

#define F_SIGN 1U
#define F_LEFT 2U
#define F_PLUS 4U
#define F_SPACE 8U
#define F_ZERO 16U
#define F_SMALL 32U
#define F_SPECIAL 64U
#define FIELD_MAX ((1 << 23) - 1)
#define PRECISION_MAX ((1 << 15) - 1)

struct format_spec { int width, precision; unsigned int flags, base; };
struct format_output {
    char *buf;
    size_t size, position;
    unsigned int status;
    bool stop;
};
static siphash_key_t pointer_key;
/* 0 = unpublished, 1 = setter owns initialization, 2 = immutable ready. */
static unsigned int pointer_key_state;

int vinix_linuxkpi_format_set_key(const u64 key[2])
{
    if (!key) return -EINVAL;
    if (!vinix_linuxkpi_may_sleep()) return -EWOULDBLOCK;
    unsigned int expected = 0;
    if (!__atomic_compare_exchange_n(&pointer_key_state, &expected, 1, false,
        __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
        return expected == 2 ? -EALREADY : -EWOULDBLOCK;
    pointer_key.key[0] = key[0];
    pointer_key.key[1] = key[1];
    __atomic_store_n(&pointer_key_state, 2, __ATOMIC_RELEASE);
    return 0;
}

static bool format_alnum(unsigned char c)
{
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z');
}

/* Count beyond the end without forming pointers outside the caller's object.
 * Padding cost is proportional to the retained bytes, even for wide fields. */
static void format_bytes(struct format_output *out, const char *data, size_t len)
{
    if (out->position < out->size) {
        size_t available = out->size - out->position;
        size_t copy = len < available ? len : available;
        if (copy) memcpy(out->buf + out->position, data, copy);
    }
    out->position += len;
}

static void format_pad(struct format_output *out, char c, size_t len)
{
    if (out->position < out->size) {
        size_t available = out->size - out->position;
        size_t copy = len < available ? len : available;
        if (copy) memset(out->buf + out->position, c, copy);
    }
    out->position += len;
}

static void format_char(struct format_output *out, char c)
{
    format_bytes(out, &c, 1);
}

static void format_number(struct format_output *out, u64 value, struct format_spec spec)
{
    static const char digits[] = "0123456789ABCDEF";
    char reversed[24], sign = 0;
    unsigned int count = 0;
    int width = spec.width, precision = spec.precision;
    bool zero = value == 0;
    bool prefix = (spec.flags & F_SPECIAL) && spec.base != 10;
    if (spec.flags & F_LEFT) spec.flags &= ~F_ZERO;
    if (spec.flags & F_SIGN) {
        if ((s64)value < 0) { sign = '-'; value = 0ULL - value; }
        else if (spec.flags & F_PLUS) sign = '+';
        else if (spec.flags & F_SPACE) sign = ' ';
        if (sign) width--;
    }
    if (prefix) {
        if (spec.base == 16) width -= 2;
        else if (!zero) width--;
    }
    do {
        reversed[count++] = digits[value % spec.base] | (spec.flags & F_SMALL);
        value /= spec.base;
    } while (value);
    if ((int)count > precision) precision = count;
    width -= precision;
    if (width > 0 && !(spec.flags & (F_ZERO | F_LEFT))) {
        format_pad(out, ' ', width); width = 0;
    }
    if (sign) format_char(out, sign);
    if (prefix) {
        if (spec.base == 16 || !zero) format_char(out, '0');
        if (spec.base == 16) format_char(out, 'X' | (spec.flags & F_SMALL));
    }
    if (width > 0 && !(spec.flags & F_LEFT)) {
        format_pad(out, spec.flags & F_ZERO ? '0' : ' ', width); width = 0;
    }
    if (precision > (int)count) format_pad(out, '0', precision - count);
    while (count) format_char(out, reversed[--count]);
    if (width > 0) format_pad(out, ' ', width);
}

static void format_string(struct format_output *out, const char *str, struct format_spec spec)
{
    size_t len = 0;
    while ((spec.precision < 0 || len < (unsigned int)spec.precision) && str[len]) len++;
    size_t spaces = spec.width > 0 && (size_t)spec.width > len ? spec.width - len : 0;
    if (!(spec.flags & F_LEFT)) format_pad(out, ' ', spaces);
    format_bytes(out, str, len);
    if (spec.flags & F_LEFT) format_pad(out, ' ', spaces);
}

static void format_error(struct format_output *out, const char *str, struct format_spec spec)
{
    if (spec.precision == -1) spec.precision = 2 * sizeof(void *);
    format_string(out, str, spec);
}

static bool format_bad_pointer(struct format_output *out, const void *ptr, struct format_spec spec)
{
    if (!ptr) { format_error(out, "(null)", spec); return true; }
    if ((unsigned long)ptr < 4096 || IS_ERR(ptr)) {
        format_error(out, "(efault)", spec); return true;
    }
    return false;
}

static void format_hex_address(struct format_output *out, u64 value, unsigned int size)
{
    struct format_spec spec = { .base = 16, .width = 2 + 2 * size,
        .precision = -1, .flags = F_SPECIAL | F_SMALL | F_ZERO };
    format_number(out, value, spec);
}

static void format_pointer_number(struct format_output *out, unsigned long value, struct format_spec spec)
{
    spec.base = 16; spec.flags |= F_SMALL;
    if (spec.width == -1) { spec.width = 2 * sizeof(void *); spec.flags |= F_ZERO; }
    format_number(out, value, spec);
}

static void format_pointer_id(struct format_output *out, const void *ptr, struct format_spec spec)
{
    if (IS_ERR_OR_NULL(ptr)) { format_pointer_number(out, (unsigned long)ptr, spec); return; }
    if (__atomic_load_n(&pointer_key_state, __ATOMIC_ACQUIRE) != 2) {
        spec.width = 2 * sizeof(void *);
        format_error(out, sizeof(void *) == 8 ? "(____ptrval____)" : "(ptrval)", spec);
        return;
    }
    u64 hash = siphash_1u64((unsigned long)ptr, &pointer_key);
    format_pointer_number(out, (unsigned long)(hash & 0xffffffffULL), spec);
}

static const struct format_spec decimal_spec = { .base = 10, .width = 0, .precision = -1 };

static void format_resource(struct format_output *out, const struct resource *res,
    struct format_spec outer, bool decode)
{
    if (format_bad_pointer(out, res, outer)) return;
    char buf[128];
    struct format_output local = { .buf = buf, .size = sizeof(buf) };
    struct format_spec spec = { .base = 16, .width = 10, .precision = -1,
        .flags = F_SPECIAL | F_SMALL | F_ZERO };
    const char *kind;
    if (res->flags & IORESOURCE_IO) { kind = "io  "; spec.width = 6; }
    else if (res->flags & IORESOURCE_MEM) kind = "mem ";
    else if (res->flags & IORESOURCE_IRQ) { kind = "irq "; spec = decimal_spec; }
    else if (res->flags & IORESOURCE_DMA) { kind = "dma "; spec = decimal_spec; }
    else if (res->flags & IORESOURCE_BUS) { kind = "bus "; spec.width = 2; spec.flags &= ~F_SPECIAL; }
    else { kind = "??? "; decode = false; }
    format_char(&local, '['); format_bytes(&local, kind, 4);
    if (decode && (res->flags & IORESOURCE_UNSET)) {
        format_bytes(&local, "size ", 5);
        format_number(&local, res->end - res->start + 1, spec);
    } else {
        format_number(&local, res->start, spec);
        if (res->start != res->end) { format_char(&local, '-'); format_number(&local, res->end, spec); }
    }
    if (decode) {
        if (res->flags & IORESOURCE_MEM_64) format_bytes(&local, " 64bit", 6);
        if (res->flags & IORESOURCE_PREFETCH) format_bytes(&local, " pref", 5);
        if (res->flags & IORESOURCE_WINDOW) format_bytes(&local, " window", 7);
        if (res->flags & IORESOURCE_DISABLED) format_bytes(&local, " disabled", 9);
    } else {
        format_bytes(&local, " flags ", 7);
        spec = (struct format_spec){ .base = 16, .precision = -1, .flags = F_SPECIAL | F_SMALL };
        format_number(&local, res->flags, spec);
    }
    format_char(&local, ']'); buf[local.position] = 0;
    format_string(out, buf, outer);
}

static void format_hex_bytes(struct format_output *out, const unsigned char *bytes,
    struct format_spec spec, char suffix)
{
    static const char hex[] = "0123456789abcdef";
    if (spec.width == 0) return;
    if (format_bad_pointer(out, bytes, spec)) return;
    int len = spec.width < 0 ? 1 : spec.width > 64 ? 64 : spec.width;
    char separator = suffix == 'C' ? ':' : suffix == 'D' ? '-' : suffix == 'N' ? 0 : ' ';
    for (int i = 0; i < len; i++) {
        unsigned char byte = bytes[i];
        format_char(out, hex[byte >> 4]); format_char(out, hex[byte & 15]);
        if (separator && i != len - 1) format_char(out, separator);
    }
}

static bool format_test_bit(const unsigned long *bits, unsigned int index)
{
    return !!(bits[index / (8 * sizeof(*bits))] & (1UL << (index % (8 * sizeof(*bits)))));
}

static void format_bitmap(struct format_output *out, const unsigned long *bits,
    struct format_spec spec, bool list)
{
    if (format_bad_pointer(out, bits, spec)) return;
    unsigned int nr_bits = spec.width > 0 ? spec.width : 0;
    if (list) {
        bool first = true;
        for (unsigned int index = 0; index < nr_bits;) {
            if (!format_test_bit(bits, index)) { index++; continue; }
            unsigned int first_bit = index++;
            while (index < nr_bits && format_test_bit(bits, index)) index++;
            if (!first) format_char(out, ','); first = false;
            format_number(out, first_bit, decimal_spec);
            if (index > first_bit + 1) {
                format_char(out, '-'); format_number(out, index - 1, decimal_spec);
            }
        }
    } else {
        struct format_spec chunk_spec = { .base = 16, .precision = 0, .flags = F_SMALL | F_ZERO };
        unsigned int chunks = (nr_bits + 31) / 32;
        while (chunks) {
            unsigned int first_bit = --chunks * 32;
            unsigned int len = nr_bits - first_bit < 32 ? nr_bits - first_bit : 32;
            unsigned int word = first_bit / (8 * sizeof(*bits));
            unsigned int bit = first_bit % (8 * sizeof(*bits));
            u32 value = (bits[word] >> bit) & ((1ULL << len) - 1);
            chunk_spec.width = (len + 3) / 4;
            format_number(out, value, chunk_spec);
            if (chunks) format_char(out, ',');
        }
    }
}

static void format_fourcc(struct format_output *out, const void *pointer, struct format_spec spec)
{
    if (format_bad_pointer(out, pointer, spec)) return;
    u32 original;
    memcpy(&original, pointer, sizeof(original));
    u32 value = original & ~(1U << 31);
    char text[sizeof("0123 little-endian (0x01234567)")];
    struct format_output local = { .buf = text, .size = sizeof(text) };
    for (unsigned int i = 0; i < 4; i++) {
        unsigned char c = value >> (8 * i);
        format_char(&local, c >= 32 && c < 127 ? c : '.');
    }
    if (original & (1U << 31)) format_bytes(&local, " big-endian (", 13);
    else format_bytes(&local, " little-endian (", 16);
    format_hex_address(&local, original, 4); format_char(&local, ')');
    text[local.position] = 0;
    format_string(out, text, spec);
}

static void format_parse(struct format_output *out, const char *fmt, va_list args);

static void format_unsupported(struct format_output *out, const char *extension, size_t len)
{
    /* Bounded even if the caller supplies an arbitrarily long extension. */
    format_bytes(out, "(unsupported %p", sizeof("(unsupported %p") - 1);
    format_bytes(out, extension, len < 12 ? len : 12);
    format_char(out, ')');
    out->status |= VINIX_FORMAT_UNSUPPORTED;
    out->stop = true;
}

static void format_pointer(struct format_output *out, const char *extension, size_t len,
    void *ptr, struct format_spec spec)
{
    if (!len) { format_pointer_id(out, ptr, spec); return; }
    switch (*extension) {
    case 'S': case 's': case 'B':
        /* CONFIG_KALLSYMS=n has this actual pinned address fallback. */
        format_hex_address(out, (unsigned long)ptr, sizeof(void *)); return;
    case 'x': format_pointer_number(out, (unsigned long)ptr, spec); return;
    case 'K': format_pointer_id(out, ptr, spec); return; /* supported policy 0 */
    case 'e':
        if (IS_ERR(ptr)) {
            spec.flags |= F_SIGN; spec.base = 10;
            format_number(out, (s64)(int)PTR_ERR(ptr), spec);
        } else format_pointer_id(out, ptr, spec);
        return;
    case 'R': case 'r': format_resource(out, ptr, spec, *extension == 'R'); return;
    case 'h': format_hex_bytes(out, ptr, spec, len > 1 ? extension[1] : 0); return;
    case 'b': format_bitmap(out, ptr, spec, len > 1 && extension[1] == 'l'); return;
    case 'a': {
        if (format_bad_pointer(out, ptr, spec)) return;
        u64 value;
        memcpy(&value, ptr, sizeof(value));
        format_hex_address(out, value, len > 1 && extension[1] == 'd' ? sizeof(dma_addr_t) : sizeof(phys_addr_t));
        return;
    }
    case '4':
        if (len >= 3 && extension[1] == 'c' && extension[2] == 'c') format_fourcc(out, ptr, spec);
        else format_error(out, "(%p4?)", spec);
        return;
    case 'V': {
        if (format_bad_pointer(out, ptr, spec)) return;
        const struct va_format *nested = ptr;
        /* The enclosing descriptor, format and arguments are borrowed only
         * here. No depth limit silently clips a caller's nested format. */
        va_list copy;
        va_copy(copy, *nested->va);
        struct format_output inner = {
            .buf = out->position < out->size ? out->buf + out->position : NULL,
            .size = out->position < out->size ? out->size - out->position : 0,
        };
        format_parse(&inner, nested->fmt, copy);
        out->position += inner.position;
        out->status |= inner.status;
        /* An invalid nested format stops its own vsnprintf, while the
         * enclosing Linux %pV format continues after its retained prefix. */
        if (inner.status & VINIX_FORMAT_UNSUPPORTED) out->stop = true;
        va_end(copy);
        return;
    }
    default: format_unsupported(out, extension, len); return;
    }
}

static unsigned int format_decimal(const char **format)
{
    unsigned int result = 0;
    while (**format >= '0' && **format <= '9') {
        result = result * 10 + (unsigned int)(*(*format)++ - '0');
    }
    return result;
}

static int format_width_literal(unsigned int value)
{
    /* Linux's printf_spec field is a signed 24-bit field. */
    value &= 0xffffffU;
    return value & 0x800000U ? (int)value - 0x1000000 : (int)value;
}

static int format_precision_literal(unsigned int value)
{
    int precision = (short)value;
    return precision < 0 ? 0 : precision;
}

static void format_parse(struct format_output *out, const char *fmt, va_list args)
{
    while (*fmt && !out->stop) {
        if (*fmt != '%') { format_char(out, *fmt++); continue; }
        fmt++;
        struct format_spec spec = { .base = 10, .width = -1, .precision = -1 };
        for (;;) {
            if (*fmt == '-') spec.flags |= F_LEFT;
            else if (*fmt == '+') spec.flags |= F_PLUS;
            else if (*fmt == ' ') spec.flags |= F_SPACE;
            else if (*fmt == '#') spec.flags |= F_SPECIAL;
            else if (*fmt == '0') spec.flags |= F_ZERO;
            else break;
            fmt++;
        }
        if (*fmt >= '0' && *fmt <= '9') spec.width = format_width_literal(format_decimal(&fmt));
        else if (*fmt == '*') {
            int width = va_arg(args, int); fmt++;
            if (format_width_literal((unsigned int)width) != width) {
                if (width > FIELD_MAX) width = FIELD_MAX;
                if (width < -FIELD_MAX) width = -FIELD_MAX;
            }
            if (width < 0) {
                spec.flags |= F_LEFT;
                width = format_width_literal(0U - (unsigned int)width);
            }
            spec.width = width;
        }
        if (*fmt == '.') {
            fmt++;
            if (*fmt >= '0' && *fmt <= '9') spec.precision = format_precision_literal(format_decimal(&fmt));
            else if (*fmt == '*') {
                int precision = va_arg(args, int); fmt++;
                if (precision > PRECISION_MAX) precision = PRECISION_MAX;
                if (precision < 0) precision = 0;
                spec.precision = precision;
            }
            /* Linux deliberately treats omitted .precision as -1. */
        }
        char qualifier = 0;
        if (*fmt == 'h' || *fmt == 'l' || *fmt == 'L' || *fmt == 'z' || *fmt == 't') {
            qualifier = *fmt++;
            if (qualifier == 'h' && *fmt == 'h') { qualifier = 'H'; fmt++; }
            else if (qualifier == 'l' && *fmt == 'l') { qualifier = 'L'; fmt++; }
        }
        char conversion = *fmt;
        if (conversion) fmt++;
        if (conversion == '%') { format_char(out, '%'); continue; }
        if (conversion == 'c') {
            char c = (unsigned char)va_arg(args, int);
            unsigned int pad = spec.width > 1 ? spec.width - 1 : 0;
            if (!(spec.flags & F_LEFT)) format_pad(out, ' ', pad);
            format_char(out, c);
            if (spec.flags & F_LEFT) format_pad(out, ' ', pad);
            continue;
        }
        if (conversion == 's') {
            const char *str = va_arg(args, const char *);
            if (!format_bad_pointer(out, str, spec)) format_string(out, str, spec);
            continue;
        }
        if (conversion == 'p') {
            const char *extension = fmt;
            while (format_alnum(*fmt)) fmt++;
            format_pointer(out, extension, fmt - extension, va_arg(args, void *), spec);
            continue;
        }
        if (conversion == 'o') spec.base = 8;
        else if (conversion == 'x' || conversion == 'X') {
            spec.base = 16;
            if (conversion == 'x') spec.flags |= F_SMALL;
        } else if (conversion == 'd' || conversion == 'i') spec.flags |= F_SIGN;
        else if (conversion != 'u') {
            /* In particular, %n never fetches or writes its pointer. */
            out->status |= VINIX_FORMAT_INVALID; out->stop = true; continue;
        }
        u64 value;
        if (qualifier == 'L') value = va_arg(args, long long);
        else if (qualifier == 'l') {
            if (spec.flags & F_SIGN) value = va_arg(args, long);
            else value = va_arg(args, unsigned long);
        } else if (qualifier == 'z') {
            if (spec.flags & F_SIGN) value = va_arg(args, ssize_t);
            else value = va_arg(args, size_t);
        } else if (qualifier == 't') value = va_arg(args, ptrdiff_t);
        else if (qualifier == 'H') {
            if (spec.flags & F_SIGN) value = (signed char)va_arg(args, int);
            else value = (unsigned char)va_arg(args, int);
        } else if (qualifier == 'h') {
            if (spec.flags & F_SIGN) value = (short)va_arg(args, int);
            else value = (unsigned short)va_arg(args, int);
        } else if (spec.flags & F_SIGN) value = va_arg(args, int);
        else value = va_arg(args, unsigned int);
        format_number(out, value, spec);
    }
}

int vinix_linuxkpi_vformat(char *buf, size_t size, const char *fmt, va_list args, unsigned int *status)
{
    if (size > INT_MAX) { if (status) *status = VINIX_FORMAT_INVALID; return 0; }
    struct format_output out = { .buf = buf, .size = size };
    format_parse(&out, fmt, args);
    if (size) buf[out.position < size ? out.position : size - 1] = 0;
    if (out.position >= size && out.position) out.status |= VINIX_FORMAT_TRUNCATED;
    if (status) *status = out.status;
    return (int)out.position;
}

int vsnprintf(char *buf, size_t size, const char *fmt, va_list args)
{
    return vinix_linuxkpi_vformat(buf, size, fmt, args, NULL);
}

int snprintf(char *buf, size_t size, const char *fmt, ...)
{
    va_list args; va_start(args, fmt);
    int count = vsnprintf(buf, size, fmt, args);
    va_end(args); return count;
}

int vscnprintf(char *buf, size_t size, const char *fmt, va_list args)
{
    if (!size) return 0;
    int count = vsnprintf(buf, size, fmt, args);
    return (size_t)count < size ? count : (int)(size - 1);
}

int scnprintf(char *buf, size_t size, const char *fmt, ...)
{
    va_list args; va_start(args, fmt);
    int count = vscnprintf(buf, size, fmt, args);
    va_end(args); return count;
}

int vsprintf(char *buf, const char *fmt, va_list args)
{
    return vsnprintf(buf, INT_MAX, fmt, args);
}

int sprintf(char *buf, const char *fmt, ...)
{
    va_list args; va_start(args, fmt);
    int count = vsnprintf(buf, INT_MAX, fmt, args);
    va_end(args); return count;
}
#endif
