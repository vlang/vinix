// SPDX-License-Identifier: GPL-2.0-only
// Fixed-HZ conversions retain Linux integer widths and truncation.
@[translated]
module compatcore

struct C.vkt_timespec64 {
mut:
	tv_sec i64
	tv_nsec i64
}
@[c_extern]
__global C.jiffies u64
@[c_extern]
__global C.jiffies_64 u64

fn C.vinix_linuxkpi_clock_ns() u64
fn C.vinix_linuxkpi_clock_resolution_ns() u32
fn C.vinix_linuxkpi_timer_tick()
fn C.vkt_jiffies_address() usize
fn C.vkt_max_sec_in_jiffies() u64
fn C.vkt_sec_conversion() u32
fn C.vkt_nsec_conversion() u32
@[c: '__atomic_store_n']
fn C.vkt_store64(&u64, u64, i32)

__global (
	vkt_deadline_lock u32
	vkt_deadline_head &VktDeadline
	vkt_deadline_tail &VktDeadline
	vkt_last_tick_ns u64
)

struct VktDeadline {
mut:
	next &VktDeadline
	prev &VktDeadline
	task voidptr
	expires u64
	expires_ns u64
	absolute bool
	linked bool
}

fn vkt_deadline_add(wait &VktDeadline) {
	unsafe {
		wait.prev = vkt_deadline_tail
		wait.next = nil
		if is_null(vkt_deadline_tail) { vkt_deadline_head = wait }
		else { vkt_deadline_tail.next = wait }
		vkt_deadline_tail = wait
		wait.linked = true
	}
}

fn vkt_deadline_remove(wait &VktDeadline) {
	unsafe {
		if !wait.linked { return }
		if is_null(wait.prev) { vkt_deadline_head = wait.next }
		else { wait.prev.next = wait.next }
		if is_null(wait.next) { vkt_deadline_tail = wait.prev }
		else { wait.next.prev = wait.prev }
		wait.next = nil
		wait.prev = nil
		wait.linked = false
	}
}

@[export: 'vinix_linuxkpi_time_tick']
pub fn time_tick(now_ns u64) {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkt_deadline_lock)
		if now_ns >= vkt_last_tick_ns {
			vkt_last_tick_ns = now_ns
			now := u64(4294667296) + now_ns / 1000000
			C.vkt_store64(&C.jiffies, now, 0)
			mut wait := vkt_deadline_head
			for !is_null(wait) {
				next := wait.next
				if if wait.absolute { now_ns >= wait.expires_ns } else { i64(now - wait.expires) >= 0 } {
					task := wait.task
					vkt_deadline_remove(wait)
					task_wake_process(task)
				}
				wait = next
			}
		}
		C.vkp_spin_unlock_irqrestore(&vkt_deadline_lock, flags)
		C.vinix_linuxkpi_timer_tick()
	}
}

@[export: 'vinix_linuxkpi_time_waiters']
pub fn time_waiters() usize {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkt_deadline_lock)
		mut result := usize(0)
		for wait := vkt_deadline_head; !is_null(wait); wait = wait.next { result++ }
		C.vkp_spin_unlock_irqrestore(&vkt_deadline_lock, flags)
		return result
	}
}

@[export: 'vinix_linuxkpi_test_task_time_waiters']
pub fn time_task_waiters(task voidptr) usize {
	unsafe {
		flags := C.vkp_spin_lock_irqsave(&vkt_deadline_lock)
		mut result := usize(0)
		for wait := vkt_deadline_head; !is_null(wait); wait = wait.next {
			if wait.task == task { result++ }
		}
		C.vkp_spin_unlock_irqrestore(&vkt_deadline_lock, flags)
		return result
	}
}

@[export: 'schedule_timeout']
pub fn time_schedule_timeout(timeout i64) i64 {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		if timeout == i64(0x7fffffffffffffff) {
			task_schedule()
			return timeout
		}
		if timeout <= 0 {
			if timeout < 0 { vinix_linuxkpi_warn(c'linuxkpi_time.v', 0) }
			set_task_state(0)
			if timeout == 0 { C.vinix_linuxkpi_cond_resched() }
			return 0
		}
		mut wait := VktDeadline{task: C.vkp_current()}
		mut flags := C.vkp_spin_lock_irqsave(&vkt_deadline_lock)
		wait.expires = C.vkp_jiffies() + u64(timeout)
		vkt_deadline_add(&wait)
		C.vkp_spin_unlock_irqrestore(&vkt_deadline_lock, flags)
		task_schedule()
		flags = C.vkp_spin_lock_irqsave(&vkt_deadline_lock)
		vkt_deadline_remove(&wait)
		remaining := i64(wait.expires - C.vkp_jiffies())
		C.vkp_spin_unlock_irqrestore(&vkt_deadline_lock, flags)
		set_task_state(0)
		return if remaining > 0 { remaining } else { 0 }
	}
}

