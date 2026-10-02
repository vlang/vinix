/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <stdint.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { \
    printf("MOUNT POLICY FAIL line %d: %s (errno=%d)\n", __LINE__, #x, errno); \
    return 1; } } while (0)

static char *const probe_argv[] = { "probe", "--probe", NULL };
static char *const empty_env[] = { NULL };
static char *const wx_env[] = { "VINIX_ALLOW_WX=1", NULL };
static int copy_file(const char *from, const char *to);

static int wx_probe(int allowed)
{
    void *mapping = mmap(NULL, 16384, PROT_READ | PROT_WRITE | PROT_EXEC,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (allowed) {
        if (mapping == MAP_FAILED || munmap(mapping, 16384)) return 1;
    } else if (mapping != MAP_FAILED || errno != ENOTSUP) return 1;
    mapping = mmap(NULL, 16384, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mapping == MAP_FAILED) return 1;
    int result = mprotect(mapping, 16384, PROT_READ | PROT_WRITE | PROT_EXEC);
    int valid = allowed ? result == 0 : result == -1 && errno == ENOTSUP;
    if (munmap(mapping, 16384)) return 1;
    return valid ? 0 : 1;
}

static int status_of(pid_t pid)
{
    int status;
    pid_t result;
    do result = waitpid(pid, &status, 0); while (result == -1 && errno == EINTR);
    return result == pid && WIFEXITED(status) ? WEXITSTATUS(status) : 255;
}

static int exec_result(const char *path, int directory, int descriptor, const char *cwd)
{
    pid_t pid = fork();
    if (pid < 0) return 255;
    if (!pid) {
        if (cwd && chdir(cwd)) _exit(254);
        if (descriptor >= 0)
            syscall(SYS_execveat, descriptor, "", probe_argv, empty_env, AT_EMPTY_PATH);
        else if (directory != AT_FDCWD)
            syscall(SYS_execveat, directory, path, probe_argv, empty_env, 0);
        else
            execve(path, probe_argv, empty_env);
        _exit(errno);
    }
    return status_of(pid);
}

/* Drop only CAP_SYS_ADMIN while retaining euid zero, or become unprivileged.
 * Authorization is checked against the launcher before credentials at exec. */
static int wx_exec_result(const char *path, int identity, int request)
{
    pid_t pid = fork();
    if (pid < 0) return 255;
    if (!pid) {
        if (identity == 1 && (setgid(65534) || setuid(65534))) _exit(254);
        if (identity == 2) {
            struct { uint32_t version; int pid; } header = { 0x20080522, 0 };
            struct { uint32_t effective, permitted, inheritable; } data[2];
            memset(data, 0, sizeof data);
            data[0].effective = data[0].permitted = UINT32_MAX & ~(1u << 21);
            data[1].effective = data[1].permitted = 0x1ff;
            if (syscall(SYS_capset, &header, data)) _exit(254);
        }
        if (identity == 3 && unshare(CLONE_NEWUSER)) _exit(254);
        char *arguments[] = { "probe", request ? "--wx" : "--no-wx", NULL };
        execve(path, arguments, request ? wx_env : empty_env);
        _exit(errno);
    }
    return status_of(pid);
}

static int mounts_have_wx(const char *path)
{
    FILE *file = fopen(path, "r");
    char line[1024];
    char mount_path[256];
    int found = 0;
    if (!file) return -1;
    while (fgets(line, sizeof line, file)) {
        int parsed = strstr(path, "mountinfo")
            ? sscanf(line, "%*d %*d %*s %*s %255s", mount_path)
            : sscanf(line, "%*s %255s", mount_path);
        if (parsed == 1 && !strcmp(mount_path, "/mp/wx") && strstr(line, "wxallowed")) found = 1;
    }
    fclose(file);
    return found;
}

static int run_wx_tests(void)
{
    CHECK(mkdir("/mp/wx", 0755) == 0 && mkdir("/mp/wx-alias", 0755) == 0);
    CHECK(mount("tmpfs", "/mp/wx", "tmpfs", 0, "size=8m,wxallowed") == 0);
    CHECK(copy_file("/sbin/init", "/mp/wx/probe") == 0);
    CHECK(mounts_have_wx("/proc/self/mounts") == 1);
    CHECK(mounts_have_wx("/proc/self/mountinfo") == 1);
    CHECK(wx_exec_result("/mp/plain/probe", 0, 0) == 0); /* default W^X */
    CHECK(wx_exec_result("/mp/plain/probe", 0, 1) == 0); /* root launcher */
    CHECK(wx_exec_result("/mp/plain/probe", 1, 1) == EPERM);
    CHECK(wx_exec_result("/mp/plain/probe", 2, 1) == EPERM);
    CHECK(wx_exec_result("/mp/plain/probe", 3, 1) == EPERM);
    CHECK(wx_exec_result("/mp/wx/probe", 1, 0) == 0); /* still explicit */
    CHECK(wx_exec_result("/mp/wx/probe", 1, 1) == 0);
    CHECK(mount("/mp/wx", "/mp/wx-alias", NULL, MS_BIND, "") == 0);
    CHECK(wx_exec_result("/mp/wx-alias/probe", 1, 1) == 0);
    int script = open("/mp/plain/wx-script", O_CREAT | O_WRONLY, 0755);
    const char *shebang = "#!/mp/wx/probe\n";
    CHECK(script >= 0 && write(script, shebang, strlen(shebang)) == (ssize_t)strlen(shebang)
        && close(script) == 0);
    CHECK(wx_exec_result("/mp/plain/wx-script", 1, 1) == EPERM);
    pid_t child = fork();
    CHECK(child >= 0);
    if (!child) {
        if (setgid(65534) || setuid(65534)) _exit(1);
        _exit(mount("none", "/mp/wx", NULL, MS_REMOUNT, "wxallowed") == -1
            && errno == EPERM ? 0 : 1);
    }
    CHECK(status_of(child) == 0);
    CHECK(mount("none", "/mp/wx", NULL, MS_REMOUNT, "") == 0);
    CHECK(mounts_have_wx("/proc/self/mounts") == 0);
    CHECK(mounts_have_wx("/proc/self/mountinfo") == 0);
    CHECK(wx_exec_result("/mp/wx/probe", 1, 1) == EPERM);
    CHECK(wx_exec_result("/mp/wx-alias/probe", 1, 1) == 0);
    CHECK(mount("none", "/mp/wx", NULL, MS_REMOUNT, "wxallowed") == 0);
    CHECK(mounts_have_wx("/proc/self/mounts") == 1 && wx_exec_result("/mp/wx/probe", 1, 1) == 0);
    puts("MOUNT POLICY PASS: W^X exceptions require administrator launch or executable mount policy");
    return 0;
}

static int copy_file(const char *from, const char *to)
{
    int input = open(from, O_RDONLY), output = open(to, O_CREAT | O_TRUNC | O_RDWR, 0755);
    char buffer[16384];
    ssize_t count;
    if (input < 0 || output < 0) return -1;
    while ((count = read(input, buffer, sizeof buffer)) > 0)
        if (write(output, buffer, (size_t)count) != count) return -1;
    close(input);
    close(output);
    return count == 0 ? 0 : -1;
}

/* Turn an unused GNU_STACK header in our static test into PT_INTERP. The
 * interpreter is itself this static test, so successful ordinary dynamic
 * loading enters --probe without needing a libc shared object in the image. */
static int set_interpreter(const char *image, const char *interpreter)
{
    int fd = open(image, O_RDWR);
    Elf64_Ehdr eh;
    Elf64_Phdr ph;
    struct stat st;
    if (fd < 0 || pread(fd, &eh, sizeof eh, 0) != sizeof eh || fstat(fd, &st)) return -1;
    for (unsigned i = 0; i < eh.e_phnum; ++i) {
        off_t offset = (off_t)(eh.e_phoff + i * sizeof ph);
        if (pread(fd, &ph, sizeof ph, offset) != sizeof ph) return -1;
        if (ph.p_type != PT_GNU_STACK) continue;
        memset(&ph, 0, sizeof ph);
        ph.p_type = PT_INTERP;
        ph.p_offset = (Elf64_Off)st.st_size;
        ph.p_filesz = strlen(interpreter) + 1;
        if (pwrite(fd, interpreter, ph.p_filesz, st.st_size) != (ssize_t)ph.p_filesz
            || pwrite(fd, &ph, sizeof ph, offset) != sizeof ph) return -1;
        close(fd);
        return 0;
    }
    close(fd);
    return -1;
}

static unsigned long slab_kb(void)
{
    FILE *file = fopen("/proc/meminfo", "r");
    char line[256];
    unsigned long result = 0;
    if (!file) return 0;
    while (fgets(line, sizeof line, file))
        if (sscanf(line, "Slab: %lu kB", &result) == 1) break;
    fclose(file);
    return result;
}

static void allocation_sites(int start)
{
    FILE *file = fopen(start ? "/proc/allocstart" : "/proc/allocsites", "r");
    if (!file) return;
    char line[1024];
    while (fgets(line, sizeof line, file))
        if (!start) printf("PERF-SITE mount-denial %s", line);
    fclose(file);
}

static int run_tests(void)
{
    CHECK(mkdir("/mp", 0755) == 0);
    CHECK(mkdir("/mp/src", 0755) == 0 && mkdir("/mp/alias", 0755) == 0);
    CHECK(mkdir("/mp/devices", 0755) == 0 && mkdir("/mp/plain", 0755) == 0);
    CHECK(mkdir("/mp/inherited", 0755) == 0 && mkdir("/mp/moved", 0755) == 0);
    CHECK(mount("tmpfs", "/mp/src", "tmpfs", 0, "") == 0);
    CHECK(copy_file("/sbin/init", "/mp/src/probe") == 0);
    CHECK(copy_file("/sbin/init", "/mp/plain/probe") == 0);
    CHECK(copy_file("/sbin/init", "/mp/plain/dynamic") == 0);
    CHECK(set_interpreter("/mp/plain/dynamic", "/mp/src/probe") == 0);
    CHECK(exec_result("/mp/plain/dynamic", AT_FDCWD, -1, NULL) == 0);
    CHECK(mount("none", "/mp/src", NULL, MS_REMOUNT | MS_NOEXEC | MS_NODEV, "") == 0);
    CHECK(exec_result("/mp/src/probe", AT_FDCWD, -1, NULL) == EACCES);
    CHECK(exec_result("/mp/plain/dynamic", AT_FDCWD, -1, NULL) == EACCES);
    int script = open("/mp/src/script", O_CREAT | O_WRONLY, 0755);
    CHECK(script >= 0 && write(script, "#!/mp/src/probe\n", 16) == 16 && close(script) == 0);
    CHECK(exec_result("/mp/src/script", AT_FDCWD, -1, NULL) == EACCES);
    CHECK(symlink("/mp/src/probe", "/mp/plain/link") == 0);
    CHECK(exec_result("/mp/plain/link", AT_FDCWD, -1, NULL) == EACCES);
    CHECK(copy_file("/mp/src/script", "/mp/plain/script") == 0);
    CHECK(exec_result("/mp/plain/script", AT_FDCWD, -1, NULL) == EACCES);
    CHECK(mount("/mp/src", "/mp/inherited", NULL, MS_BIND, "") == 0);
    CHECK(exec_result("/mp/inherited/probe", AT_FDCWD, -1, NULL) == EACCES);
    CHECK(mount("/mp/inherited", "/mp/moved", NULL, MS_MOVE, "") == 0);
    CHECK(exec_result("/mp/moved/probe", AT_FDCWD, -1, NULL) == EACCES);

    /* Fail after one argv string has already been copied, and after many
     * strings exceed the aggregate budget. Cleanup owns each clone once. */
    char *bad_argv[] = { "copied first", (char *)1, NULL };
    char *large = malloc(128 * 1024);
    CHECK(large != NULL);
    memset(large, 'a', 128 * 1024 - 1);
    large[128 * 1024 - 1] = 0;
    char *huge_argv[18];
    for (int i = 0; i < 17; ++i) huge_argv[i] = large;
    huge_argv[17] = NULL;
    for (int i = 0; i < 4; ++i) {
        CHECK(execve("/mp/plain/dynamic", bad_argv, empty_env) == -1 && errno == EFAULT);
        CHECK(execve("/mp/plain/dynamic", huge_argv, empty_env) == -1 && errno == E2BIG);
    }
    free(large);

    /* Repeat in this process: these rejected launches never create a child
     * or install their replacement page map. Warm filesystem/loader caches. */
    for (int i = 0; i < 16; ++i) {
        CHECK(execve("/mp/plain/dynamic", probe_argv, empty_env) == -1 && errno == EACCES);
    }
    unsigned long before = slab_kb();
    CHECK(before != 0);
    allocation_sites(1);
    for (int i = 0; i < 200; ++i) {
        CHECK(execve("/mp/plain/dynamic", probe_argv, empty_env) == -1 && errno == EACCES);
    }
    unsigned long after = slab_kb();
    allocation_sites(0);
    printf("MOUNT POLICY SLAB: before=%lu after=%lu KiB\n", before, after);
    CHECK(after <= before + 64);
    puts("MOUNT POLICY PASS: noexec images, scripts, symlinks and ELF interpreters");

    int fd = open("/mp/src/probe", O_RDONLY);
    CHECK(fd >= 0);
    errno = 0;
    CHECK(mmap(NULL, 16384, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0) == MAP_FAILED && errno == EPERM);
    void *mapping = mmap(NULL, 32768, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECK(mapping != MAP_FAILED);
    CHECK(mprotect(mapping, 16384, PROT_READ | PROT_EXEC) == -1 && errno == EACCES);
    CHECK(mprotect(mapping, 16384, PROT_NONE) == 0); /* split the range */
    void *moved = mremap(mapping, 16384, 16384, MREMAP_MAYMOVE);
    CHECK(moved != MAP_FAILED);
    CHECK(mprotect(moved, 16384, PROT_READ | PROT_EXEC) == -1 && errno == EACCES);
    pid_t child = fork();
    CHECK(child >= 0);
    if (!child) _exit(mprotect(moved, 16384, PROT_READ | PROT_EXEC) == -1 && errno == EACCES ? 0 : 1);
    CHECK(status_of(child) == 0);
    CHECK(munmap(moved, 16384) == 0 && munmap((char *)mapping + 16384, 16384) == 0);
    CHECK(close(fd) == 0);
    puts("MOUNT POLICY PASS: noexec mmap and protection ceilings survive split, fork and remap");

    CHECK(mount("none", "/mp/src", NULL, MS_REMOUNT, "") == 0);
    CHECK(exec_result("/mp/moved/probe", AT_FDCWD, -1, NULL) == EACCES);
    CHECK(umount("/mp/moved") == 0);
    CHECK(mount("/mp/src", "/mp/alias", NULL, MS_BIND, "") == 0);
    fd = open("/mp/alias/probe", O_RDONLY);
    int dir = open("/mp/alias", O_RDONLY | O_DIRECTORY);
    CHECK(fd >= 0 && dir >= 0);
    CHECK(mount("none", "/mp/alias", NULL, MS_REMOUNT | MS_BIND | MS_NOEXEC, "") == 0);
    CHECK(exec_result("/mp/alias/probe", AT_FDCWD, -1, NULL) == EACCES);
    CHECK(exec_result("/mp/src/probe", AT_FDCWD, -1, NULL) == 0);
    CHECK(exec_result("probe", AT_FDCWD, -1, "/mp/alias") == EACCES);
    CHECK(exec_result("../src/probe", AT_FDCWD, -1, "/mp/alias") == 0);
    CHECK(exec_result("probe", dir, -1, NULL) == EACCES);
    CHECK(exec_result(NULL, AT_FDCWD, fd, NULL) == EACCES);
    char fdpath[64];
    snprintf(fdpath, sizeof fdpath, "/proc/self/fd/%d", fd);
    CHECK(exec_result(fdpath, AT_FDCWD, -1, NULL) == EACCES);
    CHECK(mmap(NULL, 16384, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0) == MAP_FAILED && errno == EPERM);
    int source = open("/mp/src/probe", O_RDONLY);
    CHECK(source >= 0);
    mapping = mmap(NULL, 16384, PROT_READ | PROT_EXEC, MAP_PRIVATE, source, 0);
    CHECK(mapping != MAP_FAILED && munmap(mapping, 16384) == 0);
    CHECK(close(source) == 0);
    child = fork();
    CHECK(child >= 0);
    if (!child) {
        if (fchdir(dir)) _exit(1);
        execve("probe", probe_argv, empty_env);
        _exit(errno == EACCES ? 0 : 1);
    }
    CHECK(status_of(child) == 0);
    CHECK(close(fd) == 0 && close(dir) == 0);
    puts("MOUNT POLICY PASS: bind aliases retain independent policy through cwd, fds and proc links");

    CHECK(mount("/dev", "/mp/devices", NULL, MS_BIND, "") == 0);
    CHECK(mount("none", "/mp/devices", NULL, MS_REMOUNT | MS_BIND | MS_NODEV, "") == 0);
    CHECK(open("/mp/devices/null", O_RDWR) == -1 && errno == EACCES);
    fd = open("/dev/null", O_RDWR);
    CHECK(fd >= 0 && close(fd) == 0);
    fd = open("/mp/devices/null", O_PATH);
    CHECK(fd >= 0 && close(fd) == 0);
    CHECK(symlink("/mp/devices/null", "/mp/plain/null") == 0);
    CHECK(open("/mp/plain/null", O_RDONLY) == -1 && errno == EACCES);
    CHECK(mount("none", "/mp/src", NULL, MS_REMOUNT | MS_NODEV, "") == 0);
    CHECK(mknod("/mp/src/block", S_IFBLK | 0600, 0) == 0);
    CHECK(open("/mp/src/block", O_RDWR) == -1 && errno == EACCES);
    fd = open("/mp/src/probe", O_RDONLY);
    CHECK(fd >= 0 && close(fd) == 0);
    CHECK(mount("none", "/mp/devices", NULL, MS_REMOUNT | MS_BIND, "") == 0);
    fd = open("/mp/devices/null", O_RDWR);
    CHECK(fd >= 0 && close(fd) == 0);
    puts("MOUNT POLICY PASS: nodev blocks character and block devices, with O_PATH and ordinary files usable");

    /* A forked mount namespace changes its copy of a mount, including the
     * policy seen by descriptors opened before unshare. */
    CHECK(mount("none", "/mp/alias", NULL, MS_REMOUNT | MS_BIND, "") == 0);
    fd = open("/mp/alias/probe", O_RDONLY);
    CHECK(fd >= 0);
    child = fork();
    CHECK(child >= 0);
    if (!child) {
        if (unshare(CLONE_NEWNS) || mount("none", "/mp/alias", NULL,
            MS_REMOUNT | MS_BIND | MS_NOEXEC, "")) _exit(1);
        if (umount2("/mp/alias", MNT_DETACH)) _exit(1);
        void *result = mmap(NULL, 16384, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
        if (result != MAP_FAILED || errno != EPERM) _exit(1);
        syscall(SYS_execveat, fd, "", probe_argv, empty_env, AT_EMPTY_PATH);
        _exit(errno == EACCES ? 0 : 1);
    }
    CHECK(status_of(child) == 0);
    CHECK(exec_result("/mp/alias/probe", AT_FDCWD, -1, NULL) == 0);
    CHECK(close(fd) == 0);
    /* Self binds need no self-referential node.mountpoint. */
    CHECK(mount("/mp/src", "/mp/src", NULL, MS_BIND, "") == 0);
    CHECK(mount("none", "/mp/src", NULL, MS_REMOUNT | MS_BIND | MS_NOEXEC, "") == 0);
    CHECK(exec_result("/mp/src/probe", AT_FDCWD, -1, NULL) == EACCES);
    CHECK(exec_result("/mp/alias/probe", AT_FDCWD, -1, NULL) == 0);
    CHECK(exec_result("../plain/probe", AT_FDCWD, -1, "/mp/src") == 0);
    puts("MOUNT POLICY PASS: namespace remounts and self binds preserve mount identity");
    /* procfs caches its root by PID namespace; mounting that root again
     * must preserve readable paths rather than redirecting it to itself. */
    CHECK(mount("proc", "/proc", "proc", MS_NOEXEC | MS_NODEV, "") == 0);
    fd = open("/proc/self/mountinfo", O_RDONLY);
    char proc_buffer[64];
    CHECK(fd >= 0 && read(fd, proc_buffer, sizeof proc_buffer) > 0 && close(fd) == 0);
    child = fork();
    CHECK(child >= 0);
    if (!child) {
        if (unshare(CLONE_NEWNS) || mount("proc", "/proc", "proc", MS_NOEXEC, "")) _exit(1);
        int nested = open("/proc/self/mounts", O_RDONLY);
        if (nested < 0 || read(nested, proc_buffer, sizeof proc_buffer) <= 0 || close(nested)) _exit(2);
        if (umount2("/proc", MNT_DETACH)) _exit(3);
        nested = open("/proc/self/mounts", O_RDONLY);
        _exit(nested >= 0 && read(nested, proc_buffer, sizeof proc_buffer) > 0 && close(nested) == 0 ? 0 : 4);
    }
    CHECK(status_of(child) == 0);
    puts("MOUNT POLICY PASS: repeated procfs mounts preserve readable namespace paths");
    CHECK(run_wx_tests() == 0);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--probe")) return 0;
    if (argc == 2 && !strcmp(argv[1], "--wx")) return wx_probe(1);
    if (argc == 2 && !strcmp(argv[1], "--no-wx")) return wx_probe(0);
    int console = open("/dev/com1", O_WRONLY);
    if (console < 0) console = open("/dev/console", O_WRONLY);
    if (console >= 0) {
        dup2(console, STDOUT_FILENO);
        dup2(console, STDERR_FILENO);
        close(console);
    }
    setvbuf(stdout, NULL, _IONBF, 0);
    int result = run_tests();
    puts(result ? "VINIX MOUNT POLICY: FAIL" : "VINIX MOUNT POLICY: PASS");
    sync();
    reboot(RB_POWER_OFF);
    for (;;) pause();
}
