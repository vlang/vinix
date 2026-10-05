// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the actual source-built Bionic provider, using numeric addresses.
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <netdb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "musl-statistics.h"

struct android_addrinfo {
    int flags, family, socktype, protocol;
    socklen_t address_length;
    char *canonical_name;
    struct sockaddr *address;
    struct android_addrinfo *next;
};

static int (*resolve)(const char *, const char *, const struct android_addrinfo *, struct android_addrinfo **);
static void (*release)(struct android_addrinfo *);
static int (*reverse)(const struct sockaddr *, socklen_t, char *, size_t, char *, size_t, int);
static const char *(*error_text)(int);
static int (*statistics)(struct vinix_malloc_stats *, size_t);

static void require(int condition, const char *reason)
{
    if (!condition) {
        fprintf(stderr, "ANDROID-NETDB-FAIL %s errno=%d\n", reason, errno);
        exit(1);
    }
}

static struct android_addrinfo *numeric(int family, int flags)
{
    struct android_addrinfo hints = {.family = family, .flags = flags, .socktype = SOCK_STREAM};
    struct android_addrinfo *result = NULL;
    require(resolve("127.0.0.1", "443", &hints, &result) == 0 && result != NULL,
            "resolve numeric address with Android flags");
    return result;
}

static void check_results(struct android_addrinfo *result, int family)
{
    unsigned count = 0;
    for (struct android_addrinfo *item = result; item != NULL; item = item->next) {
        require(++count < 16 && item->family == family && item->socktype == SOCK_STREAM,
                "Android result list layout");
        require(item->address != NULL && item->address->sa_family == family,
                "Android address and canonical-name offsets");
        if (family == AF_INET) {
            const struct sockaddr_in *address = (const struct sockaddr_in *)item->address;
            require(item->address_length == sizeof(*address) && ntohs(address->sin_port) == 443
                    && ntohl(address->sin_addr.s_addr) == 0x7f000001, "numeric IPv4 result");
        } else {
            const struct sockaddr_in6 *address = (const struct sockaddr_in6 *)item->address;
            require(item->address_length == sizeof(*address) && ntohs(address->sin6_port) == 443
                    && IN6_IS_ADDR_V4MAPPED(&address->sin6_addr)
                    && address->sin6_addr.s6_addr[12] == 127
                    && address->sin6_addr.s6_addr[15] == 1, "Android IPv4-mapped IPv6 result");
        }
    }
}

static void check_forward(void)
{
    struct android_addrinfo *result = numeric(AF_INET, 4 | 2);
    check_results(result, AF_INET);
    require(result->canonical_name != NULL && strcmp(result->canonical_name, "127.0.0.1") == 0,
            "Android canonical-name offset");
    release(result);
    result = numeric(AF_INET6, 4 | 0x800);
    check_results(result, AF_INET6);
    release(result);
    result = numeric(AF_INET6, 4 | 0x800 | 0x100);
    check_results(result, AF_INET6);
    release(result);

    struct addrinfo host_hints = {.ai_family = AF_INET, .ai_flags = AI_ADDRCONFIG | AI_NUMERICHOST,
                                 .ai_socktype = SOCK_STREAM};
    struct addrinfo *host_result = NULL;
    int host_status = getaddrinfo("127.0.0.1", "https", &host_hints, &host_result);
    // The service database may omit https; both APIs must agree about that,
    // while Android's ADDRCONFIG must never turn into NUMERICSERV.
    require(host_status == 0 || host_status == EAI_SERVICE, "host named-service baseline");
    if (host_status == 0) freeaddrinfo(host_result);
    struct android_addrinfo hints = {.family = AF_INET, .flags = 4 | 0x400, .socktype = SOCK_STREAM};
    result = NULL;
    int status = resolve("127.0.0.1", "https", &hints, &result);
    require(status == (host_status == 0 ? 0 : 9), "ADDRCONFIG preserves named-service lookup");
    if (status == 0) release(result);

    hints.flags = 4 | 8;
    result = NULL;
    require(resolve("127.0.0.1", "https", &hints, &result) == 8,
            "Android NUMERICSERV rejects named service with positive NONAME");
    hints.flags = 0x4000;
    require(resolve("127.0.0.1", "443", &hints, &result) == 3, "positive Android BADFLAGS");
    hints.flags = 4;
    require(resolve("must-not-resolve.invalid", "443", &hints, &result) == 8,
            "numeric-host rejection uses Android NONAME");
    hints.family = AF_UNIX;
    require(resolve("127.0.0.1", "443", &hints, &result) == 5, "positive Android FAMILY");
    hints.family = AF_INET;
    require(resolve("127.0.0.1", "65536", &hints, &result) == 9, "positive Android SERVICE");
}

