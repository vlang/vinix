#ifndef VINIX_IPV6_GUEST_ABI_H
#define VINIX_IPV6_GUEST_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/syscall.h>
typedef unsigned long long ipv6_ull;
_Static_assert(sizeof(ipv6_ull) == sizeof(uint64_t), "native diagnostic and parser width");
_Static_assert(sizeof(struct sockaddr_in6) == 28 && sizeof(socklen_t) == 4,
               "original Linux socket ABI");
#endif
