/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include "mac.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef VINIX_MAC_HOST_TEST
#include <sys/prctl.h>
#include <sys/xattr.h>
#endif
#include <unistd.h>

static int number(const char *text, unsigned limit, unsigned *value)
{
    if (!text[0] || (text[0] == '0' && text[1])) return -1;
    unsigned result = 0;
    for (const unsigned char *p = (const unsigned char *)text; *p; ++p) {
        if (*p < '0' || *p > '9' || result > limit / 10) return -1;
        result = result * 10 + (unsigned)(*p - '0');
        if (result >= limit) return -1;
    }
    *value = result;
    return 0;
}

static int permissions(const char *text, unsigned *mask)
{
    static const struct { const char *name; unsigned bit; } names[] = {
        { "inspect", VINIX_MAC_INSPECT }, { "read", VINIX_MAC_READ },
        { "write", VINIX_MAC_WRITE }, { "execute", VINIX_MAC_EXECUTE },
        { "create", VINIX_MAC_CREATE }, { "remove", VINIX_MAC_REMOVE },
        { "metadata", VINIX_MAC_METADATA }, { "ioctl", VINIX_MAC_IOCTL },
        { "search", VINIX_MAC_SEARCH },
    };
    if (!strcmp(text, "none")) { *mask = 0; return 0; }
    unsigned result = 0;
    while (*text) {
        const char *end = strchr(text, ',');
        size_t length = end ? (size_t)(end - text) : strlen(text);
        int found = 0;
        for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
            if (strlen(names[i].name) == length && !memcmp(text, names[i].name, length)) {
                if (result & names[i].bit) return -1;
                result |= names[i].bit;
                found = 1;
                break;
            }
        }
        if (!found) return -1;
        if (!end) { *mask = result; return 0; }
        text = end + 1;
    }
    return -1;
}

static int failed(const char *operation)
{
    fprintf(stderr, "vinix-mac: %s: %s\n", operation, strerror(errno));
    return 1;
}

static int usage(void)
{
    fputs("usage: vinix-mac status\n"
          "       vinix-mac rule DOMAIN TYPE inspect,read,write,execute,search,create,remove,metadata,ioctl|none\n"
          "       vinix-mac label TYPE PATH...\n"
          "       vinix-mac seal\n"
          "       vinix-mac run DOMAIN PROGRAM [ARG...]\n", stderr);
    return 2;
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "status")) {
        long domain = prctl(VINIX_MAC_PRCTL, 0UL, 0UL, 0UL, 0UL);
        if (domain < 0) return failed("read domain");
        long sealed = prctl(VINIX_MAC_PRCTL, 4UL, 0UL, 0UL, 0UL);
        if (sealed < 0) return failed("read policy state");
        printf("domain=%ld sealed=%ld\n", domain, sealed);
        return 0;
    }
    if (argc == 2 && !strcmp(argv[1], "seal")) {
        if (prctl(VINIX_MAC_PRCTL, 2UL, 0UL, 0UL, 0UL) < 0) return failed("seal policy");
        return 0;
    }
    unsigned domain, kind, mask;
    if (argc == 5 && !strcmp(argv[1], "rule")) {
        if (number(argv[2], VINIX_MAC_DOMAINS, &domain) || domain == 0
            || number(argv[3], VINIX_MAC_TYPES, &kind) || permissions(argv[4], &mask)) return usage();
        if (prctl(VINIX_MAC_PRCTL, 1UL, (unsigned long)domain,
                  (unsigned long)kind, (unsigned long)mask) < 0) return failed("install rule");
        return 0;
    }
    if (argc >= 4 && !strcmp(argv[1], "label")) {
        if (number(argv[2], VINIX_MAC_LABEL_TYPES, &kind)) return usage();
        for (int i = 3; i < argc; ++i) {
            if (lsetxattr(argv[i], "security.vinix", argv[2], strlen(argv[2]), 0)) return failed(argv[i]);
        }
        return 0;
    }
    if (argc >= 4 && !strcmp(argv[1], "run")) {
        if (number(argv[2], VINIX_MAC_DOMAINS, &domain) || domain == 0) return usage();
        if (prctl(VINIX_MAC_PRCTL, 3UL, (unsigned long)domain, 0UL, 0UL) < 0) return failed("stage domain");
        execvp(argv[3], argv + 3);
        return failed(argv[3]);
    }
    return usage();
}
