// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module mqueue

// POSIX message queues: mq_open, mq_unlink, mq_timedsend, mq_timedreceive,
// mq_notify and mq_getsetattr, with Linux 6.12's semantics. A queue is a
// resource behind its descriptors and, while it has a name, in the registry
// of its IPC namespace. The registry holds one reference, every descriptor
// one and every syscall using a queue one through its descriptor; the last
// reference frees it. Messages are kept highest priority first, oldest first
// within a priority. A sender of a full queue waits holding its message and a
// receiver of an empty one waits for a message handed to it, as on Linux.
// One lock covers the registry and every queue's state.
import errno
import event
import event.eventstruct
import file
import fs as vfs
import katomic
import kbudget
import klock
import memory
import proc
import resource
import socket.netlink
import stat
import time
import userland
import usercopy

const name_max = 255
const path_max = 4096
const prio_max = u32(32768)
// The IPC namespace's msg_max and msgsize_max sysctls, and their defaults.
const default_maxmsg = i64(10)
const default_msgsize = i64(8192)
// HARD_MSGMAX and HARD_MSGSIZEMAX: what CAP_SYS_RESOURCE may ask for.
const hard_maxmsg = i64(65536)
const hard_msgsize = i64(16 * 1024 * 1024)
// queues_max: how many queues an IPC namespace has for unprivileged users.
const queues_max = 256
// What Linux charges to RLIMIT_MSGQUEUE per possible message: a msg_msg and,
// for up to MQ_PRIO_MAX of them, a priority tree node.
const message_overhead = u64(48)
const tree_node_size = u64(48)
// FILENT_SIZE, the size a queue's inode reports.
const queue_file_size = 80
const sigev_signal = 0
const sigev_none = 1
const sigev_thread = 2
const notify_cookie_len = 32
const notify_wokenup = u8(1)
const notify_removed = u8(2)
const pollin = 0x001
const pollout = 0x004
const pollrdnorm = 0x040
const pollwrnorm = 0x100
const initial_ipc_namespace = u64(4026531839)

// struct mq_attr.
struct Attr {
mut:
	flags    i64
	maxmsg   i64
	msgsize  i64
	curmsgs  i64
	reserved [4]i64
}

// struct sigevent, 64 bytes on both architectures.
struct SigEvent {
mut:
	value  u64
	signo  i32
	notify i32
	rest   [48]u8
}

// The payload follows the header in the same allocation.
struct Message {
mut:
	kernel_charge kbudget.Charge
	next          &Message = unsafe { nil }
	priority      u32
	length        u64
}

// A blocked sender or receiver, on its own stack. A receiver is handed its
// message; a sender's message is taken from it into the queue. The syscall
// frame keeps its own thread alive until it is removed under mq_lock.
struct Waiter {
mut:
	next    &Waiter = unsafe { nil }
	task    &proc.Thread = unsafe { nil }
	wake    eventstruct.Event
	ready   bool
	message &Message = unsafe { nil }
}

// A notification to send once the lock is let go.
struct Delivery {
mut:
	pid    int
	start  u64
	exec_count u64
	signal int
	value  u64
	socket &resource.Resource = unsafe { nil }
	cookie [32]u8
}

pub struct Queue {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	// The interface box its descriptors share, freed with the queue.
	box           &resource.Resource = unsafe { nil }
	kernel_charge kbudget.Charge
	all_next      &Queue = unsafe { nil }
	all_prev      &Queue = unsafe { nil }
	dead_next     &Queue = unsafe { nil }
	node          &vfs.VFSNode = unsafe { nil }
	name          [256]u8
	name_len      int
	ipc_ns        u64
	linked        bool
	// The creator's real uid and what the queue counts against its
	// RLIMIT_MSGQUEUE until it is freed.
	user    u32
	charged u64
	maxmsg  i64
	msgsize i64
	curmsgs i64
	qsize   u64
	head    &Message = unsafe { nil }
	tail    &Message = unsafe { nil }
	senders   &Waiter = unsafe { nil }
	receivers &Waiter = unsafe { nil }
	// The registered notification: the owner's global pid and start time.
	notify_owner  int
	notify_start  u64
	notify_exec_count u64
	notify_kind   int
	notify_signal int
	notify_value  u64
	notify_socket &resource.Resource = unsafe { nil }
	notify_cookie [32]u8
}

__global (
	mq_lock   klock.Lock
	mq_queues &Queue
	mq_device u64
	mq_inodes u64
)

// ── credentials and namespaces ───────────────────────────────────────────────

// The caller's IPC namespace, retained for the call so that queues are never
// made in one that has been destroyed. nil is the initial namespace.
fn enter_namespace() (&proc.Namespace, u64, bool) {
	process := proc.current_thread().process
	proc.lock_table()
	mut ns := process.ns.ipc
	if ns != unsafe { nil } && !proc.try_get_namespace(mut ns) {
		proc.unlock_table()
		return unsafe { nil }, u64(0), false
	}
	proc.unlock_table()
	id := if ns == unsafe { nil } { initial_ipc_namespace } else { ns.id }
	return ns, id, true
}

// Called without mq_lock: the last reference destroys the namespace's queues.
fn leave_namespace(ns &proc.Namespace) {
	mut held := unsafe { ns }
	if held != unsafe { nil } {
		proc.put_namespace(mut held)
	}
}

// A permission override on a queue. Linux grants it from a child user
// namespace only for a queue whose owner is mapped there; Vinix maps one id,
// the creator's, who owns such a queue anyway, so only the initial user
// namespace overrides.
fn has_capability(process &proc.Process, cap int) bool {
	return proc.has_capability(process, cap)
}

