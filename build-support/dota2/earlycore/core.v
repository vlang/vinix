// SPDX-License-Identifier: GPL-2.0-or-later
// Load the process-lifetime Steam client before Source 2 publishes its symbols.
@[translated]
module earlycore

#include "early-client-abi.h"

fn C.getenv(&char) &char
fn C.unsetenv(&char) i32
fn C.dlopen(&char, i32) voidptr
fn C.dlerror() &char
fn C.write(i32, voidptr, usize) isize
fn C._exit(i32)

fn emit(text &char) {
    unsafe {
        mut length := usize(0)
        for text[length] != 0 { length++ }
        C.write(2, text, length)
    }
}

fn init() {
    unsafe {
        requested := C.getenv(c'VINIX_DOTA2_EARLY_STEAMCLIENT')
        if requested == nil || requested[0] == 0 { return }
        // No libc environment pointer survives marker removal or dlopen.
        mut filename := [4096]char{}
        mut length := usize(0)
        for requested[length] != 0 && length < 4095 {
            filename[length] = requested[length]
            length++
        }
        filename[length] = 0
        too_long := requested[length] != 0
        if C.unsetenv(c'VINIX_DOTA2_EARLY_STEAMCLIENT') != 0 ||
            too_long || filename[0] != char(`/`) {
            emit(c'dota2: invalid early Steam client path or environment\n')
            C._exit(127)
            return
        }
        // NOW | LOCAL | NODELETE. The reference deliberately stays alive.
        if C.dlopen(&filename[0], 2 | 0x1000) == nil {
            emit(c"dota2: could not load Steam's Linux client: ")
            error := C.dlerror()
            emit(if error != nil { error } else { c'dlopen returned NULL without dlerror' })
            emit(c'\n')
            C._exit(127)
            return
        }
        emit(c'VINIX-DOTA2-EARLY-CLIENT: loaded actual steamclient locally before main\n')
    }
}
