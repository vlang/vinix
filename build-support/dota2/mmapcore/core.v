// SPDX-License-Identifier: GPL-2.0-or-later
// Select bounded x86 MAP_32BIT ranges before linux-user translation drops it.
@[translated]
module mmapcore

#include "mmap32-abi.h"

fn C.dlsym(voidptr, &char) voidptr
fn C.__errno_location() &i32
fn C.munmap(voidptr, usize) i32
fn C.open(&char, i32, ...voidptr) i32
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32

type MmapFunction = fn (voidptr, usize, i32, i32, i32, isize) voidptr

const map_fixed = i32(0x10)
const map_32bit = i32(0x40)
const map_noreplace = i32(0x100000)
const page_size = usize(4096)
const low_min = usize(0x10000)
const low_fallback = usize(0x40000000)
const low_end = usize(0x80000000)

struct MapsReader {
mut:
    candidate usize
    length usize
    limit usize
    number usize
    start usize
    previous_start usize
    phase i32
    digit bool
    records bool
    invalid bool
}

fn hex(value u8) i32 {
    if value >= `0` && value <= `9` { return i32(value - `0`) }
    if value >= `a` && value <= `f` { return i32(value - `a`) + 10 }
    if value >= `A` && value <= `F` { return i32(value - `A`) + 10 }
    return -1
}

fn record(state &MapsReader) {
    unsafe {
        end := state.number
        if end <= state.start || (state.records && state.start < state.previous_start) {
            state.invalid = true
            return
        }
        state.previous_start = state.start
        state.records = true
        if state.candidate >= state.limit { return }
        if state.start < state.candidate + state.length && end > state.candidate {
            state.candidate = if end >= state.limit { state.limit }
                else { (end + page_size - 1) & ~(page_size - 1) }
        }
    }
}

fn feed(state &MapsReader, data &u8, count usize) {
    unsafe {
        for index := usize(0); index < count && !state.invalid; index++ {
            value := data[index]
            if value == `\n` {
                if state.phase != 2 && (state.phase != 0 || state.digit) {
                    state.invalid = true
                }
                state.phase = 0
                state.digit = false
                state.number = 0
            } else if state.phase != 2 {
                digit := hex(value)
                if digit >= 0 {
                    if state.number > (usize(-1) - usize(digit)) / 16 {
                        state.invalid = true
                    } else {
                        state.number = state.number * 16 + usize(digit)
                        state.digit = true
                    }
                } else if state.phase == 0 && state.digit && value == `-` {
                    state.start = state.number
                    state.phase = 1
                    state.number = 0
                    state.digit = false
                } else if state.phase == 1 && state.digit && (value == ` ` || value == `\t`) {
                    record(state)
                    state.phase = 2
                } else {
                    state.invalid = true
                }
            }
        }
    }
}

// Hidden in the production ELF; the independent fixture calls this boundary.
@[export: 'vinix_dota_next_gap']
pub fn next_gap(requested_start usize, length usize, limit usize, output &usize) i32 {
    unsafe {
        if output == nil || length == 0 || length > usize(-1) - (page_size - 1) { return -1 }
        rounded := (length + page_size - 1) & ~(page_size - 1)
        if limit > low_end { return -1 }
        start := if requested_start < low_min { low_min } else { requested_start }
        if start >= limit || rounded > limit - start { return 0 }
        mut state := MapsReader{candidate: (start + page_size - 1) & ~(page_size - 1),
            length: rounded, limit: limit}
        fd := C.open(c'/proc/self/maps', 0x80000)
        if fd < 0 { return -1 }
        mut buffer := [256]u8{}
        mut status := i32(-1)
        for {
            count := C.read(fd, &buffer[0], 256)
            if count < 0 {
                if *C.__errno_location() == 4 { continue }
                break
            }
            if count == 0 {
                if !state.invalid && state.records && (state.phase == 2 || (state.phase == 0 && !state.digit)) {
                    status = if state.candidate <= limit - rounded { 1 } else { 0 }
                }
                break
            }
            feed(&state, &buffer[0], usize(count))
            if state.invalid { break }
        }
        // Exactly one close, including invalid input and interrupted reads.
        C.close(fd)
        if status == 1 { *output = state.candidate }
        return status
    }
}

fn failed(error i32) voidptr {
    unsafe { *C.__errno_location() = error }
    return voidptr(usize(-1))
}

fn low_mapping(next MmapFunction, address voidptr, length usize,
    protection i32, flags i32, fd i32, offset isize) voidptr {
    unsafe {
        if flags & map_32bit == 0 || flags & (map_fixed | map_noreplace) != 0 {
            return next(address, length, protection, flags, fd, offset)
        }
        if length == 0 { return failed(22) }
        if length > usize(-1) - (page_size - 1) { return failed(12) }
        rounded := (length + page_size - 1) & ~(page_size - 1)
        if rounded > low_end - low_min { return failed(12) }
        low_flags := (flags & ~map_32bit) | map_noreplace
        hint := usize(address) & ~(page_size - 1)
        if hint >= low_min && hint <= low_end - rounded {
            result := next(voidptr(hint), length, protection, low_flags, fd, offset)
            if result != voidptr(usize(-1)) {
                if usize(result) == hint { return result }
                C.munmap(result, length)
            } else if *C.__errno_location() != 17 {
                return result
            }
        }
        if rounded > low_end - low_fallback { return failed(12) }
        mut maps_available := true
        for candidate := low_fallback; candidate <= low_end - rounded; candidate += page_size {
            if maps_available {
                mut gap := usize(0)
                status := next_gap(candidate, rounded, low_end, &gap)
                if status == 0 { return failed(12) }
                if status > 0 { candidate = gap } else { maps_available = false }
            }
            result := next(voidptr(candidate), length, protection, low_flags, fd, offset)
            if result != voidptr(usize(-1)) {
                if usize(result) == candidate { return result }
                C.munmap(result, length)
            } else if *C.__errno_location() != 17 {
                return result
            }
        }
        return failed(12)
    }
}

@[export: 'mmap']
pub fn map(address voidptr, length usize, protection i32, flags i32, fd i32, offset isize) voidptr {
    unsafe {
        next := MmapFunction(C.dlsym(voidptr(usize(-1)), c'mmap'))
        return low_mapping(next, address, length, protection, flags, fd, offset)
    }
}

@[export: 'mmap64']
pub fn map64(address voidptr, length usize, protection i32, flags i32, fd i32, offset isize) voidptr {
    unsafe {
        next := MmapFunction(C.dlsym(voidptr(usize(-1)), c'mmap64'))
        return low_mapping(next, address, length, protection, flags, fd, offset)
    }
}
