// SPDX-License-Identifier: MIT
@[has_globals]
module main

import cachecli
import androidhost as ah
import encoding.binary
import gamehost
import hosttest
import io
import json2
import math
import net
import os
import screenshotcore
import sourcecommand
import time
import vmhost
import tarstream

#include <termios.h>
struct C.termios {}

fn C.tcgetattr(i32, &C.termios) i32
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.cfmakeraw(&C.termios)
fn C.fork() i32
fn C.raise(i32) i32

fn write(text string) ! {
	mut stream := os.stdout()
	stream.write_string(text)!
	stream.flush()
}

fn xwd(little bool, drawn bool) []u8 {
	mut data := []u8{len: 148}
	for offset, value in {
		0:  u32(100)
		4:  u32(7)
		16: u32(2)
		20: u32(2)
		28: if little { u32(0) } else { u32(1) }
		44: u32(32)
		48: u32(12)
		76: u32(2)
	} {
		binary.big_endian_put_u32(mut data[offset..offset + 4], value)
	}
	// Two color records, two rows with four bytes of padding per row.
	if drawn {
		for pixel, rgb in [[u8(255), 0, 0], [u8(0), 255, 0], [u8(0), 0, 255], [u8(9), 11, 13]] {
			begin := 124 + (pixel / 2) * 12 + (pixel % 2) * 4
			if little {
				data[begin] = rgb[2]
				data[begin + 1] = rgb[1]
				data[begin + 2] = rgb[0]
			} else {
				data[begin + 1] = rgb[0]
				data[begin + 2] = rgb[1]
				data[begin + 3] = rgb[2]
			}
		}
	}
	return data
}

fn request(port string, verb string, path string, body []u8) !string {
	mut connection := net.dial_tcp('127.0.0.1:' + port)!
	defer { connection.close() or {} }
	connection.set_read_timeout(5 * time.second)
	connection.write_string(verb + ' ' + path + ' HTTP/1.0\r\nContent-Length: ' + body.len.str() + '\r\n\r\n')!
	connection.write(body)!
	mut response := []u8{}
	mut buffer := []u8{len: 4096}
	for {
		n := connection.read(mut buffer) or {
			if err is io.Eof { break }
			return error('HTTP fixture read: ' + err.str())
		}
		if n == 0 { break }
		response << buffer[..n]
	}
	return response.bytestr()
}

fn mock_vm(mode string) ! {
	work := os.getenv('VINIX_ROBLOX_CASE')
	os.write_file(work + '/child.pid', os.getpid().str())!
	mut settings := C.termios{}
	assert C.tcgetattr(0, &settings) == 0
	C.cfmakeraw(&settings)
	assert C.tcsetattr(0, C.TCSANOW, &settings) == 0
	if mode == 'descendant' {
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			os.write_file(work + '/descendant.pid', os.getpid().str())!
			for { time.sleep(time.millisecond * 10) }
		}
		for !os.exists(work + '/descendant.pid') { time.sleep(time.millisecond) }
	}
	if mode == 'kill' { unsafe { C.signal(C.SIGTERM, C.SIG_IGN) } }
	if mode == 'eof' {
		write('ROBLOX-WINDOWS diagnostic\n')!
		return
	}
	if mode == 'integration' {
		os.write_file(work + '/launch-environment.json', json2.encode(os.environ()))!
		mut reader := tarstream.open_plain(os.getenv('VINIX_INITRAMFS'))!
		mut names := []string{}
		for {
			member := reader.next() or {
				if err is tarstream.End { break }
				return err
			}
			names << member.name
		}
		reader.close()
		assert './sbin/init' in names && './root/.wine-x86_64/drive_c/Roblox/Versions/version-test123/RobloxPlayerBeta.exe' in names
		port := os.getenv('VINIX_ROBLOX_PORT')
		assert request(port, 'POST', '/frame-final.xwd', xwd(true, true))!.contains('200 OK')
		assert request(port, 'POST', '/wine.log', 'wine diagnostic\n'.bytes())!.contains('200 OK')
	}
	if mode == 'shell' {
		mut buffer := [65536]u8{}
		for {
			n := C.read(0, &buffer[0], buffer.len)
			if n <= 0 { break }
			if buffer[..int(n)].bytestr().contains('echo native-command') {
				write('SHELL-COMMAND-RECEIVED\n')!
			}
		}
		return
	}
	if mode !in ['timeout', 'kill', 'interrupt', 'terminate', 'overflow'] {
		body := if mode == 'fail' {
			'ROBLOX-WINDOWS-FAIL deliberate\n'
		} else {
			'ROBLOX-WINDOWS-TICK 300\nROBLOX-WINDOWS-ALIVE\nROBLOX-WINDOWS-DONE\n'
		}
		if mode == 'large' { write('native output\n'.repeat(100000))! }
		if mode == 'split' {
			for byte in body.bytes() {
				write([byte].bytestr())!
				time.sleep(time.millisecond)
			}
		} else {
			write(body)!
		}
	}
	for { time.sleep(10 * time.millisecond) }
}

