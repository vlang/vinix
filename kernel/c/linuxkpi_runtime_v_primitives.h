/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_RUNTIME_V_PRIMITIVES_H
#define VINIX_LINUXKPI_RUNTIME_V_PRIMITIVES_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
/* Native ABI declarations only; implementations and cursor access are V. */
#ifndef VINIX_V_RUNTIME
int vkr_arg_int(void *);
unsigned int vkr_arg_uint(void *);
long vkr_arg_long(void *);
unsigned long vkr_arg_ulong(void *);
long long vkr_arg_llong(void *);
size_t vkr_arg_size(void *);
ptrdiff_t vkr_arg_ptrdiff(void *);
void *vkr_arg_pointer(void *);
void vkr_nested_parse(void *, void *);
uint64_t vkr_pointer_hash(uint64_t, void *);
uint64_t vkr_resource_start(void *);
uint64_t vkr_resource_end(void *);
uint64_t vkr_resource_flags(void *);
struct vkr_pci_match {
    uint32_t vendor, device, subvendor, subdevice, class_code, class_mask;
    unsigned long data;
};
struct vkr_pci_match *vkr_tigerlake_table(size_t *);
#endif
void *vinix_linuxkpi_alloc_pages(size_t, bool);
#ifndef VINIX_V_RUNTIME
void *vkr_log_lifecycle(void);
void *vkr_log_ready(void);
void vkr_log_reinit(void *);
void vkr_log_complete(void *);
void vkr_log_wait(void *);
void *vkr_log_current_get(void);
void vkr_log_task_put(void *);
int vkr_log_create(void *(*)(void *), void *);
int vkr_log_join(void);
void vkr_log_exit(void);
void vkr_log_host_enter(void);
void vkr_log_host_leave(void);
int vkr_log_suppress(void);
int vkr_log_console(unsigned int);
void vkr_log_call_sink(void *, void *, void *);
void vkr_log_write(void *, size_t);
bool vkr_log_key(void *);
#endif
#ifdef VINIX_LINUXKPI_HOST_TEST
#define VINIX_LINUXKPI_LOG_HOST 1
#else
#define VINIX_LINUXKPI_LOG_HOST 0
#endif
void pthread_exit(void *);
void vinix_linuxkpi_host_logger_enter(void);
void vinix_linuxkpi_host_logger_leave(void);
#ifndef VINIX_V_RUNTIME
unsigned long long vinix_linuxkpi_log_caller(void);
#endif
void msleep(unsigned int);
#ifndef VINIX_V_RUNTIME
unsigned long __msecs_to_jiffies(unsigned int);
#endif
#endif
