/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_MODULE_FS_ABI_H
#define VINIX_MODULE_FS_ABI_H
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>
typedef struct stat vinix_module_stat;
#define vinix_module_stat_path stat
#ifdef __APPLE__
#define vinix_module_atime_nsec st_atimespec.tv_nsec
#define vinix_module_mtime_nsec st_mtimespec.tv_nsec
#else
#define vinix_module_atime_nsec st_atim.tv_nsec
#define vinix_module_mtime_nsec st_mtim.tv_nsec
#endif
#endif
