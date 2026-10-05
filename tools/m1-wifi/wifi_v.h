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
/* Opaque native terminal/stat fields and errno/volatile access only. */
static struct termios vkw_saved_terminal;
static inline int vkw_terminal_save(int fd) { return tcgetattr(fd, &vkw_saved_terminal); }
static inline int vkw_terminal_hide(int fd) { struct termios state=vkw_saved_terminal; state.c_lflag &= (tcflag_t)~ECHO; return tcsetattr(fd,TCSANOW,&state); }
static inline int vkw_terminal_restore(int fd) { return tcsetattr(fd,TCSANOW,&vkw_saved_terminal); }
static inline int vkw_errno(void) { return errno; }
static inline void vkw_set_errno(int value) { errno=value; }
static inline void vkw_wipe_byte(void *p) { *(volatile uint8_t *)p=0; }
static inline FILE *vkw_stderr(void) { return stderr; }
static inline int vkw_file_stat(FILE *file, int64_t *size, int *regular) { struct stat st; int rc=fstat(fileno(file),&st); if(!rc) { *size=st.st_size; *regular=S_ISREG(st.st_mode); } return rc; }
#endif