fn http_reply(mut connection net.TcpConn) {
	defer { connection.close() or {} }
	mut head := ''
	mut one := []u8{len: 1}
	for !head.contains('\r\n\r\n') {
		if connection.read(mut one) or { return } == 0 { return }
		head += one.bytestr()
	}
	path := head.fields()[1]
	if path == '/404' {
		connection.write_string('HTTP/1.0 404 Missing\r\nContent-Length: 0\r\n\r\n') or {}
		return
	}
	if path == '/broken' {
		connection.write_string('HTTP/1.0 200 OK\r\nContent-Length: 1000\r\n\r\npartial') or {}
		return
	}
	connection.write_string('HTTP/1.0 200 OK\r\nContent-Length: 1048577\r\n\r\n' + 'x'.repeat(1048577)) or {}
}

fn http_mock() ! {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	write('ROBLOX-UPLOAD-READY ' + listener.addr()!.port()!.str() + '\n')!
	for {
		mut connection := listener.accept()!
		spawn http_reply(mut connection)
	}
}

struct Hooks {
mut:
	commands [][]string
}

fn download_hook(argv []string, capture bool, context voidptr) !sourcecommand.Output {
	mut hooks := unsafe { &Hooks(context) }
	hooks.commands << argv.clone()
	if capture {
		return sourcecommand.Output{ stdout: '{"clientVersionUpload":"version-test123"}' }
	}
	assert argv[0] == 'curl'
	at := argv.index('--output')
	assert at >= 0
	os.write_file(argv[at + 1], 'native download')!
	return sourcecommand.Output{}
}

fn zip_file(path string, items map[string]string) ! {
	mut entries := []ah.ArchiveItem{}
	for name, body in items { entries << ah.ArchiveItem{ name: name, data: body.bytes() } }
	ah.write_archive(path, entries)!
}

