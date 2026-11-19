// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

static int failures;

static void check(int ok, const char *message) {
    if (!ok) {
        printf("FAIL: drm sysfs: %s (errno=%d)\n", message, errno);
        fflush(stdout);
        ++failures;
    }
}

static int read_text(const char *path, char *text, size_t size) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    size_t got = fread(text, 1, size - 1, f);
    text[got] = 0;
    fclose(f);
    return (int)got;
}

static int link_is(const char *path, const char *expected) {
    char target[PATH_MAX];
    ssize_t got = readlink(path, target, sizeof(target) - 1);
    if (got < 0) return 0;
    target[got] = 0;
    if (strcmp(target, expected) != 0) printf("%s -> %s\n", path, target);
    return strcmp(target, expected) == 0;
}

// Every /dev/dri node has its class entry, and the devices that have no
// parent are the ones libdrm leaves out, as it left out everything before.
static void minors(void) {
    DIR *dir = opendir("/dev/dri");
    check(dir != NULL, "list /dev/dri");
    if (!dir) return;
    int seen = 0;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.') continue;
        char node[PATH_MAX], path[PATH_MAX], text[512], expected[PATH_MAX];
        snprintf(node, sizeof(node), "/dev/dri/%s", entry->d_name);
        struct stat st;
        if (stat(node, &st) != 0 || !S_ISCHR(st.st_mode)) continue;
        unsigned maj = major(st.st_rdev), min = minor(st.st_rdev);
        seen++;
        check(maj == 226, "DRM nodes use major 226");
        snprintf(path, sizeof(path), "/sys/class/drm/%s", entry->d_name);
        snprintf(expected, sizeof(expected), "../../devices/virtual/drm/%s", entry->d_name);
        check(link_is(path, expected), "the class entry leads to devices/virtual/drm");
        snprintf(path, sizeof(path), "/sys/dev/char/%u:%u", maj, min);
        check(link_is(path, expected), "the dev/char entry leads to the same directory");
        snprintf(path, sizeof(path), "/sys/dev/char/%u:%u/dev", maj, min);
        snprintf(expected, sizeof(expected), "%u:%u\n", maj, min);
        check(read_text(path, text, sizeof(text)) > 0 && strcmp(text, expected) == 0, "dev is major:minor");
        snprintf(path, sizeof(path), "/sys/dev/char/%u:%u/uevent", maj, min);
        snprintf(expected, sizeof(expected), "MAJOR=226\nMINOR=%u\nDEVNAME=dri/%s\nDEVTYPE=drm_minor\n", min,
                 entry->d_name);
        check(read_text(path, text, sizeof(text)) > 0 && strcmp(text, expected) == 0, "uevent names the node");
        snprintf(path, sizeof(path), "/sys/class/drm/%s/subsystem", entry->d_name);
        char *real = realpath(path, NULL);
        check(real && strcmp(real, "/sys/class/drm") == 0, "subsystem is the drm class");
        free(real);
        // libdrm's drmNodeIsDRM(): a device without a parent is not listed.
        snprintf(path, sizeof(path), "/sys/dev/char/%u:%u/device/drm", maj, min);
        check(stat(path, &st) != 0 && errno == ENOENT, "libdrm does not list a virtual device");
        // Linux names a device's debugfs directory after its parent; a
        // device without one gets no dri/<minor> link.
        snprintf(path, sizeof(path), "/sys/kernel/debug/dri/%u", min);
        check(lstat(path, &st) != 0 && errno == ENOENT, "a virtual device has no debugfs entry");
    }
    closedir(dir);
    check(seen > 0, "the guest has a DRM node");
    printf("PASS: %d DRM nodes have class, dev/char, dev and uevent entries; libdrm still lists none\n", seen);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    alarm(60);
    minors();
    if (failures) printf("FAIL: drm sysfs (%d checks)\n", failures);
    else puts("VINIX DRM SYSFS: PASS");
    fflush(stdout);
    sync();
    reboot(RB_POWER_OFF);
    for (;;) pause();
}