// capable(): the capability in the initial user namespace.
fn capable(process &proc.Process, cap int) bool {
	return proc.is_initial_namespace(process.ns.user) && has_capability(process, cap)
}

fn in_group(process &proc.Process, gid u32) bool {
	if process.fsgid == gid {
		return true
	}
	for group in process.groups {
		if group == gid {
			return true
		}
	}
	return false
}

// inode_permission() on the queue with the filesystem ids.
fn permitted(process &proc.Process, queue &Queue, requested u32) bool {
	mode := queue.stat.mode
	mut allowed := mode & 0o7
	if process.fsuid == queue.stat.uid {
		allowed = (mode >> 6) & 0o7
	} else if in_group(process, queue.stat.gid) {
		allowed = (mode >> 3) & 0o7
	}
	if allowed & requested == requested || has_capability(process, proc.cap_dac_override) {
		return true
	}
	read_search := if stat.isdir(mode) { u32(5) } else { u32(4) }
	return requested & ~read_search == 0 && has_capability(process, proc.cap_dac_read_search)
}

// The sticky root directory's rule: the queue's owner, the directory's
// (root) or CAP_FOWNER may remove a queue.
fn may_remove(process &proc.Process, queue &Queue, dir_uid u32) bool {
	return process.fsuid == queue.stat.uid || process.fsuid == dir_uid
		|| has_capability(process, proc.cap_fowner)
}

// ── names ────────────────────────────────────────────────────────────────────

// getname() and lookup_one_len(): a NUL-terminated name of one component.
fn user_name(address u64) ?string {
	name := usercopy.copy_cstring_from_user(address, path_max)?
	mut code := u64(0)
	if name.len == 0 {
		code = errno.enoent
	} else if name == '.' || name == '..' {
		code = errno.eacces
	} else {
		for i in 0 .. name.len {
			if name[i] == `/` {
				code = errno.eacces
				break
			}
		}
		if code == 0 && name.len > name_max {
			code = errno.enametoolong
		}
	}
	if code != 0 {
		unsafe { name.free() }
		errno.set(code)
		return none
	}
	return name
}

fn same_name(queue &Queue, name string) bool {
	if queue.name_len != name.len {
		return false
	}
	for i in 0 .. name.len {
		if queue.name[i] != name[i] {
			return false
		}
	}
	return true
}

fn find_locked(ns u64, name string) &Queue {
	mut queue := mq_queues
	for queue != unsafe { nil } {
		if queue.linked && queue.ipc_ns == ns && same_name(queue, name) {
			return queue
		}
		queue = queue.all_next
	}
	return unsafe { nil }
}

// ── accounting ───────────────────────────────────────────────────────────────

fn queue_bytes(maxmsg i64, msgsize i64) u64 {
	count := u64(maxmsg)
	nodes := if count < u64(prio_max) { count } else { u64(prio_max) }
	return count * message_overhead + nodes * tree_node_size + count * u64(msgsize)
}

// Every queue counts until it is freed, unlinked ones too, as on Linux.
fn user_bytes_locked(uid u32) u64 {
	mut total := u64(0)
	mut queue := mq_queues
	for queue != unsafe { nil } {
		if queue.user == uid {
			total += queue.charged
		}
		queue = queue.all_next
	}
	return total
}

fn namespace_queues_locked(ns u64) int {
	mut count := 0
	mut queue := mq_queues
	for queue != unsafe { nil } {
		if queue.ipc_ns == ns {
			count++
		}
		queue = queue.all_next
	}
	return count
}

// ── queue lifetime ───────────────────────────────────────────────────────────

fn allocate_queue() ?&Queue {
	// Allow for the resource box and a pathname node if the namespace mounts
	// mqueuefs later. No new charge or resource reference is needed on lookup.
	charge := proc.reserve_kernel(.ipc, sizeof(Queue) + sizeof(vfs.VFSNode) + name_max + 512)?
	mut queue := unsafe { &Queue(memory.malloc_packed_fallible(sizeof(Queue))) }
	if queue == unsafe { nil } {
		kbudget.release(charge)
		errno.set(errno.enomem)
		return none
	}
	unsafe { C.memset(queue, 0, sizeof(Queue)) }
	queue.kernel_charge = charge
	queue.box = &resource.Resource(unsafe { queue }) @[freed]
	return queue
}

// A queue nothing refers to any more, or one never published.
fn free_queue(mut queue Queue) {
	mut message := queue.head
	for message != unsafe { nil } {
		next := message.next
		free_message(message)
		message = next
	}
	queue.head = unsafe { nil }
	if queue.notify_socket != unsafe { nil } {
		mut socket := queue.notify_socket
		queue.notify_socket = unsafe { nil }
		socket.unref(unsafe { nil }) or {}
	}
	kbudget.release(queue.kernel_charge)
	unsafe {
		free(voidptr(queue.box))
		free(voidptr(queue))
	}
}

fn link_all_locked(mut queue Queue) {
	queue.all_prev = unsafe { nil }
	queue.all_next = mq_queues
	if mq_queues != unsafe { nil } {
		mq_queues.all_prev = queue
	}
	mq_queues = queue
}

fn unlink_all_locked(mut queue Queue) {
	if queue.all_prev == unsafe { nil } {
		mq_queues = queue.all_next
	} else {
		queue.all_prev.all_next = queue.all_next
	}
	if queue.all_next != unsafe { nil } {
		queue.all_next.all_prev = queue.all_prev
	}
	queue.all_next = unsafe { nil }
	queue.all_prev = unsafe { nil }
}

