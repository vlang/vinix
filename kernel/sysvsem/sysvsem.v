// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sysvsem

// Pending semaphore vectors are granted synchronously with value changes.
// Every pending vector and its private event belong to the operation frame.
// All queue state and completion decisions are protected by sets_lock.

import kbudget
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
    kernel_charge kbudget.Charge
    id int
    key i32
    values []int
    last_pid int
    removed bool
    // Pins include completed-but-not-yet-unwound syscall frames.
    waiters int
    pending_head &Pending = unsafe { nil }
    pending_tail &Pending = unsafe { nil }
}

// This record is explicitly allocated in the operation frame, never on the
// heap. operations points into that frame's already-copied fixed array.
struct Pending {
mut:
    operations &SemBuf = unsafe { nil }
    count int
    pid int
    previous &Pending = unsafe { nil }
    next &Pending = unsafe { nil }
    blocker int = -1
    wait_zero bool
    linked bool
    completed bool
    result u64
    wake eventstruct.Event
}

// The proposal is private stack storage. Nothing is committed until the
// entire vector succeeds. Returns first blocker, its kind, and an errno.
fn evaluate_unlocked(set &Set, operations &SemBuf, count int, proposed &int) (int, bool, u64) {
    unsafe {
        for number in 0 .. set.values.len { proposed[number] = set.values[number] }
        for i in 0 .. count {
            op := operations[i]
            number := int(op.number)
            if number >= set.values.len { return -1, false, errno.efbig }
            next := proposed[number] + int(op.operation)
            blocked := if op.operation == 0 { proposed[number] != 0 } else { next < 0 }
            if blocked {
                if int(op.flags) & ipc_nowait != 0 { return -1, false, errno.eagain }
                return number, op.operation == 0, 0
            }
            if next > semvmx { return -1, false, errno.erange }
            if op.operation != 0 { proposed[number] = next }
        }
        return -1, false, 0
    }
}

fn commit_unlocked(mut set Set, proposed &int, pid int) {
    for number in 0 .. set.values.len { set.values[number] = unsafe { proposed[number] } }
    set.last_pid = pid
}

fn link_unlocked(mut set Set, mut pending Pending) {
    pending.previous = set.pending_tail
    pending.next = unsafe { nil }
    if set.pending_tail == unsafe { nil } { set.pending_head = unsafe { &pending } }
    else { set.pending_tail.next = unsafe { &pending } }
    set.pending_tail = unsafe { &pending }
    pending.linked = true
}

fn unlink_unlocked(mut set Set, mut pending Pending) {
    if !pending.linked { return }
    if pending.previous == unsafe { nil } { set.pending_head = pending.next }
    else { pending.previous.next = pending.next }
    if pending.next == unsafe { nil } { set.pending_tail = pending.previous }
    else { pending.next.previous = pending.previous }
    pending.previous = unsafe { nil }
    pending.next = unsafe { nil }
    pending.linked = false
    pending.blocker = -1
}

// Completion detaches only queue membership. Its frame retains the set pin
// until await has removed every listener and operate is ready to return.
fn complete_unlocked(mut set Set, mut pending Pending, result u64) {
    unlink_unlocked(mut set, mut pending)
    pending.result = result
    pending.completed = true
    event.trigger(mut pending.wake, true)
}

// SETVAL and successful semop process pending vectors under the same lock as
// their value change. Every grant restarts the scan because a later vector
// can enable an earlier vector. Errors detach without committing a proposal.
fn progress_unlocked(mut set Set) {
    mut proposed := [max_sems]int{}
    mut pending := set.pending_head
    for pending != unsafe { nil } {
        next := pending.next
        blocker, wait_zero, result := evaluate_unlocked(set, pending.operations, pending.count,
            unsafe { &proposed[0] })
        if result != 0 {
            complete_unlocked(mut set, mut pending, result)
            pending = next
        } else if blocker >= 0 {
            pending.blocker = blocker
            pending.wait_zero = wait_zero
            pending = next
        } else {
            commit_unlocked(mut set, unsafe { &proposed[0] }, pending.pid)
            complete_unlocked(mut set, mut pending, 0)
            pending = set.pending_head
        }
    }
}

// All paths call this only after await has detached its listeners; the stack
// record is then unlinked before its frame disappears. Completed records can
// still be the last owner of a removed set even though no queue entry remains.
fn release_waiter_unlocked(mut set Set, mut pending Pending) {
    unlink_unlocked(mut set, mut pending)
    set.waiters--
    if set.removed && set.waiters == 0 { destroy_unlocked(set) }
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
    kbudget.release(set.kernel_charge)
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
    if sets.len >= 4096 { sets_lock.release(); return errno.err, errno.enospc }
    charge := proc.reserve_kernel(.ipc, 4096) or { sets_lock.release(); return errno.err, errno.get() }
    id := next_id
    next_id++
    // destroy_unlocked() frees it with the set.
    values := []int{len: nsems} @[freed]
    // Nothing slices the list, so growing can free the old block.
    sets.flags |= .noslices
    sets << &Set{
        kernel_charge: charge
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
            // Previously granted frames keep their saved success. Only live
            // pending records are completed with EIDRM by removal.
            for set.pending_head != unsafe { nil } {
                mut pending := set.pending_head
                complete_unlocked(mut set, mut pending, errno.eidrm)
            }
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
            mut count := u64(0)
            mut pending := set.pending_head
            for pending != unsafe { nil } {
                if pending.blocker == number && pending.wait_zero == (command == getzcnt) { count++ }
                pending = pending.next
            }
            sets_lock.release()
            return count, 0
        }
        setval {
            // Linux's SETVAL union member is a signed native int, even when
            // the syscall register contains nonzero upper bits.
            value := i32(argument)
            if value < 0 || value > semvmx {
                sets_lock.release()
                return errno.err, errno.erange
            }
            set.values[number] = value
            set.last_pid = proc.current_thread().process.pid
            progress_unlocked(mut set)
            sets_lock.release()
            return 0, 0
        }
        else {
            sets_lock.release()
            return errno.err, errno.einval
        }
    }
}

