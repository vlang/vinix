/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_WINE_HOST_V_ABI_H
#define VINIX_WINE_HOST_V_ABI_H
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/Xatom.h>
#include <X11/extensions/XTest.h>
#include <X11/extensions/Xdamage.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
int vwh_running(void);
void vwh_set_running(int);
int vwh_errno(void);
void vwh_install_signals(void);
void vwh_install_x_error(void);
void vwh_damage_store(void *, uint32_t);
int vinix_wine_host_main(int, char **);
#endif