// Drop the registry's reference to a named queue. True when that was the
// last one: the queue is off every list and the caller frees it unlocked.
fn unname_locked(mut queue Queue) bool {
	queue.linked = false
	queue.stat.nlink = 0
	queue.stat.ctim = now()
	if queue.node != unsafe { nil } {
		mut node := queue.node
		queue.node = unsafe { nil }
		mut dir := unsafe { &Queue(node.parent.resource) }
		dir_entry_changed(mut dir, -directory_entry_size, queue.stat.ctim)
		vfs.retire_mqueue_child(mut node)
	}
	if katomic.dec(mut &queue.refcount) {
		return false
	}
	unlink_all_locked(mut queue)
	return true
}

fn (mut this Queue) release() {
	if katomic.dec(mut &this.refcount) {
		return
	}
	// No name, no descriptor and no syscall refers to it: nothing can find it.
	mq_lock.acquire()
	unlink_all_locked(mut this)
	mq_lock.release()
	free_queue(mut this)
}

// Retire the namespace's creation authority. Surviving mount views still
// expose existing names, including to processes in different namespaces.
pub fn destroy_namespace(ns u64) {
	mq_lock.acquire()
	if ns in mq_roots {
		mut root := unsafe { mq_roots[ns] }
		root.linked = false
		if vfs.mqueue_has_views(root.node) {
			mq_lock.release()
			return
		}
	}
	dead := unname_namespace_locked(ns)
	mq_lock.release()
	free_unnamed_queues(dead)
}

fn unname_namespace_locked(ns u64) &Queue {
	mq_roots.delete(ns)
	mut dead := &Queue(unsafe { nil })
	mut queue := mq_queues
	for queue != unsafe { nil } {
		next := queue.all_next
		if queue.linked && queue.ipc_ns == ns && unname_locked(mut queue) {
			queue.dead_next = dead
			dead = queue
		}
		queue = next
	}
	return dead
}

fn free_unnamed_queues(first &Queue) {
	mut dead := unsafe { first }
	for dead != unsafe { nil } {
		next := dead.dead_next
		free_queue(mut dead)
		dead = next
	}
}

// ── messages ─────────────────────────────────────────────────────────────────

fn new_message(address u64, length u64, priority u32) ?&Message {
	allocation := sizeof(Message) + length
	charge := proc.reserve_kernel(.ipc, allocation + 64)?
	mut message := unsafe { &Message(memory.malloc_packed_fallible(allocation)) } @[freed]
	if message == unsafe { nil } {
		kbudget.release(charge)
		errno.set(errno.enomem)
		return none
	}
	unsafe {
		*message = Message{
			kernel_charge: charge
			priority:      priority
			length:        length
		}
	}
	if length != 0 && !usercopy.copy_from_user(voidptr(u64(message) + sizeof(Message)), address, length) {
		free_message(message)
		errno.set(errno.efault)
		return none
	}
	return message
}

fn free_message(message &Message) {
	kbudget.release(message.kernel_charge)
	unsafe { free(voidptr(message)) }
}

fn (mut this Queue) insert_locked(message &Message) {
	mut added := unsafe { message }
	added.next = unsafe { nil }
	if this.tail == unsafe { nil } || this.tail.priority >= added.priority {
		// The common case, one priority or a lower one: append.
		if this.tail == unsafe { nil } {
			this.head = added
		} else {
			this.tail.next = added
		}
		this.tail = added
	} else {
		mut previous := &Message(unsafe { nil })
		mut cursor := this.head
		for cursor != unsafe { nil } && cursor.priority >= added.priority {
			previous = cursor
			cursor = cursor.next
		}
		added.next = cursor
		if previous == unsafe { nil } {
			this.head = added
		} else {
			previous.next = added
		}
	}
	this.curmsgs++
	this.qsize += added.length
}

fn (mut this Queue) take_locked() &Message {
	mut message := this.head
	this.head = message.next
	if this.head == unsafe { nil } {
		this.tail = unsafe { nil }
	}
	message.next = unsafe { nil }
	this.curmsgs--
	this.qsize -= message.length
	return message
}

fn (mut this Queue) changed_locked() {
	mut status := 0
	if this.curmsgs > 0 {
		status |= pollin | pollrdnorm
	}
	if this.curmsgs < this.maxmsg {
		status |= pollout | pollwrnorm
	}
	katomic.store(mut &this.status, status)
	event.trigger(mut this.event, false)
}

fn now() time.TimeSpec {
	return time.clock_now(time.clock_type_realtime) or { time.TimeSpec{} }
}

// Linux sets all three times on a send or receive.
fn (mut this Queue) touch_locked() {
	stamp := now()
	this.stat.atim = stamp
	this.stat.mtim = stamp
	this.stat.ctim = stamp
}

// ── waiting ──────────────────────────────────────────────────────────────────

fn before(a time.TimeSpec, b time.TimeSpec) bool {
	return a.tv_sec < b.tv_sec || (a.tv_sec == b.tv_sec && a.tv_nsec < b.tv_nsec)
}

// prepare_timeout(): an absolute CLOCK_REALTIME time.
fn read_deadline(address u64, deadline &time.TimeSpec) u64 {
	if !usercopy.copy_from_user(voidptr(deadline), address, sizeof(time.TimeSpec)) {
		return errno.efault
	}
	if deadline.tv_sec < 0 || u64(deadline.tv_nsec) >= 1000000000 {
		return errno.einval
	}
	return 0
}

fn waiter_rank(task &proc.Thread) int {
	rank := proc.effective_sched_rank(task)
	// Linux's task priority uses nice for ordinary policies, including IDLE.
	return if rank > proc.rank_realtime_base { rank } else { 20 - proc.nice_value(task) }
}

