#ifndef VINIX_OVERLAY_RENAME_NATIVE_ABI_H
#define VINIX_OVERLAY_RENAME_NATIVE_ABI_H
#include <errno.h>
#include <sys/mount.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <sys/statfs.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <grp.h>
/* Declaration-only symbol alias: V cannot express connect's const pointer. */
extern int vinix_overlay_connect(int, void *, unsigned int) __asm__("connect");
#endif
