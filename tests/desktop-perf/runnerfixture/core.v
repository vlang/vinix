// SPDX-License-Identifier: GPL-2.0-or-later
module runnerfixture

import crypto.sha256
import encoding.binary as endian
import json2
import net.unix
import os
import perfconsole
import perfreport
import perfrunner
import sourcecommand
import savedworkflow
import time

#include <fcntl.h>
#include <unistd.h>

fn C.raise(i32) i32

pub fn case_lines(scenario string, historical bool) []string {
	label := 'variant=new scenario=${scenario} round=1'
	mut lines := []string{}
	match scenario {
		'ops' {
			for op in ['stat', 'pipe', 'socketpair', 'inet_socket', 'eventfd', 'epoll', 'timerfd',
				'poll', 'proc_read', 'proc_list', 'readdir', 'dup', 'mmap', 'thread', 'signal',
				'fault', 'fork', 'memfd'] {
				if !historical || op != 'fault' {
					lines << 'PERF-OPS ${label} op=${op} dir=/tmp count=200 bytes_per_op=0'
				}
			}
			for directory in ['/tmp', '/root'] {
				for op in ['file', 'rename', 'unlink_open', 'rename_over', 'hardlink', 'mkdir',
					'symlink', 'unix_connect', 'unix_datagram'] {
					lines << 'PERF-OPS ${label} op=${op} dir=${directory} count=200 bytes_per_op=0'
				}
			}
		}
		'churn' {
			for program in ['/bin/true', '/bin/sleep 0', '/usr/bin/curl --version',
				'/bin/busybox awk BEGIN{}'] {
				lines << 'PERF-CHURN ${label} program="${program}" runs=300 retained_kb=0 per_run_bytes=0'
			}
		}
		'cache' { lines << 'PERF-CACHE ${label} written_mb=32 used_mb=33 cached_kb=32768 slab_kb=1024' }
		'wakeups' {
			for via in ['nanosleep', 'poll'] {
				lines << 'PERF-WAKEUPS ${label} via=${via} interval_ms=16 wakeups=100 per_second=62.5 cpu=0.10 us_per_wakeup=16'
			}
		}
		else {
			lines << 'PERF-RESULT ${label} seconds=1.0 processes=${if scenario == 'workflows' {
				5
			} else {
				1
			}} desktop_cpu=1.0 apps_cpu=0.0 total_cpu=1.0 desktop_mb=2.0 apps_mb=0.0 total_mb=2.0 system_used_mb=20.0 physical_mb=2.0'
		}
	}
	return lines
}

fn data() []u8 {
	key := 'computer'.bytes()
	definition := 'An electronic machine.'.bytes()
	mut result := 'VNXDICT1'.bytes()
	for value in [u32(1), u32(key.len), u32(definition.len), 0, 0, u32(key.len), 0,
		u32(definition.len)] {
		mut word := []u8{len: 4}
		endian.little_endian_put_u32(mut word, value)
		result << word
	}
	result << key
	result << definition
	return result
}

fn dictionary(directory string) ![]u8 {
	os.mkdir_all(directory)!
	payload := data()
	os.write_file_array(directory + '/dictionary.vnd', payload)!
	os.write_file(directory + '/LICENSE.WordNet', 'Local test fixture license\n')!
	return payload
}

