// SPDX-License-Identifier: GPL-2.0-or-later
// Independent constructor fixture; environment storage is destroyed on removal.
@[translated]
module earlyfixture

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

fn C.getenv(&char) &char
fn C.unsetenv(&char) i32
fn C.strcmp(&char, &char) i32
fn C.write(i32, voidptr, usize) isize
fn C.abort()
fn C.open(&char, i32, ...voidptr) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.setenv(&char, &char, i32) i32

__global load_calls i32

fn init() {
    $if early_guest ? {
        unsafe {
            mut fd := i32(-1)
            $if amd64 { fd = C.open(c'/dev/com1', C.O_WRONLY) }
            $else { fd = C.open(c'/dev/console', C.O_RDWR) }
            if fd < 0 { C.abort() }
            for target := i32(0); target < 3; target++ {
                if C.dup2(fd, target) != target { C.abort() }
            }
            if fd > 2 { C.close(fd) }
            if C.setenv(c'EARLY_FIXTURE_MODE', c'ok', 1) != 0 ||
                C.setenv(c'EARLY_FIXTURE_PATH', c'/actual/client.so', 1) != 0 ||
                C.setenv(c'VINIX_DOTA2_EARLY_STEAMCLIENT', c'/actual/client.so', 1) != 0 {
                C.abort()
            }
        }
    }
}

fn mode_is(name &char) bool {
    unsafe {
        mode := C.getenv(c'EARLY_FIXTURE_MODE')
        return mode != nil && C.strcmp(mode, name) == 0
    }
}

fn emit(text &char) {
    unsafe {
        mut length := usize(0)
        for text[length] != 0 { length++ }
        C.write(2, text, length)
    }
}

@[export: 'fixture_unsetenv']
pub fn unset_marker(name &char) i32 {
    unsafe {
        if C.strcmp(name, c'VINIX_DOTA2_EARLY_STEAMCLIENT') != 0 { C.abort() }
        if mode_is(c'unsetfail') { return -1 }
        original := C.getenv(name)
        if original != nil {
            for index := usize(0); original[index] != 0; index++ {
                original[index] = char(`x`)
            }
        }
        return C.unsetenv(name)
    }
}

@[export: 'fixture_dlopen']
pub fn load(filename &char, flags i32) voidptr {
    unsafe {
        if C.getenv(c'VINIX_DOTA2_EARLY_STEAMCLIENT') != nil || flags != 0x1002 {
            C.abort()
        }
        expected := C.getenv(c'EARLY_FIXTURE_PATH')
        if expected == nil || C.strcmp(filename, expected) != 0 { C.abort() }
        load_calls++
        emit(c'EARLY-FIXTURE: loader before main\n')
        if mode_is(c'loadfail') || mode_is(c'nullerror') { return nil }
        return voidptr(usize(0x12345678))
    }
}

@[export: 'fixture_dlerror']
pub fn error() &char {
    if mode_is(c'nullerror') { return unsafe { nil } }
    return c'fixture loader failure'
}

@[export: 'main']
pub fn run() i32 {
    unsafe {
        if mode_is(c'skip') {
            if load_calls != 0 { return 1 }
        } else if load_calls != 1 || C.getenv(c'VINIX_DOTA2_EARLY_STEAMCLIENT') != nil {
            return 2
        }
        emit(c'EARLY-FIXTURE: main\n')
        return 0
    }
}
