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
typedef struct sigaction vwh_sigaction;
_Static_assert(sizeof(sig_atomic_t) == sizeof(int32_t) && __atomic_always_lock_free(4, 0),
               "Original signal-safe and shared-damage 32-bit storage");
int vwh_running(void);
void vwh_set_running(int);
int vwh_errno(void);
void vwh_install_signals(void);
void vwh_install_x_error(void);
void vwh_damage_store(void *, uint32_t);
int vinix_wine_host_main(int, char **);
void vinix_wine_host_stop(int);
int vinix_wine_host_x_error(Display *, XErrorEvent *);
#endif
