// SPDX-License-Identifier: BSD-2-Clause
@[translated]
module execinfofixture

#include "execinfo_compat.h"
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

fn C.assert(bool)
fn C.backtrace(&voidptr, i32) i32
fn C.backtrace_symbols(&voidptr, i32) &&char
fn C.backtrace_symbols_fd(&voidptr, i32, i32)
fn C.snprintf(&char, usize, &char, ...voidptr) i32
fn C.strstr(&char, &char) &char
fn C.free(voidptr)
fn C.pipe(&i32) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.puts(&char) i32
fn C.open(&char, i32, ...voidptr) i32
fn C.dup2(i32, i32) i32

@[noinline]
fn capture_and_check() {
    unsafe {
        mut frames := [32]voidptr{}
        count := C.backtrace(&frames[0], 32)
        C.assert(count >= 2)
        symbols := C.backtrace_symbols(&frames[0], count)
        C.assert(symbols != nil)
        for index := i32(0); index < count; index++ {
            mut address := [64]char{}
            C.snprintf(&address[0], 64, c'[0x%zx]', usize(frames[index]))
            C.assert(symbols[index] != nil)
            C.assert(C.strstr(symbols[index], &address[0]) != nil)
        }
        C.free(symbols)

        mut descriptors := [2]i32{}
        C.assert(C.pipe(&descriptors[0]) == 0)
        C.backtrace_symbols_fd(&frames[0], count, descriptors[1])
        C.assert(C.close(descriptors[1]) == 0)
        mut output := [8192]char{}
        length := C.read(descriptors[0], &output[0], 8192)
        C.assert(length > 0)
        C.assert(C.close(descriptors[0]) == 0)
        mut newlines := i32(0)
        for index := isize(0); index < length; index++ {
            if output[index] == 10 { newlines++ }
        }
        C.assert(newlines == count)
    }
}

@[export: 'main']
pub fn run() i32 {
    unsafe {
        $if execinfo_guest ? {
            // The fixture is init in the native harness; establish its stdio.
            mut descriptor := i32(-1)
            $if amd64 {
                descriptor = C.open(c'/dev/com1', C.O_WRONLY)
            } $else {
                descriptor = C.open(c'/dev/console', C.O_RDWR)
            }
            C.assert(descriptor >= 0)
            for target := i32(0); target < 3; target++ {
                C.assert(C.dup2(descriptor, target) == target)
            }
            if descriptor > 2 { C.assert(C.close(descriptor) == 0) }
        }
        C.assert(C.backtrace(nil, 8) == 0)
        C.assert(C.backtrace_symbols(nil, 8) == nil)
        capture_and_check()
        C.puts(c'execinfo compatibility: PASS')
        return 0
    }
}
