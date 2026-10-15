// SPDX-License-Identifier: GPL-2.0-or-later
// Independent observations plus task/IRQ/spin/park leaf transports only.
@[translated]
module rwsemfixture

#include "contract.h"
@[typedef]
struct C.pthread_t {}

@[typedef]
struct C.pthread_key_t {}

@[typedef]
struct C.pthread_mutex_t {}

@[typedef]
struct C.pthread_cond_t {}

@[typedef]
struct C.rsh_const_charp {}

struct C.rw_semaphore {}

struct C.list_head {
	next &C.list_head
	prev &C.list_head
}

fn C.pthread_key_create(&C.pthread_key_t, voidptr) i32
fn C.pthread_key_delete(C.pthread_key_t) i32
fn C.pthread_getspecific(C.pthread_key_t) voidptr
fn C.pthread_setspecific(C.pthread_key_t, voidptr) i32
fn C.pthread_mutex_init(&C.pthread_mutex_t, voidptr) i32
fn C.pthread_mutex_destroy(&C.pthread_mutex_t) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.pthread_cond_init(&C.pthread_cond_t, voidptr) i32
fn C.pthread_cond_destroy(&C.pthread_cond_t) i32
fn C.pthread_cond_wait(&C.pthread_cond_t, &C.pthread_mutex_t) i32
fn C.pthread_cond_broadcast(&C.pthread_cond_t) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.sched_yield() i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.atoi(&char) i32

@[noreturn]
fn C.exit(i32)

@[noreturn]
fn C.abort()

fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.memset(voidptr, i32, usize) voidptr
fn C.rsh_load32(&u32) u32
fn C.rsh_store32(&u32, u32)
fn C.rsh_add32(&u32, u32) u32
fn C.rsh_exchange32(&u32, u32) u32
fn C.rsh_load64(&u64) u64
fn C.rsh_store64(&u64, u64)
fn C.rsh_line(string) &char
fn C.rsh_count(&C.rw_semaphore) u64
fn C.rsh_owner(&C.rw_semaphore) usize
fn C.rsh_lock(&C.rw_semaphore) voidptr
fn C.rsh_list(&C.rw_semaphore) &C.list_head
fn C.rsh_set_count(&C.rw_semaphore, u64)
fn C.rsh_set_owner(&C.rw_semaphore, usize)
fn C.rsh_static_ptr() &C.rw_semaphore
fn C.init_rwsem(&C.rw_semaphore)
fn C.down_read(&C.rw_semaphore)
fn C.down_read_interruptible(&C.rw_semaphore) i32
fn C.down_read_killable(&C.rw_semaphore) i32
fn C.down_read_trylock(&C.rw_semaphore) i32
fn C.down_write(&C.rw_semaphore)
fn C.down_write_killable(&C.rw_semaphore) i32
fn C.down_write_trylock(&C.rw_semaphore) i32
fn C.up_read(&C.rw_semaphore)
fn C.up_write(&C.rw_semaphore)
fn C.downgrade_write(&C.rw_semaphore)
fn C.rwsem_is_locked(&C.rw_semaphore) bool
fn C.rwsem_is_contended(&C.rw_semaphore) bool
fn C.down_read_nested(&C.rw_semaphore, i32)
fn C.down_read_killable_nested(&C.rw_semaphore, i32) i32
fn C.down_write_nested(&C.rw_semaphore, i32)
fn C.down_write_killable_nested(&C.rw_semaphore, i32) i32
fn C.down_read_non_owner(&C.rw_semaphore)
fn C.up_read_non_owner(&C.rw_semaphore)
fn C.vrs_down_read(voidptr, u32) i32
fn C.vrs_down_write(voidptr, u32) i32

struct Context {
mut:
	flags            u64 = 0x202
	pins             u32
	irq_depth        u32
	active           bool = true
	state            u32
	pending          u64
	masked           u64
	fatal            u32
	wake_sequence    u32
	park_sequence    u32
	schedules        u32
	wakes            u32
	current_queries  u32
	held             voidptr = unsafe { nil }
	post_unlock_done &u32    = unsafe { nil }
	signal_on_wake   bool
	park_hold        u32
	mutex            C.pthread_mutex_t
	changed          C.pthread_cond_t
}

