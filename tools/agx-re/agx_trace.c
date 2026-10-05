// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
/* Native Mach read, pthread initializer and typed dyld interposition ABI only. */
#include "agx_trace_v.h"
#include "agx_trace.h"
#include <pthread.h>
#ifndef VINIX_AGX_TRACE_TEST
#include <mach/mach.h>
#include <mach/mach_vm.h>
#define DYLD_INTERPOSE(replacement, replacee) \
    __attribute__((used)) static struct { const void *replacement; const void *replacee; } \
    _interpose_##replacee __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(uintptr_t)&replacement, (const void *)(uintptr_t)&replacee};
#else
#define DYLD_INTERPOSE(replacement, replacee)
#endif
static pthread_mutex_t trace_lock = PTHREAD_MUTEX_INITIALIZER;
void vagt_lock(void) { pthread_mutex_lock(&trace_lock); }
void vagt_unlock(void) { pthread_mutex_unlock(&trace_lock); }
#ifndef VINIX_AGX_TRACE_TEST
int vagt_read(const void *source, size_t bytes, void *destination, uint64_t *copied) {
    mach_vm_size_t count = 0;
    kern_return_t status = mach_vm_read_overwrite(mach_task_self(),
        (mach_vm_address_t)(uintptr_t)source, bytes,
        (mach_vm_address_t)(uintptr_t)destination, &count);
    *copied = count; return status;
}
#endif
void agx_trace_resource_hook_status(int installed) { vagt_resource_hook_status(installed); }
void agx_trace_record_resource(const void *object, uint64_t gpu_address, const void *cpu_address, size_t bytes) {
    vagt_record_resource((void *)object, gpu_address, (void *)cpu_address, bytes);
}
__attribute__((visibility("default"))) void agx_trace_marker(const char *phase) { vagt_marker((char *)phase); }
static void agx_IOGPUMetalCommandBufferStorageBeginKernelCommands(void *storage, const void *start) { vagt_begin_kernel(storage, (void *)start); }
static void agx_IOGPUMetalCommandBufferStorageEndKernelCommands(void *storage, const void *end) { vagt_end_kernel(storage, (void *)end); }
static void agx_IOGPUMetalCommandBufferStorageBeginSegment(void *storage, const void *start) { vagt_begin_segment(storage, (void *)start); }
static void agx_IOGPUMetalCommandBufferStorageEndSegment(void *storage) { vagt_end_segment(storage); }
static void agx_IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(void *storage, size_t bytes) { vagt_grow(storage, bytes); }
static kern_return_t agx_IOServiceOpen(io_service_t service, task_port_t owner, uint32_t type, io_connect_t *connection) { return vagt_service_open(service, owner, type, connection); }
static kern_return_t agx_IOConnectCallStructMethod(mach_port_t connection, uint32_t selector, const void *input, size_t input_bytes, void *output, size_t *output_bytes) {
    return vagt_struct_method(connection, selector, (void *)input, input_bytes, output, output_bytes);
}
static kern_return_t agx_IOConnectCallAsyncScalarMethod(mach_port_t connection, uint32_t selector, mach_port_t wake_port, uint64_t *reference,
        uint32_t reference_count, const uint64_t *input, uint32_t input_count, uint64_t *output, uint32_t *output_count) {
    return vagt_async_method(connection, selector, wake_port, reference, reference_count, (void *)input, input_count, output, output_count);
}
DYLD_INTERPOSE(agx_IOGPUMetalCommandBufferStorageBeginKernelCommands, IOGPUMetalCommandBufferStorageBeginKernelCommands)
DYLD_INTERPOSE(agx_IOGPUMetalCommandBufferStorageEndKernelCommands, IOGPUMetalCommandBufferStorageEndKernelCommands)
DYLD_INTERPOSE(agx_IOGPUMetalCommandBufferStorageBeginSegment, IOGPUMetalCommandBufferStorageBeginSegment)
DYLD_INTERPOSE(agx_IOGPUMetalCommandBufferStorageEndSegment, IOGPUMetalCommandBufferStorageEndSegment)
DYLD_INTERPOSE(agx_IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer, IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer)
DYLD_INTERPOSE(agx_IOServiceOpen, IOServiceOpen)
DYLD_INTERPOSE(agx_IOConnectCallStructMethod, IOConnectCallStructMethod)
DYLD_INTERPOSE(agx_IOConnectCallAsyncScalarMethod, IOConnectCallAsyncScalarMethod)
