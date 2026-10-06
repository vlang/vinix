// SPDX-License-Identifier: GPL-2.0-only
// Promotion, dispatch and retirement share one raw lock. Timer ABI links
// remain visible to the original lockless timer_pending inline.
@[translated]
module compatcore

struct C.vkt_timer_view {
mut:
	next &C.vkt_timer_view
	pprev &&C.vkt_timer_view
	expires u64
	function fn (&C.timer_list)
	flags u32
}
fn C.vkt_unexpected_callback(&C.timer_list)
fn C.vkt_timer_thread(voidptr) voidptr
fn C.vkt_pthread_create(voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.vkt_pthread_detach(voidptr) i32
fn C.vkt_timer_worker_ready() voidptr
fn C.vkt_completion_complete(voidptr)
fn C.vkt_completion_wait(voidptr)
fn C.vinix_linuxkpi_task_get(voidptr)

__global (
	vkt_timer_lock u32
	vkt_timer_add_warned u32
	vkt_pending_head &C.vkt_timer_view
	vkt_ready_head &C.vkt_timer_view
	vkt_running_head &VktTimerRun
	vkt_running_tail &VktTimerRun
	vkt_timer_worker voidptr
)

struct VktTimerRun {
mut:
	next &VktTimerRun
	prev &VktTimerRun
	timer &C.vkt_timer_view
	task voidptr
}

fn vkt_running_locked(timer &C.vkt_timer_view) &VktTimerRun {
	unsafe {
		for run := vkt_running_head; !is_null(run); run = run.next {
			if run.timer == timer { return run }
		}
		return nil
	}
}

fn vkt_due_locked() &C.vkt_timer_view {
	unsafe {
		for timer := vkt_ready_head; !is_null(timer); timer = timer.next {
			if is_null(vkt_running_locked(timer)) { return timer }
		}
		return nil
	}
}

fn vkt_timer_add_head(timer &C.vkt_timer_view, head &&C.vkt_timer_view) {
	unsafe {
		C.vkt_store64(&u64(&timer.next), u64(*head), 0)
		if !is_null(*head) { C.vkt_store64(&u64(&(*head).pprev), u64(&timer.next), 0) }
		C.vkt_store64(&u64(head), u64(timer), 0)
		C.vkt_store64(&u64(&timer.pprev), u64(head), 0)
	}
}

fn vkt_detach_locked(timer &C.vkt_timer_view) i32 {
	unsafe {
		if is_null(timer.pprev) { return 0 }
		C.vkt_store64(&u64(timer.pprev), u64(timer.next), 0)
		if !is_null(timer.next) { C.vkt_store64(&u64(&timer.next.pprev), u64(timer.pprev), 0) }
		timer.next = nil
		timer.pprev = nil
		return 1
	}
}

@[export: 'init_timer_key']
pub fn timer_init(storage voidptr, function fn (&C.timer_list), flags u32, name &char, key voidptr) {
	unsafe {
		require((flags & ~u32(0x200000)) == 0)
		mut timer := &C.vkt_timer_view(storage)
		timer.next = nil
		timer.pprev = nil
		timer.expires = 0
		timer.function = function
		timer.flags = flags
	}
}

fn vkt_modify_timer(timer &C.vkt_timer_view, expires u64, pending_only bool, reduce bool, add bool) i32 {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkt_timer_lock)
		require((timer.flags & ~u32(0x200000)) == 0)
		pending := if is_null(timer.pprev) { i32(0) } else { i32(1) }
		if add && pending != 0 {
			if C.vkp_exchange32(&vkt_timer_add_warned, 1, 0) == 0 { vinix_linuxkpi_warn(c'linuxkpi_timer.v', 0) }
			C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags)
			return 0
		}
		if usize(timer.function) == 0 || (pending_only && pending == 0) {
			C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags)
			return 0
		}
		if pending != 0 && (timer.expires == expires || (reduce && i64(expires - timer.expires) >= 0)) {
			C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags)
			return 1
		}
		vkt_detach_locked(timer)
		C.vkt_store64(&timer.expires, expires, 0)
		vkt_timer_add_head(timer, &vkt_pending_head)
		C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags)
		return pending
	}
}

@[export: 'mod_timer']
pub fn timer_mod(storage voidptr, expires u64) i32 { return vkt_modify_timer(unsafe { &C.vkt_timer_view(storage) }, expires, false, false, false) }
@[export: 'mod_timer_pending']
pub fn timer_mod_pending(storage voidptr, expires u64) i32 { return vkt_modify_timer(unsafe { &C.vkt_timer_view(storage) }, expires, true, false, false) }
@[export: 'timer_reduce']
pub fn timer_reduce(storage voidptr, expires u64) i32 { return vkt_modify_timer(unsafe { &C.vkt_timer_view(storage) }, expires, false, true, false) }
@[export: 'add_timer']
pub fn timer_add(storage voidptr) { unsafe { timer := &C.vkt_timer_view(storage); vkt_modify_timer(timer, timer.expires, false, false, true) } }

