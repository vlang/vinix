/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef VINIX_LINUXKPI
#include <linux/errno.h>
#include <linux/limits.h>
#include <linux/slab.h>
#include <linux/string.h>

void *memchr(const void *s, int c, size_t n)
{
    const unsigned char *bytes = s;
    for (size_t i = 0; i < n; i++) {
        if (bytes[i] == (unsigned char)c) return (void *)(bytes + i);
    }
    return NULL;
}

void *memchr_inv(const void *s, int c, size_t n)
{
    const unsigned char *bytes = s;
    for (size_t i = 0; i < n; i++) {
        if (bytes[i] != (unsigned char)c) return (void *)(bytes + i);
    }
    return NULL;
}

size_t strnlen(const char *s, size_t n)
{
    size_t len = 0;
    while (len < n && s[len]) len++;
    return len;
}

ssize_t strscpy(char *dest, const char *src, size_t count)
{
    if (!count || count > INT_MAX) return -E2BIG;
    for (size_t i = 0; i < count; i++) {
        char c = src[i];
        dest[i] = c;
        if (!c) return (ssize_t)i;
    }
    dest[count - 1] = '\0';
    return -E2BIG;
}

ssize_t strscpy_pad(char *dest, const char *src, size_t count)
{
    ssize_t len = strscpy(dest, src, count);
    if (len >= 0) memset(dest + len + 1, 0, count - (size_t)len - 1);
    return len;
}

char *kmemdup_nul(const char *s, size_t n, gfp_t flags)
{
    if (n == SIZE_MAX) return NULL;
    char *copy = kmalloc(n + 1, flags);
    if (!copy) return NULL;
    if (n) memcpy(copy, s, n);
    copy[n] = '\0';
    return copy;
}

char *kstrndup(const char *s, size_t max, gfp_t flags)
{
    return s ? kmemdup_nul(s, strnlen(s, max), flags) : NULL;
}

char *kstrdup(const char *s, gfp_t flags)
{
    return kstrndup(s, SIZE_MAX, flags);
}
#endif
