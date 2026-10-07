// SPDX-License-Identifier: GPL-2.0-only
// Independent host sequence-counter fixture; original seqcount_test.h in Git.
@[translated]
module hostseq
#include "hostseq_v_contract.h"
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

struct C.mutex {}

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
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vmh_fixture_seq_thread(voidptr) voidptr
__global native_seq_static_lock C.seqlock_t
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
fn basic() {
	unsafe {
		mut plain := C.seqcount_t{}
		C.assert(!(C.raw_read_seqcount(&plain) != 0))
		C.seqcount_init(&plain)
		mut start := C.read_seqcount_begin(&plain)
		C.preempt_disable()
		C.write_seqcount_begin(&plain)
		C.assert(C.preempt_count() == 1 && C.raw_read_seqcount(&plain) & 1 != 0)
		C.assert(C.read_seqcount_retry(&plain, start))
		C.assert(C.read_seqcount_retry(&plain, C.raw_seqcount_begin(&plain)))
		C.write_seqcount_end(&plain)
		C.assert(C.preempt_count() == 1 && C.read_seqcount_retry(&plain, start))
		start = C.__read_seqcount_begin(&plain)
		C.smp_rmb()
		C.assert(!(C.__read_seqcount_retry(&plain, start)))
		C.write_seqcount_invalidate(&plain)
		C.assert(C.raw_read_seqcount(&plain) == start + 2 && C.read_seqcount_retry(&plain, start))
		start = C.raw_read_seqcount_begin(&plain)
		C.raw_write_seqcount_barrier(&plain)
		C.assert(C.raw_read_seqcount(&plain) == start + 2 && C.read_seqcount_retry(&plain, start))
		C.WRITE_ONCE(plain.sequence, u32(-2))
		C.raw_write_seqcount_begin(&plain)
		C.assert(!(C.raw_read_seqcount(&plain) != u32(-1)))
		C.raw_write_seqcount_end(&plain)
		C.assert(!(C.raw_read_seqcount(&plain) != 0))
		C.preempt_enable()

		mut spin := C.spinlock_t{}
		C.spin_lock_init(&spin)
		mut associated_spin := C.seqcount_spinlock_t{}
		C.seqcount_spinlock_init(&associated_spin, &spin)
		mut irq := usize(0)
		C.spin_lock_irqsave(&spin, irq)
		C.write_seqcount_begin_nested(&associated_spin, 0)
		C.assert(!C.vmh_interrupts && C.preempt_count() == 1)
		C.write_seqcount_end(&associated_spin)
		C.spin_unlock_irqrestore(&spin, irq)
		C.assert(C.vmh_interrupts && C.preempt_count() == 0)

		mut mutex := C.mutex{}
		C.mutex_init(&mutex)
		mut associated_mutex := C.seqcount_mutex_t{}
		C.seqcount_mutex_init(&associated_mutex, &mutex)
		C.mutex_lock(&mutex)
		C.preempt_disable()
		C.write_seqcount_begin(&associated_mutex)
		C.assert(C.vmh_interrupts && C.preempt_count() == 2)
		C.write_seqcount_end(&associated_mutex)
		C.assert(!(C.preempt_count() != 1))
		C.preempt_enable()
		C.raw_write_seqcount_begin(&associated_mutex)
		C.assert(!(C.preempt_count() != 1))
		C.raw_write_seqcount_end(&associated_mutex)
		C.assert(!(C.preempt_count() != 0))
		C.mutex_unlock(&mutex)
		C.mutex_destroy(&mutex)

		C.seqlock_init(&native_seq_static_lock)
		start = C.read_seqbegin(&native_seq_static_lock)
		C.write_seqlock_irqsave(&native_seq_static_lock, irq)
		C.assert(!C.vmh_interrupts && C.preempt_count() == 1)
		C.write_sequnlock_irqrestore(&native_seq_static_lock, irq)
		C.assert(C.vmh_interrupts && C.preempt_count() == 0 && C.read_seqretry(&native_seq_static_lock, start))
		mut exclusive := i32(-1)
		C.read_seqbegin_or_lock(&native_seq_static_lock, &exclusive)
		C.assert(C.spin_is_locked(&native_seq_static_lock.@lock) && C.preempt_count() == 1)
		C.assert(!(C.need_seqretry(&native_seq_static_lock, exclusive)))
		C.done_seqretry(&native_seq_static_lock, exclusive)
		C.assert(!C.spin_is_locked(&native_seq_static_lock.@lock) && C.preempt_count() == 0)
		outer_irq := C.vinix_linuxkpi_irq_save()
		exclusive = -1
		irq = C.read_seqbegin_or_lock_irqsave(&native_seq_static_lock, &exclusive)
		C.assert(!C.vmh_interrupts && C.preempt_count() == 1)
		C.done_seqretry_irqrestore(&native_seq_static_lock, exclusive, irq)
		C.assert(!C.vmh_interrupts && C.preempt_count() == 0)
		C.vinix_linuxkpi_irq_restore(outer_irq)

		mut latch := C.seqcount_latch_t{}
		C.seqcount_latch_init(&latch)
		mut copies := [2]Pair{}
		store(&copies[0], 1)
		store(&copies[1], 1)
		C.write_seqcount_latch_begin(&latch)
		C.assert(C.vmh_interrupts && C.preempt_count() == 0)
		start = C.read_seqcount_latch(&latch)
		C.assert(start & 1 != 0 && copies[start & 1].value == 1)
		store(&copies[0], 2)
		C.assert(!(C.read_seqcount_latch_retry(&latch, start)))
		C.write_seqcount_latch(&latch)
		C.assert(C.read_seqcount_latch_retry(&latch, start))
		start = C.raw_read_seqcount_latch(&latch)
		C.assert(start & 1 == 0 && copies[start & 1].value == 2)
		store(&copies[1], 2)
		C.write_seqcount_latch_end(&latch)
		C.assert(!(C.raw_read_seqcount_latch_retry(&latch, start)))
		C.assert(C.vmh_interrupts && C.preempt_count() == 0)
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
	ready u32
	go u32
}

struct Worker {
mut:
    model C.native_task_model
    shared &Shared = unsafe { nil }
    index u32
    reads u32
}
fn update(test &Shared, kind u32) {
	unsafe {
		mut irq := usize(0)
		if kind < 2 { C.spin_lock_irqsave(&test.spinlock, irq) }
		else if kind == 2 || kind == 4 { C.mutex_lock(&test.mutex) }
		else { C.write_seqlock_irqsave(&test.seqlock, irq) }
		if kind == 0 { C.write_seqcount_begin(&test.plain) }
		else if kind == 1 { C.write_seqcount_begin(&test.spin) }
		else if kind == 2 { C.write_seqcount_begin(&test.sleeping) }
		if kind < 4 {
			C.assert(C.preempt_count() == 1 && C.vmh_interrupts == (kind == 2))
			value := test.values[kind].value + 1
			C.WRITE_ONCE(test.values[kind].value, value)
			C.cpu_relax()
			C.WRITE_ONCE(test.values[kind].inverse, ~value)
		} else {
			value := test.copies[0].value + 1
			C.write_seqcount_latch_begin(&test.latch)
			C.assert(C.vmh_interrupts && C.preempt_count() == 0)
			C.WRITE_ONCE(test.copies[0].value, value)
			C.sched_yield()
			C.WRITE_ONCE(test.copies[0].inverse, ~value)
			C.write_seqcount_latch(&test.latch)
			C.WRITE_ONCE(test.copies[1].value, value)
			C.sched_yield()
			C.WRITE_ONCE(test.copies[1].inverse, ~value)
			C.write_seqcount_latch_end(&test.latch)
		}
		if kind == 0 { C.write_seqcount_end(&test.plain) }
		else if kind == 1 { C.write_seqcount_end(&test.spin) }
		else if kind == 2 { C.write_seqcount_end(&test.sleeping) }
		if kind < 2 { C.spin_unlock_irqrestore(&test.spinlock, irq) }
		else if kind == 2 || kind == 4 { C.mutex_unlock(&test.mutex) }
		else { C.write_sequnlock_irqrestore(&test.seqlock, irq) }
		C.assert(C.vmh_interrupts && C.preempt_count() == 0)
	}
}

fn read(test &Shared, kind u32) {
	unsafe {
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
		C.assert(inverse == ~value && C.vmh_interrupts && C.preempt_count() == 0)
	}
}


@[export: 'vmh_fixture_seq_thread']
pub fn thread(argument voidptr) voidptr {
    unsafe {
        worker := &Worker(argument)
        C.vmh_native_task = &worker.model
        C.vmh_current_cpu = worker.index
        C.__atomic_add_fetch(&worker.shared.ready, u32(1), i32(3))
        for C.__atomic_load_n(&worker.shared.go, 2) == 0 { C.sched_yield() }
        limit := if worker.index < 2 { u32(128) } else { u32(256) }
        for round := u32(0); round < limit; round++ {
            for kind := u32(0); kind < 5; kind++ {
                if worker.index < 2 { update(worker.shared, kind) }
                else { read(worker.shared, kind); worker.reads++ }
            }
            C.sched_yield()
        }
        C.assert(C.vmh_interrupts && C.preempt_count() == 0 && C.task_is_running(C.current))
        C.vmh_native_task = nil
        return nil
    }
}

@[export: 'vmh_seqcount_tests']
pub fn tests() {
    unsafe {
        before := C.vmh_live_pages
        saved_cpu := C.vmh_current_cpu
        mut controller := C.native_task_model{}
        C.vmh_sync_model_init(&controller, 269)
        C.vmh_native_task = &controller
        basic()
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
        mut threads := [4]C.pthread_t{}
        for i in 0 .. 4 {
            workers[i] = Worker{ shared: &test, index: u32(i) }
            C.vmh_sync_model_init(&workers[i].model, u32(270 + i))
            C.assert(C.pthread_create(&threads[i], nil, C.vmh_fixture_seq_thread, &workers[i]) == 0)
        }
        mut spin := u32(0)
        for C.__atomic_load_n(&test.ready, 2) != 4 {
            C.assert(spin < 1000000)
            C.sched_yield()
            spin++
        }
        C.__atomic_store_n(&test.go, u32(1), i32(3))
        for i in 0 .. 4 {
            C.assert(C.pthread_join(threads[i], nil) == 0)
            if i >= 2 { C.assert(workers[i].reads == 5 * 256) }
            C.vmh_sync_model_destroy(&workers[i].model)
        }
        for i in 0 .. 4 { C.assert(test.values[i].value == 256 && test.values[i].inverse == ~usize(256)) }
        for i in 0 .. 2 { C.assert(test.copies[i].value == 256 && test.copies[i].inverse == ~usize(256)) }
        C.mutex_destroy(&test.mutex)
        C.vmh_native_task = nil
        C.vmh_current_cpu = saved_cpu
        C.vmh_sync_model_destroy(&controller)
        C.assert(C.vmh_live_pages == before && C.vmh_interrupts && C.preempt_count() == 0)
    }
}
