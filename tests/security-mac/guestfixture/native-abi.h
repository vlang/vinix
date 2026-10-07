/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native declarations/layouts only; independent policy and ownership are V. */
#ifndef VINIX_MAC_POLICY_FIXTURE_NATIVE_ABI_H
#define VINIX_MAC_POLICY_FIXTURE_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <elf.h>
#include <pthread.h>
#include <sys/file.h>
#include <sys/inotify.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <unistd.h>
typedef unsigned long long mac_ull;
typedef long long mac_ll;
struct mac_sched_attr {
 uint32_t size, policy;
 uint64_t flags;
 int32_t nice;
 uint32_t priority;
 uint64_t runtime, deadline, period;
};
typedef union mac_cmsg_storage {
 struct cmsghdr align;
 unsigned char bytes[CMSG_SPACE(sizeof(int))];
} mac_cmsg_storage;
_Static_assert(sizeof(int)==4 && sizeof(unsigned)==4 && sizeof(pid_t)==4 && sizeof(id_t)==4 && sizeof(mode_t)==4 && sizeof(dev_t)==8, "original native scalar words");
_Static_assert(sizeof(unsigned long)==8 && sizeof(long)==8 && sizeof(uintptr_t)==8 && sizeof(size_t)==8 && sizeof(ssize_t)==8 && sizeof(off_t)==8, "original LP64 words");
_Static_assert(sizeof(mac_ull)==8 && sizeof(mac_ll)==8 && _Alignof(mac_ull)==8 && _Alignof(mac_ll)==8 && (mac_ll)-1 < 0 && (mac_ull)-1 > 0, "original variadic long-long nominal words");
_Static_assert(sizeof(pthread_t)==8 && _Alignof(pthread_t)==8, "native joined thread handle");
_Static_assert(sizeof(Elf64_Ehdr)==64 && sizeof(Elf64_Phdr)==56 && _Alignof(Elf64_Ehdr)==8 && _Alignof(Elf64_Phdr)==8, "original interpreter image records");
_Static_assert(sizeof(mac_cmsg_storage)==24 && _Alignof(mac_cmsg_storage)==4 && offsetof(mac_cmsg_storage,bytes)==0, "original aligned ancillary union");
_Static_assert(sizeof(struct msghdr)==56 && sizeof(struct cmsghdr)==16 && sizeof(struct iovec)==16 && _Alignof(struct msghdr)==8 && _Alignof(struct cmsghdr)==4 && _Alignof(struct iovec)==8, "original ancillary records");
_Static_assert(sizeof(((struct msghdr *)0)->msg_iovlen)==4 && sizeof(((struct msghdr *)0)->msg_controllen)==4 && sizeof(((struct cmsghdr *)0)->cmsg_len)==4, "native ancillary narrow fields");
_Static_assert(sizeof(struct mac_sched_attr)==48 && _Alignof(struct mac_sched_attr)==8 && offsetof(struct mac_sched_attr,runtime)==24, "original scheduler record");
_Static_assert(sizeof(cpu_set_t)==128 && _Alignof(cpu_set_t)==8 && sizeof(struct rlimit)==16 && _Alignof(struct rlimit)==8, "native affinity/limit records");
void *vinix_mac_policy_blocked_thread(void *);
void *vinix_mac_policy_close_exec_descriptor(void *);
#endif