fn fixtures(root string, work string) ! {
	golden := json2.decode[map[string]json2.Any](os.read_file(root + '/tests/native-vm-tools/roblox-original.json')!)!
	original := golden['packages']!.as_map()
	assert original.len == vmhost.roblox_packages.len
	for name, directory in vmhost.roblox_packages {
		assert original[name]!.str() == directory
	}
	assert golden['app_settings']!.str() == vmhost.roblox_settings
	for pair in [['version-abc123', '1'], ['version-É١Ⅷ²', '1'], ['version-', '0'],
		['version-x_y', '0'], ['version-a/b', '0'], ['other-abc', '0'], ['version-\x80', '0']] {
		assert vmhost.roblox_version_valid(pair[0]) == (pair[1] == '1')
	}
	options := vmhost.roblox_options(root, [])!
	assert options.memory == '12288' && options.cpus == '4' && options.seconds == '300' && options.timeout == '1500' && options.port == '18791'
	assert options.kernel == root + '/kernel' && options.translation == root + '/build-aarch64-x86-translation/staging'
	configured := vmhost.roblox_options(root, ['--seconds', '٠٠٧', '--timeout', '-1', '--mem',
		'999999999999999999999999999', '--shell', '--strace'])!
	assert configured.seconds == '7' && configured.timeout == '-1' && configured.shell && configured.strace
	launch := vmhost.roblox_launch(options, work + '/initramfs.tar', {
		'KEEP':             'value'
		'VINIX_QEMU_AUDIO': 'on'
	})
	assert launch.command == [root + '/scripts/run-aarch64.sh', '--no-build', '--no-persist',
		'--mem=12288', '--serial']
	assert launch.environment['KEEP']! == 'value' && launch.environment['VINIX_QEMU_AUDIO']! == 'off' && launch.environment['VINIX_QEMU_SMP']! == '4'
	configuration := vmhost.roblox_configuration(options, 'version-test123')
	assert configuration.contains('TEST_EXECUTABLE=') && configuration.contains('C:\\Roblox\\Versions\\version-test123\\RobloxPlayerBeta.exe')
	assert configuration.contains('TEST_UPLOAD=http://10.0.2.2:18791\n') && configuration.contains('TEST_SHELL=0\n')
	mut hooks := Hooks{}
	tools := gamehost.Tools{ root: root, command_hook: download_hook, context: &hooks }
	gamehost.mkdir(work + '/downloads/version-test123')!
	manifest := work + '/downloads/version-test123/rbxPkgManifest.txt'
	package := work + '/downloads/version-test123/RobloxApp.zip'
	zip_file(package, {
		'RobloxPlayerBeta.exe': 'client'
		'nested/a':             'A'
	})!
	checksum := vmhost.roblox_md5(package)!
	os.write_file(manifest, 'v0\u00a0RobloxApp.zip\n' + checksum + '\n999\n999\nWebView2RuntimeInstaller.zip\nskip\n0\n0\n')!
	fetched := vmhost.roblox_fetch(tools, work, '')!
	assert fetched.version == 'version-test123' && hooks.commands.len == 1
	client := work + '/client/version-test123'
	vmhost.roblox_stage(fetched.downloads, client)!
	assert os.read_file(client + '/RobloxPlayerBeta.exe')! == 'client' && os.read_file(client + '/AppSettings.xml')! == vmhost.roblox_settings
	os.write_file(client + '/retained', 'cache')!
	vmhost.roblox_stage(fetched.downloads, client)!
	assert os.exists(client + '/retained')
	os.write_file(manifest, 'v0\nRobloxApp.zip\nbad\n0\n0\n')!
	mut failed := false
	vmhost.roblox_fetch(tools, work, 'version-test123') or { failed = err.msg().contains('checksum') }
	assert failed && !os.exists(package)
	for body in ['', 'v1', 'v0\nother.zip\nx\n0\n0', 'v0\nRobloxApp.zip\nx'] {
		os.write_file(manifest, body)!
		mut rejected := false
		vmhost.roblox_fetch(tools, work, 'version-test123') or { rejected = true }
		assert rejected
	}
	for filename, expected in {
		'/a//./b': 'shaders/a/b'
		'a\\b':    'shaders/a/b'
		'a/':      'shaders/a'
		'':        'shaders'
	} {
		assert vmhost.roblox_member('shaders', filename)! == expected
	}
	assert vmhost.roblox_member('', 'a/../b') or {
		assert err.msg().contains('outside')
		''
	} == ''
	unsafe_zip := work + '/unsafe.zip'
	zip_file(unsafe_zip, {
		'../escape': 'BAD'
	})!
	mut refused := false
	vmhost.roblox_stage_archive(unsafe_zip, '', work + '/unsafe') or { refused = err.msg().contains('outside') }
	assert refused && !os.exists(work + '/escape')
	source := work + '/layer'
	gamehost.mkdir(source + '/skip/deeper')!
	gamehost.mkdir(source + '/keep')!
	os.write_file(source + '/keep/file', 'DATA')!
	os.chmod(source + '/keep/file', 0o751)!
	os.symlink('missing', source + '/broken')!
	os.write_file(source + '/skip/deeper/file', 'SKIP')!
	target := work + '/copy'
	vmhost.roblox_copy_layer(source, target, ['skip'])!
	assert !os.exists(target + '/skip') && os.readlink(target + '/broken')! == 'missing' && os.stat(target + '/keep/file')!.mode & 0o777 == 0o751
	for little in [false, true] {
		for drawn in [false, true] {
			name := work + '/image-' + little.str() + '-' + drawn.str()
			os.write_file_array(name + '.xwd', xwd(little, drawn))!
			assert vmhost.roblox_xwd(name + '.xwd', name + '.png')! == drawn
			image := screenshotcore.read(name + '.png')!
			assert image.width == 2 && image.height == 2
			if drawn {
				assert image.pixels == [u8(255), 0, 0, 0, 255, 0, 0, 0, 255, 9, 11, 13]
			} else {
				assert image.pixels.all(it == 0)
			}
		}
	}
	for body in [[]u8{}, []u8{len: 99}, xwd(true, true)[..120]] {
		os.write_file_array(work + '/bad.xwd', body)!
		assert !vmhost.roblox_xwd(work + '/bad.xwd', work + '/bad.png')!
	}
	duplicate := work + '/duplicate.zip'
	ah.write_archive(duplicate, [
		ah.ArchiveItem{ name: 'same', data: 'first'.bytes() },
		ah.ArchiveItem{ name: 'same', data: 'second'.bytes() },
	])!
	zip := ah.open_archive(duplicate)!
	assert zip.read_index(0)! == 'first'.bytes() && zip.read_index(1)! == 'second'.bytes() && zip.read('same')! == 'second'.bytes()
	mut missing := false
	zip.read_index(2) or {
		missing = true
		[]u8{}
	}
	assert missing
	vmhost.roblox_stage_archive(duplicate, '', work + '/duplicate-output')!
	assert os.read_file(work + '/duplicate-output/same')! == 'second'
	uploads := work + '/verdict'
	gamehost.mkdir(uploads)!
	os.write_file(uploads + '/wine.log', 'a\r\nb\u2028unknown syscall 71\n')!
	for mask in 0 .. 16 {
		text := 'ROBLOX-WINDOWS-DONE\n' + if mask & 1 != 0 { 'ROBLOX-WINDOWS-TICK\n' } else { '' } + if mask & 2 != 0 {
			'ROBLOX-WINDOWS-ALIVE\n'
		} else {
			''
		} + if mask & 4 != 0 { 'ROBLOX-WINDOWS-TICK\n' } else { '' }
		result := vmhost.roblox_verdict(work, uploads, 'version-test123', text.bytes(), mask & 8 != 0, false)!
		assert (result.status == 0) == (mask & 2 != 0 && mask & 4 == 0 && mask & 8 != 0), text + ' / ' + result.lines.str()
		assert result.lines[..3] == ['  a', '  b', '  unknown syscall 71']
		assert result.lines.last().contains(' at the end of the observation, ')
		assert result.lines.last().ends_with('/vinix.log, uploads: ' + uploads)
	}
	mut malformed_trace := false
	vmhost.roblox_verdict(work, uploads, 'v', 'ROBLOX-WINDOWS-DONE\n'.bytes(), false, true) or {
		malformed_trace = true
		vmhost.RobloxVerdict{}
	}
	assert malformed_trace
	os.write_file(uploads + '/wine.log', 'Unknown syscall 71\nUnknown syscall -1\n')!
	trace := vmhost.roblox_verdict(work, uploads, 'v', 'ROBLOX-WINDOWS-DONE\n'.bytes(), false, true)!
	assert trace.lines[0] == 'The client made 2 system calls of its own that Linux does not have, first 71, -1'
	println('PASS native package/cache/path/layer/configuration/frame/verdict fixtures')
}

