// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module runtimecore

struct ForkHandler {
mut:
    mutex C.pthread_mutex_t
    prepare voidptr
    parent voidptr
    child voidptr
    dso voidptr
    used u32
}
struct ForkThunks { prepare ForkCallback = unsafe { nil } parent ForkCallback = unsafe { nil } child ForkCallback = unsafe { nil } }

$if arm64 {
    // Musl's static mutex initializer is all-zero; native typed storage stays
    // permanent and each successful registration reserves its slot for life.
    __global fork_handlers [128]ForkHandler
    __global fork_registry_mutex C.pthread_mutex_t
    __global fork_guard_error i32

    fn fork_registry_prepare() { unsafe { C.pthread_mutex_lock(&fork_registry_mutex) } }
    fn fork_registry_release() { unsafe { C.pthread_mutex_unlock(&fork_registry_mutex) } }

    fn fork_prepare(index u32) {
        unsafe {
            handler := &fork_handlers[index]
            C.pthread_mutex_lock(&handler.mutex)
            if handler.prepare != nil { ForkCallback(handler.prepare)() }
        }
    }

    fn fork_finish(index u32, child bool) {
        unsafe {
            handler := &fork_handlers[index]
            callback := if child { handler.child } else { handler.parent }
            if callback != nil { ForkCallback(callback)() }
            C.pthread_mutex_unlock(&handler.mutex)
        }
    }

    @[export: 'bionic___register_atfork']
    pub fn register_fork(prepare ForkCallback, parent ForkCallback, child ForkCallback, dso voidptr) i32 {
        unsafe {
            if fork_guard_error != 0 { return fork_guard_error }
            C.pthread_mutex_lock(&fork_registry_mutex)
            mut index := u32(0)
            for index < 128 && fork_handlers[index].used != 0 { index++ }
            if index == 128 { C.pthread_mutex_unlock(&fork_registry_mutex); return 12 }
            handler := &fork_handlers[index]
            handler.used = 1
            C.pthread_mutex_lock(&handler.mutex)
            handler.prepare = voidptr(prepare)
            handler.parent = voidptr(parent)
            handler.child = voidptr(child)
            handler.dso = dso
            C.pthread_mutex_unlock(&handler.mutex)
            C.pthread_mutex_unlock(&fork_registry_mutex)
            // Native atfork also owns a lock: publish while holding neither
            // registry nor slot mutex, preserving the original lock ordering.
            result := C.pthread_atfork(fork_thunks[index].prepare,
                fork_thunks[index].parent, fork_thunks[index].child)
            if result != 0 {
                C.pthread_mutex_lock(&fork_registry_mutex)
                C.pthread_mutex_lock(&handler.mutex)
                handler.prepare = nil
                handler.parent = nil
                handler.child = nil
                handler.dso = nil
                handler.used = 0
                C.pthread_mutex_unlock(&handler.mutex)
                C.pthread_mutex_unlock(&fork_registry_mutex)
            }
            return result
        }
    }

    @[export: 'bionic_pthread_atfork']
    pub fn pthread_fork(prepare ForkCallback, parent ForkCallback, child ForkCallback) i32 {
        return register_fork(prepare, parent, child, unsafe { nil })
    }

    @[export: 'bionic___cxa_finalize']
    pub fn finalize(dso voidptr) {
        unsafe {
            if fork_guard_error != 0 { C.__cxa_finalize(dso); return }
            for index := u32(0); index < 128; index++ {
                handler := &fork_handlers[index]
                C.pthread_mutex_lock(&fork_registry_mutex)
                guarded := C.pthread_mutex_trylock(&handler.mutex) == 0
                if !guarded {
                    C.pthread_mutex_unlock(&fork_registry_mutex)
                    C.pthread_mutex_lock(&handler.mutex)
                }
                if dso == nil || handler.dso == dso {
                    handler.prepare = nil
                    handler.parent = nil
                    handler.child = nil
                    handler.dso = nil
                }
                C.pthread_mutex_unlock(&handler.mutex)
                if guarded { C.pthread_mutex_unlock(&fork_registry_mutex) }
            }
            C.__cxa_finalize(dso)
        }
    }
}
