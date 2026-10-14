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
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/uio.h>
/* Declaration-only symbol alias: V cannot express connect's const pointer. */
extern int vinix_overlay_connect(int, void *, unsigned int) __asm__("connect");
extern int vinix_overlay_setsockopt(int, int, int, void *, unsigned int) __asm__("setsockopt");
extern ssize_t vinix_overlay_sendto(int, void *, size_t, int, void *, unsigned int) __asm__("sendto");
extern ssize_t vinix_overlay_sendmsg(int, void *, int) __asm__("sendmsg");
#endif
