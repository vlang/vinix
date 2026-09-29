// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* PID 1 for the fake-iBoot QEMU test: proves the kernel the loader started
 * reached user space, then stays up so the framebuffer can be inspected. */
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

int main(void)
{
    static const char message[] = "APPLE-BOOT: init reached user space\n";
    int console = open("/dev/console", O_WRONLY);

    if (console < 0)
        console = 1;
    write(console, message, strlen(message));
    for (;;)
        pause();
}