enum Operation {
	read
	write
	interruptible
	kill_read
	kill_write
}

struct Actor {
mut:
	thread     C.pthread_t
	context    Context
	sem        &C.rw_semaphore = unsafe { nil }
	operation  Operation
	entered    u32
	acquired   u32
	release    u32
	done       u32
	result     i32
	free_sem   bool
	iterations u32     = 1
	ledger     &Ledger = unsafe { nil }
}

struct Ledger {
mut:
	readers u32
	writers u32
	visits  u32
	payload u64
}

@[cinit]
__global (
	key           C.pthread_key_t
	assertions    u32
	scenarios     u32
	allocations   u32
	lifetime_done u32
	negative_postunlock_read u32
	fatal_sem     &C.rw_semaphore = unsafe { nil }
	fatal_count   u64
	fatal_owner   usize
	fatal_next    usize
	fatal_prev    usize
	fatal_watch   bool
)

fn check(ok bool, line string) {
	unsafe {
		C.rsh_add32(&assertions, 1)
		if !ok {
			C.printf(c'RWSEM assertion %s\n', C.rsh_line(line))
			C.fflush(nil)
			C.abort()
		}
	}
}

fn context() &Context { return unsafe { &Context(C.pthread_getspecific(key)) } }

fn install(c &Context) { check(C.pthread_setspecific(unsafe { key }, c) == 0, @LINE) }

fn initialize_context(c &Context) {
	unsafe {
		*c = Context{}
		check(C.pthread_mutex_init(&c.mutex, nil) == 0 && C.pthread_cond_init(&c.changed, nil) == 0, @LINE)
	}
}

fn destroy_context(c &Context) {
	unsafe {
		check(c.pins == 0 && c.held == nil && C.rsh_load32(&c.state) == 0, @LINE)
		check(C.pthread_mutex_destroy(&c.mutex) == 0 && C.pthread_cond_destroy(&c.changed) == 0, @LINE)
	}
}

fn await_word(word &u32, wanted u32) {
	for turn := 0; turn < 30000000; turn++ {
		if C.rsh_load32(word) >= wanted { return }
		C.sched_yield()
	}
	check(false, @LINE)
}

fn signal_state(state u32, c &Context) bool {
	unsafe {
		pending := C.rsh_load64(&c.pending)
		return state & 257 != 0 && (C.rsh_load32(&c.fatal) != 0 || pending & (u64(1) << 8) != 0 || (state & 1 != 0 && pending & ~C.rsh_load64(&c.masked) != 0))
	}
}

@[export:'vinix_linuxkpi_may_sleep']
pub fn may_sleep() bool {
	c := context()
	return c.active && c.flags & 512 != 0 && c.pins == 0 && c.irq_depth == 0
}

@[export:'vkp_current']
pub fn current() voidptr {
	unsafe {
		c := context()
		c.current_queries++
		return if c.active { voidptr(c) } else { nil }
	}
}

@[export:'vkp_spin_init']
pub fn spin_init(p voidptr) {
	unsafe { C.rsh_store32(&u32(p), 0) }
}

@[export:'vkp_spin_lock_irqsave']
pub fn spin_lock(p voidptr) usize {
	unsafe {
		c := context()
		check(c.held == nil, @LINE)
		saved := c.flags
		c.flags &= ~u64(512)
		c.pins++
		for C.rsh_exchange32(&u32(p), 1) != 0 { C.sched_yield() }
		c.held = p
		return usize(saved)
	}
}

@[export:'vkp_spin_unlock_irqrestore']
pub fn spin_unlock(p voidptr, saved usize) {
	unsafe {
		c := context()
		check(c.held == p && c.pins != 0, @LINE)
		c.held = nil
		C.rsh_store32(&u32(p), 0)
		c.pins--
		c.flags = u64(saved)
		done := c.post_unlock_done
		c.post_unlock_done = nil
		if done != nil {
			await_word(done, 1)
			// Explicit transport-only negative control; production is unchanged.
			if C.rsh_load32(&negative_postunlock_read) != 0 {
				check(C.rsh_load32(&u32(p)) == 0, @LINE)
			}
		}
	}
}

