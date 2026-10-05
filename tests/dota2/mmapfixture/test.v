// SPDX-License-Identifier: GPL-2.0-or-later
// The original parser fixture's cases, splits, failures and output guards.
@[translated]
module mmapfixture

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include "mmap-fixture-abi.h"

fn C.strcmp(&char, &char) i32
fn C.strlen(&char) usize
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.abort()
fn C.printf(&char, ...voidptr) i32
fn C.open(&char, i32, ...voidptr) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.vinix_dota_next_gap(usize, usize, usize, &usize) i32
fn C.fixture_mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.fixture_mmap64(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.fixture_real_mmap(voidptr, usize, i32, i32, i32, isize) voidptr

__global input &char
__global position usize
__global input_size usize
__global chunk usize
__global opens i32
__global closes i32
__global reads i32
__global error_code i32
__global open_fail bool
__global fault_read i32
__global fault_code i32
__global case_count i32
__global mapping bool
__global map_calls i32
__global unmap_calls i32
__global map_mode i32
__global symbol64 bool

struct Case { data &char start usize length usize expected i32 address usize }
const cases = [
    Case{c'00000000-40000000 ---p 0 00:00 0\n', 0, 4096, 1, 0x40000000},
    Case{c'40000000-40001000 rw-p 0 00:00 0', 0, 4096, 1, 0x40001000},
    Case{c'40000000-50000000 ---p 0 00:00 0\n50000000-60000000 ---p 0 00:00 0\n', 0, 4096, 1, 0x60000000},
    Case{c'40000000-40002000 rw-p 0 00:00 0\n40001000-40004000 rw-p 0 00:00 0\n', 0, 4096, 1, 0x40004000},
    Case{c'40000000-40001000 rw-p 0 00:00 0\n40000000-40008000 rw-p 0 00:00 0\n', 0, 4096, 1, 0x40008000},
    Case{c'40000000-70000000 ---p 0 00:00 0\n', 0, 0x10000000, 1, 0x70000000},
    Case{c'40000000-70000000 ---p 0 00:00 0\n', 0, 0x10000001, 0, 0},
    Case{c'40000000-80000000 ---p 0 00:00 0\n', 0, 4096, 0, 0},
    Case{c'40000000-40000001 rw-p 0 00:00 0\n', 0, 4096, 1, 0x40001000},
    Case{c'50000000-58000000 rw-p 0 00:00 0\n', 0, 0x20000000, 1, 0x58000000},
    Case{c'40000000-40001000 rw-p 0 00:00 0\n', 0x40003001, 1, 1, 0x40004000},
    Case{c'0000000140000000-0000000180000000 rw-p 0 00:00 0\n', 0, 4096, 1, 0x40000000},
    Case{c'40000000-FFFFFFFFFFFFFFFF rw-p 0 00:00 0\n', 0, 4096, 0, 0},
    Case{c'', 0, 4096, -1, 0},
    Case{c'\n\n', 0, 4096, -1, 0},
    Case{c'50000000-50001000 rw-p 0 00:00 0\n40000000-40001000 rw-p 0 00:00 0\n', 0, 4096, -1, 0},
    Case{c'40000000-40000000 rw-p 0 00:00 0\n', 0, 4096, -1, 0},
    Case{c'40001000-40000000 rw-p 0 00:00 0\n', 0, 4096, -1, 0},
    Case{c'10000000000000000-10000000000001000 rw-p 0 00:00 0\n', 0, 4096, -1, 0},
    Case{c'40000000-10000000000000000 rw-p 0 00:00 0\n', 0, 4096, -1, 0},
    Case{c'40000000-40001000\n', 0, 4096, -1, 0},
    Case{c'40000000-40001000', 0, 4096, -1, 0},
    Case{c'x40000000-40001000 rw-p 0 00:00 0\n', 0, 4096, -1, 0},
]!

fn init() {
    $if mmap_guest ? {
        unsafe {
            mut fd := i32(-1)
            $if amd64 { fd = C.open(c'/dev/com1', 1) }
            $else { fd = C.open(c'/dev/console', 2) }
            if fd < 0 { C.abort() }
            for target := i32(0); target < 3; target++ { if C.dup2(fd, target) != target { C.abort() } }
            if fd > 2 { C.close(fd) }
        }
    }
}

@[export: 'fixture_open']
pub fn open_maps(path &char, flags i32) i32 {
    unsafe {
        if C.strcmp(path, c'/proc/self/maps') != 0 || flags != 0x80000 { C.abort() }
        opens++
        return if open_fail { -1 } else { 17 }
    }
}

@[export: 'fixture_read']
pub fn read_maps(fd i32, data voidptr, count usize) isize {
    unsafe {
        if fd != 17 { C.abort() }
        reads++
        if reads == fault_read { error_code = fault_code; return -1 }
        mut actual := count
        if actual > chunk { actual = chunk }
        if actual > input_size - position { actual = input_size - position }
        C.memcpy(data, input + position, actual)
        position += actual
        return isize(actual)
    }
}

@[export: 'fixture_close']
pub fn close_maps(fd i32) i32 {
    unsafe { if fd != 17 { C.abort() }; closes++; return 0 }
}

@[export: 'fixture_errno']
pub fn errno_location() &i32 { return unsafe { &error_code } }

@[export: 'fixture_dlsym']
pub fn resolve(handle voidptr, name &char) voidptr {
    unsafe {
        if !mapping || usize(handle) != usize(-1) ||
            C.strcmp(name, if symbol64 { c'mmap64' } else { c'mmap' }) != 0 { C.abort() }
        return voidptr(C.fixture_real_mmap)
    }
}

@[export: 'fixture_munmap']
pub fn unmap(address voidptr, length usize) i32 {
    unsafe {
        if !mapping || usize(address) != 0x90000000 || length != 4096 { C.abort() }
        unmap_calls++
        return 0
    }
}

@[export: 'fixture_real_mmap']
pub fn real_map(address voidptr, length usize, protection i32, flags i32, fd i32, offset isize) voidptr {
    unsafe {
        map_calls++
        if protection != 3 || fd != 19 || offset != -8192 { C.abort() }
        if map_mode == 0 {
            if length != 13 || flags != 0x12 || usize(address) != 0x12345 { C.abort() }
            return address
        }
        if length != 4096 || flags != 0x100002 { C.abort() }
        if map_calls == 1 && map_mode == 1 { return voidptr(usize(0x90000000)) }
        if map_calls == 1 && map_mode == 2 { error_code = 17; return voidptr(usize(-1)) }
        if map_mode == 3 { error_code = 22; return voidptr(usize(-1)) }
        if map_calls == 1 && map_mode == 4 { error_code = 17; return voidptr(usize(-1)) }
        return address
    }
}

fn reset(data &char, limit usize) {
    unsafe {
        input = data; position = 0; input_size = C.strlen(data); chunk = limit
        opens = 0; closes = 0; reads = 0; error_code = 0
        open_fail = false; fault_read = 0; fault_code = 0
        mapping = false; map_calls = 0; unmap_calls = 0; map_mode = 0; symbol64 = false
    }
}

fn dota_gap(start usize, length usize, output &usize) i32 {
    return C.vinix_dota_next_gap(if start < 0x40000000 { usize(0x40000000) } else { start }, length, 0x80000000, output)
}

fn check(data &char, start usize, length usize, expected i32, address usize) {
    unsafe {
        for split := usize(1); split <= 257; split++ {
            reset(data, split)
            mut output := usize(0x12345)
            result := dota_gap(start, length, &output)
            if result != expected || (if result == 1 { output != address } else { output != 0x12345 }) || opens != 1 || closes != 1 {
                C.printf(c'case %d split %lu: got %d/%lx expected %d/%lx opens%d closes%d\n', case_count, split, result, output, expected, address, opens, closes)
                C.abort()
            }
        }
        case_count++
    }
}

fn mapping_checks() {
    unsafe {
        reset(c'00000000-40000000 ---p 0 00:00 0\n', 256); mapping = true
        if C.fixture_mmap(voidptr(usize(0x12345)), 13, 3, 0x12, 19, -8192) != voidptr(usize(0x12345)) || map_calls != 1 { C.abort() }
        for mode := i32(1); mode <= 4; mode++ {
            reset(c'00000000-40000000 ---p 0 00:00 0\n', 256); mapping = true; map_mode = mode
            if mode == 4 { open_fail = true }
            result := C.fixture_mmap(voidptr(usize(0x12345)), 4096, 3, 0x42, 19, -8192)
            if mode == 3 {
                if usize(result) != usize(-1) || error_code != 22 || map_calls != 1 || opens != 0 { C.abort() }
            } else {
                if usize(result) != 0x40000000 || map_calls != 2 || opens != 1 || (if mode == 4 { closes != 0 } else { closes != 1 }) { C.abort() }
                if unmap_calls != (if mode == 1 { 1 } else { 0 }) { C.abort() }
            }
        }
        reset(c'00000000-40000000 ---p 0 00:00 0\n', 256); mapping = true; map_mode = 2
        if C.fixture_mmap(nil, 4096, 3, 0x42, 19, -8192) != voidptr(usize(0x40001000)) || map_calls != 2 || opens != 2 || closes != 2 { C.abort() }
        reset(c'40000000-80000000 ---p 0 00:00 0\n', 256); mapping = true; map_mode = 2
        if usize(C.fixture_mmap(nil, 4096, 3, 0x42, 19, -8192)) != usize(-1) || error_code != 12 || map_calls != 0 || opens != 1 || closes != 1 { C.abort() }
        reset(c'', 256); mapping = true
        if usize(C.fixture_mmap(nil, 0, 3, 0x42, 19, -8192)) != usize(-1) || error_code != 22 || map_calls != 0 { C.abort() }
        if usize(C.fixture_mmap(nil, usize(-1), 3, 0x42, 19, -8192)) != usize(-1) || error_code != 12 || map_calls != 0 { C.abort() }
        if usize(C.fixture_mmap(nil, 0x80000000, 3, 0x42, 19, -8192)) != usize(-1) || error_code != 12 || map_calls != 0 { C.abort() }
        reset(c'00000000-40000000 ---p 0 00:00 0\n', 256); mapping = true; map_mode = 2; symbol64 = true
        if C.fixture_mmap64(voidptr(usize(0x12345)), 4096, 3, 0x42, 19, -8192) != voidptr(usize(0x40000000)) || map_calls != 2 { C.abort() }
        C.printf(c'mmap32 mapping callbacks: forwarding, hint/collision/discard, errno, fallback, bounds and mmap64 PASS\n')
    }
}

@[export: 'main']
pub fn run() i32 {
    unsafe {
        for item in cases { check(item.data, item.start, item.length, item.expected, item.address) }
        mut large := [16384]char{}
        prefix := &char(c'40000000-40001000 rw-p 0 00:00 0 /')
        used := C.strlen(prefix)
        C.memcpy(&large[0], prefix, used)
        C.memset(&large[used], 97, 8192)
        suffix := &char(c'\n40001000-40002000 rw-p 0 00:00 0\n')
        C.memcpy(&large[used + 8192], suffix, C.strlen(suffix) + 1)
        check(&large[0], 0, 4096, 1, 0x40002000)
        reset(c'40000000-40001000 rw-p 0 00:00 0\n', 1)
        fault_read = 7; fault_code = 4
        mut output := usize(0)
        if dota_gap(0, 4096, &output) != 1 || output != 0x40001000 || opens != 1 || closes != 1 { C.abort() }
        reset(c'40000000-40001000 rw-p 0 00:00 0\n', 1); fault_read = 7; fault_code = 5
        if dota_gap(0, 4096, &output) != -1 || opens != 1 || closes != 1 { C.abort() }
        reset(c'', 1); open_fail = true
        if dota_gap(0, 4096, &output) != -1 || opens != 1 || closes != 0 || reads != 0 { C.abort() }
        reset(c'', 1)
        if dota_gap(0, 0, &output) != -1 || dota_gap(0, usize(-1), &output) != -1 || dota_gap(0, 4096, nil) != -1 || dota_gap(0x80000000, 4096, &output) != 0 || dota_gap(0, 0x40000001, &output) != 0 || opens != 0 || closes != 0 || reads != 0 { C.abort() }
        reset(c'00010000-40000000 ---p 0 00:00 0\n', 1)
        if C.vinix_dota_next_gap(0x40000000, 4096, 0x40001000, &output) != 1 || output != 0x40000000 || closes != 1 { C.abort() }
        reset(c'00010000-40000000 ---p 0 00:00 0\n', 1)
        if C.vinix_dota_next_gap(0x40000001, 4096, 0x40001000, &output) != 0 || closes != 0 || opens != 0 { C.abort() }
        reset(c'', 1)
        if C.vinix_dota_next_gap(0, 4096, usize(-1), &output) != -1 || C.vinix_dota_next_gap(0x40000000, 4096, 0x10000, &output) != 0 || opens != 0 { C.abort() }
        C.printf(c'mmap32 maps parser: %d cases x257 read sizes plus I/O/argument cases passed\n', case_count)
        mapping_checks()
        return 0
    }
}
