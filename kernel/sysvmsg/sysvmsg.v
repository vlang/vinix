// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sysvmsg

// Linux's 64-bit System V message queue ABI. The registry is fixed-size;
// queued and blocked-sender buffers share a bounded global byte budget.
// An operation retains its slot until user copies and event detachment finish.
import kbudget
import errno
import event
import event.eventstruct
import klock
import memory
import proc
import time
import usercopy

const ipc_creat = 0o1000
const ipc_excl = 0o2000
const ipc_nowait = 0o4000
const msg_noerror = 0o10000
const msg_except = 0o20000
const msg_copy = 0o40000
const ipc_rmid = 0
const ipc_set = 1
const ipc_stat = 2
const ipc_info = 3
const msg_stat = 11
const msg_info = 12
const msg_stat_any = 13
const max_queues = 256
const max_message = u64(8192)
const default_queue_bytes = u64(16384)
const max_queue_bytes = u64(1024 * 1024)
const max_buffer_bytes = u64(8 * 1024 * 1024)
const max_total_messages = u64(8192)

// ipc64_perm is 48 bytes and msqid64_ds is 120 on both supported ABIs.
@[packed]
struct IpcPerm {
mut:
	key i32
	uid u32
	gid u32
	cuid u32
	cgid u32
	mode u32
	seq u16
	pad2 u16
	pad3 u32
	unused1 u64
	unused2 u64
}

@[packed]
struct QueueInfo {
mut:
	perm IpcPerm
	stime i64
	rtime i64
	ctime i64
	cbytes u64
	qnum u64
	qbytes u64
	lspid i32
	lrpid i32
	unused1 u64
	unused2 u64
}

struct MsgInfo {
mut:
	pool i32
	map_count i32
	max_size i32
	queue_bytes i32
	queue_count i32
	segment_size i32
	total_messages i32
	segments u16
	pad u16
}

struct Waiter {
mut:
	next &Waiter = unsafe { nil }
	wake eventstruct.Event
}

struct Identity {
mut:
	uid u32
	gid u32
	groups [32]u32
	group_count int
	ipc_ns u64
	ipc_user_ns u64
	ipc_namespace &proc.Namespace = unsafe { nil }
	user_ns u64
	initial_user bool
	caps u64
	pid i32
	global_pid int
	pid_namespace u64
	initial_pid bool
}

struct Message {
mut:
	kernel_charge kbudget.Charge
	next &Message = unsafe { nil }
	kind i64
	length u64
}

struct Queue {
mut:
	kernel_charge kbudget.Charge
	used bool
	removed bool
	id int
	ipc_ns u64
	user_ns u64
	refs u64
	info QueueInfo
	head &Message = unsafe { nil }
	tail &Message = unsafe { nil }
	wake eventstruct.Event
	generation u64
	waiters &Waiter = unsafe { nil }
	sender_pid int
	sender_namespace u64
	receiver_pid int
	receiver_namespace u64
}

__global (
	queues [max_queues]Queue
	queues_lock klock.Lock
	sequences [max_queues]u16
	buffer_bytes u64
	buffer_messages u64
)

fn identity() ?Identity {
	process := proc.current_thread().process
	proc.lock_table()
	mut ipc_namespace := process.ns.ipc
	user_namespace := process.ns.user
	if ipc_namespace != unsafe { nil } && !proc.try_get_namespace(mut ipc_namespace) {
		proc.unlock_table()
		return none
	}
	mut result := Identity{
		uid: process.euid
		gid: process.egid
		ipc_ns: if ipc_namespace == unsafe { nil } { u64(4026531839) } else { ipc_namespace.id }
		ipc_user_ns: if ipc_namespace == unsafe { nil } { u64(4026531837) } else { ipc_namespace.ipc_user_ns }
		ipc_namespace: ipc_namespace
		user_ns: if user_namespace == unsafe { nil } { u64(4026531837) } else { user_namespace.id }
		initial_user: proc.is_initial_namespace(user_namespace)
		caps: process.caps.effective
		pid: i32(proc.pid_in(process, process.numbered_in))
		initial_pid: process.numbered_in == unsafe { nil } || proc.is_initial_namespace(process.numbered_in)
		global_pid: process.pid
		pid_namespace: if process.numbered_in == unsafe { nil } { u64(0) } else { process.numbered_in.id }
	}
	for i, group in process.groups {
		if i >= result.groups.len { break }
		result.groups[i] = group
		result.group_count++
	}
	proc.unlock_table()
	return result
}