fn vkt_delete_timer(timer &C.vkt_timer_view, sync bool, shutdown bool, blocking bool) i32 {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkt_timer_lock)
		run := vkt_running_locked(timer)
		if sync && !is_null(run) {
			require(!blocking || run.task != C.vkp_current())
			C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags)
			return -1
		}
		pending := vkt_detach_locked(timer)
		if shutdown { C.vkt_store64(&u64(&timer.function), 0, 0) }
		C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags)
		return pending
	}
}

@[export: 'timer_delete']
pub fn timer_delete(storage voidptr) i32 { return vkt_delete_timer(unsafe { &C.vkt_timer_view(storage) }, false, false, false) }
@[export: 'timer_shutdown']
pub fn timer_shutdown(storage voidptr) i32 { return vkt_delete_timer(unsafe { &C.vkt_timer_view(storage) }, false, true, false) }
@[export: 'try_to_del_timer_sync']
pub fn timer_try_delete_sync(storage voidptr) i32 { return vkt_delete_timer(unsafe { &C.vkt_timer_view(storage) }, true, false, false) }

fn vkt_delete_sync(timer &C.vkt_timer_view, shutdown bool) i32 {
	require((timer.flags & 0x200000) != 0 || (C.vinix_linuxkpi_irq_flags() & 512) != 0)
	for {
		result := vkt_delete_timer(timer, true, shutdown, true)
		if result >= 0 { return result }
		C.vinix_linuxkpi_spin_wait()
		C.vinix_linuxkpi_cond_resched()
	}
	return 0
}
@[export: 'timer_delete_sync']
pub fn timer_delete_sync(storage voidptr) i32 { return vkt_delete_sync(unsafe { &C.vkt_timer_view(storage) }, false) }
@[export: 'timer_shutdown_sync']
pub fn timer_shutdown_sync(storage voidptr) i32 { return vkt_delete_sync(unsafe { &C.vkt_timer_view(storage) }, true) }

@[export: 'vinix_linuxkpi_timer_tick']
pub fn timer_tick() {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkt_timer_lock)
		mut timer := vkt_pending_head
		for !is_null(timer) {
			next := timer.next
			if i64(C.vkp_jiffies() - timer.expires) >= 0 {
				vkt_detach_locked(timer)
				vkt_timer_add_head(timer, &vkt_ready_head)
			}
			timer = next
		}
		if !is_null(vkt_timer_worker) && !is_null(vkt_due_locked()) { task_wake_process(vkt_timer_worker) }
		C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags)
	}
}

fn vkt_run_add(run &VktTimerRun) {
 unsafe {
  run.prev = vkt_running_tail
  if is_null(vkt_running_tail) { vkt_running_head = run }
  else { vkt_running_tail.next = run }
  vkt_running_tail = run
 }
}

@[export: 'vinix_linuxkpi_timer_dispatch']
pub fn timer_dispatch() u32 {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		mut count := u32(0)
		for {
			mut run := VktTimerRun{task: C.vkp_current()}
			mut flags := C.vkp_spin_lock_irqsave(&vkt_timer_lock)
			timer := vkt_due_locked()
			if is_null(timer) { C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags); return count }
			run.timer = timer
			function := timer.function
			irq_safe := (timer.flags & 0x200000) != 0
			require(usize(function) != 0)
			vkt_detach_locked(timer)
			vkt_run_add(&run)
			C.vinix_linuxkpi_preempt_disable()
			C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, if irq_safe { u64(0) } else { flags })
			depth := C.vinix_linuxkpi_preempt_count()
			function(&C.timer_list(timer))
			require(C.vinix_linuxkpi_preempt_count() == depth && ((C.vinix_linuxkpi_irq_flags() & 512) != 0) != irq_safe)
			flags = C.vkp_spin_lock_irqsave(&vkt_timer_lock)
			// Callback may already have freed timer: only touch our stack record.
			if is_null(run.prev) { vkt_running_head = run.next }
			else { run.prev.next = run.next }
			if is_null(run.next) { vkt_running_tail = run.prev }
			else { run.next.prev = run.prev }
			C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags)
			if irq_safe { C.vinix_linuxkpi_irq_restore(512) }
			C.vinix_linuxkpi_preempt_enable()
			count++
		}
		return count
	}
}