fn (mut this Queue) enqueue_waiter(waiter &Waiter, sending bool) {
	mut added := unsafe { waiter }
	added.task = proc.current_thread()
	rank := waiter_rank(added.task)
	mut slot := if sending { unsafe { &this.senders } } else { unsafe { &this.receivers } }
	mut current := unsafe { *slot }
	// The head receives the next handoff. Use the last qualifying slot to
	// match Linux's reverse traversal even after a queued task changes nice.
	for current != unsafe { nil } {
		if waiter_rank(current.task) >= rank {
			slot = unsafe { &current.next }
		}
		current = current.next
	}
	unsafe {
		added.next = *slot
		*slot = added
	}
}

fn (mut this Queue) dequeue_waiter(waiter &Waiter, sending bool) {
	mut previous := &Waiter(unsafe { nil })
	mut current := if sending { this.senders } else { this.receivers }
	for current != unsafe { nil } {
		if voidptr(current) == voidptr(waiter) {
			if previous == unsafe { nil } {
				if sending {
					this.senders = current.next
				} else {
					this.receivers = current.next
				}
			} else {
				previous.next = current.next
			}
			return
		}
		previous = current
		current = current.next
	}
}

// wq_sleep(): called and returning with mq_lock held. 0 once the waiter is
// ready, ETIMEDOUT, or the restartable interruption. The waiter is off the
// list on return either way.
fn (mut this Queue) wait_locked(waiter &Waiter, sending bool, deadline &time.TimeSpec) u64 {
	if deadline != unsafe { nil } && !before(now(), *deadline) {
		return errno.etimedout
	}
	this.enqueue_waiter(waiter, sending)
	mq_lock.release()
	mut timer := &time.Timer(unsafe { nil })
	storage := unsafe { &&eventstruct.Event(C.vinix_stack_alloc(2 * sizeof(voidptr))) }
	mut watched := unsafe { waiter }
	unsafe {
		storage[0] = &watched.wake
	}
	mut count := 1
	if deadline != unsafe { nil } {
		timer = time.new_realtime_timer(*deadline)
		unsafe {
			storage[1] = &timer.event
		}
		count = 2
	}
	mut events := unsafe { event.stack_list(storage, count) }
	mut result := u64(0)
	for {
		mut woken := true
		which := event.await(mut events, true) or {
			woken = false
			u64(0)
		}
		mq_lock.acquire()
		if watched.ready {
			break
		}
		if !woken {
			result = u64(proc.interrupted_errno)
			break
		}
		if which == 1 {
			result = errno.etimedout
			break
		}
		mq_lock.release()
	}
	if timer != unsafe { nil } {
		timer.disarm()
		unsafe { free(timer) }
	}
	if watched.ready {
		return 0
	}
	this.dequeue_waiter(waiter, sending)
	return result
}

// ── notification ─────────────────────────────────────────────────────────────

fn (mut this Queue) clear_notification_locked() {
	this.notify_owner = 0
	this.notify_start = 0
	this.notify_exec_count = 0
	this.notify_kind = 0
	this.notify_signal = 0
	this.notify_value = 0
	this.notify_socket = unsafe { nil }
}

// __do_notify(): the queue went from empty to one message with no receiver
// waiting. The registration is used up.
fn (mut this Queue) fire_notification_locked(mut delivery Delivery) {
	if this.notify_owner == 0 {
		return
	}
	match this.notify_kind {
		sigev_signal {
			delivery.pid = this.notify_owner
			delivery.start = this.notify_start
			delivery.exec_count = this.notify_exec_count
			delivery.signal = this.notify_signal
			delivery.value = this.notify_value
		}
		sigev_thread {
			delivery.socket = this.notify_socket
			unsafe { C.memcpy(&delivery.cookie[0], &this.notify_cookie[0], notify_cookie_len) }
			delivery.cookie[notify_cookie_len - 1] = notify_wokenup
		}
		else {}
	}
	this.clear_notification_locked()
}

// remove_notification(): a SIGEV_THREAD helper is told it will not be called.
fn (mut this Queue) remove_notification_locked(mut delivery Delivery) {
	if this.notify_kind == sigev_thread && this.notify_socket != unsafe { nil } {
		delivery.socket = this.notify_socket
		unsafe { C.memcpy(&delivery.cookie[0], &this.notify_cookie[0], notify_cookie_len) }
		delivery.cookie[notify_cookie_len - 1] = notify_removed
	}
	this.clear_notification_locked()
}

// Sends what the queue's lock saw to, and gives back the socket's reference.
fn deliver(delivery &Delivery) {
	if delivery.signal > 0 {
		userland.signal_message_queue_owner(delivery.pid, delivery.start, delivery.exec_count,
			delivery.signal, delivery.value)
	}
	if delivery.socket != unsafe { nil } {
		mut socket := delivery.socket
		if mut socket is netlink.NetlinkSocket {
			socket.queue_kernel_datagram(unsafe { &delivery.cookie[0] }, notify_cookie_len)
		}
		socket.unref(unsafe { nil }) or {}
	}
}

// ── resource ─────────────────────────────────────────────────────────────────

fn (mut this Queue) poll_status(_ int) int {
	return katomic.load(&this.status)
}

fn (mut this Queue) descriptor_closed(pid int) {
	mut delivery := unsafe { &Delivery(C.vinix_stack_alloc(sizeof(Delivery))) }
	unsafe { C.memset(delivery, 0, sizeof(Delivery)) }
	mq_lock.acquire()
	if pid != 0 && this.notify_owner == pid {
		this.remove_notification_locked(mut delivery)
	}
	mq_lock.release()
	deliver(delivery)
}

