// SPDX-License-Identifier: GPL-2.0-only
// Independent upstream sequence-counter observations with native workers.
@[translated]
module seqfixture

#include "linuxkpi_seq_fixture_v_contract.h"

@[typedef]
struct C.spinlock_t {}

@[typedef]
struct C.seqcount_t {
mut:
	sequence u32
}

@[typedef]
struct C.seqcount_spinlock_t {}

@[typedef]
struct C.seqcount_mutex_t {}

@[typedef]
struct C.seqlock_t {
	@lock C.spinlock_t
}

@[typedef]
struct C.seqcount_latch_t {}

@[typedef]
struct C.pthread_t {}

struct C.mutex {}
struct C.completion {}

type SeqWorker = fn (voidptr) voidptr
fn C.vinix_linuxkpi_fixture_seq_worker(voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, SeqWorker, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.preempt_disable()
fn C.preempt_enable()
fn C.preempt_count() u32
fn C.cpu_relax()
fn C.smp_rmb()
fn C.seqcount_init(voidptr)
fn C.seqcount_spinlock_init(voidptr, &C.spinlock_t)
fn C.seqcount_mutex_init(voidptr, &C.mutex)
fn C.seqcount_latch_init(&C.seqcount_latch_t)
fn C.raw_read_seqcount(voidptr) u32
fn C.read_seqcount_begin(voidptr) u32
fn C.__read_seqcount_begin(voidptr) u32
fn C.raw_seqcount_begin(voidptr) u32
fn C.raw_read_seqcount_begin(voidptr) u32
fn C.read_seqcount_retry(voidptr, u32) bool
fn C.__read_seqcount_retry(voidptr, u32) bool
fn C.write_seqcount_begin(voidptr)
fn C.write_seqcount_begin_nested(voidptr, i32)
fn C.write_seqcount_end(voidptr)
fn C.write_seqcount_invalidate(voidptr)
fn C.raw_write_seqcount_barrier(voidptr)
fn C.raw_write_seqcount_begin(voidptr)
fn C.raw_write_seqcount_end(voidptr)
fn C.seqlock_init(&C.seqlock_t)
fn C.read_seqbegin(&C.seqlock_t) u32
fn C.read_seqretry(&C.seqlock_t, u32) bool
fn C.write_seqlock_irqsave(&C.seqlock_t, usize)
fn C.write_sequnlock_irqrestore(&C.seqlock_t, usize)
fn C.read_seqbegin_or_lock(&C.seqlock_t, &i32)
fn C.need_seqretry(&C.seqlock_t, i32) bool
fn C.done_seqretry(&C.seqlock_t, i32)
fn C.read_seqbegin_or_lock_irqsave(&C.seqlock_t, &i32) usize
fn C.done_seqretry_irqrestore(&C.seqlock_t, i32, usize)
fn C.write_seqcount_latch_begin(&C.seqcount_latch_t)
fn C.write_seqcount_latch(&C.seqcount_latch_t)
fn C.write_seqcount_latch_end(&C.seqcount_latch_t)
fn C.read_seqcount_latch(&C.seqcount_latch_t) u32
fn C.raw_read_seqcount_latch(&C.seqcount_latch_t) u32
fn C.read_seqcount_latch_retry(&C.seqcount_latch_t, u32) bool
fn C.raw_read_seqcount_latch_retry(&C.seqcount_latch_t, u32) bool
fn C.WRITE_ONCE(usize, usize) usize
fn C.READ_ONCE(usize) usize
fn C.spin_lock_init(&C.spinlock_t)
fn C.spin_lock_irqsave(&C.spinlock_t, usize)
fn C.spin_unlock_irqrestore(&C.spinlock_t, usize)
fn C.spin_is_locked(&C.spinlock_t) bool
fn C.mutex_init(&C.mutex)
fn C.mutex_destroy(&C.mutex)
fn C.mutex_lock(&C.mutex)
fn C.mutex_unlock(&C.mutex)
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.complete_all(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.vinix_linuxkpi_worker_bind(u32) i32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_percpu_count() u32
fn C.cond_resched() i32
fn C.msleep(u32)
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)
fn C.BUG_ON(bool)

@[c_extern]
__global (
	C.EIO i32
	C.ENOMEM i32
	C.EOPNOTSUPP i32
)

__global native_seq_static_lock C.seqlock_t

fn irqs_enabled() bool { return C.vinix_linuxkpi_irq_flags() & (usize(1) << 9) != 0 }

struct Pair {
mut:
	value usize
	inverse usize
}

fn store(pair &Pair, value usize) {
	unsafe {
		C.WRITE_ONCE(pair.value, value)
		C.WRITE_ONCE(pair.inverse, ~value)
	}
}

fn basic() i32 {
	unsafe {
		mut result := i32(0)
		mut plain := C.seqcount_t{}
		if C.raw_read_seqcount(&plain) != 0 { result = -C.EIO }
		C.seqcount_init(&plain)
		mut start := C.read_seqcount_begin(&plain)
		C.preempt_disable()
		C.write_seqcount_begin(&plain)
		if !(C.preempt_count() == 1 && C.raw_read_seqcount(&plain) & 1 != 0) { result = -C.EIO }
		if !C.read_seqcount_retry(&plain, start) { result = -C.EIO }
		if !C.read_seqcount_retry(&plain, C.raw_seqcount_begin(&plain)) { result = -C.EIO }
		C.write_seqcount_end(&plain)
		if !(C.preempt_count() == 1 && C.read_seqcount_retry(&plain, start)) { result = -C.EIO }
		start = C.__read_seqcount_begin(&plain)
		C.smp_rmb()
		if C.__read_seqcount_retry(&plain, start) { result = -C.EIO }
		C.write_seqcount_invalidate(&plain)
		if !(C.raw_read_seqcount(&plain) == start + 2 && C.read_seqcount_retry(&plain, start)) { result = -C.EIO }
		start = C.raw_read_seqcount_begin(&plain)
		C.raw_write_seqcount_barrier(&plain)
		if !(C.raw_read_seqcount(&plain) == start + 2 && C.read_seqcount_retry(&plain, start)) { result = -C.EIO }
		C.WRITE_ONCE(plain.sequence, u32(-2))
		C.raw_write_seqcount_begin(&plain)
		if C.raw_read_seqcount(&plain) != u32(-1) { result = -C.EIO }
		C.raw_write_seqcount_end(&plain)
		if C.raw_read_seqcount(&plain) != 0 { result = -C.EIO }
		C.preempt_enable()

		mut spin := C.spinlock_t{}
		C.spin_lock_init(&spin)
		mut associated_spin := C.seqcount_spinlock_t{}
		C.seqcount_spinlock_init(&associated_spin, &spin)
		mut irq := usize(0)
		C.spin_lock_irqsave(&spin, irq)
		C.write_seqcount_begin_nested(&associated_spin, 0)
		if !(!irqs_enabled() && C.preempt_count() == 1) { result = -C.EIO }
		C.write_seqcount_end(&associated_spin)
		C.spin_unlock_irqrestore(&spin, irq)
		if !(irqs_enabled() && C.preempt_count() == 0) { result = -C.EIO }

		mut mutex := C.mutex{}
		C.mutex_init(&mutex)
		mut associated_mutex := C.seqcount_mutex_t{}
		C.seqcount_mutex_init(&associated_mutex, &mutex)
		C.mutex_lock(&mutex)
		C.preempt_disable()
		C.write_seqcount_begin(&associated_mutex)
		if !(irqs_enabled() && C.preempt_count() == 2) { result = -C.EIO }
		C.write_seqcount_end(&associated_mutex)
		if C.preempt_count() != 1 { result = -C.EIO }
		C.preempt_enable()
		C.raw_write_seqcount_begin(&associated_mutex)
		if C.preempt_count() != 1 { result = -C.EIO }
		C.raw_write_seqcount_end(&associated_mutex)
		if C.preempt_count() != 0 { result = -C.EIO }
		C.mutex_unlock(&mutex)
		C.mutex_destroy(&mutex)

		C.seqlock_init(&native_seq_static_lock)
		start = C.read_seqbegin(&native_seq_static_lock)
		C.write_seqlock_irqsave(&native_seq_static_lock, irq)
		if !(!irqs_enabled() && C.preempt_count() == 1) { result = -C.EIO }
		C.write_sequnlock_irqrestore(&native_seq_static_lock, irq)
		if !(irqs_enabled() && C.preempt_count() == 0 && C.read_seqretry(&native_seq_static_lock, start)) { result = -C.EIO }
		mut exclusive := i32(-1)
		C.read_seqbegin_or_lock(&native_seq_static_lock, &exclusive)
		if !(C.spin_is_locked(&native_seq_static_lock.@lock) && C.preempt_count() == 1) { result = -C.EIO }
		if C.need_seqretry(&native_seq_static_lock, exclusive) { result = -C.EIO }
		C.done_seqretry(&native_seq_static_lock, exclusive)
		if !(!C.spin_is_locked(&native_seq_static_lock.@lock) && C.preempt_count() == 0) { result = -C.EIO }
		outer_irq := C.vinix_linuxkpi_irq_save()
		exclusive = -1
		irq = C.read_seqbegin_or_lock_irqsave(&native_seq_static_lock, &exclusive)
		if !(!irqs_enabled() && C.preempt_count() == 1) { result = -C.EIO }
		C.done_seqretry_irqrestore(&native_seq_static_lock, exclusive, irq)
		if !(!irqs_enabled() && C.preempt_count() == 0) { result = -C.EIO }
		C.vinix_linuxkpi_irq_restore(outer_irq)

		mut latch := C.seqcount_latch_t{}
		C.seqcount_latch_init(&latch)
		mut copies := [2]Pair{}
		store(&copies[0], 1)
		store(&copies[1], 1)
		C.write_seqcount_latch_begin(&latch)
		if !(irqs_enabled() && C.preempt_count() == 0) { result = -C.EIO }
		start = C.read_seqcount_latch(&latch)
		if !(start & 1 != 0 && copies[start & 1].value == 1) { result = -C.EIO }
		store(&copies[0], 2)
		if C.read_seqcount_latch_retry(&latch, start) { result = -C.EIO }
		C.write_seqcount_latch(&latch)
		if !C.read_seqcount_latch_retry(&latch, start) { result = -C.EIO }
		start = C.raw_read_seqcount_latch(&latch)
		if !(start & 1 == 0 && copies[start & 1].value == 2) { result = -C.EIO }
		store(&copies[1], 2)
		C.write_seqcount_latch_end(&latch)
		if C.raw_read_seqcount_latch_retry(&latch, start) { result = -C.EIO }
		if !(irqs_enabled() && C.preempt_count() == 0) { result = -C.EIO }
		return result
	}
}

struct Shared {
mut:
	spinlock C.spinlock_t
	mutex C.mutex
	plain C.seqcount_t
	spin C.seqcount_spinlock_t
	sleeping C.seqcount_mutex_t
	seqlock C.seqlock_t
	latch C.seqcount_latch_t
	values [4]Pair
	copies [2]Pair
}

struct Worker {
mut:
	shared &Shared = unsafe { nil }
	thread C.pthread_t
	entered C.completion
	go C.completion
	done C.completion
	index u32
	cpu u32
	reads u32
	cancel u32
	result i32
	initialized bool
	started bool
}

fn update(test &Shared, kind u32) i32 {
	unsafe {
		mut result := i32(0)
		mut irq := usize(0)
		if kind < 2 { C.spin_lock_irqsave(&test.spinlock, irq) }
		else if kind == 2 || kind == 4 { C.mutex_lock(&test.mutex) }
		else { C.write_seqlock_irqsave(&test.seqlock, irq) }
		if kind == 0 { C.write_seqcount_begin(&test.plain) }
		else if kind == 1 { C.write_seqcount_begin(&test.spin) }
		else if kind == 2 { C.write_seqcount_begin(&test.sleeping) }
		if kind < 4 {
			if !(C.preempt_count() == 1 && irqs_enabled() == (kind == 2)) { result = -C.EIO }
			value := test.values[kind].value + 1
			C.WRITE_ONCE(test.values[kind].value, value)
			C.cpu_relax()
			C.WRITE_ONCE(test.values[kind].inverse, ~value)
		} else {
			value := test.copies[0].value + 1
			C.write_seqcount_latch_begin(&test.latch)
			if !(irqs_enabled() && C.preempt_count() == 0) { result = -C.EIO }
			C.WRITE_ONCE(test.copies[0].value, value)
			C.cond_resched()
			C.WRITE_ONCE(test.copies[0].inverse, ~value)
			C.write_seqcount_latch(&test.latch)
			C.WRITE_ONCE(test.copies[1].value, value)
			C.cond_resched()
			C.WRITE_ONCE(test.copies[1].inverse, ~value)
			C.write_seqcount_latch_end(&test.latch)
		}
		if kind == 0 { C.write_seqcount_end(&test.plain) }
		else if kind == 1 { C.write_seqcount_end(&test.spin) }
		else if kind == 2 { C.write_seqcount_end(&test.sleeping) }
		if kind < 2 { C.spin_unlock_irqrestore(&test.spinlock, irq) }
		else if kind == 2 || kind == 4 { C.mutex_unlock(&test.mutex) }
		else { C.write_sequnlock_irqrestore(&test.seqlock, irq) }
		if !(irqs_enabled() && C.preempt_count() == 0) { result = -C.EIO }
		return result
	}
}

fn read(test &Shared, kind u32) i32 {
	unsafe {
		mut result := i32(0)
		mut value := usize(0)
		mut inverse := usize(0)
		for {
			mut start := u32(0)
			if kind == 0 { start = C.read_seqcount_begin(&test.plain) }
			else if kind == 1 { start = C.read_seqcount_begin(&test.spin) }
			else if kind == 2 { start = C.read_seqcount_begin(&test.sleeping) }
			else if kind == 3 { start = C.read_seqbegin(&test.seqlock) }
			else { start = C.read_seqcount_latch(&test.latch) }
			pair := if kind < 4 { &test.values[kind] } else { &test.copies[start & 1] }
			value = C.READ_ONCE(pair.value)
			C.cpu_relax()
			inverse = C.READ_ONCE(pair.inverse)
			mut retry := false
			if kind == 0 { retry = C.read_seqcount_retry(&test.plain, start) }
			else if kind == 1 { retry = C.read_seqcount_retry(&test.spin, start) }
			else if kind == 2 { retry = C.read_seqcount_retry(&test.sleeping, start) }
			else if kind == 3 { retry = C.read_seqretry(&test.seqlock, start) }
			else { retry = C.read_seqcount_latch_retry(&test.latch, start) }
			if !retry { break }
		}
		if !(inverse == ~value && irqs_enabled() && C.preempt_count() == 0) { result = -C.EIO }
		return result
	}
}

@[export: 'vinix_linuxkpi_fixture_seq_worker']
pub fn worker(argument voidptr) voidptr {
	unsafe {
		mut worker := &Worker(argument)
		worker.result = C.vinix_linuxkpi_worker_bind(worker.cpu)
		C.complete(&worker.entered)
		C.wait_for_completion(&worker.go)
		limit := if worker.index < 2 { u32(128) } else { u32(256) }
		for round := u32(0); worker.result == 0 && round < limit && C.__atomic_load_n(&worker.cancel, 2) == 0; round++ {
			for kind := u32(0); kind < 5; kind++ {
				mut result := i32(0)
				if worker.index < 2 { result = update(worker.shared, kind) }
				else { result = read(worker.shared, kind); worker.reads++ }
				if result != 0 { worker.result = result }
			}
			C.cond_resched()
			if round % 16 == 0 { C.msleep(1) }
			if !irqs_enabled() || C.preempt_count() != 0 || C.vinix_linuxkpi_cpu_id() != worker.cpu {
				worker.result = -C.EIO
			}
		}
		C.complete(&worker.done)
		C.pthread_exit(nil)
		return nil
	}
}

@[export: 'vinix_linuxkpi_seqcount_native_selftest']
pub fn selftest() i32 {
	unsafe {
		mut result := basic()
		if result != 0 { return result }
		mut test := Shared{}
		C.spin_lock_init(&test.spinlock)
		C.mutex_init(&test.mutex)
		C.seqcount_init(&test.plain)
		C.seqcount_spinlock_init(&test.spin, &test.spinlock)
		C.seqcount_mutex_init(&test.sleeping, &test.mutex)
		C.seqlock_init(&test.seqlock)
		C.seqcount_latch_init(&test.latch)
		for i in 0 .. 4 { store(&test.values[i], 0) }
		for i in 0 .. 2 { store(&test.copies[i], 0) }
		mut workers := [4]Worker{}
		cpus := C.vinix_linuxkpi_percpu_count()
		if cpus == 0 || cpus > 64 { result = -C.EOPNOTSUPP }
		else {
			for i in 0 .. 4 {
				workers[i].shared = &test
				workers[i].index = u32(i)
				workers[i].cpu = u32(i) % cpus
				C.init_completion(&workers[i].entered)
				C.init_completion(&workers[i].go)
				C.init_completion(&workers[i].done)
				workers[i].initialized = true
				if C.pthread_create(&workers[i].thread, nil, C.vinix_linuxkpi_fixture_seq_worker, &workers[i]) != 0 {
					result = -C.ENOMEM; break
				}
				workers[i].started = true
				if C.wait_for_completion_timeout(&workers[i].entered, 2000) == 0 { result = -C.EIO; break }
			}
			if result == 0 {
				for i in 0 .. 4 { C.complete(&workers[i].go) }
				for i in 0 .. 4 {
					if C.wait_for_completion_timeout(&workers[i].done, 2000) == 0 { result = -C.EIO; break }
				}
			}
		}
		// Cancellation only between complete writer transactions, then join all.
		for i in 0 .. 4 {
			C.__atomic_store_n(&workers[i].cancel, 1, 3)
			if workers[i].initialized { C.complete_all(&workers[i].go) }
		}
		for i in 0 .. 4 {
			if !workers[i].started { continue }
			C.BUG_ON(C.pthread_join(workers[i].thread, nil) != 0)
			if workers[i].result != 0 { result = -C.EIO }
			if result == 0 && i >= 2 && workers[i].reads != 5 * 256 { result = -C.EIO }
		}
		if result == 0 {
			for i in 0 .. 4 {
				if !(test.values[i].value == 256 && test.values[i].inverse == ~usize(256)) { result = -C.EIO }
			}
			for i in 0 .. 2 {
				if !(test.copies[i].value == 256 && test.copies[i].inverse == ~usize(256)) { result = -C.EIO }
			}
		}
		C.mutex_destroy(&test.mutex)
		return result
	}
}