@[export:'vkw_current_state']
pub fn current_state(state u32) {
	unsafe {
		c := context()
		check(c.held != nil && (state == 0 || state == 1 || state == 2 || state == 258), @LINE)
		check(C.pthread_mutex_lock(&c.mutex) == 0, @LINE)
		C.rsh_store32(&c.state, state)
		c.park_sequence = c.wake_sequence
		check(C.pthread_mutex_unlock(&c.mutex) == 0, @LINE)
	}
}

@[export:'vkw_signal_state']
pub fn pending_state(state u32, task voidptr) bool {
	unsafe {
		return signal_state(state, &Context(task))
	}
}

@[export:'vkw_wake_task']
pub fn wake(task voidptr) i32 {
	unsafe {
		target := &Context(task)
		check(context().held != nil && target.active, @LINE)
		check(C.pthread_mutex_lock(&target.mutex) == 0, @LINE)
		if target.signal_on_wake { C.rsh_store64(&target.pending, u64(1) << 8) }
		C.rsh_store32(&target.state, 0)
		target.wake_sequence++
		target.wakes++
		check(C.pthread_cond_broadcast(&target.changed) == 0 && C.pthread_mutex_unlock(&target.mutex) == 0, @LINE)
		return 1
	}
}

@[export:'vkp_schedule']
pub fn schedule() {
	unsafe {
		c := context()
		check(may_sleep() && c.held == nil, @LINE)
		check(C.pthread_mutex_lock(&c.mutex) == 0, @LINE)
		c.schedules++
		for C.rsh_load32(&c.state) != 0 && !signal_state(C.rsh_load32(&c.state), c) && c.wake_sequence == c.park_sequence {
			check(C.pthread_cond_wait(&c.changed, &c.mutex) == 0, @LINE)
		}
		check(C.pthread_mutex_unlock(&c.mutex) == 0, @LINE)
		for C.rsh_load32(&c.park_hold) != 0 { C.sched_yield() }
	}
}

@[export:'kmalloc']
pub fn allocate(_bytes usize, _flags u32) voidptr {
	unsafe { C.rsh_add32(&allocations, 1) }
	return unsafe { nil }
}

@[export:'kzalloc']
pub fn allocate_zero(_bytes usize, _flags u32) voidptr {
	return allocate(_bytes, _flags)
}

@[export:'vinix_linuxkpi_bug'; noreturn]
pub fn bug(reason C.rsh_const_charp, line i32) {
	unsafe {
		if fatal_watch {
			head := C.rsh_list(fatal_sem)
			check(C.rsh_count(fatal_sem) == fatal_count && C.rsh_owner(fatal_sem) == fatal_owner && usize(head.next) == fatal_next && usize(head.prev) == fatal_prev, @LINE)
			C.printf(c'RWSEM fatal preserved semaphore\n')
		}
		C.printf(c'RWSEM invariant %s:%d\n', reason, line)
		C.fflush(nil)
		C.exit(85)
	}
}

fn queued(sem &C.rw_semaphore) u32 {
	unsafe {
		saved := spin_lock(C.rsh_lock(sem))
		head := C.rsh_list(sem)
		mut node := head.next
		mut n := u32(0)
		for usize(node) != usize(head) {
			check(n < 1024, @LINE)
			n++
			node = node.next
		}
		check(C.rwsem_is_contended(sem) == (n != 0), @LINE)
		spin_unlock(C.rsh_lock(sem), saved)
		return n
	}
}

fn await_queue(sem &C.rw_semaphore, wanted u32) {
	for turn := 0; turn < 30000000; turn++ {
		if queued(sem) == wanted { return }
		C.sched_yield()
	}
	check(false, @LINE)
}

fn acquire(a &Actor) i32 {
	unsafe {
		match a.operation {
			.read {
				C.down_read(a.sem)
				return 0
			}
			.write {
				C.down_write(a.sem)
				return 0
			}
			.interruptible { return C.down_read_interruptible(a.sem) }
			.kill_read { return C.down_read_killable(a.sem) }
			.kill_write { return C.down_write_killable(a.sem) }
		}
	}
	return -1
}

fn release_actor(a &Actor) {
	unsafe { if a.operation in [.write, .kill_write] { C.up_write(a.sem) } else { C.up_read(a.sem) } }
}