fn dead(pid int) {
	until := time.sys_mono_now() + 5 * time.second
	for C.kill(i32(pid), 0) == 0 && time.sys_mono_now() < until {
		time.sleep(10 * time.millisecond)
	}
	assert C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH, pid.str()
}

fn posts(port string, index int) string {
	response := request(port, 'POST', '/nested/file-' + index.str(), ('post-' + index.str()).bytes()) or { return err.str() }
	return if response.contains('200 OK') { '' } else { response }
}

fn network(executable string, work string) ! {
	baseline := os.ls('/dev/fd')!.len
	mut server := vmhost.roblox_uploads(executable, work + '/uploads', '0')!
	defer { server.close() or {} }
	mut jobs := []thread string{}
	for index in 0 .. 20 { jobs << spawn posts(server.port, index) }
	mut failures := []string{}
	for job in jobs {
		message := job.wait()
		if message != '' { failures << message }
	}
	if failures.len > 0 {
		server.close()!
		return error(failures.str())
	}
	for index in 0 .. 20 {
		assert os.read_file(work + '/uploads/file-' + index.str())! == 'post-' + index.str()
	}
	assert request(server.port, 'POST', '/', []u8{})!.contains('200 OK') && os.exists(work + '/uploads/upload')
	assert request(server.port, 'GET', '/', []u8{})!.contains('501')
	mut hung := net.dial_tcp('127.0.0.1:' + server.port)!
	hung.write_string('POST /partial HTTP/1.0\r\nContent-Length: 1000000\r\n\r\nx')!
	server.close()!
	server.close()!
	dead(server.pid)
	hung.close()!
	assert os.ls('/dev/fd')!.len == baseline
	println('PASS concurrent real uploads, partial-request retirement and exact process/descriptor closure')
}

