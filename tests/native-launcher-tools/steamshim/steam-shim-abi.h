#ifndef VINIX_STEAM_SHIM_ABI_H
#define VINIX_STEAM_SHIM_ABI_H
/* SDK declarations and storage aliases only. */
#include <pwd.h>
#include <grp.h>
#include <utime.h>
#include <sys/stat.h>
#include <time.h>
typedef struct passwd vinix_steam_passwd;
typedef struct group vinix_steam_group;
typedef struct utimbuf vinix_steam_utimbuf;
typedef struct timespec vinix_steam_timespec;
#define vinix_steam_chown chown
#define vinix_steam_utime utime
#define vinix_steam_utimensat utimensat
#endif
