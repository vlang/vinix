// SPDX-License-Identifier: GPL-2.0-or-later
module main

import boottools
import cachecli
import crypto.sha256
import json2
import net.unix
import os
import sourcecommand
import time

#include <signal.h>

fn C.kill(i32, i32) i32

fn require(ok bool, message string) ! { if !ok { return error(message) } }

fn read_word(data []u8, at int) u64 {
	mut value := u64(0)
	for i in 0 .. 8 { value |= u64(data[at + i]) << (8 * i) }
	return value
}

fn historical(work string, golden string) ! {
	old := os.read_bytes(golden + '/apple-stage2-final-qemu/image.bin')!
	mut base := -1
	for at in 0 .. old.len - 80 {
		if old[at..at + 8].bytestr() == 'VNXAPPL1' && read_word(old, at + 8) == (u64(1) << 32) | 80 {
			base = at
			break
		}
	}
	if base < 0 { return error('historical image has no payload header') }
	fields := [0, 1, 2, 3, 4, 5, 6, 7].map(read_word(old, base + 16 + it * 8))
	loader := old[..base]
	// This historical bulk image was capped at 1 MiB after qualification.
	// Zero-fill the unknown kernel suffix to recover the layout, and compare
	// only retained image bytes. The other artifacts remain complete.
	mut kernel := []u8{len: int(fields[1])}
	copy(mut kernel, old[base + int(fields[0])..])
	initramfs := os.read_bytes(golden + '/apple-stage2-final-qemu/initramfs.tar')!
	cmdline := 'vinix.qemu_platform=1'
	repacked := boottools.pack(loader, u64(base), kernel, initramfs, cmdline, 1, fields[6])!
	require(repacked[..old.len] == old, 'historical packed-image prefix bytes changed')!
	plan := boottools.prepare(repacked, []u8{}, true)!
	for file in plan.files {
		if file.name == 'image.bin' { continue }
		expected := os.read_bytes(golden + '/apple-stage2-final-qemu/' + file.name)!
		require(expected == file.data, 'historical iBoot artifact changed: ' + file.name)!
	}
	// Preserve immutable baseline bytes and hashes outside the shared checkout.
	mut hashes := map[string]string{}
	hashes['retained-image-prefix'] = sha256.sum(old).hex()
	for file in plan.files {
		if file.name != 'image.bin' { hashes[file.name] = sha256.sum(file.data).hex() }
	}
	os.write_file(work + '/historical.json', json2.encode(hashes, prettify: true) + '\n')!
	println('Historical Python-built image prefix, complete ADT/boot/scratch/firmware/AIC bytes: PASS')
}

fn line(mut connection unix.StreamConn) !string {
	mut result := []u8{}
	mut byte := [1]u8{}
	for {
		if connection.read(mut byte) or { return err } == 0 { return error('fixture socket EOF') }
		if byte[0] == `\n` { return result.bytestr() }
		result << byte[0]
		if result.len > 1024 * 1024 { return error('oversized fixture request') }
	}
	return error('fixture socket EOF')
}

fn fake(work string, socket string, mode string) !int {
	mut child := os.new_process('/bin/sleep')
	child.set_args(['600'])
	child.run()
	os.write_file(work + '/pids', os.getpid().str() + '\n' + child.pid.str() + '\n')!
	if mode == 'early' { return 23 }
	if mode == 'verbose' {
		print('x'.repeat(150000))
		eprint('y'.repeat(150000))
	}
	if mode != 'timeout' && mode != 'signal' {
		os.write_file(work + '/serial.log', boottools.boot_marker + '\naic: masked\n')!
	}
	mut server := unix.listen_stream(socket)!
	defer { server.close() or {} }
	os.write_file(work + '/ready', 'ready')!
	if mode == 'signal' {
		for { time.sleep(50 * time.millisecond) }
	}
	mut client := server.accept()!
	defer { client.close() or {} }
	if mode == 'eof' { return 0 }
	if mode == 'malformed' {
		client.write_string('not-json\n')!
		client.write_string('not-json\n')!
		time.sleep(time.second)
		return 0
	}
	if mode == 'greeting-malformed' {
		client.write_string('not-json\n')!
	} else {
		if mode == 'event-greeting' { client.write_string('{"event":"GREETING_EVENT"}\n')! }
		client.write_string('{"QMP":{}}\n')!
	}
	for {
		request := json2.decode[json2.Any](line(mut client)!)!.as_map()
		name := request['execute']!.str()
		if mode == 'error' {
			client.write_string('{"error":{"class":"FixtureError","desc":"injected"}}\n')!
			time.sleep(time.second)
			return 0
		}
		if name == 'pmemsave' {
			args := request['arguments']!.as_map()
			path := args['filename']!.str()
			size := args['size']!.int()
			mut data := []u8{len: size}
			if path.ends_with('segment.dump') {
				for i in 0 .. data.len { data[i] = 0xa5 }
			}
			if path.ends_with('aic.dump') {
				data[0x14] = 1
				for i in boottools.aic_mask_set .. boottools.aic_mask_set + 128 { data[i] = 0xff }
			}
			if mode == 'bad' { data[0x1c] = 0xff }
			if mode != 'missing-dump' { os.write_file_array(path, data)! }
		}
		// Fragment replies and put a protocol event before each response.
		client.write_string('{"event":"FIXTURE"}\n{"ret')!
		client.write_string('urn":{}}\n')!
		if name == 'quit' { return 0 }
	}
	return 0
}

