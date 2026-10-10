// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Run as /sbin/init in a QEMU guest to say, on the serial console, what the
// kernel made of the machine's IOMMU and whether a network card still works
// behind it.
//
// It reports what /sys/class/iommu holds, what the e1000's `dma` file says,
// and whether the card can send and receive: a DNS query to QEMU's resolver,
// and a file fetched from QEMU's TFTP server when the guest was started with
// one (-nic user,model=e1000,tftp=DIR with a file DIR/vtd-probe). Either
// answer has to come in through the receive ring, so either proves DMA in
// both directions. Then it unbinds and binds the card twenty times and checks
// that the network is still there and that neither the unit's page-table
// pages nor free memory moved.
//
// Every line it prints starts with "IOMMU-TEST"; the last one is
// "IOMMU-TEST DONE". The same program serves every scenario: with no IOMMU,
// or one that was not switched on, it reports that instead.
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

static void sayf(const char *fmt, ...) {
    char line[1024];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof line) n = sizeof line;
    if (n > 0) write(out, line, n);
}

static int read_file(const char *path, char *buf, int cap) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -errno;
    int n = read(fd, buf, cap - 1);
    int e = errno;
    close(fd);
    if (n < 0) return -e;
    buf[n] = 0;
    return n;
}

static int write_file(const char *path, const char *text) {
    int fd = open(path, O_WRONLY);
    if (fd < 0) return -errno;
    int n = write(fd, text, strlen(text));
    int e = errno;
    close(fd);
    return n < 0 ? -e : n;
}

// Print a file on one line, its newlines turned into bars.
static void show(const char *label, const char *path) {
    char buf[1024];
    int n = read_file(path, buf, sizeof buf);
    if (n < 0) {
        sayf("IOMMU-TEST %s: errno %d\n", label, -n);
        return;
    }
    while (n > 0 && buf[n - 1] == '\n') buf[--n] = 0;
    for (char *c = buf; *c; c++)
        if (*c == '\n') *c = '|';
    sayf("IOMMU-TEST %s: %s\n", label, buf);
}

// The number after `key` in a "key: value" file such as /proc/meminfo, or -1.
static long long number_after(const char *path, const char *key) {
    char buf[4096];
    if (read_file(path, buf, sizeof buf) < 0) return -1;
    char *at = strstr(buf, key);
    if (!at) return -1;
    at += strlen(key);
    while (*at == ' ' || *at == ':' || *at == '\t') at++;
    return atoll(at);
}

// One exchange over UDP: send `request`, wait up to a second for an answer.
static int exchange(const char *address, int port, const void *request, int request_len,
                    unsigned char *reply, int reply_cap) {
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) return -errno;
    struct sockaddr_in to = {0};
    to.sin_family = AF_INET;
    to.sin_port = htons(port);
    inet_pton(AF_INET, address, &to.sin_addr);
    if (sendto(s, request, request_len, 0, (struct sockaddr *)&to, sizeof to) < 0) {
        int e = errno;
        close(s);
        return -e;
    }
    struct pollfd p = {.fd = s, .events = POLLIN};
    int got = -ETIMEDOUT;
    if (poll(&p, 1, 1000) > 0) {
        got = recv(s, reply, reply_cap, 0);
        if (got < 0) got = -errno;
    }
    close(s);
    return got;
}

// What the last exchange of each kind returned: a length, or minus an errno.
static int last_dns, last_tftp;

// A query for the A record of example.com, answered by QEMU's resolver from
// whatever the host's own resolver says. Any reply to this query will do: it
// is the round trip that is being tested, not the Internet.
static int dns_works(void) {
    static const unsigned char query[] = {
        0x56, 0x54, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0,
        7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 3, 'c', 'o', 'm', 0, 0, 1, 0, 1,
    };
    unsigned char reply[512];
    int n = exchange("10.0.2.3", 53, query, sizeof query, reply, sizeof reply);
    last_dns = n;
    return n >= 12 && reply[0] == 0x56 && reply[1] == 0x54 && (reply[2] & 0x80);
}

// A read request for "vtd-probe", answered by QEMU's TFTP server with the
// first block of the file, which needs nothing outside QEMU.
static int tftp_works(void) {
    static const unsigned char request[] = "\0\1vtd-probe\0octet";
    unsigned char reply[600];
    int n = exchange("10.0.2.2", 69, request, sizeof request, reply, sizeof reply);
    last_tftp = n;
    return n >= 4 + 8 && reply[1] == 3 && reply[3] == 1 && memcmp(reply + 4, "vtd-okay", 8) == 0;
}

// Wait for the network to come up -- the kernel asks for its address by DHCP
// when the card is bound -- and say which of the two exchanges worked.
static int network(const char *when) {
    int dns = 0, tftp = 0, tries = 0;
    while (tries < 60 && !(dns && tftp)) {
        tries++;
        if (!dns) dns = dns_works();
        if (!tftp) tftp = tftp_works();
        // One of them is proof enough; give the other a few more tries.
        if ((dns || tftp) && tries >= 4) break;
        // An exchange that fails at once -- no route yet -- is not retried
        // in a tight loop.
        if (!dns && !tftp && last_dns != -ETIMEDOUT) usleep(500000);
    }
    sayf("IOMMU-TEST network %s: dns=%s tftp=%s tries=%d (last results %d %d) => %s\n", when,
         dns ? "ok" : "none", tftp ? "ok" : "none", tries, last_dns, last_tftp,
         dns || tftp ? "WORKS" : "DEAD");
    return dns || tftp;
}

