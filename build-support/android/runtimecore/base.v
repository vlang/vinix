// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module runtimecore

#include "runtime-v-abi.h"

struct C.pthread_t {}
struct C.pthread_attr_t {}
struct C.pthread_mutex_t {}
struct C.FILE {}
struct C.rlimit { rlim_cur usize rlim_max usize }

fn C.pthread_self() C.pthread_t
fn C.pthread_equal(C.pthread_t, C.pthread_t) i32
fn C.pthread_attr_setstack(&C.pthread_attr_t, voidptr, usize) i32
fn C.pthread_attr_setguardsize(&C.pthread_attr_t, usize) i32
fn C.pthread_attr_destroy(&C.pthread_attr_t) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_trylock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.pthread_atfork(ForkCallback, ForkCallback, ForkCallback) i32
fn C.pthread_once(&i32, ForkCallback) i32
fn C.pthread_setcancelstate(i32, &i32) i32
fn C.__cxa_finalize(voidptr)
fn C.__errno_location() &i32
fn C.dlsym(voidptr, &char) voidptr
fn C.fopen(&char, &char) &C.FILE
fn C.getline(&&char, &usize, &C.FILE) isize
fn C.sscanf(&char, &char, ...voidptr) i32
fn C.ferror(&C.FILE) i32
fn C.fclose(&C.FILE) i32
fn C.free(voidptr)
fn C.getrlimit(i32, &C.rlimit) i32

type GetAttributes = fn (C.pthread_t, &C.pthread_attr_t) i32
type ForkCallback = fn ()

__global initial_thread C.pthread_t
__global initial_stack_anchor usize
__global next_getattr GetAttributes

fn init() {
    unsafe {
        initial_thread = C.pthread_self()
        mut stack_local := usize(0)
        initial_stack_anchor = usize(&stack_local)
        next_getattr = GetAttributes(C.dlsym(voidptr(usize(-1)), c'pthread_getattr_np'))
        $if arm64 {
            fork_guard_error = C.pthread_atfork(fork_registry_prepare,
                fork_registry_release, fork_registry_release)
        } $else {
            C.pthread_once(&mapping_once, mapping_resolve)
            C.pthread_atfork(low_fork_prepare, low_fork_release, low_fork_release)
        }
    }
}

fn mapped_stack_bounds(anchor usize, base &usize, size &usize) i32 {
    unsafe {
        maps := C.fopen(c'/proc/self/maps', c'r')
        if maps == nil { return *C.__errno_location() }
        mut line := &char(nil)
        mut capacity := usize(0)
        mut result := i32(2)
        for C.getline(&line, &capacity, maps) >= 0 {
            mut begin := usize(0)
            mut end := usize(0)
            mut permissions := [5]char{}
            if C.sscanf(line, c'%lx-%lx %4s', &begin, &end, &permissions[0]) != 3 { continue }
            if begin <= anchor && anchor < end && permissions[0] == char(`r`) && permissions[1] == char(`w`) {
                *base = begin
                *size = end - begin
                result = 0
                break
            }
        }
        C.free(line)
        C.fclose(maps)
        return result
    }
}

fn initial_stack_bounds(base &usize, size &usize) i32 {
    unsafe {
        result := mapped_stack_bounds(initial_stack_anchor, base, size)
        $if arm64 {
            if result == 0 {
                mut limit := C.rlimit{}
                if C.getrlimit(C.RLIMIT_STACK, &limit) != 0 { return *C.__errno_location() }
                if limit.rlim_cur != usize(-1) && limit.rlim_cur < *size {
                    usable := limit.rlim_cur & ~(usize(16384) - 1)
                    if usable == 0 { return 22 }
                    *base += *size - usable
                    *size = usable
                }
            }
        }
        return result
    }
}

@[export: 'pthread_getattr_np']
pub fn thread_attributes(thread C.pthread_t, attributes &C.pthread_attr_t) i32 {
    unsafe {
        if voidptr(next_getattr) == nil { return 38 }
        if C.pthread_equal(thread, initial_thread) == 0 { return next_getattr(thread, attributes) }
        saved_errno := *C.__errno_location()
        mut result := next_getattr(thread, attributes)
        if result != 0 { *C.__errno_location() = saved_errno; return result }
        mut base := usize(0)
        mut size := usize(0)
        result = initial_stack_bounds(&base, &size)
        if result == 0 {
            result = C.pthread_attr_setstack(attributes, voidptr(base), size)
            if result == 0 { result = C.pthread_attr_setguardsize(attributes, 0) }
        }
        if result != 0 { C.pthread_attr_destroy(attributes) }
        *C.__errno_location() = saved_errno
        return result
    }
}