fn fake_ioreg() ! {
	work := os.getenv('VINIX_BOOT_IOREG_FIXTURE_WORK')
	if work == '' { return error('missing IORegistry fixture work directory') }
	mut child := os.new_process('/bin/sleep')
	child.set_args(['600'])
	child.run()
	os.write_file(work + '/pids', os.getpid().str() + '\n' + child.pid.str() + '\n')!
	os.write_file(work + '/ready', 'ready')!
	for { time.sleep(50 * time.millisecond) }
}

fn alive(pid int) bool { return C.kill(pid, 0) == 0 }

fn retired(work string) ! {
	ids := os.read_file(work + '/pids')!.split_into_lines().map(it.int())
	deadline := time.sys_mono_now() + u64(5 * time.second)
	for ids.any(alive(it)) && time.sys_mono_now() < deadline { time.sleep(20 * time.millisecond) }
	require(ids.all(!alive(it)), 'emulator/descendant left alive: ' + ids.str())!
}

struct SignalCase {
	work   string
	signal int
}

fn signal_runner(pid int, pointer voidptr) ! {
	data := unsafe { &SignalCase(pointer) }
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for !os.exists(data.work + '/ready') {
		if time.sys_mono_now() > deadline { return error('signal fixture never became ready') }
		time.sleep(20 * time.millisecond)
	}
	C.kill(pid, data.signal)
}

fn fd_count() int {
	$if macos {
		return (os.ls('/dev/fd') or { []string{} }).len
	}
	return (os.ls('/proc/self/fd') or { []string{} }).len
}

