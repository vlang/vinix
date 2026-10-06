/* SPDX-License-Identifier: ISC */
#ifndef VINIX_WIFI_CTL_NATIVE_ABI_H
#define VINIX_WIFI_CTL_NATIVE_ABI_H
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include "brcm_m1.h"
typedef const char wifi_ctl_const_char;
typedef const struct termios wifi_ctl_const_termios;
typedef const struct timespec wifi_ctl_const_timespec;
int test_program_main(int, char **);
void wifi_ctl_verify_exit(void);
_Static_assert(sizeof(void *) == 8 && sizeof(unsigned long) == 8, "native LP64 variadic arguments");
#endif
