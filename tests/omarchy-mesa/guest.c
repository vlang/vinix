// SPDX-License-Identifier: GPL-2.0-or-later
// Run Omarchy's packaged Mesa, unmodified, from the glibc root that stage.v
// built and run.v attached as a read-only disk. QEMU has no Apple GPU, so this
// shows how far each client gets on Vinix: whether every library resolves and
// loads, whether the Vulkan loader takes the Honeykrisp driver, and whether the
// software renderer that the package also carries draws frames.
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int problems;

static void note(int ok, const char *what) {
    printf("OMARCHY-MESA %s: %s\n", ok ? "ok" : "BAD", what);
    fflush(stdout);
    if (!ok) problems++;
}

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

struct result {
    int status;     // wait status, or -1 if it could not run
    int timed_out;
    char output[262144];
    size_t length;
};

static struct result result;

static char *const environment[] = {
    "PATH=/usr/bin:/usr/sbin",
    "HOME=/tmp",
    "XDG_RUNTIME_DIR=/run",
    "LANG=C",
    NULL,
};

// Run argv with extra environment entries, echo its output and keep a copy.
static struct result *run(const char *title, char *const argv[], char *const extra[], int seconds) {
    char *env[32];
    int count = 0;
    for (int i = 0; environment[i]; i++) env[count++] = environment[i];
    for (int i = 0; extra && extra[i] && count < 31; i++) env[count++] = extra[i];
    env[count] = NULL;

