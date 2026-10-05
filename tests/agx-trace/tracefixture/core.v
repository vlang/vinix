// SPDX-License-Identifier: GPL-2.0-only
// Independent typed driver model; all assertions follow the frozen C fixture.
@[translated]
module tracefixture
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
fn C.abort()
fn C.printf(&char, ...voidptr) i32
fn C.fprintf(voidptr, &char, ...voidptr) i32
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.strcpy(&char, &char) &char
fn C.strcmp(&char, &char) i32
fn C.setenv(&char, &char, i32) i32
fn C.unsetenv(&char) i32
@[c_extern] fn C.vagt_test_trylock() i32
@[c_extern] fn C.vagt_unlock()
@[c_extern] fn C.agx_trace_resource_hook_status(i32)
@[c_extern] fn C.agx_trace_marker(&char)
@[c_extern] fn C.agx_trace_record_resource(voidptr, u64, voidptr, usize)
@[c_extern] fn C.agx_IOServiceOpen(u32, u32, u32, &u32) i32
@[c_extern] fn C.agx_IOGPUMetalCommandBufferStorageBeginKernelCommands(voidptr, voidptr)
@[c_extern] fn C.agx_IOGPUMetalCommandBufferStorageEndKernelCommands(voidptr, voidptr)
@[c_extern] fn C.agx_IOGPUMetalCommandBufferStorageBeginSegment(voidptr, voidptr)
@[c_extern] fn C.agx_IOGPUMetalCommandBufferStorageEndSegment(voidptr)
@[c_extern] fn C.agx_IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(voidptr, usize)
@[c_extern] fn C.agx_IOConnectCallStructMethod(u32, u32, voidptr, usize, voidptr, &usize) i32
@[c_extern] fn C.agx_IOConnectCallAsyncScalarMethod(u32, u32, u32, &u64, u32, &u64, u32, &u64, &u32) i32
@[typedef] struct C.pthread_t {}
type ThreadFn = fn (voidptr) voidptr
fn C.pthread_create(&C.pthread_t, voidptr, ThreadFn, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
@[c_extern] fn C.vagt_marker_thread(voidptr) voidptr
@[c_extern] __global C.stderr voidptr
__global (
    owned usize
    allocations usize
    releases usize
    allocation_fail i32
    read_fail i32
    partial i32
    driver_calls i32
    actual_connection u32
    actual_selector u32
    actual_wake u32
    actual_references u32
    actual_inputs u32
    actual_input voidptr
    actual_output voidptr
    actual_input_bytes usize
)
fn check(value bool) { if !value { C.fprintf(C.stderr, c'AGX trace V fixture assertion failed\n'); C.abort() } }
@[export: 'vagt_test_malloc']
pub fn allocate(size usize) voidptr {
    unsafe { if allocation_fail != 0 { return nil }; p := C.malloc(size)
        if p != nil { owned++; allocations++ }; return p }
}
@[export: 'vagt_test_free']
pub fn release(p voidptr) {
    unsafe { if p != nil { check(owned > 0); owned--; releases++ }; C.free(p) }
}
@[export: 'vagt_read']
pub fn read(source voidptr, bytes usize, destination voidptr, copied &u64) i32 {
    unsafe { if read_fail != 0 { *copied = 0; return 22 }
        n := if partial != 0 && bytes > 1 { bytes - 1 } else { bytes }
        C.memcpy(destination, source, n); *copied = u64(n); return 0 }
}
fn driver() { check(C.vagt_test_trylock() == 0); C.vagt_unlock(); driver_calls++ }
@[export: 'IOGPUMetalCommandBufferStorageBeginKernelCommands']
pub fn begin_kernel(storage voidptr, start voidptr) { unsafe { check(storage != nil && start != nil) }; driver() }
@[export: 'IOGPUMetalCommandBufferStorageEndKernelCommands']
pub fn end_kernel(storage voidptr, _end voidptr) { unsafe { check(storage != nil) }; driver() }
@[export: 'IOGPUMetalCommandBufferStorageBeginSegment']
pub fn begin_segment(storage voidptr, start voidptr) { unsafe { check(storage != nil && start != nil) }; driver() }
@[export: 'IOGPUMetalCommandBufferStorageEndSegment']
pub fn end_segment(storage voidptr) { unsafe { check(storage != nil) }; driver() }
@[export: 'IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer']
pub fn grow(storage voidptr, bytes usize) {
    unsafe { check(storage != nil && bytes == 1234); driver()
        cursor := &u8(storage) + 16; limit := &u8(storage) + 32
        C.memcpy(&u8(storage) + 0x30, &cursor, sizeof(cursor)); C.memcpy(&u8(storage) + 0x38, &limit, sizeof(limit)) }
}
@[export: 'IOServiceOpen']
pub fn service_open(service u32, owner u32, kind u32, connection &u32) i32 {
    unsafe { check(owner == 23 && kind == 3); driver(); if connection != nil { *connection = service }
        return if service == 66 { -7 } else { 0 } }
}
@[export: 'IORegistryEntryGetName']
pub fn registry_name(service u32, name &char) i32 {
    C.strcpy(name, if service == 7 || service == 66 || service >= 200 { c'AGXAccelerator' } else { c'HID' }); return 0
}
@[export: 'IOObjectGetClass']
pub fn object_class(service u32, name &char) i32 {
    C.strcpy(name, if service == 8 { c'GPUUserClient' } else { c'UserClient' }); return 0
}
@[export: 'IOConnectCallStructMethod']
pub fn struct_method(connection u32, selector u32, input voidptr, input_bytes usize, output voidptr, output_bytes &usize) i32 {
    unsafe { driver(); actual_connection = connection; actual_selector = selector; actual_input = input
        actual_input_bytes = input_bytes; actual_output = output
        if output_bytes != nil { check(*output_bytes >= 4); *output_bytes = 4
            if output != nil { C.memcpy(output, c'\x01\x02\x03\x04', 4) } }; return 17 }
}
@[export: 'IOConnectCallAsyncScalarMethod']
pub fn async_method(connection u32, selector u32, wake u32, reference &u64, references u32,
    input &u64, inputs u32, output &u64, outputs &u32) i32 {
    unsafe { driver(); actual_connection = connection; actual_selector = selector; actual_wake = wake
        actual_references = references; actual_inputs = inputs; actual_input = input; actual_output = output
        check(reference != nil && reference[0] == u64(0x8877665544332211))
        if outputs != nil { check(*outputs >= 1); *outputs = 1; if output != nil { output[0] = u64(0x1122334455667788) } }; return -5 }
}
@[export: 'vagt_marker_thread']
pub fn marker_thread(_argument voidptr) voidptr {
    for i := 0; i < 100; i++ { C.agx_trace_resource_hook_status(1) }; return unsafe { nil }
}
@[export: 'main']
pub fn test(argc i32, argv &&char) i32 {
    unsafe {
        check(argc == 3 || argc == 4); check(C.setenv(c'AGX_TRACE_FILE', argv[1], 1) == 0)
        check(C.setenv(c'AGX_TRACE_RESOURCES', c'1', 1) == 0)
        check(C.setenv(c'AGX_TRACE_BYTES', if argc == 4 { argv[3] } else { c'8' }, 1) == 0)
        if C.strcmp(argv[2], c'all') == 0 { check(C.setenv(c'AGX_TRACE_ALL', c'1', 1) == 0) }
        else { check(C.unsetenv(c'AGX_TRACE_ALL') == 0) }
        mut connection := u32(0)
        check(C.agx_IOServiceOpen(7, 23, 3, &connection) == 0 && connection == 7)
        check(C.agx_IOServiceOpen(8, 23, 3, &connection) == 0 && connection == 8)
        check(C.agx_IOServiceOpen(99, 23, 3, &connection) == 0 && connection == 99)
        check(C.agx_IOServiceOpen(66, 23, 3, &connection) == -7 && connection == 66)
        check(C.agx_IOServiceOpen(99, 23, 3, nil) == 0)
        for service := u32(200); service < 266; service++ { check(C.agx_IOServiceOpen(service, 23, 3, &connection) == 0) }
        C.agx_trace_resource_hook_status(0); C.agx_trace_marker(c'phase-one')
        mut resource := [16]u8{}; for i := 0; i < 16; i++ { resource[i] = u8(i) }
        mut gpu := u64(0x100000)
        C.agx_trace_record_resource(&resource[0], gpu, &resource[0], sizeof(resource))
        C.agx_trace_record_resource(&resource[0], gpu, &resource[0], sizeof(resource))
        mut segment := [24]u8{}; C.memcpy(&segment[4], &gpu, sizeof(gpu)); C.memcpy(&segment[12], &gpu, sizeof(gpu))
        mut storage := [64]u8{}; end := &segment[0] + sizeof(segment); C.memcpy(&storage[0x30], &end, sizeof(end))
        C.agx_IOGPUMetalCommandBufferStorageBeginKernelCommands(&storage[0], &segment[0])
        C.agx_IOGPUMetalCommandBufferStorageEndKernelCommands(&storage[0], end); check(owned == 0)
        C.agx_IOGPUMetalCommandBufferStorageBeginSegment(&storage[0], &segment[0])
        C.agx_IOGPUMetalCommandBufferStorageEndSegment(&storage[0]); check(owned == 0)
        C.agx_IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(&storage[0], 1234)
        mut input := [u8(0), 1, 2, 3, 4, 5, 6, 7]!; mut output := [8]u8{}; mut output_bytes := usize(8)
        check(C.agx_IOConnectCallStructMethod(7, 0x100, &input[0], 8, &output[0], &output_bytes) == 17 && output_bytes == 4)
        check(actual_connection == 7 && actual_selector == 0x100 && actual_input == &input[0] && actual_input_bytes == 8 && actual_output == &output[0])
        output_bytes = 8; check(C.agx_IOConnectCallStructMethod(99, 0x101, &input[0], 8, &output[0], &output_bytes) == 17)
        output_bytes = 8; check(C.agx_IOConnectCallStructMethod(66, 0x101, &input[0], 8, &output[0], &output_bytes) == 17)
        check(C.agx_IOConnectCallStructMethod(8, 0x113, nil, 0, nil, nil) == 17)
        output_bytes = 8; check(C.agx_IOConnectCallStructMethod(265, 0x101, &input[0], 8, &output[0], &output_bytes) == 17)
        if argc == 4 && C.strcmp(argv[3], c'0') != 0 {
            mut large := [70000]u8{}; output_bytes = 8
            check(C.agx_IOConnectCallStructMethod(7, 0x105, &large[0], sizeof(large), &output[0], &output_bytes) == 17)
        }
        mut reference := u64(0x8877665544332211); mut in_value := u64(0xaabbccddeeff0011)
        mut out := u64(0); mut outputs := u32(2)
        check(C.agx_IOConnectCallAsyncScalarMethod(7, 0x112, 19, &reference, 1, &in_value, 1, &out, &outputs) == -5 && outputs == 1 && out == u64(0x1122334455667788))
        check(actual_wake == 19 && actual_references == 1 && actual_inputs == 1 && actual_input == &in_value && actual_output == &out)
        check(C.agx_IOConnectCallAsyncScalarMethod(99, 0x101, 19, &reference, 1, nil, 0, nil, nil) == -5)
        read_fail = 1; output_bytes = 8; check(C.agx_IOConnectCallStructMethod(7, 0x10a, &input[0], 8, &output[0], &output_bytes) == 17); check(owned == 0); read_fail = 0
        partial = 1; output_bytes = 8; check(C.agx_IOConnectCallStructMethod(7, 0x10b, &input[0], 8, &output[0], &output_bytes) == 17); check(owned == 0); partial = 0
        allocation_fail = 1; output_bytes = 8; check(C.agx_IOConnectCallStructMethod(7, 0x10c, &input[0], 8, &output[0], &output_bytes) == 17); check(owned == 0); allocation_fail = 0
        mut storages := [70][64]u8{}
        for i := 0; i < 70; i++ { C.agx_IOGPUMetalCommandBufferStorageBeginKernelCommands(&storages[i][0], &segment[0])
            C.agx_IOGPUMetalCommandBufferStorageEndKernelCommands(&storages[i][0], end); check(owned == 0) }
        for i := u64(0); i < 1026; i++ { C.agx_trace_record_resource(voidptr(usize(i + 1)), 0x200000 + i * 64, &resource[0], sizeof(resource)) }
        mut ignored := u64(0x200000 + 1025 * 64); C.memcpy(&segment[4], &ignored, 8); C.memcpy(&segment[12], &ignored, 8)
        C.agx_IOGPUMetalCommandBufferStorageBeginKernelCommands(&storage[0], &segment[0])
        C.agx_IOGPUMetalCommandBufferStorageEndKernelCommands(&storage[0], end); check(owned == 0)
        mut threads := [4]C.pthread_t{}
        for i := 0; i < 4; i++ { check(C.pthread_create(&threads[i], nil, C.vagt_marker_thread, nil) == 0) }
        for i := 0; i < 4; i++ { check(C.pthread_join(threads[i], nil) == 0) }
        C.agx_trace_marker(nil)
        check(owned == 0 && allocations == releases && driver_calls >= 160)
        C.printf(c'AGX TRACE HOST PASS allocations=%zu releases=%zu\n', allocations, releases)
        return 0
    }
}
