// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Guest side of the AMD-Vi checks: run as /sbin/init in a QEMU q35 machine
// with an e1000 and, for most cases, `-device amd-iommu,dma-remap=on`. It
// reports what the kernel says about its IOMMU and about the network card's
// DMA domain, proves that the card's transmit and receive DMA work by getting
// an answer from the network, rebinds the card's driver twenty times while
// watching the unit's page-table pages and the machine's free memory, and
// prints the result of the kernel's isolation self-test when the kernel was
// built with one (`-d amdvi_selftest`).
//
// `dma-remap=on` matters. Without it QEMU's AMD IOMMU (as of 11.1) accepts
// every command and translates nothing: the network works, the domain reads
// "isolated", and the card can reach all of memory. Only the self-test tells
// the two apart.
//
// Everything goes to the serial console as lines starting "IOMMU-AMD", since
// an amd64 kernel's own messages go to the screen. The cases to boot:
//
//	vinix.iommu=1, amd-iommu     a unit, the card "isolated", answers before
//	                             and after the rebinds, the page-table page
//	                             count with the card unbound unchanged, and
//	                             "selftest: result: PASS" from a test kernel
//	no vinix.iommu=1             "unit: none", the card "direct", answers
//	vinix.iommu=1, no amd-iommu  the same
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/socket.h>
#include <unistd.h>

#ifndef CONSOLE
#define CONSOLE "/dev/console"
#endif

static int out = 1;

static void say(const char *fmt, ...) {
    static char line[9216];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof line - 1) n = sizeof line - 1;
    if (n > 0) write(out, line, n);
}

static int read_file(const char *path, char *buf, int cap) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -errno;
    int total = 0, n;
    while (total < cap - 1 && (n = read(fd, buf + total, cap - 1 - total)) > 0) total += n;
    close(fd);
    buf[total] = 0;
    return total;
}

static int write_file(const char *path, const char *text) {
    int fd = open(path, O_WRONLY);
    if (fd < 0) return -errno;
    int n = write(fd, text, strlen(text));
    int e = errno;
    close(fd);
    return n < 0 ? -e : n;
}

// Print a file as one line, its newlines turned into " | ".
static void show(const char *label, const char *path) {
    static char text[8192], flat[9000];
    int n = read_file(path, text, sizeof text);
    if (n < 0) {
        say("IOMMU-AMD %s: (errno %d)\n", label, -n);
        return;
    }
    int o = 0;
    for (int i = 0; i < n && o < (int)sizeof flat - 4; i++) {
        if (text[i] == '\n') {
            if (i + 1 < n) { flat[o++] = ' '; flat[o++] = '|'; flat[o++] = ' '; }
        } else {
            flat[o++] = text[i];
        }
    }
    flat[o] = 0;
    say("IOMMU-AMD %s: %s\n", label, flat);
}

// The number after `key` in a file of "key value" lines; -1 when absent.
static long field(const char *path, const char *key) {
    char text[4096];
    if (read_file(path, text, sizeof text) < 0) return -1;
    char *at = strstr(text, key);
    if (!at) return -1;
    at += strlen(key);
    while (*at == ' ' || *at == ':' || *at == '\t') at++;
    return strtol(at, 0, 10);
}

// Ask QEMU's resolver at 10.0.2.3 for example.com. The question leaves
// through the card's transmit ring and the answer comes back through its
// receive ring, so an answer means both directions of DMA work. Returns the
// number of bytes in the answer, or 0.
static int dns_answer(int seconds) {
    static const unsigned char question[] = {
        0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 3, 'c', 'o', 'm', 0,
        0x00, 0x01, 0x00, 0x01,
    };
    struct sockaddr_in resolver = {0};
    resolver.sin_family = AF_INET;
    resolver.sin_port = htons(53);
    resolver.sin_addr.s_addr = htonl(0x0a000203);
    for (int attempt = 0; attempt < seconds; attempt++) {
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        if (fd < 0) { sleep(1); continue; }
        // Until DHCP has given the interface an address there is no route.
        if (sendto(fd, question, sizeof question, 0, (struct sockaddr *)&resolver,
                   sizeof resolver) != (int)sizeof question) {
            close(fd);
            sleep(1);
            continue;
        }
        struct pollfd wait = {fd, POLLIN, 0};
        if (poll(&wait, 1, 1000) > 0) {
            unsigned char answer[512];
            int n = recv(fd, answer, sizeof answer, 0);
            close(fd);
            if (n >= 12 && answer[0] == 0x12 && answer[1] == 0x34 && (answer[2] & 0x80)) return n;
        } else {
            close(fd);
        }
    }
    return 0;
}

