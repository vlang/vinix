/* SPDX-License-Identifier: GPL-2.0-only */
/* Whitespace/matching/replacement portions from Linux 6.6.157 lib/string_helpers.c:
 * Copyright 31 August 2008 James Bottomley
 * Copyright (C) 2013, Intel Corporation
 */
/* Token/search portions from Linux 6.6.157 lib/string.c:
 * Copyright (C) 1991, 1992 Linus Torvalds
 */
#ifdef VINIX_LINUXKPI
#include <linux/ctype.h>
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

/* Keep the original synchronous borrowed-string semantics. A newline is
 * equivalent to NUL only when it is the single trailing newline. */
bool sysfs_streq(const char *s1, const char *s2)
{
    while (*s1 && *s1 == *s2) {
        s1++;
        s2++;
    }
    if (*s1 == *s2) return true;
    if (!*s1 && *s2 == '\n' && !s2[1]) return true;
    if (*s1 == '\n' && !s1[1] && !*s2) return true;
    return false;
}

int match_string(const char * const *array, size_t n, const char *string)
{
    /* The explicit cast preserves Linux's usual conversion in index < n. */
    for (int index = 0; (size_t)index < n; index++) {
        const char *item = array[index];
        if (!item) break;
        if (!strcmp(item, string)) return index;
    }
    return -EINVAL;
}

int __sysfs_match_string(const char * const *array, size_t n, const char *str)
{
    for (int index = 0; (size_t)index < n; index++) {
        const char *item = array[index];
        if (!item) break;
        if (sysfs_streq(item, str)) return index;
    }
    return -EINVAL;
}

char *strreplace(char *str, char old, char new)
{
    for (char *s = str; *s; ++s)
        if (*s == old) *s = new;
    return str;
}

char *strchr(const char *s, int c)
{
	for (; *s != (char)c; ++s)
		if (*s == '\0')
			return NULL;
	return (char *)s;
}

char *strpbrk(const char *cs, const char *ct)
{
	const char *sc;

	for (sc = cs; *sc != '\0'; ++sc) {
		if (strchr(ct, *sc))
			return (char *)sc;
	}
	return NULL;
}

char *strsep(char **s, const char *ct)
{
	char *sbegin = *s;
	char *end;

	if (sbegin == NULL)
		return NULL;

	end = strpbrk(sbegin, ct);
	if (end)
		*end++ = '\0';
	*s = end;
	return sbegin;
}

char *skip_spaces(const char *str)
{
	while (isspace(*str))
		++str;
	return (char *)str;
}

char *strim(char *s)
{
	size_t size;
	char *end;

	size = strlen(s);
	if (!size)
		return s;

	/* The pinned algorithm forms s - 1 for all-whitespace input. Keep its
	 * returned pointer and byte mutations while staying within the string. */
	end = s + size;
	while (end > s && isspace(end[-1]))
		end--;
	*end = '\0';

	return skip_spaces(s);
}
#endif
