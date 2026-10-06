// SPDX-License-Identifier: GPL-2.0-only
// Bounded owned records. Producers never allocate, call the console or wake tasks.
@[translated]
module compatcore

fn C.memmove(voidptr, voidptr, usize) voidptr
fn C.vinix_linuxkpi_log_caller() u64
fn C.msleep(u32)
fn C.__msecs_to_jiffies(u32) u64

@[c: '__atomic_store_n']
fn C.vkr_store64(&u64, u64, i32)

@[c: '__atomic_signal_fence']
fn C.vkr_signal_fence(i32)

struct PrintRecord {
mut:
	sequence      u64
	caller        u64
	format_status u32
	length        u16
	level         u8
	flags         u8
	text          [1024]char
}

struct PrintState {
mut:
	submitted     u64
	retired       u64
	dropped       u64
	truncated     u64
	format_errors u64
	queued        u32
	in_flight     bool
	worker_live   bool
	paused        bool
	key_ready     bool
}

__global (
	vkr_log_guard         u32
	vkr_log_records       [64]PrintRecord
	vkr_log_head          u32
	vkr_log_count         u32
	vkr_log_submitted     u64
	vkr_log_dropped       u64
	vkr_log_truncated     u64
	vkr_log_errors        u64
	vkr_log_in_flight     u64
	vkr_log_stop          bool
	vkr_log_paused        bool
	vkr_log_key_ready     bool
	vkr_log_fail_create   bool
	vkr_log_task          voidptr
	vkr_log_sink_callback voidptr
	vkr_log_sink_argument voidptr
)

fn vkrp_lock() u64 {
	unsafe { return C.vkp_spin_lock_irqsave(&vkr_log_guard)
	 }
}

fn vkrp_unlock(flags u64) {
	unsafe { C.vkp_spin_unlock_irqrestore(&vkr_log_guard, flags) }
}

fn vkrp_expired(deadline u64) bool { return i64(C.vkp_jiffies() - deadline) >= 0 }

// An in-flight stack record retires only after its sink returns.
fn vkrp_retired() u64 {
	unsafe {
		if vkr_log_in_flight != 0 { return vkr_log_in_flight - 1 }
		if vkr_log_count != 0 { return vkr_log_records[vkr_log_head].sequence - 1 }
		return vkr_log_submitted
	}
}

@[export: 'vkr_log_emit']
pub fn vkr_log_emit(facility i32, input_level i32, dev_info voidptr, fmt &char, args voidptr) i32 {
	unsafe {
		if facility != 0 || usize(dev_info) != 0 { return -95 }
		if input_level < -2 || input_level > 7 || usize(fmt) == 0 { return -22 }
		if vkr_log_suppress() != 0 { return 0 }
		mut level := if input_level == -2 { i32(-1) } else { input_level }
		mut record := PrintRecord{}
		result := vkr_format_entry(&record.text[0], sizeof(record.text), fmt, args, &record.format_status)
		if result < 0 { return result }
		mut length := usize(u32(result))
		if length >= sizeof(record.text) {
			length = sizeof(record.text) - 1
			record.flags |= 4
		}
		if length != 0 && record.text[length - 1] == char(`\n`) {
			length--
			record.flags |= 2
		}
		mut prefix := usize(0)
		for length - prefix >= 2 {
			mut header := i32(0)
			if record.text[prefix] == char(1) {
				c := u8(record.text[prefix + 1])
				if (c >= `0` && c <= `7`) || c == `c` { header = i32(c) }
			}
			if header == 0 { break }
			if header == i32(`c`) {
				record.flags |= 1
			} else if level == -1 {
				level = header - i32(`0`)
			}
			prefix += 2
		}
		if prefix != 0 {
			length -= prefix
			C.memmove(&record.text[0], &record.text[prefix], length)
		}
		record.text[length] = 0
		record.length = u16(length)
		record.level = u8(if level == -1 { vkr_log_console(1) & 7 } else { level })
		record.caller = C.vinix_linuxkpi_log_caller()
		flags := vkrp_lock()
		require(vkr_log_submitted != u64(-1))
		vkr_log_submitted++
		record.sequence = vkr_log_submitted
		if vkr_log_count == 64 {
			vkr_log_head = (vkr_log_head + 1) % 64
			vkr_log_count--
			vkr_log_dropped++
		}
		slot := (vkr_log_head + vkr_log_count) % 64
		vkr_log_records[slot] = record
		vkr_log_count++
		if (record.flags & 4) != 0 { vkr_log_truncated++ }
		if (record.format_status & 3) != 0 { vkr_log_errors++ }
		vkrp_unlock(flags)
		return i32(length)
	}
}