fn actor(argument voidptr) voidptr {
	unsafe {
		a := &Actor(argument)
		install(&a.context)
		C.rsh_store32(&a.entered, 1)
		for _ in 0 .. a.iterations {
			a.result = acquire(a)
			check(C.rsh_load32(&a.context.state) == 0 && may_sleep(), @LINE)
			if a.result != 0 { break }
			if a.ledger != nil {
				if a.operation in [.write, .kill_write] {
					check(C.rsh_add32(&a.ledger.writers, 1) == 0 && C.rsh_load32(&a.ledger.readers) == 0, @LINE)
					old := a.ledger.payload
					C.sched_yield()
					a.ledger.payload = old + 1
					check(C.rsh_add32(&a.ledger.writers, u32(-1)) == 1, @LINE)
				} else {
					C.rsh_add32(&a.ledger.readers, 1)
					check(C.rsh_load32(&a.ledger.writers) == 0, @LINE)
					C.sched_yield()
					check(C.rsh_load32(&a.ledger.writers) == 0, @LINE)
					C.rsh_add32(&a.ledger.readers, u32(-1))
				}
				C.rsh_add32(&a.ledger.visits, 1)
			}
			C.rsh_store32(&a.acquired, 1)
			await_word(&a.release, 1)
			release_actor(a)
		}
		if a.free_sem {
			check(a.result == 0, @LINE)
			C.free(a.sem)
			a.sem = nil
		}
		C.rsh_store32(&a.done, 1)
		if a.free_sem { C.rsh_store32(&lifetime_done, 1) }
		return nil
	}
}

fn start(a &Actor, sem &C.rw_semaphore, operation Operation) {
	unsafe {
		a.sem = sem
		a.operation = operation
		initialize_context(&a.context)
		check(C.pthread_create(&a.thread, nil, actor, a) == 0, @LINE)
		await_word(&a.entered, 1)
	}
}

fn join(a &Actor) {
	unsafe {
		check(C.pthread_join(a.thread, nil) == 0 && C.rsh_load32(&a.done) == 1, @LINE)
		destroy_context(&a.context)
	}
}

fn signal(a &Actor, bits u64, mask u64, fatal bool) {
	unsafe {
		check(C.pthread_mutex_lock(&a.context.mutex) == 0, @LINE)
		C.rsh_store64(&a.context.masked, mask)
		C.rsh_store64(&a.context.pending, bits)
		C.rsh_store32(&a.context.fatal, if fatal { u32(1) } else { u32(0) })
		a.context.wake_sequence++
		check(C.pthread_cond_broadcast(&a.context.changed) == 0 && C.pthread_mutex_unlock(&a.context.mutex) == 0, @LINE)
	}
}

fn allow(a &Actor) {
	unsafe { C.rsh_store32(&a.release, 1) }
}

fn fresh(sem &C.rw_semaphore) {
	unsafe {
		C.memset(sem, 0xa5, sizeof(C.rw_semaphore))
		C.init_rwsem(sem)
		check(C.rsh_count(sem) == 0 && C.rsh_owner(sem) == 0 && C.rsh_load32(&u32(C.rsh_lock(sem))) == 0 && queued(sem) == 0 && !C.rwsem_is_locked(sem), @LINE)
	}
}