fn operate(id int, user_operations u64, count u32, timeout_address u64) (u64, u64) {
    // semtimedop imports its timeout before checking the vector. Duration
    // validation follows the vector copy, matching Linux's error precedence.
    mut duration := time.TimeSpec{}
    if timeout_address != 0 && !usercopy.copy_from_user(unsafe { voidptr(&duration) }, timeout_address, sizeof(time.TimeSpec)) {
        return errno.err, errno.efault
    }
    if count == 0 {
        return errno.err, errno.einval
    }
    if count > max_ops { return errno.err, errno.e2big }
    mut operations := [max_ops]SemBuf{}
    if !usercopy.copy_from_user(unsafe { voidptr(&operations[0]) }, user_operations, u64(count) * sizeof(SemBuf)) {
        return errno.err, errno.efault
    }
    // Unknown sem_flg bits are ignored by Linux.

    mut timer := &time.Timer(unsafe { nil })
    defer {
        if timer != unsafe { nil } {
            timer.disarm()
            unsafe { free(timer) }
        }
    }
    if timeout_address != 0 {
        if duration.tv_sec < 0 || duration.tv_nsec < 0 || duration.tv_nsec >= 1000000000 {
            return errno.err, errno.einval
        }
        timer = time.new_timer(duration)
    }

    sets_lock.acquire()
    mut set := find_id_unlocked(id)
    if set == unsafe { nil } || set.removed {
        sets_lock.release()
        return errno.err, errno.einval
    }
    // Reject an invalid semaphore anywhere in the copied vector before
    // retaining its frame in the queue, including after a potential blocker.
    for i in 0 .. int(count) {
        if int(operations[i].number) >= set.values.len {
            sets_lock.release()
            return errno.err, errno.efbig
        }
    }
    pid := proc.current_thread().process.pid
    mut proposed := [max_sems]int{}
    blocker, wait_zero, result := evaluate_unlocked(set, unsafe { &operations[0] }, int(count),
        unsafe { &proposed[0] })
    if result != 0 {
        sets_lock.release()
        return errno.err, result
    }
    if blocker < 0 {
        commit_unlocked(mut set, unsafe { &proposed[0] }, pid)
        progress_unlocked(mut set)
        sets_lock.release()
        return 0, 0
    }

    // Explicit stack storage avoids an escaping local being heap-promoted.
    // No queue/vector allocation occurs on the blocking path. The record's
    // private event also avoids a shared event's listener limit across waiters.
    mut pending := unsafe { &Pending(C.vinix_stack_alloc(sizeof(Pending))) }
    unsafe {
        *pending = Pending{
            operations: &operations[0]
            count: int(count)
            pid: pid
            blocker: blocker
            wait_zero: wait_zero
        }
    }
    set.waiters++
    link_unlocked(mut set, mut pending)

    for {
        generation := event.generation(mut pending.wake)
        sets_lock.release()
        mut storage := [unsafe { &pending.wake }, unsafe { &pending.wake }]!
        mut waiting := 1
        if timer != unsafe { nil } {
            storage[1] = &timer.event
            waiting = 2
        }
        mut events := unsafe { event.stack_list(&storage[0], waiting) }
        which := event.await_from_generation(mut events, true, 0, generation) or { u64(-1) }
        sets_lock.acquire()
        // Completion wins against later RMID, timer expiry or signal delivery.
        // Unlinking a granted frame did not release its pin or this stack event.
        if pending.completed {
            saved_result := pending.result
            release_waiter_unlocked(mut set, mut pending)
            sets_lock.release()
            if saved_result == 0 { return 0, 0 }
            return errno.err, saved_result
        }
        if set.removed {
            release_waiter_unlocked(mut set, mut pending)
            sets_lock.release()
            return errno.err, errno.eidrm
        }
        if which == u64(-1) || which == 1 {
            release_waiter_unlocked(mut set, mut pending)
            sets_lock.release()
            return errno.err, if which == 1 { errno.eagain } else { errno.eintr }
        }
        // A spurious wake retains its original queue position and lifetime
        // pin. Value changes are handled by the changer under sets_lock.
    }
    return 0, 0
}

pub fn syscall_semop(_ voidptr, id int, operations u64, count u32) (u64, u64) {
    return operate(id, operations, count, 0)
}

pub fn syscall_semtimedop(_ voidptr, id int, operations u64, count u32, timeout u64) (u64, u64) {
    return operate(id, operations, count, timeout)
}