fn release_identity(who Identity) {
	mut ns := who.ipc_namespace
	if ns != unsafe { nil } && proc.put_namespace(mut ns) {
		destroy_namespace(ns.id)
	}
}

fn capable(who Identity, queue &Queue, cap int) bool {
	return (who.initial_user || who.user_ns == queue.user_ns)
		&& who.caps & (u64(1) << cap) != 0
}

fn in_group(who Identity, gid u32) bool {
	if who.gid == gid { return true }
	for i in 0 .. who.group_count {
		if who.groups[i] == gid { return true }
	}
	return false
}

fn may_use(who Identity, queue &Queue, requested u32) bool {
	mut mode := queue.info.perm.mode
	if who.uid == queue.info.perm.uid || who.uid == queue.info.perm.cuid {
		mode >>= 6
	} else if in_group(who, queue.info.perm.gid) || in_group(who, queue.info.perm.cgid) {
		mode >>= 3
	}
	return requested & ~mode & 7 == 0 || capable(who, queue, proc.cap_ipc_owner)
}

fn may_control(who Identity, queue &Queue) bool {
	return who.uid == queue.info.perm.uid || who.uid == queue.info.perm.cuid
		|| capable(who, queue, proc.cap_sys_admin)
}

fn now() i64 {
	stamp := time.clock_now(time.clock_type_realtime) or { return 0 }
	return stamp.tv_sec
}

fn find(id int, ns u64) &Queue {
	for i in 0 .. max_queues {
		if queues[i].used && !queues[i].removed && queues[i].id == id && queues[i].ipc_ns == ns {
			return unsafe { &queues[i] }
		}
	}
	return unsafe { nil }
}

fn finish(mut queue Queue) {
	queue.refs--
	if queue.removed && queue.refs == 0 {
		// Every event waiter has detached before giving its reference back.
		kbudget.release(queue.kernel_charge)
		queue.kernel_charge = kbudget.Charge{}
		queue.used = false
	}
}

fn free_message(message &Message) {
	buffer_messages--
	buffer_bytes -= sizeof(Message) + message.length
	kbudget.release(message.kernel_charge)
	unsafe { free(message) }
}

fn remove(mut queue Queue) {
	queue.removed = true
	mut message := queue.head
	queue.head = unsafe { nil }
	queue.tail = unsafe { nil }
	queue.info.cbytes = 0
	queue.info.qnum = 0
	for message != unsafe { nil } {
		next := message.next
		free_message(message)
		message = next
	}
	wake_queue(mut queue)
	if queue.refs == 0 { kbudget.release(queue.kernel_charge); queue.kernel_charge = kbudget.Charge{}; queue.used = false }
}

// Called when the final process/nsfs reference to an IPC namespace goes away.
// No namespace pointer is kept in a queue, so destruction cannot borrow one.
pub fn destroy_namespace(ns u64) {
	queues_lock.acquire()
	for i in 0 .. max_queues {
		if queues[i].used && !queues[i].removed && queues[i].ipc_ns == ns {
			remove(mut queues[i])
		}
	}
	queues_lock.release()
}

pub fn syscall_msgget(_ voidptr, key i32, flags int) (u64, u64) {
	who := identity() or { return errno.err, errno.eidrm }
	defer { release_identity(who) }
	queues_lock.acquire()
	defer { queues_lock.release() }
	if key != 0 {
		for i in 0 .. max_queues {
			queue := unsafe { &queues[i] }
			if !queue.used || queue.removed || queue.ipc_ns != who.ipc_ns || queue.info.perm.key != key { continue }
			if flags & (ipc_creat | ipc_excl) == ipc_creat | ipc_excl { return errno.err, errno.eexist }
			requested := u32(flags) & 0o777
			if !may_use(who, queue, (requested >> 6 | requested >> 3 | requested) & 7) { return errno.err, errno.eacces }
			return u64(queue.id), 0
		}
		if flags & ipc_creat == 0 { return errno.err, errno.enoent }
	}
	for i in 0 .. max_queues {
		if queues[i].used { continue }
		charge := proc.reserve_kernel(.ipc, 4096) or { return errno.err, errno.get() }
		sequence := if sequences[i] >= 0x7fff { u16(1) } else { sequences[i] + 1 }
		sequences[i] = sequence
		queues[i] = Queue{
			kernel_charge: charge
			used: true
			id: (int(sequence) << 16) | i
			ipc_ns: who.ipc_ns
			user_ns: who.ipc_user_ns
			info: QueueInfo{
				perm: IpcPerm{key: key, uid: who.uid, gid: who.gid, cuid: who.uid, cgid: who.gid, mode: u32(flags) & 0o777, seq: sequence}
				ctime: now()
				qbytes: default_queue_bytes
			}
		}
		return u64(queues[i].id), 0
	}
	return errno.err, errno.enospc
}