static void show_unit(const char *unit) {
    static const char *files[] = {"state", "version", "address", "cap", "ecap",
                                  "domains", "pages", "faults", "selftest"};
    for (unsigned i = 0; i < sizeof files / sizeof *files; i++) {
        char path[256], label[96];
        snprintf(path, sizeof path, "/sys/class/iommu/%s/%s", unit, files[i]);
        if (access(path, F_OK) != 0) continue;
        snprintf(label, sizeof label, "%s/%s", unit, files[i]);
        show(label, path);
    }
}

int main(void) {
    int fd = open(CONSOLE, O_WRONLY);
    if (fd >= 0) out = fd;
    sayf("IOMMU-TEST START\n");

    // The units appear under /sys a moment after /sys does.
    char unit[64] = "";
    for (int tries = 0; tries < 20 && !unit[0]; tries++) {
        DIR *d = opendir("/sys/class/iommu");
        if (d) {
            struct dirent *e;
            while ((e = readdir(d)))
                if (e->d_name[0] != '.' && !unit[0]) snprintf(unit, sizeof unit, "%s", e->d_name);
            closedir(d);
        }
        if (!unit[0]) usleep(100000);
    }
    if (unit[0]) {
        DIR *d = opendir("/sys/class/iommu");
        struct dirent *e;
        while (d && (e = readdir(d)))
            if (e->d_name[0] != '.') show_unit(e->d_name);
        if (d) closedir(d);
    } else {
        sayf("IOMMU-TEST units: none\n");
    }

    char card[64] = "";
    DIR *d = opendir("/sys/bus/pci/drivers/e1000");
    if (d) {
        struct dirent *e;
        while ((e = readdir(d)))
            if (e->d_name[0] == '0') snprintf(card, sizeof card, "%s", e->d_name);
        closedir(d);
    }
    if (!card[0]) {
        sayf("IOMMU-TEST e1000: not bound\n");
        d = opendir("/sys/bus/pci/devices");
        struct dirent *e;
        while (d && (e = readdir(d))) {
            char path[256], label[96];
            if (e->d_name[0] == '.') continue;
            snprintf(path, sizeof path, "/sys/bus/pci/devices/%s/dma", e->d_name);
            snprintf(label, sizeof label, "%s dma", e->d_name);
            show(label, path);
        }
        if (d) closedir(d);
        network("without a bound card");
        sayf("IOMMU-TEST DONE\n");
        sync();
        reboot(RB_POWER_OFF);
        for (;;) pause();
    }

    char dma[128], state[128], line[80], pages[128];
    snprintf(dma, sizeof dma, "/sys/bus/pci/devices/%s/dma", card);
    snprintf(state, sizeof state, "/sys/bus/pci/devices/%s/state", card);
    snprintf(line, sizeof line, "%s\n", card);
    snprintf(pages, sizeof pages, "/sys/class/iommu/%s/pages", unit);
    sayf("IOMMU-TEST e1000: %s\n", card);
    show("e1000 dma", dma);
    int before_ok = network("at boot");

    // Unbind and bind. The first round is not counted: it is the one that
    // finds whatever is only ever allocated once.
    write_file("/sys/bus/pci/drivers/e1000/unbind", line);
    show("e1000 dma unbound", dma);
    write_file("/sys/bus/pci/drivers/e1000/bind", line);
    long long tables_before = unit[0] ? number_after(pages, "tables") : -1;
    long long free_before = number_after("/proc/meminfo", "MemFree");
    int failed = 0;
    for (int i = 0; i < 20; i++) {
        if (write_file("/sys/bus/pci/drivers/e1000/unbind", line) < 0) failed++;
        if (write_file("/sys/bus/pci/drivers/e1000/bind", line) < 0) failed++;
    }
    long long tables_after = unit[0] ? number_after(pages, "tables") : -1;
    long long free_after = number_after("/proc/meminfo", "MemFree");
    sayf("IOMMU-TEST rebind x20: failures=%d tables %lld -> %lld, MemFree %lld -> %lld kB (%+lld)\n",
         failed, tables_before, tables_after, free_before, free_after, free_after - free_before);
    show("e1000 state", state);
    show("e1000 dma", dma);
    int after_ok = network("after rebinding");
    if (unit[0]) show_unit(unit);
    sayf("IOMMU-TEST summary: unit=%s network_before=%d network_after=%d rebind_failures=%d table_growth=%lld\n",
         unit[0] ? unit : "none", before_ok, after_ok, failed, tables_after - tables_before);
    sayf("IOMMU-TEST DONE\n");
    sync();
    reboot(RB_POWER_OFF);
    for (;;) pause();
}
