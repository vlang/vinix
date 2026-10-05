// SPDX-License-Identifier: GPL-2.0-only
// I/O intent scopes preserve the original acquire/release ordering. Native
// queue transitions maintain blocked-CPU counts independently of these tokens.
@[translated]
module compatcore

@[export: 'vinix_linuxkpi_task_in_iowait']
pub fn task_in_iowait(storage voidptr) bool {
	unsafe {
		return C.vkp_load32(&u32(C.vkp_iowait_field(storage)), 2) != 0
	}
}

@[export: 'io_schedule_prepare']
pub fn io_schedule_prepare() i32 {
	unsafe {
		return i32(C.vkp_exchange32(&u32(C.vkp_iowait_field(C.vkp_current())), 1, 4))
	}
}

@[export: 'io_schedule_finish']
pub fn io_schedule_finish(token i32) {
	unsafe {
		require(token == 0 || token == 1)
		C.vkp_store32(&u32(C.vkp_iowait_field(C.vkp_current())), u32(token), 3)
	}
}

@[export: 'io_schedule']
pub fn io_schedule() {
	unsafe {
		token := io_schedule_prepare()
		C.vkp_schedule()
		io_schedule_finish(token)
	}
}

@[export: 'io_schedule_timeout']
pub fn io_schedule_timeout(timeout i64) i64 {
	unsafe {
		token := io_schedule_prepare()
		result := C.vkp_schedule_timeout(timeout)
		io_schedule_finish(token)
		return result
	}
}

@[export: 'nr_iowait_cpu']
pub fn nr_iowait_cpu(cpu i32) u32 {
	unsafe {
		require(cpu >= 0 && u32(cpu) < percpu_count())
		return C.vinix_linuxkpi_iowait_count(u32(cpu))
	}
}

@[export: 'nr_iowait']
pub fn nr_iowait() u32 {
	unsafe {
		mut result := u32(0)
		for cpu := u32(0); cpu < percpu_count(); cpu++ {
			blocked := C.vinix_linuxkpi_iowait_count(cpu)
			require(blocked <= u32(-1) - result)
			result += blocked
		}
		return result
	}
}

@[export: 'bit_wait_io']
pub fn bit_wait_io(key voidptr, mode i32) i32 {
	unsafe {
		io_schedule()
		return if C.vkp_signal_pending(mode) { -4 } else { 0 }
	}
}

@[export: 'bit_wait_io_timeout']
pub fn bit_wait_io_timeout(key voidptr, mode i32) i32 {
	unsafe {
		now := C.vkp_jiffies()
		timeout := C.vkp_bit_timeout(key)
		if i64(now - timeout) >= 0 { return -11 }
		io_schedule_timeout(i64(timeout - now))
		return if C.vkp_signal_pending(mode) { -4 } else { 0 }
	}
}