@[export: 'vinix_linuxkpi_timer_active']
pub fn timer_active() usize {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkt_timer_lock)
		mut count := usize(0)
		for timer := vkt_pending_head; !is_null(timer); timer = timer.next { count++ }
		for timer := vkt_ready_head; !is_null(timer); timer = timer.next { count++ }
		for run := vkt_running_head; !is_null(run); run = run.next { count++ }
		C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags)
		return count
	}
}

fn vkt_round_jiffy(tick u64, cpu i32, up bool) u64 {
	original := tick
	mut value := tick + u64(cpu * 3)
	remainder := u32(value % 1000)
	value -= remainder
	if up || remainder >= 250 { value += 1000 }
	value -= u64(cpu * 3)
	return if i64(C.vkp_jiffies() - value) < 0 { value } else { original }
}
@[export: '__round_jiffies']
pub fn timer_round(tick u64, cpu i32) u64 { return vkt_round_jiffy(tick, cpu, false) }
@[export: '__round_jiffies_up']
pub fn timer_round_up(tick u64, cpu i32) u64 { return vkt_round_jiffy(tick, cpu, true) }
@[export: '__round_jiffies_relative']
pub fn timer_round_relative(tick u64, cpu i32) u64 { now := C.vkp_jiffies(); return vkt_round_jiffy(tick + now, cpu, false) - now }
@[export: '__round_jiffies_up_relative']
pub fn timer_round_up_relative(tick u64, cpu i32) u64 { now := C.vkp_jiffies(); return vkt_round_jiffy(tick + now, cpu, true) - now }
@[export: 'round_jiffies']
pub fn timer_round_current(tick u64) u64 { return timer_round(tick, i32(C.vinix_linuxkpi_cpu_id())) }
@[export: 'round_jiffies_up']
pub fn timer_round_up_current(tick u64) u64 { return timer_round_up(tick, i32(C.vinix_linuxkpi_cpu_id())) }
@[export: 'round_jiffies_relative']
pub fn timer_round_relative_current(tick u64) u64 { return timer_round_relative(tick, i32(C.vinix_linuxkpi_cpu_id())) }
@[export: 'round_jiffies_up_relative']
pub fn timer_round_up_relative_current(tick u64) u64 { return timer_round_up_relative(tick, i32(C.vinix_linuxkpi_cpu_id())) }

@[export: 'vkt_unexpected_callback']
pub fn timer_unexpected_callback(timer &C.timer_list) { require(false) }

@[export: 'vinix_linuxkpi_timer_selftest']
pub fn timer_selftest() i32 {
	unsafe {
		mut timer := C.vkt_timer_view{}
		timer_init(&timer, C.vkt_unexpected_callback, 0, nil, nil)
		expires := C.vkp_jiffies() + 10000
		mut result := i32(0)
		if !is_null(timer.pprev) || timer_mod_pending(&timer, expires) != 0 { result = -5 }
		if timer_reduce(&timer, expires) != 0 || is_null(timer.pprev) { result = -5 }
		if timer_mod(&timer, expires) != 1 || timer_reduce(&timer, expires + 1) != 1 || timer.expires != expires { result = -5 }
		if timer_try_delete_sync(&timer) != 1 || timer_delete_sync(&timer) != 0 { result = -5 }
		timer.expires = expires
		timer_add(&timer)
		if timer_shutdown_sync(&timer) != 1 || !is_null(timer.pprev) || usize(timer.function) != 0 { result = -5 }
		if timer_mod(&timer, expires) != 0 || !is_null(timer.pprev) { result = -5 }
		return result
	}
}

@[export: 'vkt_timer_thread']
pub fn timer_thread(argument voidptr) voidptr {
	unsafe {
		task := &C.vkt_task_view(C.vkp_current())
		C.vinix_linuxkpi_task_get(task.vinix_thread)
		mut flags := C.vkp_spin_lock_irqsave(&vkt_timer_lock)
		vkt_timer_worker = task
		C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags)
		C.vkt_completion_complete(C.vkt_timer_worker_ready())
		for {
			timer_dispatch()
			flags = C.vkp_spin_lock_irqsave(&vkt_timer_lock)
			if !is_null(vkt_due_locked()) { C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags); continue }
			set_task_state(2)
			C.vkp_spin_unlock_irqrestore(&vkt_timer_lock, flags)
			task_schedule()
		}
		return nil
	}
}

@[export: 'vinix_linuxkpi_timer_bootstrap']
pub fn timer_bootstrap() i32 {
	unsafe {
		mut native_thread := u64(0)
		if C.vkt_pthread_create(&native_thread, C.vkt_timer_thread, nil) != 0 { return -12 }
		require(C.vkt_pthread_detach(&native_thread) == 0)
		C.vkt_completion_wait(C.vkt_timer_worker_ready())
		return 0
	}
}