fn basic() {
	unsafe {
		static_sem := C.rsh_static_ptr()
		check(C.rsh_count(static_sem) == 0 && C.rsh_owner(static_sem) == 0 && queued(static_sem) == 0, @LINE)
		for _ in 0 .. 64 {
			check(C.down_read_trylock(static_sem) == 1 && C.rsh_count(static_sem) == 256 && C.rsh_owner(static_sem) == usize(context()) | 1, @LINE)
			check(C.down_write_trylock(static_sem) == 0, @LINE)
			C.up_read(static_sem)
			check(C.rsh_count(static_sem) == 0 && C.rsh_owner(static_sem) == usize(context()) | 1, @LINE)
			check(C.down_write_trylock(static_sem) == 1 && C.rsh_owner(static_sem) == usize(context()), @LINE)
			C.downgrade_write(static_sem)
			check(C.rsh_count(static_sem) == 256, @LINE)
			C.up_read(static_sem)
		}
		mut sem := C.rw_semaphore{}
		fresh(&sem)
		C.down_read_nested(&sem, 3)
		C.up_read(&sem)
		check(C.down_read_killable_nested(&sem, 2) == 0, @LINE)
		C.up_read(&sem)
		C.down_write_nested(&sem, 4)
		C.up_write(&sem)
		check(C.down_write_killable_nested(&sem, 1) == 0, @LINE)
		C.up_write(&sem)
		C.down_read_non_owner(&sem)
		c := context()
		before := c.current_queries
		c.active = false
		C.up_read_non_owner(&sem)
		c.active = true
		check(c.current_queries == before && !C.rwsem_is_locked(&sem), @LINE)
		// Signals do not reject an uncontended successful acquisition.
		C.rsh_store64(&c.pending, u64(1) << 8)
		check(C.down_read_interruptible(&sem) == 0, @LINE)
		C.up_read(&sem)
		check(C.down_read_killable(&sem) == 0, @LINE)
		C.up_read(&sem)
		check(C.down_write_killable(&sem) == 0, @LINE)
		C.up_write(&sem)
		C.rsh_store64(&c.pending, 0)
		// A retired modeled task's reader hint must never be dereferenced.
		temporary := &Context(C.malloc(sizeof(Context)))
		check(temporary != nil, @LINE)
		initialize_context(temporary)
		install(temporary)
		C.down_read(&sem)
		C.up_read(&sem)
		install(c)
		destroy_context(temporary)
		C.free(temporary)
		check(C.down_write_trylock(&sem) == 1, @LINE)
		C.up_write(&sem)
		scenarios++
	}
}

fn sharing_and_writer_gate() {
	unsafe {
		mut sem := C.rw_semaphore{}
		fresh(&sem)
		mut actors := [5]Actor{}
		start(&actors[0], &sem, .read)
		await_word(&actors[0].acquired, 1)
		start(&actors[1], &sem, .read)
		await_word(&actors[1].acquired, 1)
		check(C.rsh_count(&sem) == 512 && queued(&sem) == 0, @LINE)
		start(&actors[2], &sem, .write)
		await_queue(&sem, 1)
		start(&actors[3], &sem, .read)
		await_queue(&sem, 2)
		start(&actors[4], &sem, .write)
		await_queue(&sem, 3)
		check(C.rsh_count(&sem) == 514 && C.down_read_trylock(&sem) == 0 && C.down_write_trylock(&sem) == 0, @LINE)
		allow(&actors[0])
		join(&actors[0])
		check(C.rsh_load32(&actors[2].acquired) == 0, @LINE)
		allow(&actors[1])
		join(&actors[1])
		await_word(&actors[2].acquired, 1)
		check(C.rsh_count(&sem) == 3 && C.rsh_owner(&sem) == usize(&actors[2].context) && C.rsh_load32(&actors[3].acquired) == 0 && C.rsh_load32(&actors[4].acquired) == 0, @LINE)
		allow(&actors[2])
		join(&actors[2])
		await_word(&actors[3].acquired, 1)
		check(C.rsh_count(&sem) == 258 && C.rsh_load32(&actors[4].acquired) == 0, @LINE)
		allow(&actors[3])
		join(&actors[3])
		await_word(&actors[4].acquired, 1)
		check(C.rsh_count(&sem) == 1 && queued(&sem) == 0, @LINE)
		allow(&actors[4])
		join(&actors[4])
		check(!C.rwsem_is_locked(&sem), @LINE)
		scenarios++
	}
}

fn reader_phase(downgrade bool) {
	unsafe {
		mut sem := C.rw_semaphore{}
		fresh(&sem)
		C.down_write(&sem)
		mut actors := [5]Actor{}
		operations := [Operation.read, .write, .read, .write, .read]!
		for i in 0 .. 5 {
			start(&actors[i], &sem, operations[i])
			await_queue(&sem, u32(i + 1))
		}
		if downgrade { C.downgrade_write(&sem) } else { C.up_write(&sem) }
		for i in [0, 2, 4]! { await_word(&actors[i].acquired, 1) }
		check(C.rsh_count(&sem) == u64(if downgrade { 1026 } else { 770 }) && queued(&sem) == 2 && C.rsh_load32(&actors[1].acquired) == 0 && C.rsh_load32(&actors[3].acquired) == 0, @LINE)
		for i in [0, 2, 4]! {
			allow(&actors[i])
			join(&actors[i])
		}
		if downgrade {
			check(C.rsh_load32(&actors[1].acquired) == 0 && C.rsh_count(&sem) == 258, @LINE)
			C.up_read(&sem)
		}
		await_word(&actors[1].acquired, 1)
		check(C.rsh_load32(&actors[3].acquired) == 0, @LINE)
		allow(&actors[1])
		join(&actors[1])
		await_word(&actors[3].acquired, 1)
		allow(&actors[3])
		join(&actors[3])
		check(C.rsh_count(&sem) == 0 && queued(&sem) == 0, @LINE)
		scenarios++
	}
}

