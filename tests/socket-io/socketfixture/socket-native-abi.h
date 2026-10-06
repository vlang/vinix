/* Native libc/socket ABI declarations; the independent workload is V. */
#ifndef VINIX_SOCKET_IO_NATIVE_ABI_H
#define VINIX_SOCKET_IO_NATIVE_ABI_H
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <unistd.h>
typedef union { struct cmsghdr align; char buffer[CMSG_SPACE(sizeof(int))]; } vso_control;
_Static_assert(sizeof(int)==4 && sizeof(long)==8 && sizeof(off_t)==8, "native descriptor/heap/offset widths");
_Static_assert(sizeof(socklen_t)==4 && sizeof(pthread_t)==8, "native address and thread widths");
_Static_assert(sizeof(vso_control)==24 && _Alignof(vso_control)==_Alignof(struct cmsghdr), "native ancillary storage and alignment");
void *vso_blocking_receive(void *);
void *vso_blocking_send(void *);
#endif
