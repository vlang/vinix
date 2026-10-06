// SPDX-License-Identifier: GPL-2.0-or-later
// Host adapters use real Darwin pthread/stdio APIs. Darwin's mutex initializer
// has a signature word; initialize the production musl zero storage before its
// first host lock. The immutable fork fixture initializes every slot before its
// concurrent finalizer case; native guests verify musl's actual zero storage.
@[translated]
module runtimehost

#include "runtime-host-abi.h"
struct C.pthread_mutex_t {}
struct C.FILE { mut: _flags i16 }
@[typedef]
struct C.vandroid_const_char_p {}
@[typedef]
struct C.vinix_malloc_stats {
mut:
    mapped_bytes usize live_bytes usize free_bytes usize peak_mapped_bytes usize
    peak_live_bytes usize live_blocks usize free_blocks usize mapped_blocks usize
}
@[typedef]
struct C.android_mallinfo {
    arena usize ordblks usize smblks usize hblks usize hblkhd usize
    usmblks usize fsmblks usize uordblks usize fordblks usize keepcost usize
}
fn C.pthread_mutex_init(&C.pthread_mutex_t, voidptr) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_trylock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.bionic_mallinfo() C.android_mallinfo
fn C.getenv(&char) &char
fn C.strcmp(&char, &char) i32
fn C.puts(&char) i32
fn C.abort()
fn C.dlsym(voidptr, C.vandroid_const_char_p) voidptr

@[export: 'bionic___sF']
__global standard_facade [456]u8

@[export: 'fixture_dlsym']
pub fn dynamic_symbol(handle voidptr, name C.vandroid_const_char_p) voidptr {
    // Linux RTLD_DEFAULT is null; Darwin spells the same lookup as -2.
    return C.dlsym(if handle == unsafe { nil } { unsafe { voidptr(usize(-2)) } } else { handle }, name)
}

fn initialize_mutex(mutex &C.pthread_mutex_t) {
    unsafe { if *&usize(mutex) == 0 { if C.pthread_mutex_init(mutex, nil) != 0 { C.abort() } } }
}

@[export: 'fixture_pthread_mutex_lock']
pub fn lock(mutex &C.pthread_mutex_t) i32 { initialize_mutex(mutex); return C.pthread_mutex_lock(mutex) }
@[export: 'fixture_pthread_mutex_trylock']
pub fn trylock(mutex &C.pthread_mutex_t) i32 { initialize_mutex(mutex); return C.pthread_mutex_trylock(mutex) }
@[export: 'fixture_pthread_mutex_unlock']
pub fn unlock(mutex &C.pthread_mutex_t) i32 { return C.pthread_mutex_unlock(mutex) }
@[export: '__fseterr']
pub fn set_error(stream &C.FILE) { unsafe { stream._flags |= i16(0x40) } }
@[export: '__vinix_malloc_stats']
pub fn statistics(output &C.vinix_malloc_stats, size usize) i32 {
    unsafe {
        mode := C.getenv(c'ANDROID_HOST_STATS_FAIL')
        if mode != nil && C.strcmp(mode, c'1') == 0 { return -1 }
        if size != 64 { return -1 }
        *output = C.vinix_malloc_stats{mapped_bytes: 0x123456780001, live_bytes: 0x223456780002,
            free_bytes: 0x323456780003, peak_mapped_bytes: 0x423456780004,
            peak_live_bytes: 0x523456780005, live_blocks: 0x623456780006,
            free_blocks: 0x723456780007, mapped_blocks: 0x823456780008}
        return 0
    }
}

@[export: 'main']
pub fn run() i32 {
    info := C.bionic_mallinfo()
    if info.arena != 0 || info.ordblks != 0x723456780007 || info.smblks != 0 ||
       info.hblks != 0x823456780008 || info.hblkhd != 0x123456780001 ||
       info.usmblks != 0x423456780004 || info.fsmblks != 0 ||
       info.uordblks != 0x223456780002 || info.fordblks != 0x323456780003 || info.keepcost != 0 {
        return 1
    }
    C.puts(c'ANDROID-MALLINFO-HOST-PASS 80-byte aggregate and eight 64-bit provider fields')
    return 0
}
