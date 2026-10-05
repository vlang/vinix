#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

enum { CHILDREN = 8, WRITE_BYTES = 512 * 1024 };
static int failures;
static void check(int ok, const char *name) {
    printf("SHARED STREAMS %s: %s errno=%d\n", ok ? "OK" : "FAIL", name, errno);
    failures += !ok;
}
static int reap(pid_t child) {
    int status, result;
    do result = waitpid(child, &status, 0); while (result < 0 && errno == EINTR);
    return result == child && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
static void readers(int input, int output, const char *name) {
    int ready[2]; check(pipe(ready) == 0, "reader readiness pipe");
    pid_t children[CHILDREN];
    for (int i = 0; i < CHILDREN; ++i) {
        children[i] = fork();
        if (!children[i]) {
            close(ready[0]); char byte = 'r';
            if (write(ready[1], &byte, 1) != 1) _exit(1);
            /* All children share the exact same input open description. */
            _exit(read(input, &byte, 1) == 1 && byte == 'x' ? 0 : 2);
        }
        check(children[i] > 0, "fork reader");
    }
    close(ready[1]);
    for (int i = 0; i < CHILDREN; ++i) {
        char byte; check(read(ready[0], &byte, 1) == 1, "reader reached shared description");
    }
    close(ready[0]);
    check(write(output, "xxxxxxxx", CHILDREN) == CHILDREN, "producer remains schedulable");
    for (int i = 0; i < CHILDREN; ++i) check(reap(children[i]), "shared reader completed");
    char byte; errno = 0;
    check(pread(input, &byte, 1, 0) == -1 && errno == ESPIPE, "stream pread fails ESPIPE");
    printf("SHARED STREAMS PASS: %s\n", name);
}
static void writers(void) {
    int data[2], ready[2]; check(pipe(data) == 0 && pipe(ready) == 0, "writer pipes");
    pid_t children[CHILDREN];
    for (int i = 0; i < CHILDREN; ++i) {
        children[i] = fork();
        if (!children[i]) {
            close(data[0]); close(ready[0]); char chunk[4096]; memset(chunk, 'w', sizeof(chunk));
            if (write(ready[1], "r", 1) != 1) _exit(1);
            for (int done = 0; done < WRITE_BYTES;) {
                ssize_t amount = write(data[1], chunk, sizeof(chunk));
                if (amount <= 0) _exit(2);
                done += (int)amount;
            }
            _exit(0);
        }
        check(children[i] > 0, "fork writer");
    }
    close(ready[1]);
    for (int i = 0; i < CHILDREN; ++i) {
        char byte; check(read(ready[0], &byte, 1) == 1, "writer reached shared description");
    }
    close(ready[0]); close(data[1]);
    size_t total = 0; char chunk[8192]; ssize_t amount;
    while ((amount = read(data[0], chunk, sizeof(chunk))) > 0) total += (size_t)amount;
    check(total == (size_t)CHILDREN * WRITE_BYTES, "shared writers drain without starvation");
    for (int i = 0; i < CHILDREN; ++i) check(reap(children[i]), "shared writer completed");
    close(data[0]);
}
static void offsets(void) {
    int fd = open("/root/offsets", O_RDWR | O_CREAT | O_TRUNC, 0600), answers[2];
    check(fd >= 0 && pipe(answers) == 0, "seekable fixture");
    check(write(fd, "01234567", CHILDREN) == CHILDREN && lseek(fd, 0, SEEK_SET) == 0,
          "seekable initial bytes");
    pid_t children[CHILDREN];
    for (int i = 0; i < CHILDREN; ++i) {
        children[i] = fork();
        if (!children[i]) {
            close(answers[0]); char byte;
            _exit(read(fd, &byte, 1) == 1 && write(answers[1], &byte, 1) == 1 ? 0 : 1);
        }
    }
    close(answers[1]); unsigned seen = 0;
    for (int i = 0; i < CHILDREN; ++i) {
        char byte = 0; check(read(answers[0], &byte, 1) == 1 && byte >= '0' && byte <= '7', "file result");
        if (byte >= '0' && byte <= '7') seen |= 1U << (byte - '0');
    }
    for (int i = 0; i < CHILDREN; ++i) check(reap(children[i]), "file reader completed");
    check(seen == 255 && lseek(fd, 0, SEEK_CUR) == CHILDREN, "shared file offset stays atomic");
    close(answers[0]); close(fd); unlink("/root/offsets");
    puts("SHARED STREAMS PASS: offsets");
}
int main(void) {
    int console = open("/dev/com1", O_WRONLY);
    if (console >= 0) { dup2(console, 1); dup2(console, 2); close(console); }
    setvbuf(stdout, NULL, _IONBF, 0);
    int pipefd[2]; check(pipe(pipefd) == 0, "shared pipe");
    readers(pipefd[0], pipefd[1], "pipe"); close(pipefd[0]); close(pipefd[1]);
    int sockets[2]; check(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0, "shared socket");
    readers(sockets[0], sockets[1], "socket"); close(sockets[0]); close(sockets[1]);
    int master = posix_openpt(O_RDWR | O_NOCTTY), unlock = 0; unsigned int id = 0;
    check(master >= 0 && ioctl(master, TIOCSPTLCK, &unlock) == 0 && ioctl(master, TIOCGPTN, &id) == 0, "PTY master");
    char path[64]; snprintf(path, sizeof(path), "/dev/pts/%u", id);
    int slave = open(path, O_RDWR | O_NOCTTY); struct termios settings;
    check(slave >= 0 && tcgetattr(slave, &settings) == 0, "PTY slave");
    settings.c_lflag &= ~(ICANON | ECHO); settings.c_cc[VMIN] = 1; settings.c_cc[VTIME] = 0;
    check(tcsetattr(slave, TCSANOW, &settings) == 0, "PTY raw input");
    readers(slave, master, "terminal"); close(slave); close(master);
    writers(); offsets();
    puts(failures ? "SHARED STREAMS GUEST: FAIL" : "SHARED STREAMS GUEST: PASS");
    for (;;) pause();
}