// The permanent registry owns the queue. Every in-flight syscall retains a
// slot until its stack-owned waiter detaches and all checked user copies finish.
fn wake_queue(mut queue Queue) {
	queue.generation++
	mut waiter := queue.waiters
	for waiter != unsafe { nil } {
		event.trigger(mut waiter.wake, false)
		waiter = waiter.next
	}
}

fn wait_on_queue(mut queue Queue, generation u64) bool {
	mut waiter := unsafe { &Waiter(C.vinix_stack_alloc(sizeof(Waiter))) }
	unsafe { *waiter = Waiter{} }
	queues_lock.acquire()
	if queue.removed || queue.generation != generation {
		queues_lock.release()
		return true
	}
	waiter.next = queue.waiters
	queue.waiters = waiter
	queues_lock.release()
	awoken := event.await_one(mut waiter.wake, true) != none
	queues_lock.acquire()
	mut previous := &Waiter(unsafe { nil })
	mut current := queue.waiters
	for current != unsafe { nil } {
		if voidptr(current) == voidptr(waiter) {
			if previous == unsafe { nil } { queue.waiters = waiter.next }
			else { previous.next = waiter.next }
			break
		}
		previous = current
		current = current.next
	}
	queues_lock.release()
	return awoken
}

pub fn syscall_msgsnd(_ voidptr, id int, address u64, length u64, flags int) (u64, u64) {
	if id < 0 || length > max_message || flags & ~ipc_nowait != 0 { return errno.err, errno.einval }
	if !usercopy.user_range(address, 8 + length) { return errno.err, errno.efault }
	mut kind := i64(0)
	if !usercopy.copy_from_user(unsafe { voidptr(&kind) }, address, 8) { return errno.err, errno.efault }
	if kind <= 0 { return errno.err, errno.einval }
	who := identity() or { return errno.err, errno.eidrm }
	defer { release_identity(who) }
	queues_lock.acquire()
	mut queue := find(id, who.ipc_ns)
	if queue == unsafe { nil } { queues_lock.release(); return errno.err, errno.einval }
	if !may_use(who, queue, 2) { queues_lock.release(); return errno.err, errno.eacces }
	allocation := sizeof(Message) + length
	if buffer_messages >= max_total_messages || allocation > max_buffer_bytes - buffer_bytes { queues_lock.release(); return errno.err, errno.enomem }
	charge := proc.reserve_kernel(.ipc, allocation * 2 + 128) or { queues_lock.release(); return errno.err, errno.get() }
	buffer_bytes += allocation
	buffer_messages++
	queue.refs++
	queues_lock.release()
	// One owned allocation includes the payload; nothing is sliced or boxed.
	mut message := unsafe { &Message(memory.malloc_packed_fallible(allocation)) } @[freed]
	if message == unsafe { nil } {
		kbudget.release(charge)
		queues_lock.acquire()
		buffer_messages--
		buffer_bytes -= allocation
		finish(mut queue)
		queues_lock.release()
		return errno.err, errno.enomem
	}
	unsafe { *message = Message{kind: kind, length: length, kernel_charge: charge} }
	mut result := u64(0)
	if !usercopy.copy_from_user(voidptr(u64(message) + sizeof(Message)), address + 8, length) {
		result = errno.efault
	}
	queues_lock.acquire()
	for result == 0 {
		if queue.removed { result = errno.eidrm; break }
		if !may_use(who, queue, 2) { result = errno.eacces; break }
		if length <= queue.info.qbytes && queue.info.cbytes <= queue.info.qbytes - length
			&& queue.info.qnum < queue.info.qbytes {
			if queue.tail == unsafe { nil } { queue.head = message } else { queue.tail.next = message }
			queue.tail = message
			queue.info.cbytes += length
			queue.info.qnum++
			queue.info.stime = now()
			queue.info.lspid = who.pid
			queue.sender_pid = who.global_pid
			queue.sender_namespace = who.pid_namespace
			wake_queue(mut queue)
			finish(mut queue)
			queues_lock.release()
			return 0, 0
		}
		if flags & ipc_nowait != 0 { result = errno.eagain; break }
		generation := queue.generation
		queues_lock.release()
		awoke := wait_on_queue(mut queue, generation)
		queues_lock.acquire()
		if queue.removed { result = errno.eidrm } else if !awoke { result = errno.eintr }
	}
	free_message(message)
	finish(mut queue)
	queues_lock.release()
	return errno.err, result
}

