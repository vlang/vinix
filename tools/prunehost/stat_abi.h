/* SPDX-License-Identifier: GPL-2.0-only */
/* Declaration-only aliases for the host SDK's stat fields. */
#ifndef VINIX_PRUNE_STAT_ABI_H
#define VINIX_PRUNE_STAT_ABI_H
#include <sys/stat.h>
typedef struct stat vinix_prune_stat;
#define vinix_prune_stat_read stat
#define vinix_prune_lstat_read lstat
#ifdef __APPLE__
#define vinix_prune_atime_ns st_atimespec.tv_nsec
#define vinix_prune_mtime_ns st_mtimespec.tv_nsec
#define vinix_prune_ctime_ns st_ctimespec.tv_nsec
#else
#define vinix_prune_atime_ns st_atim.tv_nsec
#define vinix_prune_mtime_ns st_mtim.tv_nsec
#define vinix_prune_ctime_ns st_ctim.tv_nsec
#endif
#endif
