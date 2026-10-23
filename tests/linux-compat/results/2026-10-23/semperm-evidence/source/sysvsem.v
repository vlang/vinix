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
const getall = 13
const getncnt = 14
const getzcnt = 15
const setval = 16
const setall = 17
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
    // Creator and owner are identical until IPC_SET is implemented. These
    // scalar credentials and mode live with the set; no namespace is borrowed.
    uid u32
    gid u32
    mode u32
    user_ns u64
    values []int
    // Linux's sempid belongs to each semaphore, including zero operations.
    // Inline storage shares the set lifetime and needs no separate allocation.
    last_pid [max_sems]int
    removed bool
    // Pins include completed-but-not-yet-unwound syscall frames.
    waiters int
    pending_head &Pending = unsafe { nil }
    pending_tail &Pending = unsafe { nil }
}

struct Identity {
mut:
    uid u32
    gid u32
    groups [32]u32
    group_count int
    user_ns u64
    ipc_user_ns u64
    initial_user bool
    caps u64
}

// Copy credentials before taking sets_lock. Retain only scalar namespace IDs,
// never a process/group slice or a namespace pointer across either lock.
fn identity() Identity {
    process := proc.current_thread().process
    proc.lock_table()
    user_namespace := process.ns.user
    ipc_namespace := process.ns.ipc
    mut who := Identity{
        uid: process.euid
        gid: process.egid
        user_ns: if user_namespace == unsafe { nil } { u64(4026531837) } else { user_namespace.id }
        ipc_user_ns: if ipc_namespace == unsafe { nil } { u64(4026531837) } else { ipc_namespace.ipc_user_ns }
        initial_user: proc.is_initial_namespace(user_namespace)
        caps: process.caps.effective
    }
    for i, group in process.groups {
        if i >= who.groups.len { break }
        who.groups[i] = group
        who.group_count++
    }
    proc.unlock_table()
    return who
}

fn capable(who &Identity, set &Set, cap int) bool {
    return (who.initial_user || who.user_ns == set.user_ns)
        && who.caps & (u64(1) << cap) != 0
}

fn in_group(who &Identity, gid u32) bool {
    if who.gid == gid { return true }
    for i in 0 .. who.group_count {
        if who.groups[i] == gid { return true }
    }
    return false
}

fn may_use(who &Identity, set &Set, requested u32) bool {
    mut mode := set.mode
    if who.uid == set.uid { mode >>= 6 }
    else if in_group(who, set.gid) { mode >>= 3 }
    return requested & ~mode & 7 == 0 || capable(who, set, proc.cap_ipc_owner)
}