fn fd_count() int {
	mut count := 0
	for fd in 0 .. 1024 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn done(line string, _ voidptr) !bool { return line.trim_space() == perfreport.done }

struct Recorder {
mut:
	commands [][]string
}

fn saved_cases(work string) ! {
	root := work + '/saved-root'
	setup := root + '/build/useralloc-pipe/perf-v6-preparation'
	state := root + '/build/useralloc-desktop-perf-v6'
	kernel := root + '/build/useralloc-kernel-speed-v5/aarch64/vinix-aarch64'
	for path in [kernel, root + '/build/useralloc-pipe/static-desktop-v6/vinix-desktop',
		root + '/third_party/useralloc-libc/build/useralloc/optimized-arm126-v6-final/lib/ld-musl-aarch64.so.1',
		root + '/third_party/useralloc-libc/build/useralloc/optimized-arm126-v6-final/usr/lib/libc.a',
		setup + '/initramfs-desktop-frozen.tar', setup + '/measure.c', setup + '/perf-init.sh',
		root + '/tests/desktop-perf/run-saved.v'] {
		os.mkdir_all(os.dir(path))!
		os.write_file(path, 'immutable fixture input\n')!
	}
	for directory in ['tests/desktop-perf/perfrunner', 'tests/desktop-perf/perfconsole',
		'tests/desktop-perf/perfreport', 'tools/qmpclient', 'tools/sourcecommand'] {
		os.mkdir_all(root + '/' + directory)!
		os.write_file(root + '/' + directory + '/core.v', 'module fixture\n')!
	}
	os.cp(os.executable(), root + '/tests/desktop-perf/run-saved')!
	os.chmod(root + '/tests/desktop-perf/run-saved', 0o755)!
	image := []u8{len: 1024 * 1024 + 31, init: u8(index % 251)}
	os.write_file_array(setup + '/initramfs-desktop-frozen.tar', image)!
	os.write_file(setup + '/measure.c', '')!
	assert savedworkflow.driver(root, setup, state, 'ops,churn,cache,idle,apps,drag', kernel)! == 0
	manifest := json2.decode[json2.Any](os.read_file(state + '/run.json')!)!.as_map()
	assert manifest['initramfs_sha256']!.str() == sha256.sum(image).hex()
	assert manifest['measure_source_sha256']!.str() == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
	assert os.read_file(state + '/runner.pid')!.trim_space().int() > 0
	assert savedworkflow.validate(root, setup, state)!['checked_rows']!.int() == 43
	original := os.read_file(state + '/results.json')!
	os.write_file(state + '/results.json', '[]\n')!
	if _ := savedworkflow.validate(root, setup, state) { return error('tampered results accepted') }
	os.write_file(state + '/results.json', original)!
	os.write_file(kernel, 'modified kernel')!
	if _ := savedworkflow.validate(root, setup, state) { return error('tampered kernel accepted') }
	os.write_file(kernel, 'immutable fixture input\n')!
	os.write_file(root + '/tools/sourcecommand/core.v', 'modified native owner')!
	if _ := savedworkflow.validate(root, setup, state) {
		return error('tampered native closure accepted')
	}
	assert (savedworkflow.serial_path('prefix ==> Serial log: /tmp/native.log\r\n') or { '' }) == '/tmp/native.log'
	println('PASS saved driver PID/log ownership, 43-row validation and input/closure tamper rejection')
}

fn prepare_cases(work string) ! {
	root := work + '/root'
	sysroot := root + '/sysroot'
	llvm := root + '/llvm'
	for version in ['10', '2'] {
		os.mkdir_all(sysroot + '/usr/lib/gcc/aarch64-alpine-linux-musl/' + version)!
	}
	os.mkdir_all(llvm)!
	os.write_file(llvm + '/clang', 'fixture compiler')!
	old_llvm := os.getenv_opt('LLVM_BIN')
	old_sysroot := os.getenv_opt('VINIX_AARCH64_SYSROOT')
	os.setenv('LLVM_BIN', llvm, true)
	os.setenv('VINIX_AARCH64_SYSROOT', sysroot, true)
	defer {
		if value := old_llvm { os.setenv('LLVM_BIN', value, true) } else { os.unsetenv('LLVM_BIN') }
		if value := old_sysroot {
			os.setenv('VINIX_AARCH64_SYSROOT', value, true)
		} else {
			os.unsetenv('VINIX_AARCH64_SYSROOT')
		}
	}
	os.mkdir_all(root + '/scripts')!
	os.cp(os.executable(), root + '/scripts/run-aarch64.sh')!
	os.chmod(root + '/scripts/run-aarch64.sh', 0o755)!
	os.write_file(root + '/desktop', 'fixture binary')!
	dictionary(root + '/dictionary')!
	plan := perfrunner.parse(['new=' + root + '/desktop', '--scenarios=workflows',
		'--dictionary-data=' + root + '/dictionary', '--rounds=1', '--seconds=1', '--settle=0',
		'--timeout=10', '--json=' + work + '/prepared.json', '--initramfs=' + root + '/image.tar'], root, root, '')!
	mut recorder := &Recorder{}
	execute := fn [mut recorder] (argv []string) ! { recorder.commands << argv.clone() }
	os.mkdir(work + '/prepared')!
	assert perfrunner.run_prepared(plan, work + '/prepared', execute)! == 0
	assert !os.exists(work + '/prepared/vm')
	assert os.exists(work + '/prepared/serial.log') && os.exists(work + '/prepared.json')
	assert recorder.commands.len == 3
	gcc := sysroot + '/usr/lib/gcc/aarch64-alpine-linux-musl/2'
	lib := sysroot + '/usr/lib'
	assert recorder.commands[0] == [llvm + '/clang', '--target=aarch64-linux-musl', '-static',
		'-nostdinc', '-nostdlib', '-isystem', gcc + '/include', '-isystem', sysroot + '/usr/include',
		'-O2', '-Wall', lib + '/crt1.o', lib + '/crti.o', gcc + '/crtbeginT.o', root + '/measure.c',
		'-L' + lib, '-L' + gcc, '-lc', '-lgcc', gcc + '/crtend.o', lib + '/crtn.o', '-fuse-ld=lld',
		'-B' + llvm, '-o', work + '/prepared/vm/overlay/opt/vinix-perf/measure']
	assert recorder.commands[1][0] == root + '/tools/prune-build-artifacts' && recorder.commands[2][0] == root + '/tools/build-qemu-module-iso'
	for suffix in ['v4-final', 'v3', 'v5-final', 'v6-final'] {
		argv := perfrunner.measure_command(root, 'source.c', 'measure', root + '/libc-' + suffix, os.environ())!
		assert argv[15] == '-L' + root + '/libc-' + suffix + '/usr/lib'
		assert argv.len == recorder.commands[0].len + 1
	}
	for interrupted in [false, true] {
		os.mkdir(work + '/failed-' + interrupted.str())!
		failed := fn [interrupted] (_ []string) ! {
			if interrupted {
				C.raise(C.SIGTERM)
				perfconsole.checkpoint()!
			}
			return error('compiler failed')
		}
		if _ := perfrunner.run_prepared(plan, work + '/failed-' + interrupted.str(), failed) {
			return error('failed setup accepted')
		}
		assert !os.exists(work + '/failed-' + interrupted.str() + '/vm')
		if interrupted {
			assert perfconsole.interrupt_status() == 143
			guard := perfconsole.own_commands()
			guard.close()
		}
	}
	println('PASS unchanged compiler recipes, local workflow assets before launch and setup/signal cleanup')
}

fn fixture_plan(work string, scenario string, historical bool) !perfrunner.Plan {
	binary := work + '/desktop'
	os.write_file(binary, 'fixture')!
	mut args := ['new=' + binary, '--rounds=1', '--scenarios=' + scenario,
		'--json=' + work + '/results.json', '--timeout=1']
	if scenario == 'workflows' {
		dictionary(work + '/dictionary')!
		args << '--dictionary-data=' + work + '/dictionary'
	}
	return perfrunner.parse(args, work, work, if historical { 'historical-libc' } else { '' })!
}

fn fixture_run(work string, scenario string, mode string, historical bool) !int {
	plan := fixture_plan(work, scenario, historical)!
	launch := perfrunner.Launch{[os.executable(), '--child', mode, scenario,
		if historical { 'historical' } else { 'current' }], os.environ(), work + '/qmp.sock'}
	return perfrunner.drive(plan, launch, work, 0.2, false)!
}

fn json_rows(work string) ![]perfreport.Row {
	return json2.decode[[]perfreport.Row](os.read_file(work + '/results.json')!)!
}

struct Pending {
mut:
	text string
}

fn checked_qmp(mut conn unix.StreamConn, mut pending Pending) !map[string]json2.Any {
	for !pending.text.contains('\n') {
		mut buffer := []u8{len: 4096}
		count := conn.read(mut buffer)!
		if count == 0 { return error('QMP EOF') }
		pending.text += buffer[..count].bytestr()
	}
	line := pending.text.all_before('\n')
	pending.text = pending.text.all_after('\n')
	return json2.decode[json2.Any](line)!.as_map()
}

pub fn child(argv []string) ! {
	mode, scenario := argv[0], argv[1]
	historical := argv.len > 2 && argv[2] == 'historical'
	if mode == 'partial' {
		println(case_lines('ops', false)[..2].join('\n'))
		for { time.sleep(100 * time.millisecond) }
	}
	if mode == 'hold' {
		println('guest holds console')
		for { time.sleep(100 * time.millisecond) }
	}
	if mode == 'qmp' {
		path := os.getenv('PERF_FIXTURE_SOCKET')
		mut listener := unix.listen_stream(path)!
		defer { listener.close() or {} }
		println('PERF-SHOT variant=new scenario=cache round=1')
		mut conn := listener.accept()!
		defer { conn.close() or {} }
		conn.write_string('discard this raw greeting\n')!
		mut pending := Pending{}
		cap := checked_qmp(mut conn, mut pending)!
		assert cap['execute']!.str() == 'qmp_capabilities' && 'arguments' !in cap
		conn.write_string('{"event":"RESET"}\n{"return":{}}\n')!
		request := checked_qmp(mut conn, mut pending)!
		assert request['execute']!.str() == 'screendump'
		// QMP cannot reply until all this serial output is drained. A callback on
		// the serial-reading thread would deadlock on the PTY's much smaller buffer.
		for _ in 0 .. 128 { println('serial-progress-'.repeat(512)) }
		filename := request['arguments']!.as_map()['filename']!.str()
		os.write_file(filename, 'P6\n1 1\n255\nabc')!
		conn.write_string('{"error":{"class":"GenericError","desc":"saved policy accepts error replies"}}\n')!
	}
	if mode == 'pointer' {
		mut listener := unix.listen_stream(os.getenv('PERF_FIXTURE_SOCKET'))!
		defer { listener.close() or {} }
		println('PERF-DRIVE ${scenario} 1')
		mut conn := listener.accept()!
		defer { conn.close() or {} }
		conn.write_string('{}\n')!
		mut pending := Pending{}
		cap := checked_qmp(mut conn, mut pending)!
		assert cap['execute']!.str() == 'qmp_capabilities'
		conn.write_string('{"return":{}}\n')!
		mut moves := 0
		mut down := false
		mut released := false
		for {
			request := checked_qmp(mut conn, mut pending)!
			assert request['execute']!.str() == 'input-send-event'
			events := request['arguments']!.as_map()['events']!.as_array()
			first := events[0].as_map()
			if first['type']!.str() == 'abs' {
				assert events.len == 2
				moves++
				if scenario == 'drag' && moves == 1 { assert first['data']!.as_map()['value']!.int() == 12255 }
			} else {
				state := first['data']!.as_map()
				assert state['button']!.str() == 'left'
				if state['down']!.bool() { down = true } else { released = true }
			}
			conn.write_string('{"event":"INPUT"}\n{"return":{}}\n')!
			if (scenario == 'pointer' && moves >= 30) || (scenario == 'drag' && released) { break }
		}
		if scenario == 'drag' { assert down && released && moves > 1 }
	}
	if mode == 'workflow' {
		assert os.read_bytes(os.getenv('VINIX_QEMU_OVERLAY') + '/usr/share/vinix/dictionary/dictionary.vnd')! == data()
		assert os.read_file(os.getenv('VINIX_QEMU_OVERLAY') + '/usr/share/vinix/dictionary/LICENSE.WordNet')! == 'Local test fixture license\n'
	}
	println(case_lines(scenario, historical).join('\n'))
	println(perfreport.done)
	if mode == 'late' {
		time.sleep(50 * time.millisecond)
		println('KERNEL PANIC: late')
	}
}

pub fn run() ! {
	guard := perfconsole.own_commands()
	defer { guard.close() }
	work := sourcecommand.temporary('vinix-perf-fixture')!
	defer { os.rmdir_all(work) or {} }
	prepare_cases(work)!
	saved_cases(work)!
	assert fixture_run(work, 'ops', 'complete', false)! == 0
	assert json_rows(work)!.len == 36 && os.read_file(work + '/serial.log')!.contains(perfreport.done)
	assert fixture_run(work, 'ops', 'partial', false)! == 1
	assert json_rows(work)!.len == 2
	assert fixture_run(work, 'ops', 'late', false)! == 1
	assert json_rows(work)!.len == 36 && os.read_file(work + '/serial.log')!.contains('KERNEL PANIC')
	plan := fixture_plan(work, 'ops', false)!
	closed := perfconsole.Output{ data: ([...case_lines('ops', false), perfreport.done].join('\n')).bytes(), status: 0, drained: false }
	assert perfrunner.finish_capture(plan, work, closed)! == 1
	println('PASS DONE at EOF, partial timeout JSON, final panic and unfinished-reader verdicts')
	payload := dictionary(work + '/assets')!
	assert perfrunner.dictionary_assets(work + '/assets')!.map(os.file_name(it)) == [
		'dictionary.vnd',
		'LICENSE.WordNet',
	]
	for damaged in ['magic', 'count', 'reserved', 'keys', 'definitions', 'trailing'] {
		mut bytes := payload.clone()
		match damaged {
			'magic' { bytes[0] = 0 }
			'trailing' { bytes << 'unexpected'.bytes() }
			else {
				at := match damaged {
					'count' { 8 }
					'reserved' { 20 }
					'keys' { 12 }
					else { 16 }
				}
				mut field := unsafe { bytes[at..at + 4] }
				endian.little_endian_put_u32(mut field, if damaged == 'reserved' {
					1
				} else if damaged == 'keys' {
					129
				} else {
					0
				})
			}
		}
		os.write_file_array(work + '/assets/dictionary.vnd', bytes)!
		if _ := perfrunner.dictionary_assets(work + '/assets') {
			return error('damaged dictionary accepted: ' + damaged)
		}
	}
	for item in ['dictionary.vnd', 'LICENSE.WordNet'] {
		dictionary(work + '/assets')!
		mut file := os.create(work + '/assets/' + item)!
		file.seek(if item == 'dictionary.vnd' { 64 * 1024 * 1024 } else { 16384 }, .start)!
		file.write([u8(0)])!
		file.close()
		if _ := perfrunner.dictionary_assets(work + '/assets') {
			return error('oversized asset accepted')
		}
	}
	for broken in ['missing_license', 'empty_license', 'data_directory', 'empty_data'] {
		dictionary(work + '/assets')!
		match broken {
			'missing_license' { os.rm(work + '/assets/LICENSE.WordNet')! }
			'empty_license' { os.write_file(work + '/assets/LICENSE.WordNet', '')! }
			'empty_data' { os.write_file(work + '/assets/dictionary.vnd', '')! }
			else {
				os.rm(work + '/assets/dictionary.vnd')!
				os.mkdir(work + '/assets/dictionary.vnd')!
			}
		}
		if _ := perfrunner.dictionary_assets(work + '/assets') {
			return error('missing asset accepted')
		}
		if broken == 'data_directory' { os.rmdir(work + '/assets/dictionary.vnd')! }
	}
	println('PASS dictionary bytes, license, bounds, malformed and nonregular assets')
	for args in [['new=' + work + '/desktop', '--scenarios=workflows'],
		['new=' + work + '/desktop', '--rounds=0'], ['new=' + work + '/desktop', '--scenarios=ops,ops'],
		['new=' + work + '/desktop', 'new=' + work + '/desktop'], ['bad.label=' + work + '/desktop'],
		['new=' + work + '/desktop', '--scenarios=unknown']] {
		if _ := perfrunner.parse(args, work, work, '') { return error('invalid plan accepted') }
	}
	for historical in [false, true] {
		assert fixture_run(work, 'ops', 'complete', historical)! == 0
		assert json_rows(work)!.len == if historical { 35 } else { 36 }
	}
	assert perfrunner.marker('PERF-DRIVE bad x prefix PERF-DRIVE pointer 2', 'PERF-DRIVE ', ['',
		'']) == ['pointer', '2']
	events := perfrunner.move_events(766.0 / 2048, 72.0 / 1536)
	assert events[0].as_map()['data']!.as_map()['value']!.int() == 12255
	println('PASS plan errors, saved operation contract and pointer quantization')
	qmp_work := work + '/qmp'
	os.mkdir(qmp_work)!
	qmp_plan := perfrunner.parse(['new=' + work + '/desktop', '--scenarios=cache', '--rounds=1',
		'--timeout=5', '--shots=' + qmp_work + '/shots'], work, work, '')!
	mut env := os.environ()
	env['PERF_FIXTURE_SOCKET'] = qmp_work + '/qmp.sock'
	assert perfrunner.drive(qmp_plan, perfrunner.Launch{[os.executable(), '--child', 'qmp', 'cache'], env, qmp_work + '/qmp.sock'}, qmp_work, 0.1, false)! == 0
	assert os.file_size(qmp_work + '/serial.log') > 800000
	assert os.read_file(qmp_work + '/shots/new-cache-1.ppm')!.starts_with('P6')
	println('PASS real Unix QMP, events/error replies and independent serial drain under backpressure')
	for scenario in ['pointer', 'drag'] {
		path := work + '/' + scenario
		os.mkdir(path)!
		pointer_plan := perfrunner.parse(['new=' + work + '/desktop', '--scenarios=' + scenario,
			'--rounds=1', '--timeout=5'], work, work, '')!
		mut driver_env := os.environ()
		driver_env['PERF_FIXTURE_SOCKET'] = path + '/qmp.sock'
		assert perfrunner.drive(pointer_plan, perfrunner.Launch{[os.executable(), '--child', 'pointer', scenario], driver_env, path + '/qmp.sock'}, path, 0.2, false)! == 0
	}
	println('PASS concurrent pointer/drag workers, absolute coordinates and button retirement')
	baseline := fd_count()
	for _ in 0 .. 100 {
		out := perfconsole.capture(['/bin/echo', perfreport.done], os.environ(), work, 2, 0.05, false, done, unsafe { nil })!
		assert out.status == 0 && out.drained && out.data.bytestr().contains(perfreport.done)
	}
	assert fd_count() == baseline, '${baseline} -> ${fd_count()}'
	println('PASS 100 native PTY owners in one process, flat descriptors')
}

pub fn cli(argv []string) int {
	if argv.len > 1 && argv[0] == 'v6' {
		json_at := argv.index('--json')
		if json_at < 0 { return 2 }
		output := argv[json_at + 1]
		state := os.dir(output)
		mut lines := []string{}
		for scenario in savedworkflow.selected {
			lines << case_lines(scenario, true).map(it.replace('variant=new', 'variant=final'))
		}
		lines << perfreport.done
		transcript := lines.join('\n') + '\n'
		os.write_file(state + '/original-serial.log', transcript) or { return 1 }
		report := perfreport.finish_policy(transcript.bytes(), ['final'], savedworkflow.selected, 1, output, false, perfreport.Value(perfreport.Number{'0'}), true) or { return 1 }
		println('==> Serial log: ' + state + '/original-serial.log')
		return report.status
	}
	if argv.len > 0 && argv[0] == '--no-build' {
		for variable in ['VINIX_BOOT_DISK', 'VINIX_EFIVARS', 'VINIX_QEMU_PACKAGE_STORE',
			'VINIX_QEMU_PERSIST_DISK'] {
			os.write_file(os.getenv(variable), 'temporary VM image') or { return 1 }
		}
		child(['workflow', 'workflows']) or {
			eprintln(err)
			return 1
		}
		return 0
	}
	if argv.len >= 3 && argv[0] == '--child' {
		child(argv[1..]) or {
			eprintln(err)
			return 1
		}
		return 0
	}
	run() or {
		eprintln(err)
		return 1
	}
	return 0
}
