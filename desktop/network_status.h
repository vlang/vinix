/* SPDX-License-Identifier: GPL-2.0-or-later
 * The taskbar's network icon asks the kernel about one interface with the same
 * SIOCGIFADDR query ifconfig uses. Kept in C because struct ifreq is a union
 * whose layout V has no reason to restate. */
#ifndef VINIX_DESKTOP_NETWORK_STATUS_H
#define VINIX_DESKTOP_NETWORK_STATUS_H

#include <errno.h>
#include <net/if.h>
#include <netinet/in.h>
#include <stdint.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

/* Returns 0 with the interface's IPv4 address in network byte order,
 * ENODEV or ENXIO when there is no such interface, EADDRNOTAVAIL while it has
 * no address yet, or another errno value when the question failed. */
static inline int vinix_interface_ipv4(const char *name, uint32_t *address) {
    struct ifreq request;
    int result = 0;
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        return errno ? errno : EIO;
    }
    memset(&request, 0, sizeof request);
    strncpy(request.ifr_name, name, IFNAMSIZ - 1);
    if (ioctl(fd, SIOCGIFADDR, &request) != 0) {
        result = errno ? errno : EIO;
    } else {
        struct sockaddr_in *in = (struct sockaddr_in *)&request.ifr_addr;
        *address = (uint32_t)in->sin_addr.s_addr;
    }
    close(fd);
    return result;
}

#endif