fn select_message(queue &Queue, kind i64, flags int) &Message {
	mut selected := &Message(unsafe { nil })
	mut message := queue.head
	mut ordinal := i64(0)
	for message != unsafe { nil } {
		if flags & msg_copy != 0 {
			if ordinal == kind { return message }
			ordinal++
			message = message.next
			continue
		}
		if kind == 0 || (kind > 0 && if flags & msg_except != 0 { message.kind != kind } else { message.kind == kind }) {
			return message
		}
		// Unsigned negation also handles LONG_MIN without signed overflow.
		if kind < 0 && u64(message.kind) <= u64(~kind) + 1
			&& (selected == unsafe { nil } || message.kind < selected.kind) { selected = message }
		message = message.next
	}
	return selected
}

pub fn syscall_msgrcv(_ voidptr, id int, address u64, capacity u64, kind i64, flags int) (u64, u64) {
	if id < 0 || capacity > u64(0x7fffffffffffffff) { return errno.err, errno.einval }
	copying := flags & msg_copy != 0
	if copying && (flags & ipc_nowait == 0 || flags & msg_except != 0 || kind < 0) { return errno.err, errno.einval }
	if flags & ~(ipc_nowait | msg_noerror | msg_except | msg_copy) != 0 { return errno.err, errno.einval }
	if !usercopy.user_range(address, 8) { return errno.err, errno.efault }
	who := identity() or { return errno.err, errno.eidrm }
	defer { release_identity(who) }
	queues_lock.acquire()
	mut queue := find(id, who.ipc_ns)
	if queue == unsafe { nil } { queues_lock.release(); return errno.err, errno.einval }
	if !may_use(who, queue, 4) { queues_lock.release(); return errno.err, errno.eacces }
	queue.refs++
	mut result := u64(0)
	mut message := &Message(unsafe { nil })
	for {
		if queue.removed { result = errno.eidrm; break }
		if !may_use(who, queue, 4) { result = errno.eacces; break }
		message = select_message(queue, kind, flags)
		if message != unsafe { nil } {
			if message.length > capacity && flags & msg_noerror == 0 { result = errno.e2big }
			break
		}
		if flags & ipc_nowait != 0 { result = errno.enomsg; break }
		generation := queue.generation
		queues_lock.release()
		awoke := wait_on_queue(mut queue, generation)
		queues_lock.acquire()
		if queue.removed { result = errno.eidrm } else if !awoke { result = errno.eintr }
		if result != 0 { break }
	}
	if result != 0 {
		finish(mut queue)
		queues_lock.release()
		return errno.err, result
	}
	if copying {
		length := if message.length < capacity { message.length } else { capacity }
		allocation := sizeof(Message) + length
		if buffer_messages >= max_total_messages || allocation > max_buffer_bytes - buffer_bytes {
			finish(mut queue); queues_lock.release(); return errno.err, errno.enomem
		}
		charge := proc.reserve_kernel(.ipc, allocation * 2 + 128) or { finish(mut queue); queues_lock.release(); return errno.err, errno.get() }
		mut snapshot := unsafe { &Message(memory.malloc_packed_fallible(allocation)) } @[freed]
		if snapshot == unsafe { nil } { kbudget.release(charge); finish(mut queue); queues_lock.release(); return errno.err, errno.enomem }
		unsafe {
			*snapshot = Message{kind: message.kind, length: length, kernel_charge: charge}
			C.memcpy(voidptr(u64(snapshot) + sizeof(Message)), voidptr(u64(message) + sizeof(Message)), length)
		}
		buffer_bytes += allocation
		buffer_messages++
		message = snapshot
	} else {
		mut previous := &Message(unsafe { nil })
		mut cursor := queue.head
		for cursor != message { previous = cursor; cursor = cursor.next }
		if previous == unsafe { nil } { queue.head = message.next } else { previous.next = message.next }
		if queue.tail == message { queue.tail = previous }
		queue.info.cbytes -= message.length
		queue.info.qnum--
		queue.info.rtime = now()
		queue.info.lrpid = who.pid
		queue.receiver_pid = who.global_pid
		queue.receiver_namespace = who.pid_namespace
		wake_queue(mut queue)
	}
	queues_lock.release()
	length := if message.length < capacity { message.length } else { capacity }
	// Once removed from the queue this operation alone owns the message.
	// As on Linux, a failed output copy consumes the selected message.
	if !usercopy.user_range(address, 8 + length)
		|| !usercopy.copy_to_user(address, unsafe { voidptr(&message.kind) }, 8)
		|| !usercopy.copy_to_user(address + 8, voidptr(u64(message) + sizeof(Message)), length) { result = errno.efault }
	queues_lock.acquire()
	free_message(message)
	finish(mut queue)
	queues_lock.release()
	if result != 0 { return errno.err, result }
	return length, 0
}

