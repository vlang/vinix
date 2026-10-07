#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <poll.h>
#include <time.h>
#include <termios.h>
#include <unistd.h>

static int failures;
static volatile sig_atomic_t caught_signal;
static volatile int *transition_state;
static int restart_terminal, restart_gate;
static void acquire_foreground(int number) {
    caught_signal = number;
    sigset_t mask; sigemptyset(&mask); sigaddset(&mask, SIGTTOU);
    sigprocmask(SIG_BLOCK, &mask, NULL);
    if (tcsetpgrp(restart_terminal, getpgrp()) || write(restart_gate, "r", 1) != 1) _exit(80);
}
static void caught(int signal) { caught_signal = signal; }
static void transition_signal(int number) {
    if (number == SIGHUP) ++transition_state[0];
    if (number == SIGCONT) ++transition_state[1];
}
static void check(int ok, const char *name) {
    printf("TERMINAL JOBS %s: %s (errno=%d)\n", ok ? "PASS" : "FAIL", name, errno);
    failures += !ok;
}
static int wait_status(pid_t child, int flags) {
    int status; pid_t value;
    do value = waitpid(child, &status, flags); while (value == -1 && errno == EINTR);
    return value == child ? status : -1;
}
static int exited_ok(pid_t child) {
    int status = wait_status(child, 0);
    return status >= 0 && WIFEXITED(status) && !WEXITSTATUS(status);
}
static void block(int number, int how) {
    sigset_t set; sigemptyset(&set); sigaddset(&set, number); sigprocmask(how, &set, NULL);
}
static void handler(int number) {
    struct sigaction action; memset(&action, 0, sizeof(action));
    action.sa_handler = caught; sigemptyset(&action.sa_mask); sigaction(number, &action, NULL);
}
static pid_t background(void) {
    pid_t child = fork();
    if (!child && setpgid(0, 0)) _exit(90);
    return child;
}
static void foreground(int slave, pid_t group) {
    block(SIGTTOU, SIG_BLOCK);
    check(tcsetpgrp(slave, group) == 0, "set foreground process group");
    block(SIGTTOU, SIG_UNBLOCK);
}
static long slab_kb(void) {
    char data[8192]; int fd = open("/proc/meminfo", O_RDONLY);
    if (fd < 0) return -1;
    ssize_t length = read(fd, data, sizeof(data) - 1); close(fd);
    if (length <= 0) return -1;
    data[length] = 0; char *line = strstr(data, "Slab:");
    return line ? strtol(line + 5, NULL, 10) : -1;
}
static void allocation_tracking(void) {
    int fd = open("/proc/allocstart", O_RDONLY); char byte;
    if (fd >= 0) { (void)read(fd, &byte, 1); close(fd); }
}
static void allocation_sites(void) {
    char data[65536]; int fd = open("/proc/allocsites", O_RDONLY);
    if (fd < 0) return;
    ssize_t amount = read(fd, data, sizeof(data) - 1); close(fd);
    if (amount > 0) { data[amount] = 0; printf("TERMINAL ALLOCATION SITES\n%s\n", data); }
}
static void settle_grace(void) {
    struct timespec start, now, interval = { .tv_nsec = 100000000 };
    clock_gettime(CLOCK_MONOTONIC, &start);
    do {
        /* Terminal HUP/CONT may interrupt a sleep; measure actual elapsed time. */
        nanosleep(&interval, NULL);
        clock_gettime(CLOCK_MONOTONIC, &now);
    } while (now.tv_sec - start.tv_sec < 6
             || (now.tv_sec - start.tv_sec == 6 && now.tv_nsec < start.tv_nsec));
}
static void permission_cases(int master, int slave) {
    pid_t child = background();
    if (!child) {
        char byte; block(SIGTTIN, SIG_BLOCK);
        errno = 0; _exit(read(slave, &byte, 1) == -1 && errno == EIO ? 0 : 1);
    }
    check(child > 0 && exited_ok(child), "blocked background read fails EIO");
    child = background();
    if (!child) {
        char byte; signal(SIGTTIN, SIG_IGN);
        errno = 0; _exit(read(slave, &byte, 1) == -1 && errno == EIO ? 0 : 1);
    }
    check(child > 0 && exited_ok(child), "ignored background read fails EIO");
    child = background();
    if (!child) {
        char byte; handler(SIGTTIN);
        errno = 0; _exit(read(slave, &byte, 1) == -1 && errno == EINTR && caught_signal == SIGTTIN ? 0 : 1);
    }
    check(child > 0 && exited_ok(child), "caught background read receives SIGTTIN and EINTR");
    child = background();
    if (!child) _exit(write(slave, "n", 1) == 1 ? 0 : 1);
    check(child > 0 && exited_ok(child), "background output allowed without TOSTOP");

    struct termios settings; check(tcgetattr(slave, &settings) == 0, "read terminal settings");
    settings.c_lflag |= TOSTOP;
    check(tcsetattr(slave, TCSANOW, &settings) == 0, "enable TOSTOP");
    child = background();
    if (!child) {
        handler(SIGTTOU); errno = 0;
        _exit(write(slave, "x", 1) == -1 && errno == EINTR && caught_signal == SIGTTOU ? 0 : 1);
    }
    check(child > 0 && exited_ok(child), "TOSTOP catches background output before writing");
    child = background();
    if (!child) { block(SIGTTOU, SIG_BLOCK); _exit(write(slave, "b", 1) == 1 ? 0 : 1); }
    check(child > 0 && exited_ok(child), "blocked SIGTTOU permits background output");
    child = background();
    if (!child) { signal(SIGTTOU, SIG_IGN); _exit(write(slave, "i", 1) == 1 ? 0 : 1); }
    check(child > 0 && exited_ok(child), "ignored SIGTTOU permits background output");
    settings.c_lflag &= ~TOSTOP;
    check(tcsetattr(slave, TCSANOW, &settings) == 0, "disable TOSTOP");
    child = background();
    if (!child) {
        handler(SIGTTOU); struct termios changed = settings; changed.c_lflag ^= ECHO;
        errno = 0; _exit(tcsetattr(slave, TCSANOW, &changed) == -1 && errno == EINTR
                          && caught_signal == SIGTTOU ? 0 : 1);
    }
    check(child > 0 && exited_ok(child), "background attribute change signals regardless TOSTOP");
    struct termios observed;
    check(tcgetattr(slave, &observed) == 0 && observed.c_lflag == settings.c_lflag,
          "rejected attribute change leaves settings intact");
    child = background();
    if (!child) {
        handler(SIGTTOU); errno = 0;
        _exit(tcsetpgrp(slave, getpgrp()) == -1 && errno == EINTR && caught_signal == SIGTTOU ? 0 : 1);
    }
    check(child > 0 && exited_ok(child), "background foreground-group mutation receives SIGTTOU");
    child = background();
    if (!child) {
        block(SIGTTOU, SIG_BLOCK);
        if (tcsetpgrp(slave, getpgrp()) || tcgetpgrp(slave) != getpgrp()) _exit(1);
        _exit(tcsetpgrp(slave, getppid()) ? 2 : 0);
    }
    check(child > 0 && exited_ok(child), "blocked SIGTTOU permits group mutation");

    child = background();
    if (!child) {
        char byte; block(SIGTTIN, SIG_BLOCK);
        for (int i = 0; i < 10; ++i) (void)read(slave, &byte, 1);
        long before = slab_kb();
        allocation_tracking();
        for (int i = 0; i < 1000; ++i) if (read(slave, &byte, 1) != -1 || errno != EIO) _exit(1);
        long after = slab_kb();
        printf("TERMINAL JOBS SLAB before=%ld after=%ld KiB\n", before, after);
        if (after - before > 64) allocation_sites();
        _exit(before >= 0 && after >= 0 && after - before <= 64 ? 0 : 2);
    }
    check(child > 0 && exited_ok(child), "1000 rejected reads retain no growing slab memory");
    char data[2]; check(write(master, "R\n", 2) == 2 && read(slave, data, 2) == 2 && data[0] == 'R',
                     "foreground read still consumes data");
}
static void session_cases(int master, int slave, const char *image) {
    int gate[2]; check(pipe(gate) == 0, "create session gate");
    pid_t child = fork();
    if (!child) {
        close(gate[0]);
        if (setsid() < 0) _exit(1);
        char ready = 'r'; if (write(gate[1], &ready, 1) != 1) _exit(2);
        for (;;) pause();
    }
    close(gate[1]); char byte; check(read(gate[0], &byte, 1) == 1, "foreign session ready"); close(gate[0]);
    errno = 0; check(tcsetpgrp(slave, child) == -1 && errno == EPERM, "foreign-session foreground group rejected");
    errno = 0; check(setpgid(child, child) == -1 && errno == EPERM, "foreign-session child group mutation rejected");
    kill(child, SIGKILL); (void)wait_status(child, 0);
    child = background();
    if (!child) { errno = 0; _exit(setpgid(getppid(), getpgrp()) == -1 && errno == ESRCH ? 0 : 1); }
    check(child > 0 && exited_ok(child), "child cannot alter parent process group");
    errno = 0; check(tcsetpgrp(slave, -1) == -1 && errno == EINVAL, "negative foreground group rejected");
    errno = 0; check(tcsetpgrp(slave, 0) == -1 && errno == ESRCH, "nonexistent zero foreground group rejected");
    child = fork();
    if (!child) {
        if (setsid() < 0) _exit(1);
        errno = 0; _exit(tcgetpgrp(slave) == -1 && errno == ENOTTY && tcgetpgrp(master) >= 0 ? 0 : 2);
    }
    check(child > 0 && exited_ok(child), "non-controlling slave query rejected but master query usable");
    check(pipe(gate) == 0, "create exec gate");
    child = fork();
    if (!child) {
        close(gate[0]); char fd[24]; snprintf(fd, sizeof(fd), "%d", gate[1]);
        execl(image, image, "--after-exec", fd, NULL); _exit(1);
    }
    close(gate[1]); check(read(gate[0], &byte, 1) == 1, "child completed exec"); close(gate[0]);
    errno = 0; check(setpgid(child, child) == -1 && errno == EACCES, "parent cannot change child group after exec");
    kill(child, SIGKILL); (void)wait_status(child, 0);
}
static void stop_cases(int master, int slave) {
    struct termios settings; tcgetattr(slave, &settings);
    settings.c_lflag &= ~ICANON; settings.c_cc[VMIN] = 1;
    check(tcsetattr(slave, TCSANOW, &settings) == 0, "use noncanonical foreground input");
    pid_t owner = getpgrp(), child = background();
    if (!child) { char byte; _exit(read(slave, &byte, 1) == 1 && byte == 'Q' ? 0 : 1); }
    int status = wait_status(child, WUNTRACED);
    check(status >= 0 && WIFSTOPPED(status) && WSTOPSIG(status) == SIGTTIN, "background read stops with SIGTTIN");
    foreground(slave, child);
    check(write(master, "Q", 1) == 1 && kill(child, SIGCONT) == 0, "feed and continue foreground reader");
    check(exited_ok(child), "continued read restarts in foreground");
    foreground(slave, owner);
    settings.c_lflag |= TOSTOP;
    check(tcsetattr(slave, TCSANOW, &settings) == 0, "enable default writer stop");
    child = background();
    if (!child) _exit(write(slave, "w", 1) == 1 ? 0 : 1);
    status = wait_status(child, WUNTRACED);
    check(status >= 0 && WIFSTOPPED(status) && WSTOPSIG(status) == SIGTTOU,
          "default background writer stops with SIGTTOU");
    foreground(slave, child); kill(child, SIGCONT);
    check(exited_ok(child), "continued writer restarts in foreground");
    foreground(slave, owner);
    settings.c_lflag &= ~TOSTOP;
    check(tcsetattr(slave, TCSANOW, &settings) == 0, "disable default writer stop");
    int gate[2]; check(pipe(gate) == 0, "restart readiness pipe");
    child = background();
    if (!child) {
        close(gate[0]); restart_terminal = slave; restart_gate = gate[1];
        struct sigaction action; memset(&action, 0, sizeof(action));
        action.sa_handler = acquire_foreground; action.sa_flags = SA_RESTART;
        sigemptyset(&action.sa_mask); sigaction(SIGTTIN, &action, NULL);
        char byte = 0; ssize_t amount = read(slave, &byte, 1);
        printf("TERMINAL RESTART amount=%ld byte=%u signal=%d errno=%d\n",
               (long)amount, (unsigned char)byte, (int)caught_signal, errno);
        _exit(amount == 1 && byte == 'A' && caught_signal == SIGTTIN ? 0 : 1);
    }
    close(gate[1]); char ready;
    ssize_t ready_count = read(gate[0], &ready, 1);
    /* Force the restarted call to wait after its signal handler returned. */
    usleep(50000);
    check(ready_count == 1 && write(master, "A", 1) == 1,
          "restart handler acquires foreground and receives input");
    close(gate[0]); check(exited_ok(child), "caught SIGTTIN with SA_RESTART restarts read");
    foreground(slave, owner);
    child = background();
    if (!child) for (;;) pause();
    /* Parent publishes the group if its child has not run setpgid yet. */
    check(setpgid(child, child) == 0, "publish foreground child's group");
    foreground(slave, child);
    check(write(master, "\032", 1) == 1, "feed terminal suspend character");
    status = wait_status(child, WUNTRACED);
    check(status >= 0 && WIFSTOPPED(status) && WSTOPSIG(status) == SIGTSTP, "terminal suspend targets foreground group");
    foreground(slave, owner); kill(child, SIGKILL); (void)wait_status(child, 0);
    child = background();
    if (!child) for (;;) pause();
    check(setpgid(child, child) == 0, "publish foreground interrupt group");
    pid_t sibling = fork();
    if (!sibling) for (;;) pause();
    check(setpgid(sibling, child) == 0, "join sibling to foreground group");
    foreground(slave, child); check(write(master, "\003", 1) == 1, "feed terminal interrupt character");
    status = wait_status(child, 0);
    check(status >= 0 && WIFSIGNALED(status) && WTERMSIG(status) == SIGINT, "foreground leader receives SIGINT");
    status = wait_status(sibling, 0);
    check(status >= 0 && WIFSIGNALED(status) && WTERMSIG(status) == SIGINT, "foreground sibling receives SIGINT");
    foreground(slave, owner);
}
static int console_cases(void) {
    failures = 0;
    if (setsid() < 0) return 1;
    int console = open("/dev/console", O_RDWR | O_NOCTTY);
    errno = 0; check(console >= 0 && tcgetpgrp(console) == -1 && errno == ENOTTY,
                     "O_NOCTTY console open leaves terminal unclaimed");
    int claimed = open("/dev/console", O_RDWR);
    check(claimed >= 0 && tcgetpgrp(claimed) == getpgrp(), "console open claims eligible session");
    pid_t child = background();
    if (!child) {
        char byte; block(SIGTTIN, SIG_BLOCK);
        errno = 0; _exit(read(console, &byte, 1) == -1 && errno == EIO ? 0 : 1);
    }
    check(child > 0 && exited_ok(child), "console background read enforces SIGTTIN");
    struct termios settings; check(tcgetattr(console, &settings) == 0, "console attributes");
    settings.c_lflag |= TOSTOP;
    check(tcsetattr(console, TCSANOW, &settings) == 0, "console enables TOSTOP");
    child = background();
    if (!child) {
        handler(SIGTTOU); errno = 0;
        _exit(write(console, "x", 1) == -1 && errno == EINTR && caught_signal == SIGTTOU ? 0 : 1);
    }
    check(child > 0 && exited_ok(child), "console background write enforces TOSTOP");
    signal(SIGHUP, SIG_IGN);
    check(ioctl(console, TIOCNOTTY, 0) == 0, "console detach");
    close(claimed); close(console);
    return failures ? 1 : 0;
}
static void orphan_mutations(void) {
    signal(SIGHUP, SIG_IGN);
    transition_state = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    check(transition_state != MAP_FAILED, "orphan transition shared state");
    if (transition_state == MAP_FAILED) return;
    pid_t owner = getpgrp();
    for (int change_session = 0; change_session < 2; ++change_session) {
        memset((void *)transition_state, 0, 4096);
        int gate[2]; check(pipe(gate) == 0, "orphan transition gate");
        pid_t parent = fork();
        if (!parent) {
            close(gate[1]);
            if (!change_session && setpgid(0, 0)) _exit(1);
            pid_t job = fork();
            if (!job) {
                close(gate[0]);
                if (setpgid(0, change_session ? 0 : owner)) _exit(2);
                struct sigaction action; memset(&action, 0, sizeof(action));
                action.sa_handler = transition_signal; sigemptyset(&action.sa_mask);
                sigaction(SIGHUP, &action, NULL); sigaction(SIGCONT, &action, NULL);
                transition_state[2] = 1;
                for (;;) pause();
            }
            while (!transition_state[2]) usleep(1000);
            if (kill(job, SIGSTOP) || !WIFSTOPPED(wait_status(job, WUNTRACED))) _exit(3);
            int changed = change_session ? setsid() > 0 : setpgid(0, owner) == 0;
            transition_state[3] = changed;
            transition_state[4] = 1;
            char release; (void)read(gate[0], &release, 1);
            int valid = changed && transition_state[0] == 1 && transition_state[1] == 1;
            kill(job, SIGKILL); (void)wait_status(job, 0); close(gate[0]);
            _exit(valid ? 0 : 4);
        }
        close(gate[0]);
        for (int i = 0; i < 5000 && (!transition_state[4] || !transition_state[0] || !transition_state[1]); ++i) usleep(1000);
        check(transition_state[3] && transition_state[0] == 1 && transition_state[1] == 1,
              change_session ? "setsid resumes newly orphaned stopped group" : "setpgid resumes newly orphaned stopped group");
        (void)write(gate[1], "r", 1); close(gate[1]);
        check(parent > 0 && exited_ok(parent), "orphan mutation parent finishes");
    }
    munmap((void *)transition_state, 4096);
}
static int leader_hangup(void) {
    transition_state = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (transition_state == MAP_FAILED) return 0;
    int ready[2], release[2]; if (pipe(ready) || pipe(release)) return 0;
    pid_t leader = fork();
    if (!leader) {
        close(ready[0]); close(release[1]);
        if (setsid() < 0) _exit(1);
        int master = posix_openpt(O_RDWR | O_NOCTTY), unlocked = 0; unsigned int id;
        if (master < 0 || ioctl(master, TIOCSPTLCK, &unlocked) || ioctl(master, TIOCGPTN, &id)) _exit(2);
        char path[64]; snprintf(path, sizeof(path), "/dev/pts/%u", id);
        int slave = open(path, O_RDWR | O_NOCTTY);
        if (slave < 0 || ioctl(slave, TIOCSCTTY, 0)) _exit(3);
        pid_t job = fork();
        if (!job) {
            close(ready[1]); close(release[0]);
            if (setpgid(0, 0)) _exit(4);
            struct sigaction action; memset(&action, 0, sizeof(action));
            action.sa_handler = transition_signal; sigemptyset(&action.sa_mask);
            sigaction(SIGHUP, &action, NULL); sigaction(SIGCONT, &action, NULL);
            transition_state[2] = 1;
            while (!transition_state[0] || !transition_state[1]) usleep(1000);
            errno = 0; int no_query = tcgetpgrp(slave) == -1 && errno == ENOTTY;
            errno = 0; int no_tty = open("/dev/tty", O_RDWR | O_NOCTTY) == -1 && errno == ENXIO;
            transition_state[3] = no_query && no_tty;
            pid_t successor = fork();
            if (!successor) {
                signal(SIGHUP, SIG_IGN);
                signal(SIGCONT, SIG_IGN);
                _exit(setsid() > 0 && ioctl(slave, TIOCSCTTY, 0) == 0
                      && ioctl(slave, TIOCNOTTY, 0) == 0 ? 0 : 5);
            }
            transition_state[4] = successor > 0 && exited_ok(successor);
            close(slave); close(master); _exit(0);
        }
        while (!transition_state[2]) usleep(1000);
        if (tcsetpgrp(slave, job) || kill(job, SIGSTOP) || !WIFSTOPPED(wait_status(job, WUNTRACED))) _exit(6);
        (void)write(ready[1], &job, sizeof(job)); close(ready[1]);
        char byte; (void)read(release[0], &byte, 1); close(release[0]);
        _exit(0);
    }
    close(ready[1]); close(release[0]); pid_t job = 0;
    ssize_t amount = read(ready[0], &job, sizeof(job)); close(ready[0]);
    (void)write(release[1], "r", 1); close(release[1]);
    int leader_status = leader > 0 ? wait_status(leader, 0) : -1;
    int valid = leader_status >= 0 && WIFEXITED(leader_status) && !WEXITSTATUS(leader_status)
        && amount == (ssize_t)sizeof(job) && job > 0;
    int job_status = valid ? wait_status(job, 0) : -1;
    valid = valid && job_status >= 0 && WIFEXITED(job_status) && !WEXITSTATUS(job_status);
    printf("TERMINAL HANGUP leader_status=%d job=%d status=%d ready_bytes=%ld hup=%d cont=%d detached=%d successor=%d\n",
           leader_status, job, job_status, (long)amount, transition_state[0], transition_state[1],
           transition_state[3], transition_state[4]);
    check(valid && transition_state[0] == 1 && transition_state[1] == 1,
          "session-leader exit sends HUP and resumes stopped foreground job");
    check(valid && transition_state[3], "session-leader exit clears controlling identity for remaining members");
    check(valid && transition_state[4], "a new session can claim the hung-up terminal");
    munmap((void *)transition_state, 4096);
    return valid && !failures;
}
enum { OPEN_WORKERS = 3, OPEN_ROUNDS = 100 };
static int open_epoch, open_started[OPEN_WORKERS], open_done[OPEN_WORKERS], open_errors;
static void *race_open(void *argument) {
    int worker = (int)(intptr_t)argument, previous = 0;
    for (;;) {
        int epoch = __atomic_load_n(&open_epoch, __ATOMIC_ACQUIRE);
        if (epoch < 0) return NULL;
        if (epoch == previous) { usleep(100); continue; }
        previous = epoch;
        __atomic_store_n(&open_started[worker], epoch, __ATOMIC_RELEASE);
        for (int i = 0; i < 32; ++i) {
            int alias = open("/dev/tty", O_RDWR | O_NOCTTY);
            if (alias >= 0) {
                struct stat information;
                /* The master may close between open and this endpoint use. */
                if (fstat(alias, &information) || !S_ISCHR(information.st_mode))
                    __atomic_fetch_add(&open_errors, 1, __ATOMIC_RELAXED);
                usleep(100);
                if (close(alias)) __atomic_fetch_add(&open_errors, 1, __ATOMIC_RELAXED);
            } else if (errno != ENXIO && errno != EIO) {
                __atomic_fetch_add(&open_errors, 1, __ATOMIC_RELAXED);
            }
        }
        __atomic_store_n(&open_done[worker], epoch, __ATOMIC_RELEASE);
    }
}
static void owned_open_cases(void) {
    int unlock = 0; unsigned int id;
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    check(master >= 0 && ioctl(master, TIOCSPTLCK, &unlock) == 0
          && ioctl(master, TIOCGPTN, &id) == 0, "owned-open rollback master");
    if (master < 0) return;
    char path[64]; snprintf(path, sizeof(path), "/dev/pts/%u", id);
    int slave = open(path, O_RDWR | O_NOCTTY);
    check(slave >= 0 && ioctl(slave, TIOCSCTTY, 0) == 0, "owned-open rollback claim");
    struct stat information; check(fstat(slave, &information) == 0, "owned-open device identity");
    check(mknod("/root/tty-alias", S_IFCHR | 0600, information.st_rdev) == 0,
          "mknod forwards owned terminal opens");
    int alias = open("/root/tty-alias", O_RDWR | O_NOCTTY);
    check(alias >= 0 && tcgetpgrp(alias) == getpgrp(), "mknod terminal alias uses controlling session");
    if (alias >= 0) close(alias);
    struct rlimit original, limited;
    check(getrlimit(RLIMIT_NOFILE, &original) == 0, "read descriptor limit");
    limited = original; limited.rlim_cur = 64;
    check(setrlimit(RLIMIT_NOFILE, &limited) == 0, "limit rollback descriptor table");
    int held[64], count = 0;
    while (count < 64 && (held[count] = dup(master)) >= 0) ++count;
    int rolled_back = count < 64 && errno == EMFILE;
    for (int i = 0; i < 100; ++i) {
        errno = 0;
        if (open("/dev/tty", O_RDWR | O_NOCTTY) != -1 || errno != EMFILE) rolled_back = 0;
    }
    check(rolled_back, "full descriptor table rejects owned terminal opens");
    for (int i = 0; i < count; ++i) close(held[i]);
    check(setrlimit(RLIMIT_NOFILE, &original) == 0, "restore descriptor limit");
    close(slave);
    struct pollfd polled = { .fd = master, .events = POLLIN };
    check(poll(&polled, 1, 0) == 1 && (polled.revents & POLLHUP),
          "failed owned opens roll back every slave-open count");
    close(master); unlink("/root/tty-alias");

    pthread_t workers[OPEN_WORKERS]; int created = 0;
    for (; created < OPEN_WORKERS; ++created)
        if (pthread_create(&workers[created], NULL, race_open, (void *)(intptr_t)created)) break;
    check(created == OPEN_WORKERS, "create simultaneous terminal-open workers");
    int rounds = 0;
    long race_before = slab_kb();
    allocation_tracking();
    for (int epoch = 1; created == OPEN_WORKERS && epoch <= OPEN_ROUNDS; ++epoch) {
        master = posix_openpt(O_RDWR | O_NOCTTY);
        if (master < 0 || ioctl(master, TIOCSPTLCK, &unlock) || ioctl(master, TIOCGPTN, &id)) break;
        snprintf(path, sizeof(path), "/dev/pts/%u", id);
        slave = open(path, O_RDWR | O_NOCTTY);
        if (slave < 0 || ioctl(slave, TIOCSCTTY, 0)) break;
        close(slave); /* The pathname is now the only pre-existing slave ref. */
        __atomic_store_n(&open_epoch, epoch, __ATOMIC_RELEASE);
        for (int worker = 0; worker < OPEN_WORKERS; ++worker)
            while (__atomic_load_n(&open_started[worker], __ATOMIC_ACQUIRE) != epoch) usleep(100);
        usleep(100); close(master);
        for (int worker = 0; worker < OPEN_WORKERS; ++worker)
            while (__atomic_load_n(&open_done[worker], __ATOMIC_ACQUIRE) != epoch) usleep(100);
        ++rounds;
    }
    __atomic_store_n(&open_epoch, -1, __ATOMIC_RELEASE);
    for (int i = 0; i < created; ++i) pthread_join(workers[i], NULL);
    /* Wait out both retired VFS nodes and the Thread quarantine. */
    settle_grace();
    long race_after = slab_kb();
    printf("TERMINAL OWNED SLAB before=%ld after=%ld KiB\n", race_before, race_after);
    if (race_after > race_before + 64) allocation_sites();
    printf("TERMINAL OWNED OPEN rounds=%d errors=%d\n", rounds, open_errors);
    check(rounds == OPEN_ROUNDS && !open_errors, "concurrent controlling-terminal open and master-close survive");
    check(race_before >= 0 && race_after >= 0 && race_after <= race_before + 64,
          "retired terminal pairs and owned-open references remain bounded");
    errno = 0; check(open("/dev/tty", O_RDWR | O_NOCTTY) == -1 && errno == ENXIO,
                     "master-close clears final controlling-terminal identity");
}
static int manager(const char *image) {
    check(setsid() > 0, "create controlling session");
    int master = posix_openpt(O_RDWR | O_NOCTTY), unlock = 0; unsigned int id;
    check(master >= 0 && ioctl(master, TIOCSPTLCK, &unlock) == 0 && ioctl(master, TIOCGPTN, &id) == 0, "open PTY master");
    if (master < 0) return 1;
    char path[64]; snprintf(path, sizeof(path), "/dev/pts/%u", id);
    int slave = open(path, O_RDWR | O_NOCTTY);
    check(slave >= 0 && ioctl(slave, TIOCSCTTY, 0) == 0, "claim controlling PTY");
    if (slave < 0) return 1;
    check(tcgetpgrp(slave) == getpgrp(), "report initial foreground group");
    int alias = open("/dev/tty", O_RDWR | O_NOCTTY);
    check(alias >= 0 && tcgetpgrp(alias) == getpgrp(), "/dev/tty opens the claimed device");
    if (alias >= 0) close(alias);
    for (int i = 0; i < 50; ++i) { alias = open("/dev/tty", O_RDWR | O_NOCTTY); if (alias >= 0) close(alias); }
    long open_before = slab_kb();
    int opens_ok = 1;
    for (int i = 0; i < 1000; ++i) {
        alias = open("/dev/tty", O_RDWR | O_NOCTTY);
        if (alias < 0 || close(alias)) { opens_ok = 0; break; }
    }
    long open_after = slab_kb();
    printf("TERMINAL OPEN SLAB before=%ld after=%ld KiB\n", open_before, open_after);
    check(opens_ok && open_before >= 0 && open_after >= 0 && open_after <= open_before + 8,
          "1000 controlling-terminal opens retain bounded slab memory");
    int second_master = posix_openpt(O_RDWR | O_NOCTTY); unsigned int second_id = 0;
    check(second_master >= 0 && ioctl(second_master, TIOCSPTLCK, &unlock) == 0
          && ioctl(second_master, TIOCGPTN, &second_id) == 0, "second PTY master");
    snprintf(path, sizeof(path), "/dev/pts/%u", second_id);
    int second_slave = open(path, O_RDWR | O_NOCTTY);
    errno = 0; check(second_slave >= 0 && ioctl(second_slave, TIOCSCTTY, 0) == -1 && errno == EPERM,
                     "one session cannot claim two controlling terminals");
    permission_cases(master, slave); session_cases(master, slave, image); orphan_mutations();
    puts("TERMINAL JOBS PASS: permissions and sessions");
    stop_cases(master, slave);
    puts("TERMINAL JOBS PASS: stop and foreground signals");
    /* A session leader detaching its own foreground group receives SIGHUP. */
    signal(SIGHUP, SIG_IGN);
    check(ioctl(slave, TIOCNOTTY, 0) == 0, "detach controlling terminal");
    errno = 0; check(tcgetpgrp(slave) == -1 && errno == ENOTTY, "detached terminal loses controlling state");
    errno = 0; check(open("/dev/tty", O_RDWR | O_NOCTTY) == -1 && errno == ENXIO,
                     "detached session has no /dev/tty");
    check(ioctl(second_slave, TIOCSCTTY, 0) == 0, "detached session can claim a new terminal");
    alias = open("/dev/tty", O_RDWR | O_NOCTTY);
    struct stat claimed, reopened;
    check(alias >= 0 && fstat(alias, &reopened) == 0 && fstat(second_slave, &claimed) == 0
          && reopened.st_rdev == claimed.st_rdev, "/dev/tty follows unique replacement device");
    if (alias >= 0) close(alias);
    check(ioctl(second_slave, TIOCNOTTY, 0) == 0, "detach replacement terminal");
    close(second_slave); close(second_master); close(slave); close(master);
    owned_open_cases();
    return failures ? 1 : 0;
}
int main(int argc, char **argv) {
    if (argc == 3 && !strcmp(argv[1], "--after-exec")) {
        if (write(atoi(argv[2]), "r", 1) != 1) return 1;
        for (;;) pause();
    }
    int console = open("/dev/com1", O_WRONLY);
    if (console >= 0) { dup2(console, 1); dup2(console, 2); close(console); }
    setvbuf(stdout, NULL, _IONBF, 0);
    pid_t child = fork();
    if (!child) _exit(manager(argv[0]));
    int passed = child > 0 && exited_ok(child);
    passed = leader_hangup() && passed;
    child = fork();
    if (!child) _exit(console_cases());
    passed = (child > 0 && exited_ok(child)) && passed;
    puts(passed ? "TERMINAL JOBS GUEST: PASS" : "TERMINAL JOBS GUEST: FAIL");
    for (;;) pause();
}
