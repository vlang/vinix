/* Native stream, terminal and libc declarations; fixture algorithms are V. */
#ifndef VINIX_SHARED_STREAM_FIXTURE_NATIVE_ABI_H
#define VINIX_SHARED_STREAM_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
_Static_assert(sizeof(int) == 4 && sizeof(pid_t) == 4, "native process and descriptor widths");
_Static_assert(sizeof(off_t) == 8 && sizeof(size_t) == 8 && sizeof(ssize_t) == 8, "native stream offsets and transfer widths");
_Static_assert(sizeof(tcflag_t) == 4 && sizeof(((struct termios *)0)->c_lflag) == 4, "native terminal flag width");
_Static_assert(sizeof(((struct termios *)0)->c_cc) == 32, "native Linux terminal control array");
#endif