fn put_text(text &u8, at int, value &u8, length int) int {
	unsafe { C.memcpy(text + at, value, length) }
	return at + length
}

// printf's %-<width>lu.
fn put_number(text &u8, at int, value u64, width int) int {
	mut digits := [20]u8{}
	mut count := 0
	mut rest := value
	for {
		digits[count] = u8(`0` + rest % 10)
		count++
		rest /= 10
		if rest == 0 {
			break
		}
	}
	mut position := at
	for i := count - 1; i >= 0; i-- {
		unsafe {
			text[position] = digits[i]
		}
		position++
	}
	for position - at < width {
		unsafe {
			text[position] = ` `
		}
		position++
	}
	return position
}

// "QSIZE:%-10lu NOTIFY:%-5d SIGNO:%-5d NOTIFY_PID:%-6d\n". NOTIFY is the
// sigevent kind (SIGEV_SIGNAL shows as 0), SIGNO the signal of a
// SIGEV_SIGNAL registration and NOTIFY_PID the owner as the reader sees it.
fn (mut this Queue) status_text(text &u8) int {
	mq_lock.acquire()
	qsize := this.qsize
	owner := this.notify_owner
	start := this.notify_start
	kind := if owner != 0 { this.notify_kind } else { 0 }
	signal := if owner != 0 && kind == sigev_signal { this.notify_signal } else { 0 }
	mq_lock.release()
	mut owner_pid := 0
	if owner != 0 {
		target := proc.pin_process_at(owner)
		if target != unsafe { nil } {
			if target.start_time_ticks == start {
				owner_pid = proc.pid_in(target, proc.current_thread().process.numbered_in)
			}
			proc.unpin_process(target)
		}
	}
	mut at := put_text(text, 0, c'QSIZE:', 6)
	at = put_number(text, at, qsize, 10)
	at = put_text(text, at, c' NOTIFY:', 8)
	at = put_number(text, at, u64(kind), 5)
	at = put_text(text, at, c' SIGNO:', 7)
	at = put_number(text, at, u64(signal), 5)
	at = put_text(text, at, c' NOTIFY_PID:', 12)
	at = put_number(text, at, u64(owner_pid), 6)
	return put_text(text, at, c'\n', 1)
}

fn (mut this Queue) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if stat.isdir(this.stat.mode) { errno.set(errno.eisdir); return none }
	text := unsafe { &u8(C.vinix_stack_alloc(128)) }
	length := u64(this.status_text(text))
	if loc >= length {
		return 0
	}
	n := if count < length - loc { count } else { length - loc }
	unsafe { C.memcpy(buf, text + loc, n) }
	return i64(n)
}

// Linux's queue file has no write operation.
fn (mut this Queue) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this Queue) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this Queue) unref(_handle voidptr) ? {
	this.release()
}

fn (mut this Queue) link(_handle voidptr) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this Queue) unlink(_handle voidptr) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this Queue) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.einval)
	return none
}

fn (mut this Queue) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

// ── syscalls ─────────────────────────────────────────────────────────────────

fn queue_of(fd &file.FD) &Queue {
	if fd.handle.flags & resource.o_path != 0 { return unsafe { nil } }
	mut res := fd.handle.resource
	if mut res is Queue && stat.isreg(res.stat.mode) {
		return unsafe { res }
	}
	return unsafe { nil }
}

fn readable(handle &file.Handle) bool {
	mode := handle.flags & 3
	return mode == resource.o_rdonly || mode == resource.o_rdwr
}

fn writable(handle &file.Handle) bool {
	mode := handle.flags & 3
	return mode == resource.o_wronly || mode == resource.o_rdwr
}

// Create a queue in `spare` under mq_lock: mqueue_create_attr() and
// mqueue_get_inode(). 0 or the errno.
fn create_locked(mut spare Queue, process &proc.Process, ns u64, name string, mode u32, attr &Attr) u64 {
	privileged := capable(process, proc.cap_sys_resource)
	if namespace_queues_locked(ns) >= queues_max && !privileged {
		return errno.enospc
	}
	maxmsg := if attr != unsafe { nil } { attr.maxmsg } else { default_maxmsg }
	msgsize := if attr != unsafe { nil } { attr.msgsize } else { default_msgsize }
	if maxmsg <= 0 || msgsize <= 0 {
		return errno.einval
	}
	if privileged {
		if maxmsg > hard_maxmsg || msgsize > hard_msgsize {
			return errno.einval
		}
	} else if maxmsg > default_maxmsg || msgsize > default_msgsize {
		return errno.einval
	}
	bytes := queue_bytes(maxmsg, msgsize)
	limit := proc.soft_limit(process, proc.rlimit_msgqueue)
	used := user_bytes_locked(process.uid)
	if bytes > limit || used > limit - bytes {
		return errno.emfile
	}
	if mq_device == 0 {
		mq_device = resource.create_dev_id()
	}
	mq_inodes++
	stamp := now()
	spare.stat.dev = mq_device
	spare.stat.ino = mq_inodes
	spare.stat.nlink = 1
	spare.stat.mode = stat.ifreg | (mode & 0o7777)
	spare.stat.uid = process.fsuid
	spare.stat.gid = process.fsgid
	spare.stat.size = queue_file_size
	spare.stat.blksize = 4096
	spare.stat.atim = stamp
	spare.stat.mtim = stamp
	spare.stat.ctim = stamp
	unsafe { C.memcpy(&spare.name[0], name.str, name.len) }
	spare.name_len = name.len
	spare.ipc_ns = ns
	spare.linked = true
	spare.user = process.uid
	spare.charged = bytes
	spare.maxmsg = maxmsg
	spare.msgsize = msgsize
	spare.status = pollout | pollwrnorm
	// The registry's reference.
	spare.refcount = 1
	link_all_locked(mut spare)
	if ns in mq_roots {
		publish_queue_locked(mut spare, unsafe { mq_roots[ns] })
	}
	return 0
}

