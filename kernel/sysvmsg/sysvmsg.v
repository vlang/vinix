// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sysvmsg

// Linux's 64-bit System V message queue ABI. The registry is fixed-size;
// queued and blocked-sender buffers share a bounded global byte budget.
// An operation retains its slot until user copies and event detachment finish.
import errno
import event
import event.eventstruct
import klock
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
const max_queues = 128
const max_message = u64(8192)
const default_queue_bytes = u64(16384)
const max_queue_bytes = u64(1024 * 1024)
const max_buffer_bytes = u64(32 * 1024 * 1024)

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
}

struct Message {
mut:
	next &Message = unsafe { nil }
	kind i64
	length u64
}

struct Queue {
mut:
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
}

__global (
	queues [max_queues]Queue
	queues_lock klock.Lock
	next_id = int(1)
	buffer_bytes u64
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
		queue.used = false
	}
}

fn free_message(message &Message) {
	buffer_bytes -= sizeof(Message) + message.length
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
	event.trigger(mut queue.wake, true)
	if queue.refs == 0 { queue.used = false }
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
	if next_id == 0x7fffffff { return errno.err, errno.enospc }
	for i in 0 .. max_queues {
		if queues[i].used { continue }
		queues[i] = Queue{
			used: true
			id: next_id
			ipc_ns: who.ipc_ns
			user_ns: who.ipc_user_ns
			info: QueueInfo{
				perm: IpcPerm{key: key, uid: who.uid, gid: who.gid, cuid: who.uid, cgid: who.gid, mode: u32(flags) & 0o777, seq: u16(next_id / max_queues)}
				ctime: now()
				qbytes: default_queue_bytes
			}
		}
		next_id++
		return u64(queues[i].id), 0
	}
	return errno.err, errno.enospc
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
	if allocation > max_buffer_bytes - buffer_bytes { queues_lock.release(); return errno.err, errno.enomem }
	buffer_bytes += allocation
	queue.refs++
	queues_lock.release()
	// One owned allocation includes the payload; nothing is sliced or boxed.
	mut message := unsafe { &Message(malloc(allocation)) } @[freed]
	if message == unsafe { nil } {
		queues_lock.acquire()
		buffer_bytes -= allocation
		finish(mut queue)
		queues_lock.release()
		return errno.err, errno.enomem
	}
	unsafe { *message = Message{kind: kind, length: length} }
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
			event.trigger(mut queue.wake, true)
			finish(mut queue)
			queues_lock.release()
			return 0, 0
		}
		if flags & ipc_nowait != 0 { result = errno.eagain; break }
		generation := event.generation(mut queue.wake)
		queues_lock.release()
		awoke := event.await_one_from_generation(mut queue.wake, true, generation) != none
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
	for message != unsafe { nil } {
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
	if flags & msg_copy != 0 { return errno.err, if flags & ipc_nowait == 0 || flags & msg_except != 0 { errno.einval } else { errno.enosys } }
	if flags & ~(ipc_nowait | msg_noerror | msg_except) != 0 { return errno.err, errno.einval }
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
		generation := event.generation(mut queue.wake)
		queues_lock.release()
		awoke := event.await_one_from_generation(mut queue.wake, true, generation) != none
		queues_lock.acquire()
		if queue.removed { result = errno.eidrm } else if !awoke { result = errno.eintr }
		if result != 0 { break }
	}
	if result != 0 {
		finish(mut queue)
		queues_lock.release()
		return errno.err, result
	}
	mut previous := &Message(unsafe { nil })
	mut cursor := queue.head
	for cursor != message { previous = cursor; cursor = cursor.next }
	if previous == unsafe { nil } { queue.head = message.next } else { previous.next = message.next }
	if queue.tail == message { queue.tail = previous }
	queue.info.cbytes -= message.length
	queue.info.qnum--
	queue.info.rtime = now()
	queue.info.lrpid = who.pid
	event.trigger(mut queue.wake, true)
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

pub fn syscall_msgctl(_ voidptr, id int, command int, address u64) (u64, u64) {
	cmd := command & ~0x100 // IPC_64: both architectures use this layout.
	if cmd != ipc_rmid && cmd != ipc_set && cmd != ipc_stat { return errno.err, errno.einval }
	mut incoming := QueueInfo{}
	if cmd == ipc_set && !usercopy.copy_from_user(unsafe { voidptr(&incoming) }, address, sizeof(QueueInfo)) { return errno.err, errno.efault }
	who := identity() or { return errno.err, errno.eidrm }
	defer { release_identity(who) }
	queues_lock.acquire()
	mut queue := find(id, who.ipc_ns)
	if queue == unsafe { nil } { queues_lock.release(); return errno.err, errno.einval }
	if cmd == ipc_stat {
		if !may_use(who, queue, 4) { queues_lock.release(); return errno.err, errno.eacces }
		info := queue.info
		queues_lock.release()
		if !usercopy.copy_to_user(address, unsafe { voidptr(&info) }, sizeof(QueueInfo)) { return errno.err, errno.efault }
		return 0, 0
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
	event.trigger(mut queue.wake, true)
	queues_lock.release()
	return 0, 0
}
