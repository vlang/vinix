#ifndef VINIX_DOTA_STAT_ABI_H
#define VINIX_DOTA_STAT_ABI_H
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>
typedef struct stat vinix_dota_stat;
#ifdef __APPLE__
#define vinix_dota_atime_nsec st_atimespec.tv_nsec
#define vinix_dota_mtime_nsec st_mtimespec.tv_nsec
#else
#define vinix_dota_atime_nsec st_atim.tv_nsec
#define vinix_dota_mtime_nsec st_mtim.tv_nsec
#endif
#endif