pub fn syscall_mq_open(_ voidptr, name_ptr u64, oflag_word u64, mode_word u64, attr_ptr u64) (u64, u64) {
	oflag := int(i32(u32(oflag_word)))
	mode := u32(mode_word) & 0xffff
	mut attr := &Attr(unsafe { nil })
	if attr_ptr != 0 {
		attr = unsafe { &Attr(C.vinix_stack_alloc(sizeof(Attr))) }
		if !usercopy.copy_from_user(attr, attr_ptr, sizeof(Attr)) {
			return errno.err, errno.efault
		}
	}
	name := user_name(name_ptr) or { return errno.err, errno.get() }
	defer {
		unsafe { name.free() }
	}
	ns, ns_id, entered := enter_namespace()
	if !entered {
		return errno.err, errno.eacces
	}
	defer {
		leave_namespace(ns)
	}
	// The number first, as Linux takes it: a queue is never named for a
	// descriptor that cannot be had, and EMFILE comes before lookup errors.
	reservation := unsafe { &file.FdReservation(C.vinix_stack_alloc(sizeof(file.FdReservation))) }
	unsafe {
		*reservation = file.FdReservation{}
	}
	file.reserve_fd(unsafe { nil }, reservation) or { return errno.err, errno.get() }
	defer {
		file.cancel_fd_reservation(reservation)
	}
	process := proc.current_thread().process
	mut spare := &Queue(unsafe { nil })
	if oflag & resource.o_creat != 0 {
		spare = allocate_queue() or { return errno.err, errno.get() }
	}
	mut result := u64(0)
	mut created := false
	mq_lock.acquire()
	root := if ns_id in mq_roots { unsafe { mq_roots[ns_id] } } else { unsafe { &Queue(nil) } }
	mut queue := find_locked(ns_id, name)
	if root != unsafe { nil } && !permitted(process, root, 1) {
		result = errno.eacces
	} else if queue != unsafe { nil } {
		requested := match oflag & 3 {
			resource.o_rdonly { u32(4) }
			resource.o_wronly { u32(2) }
			else { u32(6) }
		}
		if oflag & (resource.o_creat | resource.o_excl) == resource.o_creat | resource.o_excl {
			result = errno.eexist
		} else if oflag & 3 == 3 {
			result = errno.einval
		} else if !permitted(process, queue, requested) {
			result = errno.eacces
		}
	} else if oflag & resource.o_creat == 0 {
		result = errno.enoent
	} else if root != unsafe { nil } && !permitted(process, root, 3) {
		result = errno.eacces
	} else {
		result = create_locked(mut spare, process, ns_id, name, mode & ~process.umask, attr)
		if result == 0 {
			queue = spare
			spare = unsafe { nil }
			created = true
		}
	}
	if result == 0 {
		// The descriptor's reference, and this call's while it may unname a
		// queue it made if the descriptor's kernel budget runs out.
		katomic.inc(mut &queue.refcount)
		katomic.inc(mut &queue.refcount)
	}
	mq_lock.release()
	if spare != unsafe { nil } {
		free_queue(mut spare)
	}
	if result != 0 {
		return errno.err, result
	}
	// The access mode as the file has it, accmode 3 giving neither direction
	// as on Linux, and the status flags F_GETFL reports. Always close-on-exec.
	flags := (oflag & 3) | (oflag & resource.file_status_flags_mask & ~(resource.o_accmode | 3))
		| resource.o_cloexec
	opened := resource.OpenedResource{
		resource: queue.box
		owned:    true
	}
	mut fdnum := -1
	if fd := file.fd_create_from_opened(opened, flags) {
		fdnum = file.fdnum_install_reserved_fd(reservation, fd) or {
			failure := errno.get()
			mut unused := unsafe { fd }
			unused.unref()
			errno.set(failure)
			-1
		}
	}
	if fdnum < 0 {
		failure := errno.get()
		finish_open(mut queue, created)
		return errno.err, failure
	}
	finish_open(mut queue, false)
	return u64(fdnum), 0
}

// Gives back mq_open's own reference. The number is reserved before the queue
// is made, but the open file's kernel budget can still run out; a queue made
// for a descriptor that could not be had is then removed again.
fn finish_open(mut queue Queue, unname bool) {
	if unname {
		mq_lock.acquire()
		// This call still holds its reference, so the name's is never the last.
		if queue.linked {
			unname_locked(mut queue)
		}
		mq_lock.release()
	}
	queue.release()
}

pub fn syscall_mq_unlink(_ voidptr, name_ptr u64) (u64, u64) {
	name := user_name(name_ptr) or { return errno.err, errno.get() }
	defer {
		unsafe { name.free() }
	}
	ns, ns_id, entered := enter_namespace()
	if !entered {
		return errno.err, errno.eacces
	}
	defer {
		leave_namespace(ns)
	}
	process := proc.current_thread().process
	mut result := u64(0)
	mut last := false
	mq_lock.acquire()
	root := if ns_id in mq_roots { unsafe { mq_roots[ns_id] } } else { unsafe { &Queue(nil) } }
	dir_uid := if root != unsafe { nil } { root.stat.uid } else if ns != unsafe { nil } { ns.ipc_fsuid } else { u32(0) }
	sticky := root == unsafe { nil } || root.stat.mode & 0o1000 != 0
	mut queue := find_locked(ns_id, name)
	if root != unsafe { nil } && !permitted(process, root, 1) {
		result = errno.eacces
	} else if queue == unsafe { nil } {
		result = errno.enoent
	} else if root != unsafe { nil } && !permitted(process, root, 3) {
		result = errno.eacces
	} else if sticky && !may_remove(process, queue, dir_uid) {
		result = errno.eperm
	} else if vfs.mqueue_child_mounted_on(queue.node) {
		result = errno.ebusy
	} else {
		last = unname_locked(mut queue)
	}
	mq_lock.release()
	if last {
		free_queue(mut queue)
	}
	if result != 0 {
		return errno.err, result
	}
	return 0, 0
}

