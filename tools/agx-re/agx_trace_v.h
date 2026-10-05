/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_AGX_TRACE_V_H
#define VINIX_AGX_TRACE_V_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
_Static_assert(sizeof(size_t) == sizeof(uint64_t), "AGX trace address word ABI");
#ifndef VINIX_AGX_TRACE_TEST
#include <IOKit/IOKitLib.h>
#else
/* Independent host fixture supplies the same typed driver ABI. */
typedef uint32_t io_service_t, io_connect_t, task_port_t, mach_port_t;
typedef int32_t kern_return_t;
typedef char io_name_t[128];
kern_return_t IOServiceOpen(io_service_t, task_port_t, uint32_t, io_connect_t *);
kern_return_t IORegistryEntryGetName(io_service_t, char *);
kern_return_t IOObjectGetClass(io_service_t, char *);
kern_return_t IOConnectCallStructMethod(mach_port_t, uint32_t, const void *, size_t, void *, size_t *);
kern_return_t IOConnectCallAsyncScalarMethod(mach_port_t, uint32_t, mach_port_t, uint64_t *, uint32_t,
                                            const uint64_t *, uint32_t, uint64_t *, uint32_t *);
#endif
void IOGPUMetalCommandBufferStorageBeginKernelCommands(void *, const void *);
void IOGPUMetalCommandBufferStorageEndKernelCommands(void *, const void *);
void IOGPUMetalCommandBufferStorageBeginSegment(void *, const void *);
void IOGPUMetalCommandBufferStorageEndSegment(void *);
void IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(void *, size_t);
void vagt_lock(void);
void vagt_unlock(void);
int vagt_read(const void *, size_t, void *, uint64_t *);
#ifndef VINIX_V_RUNTIME
void vagt_resource_hook_status(int);
void vagt_record_resource(void *, uint64_t, void *, size_t);
void vagt_marker(char *);
void vagt_begin_kernel(void *, void *);
void vagt_end_kernel(void *, void *);
void vagt_begin_segment(void *, void *);
void vagt_end_segment(void *);
void vagt_grow(void *, size_t);
int vagt_service_open(uint32_t, uint32_t, uint32_t, uint32_t *);
int vagt_struct_method(uint32_t, uint32_t, void *, size_t, void *, size_t *);
int vagt_async_method(uint32_t, uint32_t, uint32_t, uint64_t *, uint32_t, void *, uint32_t, uint64_t *, uint32_t *);
#endif
#endif