fn signal_after(path string, signal i32) {
	until := time.sys_mono_now() + 10 * time.second
	for !os.exists(path) && time.sys_mono_now() < until { time.sleep(time.millisecond) }
	assert os.exists(path)
	C.raise(signal)
}

fn idle() {}

fn shell_commands(work string) {
	until := time.sys_mono_now() + 10 * time.second
	for !os.exists(work + '/shell.in') && time.sys_mono_now() < until {
		time.sleep(time.millisecond)
	}
	assert os.exists(work + '/shell.in')
	mut file := os.open_append(work + '/shell.in') or { panic(err) }
	file.write_string('echo native-command\n') or { panic(err) }
	file.flush()
	for !(os.read_file(work + '/vinix.log') or { '' }).contains('SHELL-COMMAND-RECEIVED') && time.sys_mono_now() < until {
		time.sleep(time.millisecond)
	}
	assert (os.read_file(work + '/vinix.log') or { '' }).contains('SHELL-COMMAND-RECEIVED')
	file.write_string('poweroff-test\n') or { panic(err) }
	file.flush()
	file.close()
}

fn processes(work string) ! {
	baseline := os.ls('/dev/fd')!.len
	for mode in ['pass', 'split', 'large', 'fail', 'eof', 'timeout', 'kill', 'descendant', 'shell',
		'overflow', 'interrupt', 'terminate'] {
		case := work + '/' + mode
		gamehost.mkdir(case)!
		guard := cachecli.own_commands()
		mut env := os.environ()
		env['VINIX_ROBLOX_CASE'] = case
		launch := vmhost.Launch{[os.executable(), 'mock-vm', mode], env, case}
		sender := if mode in ['interrupt', 'terminate'] {
			spawn signal_after(case + '/child.pid', if mode == 'interrupt' {
				C.SIGINT
			} else {
				C.SIGTERM
			})
		} else if mode == 'shell' {
			spawn shell_commands(case)
		} else {
			spawn idle()
		}
		mut failed := false
		bytes := vmhost.roblox_capture(launch, case, mode == 'shell', if mode == 'overflow' {
			math.inf(1)
		} else if mode in ['timeout', 'kill'] {
			0.05
		} else {
			45
		}) or {
			failed = true
			[]u8{}
		}
		assert failed == (mode in ['overflow', 'interrupt', 'terminate']), mode
		if !failed {
			assert os.read_bytes(case + '/vinix.log')! == bytes
			if mode in ['pass', 'split', 'large', 'descendant'] {
				assert bytes.bytestr().contains('ROBLOX-WINDOWS-DONE')
			}
			if mode == 'shell' {
				assert !os.exists(case + '/shell.in')
			}
		}
		sender.wait()
		guard.close()
		if os.exists(case + '/child.pid') { dead(os.read_file(case + '/child.pid')!.int()) }
		if mode == 'descendant' { dead(os.read_file(case + '/descendant.pid')!.int()) }
		assert os.ls('/dev/fd')!.len == baseline, mode
		println('PASS real Roblox PTY/FIFO ' + mode)
		flush_stdout()
	}
}