fn may_remove(who &Identity, set &Set) bool {
    return who.uid == set.uid || capable(who, set, proc.cap_sys_admin)
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

fn commit_unlocked(mut set Set, proposed &int, operations &SemBuf, count int, pid int) {
    for number in 0 .. set.values.len { set.values[number] = unsafe { proposed[number] } }
    // Record every index in a successful vector, even duplicate/net-zero
    // operations. Failed or still-blocked proposals never reach this point.
    for i in 0 .. count {
        number := int(unsafe { operations[i].number })
        set.last_pid[number] = pid
    }
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

// SETVAL/SETALL and successful semop process pending vectors under the same lock as
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
            commit_unlocked(mut set, unsafe { &proposed[0] }, pending.operations, pending.count, pending.pid)
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

pub fn syscall_semget(_ voidptr, key i32, nsems i32, flags i32) (u64, u64) {
    // Linux imports these registers as signed 32-bit ints and validates the
    // count before key lookup, including queries and exclusive creation.
    if nsems < 0 || nsems > max_sems { return errno.err, errno.einval }
    who := identity()
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
            requested := u32(flags) & 0o777
            if !may_use(&who, existing, (requested >> 6 | requested >> 3 | requested) & 7) {
                sets_lock.release()
                return errno.err, errno.eacces
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
    if nsems == 0 {
        sets_lock.release()
        return errno.err, errno.einval
    }
    if sets.len >= 4096 { sets_lock.release(); return errno.err, errno.enospc }
    charge := proc.reserve_kernel(.ipc, 4096) or { sets_lock.release(); return errno.err, errno.get() }
    id := next_id
    next_id++
    // destroy_unlocked() frees it with the set.
    values := []int{len: int(nsems)} @[freed]
    // Nothing slices the list, so growing can free the old block.
    sets.flags |= .noslices
    sets << &Set{
        kernel_charge: charge
        id: id
        key: key
        uid: who.uid
        gid: who.gid
        mode: u32(flags) & 0o777
        user_ns: who.ipc_user_ns
        values: values
    }
    sets_lock.release()
    return u64(id), 0
}

pub fn syscall_semctl(_ voidptr, id i32, number i32, command i32, argument u64) (u64, u64) {
    // Linux rejects a negative ID first, then validates SETVAL's signed
    // union member before looking up a nonnegative ID or checking semnum.
    if id < 0 { return errno.err, errno.einval }
    if command == setval && (i32(argument) < 0 || i32(argument) > semvmx) {
        return errno.err, errno.erange
    }
    // Unsupported commands do not acquire read/alter permission semantics.
    if command !in [ipc_rmid, getpid, getval, getall, getncnt, getzcnt, setval, setall] {
        return errno.err, errno.einval
    }
    who := identity()
    sets_lock.acquire()
    mut set := find_id_unlocked(int(id))
    if set == unsafe { nil } || set.removed {
        sets_lock.release()
        return errno.err, errno.einval
    }
    // SETVAL validates semnum before permissions. The other indexed queries
    // validate it afterwards; GETALL/SETALL and RMID ignore semnum entirely.
    if command == setval && (number < 0 || number >= set.values.len) {
        sets_lock.release()
        return errno.err, errno.einval
    }
    if command == ipc_rmid {
        if !may_remove(&who, set) { sets_lock.release(); return errno.err, errno.eperm }
    } else {
        requested := if command == setval || command == setall { u32(2) } else { u32(4) }
        if !may_use(&who, set, requested) { sets_lock.release(); return errno.err, errno.eacces }
        if command != getall && command != setall && (number < 0 || number >= set.values.len) {
            sets_lock.release()
            return errno.err, errno.einval
        }
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
        getall {
            // Linux exports exactly sem_nsems unsigned shorts and ignores
            // semnum. Snapshot under the lock before touching user memory.
            mut values := [max_sems]u16{}
            count := set.values.len
            for index in 0 .. count { values[index] = u16(set.values[index]) }
            sets_lock.release()
            if !usercopy.copy_to_user(argument, unsafe { voidptr(&values[0]) }, u64(count) * sizeof(u16)) {
                return errno.err, errno.efault
            }
            return 0, 0
        }
        setall {
            // Import the entire bounded array before range validation or any
            // mutation. User faults can sleep; keep no set pointer across the
            // unlocked import. IDs are not reused, so a fresh lookup below
            // either finds this same set or reports removal with EIDRM.
            mut values := [max_sems]u16{}
            count := set.values.len
            sets_lock.release()
            if !usercopy.copy_from_user(unsafe { voidptr(&values[0]) }, argument, u64(count) * sizeof(u16)) {
                return errno.err, errno.efault
            }
            for index in 0 .. count {
                if values[index] > semvmx {
                    return errno.err, errno.erange
                }
            }
            sets_lock.acquire()
            set = find_id_unlocked(int(id))
            if set == unsafe { nil } || set.removed {
                sets_lock.release()
                return errno.err, errno.eidrm
            }
            pid := proc.current_thread().process.pid
            for index in 0 .. count {
                set.values[index] = int(values[index])
                set.last_pid[index] = pid
            }
            progress_unlocked(mut set)
            sets_lock.release()
            return 0, 0
        }
        getpid {
            pid := set.last_pid[number]
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
            set.values[number] = value
            set.last_pid[number] = proc.current_thread().process.pid
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

fn operate(id i32, user_operations u64, count u32, timeout_address u64) (u64, u64) {
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

    who := identity()
    sets_lock.acquire()
    mut set := find_id_unlocked(int(id))
    if set == unsafe { nil } || set.removed {
        sets_lock.release()
        return errno.err, errno.einval
    }
    // Reject an invalid semaphore anywhere in the copied vector before
    // retaining its frame in the queue, including after a potential blocker.
    mut alter := false
    for i in 0 .. int(count) {
        if int(operations[i].number) >= set.values.len {
            sets_lock.release()
            return errno.err, errno.efbig
        }
        if operations[i].operation != 0 { alter = true }
    }
    if !may_use(&who, set, if alter { u32(2) } else { u32(4) }) {
        sets_lock.release()
        return errno.err, errno.eacces
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
        commit_unlocked(mut set, unsafe { &proposed[0] }, unsafe { &operations[0] }, int(count), pid)
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

pub fn syscall_semop(_ voidptr, id i32, operations u64, count u32) (u64, u64) {
    return operate(id, operations, count, 0)
}

pub fn syscall_semtimedop(_ voidptr, id i32, operations u64, count u32, timeout u64) (u64, u64) {
    return operate(id, operations, count, timeout)
}
