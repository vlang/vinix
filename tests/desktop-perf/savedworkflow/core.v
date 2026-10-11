// SPDX-License-Identifier: GPL-2.0-or-later
module savedworkflow

import crypto.sha256
import hosttest
import json2
import os
import perfconsole
import perfreport
import sourcecommand
import time

pub const selected = ['ops', 'churn', 'cache', 'idle', 'apps', 'drag']

fn stamp() string { return time.utc().format_ss() + ' UTC' }

fn iso_stamp() string { return time.utc().format_rfc3339() }

fn sha(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	defer { unsafe { digest.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		perfconsole.checkpoint()!
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	return digest.sum([]).hex()
}

fn save(path string, row map[string]json2.Any) ! {
	os.write_file(path, json2.encode(row, prettify: true) + '\n')!
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[json2.Any](os.read_file(path)!)!.as_map()
}

fn native_inputs(root string) !map[string]json2.Any {
	mut result := map[string]json2.Any{}
	for directory in ['tests/desktop-perf/perfrunner', 'tests/desktop-perf/perfconsole',
		'tests/desktop-perf/perfreport', 'tools/qmpclient', 'tools/sourcecommand'] {
		for name in os.ls(root + '/' + directory)! {
			if name.ends_with('_test.v') || os.is_dir(root + '/' + directory + '/' + name) {
				continue
			}
			path := directory + '/' + name
			result[path] = sha(root + '/' + path)!
		}
	}
	return result
}

struct Log {
	pid_path string
mut:
	file os.File
}

fn log_chunk(chunk string, context voidptr) ! {
	mut log := unsafe { &Log(context) }
	log.file.write_string(chunk)!
	log.file.flush()
}

fn spawned(pid int, context voidptr) ! {
	log := unsafe { &Log(context) }
	os.write_file(log.pid_path, pid.str() + '\n')!
}

pub fn driver(root string, setup string, state_arg string, scenarios string, kernel_arg string) !int {
	state := hosttest.module_resolve(state_arg)!
	os.mkdir_all(state)!
	kernel := hosttest.module_resolve(kernel_arg)!
	desktop := root + '/build/useralloc-pipe/static-desktop-v6/vinix-desktop'
	directory := state + '/kernel/bin'
	os.mkdir_all(directory)!
	hosttest.module_copy_file_preserving_stat(kernel, directory + '/vinix')!
	mut env := os.environ()
	for key, value in {
		'VINIX_KERNEL_DIR':      os.dir(directory)
		'VINIX_AARCH64_SYSROOT': root + '/build/useralloc-pipe/static-desktop-v6/sysroot'
		'VINIX_QEMU_SMP':        '2'
		'USE_TCG':               '0'
	} {
		env[key] = value
	}
	argv := [root + '/tests/desktop-perf/run-saved', 'v6', setup, 'final=' + desktop,
		'--scenarios=' + scenarios, '--rounds', '1', '--initramfs',
		setup + '/initramfs-desktop-frozen.tar', '--settle', '5', '--seconds', '20', '--timeout',
		'1800', '--json', state + '/results.json', '--shots', state + '/shots']
	harness := root + '/tests/desktop-perf/run-saved.v'
	mut manifest := {
		'kernel_sha256':         json2.Any(sha(kernel)!)
		'desktop_sha256':        json2.Any(sha(desktop)!)
		'loader_sha256':         json2.Any(sha(root + '/third_party/useralloc-libc/build/useralloc/optimized-arm126-v6-final/lib/ld-musl-aarch64.so.1')!)
		'static_libc_sha256':    json2.Any(sha(root + '/third_party/useralloc-libc/build/useralloc/optimized-arm126-v6-final/usr/lib/libc.a')!)
		'initramfs_sha256':      json2.Any(sha(setup + '/initramfs-desktop-frozen.tar')!)
		'harness_sha256':        json2.Any(sha(harness)!)
		'harness_path':          json2.Any(harness)
		'native_inputs':         json2.Any(native_inputs(root)!)
		'measure_source_sha256': json2.Any(sha(setup + '/measure.c')!)
		'guest_init_sha256':     json2.Any(sha(setup + '/perf-init.sh')!)
		'command':               json2.Any(argv.map(json2.Any(it)))
		'environment':           json2.Any({
			'VINIX_KERNEL_DIR':      json2.Any(env['VINIX_KERNEL_DIR'])
			'VINIX_AARCH64_SYSROOT': json2.Any(env['VINIX_AARCH64_SYSROOT'])
			'VINIX_QEMU_SMP':        json2.Any(env['VINIX_QEMU_SMP'])
			'USE_TCG':               json2.Any(env['USE_TCG'])
		})
		'start_time_utc':        json2.Any(stamp())
		'timeout_seconds':       json2.Any(1800)
		'notes':                 json2.Any('Unmodified workload sources; native saved harness overlays final production loader/manifest. Existing full desktop image, frozen final isolated kernel and new static desktop with verified final libc.a.')
	}
	save(state + '/run.json', manifest)!
	mut log := &Log{ pid_path: state + '/runner.pid', file: os.create(state + '/driver.log')! }
	defer { log.file.close() }
	// The inner runner owns a separate QEMU session. Give its SIGTERM cleanup
	// enough time to retire that guest before the outer owner forces a reap.
	output := sourcecommand.capture_owned(argv, env, -1, 0x7fffffff, perfconsole.cancelled, log_chunk, spawned, log, 15) or {
		manifest['runner_exit_code'] = json2.Any(if perfconsole.cancelled() {
			perfconsole.interrupt_status()
		} else {
			1
		})
		manifest['end_time_utc'] = json2.Any(stamp())
		manifest['runner_error'] = json2.Any(err.msg())
		save(state + '/run.json', manifest)!
		return err
	}
	manifest['runner_exit_code'] = json2.Any(output.status)
	manifest['end_time_utc'] = json2.Any(stamp())
	if serial := serial_path(output.stdout) {
		hosttest.module_copy_file_preserving_stat(serial, state + '/serial.log')!
		manifest['serial_sha256'] = json2.Any(sha(state + '/serial.log')!)
		manifest['guest_temp_state'] = json2.Any(os.dir(serial))
	} else {
		manifest['serial_capture_error'] = json2.Any('Guest transcript path was not reported; inspect driver.log.')
	}
	save(state + '/run.json', manifest)!
	println(json2.encode(manifest, prettify: true))
	return output.status
}

pub fn serial_path(log string) ?string {
	for line in log.split_into_lines() {
		if at := line.index('==> Serial log: ') { return line[at + 16..].trim_space() }
	}
	return none
}

pub fn validate(root string, setup string, state string) !map[string]json2.Any {
	verdict := perfreport.inspect_policy(os.read_bytes(state + '/serial.log')!, ['final'], selected, 1, false, perfreport.Value(perfreport.Number{'0'}), true)
	if verdict.errors.len != 0 { return error(verdict.errors.join('\n')) }
	if verdict.rows.len != 43 { return error('expected 43 completed measurements') }
	actual := json2.decode[[]perfreport.Row](os.read_file(state + '/results.json')!)!
	if actual != verdict.rows {
		return error('saved results differ from independent transcript inspection')
	}
	run := object(state + '/run.json')!
	if run['runner_exit_code']!.int() != 0 {
		return error('saved runner did not exit successfully')
	}
	harness := if 'harness_path' in run { run['harness_path']!.str() } else { setup + '/run.py' }
	for field, path in {
		'kernel_sha256':  root + '/build/useralloc-kernel-speed-v5/aarch64/vinix-aarch64'
		'desktop_sha256': root + '/build/useralloc-pipe/static-desktop-v6/vinix-desktop'
		'serial_sha256':  state + '/serial.log'
		'harness_sha256': harness
	} {
		if run[field]!.str() != sha(path)! { return error('saved input hash mismatch: ' + field) }
	}
	if 'native_inputs' in run {
		for path, digest in run['native_inputs']!.as_map() {
			if digest.str() != sha(root + '/' + path)! {
				return error('native input hash mismatch: ' + path)
			}
		}
	}
	result := {
		'status':           json2.Any('PASS')
		'checked_rows':     json2.Any(verdict.rows.len)
		'scenarios':        json2.Any(selected.map(json2.Any(it)))
		'runner_exit_code': json2.Any(0)
		'kernel_sha256':    run['kernel_sha256']!
		'desktop_sha256':   run['desktop_sha256']!
		'serial_sha256':    run['serial_sha256']!
		'harness_sha256':   run['harness_sha256']!
		'notes':            json2.Any('Complete functional/memory scenarios with unchanged workloads. Existing ops/churn growth remains visible; this does not claim flat kernel memory.')
	}
	save(state + '/validation.json', result)!
	return result
}

fn checkpoint(path string, start string, phase string, fields map[string]json2.Any) ! {
	mut row := fields.clone()
	row['phase'] = json2.Any(phase)
	row['started_utc'] = json2.Any(start)
	row['updated_utc'] = json2.Any(iso_stamp())
	save(path, row)!
}

pub fn pipeline(root string, setup string) ! {
	state := root + '/build/useralloc-desktop-perf-v6'
	start := iso_stamp()
	file := setup + '/pipeline-checkpoint.json'
	checkpoint(file, start, 'waiting-static-desktop', {})!
	desktop := root + '/build/useralloc-pipe/static-desktop-v6'
	mut ready := false
	for _ in 0 .. 600 {
		perfconsole.checkpoint()!
		if os.exists(desktop + '/driver.exit.json') {
			ready = true
			break
		}
		until := time.sys_mono_now() + u64(2 * time.second)
		for time.sys_mono_now() < until {
			perfconsole.checkpoint()!
			time.sleep(50 * time.millisecond)
		}
	}
	if !ready { return error('Static desktop wait exceeded20minutes') }
	if object(desktop + '/driver.exit.json')!['exit_code']!.int() != 0 || object(desktop + '/build.json')!['build_exit_code']!.int() != 0 {
		return error('static desktop build did not pass')
	}
	checkpoint(file, start, 'perf-running', {})!
	command := [root + '/tests/desktop-perf/run-saved-driver', 'run-driver', setup, state,
		'ops,churn,cache,idle,apps,drag',
		root + '/build/useralloc-kernel-speed-v5/aarch64/vinix-aarch64']
	status := driver(root, root + '/build/useralloc-pipe/perf-v6-preparation', state, 'ops,churn,cache,idle,apps,drag', root + '/build/useralloc-kernel-speed-v5/aarch64/vinix-aarch64')!
	save(setup + '/driver.exit.json', {
		'exit_code':    json2.Any(status)
		'started_utc':  json2.Any(start)
		'finished_utc': json2.Any(iso_stamp())
		'argv':         json2.Any(command.map(json2.Any(it)))
	})!
	if status != 0 { return error('performance driver failed') }
	checkpoint(file, start, 'independent-validation', {})!
	validation := validate(root, setup, state)!
	checkpoint(file, start, 'complete', {
		'validation': json2.Any(validation)
	})!
}

pub fn cli(argv []string, root string) int {
	if argv == ['--help'] {
		println('run-saved-driver pipeline SETUP | run-driver SETUP STATE SCENARIOS KERNEL | validate-completed SETUP STATE')
		return 0
	}
	guard := perfconsole.own_commands()
	defer { guard.close() }
	status := dispatch(argv, root) or {
		eprintln(err)
		return if perfconsole.cancelled() { perfconsole.interrupt_status() } else { 1 }
	}
	return status
}

fn dispatch(argv []string, root string) !int {
	if argv.len == 2 && argv[0] == 'pipeline' {
		pipeline(root, argv[1])!
		return 0
	}
	if argv.len == 5 && argv[0] == 'run-driver' {
		return driver(root, argv[1], argv[2], argv[3], argv[4])!
	}
	if argv.len == 3 && argv[0] == 'validate-completed' {
		println(json2.encode(validate(root, argv[1], argv[2])!, prettify: true))
		return 0
	}
	return error('invalid saved driver arguments')
}