fn visible_pid(who Identity, global int, local i32, namespace u64) i32 {
	if who.initial_pid { return i32(global) }
	return if who.pid_namespace == namespace { local } else { i32(0) }
}

pub fn syscall_msgctl(_ voidptr, id int, command int, address u64) (u64, u64) {
	if id < 0 || command < 0 { return errno.err, errno.einval }
	cmd := command & ~0x100
	who := identity() or { return errno.err, errno.eidrm }
	defer { release_identity(who) }
	if cmd == ipc_info || cmd == msg_info {
		mut info := unsafe { &MsgInfo(C.vinix_stack_alloc(sizeof(MsgInfo))) }
		unsafe { *info = MsgInfo{
			pool: i32(max_buffer_bytes / 1024)
			map_count: i32(max_total_messages)
			max_size: i32(max_message)
			queue_bytes: i32(default_queue_bytes)
			queue_count: max_queues
			segment_size: 16
			total_messages: i32(max_total_messages)
			segments: 65535
		} }
		if cmd == msg_info { info.pool = 0; info.map_count = 0; info.total_messages = 0 }
		mut highest := 0
		queues_lock.acquire()
		for i in 0 .. max_queues {
			q := unsafe { &queues[i] }
			if !q.used || q.removed || q.ipc_ns != who.ipc_ns { continue }
			highest = i
			if cmd == msg_info {
				info.pool++
				info.map_count += i32(q.info.qnum)
				info.total_messages += i32(q.info.cbytes)
			}
		}
		queues_lock.release()
		if !usercopy.copy_to_user(address, info, sizeof(MsgInfo)) { return errno.err, errno.efault }
		return u64(highest), 0
	}
	if cmd != ipc_rmid && cmd != ipc_set && cmd != ipc_stat && cmd != msg_stat && cmd != msg_stat_any {
		return errno.err, errno.einval
	}
	mut incoming := unsafe { &QueueInfo(C.vinix_stack_alloc(sizeof(QueueInfo))) }
	unsafe { *incoming = QueueInfo{} }
	if cmd == ipc_set && !usercopy.copy_from_user(incoming, address, sizeof(QueueInfo)) { return errno.err, errno.efault }
	queues_lock.acquire()
	mut queue := if cmd == msg_stat || cmd == msg_stat_any {
		if id < max_queues { unsafe { &queues[id] } } else { &Queue(unsafe { nil }) }
	} else { find(id, who.ipc_ns) }
	if queue == unsafe { nil } || !queue.used || queue.removed || queue.ipc_ns != who.ipc_ns {
		queues_lock.release(); return errno.err, errno.einval
	}
	if cmd == ipc_stat || cmd == msg_stat || cmd == msg_stat_any {
		if cmd != msg_stat_any && !may_use(who, queue, 4) { queues_lock.release(); return errno.err, errno.eacces }
		mut info := unsafe { &QueueInfo(C.vinix_stack_alloc(sizeof(QueueInfo))) }
		unsafe { *info = queue.info }
		info.lspid = visible_pid(who, queue.sender_pid, queue.info.lspid, queue.sender_namespace)
		info.lrpid = visible_pid(who, queue.receiver_pid, queue.info.lrpid, queue.receiver_namespace)
		result := if cmd == ipc_stat { 0 } else { queue.id }
		queues_lock.release()
		if !usercopy.copy_to_user(address, info, sizeof(QueueInfo)) { return errno.err, errno.efault }
		return u64(result), 0
	}
	if !may_control(who, queue) { queues_lock.release(); return errno.err, errno.eperm }
	if cmd == ipc_rmid { remove(mut queue); queues_lock.release(); return 0, 0 }
	if incoming.qbytes > max_queue_bytes { queues_lock.release(); return errno.err, errno.einval }
	if incoming.qbytes > default_queue_bytes && !capable(who, queue, proc.cap_sys_resource) { queues_lock.release(); return errno.err, errno.eperm }
	queue.info.perm.uid = incoming.perm.uid
	queue.info.perm.gid = incoming.perm.gid
	queue.info.perm.mode = incoming.perm.mode & 0o777
	queue.info.qbytes = incoming.qbytes
	queue.info.ctime = now()
	wake_queue(mut queue)
	queues_lock.release()
	return 0, 0
}