@[export: 'schedule_timeout_interruptible']
pub fn time_schedule_interruptible(timeout i64) i64 { set_task_state(1); return time_schedule_timeout(timeout) }
@[export: 'schedule_timeout_uninterruptible']
pub fn time_schedule_uninterruptible(timeout i64) i64 { set_task_state(2); return time_schedule_timeout(timeout) }
@[export: 'schedule_timeout_killable']
pub fn time_schedule_killable(timeout i64) i64 { set_task_state(258); return time_schedule_timeout(timeout) }
@[export: 'schedule_timeout_idle']
pub fn time_schedule_idle(timeout i64) i64 { set_task_state(1026); return time_schedule_timeout(timeout) }

@[export: 'ktime_get']
pub fn time_ktime_get() i64 { return i64(C.vinix_linuxkpi_clock_ns()) }
@[export: 'ktime_get_raw']
pub fn time_ktime_raw() i64 { return i64(C.vinix_linuxkpi_clock_ns()) }
@[export: 'ktime_get_resolution_ns']
pub fn time_resolution() u32 { return C.vinix_linuxkpi_clock_resolution_ns() }
@[export: 'ktime_get_ts64']
pub fn time_get_ts64(value &C.vkt_timespec64) { unsafe { *value = time_ns_to_ts64(time_ktime_get()) } }
@[export: 'ktime_get_raw_ts64']
pub fn time_get_raw_ts64(value &C.vkt_timespec64) { unsafe { *value = time_ns_to_ts64(time_ktime_raw()) } }
@[export: 'ktime_get_coarse_ts64']
pub fn time_get_coarse_ts64(value &C.vkt_timespec64) { unsafe { *value = time_ns_to_ts64(i64((C.vkp_jiffies() - 4294667296) * 1000000)) } }
@[export: 'ktime_get_seconds']
pub fn time_get_seconds() i64 { return i64((C.vkp_jiffies() - 4294667296) / 1000) }

@[export: 'jiffies_to_msecs']
pub fn time_jiffies_to_msecs(value u64) u32 { return u32(value) }
@[export: 'jiffies_to_usecs']
pub fn time_jiffies_to_usecs(value u64) u32 { return u32(value * 1000) }
@[export: 'jiffies64_to_msecs']
pub fn time_jiffies64_to_msecs(value u64) u64 { return value }
@[export: 'jiffies64_to_nsecs']
pub fn time_jiffies64_to_nsecs(value u64) u64 { return value * 1000000 }
@[export: '__msecs_to_jiffies']
pub fn time_msecs_to_jiffies(value u32) u64 { return if i32(value) < 0 { u64(0x3ffffffffffffffe) } else { u64(value) } }
@[export: '__usecs_to_jiffies']
pub fn time_usecs_to_jiffies(value u32) u64 {
	return if value > time_jiffies_to_usecs(0x3ffffffffffffffe) { u64(0x3ffffffffffffffe) } else { u64((value + 999) / 1000) }
}
@[export: 'nsecs_to_jiffies64']
pub fn time_nsecs_to_jiffies64(value u64) u64 { return value / 1000000 }
@[export: 'nsecs_to_jiffies']
pub fn time_nsecs_to_jiffies(value u64) u64 { return value / 1000000 }
@[export: 'jiffies_to_clock_t']
pub fn time_jiffies_to_clock_t(value u64) i64 { return i64(value / 10) }
@[export: 'jiffies_64_to_clock_t']
pub fn time_jiffies64_to_clock_t(value u64) u64 { return value / 10 }
@[export: 'nsec_to_clock_t']
pub fn time_nsec_to_clock_t(value u64) u64 { return value / 10000000 }
@[export: 'clock_t_to_jiffies']
pub fn time_clock_t_to_jiffies(value u64) u64 { return if value >= u64(-1) / 10 { u64(-1) } else { value * 10 } }