fn batch_limit() {
	unsafe {
		mut sem := C.rw_semaphore{}
		fresh(&sem)
		C.down_write(&sem)
		mut actors := [257]Actor{}
		for i in 0 .. 257 {
			start(&actors[i], &sem, .read)
			await_queue(&sem, u32(i + 1))
		}
		C.up_write(&sem)
		for i in 0 .. 256 { await_word(&actors[i].acquired, 1) }
		check(C.rsh_count(&sem) == 65538 && queued(&sem) == 1 && C.rsh_load32(&actors[256].acquired) == 0 && C.down_read_trylock(&sem) == 0, @LINE)
		for i in 0 .. 255 {
			allow(&actors[i])
			join(&actors[i])
		}
		check(C.rsh_count(&sem) == 258 && C.rsh_load32(&actors[256].acquired) == 0, @LINE)
		allow(&actors[255])
		join(&actors[255])
		await_word(&actors[256].acquired, 1)
		check(C.rsh_count(&sem) == 256 && queued(&sem) == 0, @LINE)
		allow(&actors[256])
		join(&actors[256])
		check(C.rsh_count(&sem) == 0, @LINE)
		scenarios++
	}
}

fn cancellation() {
	unsafe {
		// Cancelling a head writer admits a reader phase beside an older reader.
		mut sem := C.rw_semaphore{}
		fresh(&sem)
		C.down_read(&sem)
		mut a := [4]Actor{}
		start(&a[0], &sem, .kill_write)
		await_queue(&sem, 1)
		start(&a[1], &sem, .interruptible)
		await_queue(&sem, 2)
		start(&a[2], &sem, .kill_write)
		await_queue(&sem, 3)
		start(&a[3], &sem, .kill_read)
		await_queue(&sem, 4)
		signal(&a[0], u64(1) << 8, 0, false)
		join(&a[0])
		check(a[0].result == -4 && C.rsh_load32(&a[0].acquired) == 0, @LINE)
		await_word(&a[1].acquired, 1)
		await_word(&a[3].acquired, 1)
		check(queued(&sem) == 1 && C.rsh_count(&sem) == 770 && C.rsh_load32(&a[2].acquired) == 0, @LINE)
		allow(&a[1])
		allow(&a[3])
		join(&a[1])
		join(&a[3])
		C.up_read(&sem)
		await_word(&a[2].acquired, 1)
		allow(&a[2])
		join(&a[2])
		// Middle and tail records detach while the writer stays held.
		fresh(&sem)
		C.down_write(&sem)
		for i in 0 .. 4 {
			a[i] = Actor{}
			start(&a[i], &sem, if i == 3 { .kill_read } else { .interruptible })
			await_queue(&sem, u32(i + 1))
		}
		signal(&a[1], u64(1) << 14, 0, false)
		join(&a[1])
		check(a[1].result == -4 && queued(&sem) == 3, @LINE)
		signal(&a[3], u64(1) << 14, 0, false)
		for _ in 0 .. 1000 { C.sched_yield() }
		check(C.rsh_load32(&a[3].done) == 0 && queued(&sem) == 3, @LINE)
		signal(&a[3], u64(1) << 8, 0, false)
		join(&a[3])
		check(a[3].result == -4 && queued(&sem) == 2, @LINE)
		C.up_write(&sem)
		for i in [0, 2]! {
			await_word(&a[i].acquired, 1)
			allow(&a[i])
			join(&a[i])
			check(a[i].result == 0, @LINE)
		}
		check(C.rsh_count(&sem) == 0 && queued(&sem) == 0, @LINE)
		scenarios++
	}
}

