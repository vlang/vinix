@[has_globals]
module file

import errno
import event
import event.eventstruct
import katomic
import klock
import memory
import resource
import stat

// A fixed table keeps subscribing during low memory allocation-free. A slot
// belongs to one open description, so dup/fork share consumption and separate
// opens remain independent. Descriptor/epoll references protect it until unref.
const pressure_subscriptions = 64

struct MemoryPressureFile {
mut:
	stat stat.Stat
	refcount int
	l klock.Lock
	event eventstruct.Event
	status int
	can_mmap bool
	source bool
	slot int = -1
	acknowledged u64
	buffer [512]u8
	length int
	box &resource.Resource = unsafe { nil }
}

__global (
	pressure_files_lock klock.Lock
	pressure_files [pressure_subscriptions]MemoryPressureFile
	pressure_file_boxes [pressure_subscriptions]resource.Resource
	pressure_file_used [pressure_subscriptions]bool
)

// The procfs node is mount-lifetime storage. Only its opens take a bounded
// subscription slot; an O_PATH handle keeps the ordinary node resource.
pub fn new_memory_pressure_source(metadata stat.Stat) &resource.Resource {
	mut source := &MemoryPressureFile{source: true, stat: metadata, refcount: 1}
	source.box = &resource.Resource(unsafe { source })
	memory.register_pressure_observer(notify_memory_pressure)
	return source.box
}

fn (mut this MemoryPressureFile) open(flags int) ?&resource.Resource {
	if flags & resource.o_path != 0 { return this.box }
	if flags & resource.o_accmode != resource.o_rdonly {
		errno.set(errno.eacces)
		return none
	}
	pressure_files_lock.acquire()
	defer { pressure_files_lock.release() }
	for i in 0 .. pressure_subscriptions {
		if pressure_file_used[i] { continue }
		pressure_files[i] = MemoryPressureFile{
			stat: this.stat
			slot: i
			status: pollin
		}
		// Converting a pointer borrows its storage. Both the object and its
		// interface box are static and need no per-open heap allocation.
		pressure_file_boxes[i] = resource.Resource(unsafe { &pressure_files[i] })
		pressure_files[i].box = &pressure_file_boxes[i]
		pressure_file_used[i] = true
		return &pressure_file_boxes[i]
	}
	errno.set(errno.enospc)
	return none
}

fn notify_memory_pressure(generation u64) {
	pressure_files_lock.acquire()
	defer { pressure_files_lock.release() }
	for i in 0 .. pressure_subscriptions {
		if !pressure_file_used[i] { continue }
		mut subscription := &pressure_files[i]
		subscription.l.acquire()
		if generation > subscription.acknowledged {
			subscription.status = pollin
			event.trigger(mut subscription.event, true)
		}
		subscription.l.release()
	}
}

fn (mut this MemoryPressureFile) append_text(value string) {
	for byte in value {
		if this.length == this.buffer.len { return }
		this.buffer[this.length] = byte
		this.length++
	}
}

fn (mut this MemoryPressureFile) append_number(value u64) {
	mut digits := [20]u8{}
	mut pos := digits.len
	mut remaining := value
	for {
		pos--
		digits[pos] = u8(remaining % 10) + `0`
		remaining /= 10
		if remaining == 0 { break }
	}
	for pos < digits.len && this.length < this.buffer.len {
		this.buffer[this.length] = digits[pos]
		this.length++
		pos++
	}
}

fn (mut this MemoryPressureFile) refresh() {
	snapshot := memory.pressure_snapshot()
	this.length = 0
	this.append_text('level ')
	this.append_text(match snapshot.level { 2 { 'critical' } 1 { 'warning' } else { 'normal' } })
	this.append_text('\ngeneration ')
	this.append_number(snapshot.generation)
	this.append_text('\nfree_bytes ')
	this.append_number(snapshot.free_bytes)
	this.append_text('\ntotal_bytes ')
	this.append_number(snapshot.total_bytes)
	this.append_text('\ncritical_bytes ')
	this.append_number(snapshot.watermarks.critical)
	this.append_text('\nlow_bytes ')
	this.append_number(snapshot.watermarks.low)
	this.append_text('\nhigh_bytes ')
	this.append_number(snapshot.watermarks.high)
	this.append_text('\nreclaim_runs ')
	this.append_number(snapshot.reclaim_runs)
	this.append_text('\nreclaimed_pages ')
	this.append_number(snapshot.reclaimed_pages)
	this.append_text('\nallocation_failures ')
	this.append_number(snapshot.allocation_failures)
	this.append_text('\n')
	this.acknowledged = snapshot.generation
	this.status = 0
}

fn (mut this MemoryPressureFile) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if count == 0 { return 0 }
	this.l.acquire()
	defer { this.l.release() }
	if loc == 0 { this.refresh() }
	if loc >= u64(this.length) { return 0 }
	mut amount := u64(this.length) - loc
	if amount > count { amount = count }
	unsafe { C.memcpy(buf, &this.buffer[0] + loc, amount) }
	return i64(amount)
}

fn (mut this MemoryPressureFile) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) || this.source { return }
	pressure_files_lock.acquire()
	// The last Handle reference drops after in-flight reads and poll waiters
	// detach. Stop publication before allowing this static slot to be reused.
	pressure_file_used[this.slot] = false
	// eventstruct frees its overflow when listeners detach; no dynamic state
	// is owned by an idle pressure subscription.
	pressure_files_lock.release()
}

fn (mut this MemoryPressureFile) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.eperm)
	return none
}
fn (mut this MemoryPressureFile) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}
fn (mut this MemoryPressureFile) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}
fn (mut this MemoryPressureFile) grow(_handle voidptr, _size u64) ? {
	errno.set(errno.eperm)
	return none
}
fn (mut this MemoryPressureFile) link(_handle voidptr) ? {
	errno.set(errno.eperm)
	return none
}
fn (mut this MemoryPressureFile) unlink(_handle voidptr) ? {
	errno.set(errno.eperm)
	return none
}
