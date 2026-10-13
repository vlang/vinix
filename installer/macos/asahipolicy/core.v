// SPDX-License-Identifier: GPL-2.0-or-later
module asahipolicy

import strconv

pub const minimum_allocation = i64(16_000_000_000)
pub const stub_bytes = i64(2_499_805_184)
pub const partition_alignment = i64(1_048_576)
pub const minimum_macos_free = i64(38_000_000_000)
pub const minimum_other_free = i64(1_000_000_000)

pub struct Failure {
pub:
	kind        string = 'RuntimeError'
	description string
}

pub fn (failure Failure) msg() string { return failure.description }

pub fn (failure Failure) code() int { return 1 }

pub struct Config {
pub:
	disk       string
	allocation i64
}

pub fn config(disk string, allocation string) !Config {
	if disk.len <= 4 || !disk.starts_with('disk') {
		return Failure{ kind: 'ValueError', description: 'Invalid target disk identifier' }
	}
	for ch in disk[4..].bytes() {
		if ch < `0` || ch > `9` {
			return Failure{ kind: 'ValueError', description: 'Invalid target disk identifier' }
		}
	}
	amount := strconv.common_parse_int(allocation.trim_space(), 10, 64, true, true) or { return Failure{ kind: 'ValueError', description: 'Invalid Vinix allocation' } }
	if amount < minimum_allocation {
		return Failure{ kind: 'ValueError', description: 'Vinix allocation must be at least 16 GB' }
	}
	return Config{ disk: disk, allocation: amount }
}

pub fn (selected Config) action(current string, system string, available []string, free_sizes []i64) !string {
	if current != selected.disk {
		if 'd' !in available {
			return Failure{ description: 'Selected disk ' + selected.disk + ' is not available' }
		}
		return 'd'
	}
	if current != system {
		if 'w' !in available {
			return Failure{ description: 'External disk ' + selected.disk + ' cannot be installed' }
		}
		return 'w'
	}
	if 'f' in available {
		for size in free_sizes { if size >= selected.allocation { return 'f' } }
	}
	if 'r' in available { return 'r' }
	return Failure{ description: 'No APFS container on ' + selected.disk + ' can safely provide the selected allocation' }
}

pub fn newest_version(count int) int { return count - 1 }

pub fn (selected Config) select_external(eligible []string) ! {
	if selected.disk !in eligible {
		return Failure{ description: selected.disk + ' is not an m1n1-bootable external USB disk' }
	}
}

pub fn resize_candidate(contains_booted_os []bool) !int {
	mut selected := -1
	for index, contains in contains_booted_os {
		if !contains { continue }
		if selected >= 0 {
			return Failure{ description: 'Could not unambiguously identify the booted macOS APFS container' }
		}
		selected = index
	}
	if selected < 0 {
		return Failure{ description: 'Could not unambiguously identify the booted macOS APFS container' }
	}
	return selected
}

pub fn free_margin(has_installed_os bool) i64 {
	return if has_installed_os { minimum_macos_free } else { minimum_other_free }
}

pub fn (selected Config) macos_size(total i64, minimum ?i64) !i64 {
	// Physical disk sizes and GUI allocations are bounded signed 64-bit values.
	if total < 0 || total < -9223372036854775807 + selected.allocation {
		return Failure{ description: 'Invalid APFS container size' }
	}
	remaining := total - selected.allocation
	if remaining > 9223372036854775807 - (partition_alignment - 1) {
		return Failure{ description: 'APFS alignment overflow' }
	}
	value := (remaining + partition_alignment - 1) & ~(partition_alignment - 1)
	if boundary := minimum {
		if value < boundary {
			return Failure{ description: 'Allocating the selected space would leave macOS below its safe minimum' }
		}
	}
	return value
}

pub fn signed_profile(names []string) ! {
	if names.len != 1 || names[0] != 'Vinix' {
		return Failure{ description: 'The signed Vinix installer profile is missing' }
	}
}

pub fn (selected Config) os_partition(free_size i64, minimum_size i64) !i64 {
	if selected.allocation < minimum_size {
		return Failure{ description: 'Vinix needs more space on this disk' }
	}
	if selected.allocation > free_size {
		return Failure{ description: 'Insufficient contiguous space is available' }
	}
	return selected.allocation - stub_bytes
}

pub fn completion(recovery bool) []string {
	return if recovery {
		['Vinix and m1n1 are installed.',
			'After restart, hold the power button to open startup options and select Vinix.']
	} else {
		['Vinix and m1n1 are installed.', 'The Mac must fully shut down before the first boot:',
			'  1. Press Enter below and wait at least 25 seconds.',
			'  2. Press and HOLD the power button until startup options appear.',
			'  3. Select Vinix (it may briefly appear as macOS Recovery).',
			'  4. Complete the one-time Finish Installation screen.']
	}
}
