/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_CACHE_STAT_ABI_H
#define VINIX_CACHE_STAT_ABI_H
#include <sys/stat.h>
#include <pwd.h>
typedef struct stat vinix_cache_stat;
typedef struct passwd vinix_cache_passwd;
#define vinix_cache_getpwnam getpwnam
#define vinix_cache_lstat lstat
#define vinix_cache_fstat fstat
#define vinix_cache_stat_path stat
#ifdef __APPLE__
#define vinix_cache_atime_nsec st_atimespec.tv_nsec
#define vinix_cache_mtime_nsec st_mtimespec.tv_nsec
#define vinix_cache_ctime_nsec st_ctimespec.tv_nsec
#else
#define vinix_cache_atime_nsec st_atim.tv_nsec
#define vinix_cache_mtime_nsec st_mtim.tv_nsec
#define vinix_cache_ctime_nsec st_ctim.tv_nsec
#endif
#endif
