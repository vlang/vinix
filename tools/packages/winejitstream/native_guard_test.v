// SPDX-License-Identifier: GPL-2.0-or-later
module winejitstream

import os
import time

fn native_test_limits() NativeLimits {
	return NativeLimits{
		timeout_ms:   1000
		file_bytes:   64
		total_bytes:  128
		log_bytes:    32
		serial_bytes: 48
	}
}

fn native_test_directory(name string) !string {
	path := os.real_path(os.temp_dir()) + '/wine-jit-native-' + name + '-' +
		os.getpid().str() + '-' + time.sys_mono_now().str()
	os.mkdir(path)!
	return path
}

fn native_test_refused(command []string, directory string, log_name string, limits NativeLimits) {
	native_guard(command, directory, log_name, limits) or { return }
	assert false, 'invalid native guard admission was accepted'
}

fn test_native_guard_rejects_invalid_bounds_before_accessing_state() {
	limits := native_test_limits()
	missing := '/nonexistent-wine-jit-native-state'
	for changed in [
		NativeLimits{ ...limits, timeout_ms: 0 },
		NativeLimits{ ...limits, timeout_ms: 300001 },
		NativeLimits{ ...limits, file_bytes: 0 },
		NativeLimits{ ...limits, file_bytes: 128 * 1024 * 1024 + 1 },
		NativeLimits{ ...limits, total_bytes: 63 },
		NativeLimits{ ...limits, total_bytes: 256 * 1024 * 1024 + 1 },
		NativeLimits{ ...limits, log_bytes: 0 },
		NativeLimits{ ...limits, log_bytes: 65 },
		NativeLimits{ ...limits, serial_bytes: 0 },
		NativeLimits{ ...limits, serial_bytes: 65 },
	] {
		native_guard(['/nonexistent-wine-jit-native-command'], missing, 'worker.log', changed) or {
			assert err.msg().contains('invalid native guard')
			continue
		}
		assert false, 'invalid limits reached process execution'
	}
	native_test_refused([]string{}, missing, 'worker.log', limits)
	native_test_refused(['relative-command'], missing, 'worker.log', limits)
	for log_name in ['', '../worker.log', '/worker.log', 'worker.txt'] {
		native_test_refused(['/nonexistent-wine-jit-native-command'], missing, log_name, limits)
	}
}

fn test_native_state_rejects_links_and_noncanonical_guard_directories() {
	directory := native_test_directory('links')!
	defer { os.rmdir_all(directory) or {} }
	os.mkdir(directory + '/real')!
	os.write_file(directory + '/real/retained', 'retain')!
	os.symlink(directory + '/real', directory + '/alias')!
	native_test_refused(['/nonexistent-wine-jit-native-command'], directory + '/alias',
		'worker.log', native_test_limits())
	mut refused := false
	native_state_bytes(directory) or {
		refused = true
		u64(0)
	}
	assert refused
	assert os.read_file(directory + '/real/retained')! == 'retain'
	assert !os.exists(directory + '/real/worker.log')
	os.rm(directory + '/alias')!
	os.symlink(directory + '/absent', directory + '/dangling')!
	refused = false
	native_state_bytes(directory) or {
		refused = true
		u64(0)
	}
	assert refused
}

fn test_native_guard_preserves_existing_log_and_refuses_oversized_state() {
	directory := native_test_directory('admission')!
	defer { os.rmdir_all(directory) or {} }
	os.write_file(directory + '/worker.log', 'retain')!
	native_test_refused(['/nonexistent-wine-jit-native-command'], directory, 'worker.log',
		native_test_limits())
	assert os.read_file(directory + '/worker.log')! == 'retain'
	os.rm(directory + '/worker.log')!
	os.write_file(directory + '/build.log', 'x'.repeat(32))!
	native_test_refused(['/nonexistent-wine-jit-native-command'], directory, 'worker.log',
		native_test_limits())
	assert !os.exists(directory + '/worker.log')
	assert os.read_file(directory + '/build.log')! == 'x'.repeat(32)
}

fn test_native_scan_classifies_file_log_serial_and_aggregate_thresholds() {
	directory := native_test_directory('thresholds')!
	defer { os.rmdir_all(directory) or {} }
	limits := native_test_limits()
	for name, cap in {
		'payload.bin': 64
		'build.log':   32
		'serial.log':  48
	} {
		path := directory + '/' + name
		os.write_file(path, 'x'.repeat(cap - 1))!
		mut below := NativeTree{}
		native_scan(directory, '', limits, mut below)!
		assert !below.limited
		assert below.bytes == u64(cap - 1)
		os.write_file(path, 'x'.repeat(cap))!
		mut at := NativeTree{}
		native_scan(directory, '', limits, mut at)!
		assert at.limited
		os.rm(path)!
	}
	os.mkdir(directory + '/nested')!
	for name in ['a', 'b', 'c'] {
		os.write_file(directory + '/nested/' + name, 'x'.repeat(50))!
	}
	mut aggregate := NativeTree{}
	native_scan(directory, '', limits, mut aggregate)!
	assert aggregate.limited
	assert aggregate.bytes == 150
	assert native_state_bytes(directory)! == 150
}
