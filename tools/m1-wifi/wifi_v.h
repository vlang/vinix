/* SPDX-License-Identifier: ISC */
#ifndef VINIX_WIFI_CTL_V_H
#define VINIX_WIFI_CTL_V_H
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include "brcm_m1.h"
_Static_assert(BW_STATUS_SIZE == 256, "V status buffer ABI");
_Static_assert(BW_JOIN_SIZE == 104, "V join buffer ABI");
_Static_assert(BW_UPLOAD_SIZE == 4112, "V upload buffer ABI");
_Static_assert(BW_NETWORK_MAX == 32 && BW_NETWORK_ENTRY_SIZE == 48 &&
               BW_NETWORKS_SIZE == 1552, "V network buffer ABI");
/* Native SDK declarations and a volatile byte view; algorithms live in V. */
struct vkw_volatile_byte_view { volatile uint8_t value; };
_Static_assert(sizeof(struct vkw_volatile_byte_view) == 1 &&
               _Alignof(struct vkw_volatile_byte_view) == 1, "volatile byte ABI");
#if defined(__APPLE__)
#define vkw_native_errno __error
#else
#define vkw_native_errno __errno_location
#endif
int vkw_terminal_save(int);
int vkw_terminal_hide(int);
int vkw_terminal_restore(int);
int vkw_errno(void);
void vkw_set_errno(int);
void vkw_wipe_byte(void *);
FILE *vkw_stderr(void);
int vkw_file_stat(FILE *, int64_t *, int *);
#endif
