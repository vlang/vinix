// SPDX-License-Identifier: GPL-2.0-or-later
// Run tools/gpucheck in QEMU, against Omarchy's Mesa root on a read-only disk
// and a machine with no Apple GPU, and check that its report says exactly
// what is missing: every step must run, and every absence must be reported.
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static int problems;

static void check(int ok, const char *what) {
    printf("GPUCHECK %s: %s\n", ok ? "ok" : "BAD", what);
    fflush(stdout);
    if (!ok) problems++;
}

static int mount_root(const char *at) {
    mkdir("/mnt", 0755);
    mkdir(at, 0755);
    for (char letter = 'a'; letter <= 'h'; letter++) {
        char device[16];
        snprintf(device, sizeof(device), "/dev/vd%c", letter);
        if (access(device, F_OK) != 0) continue;
        if (mount(device, at, "ext2", MS_RDONLY, "") != 0) continue;
        char probe[256];
        snprintf(probe, sizeof(probe), "%s/usr/bin/vulkaninfo", at);
        if (access(probe, F_OK) == 0) return 1;
        umount(at);
    }
    return 0;
}

static char report[1 << 20];

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    const char *root = "/mnt/omarchy-mesa";
    if (!mount_root(root)) {
        printf("FAIL: no disk carries the staged root\n");
        return 1;
    }
    pid_t pid = fork();
    if (pid == 0) {
        char *argv[] = { "/sbin/gpucheck", "--root", (char *)root, "--out", "/root/gpucheck.md", NULL };
        char *envp[] = { "PATH=/sbin:/usr/bin", NULL };
        execve(argv[0], argv, envp);
        _exit(127);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    printf("GPUCHECK exit %d\n", WIFEXITED(status) ? WEXITSTATUS(status) : -1);

    FILE *file = fopen("/root/gpucheck.md", "r");
    size_t length = file ? fread(report, 1, sizeof(report) - 1, file) : 0;
    if (file) fclose(file);
    report[length] = 0;

    check(WIFEXITED(status) && WEXITSTATUS(status) == 1, "gpucheck exits 1: there are problems");
    check(strncmp(report, "# M1 GPU check\n", 15) == 0, "the report is written to /root");
    check(strstr(report, "problem:** the boot log has no agx lines") != NULL ||
              strstr(report, "problem:** the GPU driver did not finish initializing") != NULL,
          "the missing GPU driver is reported");
    check(strstr(report, "problem:** there is no render node of the asahi driver") != NULL,
          "the missing render node is reported");
    check(strstr(report, "run-m1-agx-smoke is not installed") != NULL,
          "the missing smoke test is noted");
    check(strstr(report, "5 of 5 mounts made") != NULL, "the chroot gets all five mounts");
    check(strstr(report, "problem:** Honeykrisp found no Apple M1 GPU") != NULL,
          "vulkaninfo runs and finds no Apple GPU");
    check(strstr(report, "problem:** EGL rendered with llvmpipe") != NULL,
          "eglinfo runs, on llvmpipe, and that is reported");
    check(strstr(report, "frames in") != NULL, "peglgears runs in the chroot");
    check(strstr(report, "problem:** peglgears held no memory on the asahi device") != NULL,
          "its fdinfo is sampled and shows no asahi memory");
    check(strstr(report, "problem(s) found.\n") != NULL, "the report ends with its count");
    char probe[256];
    snprintf(probe, sizeof(probe), "%s/proc/self", root);
    check(access(probe, F_OK) != 0, "gpucheck unmounts what it mounted");

    if (problems == 0)
        printf("GPUCHECK QEMU PASS\n");
    else
        printf("GPUCHECK QEMU INCOMPLETE problems=%d\n", problems);
    fflush(stdout);
    for (;;) pause();
}