// netlink_getsockbyfilp(): only a netlink socket takes a SIGEV_THREAD cookie.
fn is_netlink(mut res resource.Resource) bool {
	if mut res is netlink.NetlinkSocket {
		return true
	}
	return false
}

// The descriptor and its queue, or nil with the descriptor given back.
fn queue_fd(mqdes u64) (&file.FD, &Queue) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, int(i32(u32(mqdes)))) or {
		return unsafe { nil }, unsafe { nil }
	}
	queue := queue_of(fd)
	if queue == unsafe { nil } {
		fd.unref()
		return unsafe { nil }, unsafe { nil }
	}
	return fd, queue
}

pub fn syscall_mq_timedsend(_ voidptr, mqdes u64, msg_ptr u64, msg_len u64, prio_word u64, timeout_ptr u64) (u64, u64) {
	mut deadline := &time.TimeSpec(unsafe { nil })
	if timeout_ptr != 0 {
		deadline = unsafe { &time.TimeSpec(C.vinix_stack_alloc(sizeof(time.TimeSpec))) }
		code := read_deadline(timeout_ptr, deadline)
		if code != 0 {
			return errno.err, code
		}
	}
	priority := u32(prio_word)
	if priority >= prio_max {
		return errno.err, errno.einval
	}
	mut fd, mut queue := queue_fd(mqdes)
	if fd == unsafe { nil } {
		return errno.err, errno.ebadf
	}
	defer {
		fd.unref()
	}
	if !writable(fd.handle) {
		return errno.err, errno.ebadf
	}
	if msg_len > u64(queue.msgsize) {
		return errno.err, errno.emsgsize
	}
	mut message := new_message(msg_ptr, msg_len, priority) or { return errno.err, errno.get() }
	mut delivery := unsafe { &Delivery(C.vinix_stack_alloc(sizeof(Delivery))) }
	unsafe { C.memset(delivery, 0, sizeof(Delivery)) }
	mut result := u64(0)
	mq_lock.acquire()
	if queue.curmsgs >= queue.maxmsg {
		if fd.handle.flags & resource.o_nonblock != 0 {
			result = errno.eagain
		} else {
			mut waiter := unsafe { &Waiter(C.vinix_stack_alloc(sizeof(Waiter))) }
			unsafe {
				*waiter = Waiter{
					message: message
				}
			}
			result = queue.wait_locked(waiter, true, deadline)
			if result == 0 {
				// A receiver moved it into the queue.
				message = unsafe { nil }
			}
		}
	} else {
		mut receiver := queue.receivers
		if receiver != unsafe { nil } {
			// pipelined_send(): straight to the first waiting receiver.
			queue.receivers = receiver.next
			receiver.next = unsafe { nil }
			receiver.message = message
			receiver.ready = true
			event.trigger(mut receiver.wake, false)
		} else {
			queue.insert_locked(message)
			if queue.curmsgs == 1 {
				queue.fire_notification_locked(mut delivery)
			}
			queue.changed_locked()
		}
		message = unsafe { nil }
		queue.touch_locked()
	}
	mq_lock.release()
	if message != unsafe { nil } {
		free_message(message)
	}
	deliver(delivery)
	if result != 0 {
		return errno.err, result
	}
	return 0, 0
}

pub fn syscall_mq_timedreceive(_ voidptr, mqdes u64, msg_ptr u64, msg_len u64, prio_ptr u64, timeout_ptr u64) (u64, u64) {
	mut deadline := &time.TimeSpec(unsafe { nil })
	if timeout_ptr != 0 {
		deadline = unsafe { &time.TimeSpec(C.vinix_stack_alloc(sizeof(time.TimeSpec))) }
		code := read_deadline(timeout_ptr, deadline)
		if code != 0 {
			return errno.err, code
		}
	}
	mut fd, mut queue := queue_fd(mqdes)
	if fd == unsafe { nil } {
		return errno.err, errno.ebadf
	}
	defer {
		fd.unref()
	}
	if !readable(fd.handle) {
		return errno.err, errno.ebadf
	}
	if msg_len < u64(queue.msgsize) {
		return errno.err, errno.emsgsize
	}
	mut message := &Message(unsafe { nil })
	mut result := u64(0)
	mq_lock.acquire()
	if queue.curmsgs == 0 {
		if fd.handle.flags & resource.o_nonblock != 0 {
			result = errno.eagain
		} else {
			mut waiter := unsafe { &Waiter(C.vinix_stack_alloc(sizeof(Waiter))) }
			unsafe {
				*waiter = Waiter{}
			}
			result = queue.wait_locked(waiter, false, deadline)
			if result == 0 {
				message = waiter.message
			}
		}
	} else {
		message = queue.take_locked()
		// pipelined_receive(): the room goes to the first waiting sender.
		mut sender := queue.senders
		if sender != unsafe { nil } {
			queue.senders = sender.next
			sender.next = unsafe { nil }
			queue.insert_locked(sender.message)
			sender.message = unsafe { nil }
			sender.ready = true
			event.trigger(mut sender.wake, false)
		}
		queue.changed_locked()
		queue.touch_locked()
	}
	mq_lock.release()
	if result != 0 {
		return errno.err, result
	}
	// The message is this call's now. As on Linux a fault loses it.
	length := message.length
	mut failed := prio_ptr != 0
		&& !usercopy.copy_to_user(prio_ptr, unsafe { voidptr(&message.priority) }, 4)
	if !failed && length != 0 {
		failed = !usercopy.copy_to_user(msg_ptr, voidptr(u64(message) + sizeof(Message)), length)
	}
	free_message(message)
	if failed {
		return errno.err, errno.efault
	}
	return length, 0
}

