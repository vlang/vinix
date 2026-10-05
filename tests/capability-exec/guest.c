#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct cap_header { uint32_t version; int32_t pid; };
struct cap_data { uint32_t effective, permitted, inheritable; };
struct caps { uint64_t effective, permitted, inheritable; };
static int failures;
static const uint64_t subset = UINT64_C(1) | (UINT64_C(1) << 34);
static const uint64_t kill_bit = UINT64_C(1) << 5;
static void check(int valid, const char *name) {
    printf("CAP EXEC %s: %s errno=%d\n", valid ? "PASS" : "FAIL", name, errno);
    failures += !valid;
}
static int read_caps(struct caps *result) {
    struct cap_header header = {0x20080522, 0};
    struct cap_data data[2] = {{0}};
    if (syscall(SYS_capget, &header, data)) return -1;
    result->effective = data[0].effective | ((uint64_t)data[1].effective << 32);
    result->permitted = data[0].permitted | ((uint64_t)data[1].permitted << 32);
    result->inheritable = data[0].inheritable | ((uint64_t)data[1].inheritable << 32);
    return 0;
}
static int write_caps(uint64_t effective, uint64_t permitted, uint64_t inheritable) {
    struct cap_header header = {0x20080522, 0};
    struct cap_data data[2] = {
        {(uint32_t)effective, (uint32_t)permitted, (uint32_t)inheritable},
        {(uint32_t)(effective >> 32), (uint32_t)(permitted >> 32), (uint32_t)(inheritable >> 32)}
    };
    return syscall(SYS_capset, &header, data);
}
static int probe(int argc, char **argv) {
    if (argc != 7) return 20;
    struct caps got;
    uint64_t expected = strtoull(argv[2], NULL, 16);
    int nnp = atoi(argv[3]), mixed = atoi(argv[4]);
    uint64_t inheritable = strtoull(argv[5], NULL, 16);
    int again = atoi(argv[6]);
    if (read_caps(&got) || got.permitted != expected ||
        got.effective != (mixed ? 0 : expected) || got.inheritable != inheritable)
        return 21;
    if (prctl(PR_GET_NO_NEW_PRIVS, 0L, 0L, 0L, 0L) != nnp ||
        getuid() != 0 || geteuid() != (mixed ? 1000 : 0)) return 22;
    if (getauxval(AT_SECURE) != (unsigned long)mixed ||
        prctl(PR_GET_DUMPABLE, 0L, 0L, 0L, 0L) != !mixed) return 23;
    if (nnp) {
        errno = 0;
        if (prctl(PR_SET_NO_NEW_PRIVS, 0L, 0L, 0L, 0L) != -1 || errno != EINVAL) return 24;
        pid_t child = fork();
        if (!child) _exit(prctl(PR_GET_NO_NEW_PRIVS, 0L, 0L, 0L, 0L) == 1 ? 0 : 1);
        int status;
        if (child <= 0 || waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status)) return 25;
    }
    if (again) {
        argv[6] = "0";
        execv(argv[0], argv);
        return 26;
    }
    return 0;
}
static int launch(const char *path, int nnp, int mixed, uint64_t retained,
                  uint64_t expected, uint64_t inheritable) {
    pid_t child = fork();
    if (!child) {
        if (mixed && setresuid(0, 1000, 0)) _exit(30);
        if (nnp && prctl(PR_SET_NO_NEW_PRIVS, 1L, 0L, 0L, 0L)) _exit(31);
        if (write_caps(mixed ? 0 : retained & 1, retained, inheritable)) _exit(32);
        struct caps before;
        if (read_caps(&before) || before.permitted != retained) _exit(33);
        char cap_text[32], inherit_text[32];
        snprintf(cap_text, sizeof cap_text, "%llx", (unsigned long long)expected);
        snprintf(inherit_text, sizeof inherit_text, "%llx", (unsigned long long)inheritable);
        char *args[] = {(char *)path, "--probe", cap_text, nnp ? "1" : "0",
                        mixed ? "1" : "0", inherit_text, "1", NULL};
        execv(path, args);
        _exit(34);
    }
    int status = -1;
    if (child <= 0 || waitpid(child, &status, 0) != child) return 0;
    if (!WIFEXITED(status) || WEXITSTATUS(status))
        printf("CAP EXEC child status=%d\n", status);
    return WIFEXITED(status) && !WEXITSTATUS(status);
}
static int ambient_probe(void) {
    struct caps got;
    return read_caps(&got) == 0 && got.permitted == kill_bit && got.effective == kill_bit &&
        got.inheritable == kill_bit && getuid() == 1000 && geteuid() == 1000 &&
        prctl(PR_GET_NO_NEW_PRIVS, 0L, 0L, 0L, 0L) == 1 &&
        prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_IS_SET, 5L, 0L, 0L) == 1 &&
        prctl(PR_GET_KEEPCAPS, 0L, 0L, 0L, 0L) == 0 && getauxval(AT_SECURE) == 0 ? 0 : 40;
}
static int ambient_case(const char *path, int drop_inheritable, int execute) {
    pid_t child = fork();
    if (!child) {
        if (execute && (prctl(PR_SET_KEEPCAPS, 1L, 0L, 0L, 0L) ||
                        setresuid(1000, 1000, 1000))) _exit(41);
        if (write_caps(kill_bit, kill_bit, kill_bit)) _exit(42);
        // IS_SET is an observation: it must not raise or lower a bit.
        if (prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_IS_SET, 5L, 0L, 0L) != 0 ||
            prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE, 5L, 0L, 0L) ||
            prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_IS_SET, 5L, 0L, 0L) != 1 ||
            prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_IS_SET, 5L, 0L, 0L) != 1 ||
            prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_LOWER, 5L, 0L, 0L) ||
            prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_IS_SET, 5L, 0L, 0L) != 0 ||
            prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE, 5L, 0L, 0L)) _exit(43);
        if (execute) {
            if (prctl(PR_SET_NO_NEW_PRIVS, 1L, 0L, 0L, 0L)) _exit(44);
            char *args[] = {(char *)path, "--ambient-probe", NULL};
            execv(path, args); _exit(45);
        }
        if (write_caps(drop_inheritable ? kill_bit : 0, drop_inheritable ? kill_bit : 0,
                       drop_inheritable ? 0 : kill_bit)) _exit(46);
        if (prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_IS_SET, 5L, 0L, 0L) != 0) _exit(47);
        errno = 0;
        if (prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE, 5L, 0L, 0L) != -1 || errno != EPERM) _exit(48);
        _exit(0);
    }
    int status = -1;
    if (child <= 0 || waitpid(child, &status, 0) != child) return 0;
    if (!WIFEXITED(status) || WEXITSTATUS(status)) printf("CAP EXEC ambient child status=%d\n", status);
    return WIFEXITED(status) && !WEXITSTATUS(status);
}
int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "--probe")) return probe(argc, argv);
    if (argc == 2 && !strcmp(argv[1], "--ambient-probe")) return ambient_probe();
    int serial = open("/dev/com1", O_WRONLY | O_NOCTTY);
    if (serial >= 0) { dup2(serial, 1); dup2(serial, 2); close(serial); }
    setbuf(stdout, NULL);
    puts("CAP EXEC START");
    struct caps original;
    check(getuid() == 0 && geteuid() == 0 && read_caps(&original) == 0 &&
          (original.permitted & subset) == subset, "privileged test setup");
    if (failures) goto finish;
    check(launch(argv[0], 0, 0, 0, original.permitted, kill_bit),
          "ordinary root exec retains bounding-set behavior");
    check(launch(argv[0], 1, 0, 0, 0, kill_bit),
          "no_new_privs prevents root capability regain across repeated exec");
    check(launch(argv[0], 1, 0, subset, subset, kill_bit),
          "no_new_privs preserves only previously permitted low and high bits");
    check(launch(argv[0], 1, 1, 0, 0, kill_bit),
          "mixed credentials retain capability ceiling and secure-loader state");
    check(ambient_case(argv[0], 0, 0) && ambient_case(argv[0], 1, 0),
          "Linux ambient commands and capset maintain the permitted-inheritable invariant");
    check(ambient_case(argv[0], 0, 1), "valid nonroot ambient privilege survives no_new_privs exec");
finish:
    puts(failures ? "CAP EXEC GUEST: FAIL" : "CAP EXEC GUEST: PASS");
    for (;;) pause();
}
