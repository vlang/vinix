// SPDX-License-Identifier: GPL-2.0-only
// Native header primitives and actual dyld callback addresses for AGX tracing.
@[translated]
module nativecore

#include <pthread.h>
#include <stdint.h>
@[typedef]
struct C.pthread_mutex_t {}
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
@[c_extern] fn C.agx_IOGPUMetalCommandBufferStorageBeginKernelCommands(voidptr, voidptr)
@[c_extern] fn C.agx_IOGPUMetalCommandBufferStorageEndKernelCommands(voidptr, voidptr)
@[c_extern] fn C.agx_IOGPUMetalCommandBufferStorageBeginSegment(voidptr, voidptr)
@[c_extern] fn C.agx_IOGPUMetalCommandBufferStorageEndSegment(voidptr)
@[c_extern] fn C.agx_IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(voidptr, usize)
@[c_extern] fn C.agx_IOServiceOpen(u32, u32, u32, &u32) i32
@[c_extern] fn C.agx_IOConnectCallStructMethod(u32, u32, voidptr, usize, voidptr, &usize) i32
@[c_extern] fn C.agx_IOConnectCallAsyncScalarMethod(u32, u32, u32, &u64, u32, &u64, u32, &u64, &u32) i32
@[c_extern] fn C.IOGPUMetalCommandBufferStorageBeginKernelCommands(voidptr, voidptr)
@[c_extern] fn C.IOGPUMetalCommandBufferStorageEndKernelCommands(voidptr, voidptr)
@[c_extern] fn C.IOGPUMetalCommandBufferStorageBeginSegment(voidptr, voidptr)
@[c_extern] fn C.IOGPUMetalCommandBufferStorageEndSegment(voidptr)
@[c_extern] fn C.IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(voidptr, usize)
@[cinit]
__global trace_mutex C.pthread_mutex_t = C.PTHREAD_MUTEX_INITIALIZER

@[c_extern] fn C.vagt_resource_hook_status(i32)
@[c_extern] fn C.vagt_record_resource(voidptr, u64, voidptr, usize)
@[c_extern] fn C.vagt_marker(&char)
@[c_extern] fn C.vagt_begin_kernel(voidptr, voidptr)
@[c_extern] fn C.vagt_end_kernel(voidptr, voidptr)
@[c_extern] fn C.vagt_begin_segment(voidptr, voidptr)
@[c_extern] fn C.vagt_end_segment(voidptr)
@[c_extern] fn C.vagt_grow(voidptr, usize)
@[c_extern] fn C.vagt_service_open(u32, u32, u32, &u32) i32
@[c_extern] fn C.vagt_struct_method(u32, u32, voidptr, usize, voidptr, &usize) i32
@[c_extern] fn C.vagt_async_method(u32, u32, u32, &u64, u32, voidptr, u32, &u64, &u32) i32