pub fn syscall_mq_notify(_ voidptr, mqdes u64, sev_ptr u64) (u64, u64) {
	registering := sev_ptr != 0
	mut sev := unsafe { &SigEvent(C.vinix_stack_alloc(sizeof(SigEvent))) }
	unsafe { C.memset(sev, 0, sizeof(SigEvent)) }
	cookie := unsafe { &u8(C.vinix_stack_alloc(notify_cookie_len)) }
	mut socket := &resource.Resource(unsafe { nil })
	if registering {
		if !usercopy.copy_from_user(sev, sev_ptr, sizeof(SigEvent)) {
			return errno.err, errno.efault
		}
		if sev.notify != sigev_none && sev.notify != sigev_signal && sev.notify != sigev_thread {
			return errno.err, errno.einval
		}
		if sev.notify == sigev_signal && u32(sev.signo) > 64 {
			return errno.err, errno.einval
		}
		if sev.notify == sigev_thread {
			if !usercopy.copy_from_user(cookie, sev.value, notify_cookie_len) {
				return errno.err, errno.efault
			}
			mut socket_fd := file.fd_from_fdnum(unsafe { nil }, int(sev.signo)) or {
				return errno.err, errno.ebadf
			}
			mut res := socket_fd.handle.resource
			if !stat.issock(res.stat.mode) {
				socket_fd.unref()
				return errno.err, errno.enotsock
			}
			if !is_netlink(mut res) {
				socket_fd.unref()
				return errno.err, errno.einval
			}
			katomic.inc(mut &res.refcount)
			socket = res
			socket_fd.unref()
		}
	}
	mut fd, mut queue := queue_fd(mqdes)
	if fd == unsafe { nil } {
		if socket != unsafe { nil } {
			socket.unref(unsafe { nil }) or {}
		}
		return errno.err, errno.ebadf
	}
	process := proc.current_thread().process
	mut delivery := unsafe { &Delivery(C.vinix_stack_alloc(sizeof(Delivery))) }
	unsafe { C.memset(delivery, 0, sizeof(Delivery)) }
	mut result := u64(0)
	mq_lock.acquire()
	if !registering {
		if queue.notify_owner == process.pid {
			queue.remove_notification_locked(mut delivery)
		}
	} else if queue.notify_owner != 0 {
		result = errno.ebusy
	} else {
		queue.notify_owner = process.pid
		queue.notify_start = process.start_time_ticks
		queue.notify_kind = sev.notify
		if sev.notify == sigev_signal {
			queue.notify_exec_count = katomic.load(&process.exec_count)
			queue.notify_signal = sev.signo
			queue.notify_value = sev.value
		}
		if sev.notify == sigev_thread {
			queue.notify_socket = socket
			socket = unsafe { nil }
			unsafe { C.memcpy(&queue.notify_cookie[0], cookie, notify_cookie_len) }
		}
		queue.stat.atim = now()
		queue.stat.ctim = queue.stat.atim
	}
	mq_lock.release()
	fd.unref()
	if socket != unsafe { nil } {
		socket.unref(unsafe { nil }) or {}
	}
	deliver(delivery)
	if result != 0 {
		return errno.err, result
	}
	return 0, 0
}

pub fn syscall_mq_getsetattr(_ voidptr, mqdes u64, new_ptr u64, old_ptr u64) (u64, u64) {
	mut incoming := unsafe { &Attr(C.vinix_stack_alloc(sizeof(Attr))) }
	if new_ptr != 0 {
		if !usercopy.copy_from_user(incoming, new_ptr, sizeof(Attr)) {
			return errno.err, errno.efault
		}
		if incoming.flags & ~i64(resource.o_nonblock) != 0 {
			return errno.err, errno.einval
		}
	}
	mut fd, mut queue := queue_fd(mqdes)
	if fd == unsafe { nil } {
		return errno.err, errno.ebadf
	}
	mut previous := unsafe { &Attr(C.vinix_stack_alloc(sizeof(Attr))) }
	unsafe { C.memset(previous, 0, sizeof(Attr)) }
	mut handle := fd.handle
	mq_lock.acquire()
	previous.flags = i64(handle.flags & resource.o_nonblock)
	previous.maxmsg = queue.maxmsg
	previous.msgsize = queue.msgsize
	previous.curmsgs = queue.curmsgs
	if new_ptr != 0 {
		if incoming.flags & i64(resource.o_nonblock) != 0 {
			handle.flags |= resource.o_nonblock
		} else {
			handle.flags &= ~resource.o_nonblock
		}
		queue.stat.atim = now()
		queue.stat.ctim = queue.stat.atim
	}
	mq_lock.release()
	fd.unref()
	if old_ptr != 0 && !usercopy.copy_to_user(old_ptr, previous, sizeof(Attr)) {
		return errno.err, errno.efault
	}
	return 0, 0
}
