// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

@[c_extern]
__global C.stdout voidptr
fn C.fflush(voidptr) i32
fn C.sleep(u32) u32

struct MonitorDelta {
	read_bytes  u64
	write_bytes u64
	errors      u64
	reset       bool
}

struct MonitorObservation {
	code         i32
	query_error  i32
	health_valid bool
}

fn monitor_status_valid(status &Status) bool {
	return status.version == 1 && status.reserved == 0 && status.disk_id != 0
		&& status.flags & ~u64(63) == 0 && status.sector >= 512 && status.sector <= 4096
		&& status.sector & (status.sector - 1) == 0 && status.bytes % status.sector == 0
		&& status.start <= u64(-1) - status.bytes
}

// The descriptor stays open for the entire session. Do not silently combine
// counters or health from a replacement device or a reused mapper slot.
fn monitor_same_device(left &Status, right &Status) bool {
	return left.disk_id == right.disk_id && left.start == right.start && left.slot == right.slot
		&& left.generation == right.generation
}

fn monitor_delta(previous &Status, current &Status, baseline bool) MonitorDelta {
	if baseline { return MonitorDelta{} }
	if current.reads < previous.reads || current.writes < previous.writes
		|| current.read_bytes < previous.read_bytes || current.write_bytes < previous.write_bytes
		|| current.flushes < previous.flushes || current.errors < previous.errors {
		return MonitorDelta{
			reset: true
		}
	}
	return MonitorDelta{
		read_bytes:  current.read_bytes - previous.read_bytes
		write_bytes: current.write_bytes - previous.write_bytes
		errors:      current.errors - previous.errors
	}
}

// Retain the most serious observation even if a later sample recovers. An
// operational failure outranks a health warning, which outranks unavailable
// health. Existing historical errors alone do not fail the first sample.
fn monitor_exit(current i32, observation i32) i32 {
	if current == 1 || observation == 1 { return 1 }
	if current == 3 || observation == 3 { return 3 }
	if current == 4 || observation == 4 { return 4 }
	return 0
}

fn monitor_status(fd i32, mut status Status) bool {
	if C.ioctl(fd, u64(0x56560004), unsafe { &status }) != 0 {
		C.perror(c'vinix-volume: monitor status')
		return false
	}
	if !monitor_status_valid(unsafe { &status }) {
		plan_error(c'invalid monitor status report')
		return false
	}
	return true
}

// Health and status are separate snapshots. Refresh status after the health
// query so a failed query's error/offline transition is visible immediately.
// Offline devices are observed without submitting another health command.
fn monitor_sample(fd i32, previous &Status, baseline bool, mut status Status,
	mut health Health) MonitorObservation {
	if !monitor_status(fd, mut status) { return MonitorObservation{
			code: -1
		} }
	if !baseline && !monitor_same_device(previous, unsafe { &status }) {
		plan_error(c'monitored device identity changed')
		return MonitorObservation{
			code: -1
		}
	}
	if status.flags & 2 != 0 { return MonitorObservation{
			code: 1
		} }
	before := status
	mut result := i32(0)
	mut query_error := i32(0)
	mut queried := false
	if C.ioctl(fd, u64(0x56560005), unsafe { &health }) != 0 {
		query_error = unsafe { C.errno }
		result = if query_error == C.ENOTTY || query_error == C.EOPNOTSUPP { i32(4) } else { i32(1) }
	} else if !health_valid(unsafe { &health }) || health.disk_id != status.disk_id {
		plan_error(c'invalid monitor health report')
		return MonitorObservation{
			code: -1
		}
	} else {
		result = health_exit(unsafe { &health })
		queried = true
	}
	if !monitor_status(fd, mut status) { return MonitorObservation{
			code: -1
		} }
	if !monitor_same_device(unsafe { &before }, unsafe { &status }) {
		plan_error(c'monitored device identity changed during health query')
		return MonitorObservation{
			code: -1
		}
	}
	return MonitorObservation{
		code:         result
		query_error:  query_error
		health_valid: queried
	}
}

fn monitor_show(sample u64, status &Status, health &Health, query_error i32,
	observation i32, delta MonitorDelta, baseline bool, media_errors bool) bool {
	state := if status.flags & 2 != 0 {
		&char(c'offline')
	} else if observation == 1 {
		&char(c'query-failed')
	} else if media_errors {
		&char(c'media-errors')
	} else if observation == 3 {
		&char(c'warning')
	} else if observation == 4 {
		&char(c'unavailable')
	} else {
		&char(c'healthy')
	}
	warnings := if observation == 3 {
		if health.protocol == 2 { u32(health.data[0]) } else { u32(1) }
	} else {
		u32(0)
	}
	return C.printf(c'sample=%lu disk=%lu health=%s warnings=0x%02x offline=%lu query_errno=%d errors=%lu last_error=%lu new_errors=%lu read_bytes=%lu write_bytes=%lu read_delta=%lu write_delta=%lu baseline=%u counters_reset=%u',
		sample, status.disk_id, state, warnings, (status.flags >> 1) & 1, query_error,
		status.errors, status.last_error, delta.errors, status.read_bytes, status.write_bytes,
		delta.read_bytes, delta.write_bytes, u32(baseline), u32(delta.reset)) >= 0
}

fn monitor_device(path &char, interval u32, samples u64) i32 {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC)
	if fd < 0 {
		C.perror(c'vinix-volume: open monitor device')
		return 1
	}
	defer { C.close(fd) }
	mut previous := Status{}
	mut baseline := true
	mut result := i32(0)
	mut sample := u64(1)
	// V can promote a large mut argument to the heap. Reuse one caller-stack
	// report for all synchronous queries; alloca must stay outside the loop.
	mut health := unsafe { &Health(C.alloca(sizeof(Health))) }
	mut health_counters := unsafe { &MonitorHealthCounters(C.alloca(sizeof(MonitorHealthCounters))) }
	unsafe {
		*health_counters = MonitorHealthCounters{}
	}
	for {
		mut status := Status{}
		unsafe {
			*health = Health{}
		}
		observation := monitor_sample(fd, unsafe { &previous }, baseline, mut status, mut health)
		if observation.code < 0 { return 1 }
		delta := monitor_delta(unsafe { &previous }, unsafe { &status }, baseline)
		health_delta := monitor_health_delta(mut health_counters, health, observation.health_valid)
		if !monitor_show(sample, unsafe { &status }, health, observation.query_error, observation.code, delta, baseline, health_delta.media_errors)
			|| !monitor_health_show(health, unsafe { &health_delta }) || C.fflush(C.stdout) != 0 {
			C.perror(c'vinix-volume: monitor output')
			return 1
		}
		result = monitor_exit(result, observation.code)
		if status.flags & 2 != 0 || delta.errors != 0 || health_delta.media_errors { result = 1 }
		if samples != 0 && sample == samples { return result }
		previous = status
		baseline = false
		if sample != u64(-1) { sample++ }
		mut remaining := interval
		for remaining != 0 {
			remaining = C.sleep(remaining)
		}
	}
	return result
}
