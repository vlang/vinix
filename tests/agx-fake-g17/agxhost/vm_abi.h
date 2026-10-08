#ifndef VINIX_AGX_VM_ABI_H
#define VINIX_AGX_VM_ABI_H
/* SDK types/constants only. PTY, QMP, shutdown and marker algorithms live in V. */
#include <stdint.h>
#include <stddef.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#ifdef __APPLE__
#include <util.h>
#else
#include <pty.h>
#endif
typedef struct sockaddr_in vinix_agx_inet_address;
typedef struct sockaddr_un vinix_agx_unix_address;
typedef struct in_addr vinix_agx_ip_address;
#define VINIX_AGX_UNIX_PATH_SIZE sizeof(((struct sockaddr_un *)0)->sun_path)
_Static_assert(sizeof(pid_t) == sizeof(int32_t), "PTY pid width");
_Static_assert(sizeof(socklen_t) == sizeof(uint32_t), "socket length width");
_Static_assert(sizeof(int) == sizeof(int32_t), "wait status width");
static volatile sig_atomic_t vinix_agx_vm_interrupted;
#define VINIX_AGX_VM_INTERRUPTED (&vinix_agx_vm_interrupted)
#endif
