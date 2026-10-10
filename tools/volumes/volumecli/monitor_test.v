// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn monitor_test_status() Status {
	return Status{
		version: 1
		bytes:   8192
		sector:  512
		disk_id: 91
		slot:    u64(-1)
	}
}

fn test_monitor_validates_geometry_abi_and_stable_device_identity() {
	mut status := monitor_test_status()
	assert monitor_status_valid(&status)
	for flags in [u64(0), 1, 2, 4, 8, 16, 32, 63]! {
		status.flags = flags
		assert monitor_status_valid(&status)
	}
	status.flags = 64
	assert !monitor_status_valid(&status)
	status = monitor_test_status()
	status.version = 2
	assert !monitor_status_valid(&status)
	status.version = 1
	status.reserved = 1
	assert !monitor_status_valid(&status)
	status.reserved = 0
	status.disk_id = 0
	assert !monitor_status_valid(&status)
	status = monitor_test_status()
	for sector in [u64(0), 256, 513, 8192]! {
		status.sector = sector
		assert !monitor_status_valid(&status)
	}
	status = monitor_test_status()
	status.bytes = 8193
	assert !monitor_status_valid(&status)
	status.bytes = 8192
	status.start = u64(-1) - 4096
	assert !monitor_status_valid(&status)
	status = monitor_test_status()
	mut other := status
	other.bytes += 4096
	other.read_bytes = 512
	other.flags = 2
	assert monitor_same_device(&status, &other) // Grow and offline retain identity.
	other.disk_id++
	assert !monitor_same_device(&status, &other)
	other = status
	other.start = 512
	assert !monitor_same_device(&status, &other)
	other = status
	other.slot = 3
	assert !monitor_same_device(&status, &other)
	other = status
	other.generation = 1
	assert !monitor_same_device(&status, &other)
}

fn test_monitor_delta_baseline_completed_io_and_reset_without_underflow() {
	before := Status{
		reads:       10
		writes:      20
		read_bytes:  4096
		write_bytes: 8192
		flushes:     4
		errors:      7
	}
	mut after := before
	after.reads += 2
	after.writes++
	after.read_bytes += 1024
	after.write_bytes += 512
	after.flushes++
	after.errors += 3
	first := monitor_delta(&before, &after, true)
	assert first.read_bytes == 0 && first.write_bytes == 0 && first.errors == 0 && !first.reset
	next := monitor_delta(&before, &after, false)
	assert next.read_bytes == 1024 && next.write_bytes == 512 && next.errors == 3 && !next.reset
	for field in 0 .. 6 {
		after = before
		match field {
			0 { after.reads-- }
			1 { after.writes-- }
			2 { after.read_bytes-- }
			3 { after.write_bytes-- }
			4 { after.flushes-- }
			else { after.errors-- }
		}

		reset := monitor_delta(&before, &after, false)
		assert reset.reset && reset.read_bytes == 0 && reset.write_bytes == 0 && reset.errors == 0
	}
	after = before
	after.read_bytes = u64(-1)
	after.write_bytes = u64(-1)
	after.errors = u64(-1)
	large := monitor_delta(&before, &after, false)
	assert large.read_bytes == u64(-1) - 4096 && large.write_bytes == u64(-1) - 8192
	assert large.errors == u64(-1) - 7 && !large.reset
}

fn test_monitor_session_retains_failure_and_warning_after_recovery() {
	for code in [i32(0), 1, 3, 4]! {
		assert monitor_exit(code, 0) == code
		assert monitor_exit(0, code) == code
		assert monitor_exit(code, 1) == 1 && monitor_exit(1, code) == 1
	}
	assert monitor_exit(4, 3) == 3 && monitor_exit(3, 4) == 3
	assert monitor_exit(monitor_exit(0, 3), 0) == 3
	assert monitor_exit(monitor_exit(3, 1), 0) == 1
}
