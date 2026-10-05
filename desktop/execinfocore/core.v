// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// GCC's unwinder supplies musl's missing execinfo API. All scratch storage is
// borrowed synchronously; backtrace_symbols returns one caller-owned malloc.
@[translated]
module execinfocore

// ABI readonly-pointer: backtrace_symbols.buffer
// ABI readonly-pointer: backtrace_symbols_fd.buffer

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <unwind.h>
#include <errno.h>

@[typedef]
struct C.Dl_info {
    dli_fname &char
    dli_fbase voidptr
    dli_sname &char
    dli_saddr voidptr
}

struct C._Unwind_Context {}
@[typedef]
struct C._Unwind_Reason_Code {}
fn C._Static_assert(bool, &char)
fn C._Unwind_GetIP(&C._Unwind_Context) usize
fn C._Unwind_Backtrace(fn (&C._Unwind_Context, voidptr) C._Unwind_Reason_Code, voidptr) C._Unwind_Reason_Code
fn C.dladdr(voidptr, &C.Dl_info) i32
fn C.readlink(&char, &char, usize) isize
fn C.snprintf(&char, usize, &char, ...voidptr) i32
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.memset(voidptr, i32, usize) voidptr
fn C.write(i32, voidptr, usize) isize
fn C.__errno_location() &i32
fn C.__error() &i32

struct TraceState {
mut:
    buffer &voidptr
    size i32
    count i32
    skip i32
}

// Keep the upstream enum return type on the callback. V treats imported
// enums as opaque; its 32-bit integer representation is verified by the build.
fn reason(code i32) C._Unwind_Reason_Code {
    C._Static_assert(sizeof(C._Unwind_Reason_Code) == sizeof(i32), c'unwinder enum ABI')
    return unsafe { *(&C._Unwind_Reason_Code(&code)) }
}

fn trace_step(context &C._Unwind_Context, argument voidptr) C._Unwind_Reason_Code {
    unsafe {
        mut state := &TraceState(argument)
        instruction := C._Unwind_GetIP(context)
        if state.skip != 0 {
            state.skip--
            return reason(0) // _URC_NO_REASON
        }
        if instruction == 0 || state.count == state.size {
            return reason(5) // _URC_END_OF_STACK
        }
        state.buffer[state.count] = voidptr(instruction)
        state.count++
        return reason(0)
    }
}

@[export: 'backtrace'; noinline]
pub fn capture(buffer &voidptr, size i32) i32 {
    unsafe {
        if buffer == nil || size <= 0 { return 0 }
        mut state := TraceState{buffer: buffer, size: size, skip: 1}
        C._Unwind_Backtrace(trace_step, &state)
        return state.count
    }
}

fn format_frame(destination &char, capacity usize, address voidptr) i32 {
    $if execinfo_darwin ? {
        mut executable := [1024]char{}
        return unsafe { format_frame_with_buffer(destination, capacity, address, &executable[0], 1024) }
    } $else {
        mut executable := [4096]char{}
        return unsafe { format_frame_with_buffer(destination, capacity, address, &executable[0], 4096) }
    }
}

fn format_frame_with_buffer(destination &char, capacity usize, address voidptr, executable &char, executable_capacity usize) i32 {
    unsafe {
        mut information := C.Dl_info{}
        mut image := &char(c'/proc/self/exe')
        mut symbol := &char(nil)
        instruction := usize(address)
        mut offset := instruction
        length := C.readlink(c'/proc/self/exe', executable, executable_capacity - 1)
        if length > 0 && usize(length) < executable_capacity {
            executable[length] = 0
            image = &char(executable)
        }
        if C.dladdr(address, &information) != 0 {
            if information.dli_fname != nil && information.dli_fname[0] != 0 {
                image = &char(information.dli_fname)
            }
            if information.dli_sname != nil && information.dli_saddr != nil &&
                instruction >= usize(information.dli_saddr) {
                symbol = &char(information.dli_sname)
                offset = instruction - usize(information.dli_saddr)
            } else if information.dli_fbase != nil && instruction >= usize(information.dli_fbase) {
                offset = instruction - usize(information.dli_fbase)
            }
        }
        if symbol != nil {
            return C.snprintf(destination, capacity, c'%s(%s+0x%zx) [0x%zx]', image, symbol, offset, instruction)
        }
        return C.snprintf(destination, capacity, c'%s(+0x%zx) [0x%zx]', image, offset, instruction)
    }
}

@[export: 'backtrace_symbols']
pub fn symbols(buffer &voidptr, size i32) &&char {
    unsafe {
        if buffer == nil || size <= 0 { return nil }
        pointer_bytes := usize(size) * sizeof(&char)
        if pointer_bytes / sizeof(&char) != usize(size) { return nil }
        mut allocation_size := pointer_bytes
        for index := i32(0); index < size; index++ {
            length := format_frame(nil, 0, buffer[index])
            if length < 0 || usize(length) >= ~usize(0) - allocation_size { return nil }
            allocation_size += usize(length) + 1
        }
        result := &&char(C.malloc(allocation_size))
        if result == nil { return nil }
        mut text := &char(result) + pointer_bytes
        mut remaining := allocation_size - pointer_bytes
        for index := i32(0); index < size; index++ {
            length := format_frame(text, remaining, buffer[index])
            if length < 0 || usize(length) >= remaining {
                C.free(result)
                return nil
            }
            result[index] = text
            text += usize(length) + 1
            remaining -= usize(length) + 1
        }
        return result
    }
}

fn interrupted() bool {
    $if execinfo_darwin ? { return unsafe { *C.__error() == C.EINTR } }
    $else { return unsafe { *C.__errno_location() == C.EINTR } }
}

fn write_all(fd i32, text &char, length usize) {
    unsafe {
        mut cursor := &char(text)
        mut remaining := length
        for remaining != 0 {
            written := C.write(fd, cursor, remaining)
            if written > 0 {
                cursor += written
                remaining -= usize(written)
            } else if written < 0 && interrupted() { continue }
            else { return }
        }
    }
}

@[export: 'backtrace_symbols_fd']
pub fn symbols_fd(buffer &voidptr, size i32, fd i32) {
    unsafe {
        if buffer == nil || size <= 0 { return }
        for index := i32(0); index < size; index++ {
            mut line := [1024]char{}
            mut length := format_frame(&line[0], 1024, buffer[index])
            if length < 0 { continue }
            if usize(length) >= 1024 {
                length = C.snprintf(&line[0], 1024, c'/proc/self/exe(+0x%zx) [0x%zx]',
                    usize(buffer[index]), usize(buffer[index]))
            }
            if length > 0 { write_all(fd, &line[0], usize(length)) }
            write_all(fd, c'\n', 1)
        }
    }
}