fn signal_and_grant() {
	unsafe {
		mut sem := C.rw_semaphore{}
		mut a := Actor{}
		for operation in [Operation.interruptible, .kill_read, .kill_write]! {
			fresh(&sem)
			C.down_write(&sem)
			a = Actor{}
			start(&a, &sem, operation)
			await_queue(&sem, 1)
			signal(&a, u64(1) << 14, u64(1) << 14, false)
			for _ in 0 .. 1000 { C.sched_yield() }
			check(C.rsh_load32(&a.done) == 0 && queued(&sem) == 1, @LINE)
			signal(&a, 0, 0, true)
			join(&a)
			check(a.result == -4 && queued(&sem) == 0 && C.rsh_count(&sem) == 1, @LINE)
			C.up_write(&sem)
			// Waker publishes signal after actual grant under wait_lock.
			fresh(&sem)
			C.down_write(&sem)
			a = Actor{}
			start(&a, &sem, operation)
			await_queue(&sem, 1)
			a.context.signal_on_wake = true
			C.up_write(&sem)
			await_word(&a.acquired, 1)
			check(a.result == 0 && C.rsh_load64(&a.context.pending) & (u64(1) << 8) != 0, @LINE)
			allow(&a)
			join(&a)
		}
		// Uninterruptible down ignores both ordinary and fatal pending signals.
		fresh(&sem)
		C.down_write(&sem)
		a = Actor{}
		start(&a, &sem, .read)
		await_queue(&sem, 1)
		signal(&a, u64(1) << 8, 0, true)
		for _ in 0 .. 1000 { C.sched_yield() }
		check(C.rsh_load32(&a.done) == 0 && queued(&sem) == 1, @LINE)
		C.up_write(&sem)
		await_word(&a.acquired, 1)
		allow(&a)
		join(&a)
		scenarios++
	}
}

fn atomic_contexts() {
	unsafe {
		mut sem := C.rw_semaphore{}
		fresh(&sem)
		c := context()
		for flags in [u64(2), 514]! {
			for pins in [u32(0), 1, 3]! {
				for depth in [u32(0), 1, 2]! {
					c.flags = flags
					c.pins = pins
					c.irq_depth = depth
					check(C.down_read_trylock(&sem) == 1 && c.flags == flags && c.pins == pins && c.irq_depth == depth, @LINE)
					C.up_read(&sem)
					check(C.down_write_trylock(&sem) == 1 && c.flags == flags && c.pins == pins, @LINE)
					C.downgrade_write(&sem)
					C.up_read(&sem)
					check(C.down_write_trylock(&sem) == 1, @LINE)
					C.up_write(&sem)
					check(c.flags == flags && c.pins == pins && c.irq_depth == depth && C.rsh_count(&sem) == 0, @LINE)
				}
			}
		}
		c.flags = 514
		c.pins = 0
		c.irq_depth = 0
		scenarios++
	}
}

fn stress() {
	unsafe {
		mut sem := C.rw_semaphore{}
		fresh(&sem)
		mut ledger := Ledger{}
		mut a := [8]Actor{}
		for i in 0 .. 8 {
			a[i] = Actor{ iterations: 200, release: 1, ledger: &ledger }
			start(&a[i], &sem, if i < 4 { .read } else { .write })
		}
		for i in 0 .. 8 { join(&a[i]) }
		check(ledger.payload == 800 && C.rsh_load32(&ledger.visits) == 1600 && C.rsh_load32(&ledger.readers) == 0 && C.rsh_load32(&ledger.writers) == 0 && C.rsh_count(&sem) == 0 && queued(&sem) == 0, @LINE)
		scenarios++
	}
}

fn release_free() {
	for writer_index := 0; writer_index < 2; writer_index++ {
		writer := writer_index == 1
		for _ in 0 .. 24 {
			sem := unsafe { &C.rw_semaphore(C.malloc(sizeof(C.rw_semaphore))) }
			check(sem != nil, @LINE)
			fresh(sem)
			C.down_write(sem)
			C.rsh_store32(unsafe { &lifetime_done }, 0)
			mut a := Actor{ free_sem: true, release: 1 }
			start(&a, sem, if writer { .write } else { .read })
			await_queue(sem, 1)
			// Transport hook runs strictly after raw unlock and IRQ restoration. The
			// real queued API reacquires sem.wait_lock before returning/freeing.
			context().post_unlock_done = unsafe { &lifetime_done }
			C.up_write(sem)
			check(C.rsh_load32(&a.done) == 1 && a.sem == nil, @LINE)
			join(&a)
		}
	}
	scenarios++
}