// A second proof that needs nothing beyond QEMU itself: nothing listens on
// the host's discard port, so the connection is refused -- by a reset that
// has to arrive through the receive ring. A dead receive path times out.
static int tcp_errno;
static int tcp_refused(void) {
    struct sockaddr_in host = {0};
    host.sin_family = AF_INET;
    host.sin_port = htons(9);
    host.sin_addr.s_addr = htonl(0x0a000202);
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return 0;
    int r = connect(fd, (struct sockaddr *)&host, sizeof host);
    int e = errno;
    close(fd);
    tcp_errno = r < 0 ? e : 0;
    // The reset reaches a program as "refused" or, here, as "reset".
    return r < 0 && (e == ECONNREFUSED || e == ECONNRESET);
}

static void network(const char *when) {
    int n = dns_answer(20);
    int refused = tcp_refused();
    say("IOMMU-AMD network %s: dns %s (%d bytes), tcp-reset %s (errno %d)\n", when,
        n ? "answered" : "NO ANSWER", n, refused ? "received" : "NOT RECEIVED", tcp_errno);
}

int main(void) {
    int fd = open(CONSOLE, O_WRONLY);
    if (fd >= 0) out = fd;
    say("IOMMU-AMD START\n");

    char unit[64] = "";
    DIR *d = opendir("/sys/class/iommu");
    // The kernel publishes its units from a thread, moments after /sys is
    // mounted; give it those moments.
    for (int i = 0; !d && i < 20; i++) {
        usleep(100000);
        d = opendir("/sys/class/iommu");
    }
    if (d) {
        struct dirent *e;
        while ((e = readdir(d)))
            if (!strncmp(e->d_name, "ivhd", 4)) strcpy(unit, e->d_name);
        closedir(d);
    }
    char path[256], pages[256], line[80];
    if (unit[0]) {
        say("IOMMU-AMD unit: %s\n", unit);
        static const char *files[] = {"unit", "features", "events", "domains", "selftest"};
        for (unsigned i = 0; i < sizeof files / sizeof files[0]; i++) {
            snprintf(path, sizeof path, "/sys/class/iommu/%s/%s", unit, files[i]);
            if (access(path, F_OK) == 0) show(files[i], path);
        }
    } else {
        say("IOMMU-AMD unit: none\n");
    }
    snprintf(pages, sizeof pages, "/sys/class/iommu/%s/unit", unit);

    char card[64] = "";
    d = opendir("/sys/bus/pci/drivers/e1000");
    if (d) {
        struct dirent *e;
        while ((e = readdir(d)))
            if (e->d_name[0] == '0') strcpy(card, e->d_name);
        closedir(d);
    }
    say("IOMMU-AMD e1000: %s\n", card[0] ? card : "none");
    if (!card[0]) goto done;
    snprintf(path, sizeof path, "/sys/bus/pci/devices/%s/dma", card);
    show("e1000 dma", path);
    network("first");

    // Twenty times round: each unbind tears the card's domain down and each
    // bind builds a new one. Neither may leave anything behind. The count of
    // page-table pages is taken with the card unbound, when it should be
    // whatever firmware's ranges need and no more: with the card bound it
    // depends on where the card's buffers happened to land.
    snprintf(line, sizeof line, "%s\n", card);
    int failed = 0;
    if (write_file("/sys/bus/pci/drivers/e1000/unbind", line) < 0) failed++;
    long tables_before = unit[0] ? field(pages, "table_pages") : -1;
    long free_before = field("/proc/meminfo", "MemFree");
    for (int i = 0; i < 20; i++) {
        if (write_file("/sys/bus/pci/drivers/e1000/bind", line) < 0) failed++;
        if (write_file("/sys/bus/pci/drivers/e1000/unbind", line) < 0) failed++;
    }
    long tables_after = unit[0] ? field(pages, "table_pages") : -1;
    long free_after = field("/proc/meminfo", "MemFree");
    if (write_file("/sys/bus/pci/drivers/e1000/bind", line) < 0) failed++;
    say("IOMMU-AMD rebind x20: failed %d, table_pages while unbound %ld -> %ld, MemFree while unbound "
        "%ld -> %ld kB\n", failed, tables_before, tables_after, free_before, free_after);
    show("e1000 dma after rebind", path);
    network("after rebind");

    if (unit[0]) {
        snprintf(path, sizeof path, "/sys/class/iommu/%s/events", unit);
        show("events at end", path);
        snprintf(path, sizeof path, "/sys/class/iommu/%s/domains", unit);
        show("domains at end", path);
    }
done:
    say("IOMMU-AMD DONE\n");
    sync();
    reboot(RB_POWER_OFF);
    for (;;) pause();
}
