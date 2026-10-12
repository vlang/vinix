/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_IOS_COPY_ABI_H
#define VINIX_IOS_COPY_ABI_H
#include <stdint.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <time.h>
typedef struct stat vinix_ios_file_stat;
#define vinix_ios_file_stat_call stat
#endif
