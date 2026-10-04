// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sysvsem

// System V counting semaphores used by the Linux Steam client and other
// glibc programs. Operations on a set are atomic; waiters sleep on its event
// and recheck the full operation after every wakeup.

import errno
import event
import event.eventstruct
import klock
import proc
import time
import usercopy

const ipc_private = i32(0)
const ipc_creat = 0o1000
const ipc_excl = 0o2000
const ipc_nowait = 0o4000
const sem_undo = 0x1000
const ipc_rmid = 0
const getpid = 11
const getval = 12
const getncnt = 14
const getzcnt = 15
const setval = 16
const max_sems = 32
const max_ops = 32
const semvmx = 32767

@[packed]
struct SemBuf {
    number u16
    operation i16
    flags i16
}

@[heap]
struct Set {
mut:
    id int
    key i32
    values []int
    last_pid int
    removed bool
    waiters int
    wake eventstruct.Event
}

__global (
    sets = []&Set{}
    sets_lock klock.Lock
    next_id = int(1)
)

fn find_id_unlocked(id int) &Set {
    for set in sets {
        if set.id == id {
            return set
        }
    }
    return unsafe { nil }
}

fn find_key_unlocked(key i32) &Set {
    for set in sets {
        if !set.removed && set.key == key {
            return set
        }
    }
    return unsafe { nil }
}

fn destroy_unlocked(set &Set) {
    index := sets.index(set)
    if index >= 0 {
        sets.delete(index)
    }
    unsafe { set.values.free() }
    unsafe { free(set) }
}

pub fn syscall_semget(_ voidptr, key i32, nsems int, flags int) (u64, u64) {
    sets_lock.acquire()
    if key != ipc_private {
        existing := find_key_unlocked(key)
        if existing != unsafe { nil } {
            if flags & ipc_creat != 0 && flags & ipc_excl != 0 {
                sets_lock.release()
                return errno.err, errno.eexist
            }
            if nsems > existing.values.len {
                sets_lock.release()
                return errno.err, errno.einval
            }
            id := existing.id
            sets_lock.release()
            return u64(id), 0
        }
        if flags & ipc_creat == 0 {
            sets_lock.release()
            return errno.err, errno.enoent
        }
    }
    if nsems <= 0 || nsems > max_sems {
        sets_lock.release()
        return errno.err, errno.einval
    }
    id := next_id
    next_id++
    // destroy_unlocked() frees it with the set.
    values := []int{len: nsems} @[freed]
    // Nothing slices the list, so growing can free the old block.
    sets.flags |= .noslices
    sets << &Set{
        id: id
        key: key
        values: values
    }
    sets_lock.release()
    return u64(id), 0
}

pub fn syscall_semctl(_ voidptr, id int, number int, command int, argument u64) (u64, u64) {
    sets_lock.acquire()
    mut set := find_id_unlocked(id)
    if set == unsafe { nil } || set.removed {
        sets_lock.release()
        return errno.err, errno.einval
    }
    if command != ipc_rmid && (number < 0 || number >= set.values.len) {
        sets_lock.release()
        return errno.err, errno.einval
    }
    match command {
        ipc_rmid {
            set.removed = true
            event.trigger(mut set.wake, true)
            if set.waiters == 0 {
                destroy_unlocked(set)
            }
            sets_lock.release()
            return 0, 0
        }
        getval {
            value := set.values[number]
            sets_lock.release()
            return u64(value), 0
        }
        getpid {
            pid := set.last_pid
            sets_lock.release()
            return u64(pid), 0
        }
        getncnt, getzcnt {
            sets_lock.release()
            return 0, 0
        }
        setval {
            if argument > semvmx {
                sets_lock.release()
                return errno.err, errno.erange
            }
            set.values[number] = int(argument)
            set.last_pid = proc.current_thread().process.pid
            event.trigger(mut set.wake, true)
            sets_lock.release()
            return 0, 0
        }
        else {
            sets_lock.release()
            return errno.err, errno.einval
        }
    }
}

fn operate(id int, user_operations u64, count u64, timeout_address u64) (u64, u64) {
    if user_operations == 0 || count == 0 || count > max_ops {
        return errno.err, errno.einval
    }
    mut operations := [max_ops]SemBuf{}
    if !usercopy.copy_from_user(unsafe { voidptr(&operations[0]) }, user_operations, count * sizeof(SemBuf)) {
        return errno.err, errno.efault
    }
    for i in 0 .. int(count) {
        op := operations[i]
        if int(op.flags) & ~(ipc_nowait | sem_undo) != 0 {
            return errno.err, errno.einval
        }
    }

    mut timer := &time.Timer(unsafe { nil })
    defer {
        if timer != unsafe { nil } {
            timer.disarm()
            unsafe { free(timer) }
        }
    }
    if timeout_address != 0 {
        mut duration := time.TimeSpec{}
        if !usercopy.copy_from_user(voidptr(&duration), timeout_address, sizeof(time.TimeSpec)) {
            return errno.err, errno.efault
        }
        if duration.tv_sec < 0 || duration.tv_nsec < 0 || duration.tv_nsec >= 1000000000 {
            return errno.err, errno.einval
        }
        timer = time.new_timer(duration)
    }

    for {
        sets_lock.acquire()
        mut set := find_id_unlocked(id)
        if set == unsafe { nil } || set.removed {
            sets_lock.release()
            return errno.err, errno.eidrm
        }
        mut proposed := set.values.clone()
        mut blocked := false
        mut nowait := false
        for i in 0 .. int(count) {
            op := operations[i]
            number := int(op.number)
            if number >= proposed.len {
                unsafe { proposed.free() }
                sets_lock.release()
                return errno.err, errno.efbig
            }
            next := proposed[number] + int(op.operation)
            if op.operation == 0 {
                blocked = proposed[number] != 0
            } else if next < 0 {
                blocked = true
            } else if next > semvmx {
                unsafe { proposed.free() }
                sets_lock.release()
                return errno.err, errno.erange
            } else {
                proposed[number] = next
            }
            if blocked {
                nowait = int(op.flags) & ipc_nowait != 0
                break
            }
        }
        if !blocked {
            unsafe { set.values.free() }
            set.values = proposed
            set.last_pid = proc.current_thread().process.pid
            event.trigger(mut set.wake, true)
            sets_lock.release()
            return 0, 0
        }
        unsafe { proposed.free() }
        if nowait {
            sets_lock.release()
            return errno.err, errno.eagain
        }
        generation := event.generation(mut set.wake)
        set.waiters++
        mut wake := &set.wake
        sets_lock.release()

        mut storage := [wake, wake]!
        mut waiting := 1
        if timer != unsafe { nil } {
            storage[1] = &timer.event
            waiting = 2
        }
        mut events := unsafe { event.stack_list(&storage[0], waiting) }
        which := event.await_from_generation(mut events, true, 0, generation) or { u64(-1) }

        sets_lock.acquire()
        set.waiters--
        removed := set.removed
        if removed && set.waiters == 0 {
            destroy_unlocked(set)
        }
        sets_lock.release()
        if removed {
            return errno.err, errno.eidrm
        }
        if which == u64(-1) {
            return errno.err, errno.eintr
        }
        if which == 1 {
            return errno.err, errno.eagain
        }
    }
    return 0, 0
}

pub fn syscall_semop(_ voidptr, id int, operations u64, count u64) (u64, u64) {
    return operate(id, operations, count, 0)
}

pub fn syscall_semtimedop(_ voidptr, id int, operations u64, count u64, timeout u64) (u64, u64) {
    return operate(id, operations, count, timeout)
}