fn cases(work string) ! {
	os.mkdir_all(work)!
	guard := cachecli.own_commands()
	defer { guard.close() }
	self := os.executable()
	for mode in ['success', 'verbose', 'event-greeting', 'bad', 'missing-dump', 'timeout', 'early',
		'eof', 'malformed', 'greeting-malformed', 'error'] {
		directory := work + '/' + mode
		os.mkdir(directory)!
		socket := os.temp_dir() + '/vinix-boot-fixture-' + os.getpid().str() + '.sock'
		result := sourcecommand.capture([self, 'run', directory, socket, mode], os.environ(), 15, 4 * 1024 * 1024, unsafe { nil })!
		os.write_file(directory + '/result.log', result.stdout + result.stderr)!
		require(result.status == if mode in ['success', 'verbose', 'event-greeting'] {
			0
		} else {
			1
		}, 'unexpected runner status: ' + mode + '\n' + result.stdout + result.stderr)!
		if mode == 'verbose' {
			require(result.stdout.starts_with('==>') && result.stdout.contains('x'.repeat(150000)), 'inherited stdout blocked or lost data')!
		}
		if mode == 'success' {
			require(result.stdout.contains('PASS: iBoot-style hand-off reached user space'), 'success report missing')!
		}
		if mode == 'early' {
			require(result.stdout.contains('QEMU exited with status 23'), 'early-exit status missing')!
		}
		if mode == 'timeout' {
			require(result.stdout.contains('PID 1 never printed its marker'), 'timeout report missing')!
		}
		retired(directory)!
		require(!os.exists(socket), 'QMP socket left behind')!
		println('QMP / owner / dumps: PASS ' + mode)
	}
	for signal in [2, 15] {
		directory := work + '/signal-' + signal.str()
		os.mkdir(directory)!
		socket := os.temp_dir() + '/vinix-boot-fixture-' + os.getpid().str() + '.sock'
		data := SignalCase{directory, signal}
		result := sourcecommand.capture_owned([self, 'run', directory, socket, 'signal'], os.environ(), 15, 4 * 1024 * 1024, unsafe { nil }, unsafe { nil }, signal_runner, unsafe { &data }, 0)!
		require(result.status == 128 + signal, 'signal status wrong: ' + result.status.str() + result.stderr)!
		retired(directory)!
		require(!os.exists(socket), 'signal left QMP socket')!
		println('Signal / descendant retirement: PASS ' + signal.str())
	}
	old_path := os.getenv('PATH')
	bin := work + '/ioreg-bin'
	os.mkdir(bin)!
	os.symlink(self, bin + '/ioreg')!
	os.setenv('PATH', bin + ':' + old_path, true)
	defer {
		os.setenv('PATH', old_path, true)
		os.unsetenv('VINIX_BOOT_IOREG_FIXTURE_WORK')
	}
	for signal in [2, 15] {
		directory := work + '/ioreg-signal-' + signal.str()
		os.mkdir(directory)!
		os.setenv('VINIX_BOOT_IOREG_FIXTURE_WORK', directory, true)
		output := directory + '/out.adt'
		os.write_file(output, 'protected')!
		data := SignalCase{directory, signal}
		result := sourcecommand.capture_owned([self, '--tool', 'ioreg_adt', output], os.environ(), 15, 1024 * 1024, unsafe { nil }, unsafe { nil }, signal_runner, unsafe { &data }, 0)!
		require(result.status == 128 + signal, 'IORegistry signal status wrong: ' + result.status.str() + result.stderr)!
		retired(directory)!
		require(os.read_file(output)! == 'protected', 'interrupted IORegistry replaced output')!
		println('IORegistry signal / descendant / output preservation: PASS ' + signal.str())
	}
	before := fd_count()
	for _ in 0 .. 100 {
		result := sourcecommand.capture_as('/usr/bin/true', ['custom-argv0'], os.environ(), 2, 1024, unsafe { nil })!
		require(result.status == 0, 'explicit executable launch failed')!
	}
	require(fd_count() == before, 'explicit executable capture leaked a descriptor')!
	println('100 explicit-executable launches: PASS, descriptors flat')
}

fn run(work string, socket string, mode string) !int {
	guard := cachecli.own_commands()
	defer { guard.close() }
	preparation := boottools.Preparation{ segment: 0x43000000, with_aic: true }
	return boottools.run_prepared([os.executable(), 'fake', work, socket, mode], work, socket, preparation, boottools.BootOptions{
		timeout: if mode in [
			'timeout',
			'early',
		] {
			1
		} else {
			300
		}
	}) or {
		eprintln(err)
		return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	}
}

fn main() {
	if os.file_name(os.args[0]) == 'ioreg' {
		fake_ioreg() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	argv := os.args[1..]
	if argv.len >= 2 && argv[0] == '--tool' {
		args := argv[2..]
		status := match argv[1] {
			'pack' { boottools.pack_cli(args) }
			'build-image' { boottools.build_cli(args) }
			'check-v-abi' { boottools.abi_cli(args) }
			'check_converter' { boottools.converter_cli(args) }
			'ioreg_adt' { boottools.ioreg_cli(args) }
			'qemu_iboot' { boottools.iboot_cli(args) }
			'run-v-core' { boottools.core_cli(args) }
			'fixture-parity' { boottools.parity_cli(args) }
			else { 2 }
		}
		exit(status)
	}
	if argv.len == 4 && argv[0] == 'fake' {
		exit(fake(argv[1], argv[2], argv[3]) or {
			eprintln(err)
			1
		})
	}
	if argv.len == 4 && argv[0] == 'run' {
		exit(run(argv[1], argv[2], argv[3]) or {
			eprintln(err)
			1
		})
	}
	if argv.len == 3 && argv[0] == 'historical' {
		historical(argv[1], argv[2]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if argv.len == 1 {
		cases(argv[0]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	eprintln('usage: test-boot-tools NEW_STATE | historical STATE OLD_GOLDENS')
	exit(2)
}
