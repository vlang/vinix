// SPDX-License-Identifier: GPL-2.0-only
// Check Mach output ownership and dyld's actual C wrapper pointers natively.
@[translated]
module nativefixture
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <IOKit/IOKitLib.h>
fn C.abort()
fn C.printf(&char, ...voidptr) i32
fn C.memcmp(voidptr, voidptr, usize) i32
@[c_extern] fn C.vagt_read(voidptr, usize, voidptr, &u64) i32
@[c_extern] fn C.vagt_lock()
@[c_extern] fn C.vagt_unlock()
@[c_extern] fn C.vagt_interpose_table_address() voidptr
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
fn C.IOServiceOpen(u32, u32, u32, &u32) i32
fn C.IOConnectCallStructMethod(u32, u32, voidptr, usize, voidptr, &usize) i32
fn C.IOConnectCallAsyncScalarMethod(u32, u32, u32, &u64, u32, &u64, u32, &u64, &u32) i32
struct Interpose { replacement voidptr, replacee voidptr }
fn check(value bool) { if !value { C.abort() } }
@[export: 'main']
pub fn test() i32 {
    unsafe {
        mut source := [32]u8{}; mut output := [32]u8{}
        for i := 0; i < 32; i++ { source[i] = u8(i + 17) }
        mut copied := u64(0)
        check(C.vagt_read(&source[0], sizeof(source), &output[0], &copied) == 0)
        check(copied == 32 && C.memcmp(&source[0], &output[0], sizeof(source)) == 0)
        copied = 1234
        check(C.vagt_read(voidptr(usize(1)), 32, &output[0], &copied) != 0 && copied == 0)
        C.vagt_lock(); C.vagt_unlock(); C.vagt_lock(); C.vagt_unlock()
        expected := [
            Interpose{voidptr(C.agx_IOGPUMetalCommandBufferStorageBeginKernelCommands), voidptr(C.IOGPUMetalCommandBufferStorageBeginKernelCommands)},
            Interpose{voidptr(C.agx_IOGPUMetalCommandBufferStorageEndKernelCommands), voidptr(C.IOGPUMetalCommandBufferStorageEndKernelCommands)},
            Interpose{voidptr(C.agx_IOGPUMetalCommandBufferStorageBeginSegment), voidptr(C.IOGPUMetalCommandBufferStorageBeginSegment)},
            Interpose{voidptr(C.agx_IOGPUMetalCommandBufferStorageEndSegment), voidptr(C.IOGPUMetalCommandBufferStorageEndSegment)},
            Interpose{voidptr(C.agx_IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer), voidptr(C.IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer)},
            Interpose{voidptr(C.agx_IOServiceOpen), voidptr(C.IOServiceOpen)},
            Interpose{voidptr(C.agx_IOConnectCallStructMethod), voidptr(C.IOConnectCallStructMethod)},
            Interpose{voidptr(C.agx_IOConnectCallAsyncScalarMethod), voidptr(C.IOConnectCallAsyncScalarMethod)},
        ]!
        actual := &Interpose(C.vagt_interpose_table_address())
        check(usize(actual) % 8 == 0 && sizeof(Interpose) == 16)
        for i := 0; i < 8; i++ {
            check(actual[i].replacement == expected[i].replacement && actual[i].replacee == expected[i].replacee)
        }
        C.printf(c'AGX NATIVE MACH/DYLD PASS\n'); return 0
    }
}