@[export: 'vagt_lock']
pub fn lock() { unsafe { C.pthread_mutex_lock(&trace_mutex) } }
@[export: 'vagt_unlock']
pub fn unlock() { unsafe { C.pthread_mutex_unlock(&trace_mutex) } }
$if agx_trace_fixture ? {
    // The independent driver fixture verifies forwarding happens unlocked.
    fn C.pthread_mutex_trylock(&C.pthread_mutex_t) i32
    @[export: 'vagt_test_trylock']
    pub fn trylock() i32 { return unsafe { C.pthread_mutex_trylock(&trace_mutex) } }
} $else {
    #include <mach/mach.h>
    #include <mach/mach_vm.h>
    #include <IOKit/IOKitLib.h>
    fn C.mach_task_self() u32
    fn C.mach_vm_read_overwrite(u32, u64, u64, u64, &u64) i32
    // ABI readonly: vagt_read.source
    @[export: 'vagt_read']
    pub fn read(source voidptr, bytes usize, destination voidptr, copied &u64) i32 {
        unsafe {
            mut count := u64(0)
            status := C.mach_vm_read_overwrite(C.mach_task_self(), u64(usize(source)),
                u64(bytes), u64(usize(destination)), &count)
            *copied = count
            return status
        }
    }
}
@[export: 'agx_trace_resource_hook_status']
pub fn resource_hook_status(installed i32) { C.vagt_resource_hook_status(installed) }
// ABI readonly: agx_trace_record_resource.object
// ABI readonly: agx_trace_record_resource.cpu_address
@[export: 'agx_trace_record_resource']
pub fn record_resource(object voidptr, gpu_address u64, cpu_address voidptr, bytes usize) {
    C.vagt_record_resource(object, gpu_address, cpu_address, bytes)
}
// ABI readonly: agx_trace_marker.phase
@[export: 'agx_trace_marker']
pub fn marker(phase &char) { C.vagt_marker(phase) }
@[export: 'agx_IOGPUMetalCommandBufferStorageBeginKernelCommands']
// ABI readonly: agx_IOGPUMetalCommandBufferStorageBeginKernelCommands.start
pub fn begin_kernel(storage voidptr, start voidptr) { C.vagt_begin_kernel(storage, start) }
@[export: 'agx_IOGPUMetalCommandBufferStorageEndKernelCommands']
// ABI readonly: agx_IOGPUMetalCommandBufferStorageEndKernelCommands.end
pub fn end_kernel(storage voidptr, end voidptr) { C.vagt_end_kernel(storage, end) }
@[export: 'agx_IOGPUMetalCommandBufferStorageBeginSegment']
// ABI readonly: agx_IOGPUMetalCommandBufferStorageBeginSegment.start
pub fn begin_segment(storage voidptr, start voidptr) { C.vagt_begin_segment(storage, start) }
@[export: 'agx_IOGPUMetalCommandBufferStorageEndSegment']
pub fn end_segment(storage voidptr) { C.vagt_end_segment(storage) }
@[export: 'agx_IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer']
pub fn grow(storage voidptr, bytes usize) { C.vagt_grow(storage, bytes) }
@[export: 'agx_IOServiceOpen']
pub fn service_open(service u32, owner u32, kind u32, connection &u32) i32 {
    return C.vagt_service_open(service, owner, kind, connection)
}
@[export: 'agx_IOConnectCallStructMethod']
// ABI readonly: agx_IOConnectCallStructMethod.input
pub fn struct_method(connection u32, selector u32, input voidptr, input_bytes usize,
    output voidptr, output_bytes &usize) i32 {
    return C.vagt_struct_method(connection, selector, input, input_bytes, output, output_bytes)
}
@[export: 'agx_IOConnectCallAsyncScalarMethod']
// ABI readonly: agx_IOConnectCallAsyncScalarMethod.input
pub fn async_method(connection u32, selector u32, wake_port u32, reference &u64,
    reference_count u32, input &u64, input_count u32, output &u64, output_count &u32) i32 {
    return C.vagt_async_method(connection, selector, wake_port, reference, reference_count,
        input, input_count, output, output_count)
}

$if !agx_trace_fixture ? {
    // The dyld ABI is a permanent sequence of replacement/replacee pointers.
    // Register C export wrappers, whose addresses differ from native V bodies.
    struct Interpose { replacement voidptr, replacee voidptr }
    fn C.IOServiceOpen(u32, u32, u32, &u32) i32
    fn C.IOConnectCallStructMethod(u32, u32, voidptr, usize, voidptr, &usize) i32
    fn C.IOConnectCallAsyncScalarMethod(u32, u32, u32, &u64, u32, &u64, u32, &u64, &u32) i32
    @[export: 'vagt_interpose_table']
    @[cinit]
    @[_linker_section: '__DATA,__interpose']
    __global interpose_table = [
        Interpose{voidptr(C.agx_IOGPUMetalCommandBufferStorageBeginKernelCommands), voidptr(C.IOGPUMetalCommandBufferStorageBeginKernelCommands)},
        Interpose{voidptr(C.agx_IOGPUMetalCommandBufferStorageEndKernelCommands), voidptr(C.IOGPUMetalCommandBufferStorageEndKernelCommands)},
        Interpose{voidptr(C.agx_IOGPUMetalCommandBufferStorageBeginSegment), voidptr(C.IOGPUMetalCommandBufferStorageBeginSegment)},
        Interpose{voidptr(C.agx_IOGPUMetalCommandBufferStorageEndSegment), voidptr(C.IOGPUMetalCommandBufferStorageEndSegment)},
        Interpose{voidptr(C.agx_IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer), voidptr(C.IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer)},
        Interpose{voidptr(C.agx_IOServiceOpen), voidptr(C.IOServiceOpen)},
        Interpose{voidptr(C.agx_IOConnectCallStructMethod), voidptr(C.IOConnectCallStructMethod)},
        Interpose{voidptr(C.agx_IOConnectCallAsyncScalarMethod), voidptr(C.IOConnectCallAsyncScalarMethod)},
    ]!
    // This borrowed view lets native ABI checks inspect dyld's real table.
    // The compiler also needs these foreign addresses referenced by a body
    // when discovering declarations used only by a cinit data initializer.
    @[export: 'vagt_interpose_table_address']
    pub fn table_address() voidptr {
        _ = C.IOGPUMetalCommandBufferStorageBeginKernelCommands
        _ = C.IOGPUMetalCommandBufferStorageEndKernelCommands
        _ = C.IOGPUMetalCommandBufferStorageBeginSegment
        _ = C.IOGPUMetalCommandBufferStorageEndSegment
        _ = C.IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer
        return unsafe { &interpose_table[0] }
    }
}