fn cancel_release_races() {
	unsafe {
		for round in 0 .. 120 {
			mut sem := C.rw_semaphore{}
			fresh(&sem)
			C.down_write(&sem)
			mut a := Actor{ release: 1 }
			start(&a, &sem, if round & 1 == 0 { .interruptible } else { .kill_write })
			await_queue(&sem, 1)
			if round % 3 == 0 {
				signal(&a, u64(1) << 8, 0, false)
				C.up_write(&sem)
			} else {
				C.up_write(&sem)
				signal(&a, u64(1) << 8, 0, false)
			}
			join(&a)
			check((a.result == 0 || a.result == -4) && C.rsh_count(&sem) == 0 && queued(&sem) == 0, @LINE)
		}
		scenarios++
	}
}

fn invalid(mode i32) {
	unsafe {
		mut sem := C.rw_semaphore{}
		fresh(&sem)
		c := context()
		if mode in [17, 18] {
			C.down_write(&sem)
			C.rsh_set_owner(&sem, usize(c) + 8)
		}
		if mode == 20 { C.rsh_set_count(&sem, 8) }
		if mode == 21 { C.rsh_set_count(&sem, 257) }
		if mode == 22 {
			C.rsh_set_count(&sem, 0x7fffffffffffff00)
			C.rsh_set_owner(&sem, usize(c) | 1)
		}
		fatal_sem = &sem
		fatal_count = C.rsh_count(&sem)
		fatal_owner = C.rsh_owner(&sem)
		head := C.rsh_list(&sem)
		fatal_next = usize(head.next)
		fatal_prev = usize(head.prev)
		fatal_watch = true
		match mode {
			10 {
				c.flags = 2
				C.down_read(&sem)
			}
			11 {
				c.pins = 1
				C.down_write(&sem)
			}
			12 {
				c.irq_depth = 1
				C.down_read(&sem)
			}
			13 {
				c.active = false
				C.down_write(&sem)
			}
			14 { C.vrs_down_read(&sem, 0) }
			15 {
				c.active = false
				C.down_read_trylock(&sem)
			}
			16 {
				c.active = false
				C.down_write_trylock(&sem)
			}
			17 { C.up_write(&sem) }
			18 { C.downgrade_write(&sem) }
			19 { C.up_read(&sem) }
			20 { C.down_read_trylock(&sem) }
			21 { C.down_write_trylock(&sem) }
			22 { C.down_read_trylock(&sem) }
			23 { C.vrs_down_write(&sem, 1) }
			24 {
				C.down_write(&sem)
				fatal_count = C.rsh_count(&sem)
				fatal_owner = C.rsh_owner(&sem)
				C.down_write(&sem)
			}
			else { check(false, @LINE) }
		}
		check(false, @LINE)
	}
}

@[export:'main']
pub fn main(argc i32, argv &&char) i32 {
	unsafe {
		check(argc == 2 && C.pthread_key_create(&key, nil) == 0, @LINE)
		mut c := Context{}
		initialize_context(&c)
		install(&c)
		mode := C.atoi(argv[1])
		if mode == 1 {
			C.rsh_store32(&negative_postunlock_read, 1)
			release_free()
			check(false, @LINE)
		}
		if mode != 0 { invalid(mode) }
		basic()
		sharing_and_writer_gate()
		reader_phase(false)
		reader_phase(true)
		batch_limit()
		cancellation()
		signal_and_grant()
		atomic_contexts()
		stress()
		release_free()
		cancel_release_races()
		check(C.rsh_load32(&allocations) == 0 && may_sleep() && C.rsh_load32(&c.state) == 0, @LINE)
		destroy_context(&c)
		check(C.pthread_setspecific(key, nil) == 0 && C.pthread_key_delete(key) == 0, @LINE)
		C.printf(c'PASS: original rwsem records, actual V sleeping reader/writer phases, signals, atomic contexts,257-reader bound and postunlock free; scenarios=%u assertions=%u allocations=%u\n', scenarios, C.rsh_load32(&assertions), C.rsh_load32(&allocations))
		return 0
	}
}
