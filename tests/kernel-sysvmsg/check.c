#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/msg.h>
#include <sys/reboot.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef MSG_COPY
#define MSG_COPY 040000
#endif

struct message { long type; unsigned char text[8192]; };
static struct message message;
static int failures;
static volatile sig_atomic_t signals_seen;

static void check(int valid, const char *name) {
    printf("MSG-CHECK %s %s\n", valid ? "PASS" : "FAIL", name);
    if (!valid) failures++;
}

static int send_byte(int queue, long type, unsigned char byte) {
    struct { long type; unsigned char byte; } one = {type, byte};
    return msgsnd(queue, &one, 1, IPC_NOWAIT);
}

static int take_byte(int queue, long selector, int flags, long type, unsigned char byte) {
    return msgrcv(queue, &message, sizeof(message.text), selector, IPC_NOWAIT | flags) == 1 &&
           message.type == type && message.text[0] == byte;
}

static int queue_new(void) {
    return msgget(IPC_PRIVATE, 0600);
}

static int resize_queue(int queue, unsigned long bytes) {
    struct msqid_ds info;
    if (msgctl(queue, IPC_STAT, &info)) return -1;
    info.msg_qbytes = bytes;
    return msgctl(queue, IPC_SET, &info);
}

static void basic(void) {
    struct msginfo limits;
    check(msgctl(0, IPC_INFO, (void *)&limits) >= 0 && limits.msgmax == 8192 &&
          limits.msgmnb == 16384 && limits.msgmni > 0, "IPC_INFO reports enforced limits");
    int queue = queue_new();
    check(queue >= 0, "private queue create");
    struct msqid_ds info;
    check(msgctl(queue, IPC_STAT, &info) == 0 && info.msg_qnum == 0 &&
          info.msg_qbytes == 16384 && (info.msg_perm.mode & 0777) == 0600,
          "IPC_STAT native ABI metadata");
    check(msgctl(queue & 0xffff, MSG_STAT, &info) == queue,
          "MSG_STAT index returns generation ID");
    check(send_byte(queue, 5, 'a') == 0 && send_byte(queue, 2, 'b') == 0 &&
          send_byte(queue, 5, 'c') == 0 && send_byte(queue, 1, 'd') == 0,
          "enqueue distinct message types");
    check(take_byte(queue, -4, 0, 1, 'd'), "negative selector chooses lowest type");
    check(take_byte(queue, 5, 0, 5, 'a'), "positive selector preserves FIFO ties");
    check(take_byte(queue, 5, MSG_EXCEPT, 2, 'b'), "MSG_EXCEPT chooses first other type");
    check(take_byte(queue, 0, 0, 5, 'c'), "zero selector chooses FIFO head");
    check(send_byte(queue, LONG_MAX, 'm') == 0 && take_byte(queue, LONG_MIN, 0, LONG_MAX, 'm'),
          "LONG_MIN selector avoids signed overflow");
    errno = 0;
    check(msgrcv(queue, &message, 1, 0, IPC_NOWAIT) == -1 && errno == ENOMSG,
          "empty nonblocking receive ENOMSG");

    message.type = 7;
    memcpy(message.text, "abcdefgh", 8);
    check(msgsnd(queue, &message, 8, 0) == 0, "send eight bytes");
    errno = 0;
    check(msgrcv(queue, &message, 4, 0, IPC_NOWAIT) == -1 && errno == E2BIG &&
          msgctl(queue, IPC_STAT, &info) == 0 && info.msg_qnum == 1,
          "E2BIG keeps message queued");
    check(msgrcv(queue, &message, 4, 0, IPC_NOWAIT | MSG_COPY | MSG_NOERROR) == 4 &&
          message.type == 7 && !memcmp(message.text, "abcd", 4) &&
          msgctl(queue, IPC_STAT, &info) == 0 && info.msg_qnum == 1,
          "MSG_COPY snapshots ordinal without consuming");
    errno = 0;
    check(msgrcv(queue, &message, 8, 0, MSG_COPY) == -1 && errno == EINVAL,
          "MSG_COPY requires IPC_NOWAIT");
    errno = 0;
    check(msgrcv(queue, &message, 8, 0, MSG_COPY | MSG_EXCEPT | IPC_NOWAIT) == -1 && errno == EINVAL,
          "MSG_COPY rejects MSG_EXCEPT");
    check(msgrcv(queue, &message, 4, 0, IPC_NOWAIT | MSG_NOERROR) == 4 &&
          !memcmp(message.text, "abcd", 4) && msgctl(queue, IPC_STAT, &info) == 0 && !info.msg_qnum,
          "MSG_NOERROR truncates and consumes");

    check(resize_queue(queue, 1) == 0, "IPC_SET changes queue byte quota");
    message.type = 1;
    check(msgsnd(queue, &message, 0, 0) == 0, "zero-byte message enqueues");
    errno = 0;
    check(msgsnd(queue, &message, 0, IPC_NOWAIT) == -1 && errno == EAGAIN &&
          msgctl(queue, IPC_STAT, &info) == 0 && info.msg_qnum == 1 && !info.msg_cbytes,
          "zero-byte messages obey count quota");
    check(msgrcv(queue, &message, 0, 0, IPC_NOWAIT) == 0 && message.type == 1,
          "zero-byte receive returns message type");

    message.type = 0;
    errno = 0;
    check(msgsnd(queue, &message, 1, IPC_NOWAIT) == -1 && errno == EINVAL,
          "reject nonpositive type");
    message.type = 1;
    errno = 0;
    check(msgsnd(queue, &message, 8193, IPC_NOWAIT) == -1 && errno == EINVAL,
          "enforce maximum message size");
    errno = 0;
    check(syscall(SYS_msgsnd, queue, UINTPTR_MAX, 1, IPC_NOWAIT) == -1 && errno == EFAULT,
          "checked msgsnd user pointer");
    errno = 0;
    check(syscall(SYS_msgctl, queue, IPC_STAT, UINTPTR_MAX) == -1 && errno == EFAULT,
          "checked msgctl output pointer");
    check(send_byte(queue, 1, 'f') == 0, "faulted receive arm");
    void *bad = mmap(NULL, 4096, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    errno = 0;
    check(bad != MAP_FAILED && msgrcv(queue, bad, 1, 0, IPC_NOWAIT) == -1 && errno == EFAULT,
          "unwritable receive returns EFAULT without kernel fault");
    if (bad != MAP_FAILED) munmap(bad, 4096);
    check(msgctl(queue, IPC_STAT, &info) == 0 && !info.msg_qnum,
          "faulted receive releases detached message");
    check(msgctl(queue, IPC_RMID, NULL) == 0, "remove queue");
    int replacement = queue_new();
    errno = 0;
    check(replacement >= 0 && replacement != queue && msgctl(queue, IPC_STAT, &info) == -1 && errno == EINVAL,
          "removed generation ID never aliases replacement");
    msgctl(replacement, IPC_RMID, NULL);
}

static void permissions(void) {
    const key_t key = 0x48716533;
    int queue = msgget(key, IPC_CREAT | IPC_EXCL | 0600);
    check(queue >= 0 && msgget(key, 0600) == queue, "key lookup finds same queue");
    errno = 0;
    check(msgget(key, IPC_CREAT | IPC_EXCL | 0600) == -1 && errno == EEXIST,
          "exclusive key collision EEXIST");
    struct msqid_ds info;
    msgctl(queue, IPC_STAT, &info);
    info.msg_perm.uid = 1000;
    info.msg_perm.gid = 2000;
    info.msg_perm.mode = 0640;
    check(msgctl(queue, IPC_SET, &info) == 0, "owner and group permissions set");
    pid_t child = fork();
    if (!child) {
        if (setgid(3000) || setuid(3000)) _exit(2);
        struct msqid_ds state;
        int valid = msgget(key, 0400) == -1 && errno == EACCES;
        valid &= send_byte(queue, 1, 'x') == -1 && errno == EACCES;
        valid &= msgrcv(queue, &message, 1, 0, IPC_NOWAIT) == -1 && errno == EACCES;
        valid &= msgctl(queue, IPC_STAT, &state) == -1 && errno == EACCES;
        valid &= msgctl(queue & 0xffff, MSG_STAT_ANY, &state) == queue;
        valid &= msgctl(queue, IPC_SET, &state) == -1 && errno == EPERM;
        valid &= msgctl(queue, IPC_RMID, NULL) == -1 && errno == EPERM;
        _exit(valid ? 0 : 3);
    }
    int status = 0;
    check(child > 0 && waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0,
          "nonowner access/control denied and MSG_STAT_ANY allowed");
    child = fork();
    if (!child) {
        if (setgid(2000) || setuid(3000)) _exit(2);
        int valid = msgget(key, 0400) == queue;
        valid &= send_byte(queue, 1, 'x') == -1 && errno == EACCES;
        valid &= msgrcv(queue, &message, 1, 0, IPC_NOWAIT) == -1 && errno == ENOMSG;
        _exit(valid ? 0 : 3);
    }
    check(child > 0 && waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0,
          "group read permission without write permission");
    msgctl(queue, IPC_RMID, NULL);
}

struct waiter {
    int queue, sending, result, error;
    atomic_int ready;
};

static void *wait_message(void *argument) {
    struct waiter *waiter = argument;
    struct { long type; unsigned char byte; } one = {9, 'w'};
    waiter->ready = 1;
    waiter->result = waiter->sending ? msgsnd(waiter->queue, &one, 1, 0) :
                     (int)msgrcv(waiter->queue, &one, 1, 9, 0);
    waiter->error = errno;
    return NULL;
}

static void wait_ready(struct waiter *waiter) {
    while (!waiter->ready) sched_yield();
    usleep(30000);
}

static void signal_seen(int signal) { (void)signal; signals_seen++; }

static void blocking(void) {
    int queue = queue_new();
    struct waiter receiver = {.queue = queue};
    pthread_t thread;
    check(pthread_create(&thread, NULL, wait_message, &receiver) == 0, "blocking receiver created");
    wait_ready(&receiver);
    send_byte(queue, 9, 'w');
    pthread_join(thread, NULL);
    check(receiver.result == 1, "send wakes matching blocked receiver");

    resize_queue(queue, 1);
    send_byte(queue, 9, 'f');
    struct waiter sender = {.queue = queue, .sending = 1};
    pthread_create(&thread, NULL, wait_message, &sender);
    wait_ready(&sender);
    check(take_byte(queue, 9, 0, 9, 'f'), "receive frees full queue capacity");
    pthread_join(thread, NULL);
    check(sender.result == 0 && take_byte(queue, 9, 0, 9, 'w'), "receive wakes blocked sender");

    send_byte(queue, 9, 'f');
    sender = (struct waiter){.queue = queue, .sending = 1};
    pthread_create(&thread, NULL, wait_message, &sender);
    wait_ready(&sender);
    resize_queue(queue, 2);
    pthread_join(thread, NULL);
    check(sender.result == 0, "IPC_SET larger quota wakes blocked sender");
    take_byte(queue, 0, 0, 9, 'f');
    take_byte(queue, 0, 0, 9, 'w');

    struct sigaction action = {.sa_handler = signal_seen, .sa_flags = SA_RESTART};
    sigemptyset(&action.sa_mask);
    sigaction(SIGUSR1, &action, NULL);
    receiver = (struct waiter){.queue = queue};
    pthread_create(&thread, NULL, wait_message, &receiver);
    wait_ready(&receiver);
    pthread_kill(thread, SIGUSR1);
    pthread_join(thread, NULL);
    check(receiver.result == -1 && receiver.error == EINTR && signals_seen,
          "signal interrupts receive despite SA_RESTART");

    resize_queue(queue, 1);
    send_byte(queue, 9, 'f');
    sender = (struct waiter){.queue = queue, .sending = 1};
    pthread_create(&thread, NULL, wait_message, &sender);
    wait_ready(&sender);
    pthread_kill(thread, SIGUSR1);
    pthread_join(thread, NULL);
    check(sender.result == -1 && sender.error == EINTR && take_byte(queue, 0, 0, 9, 'f'),
          "signal interrupts sender and releases its pending snapshot");

    int races = 1;
    for (int i = 0; i < 100 && races; i++) {
        receiver = (struct waiter){.queue = queue};
        if (pthread_create(&thread, NULL, wait_message, &receiver)) { races = 0; break; }
        while (!receiver.ready) sched_yield();
        if (send_byte(queue, 9, 'w')) races = 0;
        pthread_join(thread, NULL);
        if (receiver.result != 1) races = 0;
        send_byte(queue, 9, 'f');
        sender = (struct waiter){.queue = queue, .sending = 1};
        if (pthread_create(&thread, NULL, wait_message, &sender)) { races = 0; break; }
        while (!sender.ready) sched_yield();
        if (!take_byte(queue, 0, 0, 9, 'f')) races = 0;
        pthread_join(thread, NULL);
        if (sender.result != 0 || !take_byte(queue, 0, 0, 9, 'w')) races = 0;
    }
    check(races, "send/receive wake and waiter attachment races make progress");

    enum { count = 70 };
    struct waiter receivers[count];
    pthread_t threads[count];
    memset(receivers, 0, sizeof receivers);
    for (int i = 0; i < count; i++) {
        receivers[i].queue = queue;
        pthread_create(&threads[i], NULL, wait_message, &receivers[i]);
        while (!receivers[i].ready) sched_yield();
    }
    usleep(50000);
    msgctl(queue, IPC_RMID, NULL);
    int valid = 1;
    for (int i = 0; i < count; i++) {
        pthread_join(threads[i], NULL);
        valid &= receivers[i].result == -1 && receivers[i].error == EIDRM;
    }
    check(valid, "removal wakes seventy receivers without a shared-listener cap");

    queue = queue_new();
    resize_queue(queue, 1);
    send_byte(queue, 9, 'f');
    sender = (struct waiter){.queue = queue, .sending = 1};
    pthread_create(&thread, NULL, wait_message, &sender);
    wait_ready(&sender);
    msgctl(queue, IPC_RMID, NULL);
    pthread_join(thread, NULL);
    check(sender.result == -1 && sender.error == EIDRM, "removal wakes sender and frees pending payload");
}

static void namespaces(void) {
    const key_t key = 0x49706533;
    int queue = msgget(key, IPC_CREAT | IPC_EXCL | 0600);
    send_byte(queue, 3, 'p');
    pid_t child = fork();
    if (!child) {
        if (unshare(CLONE_NEWIPC)) _exit(2);
        int valid = msgget(key, 0) == -1 && errno == ENOENT;
        valid &= send_byte(queue, 3, 'x') == -1 && errno == EINVAL;
        int own = msgget(key, IPC_CREAT | IPC_EXCL | 0600);
        valid &= own >= 0 && own != queue && send_byte(own, 3, 'c') == 0;
        // Leave the queue populated: namespace destruction must reclaim it.
        _exit(valid ? 0 : 3);
    }
    int status = 0;
    check(child > 0 && waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0,
          "IPC namespace isolates keys and IDs");
    check(take_byte(queue, 0, 0, 3, 'p'), "child namespace cannot mutate parent queue");
    msgctl(queue, IPC_RMID, NULL);
}

static void global_quotas(void) {
    int queues[9];
    int complete = 1;
    for (int i = 0; i < 9; i++) {
        queues[i] = queue_new();
        if (queues[i] < 0 || resize_queue(queues[i], 1024 * 1024)) complete = 0;
    }
    message.type = 1;
    int filled = 0, exhausted = 0;
    // The bounded pool includes each private kernel message header as well
    // as its payload. Filling exactly 8 MiB of payloads must fail earlier.
    for (; filled < 1024 && complete; filled++) {
        if (msgsnd(queues[filled / 128], &message, 8192, IPC_NOWAIT)) {
            exhausted = errno == ENOMEM;
            break;
        }
    }
    errno = 0;
    check(complete && exhausted && filled > 960 && filled < 1024 &&
          msgsnd(queues[8], &message, 8192, IPC_NOWAIT) == -1 && errno == ENOMEM,
          "global byte quota bounds queued and pending payloads");
    errno = 0;
    check(complete && exhausted && filled > 960 &&
          msgrcv(queues[0], &message, 8192, 0, MSG_COPY | IPC_NOWAIT) == -1 && errno == ENOMEM,
          "MSG_COPY snapshot obeys the saturated global byte quota");
    check(complete && exhausted && filled > 960 &&
          msgrcv(queues[0], &message, 8192, 0, IPC_NOWAIT) == 8192 &&
          msgsnd(queues[8], &message, 8192, IPC_NOWAIT) == 0,
          "consuming one message returns its global byte reservation");
    for (int i = 0; i < 9; i++) if (queues[i] >= 0) msgctl(queues[i], IPC_RMID, NULL);

    int queue = queue_new();
    complete = queue >= 0;
    for (int i = 0; i < 8192 && complete; i++) {
        if (msgsnd(queue, &message, 0, IPC_NOWAIT)) complete = 0;
    }
    errno = 0;
    check(complete && msgsnd(queue, &message, 0, IPC_NOWAIT) == -1 && errno == ENOMEM,
          "global message quota bounds zero-byte headers");
    msgctl(queue, IPC_RMID, NULL);
    queue = queue_new();
    check(queue >= 0 && send_byte(queue, 1, 'r') == 0 && take_byte(queue, 0, 0, 1, 'r'),
          "removal returns global byte and message reservations");
    msgctl(queue, IPC_RMID, NULL);
}

static void namespace_descriptions(void) {
    int announced[2], exit_now[2], join_now[2];
    if (pipe(announced) || pipe(exit_now) || pipe(join_now)) {
        check(0, "namespace description pipes");
        return;
    }
    pid_t creator = fork();
    if (!creator) {
        close(announced[0]);
        close(exit_now[1]);
        if (unshare(CLONE_NEWIPC)) _exit(2);
        int queue = queue_new();
        if (queue < 0 || send_byte(queue, 3, 'n') ||
            write(announced[1], &queue, sizeof queue) != sizeof queue) _exit(3);
        char release;
        if (read(exit_now[0], &release, 1) != 1) _exit(4);
        _exit(0);
    }
    close(announced[1]);
    close(exit_now[0]);
    int queue = -1;
    int notified = read(announced[0], &queue, sizeof queue) == sizeof queue;
    close(announced[0]);
    char path[64];
    snprintf(path, sizeof path, "/proc/%ld/ns/ipc", (long)creator);
    int descriptor = open(path, O_PATH | O_CLOEXEC);
    int duplicate = dup(descriptor);
    check(notified && descriptor >= 0 && duplicate >= 0,
          "O_PATH namespace description and dup pin created");
    pid_t observer = fork();
    if (!observer) {
        close(join_now[1]);
        char release;
        if (read(join_now[0], &release, 1) != 1 ||
            setns(duplicate, CLONE_NEWIPC) || !take_byte(queue, 0, 0, 3, 'n') ||
            send_byte(queue, 3, 'r')) _exit(5);
        close(descriptor);
        close(duplicate);
        // Leaving this namespace releases its process reference after its
        // inherited description's single pin has been given back.
        _exit(0);
    }
    close(join_now[0]);
    char release = 'x';
    write(exit_now[1], &release, 1);
    close(exit_now[1]);
    int status = 0;
    int creator_exited = creator > 0 && waitpid(creator, &status, 0) == creator &&
                         WIFEXITED(status) && WEXITSTATUS(status) == 0;
    close(descriptor);
    close(duplicate);
    write(join_now[1], &release, 1);
    close(join_now[1]);
    check(creator_exited && observer > 0 && waitpid(observer, &status, 0) == observer &&
          WIFEXITED(status) && WEXITSTATUS(status) == 0,
          "forked O_PATH description keeps queues after last namespace process exits");

    struct msginfo limits;
    int ids[256], count = 0;
    msgctl(0, IPC_INFO, (void *)&limits);
    while (count < limits.msgmni && count < 256) {
        int id = queue_new();
        if (id < 0) break;
        ids[count++] = id;
    }
    check(count == limits.msgmni, "last namespace description/process release reclaims queue slot");
    for (int i = 0; i < count; i++) msgctl(ids[i], IPC_RMID, NULL);
}

struct snapshot { unsigned long size[32], objects[32]; int count; };

static int snapshot(struct snapshot *state) {
    FILE *file = fopen("/proc/slabinfo", "r");
    if (!file) return -1;
    memset(state, 0, sizeof *state);
    char line[256];
    while (fgets(line, sizeof line, file)) {
        unsigned long size, live, pages;
        if (sscanf(line, "size-%lu %*u %lu %lu", &size, &live, &pages) != 3) continue;
        if (state->count == 32) { fclose(file); return -1; }
        state->size[state->count] = size;
        state->objects[state->count++] = live;
    }
    fclose(file);
    return state->count ? 0 : -1;
}

static int cycle(unsigned iterations) {
    for (unsigned i = 0; i < iterations; i++) {
        int descriptor = open("/proc/self/ns/ipc", O_PATH | O_CLOEXEC);
        int duplicate = dup(descriptor);
        if (descriptor < 0 || duplicate < 0 || close(descriptor) || close(duplicate)) return -1;
        int queue = queue_new();
        message.type = 1;
        if (queue < 0 || msgsnd(queue, &message, 8192, 0) ||
            msgrcv(queue, &message, 8192, 0, MSG_COPY | IPC_NOWAIT) != 8192 ||
            msgrcv(queue, &message, 8192, 0, 0) != 8192 ||
            msgsnd(queue, &message, 0, 0) || msgctl(queue, IPC_RMID, NULL)) return -1;
    }
    return 0;
}

static long free_kb(void) {
    FILE *file = fopen("/proc/meminfo", "r");
    if (!file) return -1;
    char line[256];
    long available = -1;
    while (fgets(line, sizeof line, file)) {
        if (sscanf(line, "MemFree: %ld kB", &available) == 1) break;
    }
    fclose(file);
    return available;
}

static void allocations(void) {
    struct snapshot before = {0}, after = {0}, final = {0};
    int completed = cycle(32) == 0 && snapshot(&before) == 0 && cycle(200) == 0 &&
                    snapshot(&after) == 0 && cycle(200) == 0 && snapshot(&final) == 0;
    check(completed, "repeated queue/message allocation measurement completed");
    if (!completed) return;
    int valid = before.count > 0 && before.count == after.count && after.count == final.count;
    for (int i = 0; i < before.count; i++) {
        long delta1 = (long)after.objects[i] - (long)before.objects[i];
        long delta2 = (long)final.objects[i] - (long)after.objects[i];
        printf("MSG-SLAB size=%lu first=%ld second=%ld\n", before.size[i], delta1, delta2);
        if (delta1 > 2 || delta2 > 2) valid = 0;
    }
    check(valid, "queue/create/send/copy/receive/remove retains no repeated heap objects");
    struct msginfo info;
    check(msgctl(0, MSG_INFO, (void *)&info) >= 0 && info.msgpool == 0 &&
          info.msgmap == 0 && info.msgtql == 0, "queue statistics return empty after removal");

    // Maximum-size payloads exceed the largest slab class. Measure physical
    // free memory separately so page allocations cannot hide in slab counts.
    long free_before = free_kb();
    int pages_complete = cycle(200) == 0;
    long free_after = free_kb();
    pages_complete &= cycle(200) == 0;
    long free_final = free_kb();
    printf("MSG-MEM first_kb=%ld second_kb=%ld\n", free_before - free_after, free_after - free_final);
    check(pages_complete && free_before >= 0 && free_after >= 0 && free_final >= 0 &&
          free_before - free_after <= 128 && free_after - free_final <= 128,
          "maximum-sized messages return physical page allocations");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("MSG-CHECK START");
    alarm(90);
    basic();
    permissions();
    blocking();
    namespaces();
    namespace_descriptions();
    global_quotas();
    allocations();
    alarm(0);
    printf("MSG-CHECK DONE failures=%d\n", failures);
    if (getpid() == 1) { reboot(RB_POWER_OFF); for (;;) pause(); }
    return failures ? 1 : 0;
}