@[export: 'ns_to_timespec64']
pub fn time_ns_to_ts64(value i64) C.vkt_timespec64 {
	mut result := C.vkt_timespec64{tv_sec: value / 1000000000, tv_nsec: value % 1000000000}
	if result.tv_nsec < 0 { result.tv_nsec += 1000000000; result.tv_sec-- }
	return result
}
@[export: 'set_normalized_timespec64']
pub fn time_normalized_ts64(value &C.vkt_timespec64, seconds i64, nanoseconds i64) {
	unsafe { remainder := time_ns_to_ts64(nanoseconds)
		value.tv_sec = seconds + remainder.tv_sec
		value.tv_nsec = remainder.tv_nsec }
}
@[export: 'jiffies_to_timespec64']
pub fn time_jiffies_to_ts64(ticks u64, value &C.vkt_timespec64) {
	unsafe { value.tv_sec = i64(ticks / 1000); value.tv_nsec = i64((ticks % 1000) * 1000000) }
}
@[export: 'timespec64_to_jiffies']
pub fn time_ts64_to_jiffies(value &C.vkt_timespec64) u64 {
	mut seconds := u64(value.tv_sec)
	mut nanoseconds := value.tv_nsec + 999999
	maximum := C.vkt_max_sec_in_jiffies()
	if seconds >= maximum { seconds = maximum; nanoseconds = 0 }
	return ((seconds * u64(C.vkt_sec_conversion())) + ((u64(nanoseconds) * u64(C.vkt_nsec_conversion())) >> 29)) >> 22
}
@[export: 'ktime_add_safe']
pub fn time_ktime_add_safe(left i64, right i64) i64 {
	if left < 0 || right < 0 || u64(left) > u64(0x7fffffffffffffff) - u64(right) { return i64(0x7fffffffffffffff) }
	return left + right
}

@[export: 'msleep']
pub fn time_msleep(milliseconds u32) {
	mut remaining := time_msecs_to_jiffies(milliseconds) + 1
	for remaining != 0 { remaining = u64(time_schedule_uninterruptible(i64(remaining))) }
}

@[export: 'usleep_range_state']
pub fn time_usleep_range_state(minimum u64, maximum u64, state u32) {
	unsafe {
		require(C.vinix_linuxkpi_may_sleep())
		now := C.vinix_linuxkpi_clock_ns()
		require(maximum >= minimum && now <= u64(0x7fffffffffffffff) && maximum <= (u64(0x7fffffffffffffff) - now) / 1000)
		mut wait := VktDeadline{task: C.vkp_current(), expires_ns: now + minimum * 1000, absolute: true}
		for {
			set_task_state(state)
			mut flags := C.vkp_spin_lock_irqsave(&vkt_deadline_lock)
			if C.vinix_linuxkpi_clock_ns() >= wait.expires_ns {
				C.vkp_spin_unlock_irqrestore(&vkt_deadline_lock, flags)
				set_task_state(0)
				return
			}
			vkt_deadline_add(&wait)
			C.vkp_spin_unlock_irqrestore(&vkt_deadline_lock, flags)
			task_schedule()
			flags = C.vkp_spin_lock_irqsave(&vkt_deadline_lock)
			vkt_deadline_remove(&wait)
			C.vkp_spin_unlock_irqrestore(&vkt_deadline_lock, flags)
			set_task_state(0)
			if C.vinix_linuxkpi_clock_ns() >= wait.expires_ns { return }
			C.vinix_linuxkpi_cond_resched()
		}
	}
}

@[export: 'msleep_interruptible']
pub fn time_msleep_interruptible(milliseconds u32) u64 {
	mut remaining := time_msecs_to_jiffies(milliseconds) + 1
	for remaining != 0 && !C.vkp_signal_pending(1) { remaining = u64(time_schedule_interruptible(i64(remaining))) }
	return u64(time_jiffies_to_msecs(remaining))
}
@[export: 'ndelay']
pub fn time_ndelay(nanoseconds u64) {
	start := C.vinix_linuxkpi_clock_ns()
	for C.vinix_linuxkpi_clock_ns() - start < nanoseconds { C.vinix_linuxkpi_spin_wait() }
}
@[export: 'udelay']
pub fn time_udelay(microseconds u64) { require(microseconds <= u64(-1) / 1000); time_ndelay(microseconds * 1000) }

@[export: 'vinix_linuxkpi_time_selftest']
pub fn time_selftest() i32 {
	unsafe {
		if C.vkt_jiffies_address() != usize(&C.jiffies_64) { return -5 }
		before := (C.vkp_jiffies() - 4294667296) * 1000000
		mono := u64(time_ktime_get())
		raw := u64(time_ktime_raw())
		if mono < before || raw < mono { return -5 }
		value := time_ns_to_ts64(-1)
		if value.tv_sec != -1 || value.tv_nsec != 999999999 { return -5 }
		if time_msecs_to_jiffies(2) != 2 || time_usecs_to_jiffies(1001) != 2 || i64(u64(-1) - 1) >= 0 || time_ktime_add_safe(0x7fffffffffffffff, 1) != 0x7fffffffffffffff { return -5 }
		return 0
	}
}
