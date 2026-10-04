// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* PID 1 of the small image build.py makes by default. The first boots on a
 * new Mac have no keyboard driver to type at, so instead of a shell this
 * says it reached user space -- the QEMU test waits for that line -- and
 * puts what the kernel found on the console: the machine, its memory, its
 * CPUs. Then it stays up, so the screen can be read. */
#include <fcntl.h>
#include <string.h>
#include <sys/utsname.h>
#include <unistd.h>

static int console = 1;

static void say(const char *text)
{
    write(console, text, strlen(text));
}

/* The first lines of a /proc file. */
static void show(const char *path, int lines)
{
    char buffer[4096];
    int file = open(path, O_RDONLY);
    ssize_t length;

    if (file < 0)
        return;
    say("--- ");
    say(path);
    say(" ---\n");
    length = read(file, buffer, sizeof(buffer));
    close(file);
    for (ssize_t index = 0; index < length && lines > 0; index++) {
        write(console, &buffer[index], 1);
        if (buffer[index] == '\n')
            lines--;
    }
}

int main(void)
{
    struct utsname name;
    int fd = open("/dev/console", O_WRONLY);

    if (fd >= 0)
        console = fd;
    say("APPLE-BOOT: init reached user space\n");
    if (uname(&name) == 0) {
        say(name.sysname);
        say(" ");
        say(name.release);
        say(" ");
        say(name.machine);
        say("\n");
    }
    show("/proc/meminfo", 3);
    show("/proc/cpuinfo", 12);
    for (;;)
        pause();
}