@[export: 'vkr_log_snapshot']
pub fn vkr_log_snapshot() u64 {
	unsafe {
		flags := vkrp_lock()
		snapshot := vkr_log_submitted
		vkrp_unlock(flags)
		return snapshot
	}
}

@[export: 'vkr_log_state']
pub fn vkr_log_state(state &PrintState) {
	unsafe {
		flags := vkrp_lock()
		*state = PrintState{
			submitted:     vkr_log_submitted
			retired:       vkrp_retired()
			dropped:       vkr_log_dropped
			truncated:     vkr_log_truncated
			format_errors: vkr_log_errors
			queued:        vkr_log_count
			in_flight:     vkr_log_in_flight != 0
			worker_live:   usize(vkr_log_task) != 0
			paused:        vkr_log_paused
			key_ready:     vkr_log_key_ready
		}
		vkrp_unlock(flags)
	}
}

@[export: 'vkr_log_flush']
pub fn vkr_log_flush(snapshot u64, timeout_ms u32) i32 {
	unsafe {
		if !C.vinix_linuxkpi_may_sleep() { return -11 }
		caller := C.vkp_current()
		deadline := C.vkp_jiffies() + C.__msecs_to_jiffies(timeout_ms)
		for {
			flags := vkrp_lock()
			mut result := i32(1)
			if snapshot > vkr_log_submitted {
				result = -22
			} else if caller == vkr_log_task {
				result = -35
			} else if vkrp_retired() >= snapshot {
				result = 0
			} else if usize(vkr_log_task) == 0 {
				result = -19
			}
			vkrp_unlock(flags)
			if result != 1 { return result }
			if vkrp_expired(deadline) { return -110 }
			C.msleep(1)
		}
		return 0
	}
}

fn vkrp_worker(_ voidptr) voidptr {
	unsafe {
		vkr_log_host_enter()
		task := vkr_log_current_get()
		mut flags := vkrp_lock()
		vkr_log_task = task
		vkrp_unlock(flags)
		vkr_log_complete(vkr_log_ready())
		for {
			mut record := PrintRecord{}
			mut sink := voidptr(0)
			mut argument := voidptr(0)
			flags = vkrp_lock()
			stop := vkr_log_stop && vkr_log_count == 0
			ready := !vkr_log_paused && vkr_log_count != 0
			key_ready := vkr_log_key_ready
			if ready {
				record = vkr_log_records[vkr_log_head]
				vkr_log_head = (vkr_log_head + 1) % 64
				vkr_log_count--
				vkr_log_in_flight = record.sequence
				sink = vkr_log_sink_callback
				argument = vkr_log_sink_argument
			}
			vkrp_unlock(flags)
			if stop { break }
			if !key_ready {
				mut key := [2]u64{}
				if vkr_log_key(&key[0]) {
					result := vkr_format_key(&key[0])
					flags = vkrp_lock()
					if result == 0 || result == -114 { vkr_log_key_ready = true }
					vkrp_unlock(flags)
					C.vkr_store64(&key[0], 0, 0)
					C.vkr_store64(&key[1], 0, 0)
					C.vkr_signal_fence(5)
				}
			}
			if !ready {
				C.msleep(10)
				continue
			}
			require(C.vinix_linuxkpi_may_sleep())
			if usize(sink) != 0 {
				vkr_log_call_sink(sink, &record, argument)
			} else if i32(record.level) < vkr_log_console(0) {
				record.text[record.length] = char(`\n`)
				vkr_log_write(&record.text[0], usize(record.length) + 1)
			}
			flags = vkrp_lock()
			require(vkr_log_in_flight == record.sequence)
			vkr_log_in_flight = 0
			vkrp_unlock(flags)
		}
		vkr_log_host_leave()
		vkr_log_exit()
		return nil
	}
}

@[export: 'vkr_log_bootstrap']
pub fn vkr_log_bootstrap() i32 {
	unsafe {
		if !C.vinix_linuxkpi_may_sleep() { return -11 }
		caller := C.vkp_current()
		mut flags := vkrp_lock()
		self := caller == vkr_log_task
		vkrp_unlock(flags)
		if self { return 0 }
		lifecycle := vkr_log_lifecycle()
		C.vkp_mutex_lock(lifecycle)
		flags = vkrp_lock()
		if usize(vkr_log_task) != 0 {
			vkrp_unlock(flags)
			C.vkp_mutex_unlock(lifecycle)
			return 0
		}
		vkr_log_stop = false
		fail := vkr_log_fail_create
		vkr_log_fail_create = false
		vkrp_unlock(flags)
		vkr_log_reinit(vkr_log_ready())
		if fail || vkr_log_create(vkrp_worker, nil) != 0 {
			C.vkp_mutex_unlock(lifecycle)
			return -12
		}
		vkr_log_wait(vkr_log_ready())
		C.vkp_mutex_unlock(lifecycle)
		return 0
	}
}

