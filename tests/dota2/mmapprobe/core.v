// SPDX-License-Identifier: GPL-2.0-or-later
// The original real-translator mmap assertions, retaining original failure lines.
@[translated]
module mmapprobe

#include "mmap-probe-abi.h"
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mmap64(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.__errno_location() &i32
fn C.printf(&char, ...voidptr) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32

const anon_private = i32(0x22)
const map32 = i32(0x40)
const fixed = i32(0x10)
const noreplace = i32(0x100000)
const rw = i32(3)

fn expect(condition bool, line i32) bool {
    if !condition {
        unsafe { C.printf(c'VINIX-DOTA2-MMAP32-FAIL: line=%d errno=%d\n', line, *C.__errno_location()); C.fflush(nil) }
    }
    return condition
}
fn low(value voidptr, length usize) bool {
    start := usize(value)
    return value != voidptr(usize(-1)) && start >= 0x10000 && start <= 0x80000000 - length
}
fn separate(left voidptr, left_length usize, right voidptr, right_length usize) bool {
    a := usize(left); b := usize(right)
    return a + left_length <= b || b + right_length <= a
}

@[export: 'main']
pub fn run() i32 {
    unsafe {
        C.puts(c'VINIX-DOTA2-MMAP32-START')
        if !expect(C.mmap(nil, 0, rw, anon_private | map32, -1, 0) == voidptr(usize(-1)), 42) { return 1 }
        if !expect(*C.__errno_location() == 22, 43) { return 1 }
        if !expect(C.mmap(nil, usize(-1), rw, anon_private | map32, -1, 0) == voidptr(usize(-1)), 44) { return 1 }
        if !expect(*C.__errno_location() == 12, 45) { return 1 }
        if !expect(C.mmap(voidptr(usize(0x10000)), 0x80000000, 0, anon_private | map32, -1, 0) == voidptr(usize(-1)), 46) { return 1 }
        if !expect(*C.__errno_location() == 12, 47) { return 1 }
        if !expect(C.mmap64(nil, 0x80000000, 0, anon_private | map32, -1, 0) == voidptr(usize(-1)), 48) { return 1 }
        if !expect(*C.__errno_location() == 12, 49) { return 1 }
    
        first := C.mmap(nil, 4096, rw, anon_private | map32, -1, 0)
        if !expect(low(first, 4096), 52) { return 1 }
        (&u8(first))[0] = 0x5a
        second := C.mmap64(nil, 4096, rw, anon_private | map32, -1, 0)
        if !expect(low(second, 4096) && second != first, 55) { return 1 }
        (&u8(second))[0] = 0x37
        if !expect((&u8(first))[0] == 0x5a, 57) { return 1 }
        
        if !expect(C.mmap(first, 4096, rw, anon_private | noreplace, -1, 0) == voidptr(usize(-1)), 61) { return 1 }
        if !expect(*C.__errno_location() == 17 && (&u8(first))[0] == 0x5a, 62) { return 1 }
        if !expect(C.mmap64(second, 4096, rw, anon_private | noreplace, -1, 0) == voidptr(usize(-1)), 63) { return 1 }
        if !expect(*C.__errno_location() == 17 && (&u8(second))[0] == 0x37, 64) { return 1 }
    
        hint := C.mmap(voidptr(usize(0x20000001)), 4096, rw, anon_private | map32, -1, 0)
        if !expect(hint == voidptr(usize(0x20000000)), 67) { return 1 }
        (&u8(hint))[0] = 0x6b
        collision := C.mmap(hint, 4096, rw, anon_private | map32, -1, 0)
        if !expect(low(collision, 4096) && collision != hint, 70) { return 1 }
        if !expect(separate(collision, 4096, first, 4096), 71) { return 1 }
        if !expect(separate(collision, 4096, second, 4096), 72) { return 1 }
        (&u8(collision))[0] = 0x42
        if !expect((&u8(hint))[0] == 0x6b, 74) { return 1 }
        overflow_hint := C.mmap(voidptr(usize(0x7ffff000)), 8192, rw, anon_private | map32, -1, 0)
        if !expect(low(overflow_hint, 8192) && overflow_hint != voidptr(usize(0x7ffff000)), 76) { return 1 }
        if !expect(separate(overflow_hint, 8192, first, 4096), 77) { return 1 }
        if !expect(separate(overflow_hint, 8192, second, 4096), 78) { return 1 }
        if !expect(separate(overflow_hint, 8192, hint, 4096), 79) { return 1 }
        if !expect(separate(overflow_hint, 8192, collision, 4096), 80) { return 1 }
        (&u8(overflow_hint))[0] = 0x95
        (&u8(overflow_hint))[8191] = 0x28
        if !expect((&u8(first))[0] == 0x5a && (&u8(second))[0] == 0x37, 83) { return 1 }
        if !expect((&u8(hint))[0] == 0x6b && (&u8(collision))[0] == 0x42, 84) { return 1 }
        boundary := C.mmap(voidptr(usize(0x7fff0000)), 65536, rw, anon_private | map32, -1, 0)
        if !expect(boundary == voidptr(usize(0x7fff0000)), 86) { return 1 }
    
        
        high := C.mmap(voidptr(usize(0x90000000)), 4096, rw, anon_private | noreplace | map32, -1, 0)
        if !expect(high == voidptr(usize(0x90000000)), 92) { return 1 }
        (&u8(high))[0] = 0x79
        if !expect(C.mmap(high, 4096, rw, anon_private | noreplace | map32, -1, 0) == voidptr(usize(-1)), 94) { return 1 }
        if !expect(*C.__errno_location() == 17 && (&u8(high))[0] == 0x79, 95) { return 1 }
        if !expect(C.mmap(high, 4096, rw, anon_private | fixed | map32, -1, 0) == high, 96) { return 1 }
        if !expect((&u8(high))[0] == 0, 97) { return 1 }
    
        if !expect(C.munmap(first, 4096) == 0, 99) { return 1 }
        if !expect(C.munmap(second, 4096) == 0, 100) { return 1 }
        if !expect(C.munmap(hint, 4096) == 0, 101) { return 1 }
        if !expect(C.munmap(collision, 4096) == 0, 102) { return 1 }
        if !expect(C.munmap(overflow_hint, 8192) == 0, 103) { return 1 }
        if !expect(C.munmap(boundary, 65536) == 0, 104) { return 1 }
        if !expect(C.munmap(high, 4096) == 0, 105) { return 1 }
    
        
        reserved := C.mmap(voidptr(usize(0x40000000)), 0x20000000, 0,
                              anon_private | noreplace, -1, 0)
        if !expect(reserved == voidptr(usize(0x40000000)), 113) { return 1 }
        tail := C.mmap(nil, 0x08000000, 0, anon_private | map32, -1, 0)
        if !expect(low(tail, 0x08000000) && usize(tail) >= 0x60000000, 115) { return 1 }
        if !expect(C.munmap(voidptr(usize(0x48000000)), 4096) == 0, 116) { return 1 }
        hole := C.mmap(nil, 4096, rw, anon_private | map32, -1, 0)
        if !expect(hole == voidptr(usize(0x48000000)), 118) { return 1 }
        (&u8(hole))[0] = 0x81
        if !expect(C.munmap(reserved, 0x20000000) == 0, 120) { return 1 }
        if !expect(C.munmap(tail, 0x08000000) == 0, 121) { return 1 }
        full := C.mmap(voidptr(usize(0x40000000)), 0x40000000, 0,
                          anon_private | noreplace, -1, 0)
        if !expect(full == voidptr(usize(0x40000000)), 124) { return 1 }
        if !expect(C.mmap(nil, 4096, rw, anon_private | map32, -1, 0) == voidptr(usize(-1)), 125) { return 1 }
        if !expect(*C.__errno_location() == 12, 126) { return 1 }
        if !expect(C.munmap(full, 0x40000000) == 0, 127) { return 1 }
        C.puts(c'VINIX-DOTA2-MMAP32-PASS')
        C.fflush(nil)
        return 0
    }
}