static void check_reverse(void)
{
    struct sockaddr_in address = {.sin_family = AF_INET, .sin_port = htons(443)};
    require(inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1, "initialize numeric address");
    char host[128], service[32];
    require(reverse((struct sockaddr *)&address, sizeof(address), host, sizeof(host),
                    service, sizeof(service), 2 | 8) == 0
            && strcmp(host, "127.0.0.1") == 0 && strcmp(service, "443") == 0,
            "Android numeric reverse flags");
    require(reverse((struct sockaddr *)&address, sizeof(address), host, 1,
                    service, sizeof(service), 2 | 8) == 14, "positive Android OVERFLOW");
    require(reverse((struct sockaddr *)&address, sizeof(address), host, sizeof(host),
                    service, sizeof(service), 0x4000) == 3, "reverse rejects unknown Android flags");
#if SIZE_MAX > UINT_MAX
    // The result is tiny even when Android's size_t bound exceeds the host's
    // socklen_t range. Wrapping that bound to zero would lose a valid result.
    strcpy(host, "pending-host");
    require(reverse((struct sockaddr *)&address, sizeof(address), host, (size_t)UINT_MAX + 1,
                    service, sizeof(service), 2 | 8) == 0
            && strcmp(host, "127.0.0.1") == 0 && strcmp(service, "443") == 0,
            "64-bit Android host bound does not wrap");
    strcpy(service, "pending-service");
    require(reverse((struct sockaddr *)&address, sizeof(address), host, sizeof(host),
                    service, (size_t)UINT_MAX + 1, 2 | 8) == 0
            && strcmp(host, "127.0.0.1") == 0 && strcmp(service, "443") == 0,
            "64-bit Android service bound does not wrap");
#endif
    struct sockaddr_in6 scoped = {.sin6_family = AF_INET6, .sin6_port = htons(443), .sin6_scope_id = 1};
    require(inet_pton(AF_INET6, "fe80::1", &scoped.sin6_addr) == 1, "initialize scoped address");
    require(reverse((struct sockaddr *)&scoped, sizeof(scoped), host, sizeof(host),
                    service, sizeof(service), 2 | 8 | 32) == 0
            && strncmp(host, "fe80::1%", 8) == 0 && strcmp(service, "443") == 0,
            "scoped numeric IPv6 reverse result");
}

static void check_errors(void)
{
    const struct {int android, host;} errors[] = {
        {2, EAI_AGAIN}, {3, EAI_BADFLAGS}, {4, EAI_FAIL}, {5, EAI_FAMILY},
        {6, EAI_MEMORY}, {8, EAI_NONAME}, {9, EAI_SERVICE}, {10, EAI_SOCKTYPE},
        {11, EAI_SYSTEM}, {14, EAI_OVERFLOW}
    };
    for (unsigned index = 0; index < sizeof(errors)/sizeof(errors[0]); ++index)
        require(strcmp(error_text(errors[index].android), gai_strerror(errors[index].host)) == 0,
                "Android error text uses matching host error domain");
    require(strcmp(error_text(0), "Success") == 0 && strcmp(error_text(INT_MAX), "Unknown error") == 0,
            "success and unknown error text");
}

int main(int argc, char **argv)
{
    alarm(30);
    require(argc == 2, "usage: netdb-test libc_bio.so");
    require(dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL) != NULL, "load real Bionic provider");
    resolve = dlsym(RTLD_DEFAULT, "bionic_getaddrinfo");
    release = dlsym(RTLD_DEFAULT, "bionic_freeaddrinfo");
    reverse = dlsym(RTLD_DEFAULT, "bionic_getnameinfo");
    error_text = dlsym(RTLD_DEFAULT, "bionic_gai_strerror");
    statistics = dlsym(RTLD_DEFAULT, "__vinix_malloc_stats");
    require(resolve && release && reverse && error_text, "Android netdb exports");
    check_forward();
    check_reverse();
    check_errors();
    struct vinix_malloc_stats before, after;
    if (statistics) require(statistics(&before, sizeof(before)) == 0, "allocator baseline");
    for (unsigned iteration = 0; iteration < 200; ++iteration) {
        struct android_addrinfo *result = numeric(AF_UNSPEC, 4 | 2);
        release(result);
    }
    if (statistics) {
        require(statistics(&after, sizeof(after)) == 0
                && after.live_bytes == before.live_bytes && after.live_blocks == before.live_blocks,
                "free returned lists without retained caller allocations");
    }
    puts("ANDROID-NETDB-PASS flags=android errors=android v4mapped=verified numeric-reverse=verified free-list=verified");
    return 0;
}