    printf("OMARCHY-MESA run %s\n", title);
    fflush(stdout);
    memset(&result, 0, sizeof(result));
    result.status = -1;
    int pipefd[2];
    if (pipe(pipefd) != 0) return &result;
    pid_t pid = fork();
    if (pid < 0) return &result;
    if (pid == 0) {
        dup2(pipefd[1], 1);
        dup2(pipefd[1], 2);
        close(pipefd[0]);
        close(pipefd[1]);
        execve(argv[0], argv, env);
        dprintf(2, "execve %s: %s\n", argv[0], strerror(errno));
        _exit(127);
    }
    close(pipefd[1]);
    long long deadline = now_ms() + seconds * 1000LL;
    for (;;) {
        long long left = deadline - now_ms();
        if (left <= 0) {
            result.timed_out = 1;
            kill(pid, SIGKILL);
            break;
        }
        struct pollfd p = { .fd = pipefd[0], .events = POLLIN };
        int ready = poll(&p, 1, left > 1000 ? 1000 : (int)left);
        if (ready < 0 && errno != EINTR) break;
        if (ready <= 0) continue;
        char chunk[4096];
        ssize_t n = read(pipefd[0], chunk, sizeof(chunk));
        if (n <= 0) break;
        fwrite(chunk, 1, (size_t)n, stdout);
        size_t room = sizeof(result.output) - 1 - result.length;
        size_t keep = (size_t)n < room ? (size_t)n : room;
        memcpy(result.output + result.length, chunk, keep);
        result.length += keep;
    }
    close(pipefd[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    result.status = status;
    result.output[result.length] = 0;
    fflush(stdout);
    if (result.timed_out)
        printf("OMARCHY-MESA %s: killed after %d s\n", title, seconds);
    else if (WIFSIGNALED(status))
        printf("OMARCHY-MESA %s: signal %d\n", title, WTERMSIG(status));
    else
        printf("OMARCHY-MESA %s: exit %d\n", title, WEXITSTATUS(status));
    fflush(stdout);
    return &result;
}

static int has(const struct result *r, const char *text) {
    return strstr(r->output, text) != NULL;
}

static int exited(const struct result *r) {
    return r->status >= 0 && !r->timed_out && WIFEXITED(r->status);
}

static int mount_root(void) {
    mkdir("/mnt", 0755);
    for (char letter = 'a'; letter <= 'h'; letter++) {
        char device[16];
        snprintf(device, sizeof(device), "/dev/vd%c", letter);
        if (access(device, F_OK) != 0) continue;
        if (mount(device, "/mnt", "ext2", MS_RDONLY, "") != 0) continue;
        if (access("/mnt/usr/lib/libEGL_mesa.so.0", F_OK) == 0) {
            printf("OMARCHY-MESA root on %s\n", device);
            return 1;
        }
        umount("/mnt");
    }
    return 0;
}

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    printf("OMARCHY-MESA start\n");
    if (!mount_root()) {
        printf("FAIL: no disk carries the staged root\n");
        return 1;
    }
    note(mount("proc", "/mnt/proc", "proc", 0, "") == 0, "mount /proc in the root");
    note(mount("sysfs", "/mnt/sys", "sysfs", 0, "") == 0, "mount /sys in the root");
    note(mount("/dev", "/mnt/dev", NULL, MS_BIND, "") == 0, "bind /dev into the root");
    note(mount("tmpfs", "/mnt/tmp", "tmpfs", 0, "") == 0, "mount /tmp in the root");
    note(mount("tmpfs", "/mnt/run", "tmpfs", 0, "") == 0, "mount /run in the root");
    if (chroot("/mnt") != 0 || chdir("/") != 0) {
        printf("FAIL: chroot into the staged root: %s\n", strerror(errno));
        return 1;
    }

    static const char *libraries[] = {
        "/usr/lib/libgallium-26.3.0-devel.so",
        "/usr/lib/libvulkan_asahi.so",
        "/usr/lib/libEGL_mesa.so.0",
        "/usr/bin/vulkaninfo",
        "/usr/bin/eglinfo",
        "/usr/bin/peglgears",
    };
    for (size_t i = 0; i < sizeof(libraries) / sizeof(libraries[0]); i++) {
        char *argv[] = { "/usr/lib/ld-linux-aarch64.so.1", "--list", (char *)libraries[i], NULL };
        struct result *r = run(libraries[i], argv, NULL, 60);
        char what[160];
        snprintf(what, sizeof(what), "every library of %s resolves", libraries[i]);
        note(exited(r) && WEXITSTATUS(r->status) == 0 && !has(r, "not found"), what);
    }

    {
        char *argv[] = { "/usr/bin/vulkaninfo", "--summary", NULL };
        char *extra[] = { "VK_LOADER_DEBUG=error,driver", NULL };
        struct result *r = run("vulkaninfo", argv, extra, 120);
        note(exited(r), "vulkaninfo exits without a signal");
        // The loader prints nothing when a driver loads, but vkCreateInstance
        // fails when none does, and vulkaninfo enumerates devices only after
        // it succeeds.
        note(has(r, "Searching for ICD drivers named /usr/lib/libvulkan_asahi.so")
                 && !has(r, "Failed loading library") && !has(r, "Found no drivers")
                 && has(r, "vkEnumeratePhysicalDevices"),
             "the loader loads Honeykrisp and creates an instance");
        // QEMU has no Apple GPU; the loader says so once Honeykrisp lists none.
        note(has(r, "Failed to detect any valid GPUs"), "Honeykrisp finds no GPU in QEMU");
    }
    {
        // With no render node, Mesa's surfaceless and device platforms fall
        // back to llvmpipe, which JIT-compiles every shader with LLVM.
        char *argv[] = { "/usr/bin/eglinfo", "-B", NULL };
        struct result *r = run("eglinfo", argv, NULL, 120);
        note(exited(r), "eglinfo exits without a signal");
        note(has(r, "OpenGL core profile renderer: llvmpipe (LLVM 23.")
                 && has(r, "OpenGL ES profile renderer: llvmpipe (LLVM 23."),
             "llvmpipe with LLVM 23 creates GL and GLES contexts");
        note(has(r, "4.6 (Core Profile) Mesa 26.3.0-devel (git-b7b03c5b3b)"),
             "the contexts come from Omarchy's pinned Mesa");
        // libdrm lists only devices with a parent; QEMU's framebuffer has none.
        note(has(r, "Device #0:") && !has(r, "Device #1:"),
             "the device platform has only the software device");
    }
    {
        char *argv[] = { "/usr/bin/peglgears", NULL };
        char *extra[] = { "EGL_PLATFORM=surfaceless", NULL };
        struct result *r = run("peglgears", argv, extra, 20);
        note(has(r, "frames in"), "peglgears draws frames");
    }

    if (problems == 0)
        printf("OMARCHY-MESA PASS\n");
    else
        printf("OMARCHY-MESA INCOMPLETE problems=%d\n", problems);
    fflush(stdout);
    for (;;) pause();
}