fn actual_download(work string) ! {
	guard := cachecli.own_commands()
	defer { guard.close() }
	// The helper publishes the same readiness protocol but returns HTTP fixtures.
	mut server := vmhost.roblox_uploads(os.executable(), work + '/http', '0')!
	defer { server.close() or {} }
	// The test executable routes roblox-upload to its deterministic HTTP server
	// when this environment flag is present (set before this function's call).
	target := work + '/download'
	vmhost.roblox_download(gamehost.Tools{}, 'http://127.0.0.1:' + server.port + '/ok', target)!
	assert os.file_size(target) == 1048577 && !os.exists(target + '.partial')
	for path in ['/broken', '/404'] {
		mut failed := false
		vmhost.roblox_download(gamehost.Tools{}, 'http://127.0.0.1:' + server.port + path, target + '-failed') or { failed = true }
		assert failed && !os.exists(target + '-failed')
	}
	server.close()!
	dead(server.pid)
	println('PASS real streamed HTTP download, atomic success and partial/status failures')
}

fn integration(root string, executable string, work string) ! {
	guard := cachecli.own_commands()
	defer { guard.close() }
	repo := work + '/checkout'
	state := work + '/state'
	for directory in ['build-aarch64-x11/staging/lib', 'build-aarch64-x11/staging/usr/lib',
		'build-aarch64-x11/staging/usr/bin', 'build-aarch64-userland/staging/lib',
		'build-aarch64-userland/staging/usr/lib', 'build-aarch64-userland/staging/bin',
		'build-aarch64-x86-translation/staging/usr/bin',
		'build-aarch64-x86-translation/staging/root/.wine-word2013-x86_64', 'scripts'] {
		gamehost.mkdir(repo + '/' + directory)!
	}
	os.write_file(repo + '/build-aarch64-userland/staging/lib/libc.so', 'LIBC')!
	os.symlink('missing', repo + '/build-aarch64-userland/staging/usr/lib/missing.so')!
	os.write_file(repo + '/build-aarch64-userland/staging/bin/busybox', 'BUSYBOX')!
	os.write_file(repo + '/build-aarch64-x86-translation/staging/usr/bin/wine64', 'WINE')!
	os.write_file(repo + '/build-aarch64-x86-translation/staging/root/.wine-word2013-x86_64/file', 'UNUSED')!
	os.write_file(repo + '/scripts/run-aarch64.sh', '#!/bin/sh\nexec ' + hosttest.shell_quote(os.executable()) + ' mock-vm integration "$@"\n')!
	os.chmod(repo + '/scripts/run-aarch64.sh', 0o755)!
	downloads := state + '/downloads/version-test123'
	gamehost.mkdir(downloads)!
	zip_file(downloads + '/RobloxApp.zip', {
		'RobloxPlayerBeta.exe': 'unchanged client'
	})!
	os.write_file(downloads + '/rbxPkgManifest.txt', 'v0\nRobloxApp.zip\n' + vmhost.roblox_md5(downloads + '/RobloxApp.zip')! + '\n0\n0\n')!
	port := vmhost.available_port()!
	mut env := os.environ()
	env['VINIX_ROBLOX_CASE'] = state
	env['VINIX_ROBLOX_PORT'] = port
	for index in 0 .. 2 {
		if index == 1 {
			os.write_file(state + '/root/root/.wine-x86_64/drive_c/Roblox/stale', 'remove on refresh')!
		}
		result := sourcecommand.capture_full([executable, 'roblox-windows', '--repo', repo, '--work',
			state, '--version', 'version-test123', '--port', port, '--timeout', '20', '--arguments',
			"--quoted 'value'"], env, 30, 16 * 1024 * 1024, cachecli.cancelled)!
		assert result.status == 0, result.stdout + result.stderr
		assert result.stdout.contains('client still running at the end of the observation, a drawn display.')
		assert !os.exists(state + '/initramfs.tar') && !os.exists(state + '/boot.img') && !os.exists(state + '/root/root/.wine-x86_64/drive_c/Roblox/stale')
		assert os.is_link(state + '/root/bin/sh') && os.readlink(state + '/root/usr/lib/missing.so')! == 'missing'
		assert !os.exists(state + '/root/root/.wine-word2013-x86_64')
		assert os.read_bytes(state + '/root/sbin/init')! == os.read_bytes(root + '/tests/roblox-windows/guest-init.sh')!
		assert os.read_file(state + '/root/opt/roblox-test/config.sh')!.contains("TEST_ARGUMENTS='--quoted '")
		actual := json2.decode[map[string]string](os.read_file(state + '/launch-environment.json')!)!
		assert actual['VINIX_KERNEL_DIR']! == repo + '/kernel' && actual['VINIX_QEMU_AUDIO']! == 'off'
		assert screenshotcore.read(state + '/uploads/frame-final.png')!.width == 2
		dead(os.read_file(state + '/child.pid')!.int())
	}
	os.write_file(repo + '/scripts/run-aarch64.sh', '#!/bin/sh\nexec ' + hosttest.shell_quote(os.executable()) + ' mock-vm kill "$@"\n')!
	os.chmod(repo + '/scripts/run-aarch64.sh', 0o755)!
	failed := sourcecommand.capture_full([executable, 'roblox-windows', '--repo', repo, '--work',
		state, '--version', 'version-test123', '--port', port, '--timeout', '1'], env, 20, 16 * 1024 * 1024, cachecli.cancelled)!
	assert failed.status == 1 && failed.stderr.contains('never finished its observation'), failed.stdout + failed.stderr
	assert !failed.stderr.contains('V panic:')
	assert os.read_bytes(state + '/vinix.log')!.len == 0 && !os.exists(state + '/initramfs.tar')
	dead(os.read_file(state + '/child.pid')!.int())
	println('PASS three real complete CLI runs: staging/archive/upload/frame/report, prepared-root refresh and empty timeout retirement')
}

