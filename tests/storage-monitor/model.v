// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

struct MonitorModel {
mut:
	mode         int
	opens        int
	closes       int
	status_calls int
	health_calls int
	sleeps       int
	flushes      int
	prints       int
}

__global monitor_model MonitorModel

fn monitor_model_reset(mode int) {
	monitor_model = MonitorModel{
		mode: mode
	}
}

fn monitor_mock_open(_ &char, flags int) i32 {
	assert flags == C.O_RDONLY | C.O_CLOEXEC
	monitor_model.opens++
	if monitor_model.mode == 10 {
		unsafe {
			C.errno = C.EACCES
		}
		return -1
	}
	return 42
}

fn monitor_mock_close(fd i32) i32 {
	assert fd == 42
	monitor_model.closes++
	return 0
}

fn monitor_mock_ioctl(fd i32, request u64, output voidptr) i32 {
	assert fd == 42
	if request == 0x56560004 {
		monitor_model.status_calls++
		if monitor_model.mode == 7 {
			unsafe {
				C.errno = C.EIO
			}
			return -1
		}
		mut status := monitor_test_status()
		status.errors = 5
		status.reads = u64(monitor_model.sleeps + 1)
		status.read_bytes = u64(monitor_model.sleeps + 1) * 512
		if monitor_model.mode == 4 && monitor_model.sleeps > 0 { status.errors++ }
		if monitor_model.mode == 5 { status.flags = 2 }
		if monitor_model.mode == 6 && monitor_model.health_calls > 0 {
			status.flags = 2
			status.errors++
		}
		if monitor_model.mode == 8 && monitor_model.sleeps > 0 { status.disk_id = 92 }
		if monitor_model.mode == 9 { status.reserved = 1 }
		if monitor_model.mode == 11 && monitor_model.sleeps > 0 {
			status.reads = 0
			status.read_bytes = 0
		}
		if monitor_model.mode == 12 && monitor_model.health_calls > 0 { status.generation++ }
		unsafe {
			*(&Status(output)) = status
		}
		return 0
	}
	assert request == 0x56560005 // No write or management ioctl is allowed.
	monitor_model.health_calls++
	if monitor_model.mode == 3 {
		unsafe {
			C.errno = C.ENOTTY
		}
		return -1
	}
	if monitor_model.mode in [6, 13]! {
		unsafe {
			C.errno = C.EIO
		}
		return -1
	}
	mut health := Health{
		version:  1
		protocol: 2
		flags:    15
		disk_id:  91
	}
	if monitor_model.mode == 1 && monitor_model.health_calls == 1 {
		health.flags = 31
		health.data[0] = 0x80
	}
	if monitor_model.mode == 2 {
		health.protocol = 1
		health.flags = 1
	}
	if monitor_model.mode == 14 { health.disk_id = 92 }
	if monitor_model.mode == 15 { health.flags = 31 } // Warning flag disagrees with data.
	unsafe {
		*(&Health(output)) = health
	}
	return 0
}

fn monitor_mock_sleep(seconds u32) u32 {
	assert seconds == 1
	monitor_model.sleeps++
	if monitor_model.mode == 16 && monitor_model.sleeps == 1 { return 1 }
	return 0
}

fn monitor_mock_flush(_ voidptr) i32 {
	monitor_model.flushes++
	if monitor_model.mode == 17 {
		unsafe {
			C.errno = C.EIO
		}
		return -1
	}
	return 0
}

fn monitor_mock_printf(format &char, sample u64, disk u64, state &char, warnings u32,
	offline u64, query_error i32, errors u64, last_error u64, new_errors u64, read_bytes u64,
	write_bytes u64, read_delta u64, write_delta u64, baseline u32, counters_reset u32) i32 {
	monitor_model.prints++
	if monitor_model.mode == 18 {
		unsafe {
			C.errno = C.EIO
		}
		return -1
	}
	return C.printf(format, sample, disk, state, warnings, offline, query_error, errors,
		last_error, new_errors, read_bytes, write_bytes, read_delta, write_delta, baseline,
		counters_reset)
}
