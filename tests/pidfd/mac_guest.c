/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#define MAC_PRCTL 0x56584d41
#define CHECK(c) do { if (!(c)) { \
 printf("PIDFD MAC FAIL line=%d %s errno=%d\n", __LINE__, #c, errno); return 1; \
} } while (0)
#define DENIED(call) do { errno = 0; CHECK((call) == -1 && errno == EPERM); } while (0)

static long control(unsigned command, unsigned domain, unsigned type, unsigned mask) {
 return prctl(MAC_PRCTL, (unsigned long)command, (unsigned long)domain,
              (unsigned long)type, (unsigned long)mask);
}
static int p_open(pid_t pid) { return syscall(434, pid, 0); }
static int p_signal(int fd, int signal) { return syscall(424, fd, signal, 0, 0); }
static int inherit(int fd) { return fcntl(fd, F_SETFD, 0); }

static int receive(int fd, char wanted) {
 struct pollfd p = {fd, POLLIN, 0};
 int result; do { result = poll(&p, 1, 10000); } while (result < 0 && errno == EINTR);
 CHECK(result == 1 && (p.revents & POLLIN));
 char byte; CHECK(read(fd, &byte, 1) == 1 && byte == wanted);
 return 0;
}
static int reap(pid_t pid) {
 int status; pid_t result;
 do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
 CHECK(result == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0);
 return 0;
}
static int block_usr1(void) {
 sigset_t set; CHECK(sigemptyset(&set) == 0 && sigaddset(&set, SIGUSR1) == 0);
 CHECK(sigprocmask(SIG_BLOCK, &set, NULL) == 0);
 return 0;
}
static int usr1_pending(void) {
 sigset_t pending; CHECK(sigpending(&pending) == 0 && sigismember(&pending, SIGUSR1) == 1);
 return 0;
}

static int target(int acknowledgements, int commands) {
 CHECK(control(0, 0, 0, 0) == 1 && geteuid() == 0);
 CHECK(block_usr1() == 0 && write(acknowledgements, "R", 1) == 1);
 CHECK(receive(commands, 'C') == 0 && usr1_pending() == 0);
 CHECK(write(acknowledgements, "A", 1) == 1);
 close(acknowledgements); close(commands);
 return 0;
}

static int worker(int parent_fd, int target_fd, pid_t parent, pid_t parent_session,
                  int commands, int acknowledgements) {
 CHECK(control(0, 0, 0, 0) == 1 && geteuid() == 0);
 // Version 3 capget has two fixed-width words. Confined root retains CAP_KILL;
 // MAC must run before that capability, matching UID and same-session CONT.
 struct { uint32_t version; int32_t pid; } header = {0x20080522, 0};
 struct { uint32_t effective, permitted, inheritable; } capabilities[2] = {{0}};
 CHECK(syscall(SYS_capget, &header, capabilities) == 0);
 CHECK(capabilities[0].effective & (1U << 5));
 CHECK(getsid(0) == parent_session);
 DENIED(kill(parent, 0));
 DENIED(p_signal(parent_fd, 0));
 DENIED(p_signal(parent_fd, SIGCONT));
 DENIED(p_signal(parent_fd, SIGKILL));
 puts("PIDFD MAC inherited trusted-parent denial PASS");

 CHECK(block_usr1() == 0);
 int self = p_open(getpid()); CHECK(self >= 0);
 CHECK(p_signal(self, 0) == 0 && p_signal(self, SIGUSR1) == 0 && usr1_pending() == 0);
 close(self);

 // This description was created while the target was trusted. Authorization
 // must consult the target's current Process domain, not cache the open domain.
 DENIED(p_signal(target_fd, 0));
 DENIED(p_signal(target_fd, SIGCONT));
 DENIED(p_signal(target_fd, SIGKILL));
 CHECK(write(commands, "X", 1) == 1 && receive(acknowledgements, 'R') == 0);
 CHECK(p_signal(target_fd, 0) == 0 && p_signal(target_fd, SIGUSR1) == 0);
 CHECK(write(commands, "C", 1) == 1 && receive(acknowledgements, 'A') == 0);
 struct pollfd p = {target_fd, POLLIN, 0};
 CHECK(poll(&p, 1, 10000) == 1 && (p.revents & POLLIN));
 // The trusted parent waits for this worker before reaping the target.
 CHECK(p_signal(target_fd, 0) == 0 && p_signal(target_fd, SIGUSR1) == 0);
 DENIED(p_signal(parent_fd, 0));
 puts("PIDFD MAC same-domain delivery and target exec transition PASS");
 close(parent_fd); close(target_fd); close(commands); close(acknowledgements);
 return 0;
}

int main(int argc, char **argv) {
 setvbuf(stdout, NULL, _IONBF, 0);
 if (argc == 4 && !strcmp(argv[1], "target")) _exit(target(atoi(argv[2]), atoi(argv[3])));
 if (argc == 8 && !strcmp(argv[1], "worker"))
  _exit(worker(atoi(argv[2]), atoi(argv[3]), (pid_t)atoi(argv[4]), (pid_t)atoi(argv[5]),
               atoi(argv[6]), atoi(argv[7])));
 CHECK(control(0, 0, 0, 0) == 0 && geteuid() == 0);
 // Unlabelled executable/path traversal, pipe coordination and console output.
 CHECK(control(1, 1, 0, 1U | 2U | 8U | 256U) == 0);
 CHECK(control(1, 1, 29, 2U | 4U) == 0);
 CHECK(control(1, 1, 30, 4U) == 0);
 CHECK(control(2, 0, 0, 0) == 0);
 int parent_fd = p_open(getpid()); CHECK(parent_fd >= 0 && inherit(parent_fd) == 0);
 int commands[2], acknowledgements[2];
 CHECK(pipe(commands) == 0 && pipe(acknowledgements) == 0);
 pid_t peer = fork(); CHECK(peer >= 0);
 if (!peer) {
  close(commands[1]); close(acknowledgements[0]);
  if (receive(commands[0], 'X') || control(3, 1, 0, 0)) _exit(2);
  char a[32], b[32]; snprintf(a, sizeof(a), "%d", acknowledgements[1]);
  snprintf(b, sizeof(b), "%d", commands[0]);
  char *args[] = {"/sbin/init", "target", a, b, NULL}; execv(args[0], args); _exit(3);
 }
 int target_fd = p_open(peer); CHECK(target_fd >= 0 && inherit(target_fd) == 0);
 pid_t child = fork(); CHECK(child >= 0);
 if (!child) {
  close(commands[0]); close(acknowledgements[1]);
  char a[32], b[32], c[32], d[32], e[32], f[32];
  snprintf(a, sizeof(a), "%d", parent_fd); snprintf(b, sizeof(b), "%d", target_fd);
  snprintf(c, sizeof(c), "%d", (int)getppid()); snprintf(d, sizeof(d), "%d", (int)getsid(0));
  snprintf(e, sizeof(e), "%d", commands[1]); snprintf(f, sizeof(f), "%d", acknowledgements[0]);
  char *args[] = {"/sbin/init", "worker", a, b, c, d, e, f, NULL};
  if (control(3, 1, 0, 0)) _exit(4);
  execv(args[0], args); _exit(5);
 }
 close(commands[0]); close(commands[1]); close(acknowledgements[0]); close(acknowledgements[1]);
 CHECK(reap(child) == 0 && reap(peer) == 0);
 CHECK(control(0, 0, 0, 0) == 0 && p_signal(parent_fd, 0) == 0);
 close(parent_fd); close(target_fd);
 puts("PIDFD MAC PASS");
 for (;;) pause();
}