fn main() { run() or { panic(err) } }

fn run() ! {
	if os.args.len > 1 && os.args[1] == 'mock-vm' {
		mock_vm(os.args[2])!
		return
	}
	if os.args.len > 1 && os.args[1] == 'roblox-upload' {
		if os.getenv('VINIX_ROBLOX_HTTP_FIXTURE') == '1' {
			http_mock()!
		} else {
			vmhost.roblox_serve(os.args[2], os.args[3])!
		}
		return
	}
	if os.args.len != 3 { return error('expected native main and evidence directory') }
	executable := os.args[1]
	work := os.args[2]
	gamehost.mkdir(work)!
	// Local fixture requests must stay on loopback under proxy-configured hosts.
	os.setenv('NO_PROXY', '127.0.0.1,localhost', true)
	os.setenv('no_proxy', '127.0.0.1,localhost', true)
	root := os.real_path(os.dir(@FILE) + '/../..')
	fixtures(root, work + '/files')!
	network(executable, work)!
	processes(work + '/processes')!
	os.setenv('VINIX_ROBLOX_HTTP_FIXTURE', '1', true)
	actual_download(work)!
	os.unsetenv('VINIX_ROBLOX_HTTP_FIXTURE')
	integration(root, executable, work + '/integration')!
	os.write_file(work + '/passed', 'PASS\n')!
}