@[export: 'vkr_log_shutdown']
pub fn vkr_log_shutdown() i32 {
	unsafe {
		if !C.vinix_linuxkpi_may_sleep() { return -11 }
		caller := C.vkp_current()
		mut flags := vkrp_lock()
		self := caller == vkr_log_task
		vkrp_unlock(flags)
		if self { return -35 }
		lifecycle := vkr_log_lifecycle()
		C.vkp_mutex_lock(lifecycle)
		flags = vkrp_lock()
		task := vkr_log_task
		if task == caller {
			vkrp_unlock(flags)
			C.vkp_mutex_unlock(lifecycle)
			return -35
		}
		if usize(task) == 0 {
			vkrp_unlock(flags)
			C.vkp_mutex_unlock(lifecycle)
			return 0
		}
		vkr_log_stop = true
		vkr_log_paused = false
		vkrp_unlock(flags)
		require(vkr_log_join() == 0)
		flags = vkrp_lock()
		require(vkr_log_count == 0 && vkr_log_in_flight == 0)
		vkr_log_task = nil
		vkr_log_sink_callback = nil
		vkr_log_sink_argument = nil
		vkrp_unlock(flags)
		vkr_log_task_put(task)
		C.vkp_mutex_unlock(lifecycle)
		return 0
	}
}

@[export: 'vkr_log_pause']
pub fn vkr_log_pause(pause bool, timeout_ms u32) i32 {
	unsafe {
		if !C.vinix_linuxkpi_may_sleep() { return -11 }
		caller := C.vkp_current()
		deadline := C.vkp_jiffies() + C.__msecs_to_jiffies(timeout_ms)
		for {
			flags := vkrp_lock()
			if caller == vkr_log_task {
				vkrp_unlock(flags)
				return -35
			}
			vkr_log_paused = pause
			busy := vkr_log_in_flight != 0
			vkrp_unlock(flags)
			if !pause || !busy { return 0 }
			if vkrp_expired(deadline) { return -110 }
			C.msleep(1)
		}
		return 0
	}
}

@[export: 'vkr_log_sink']
pub fn vkr_log_sink(sink voidptr, argument voidptr) i32 {
	unsafe {
		if !C.vinix_linuxkpi_may_sleep() { return -11 }
		flags := vkrp_lock()
		mut result := i32(-16)
		if vkr_log_paused && vkr_log_in_flight == 0 {
			vkr_log_sink_callback = sink
			vkr_log_sink_argument = argument
			result = 0
		}
		vkrp_unlock(flags)
		return result
	}
}

@[export: 'vkr_log_fail']
pub fn vkr_log_fail(fail bool) {
	unsafe {
		flags := vkrp_lock()
		vkr_log_fail_create = fail
		vkrp_unlock(flags)
	}
}

@[export: 'vinix_linuxkpi_printk_snapshot']
pub fn native_printk_snapshot() u64 { return vkr_log_snapshot() }
@[export: 'vinix_linuxkpi_printk_get_state']
pub fn native_printk_state(p &PrintState) { vkr_log_state(p) }
@[export: 'vinix_linuxkpi_printk_flush']
pub fn native_printk_flush(seq u64, timeout u32) i32 { return vkr_log_flush(seq, timeout) }
@[export: 'vinix_linuxkpi_printk_bootstrap']
pub fn native_printk_bootstrap() i32 { return vkr_log_bootstrap() }
@[export: 'vinix_linuxkpi_printk_shutdown']
pub fn native_printk_shutdown() i32 { return vkr_log_shutdown() }
@[export: 'vinix_linuxkpi_printk_test_pause']
pub fn native_printk_pause(pause bool, timeout u32) i32 { return vkr_log_pause(pause, timeout) }
@[export: 'vinix_linuxkpi_printk_test_sink']
pub fn native_printk_sink(sink LogSinkABI, arg voidptr) i32 { return unsafe { vkr_log_sink(voidptr(sink), arg) } }
@[export: 'vinix_linuxkpi_printk_test_fail_create']
pub fn native_printk_fail(fail bool) { vkr_log_fail(fail) }
