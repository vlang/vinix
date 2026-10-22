// SPDX-License-Identifier: GPL-2.0-or-later
// Build and boot authenticated X11 with the real signed package/account tools.
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso
import time
import net.unix
import qmpclient
import screenshotcore
import stbi
import tools.packages.pkgcore
import proof

struct TreeInput {
	root string
	selected_sources bool
	entries map[string]string
}

fn remember_tree(name string, directory string, selected bool, mut trees map[string]TreeInput, mut inputs map[string]string) ! {
	entries := proof.tree(directory, selected)!
	if entries.len == 0 { return error('empty required input tree: ' + name) }
	trees[name] = TreeInput{directory, selected, entries}
	for relative, value in entries {
		if value.len == 64 { inputs[directory + '/' + relative] = value }
		if value.starts_with('link:') && value.contains('\nsha256:') { inputs[directory + '/' + relative] = value.all_after('\nsha256:') }
	}
}

fn verify_trees(trees map[string]TreeInput) ! {
	for _, tree in trees { proof.tree_unchanged(tree.root, tree.selected_sources, tree.entries)! }
}

fn digest(path string) !string {
 mut file := os.open(path)!
 defer { file.close() }
 mut state := sha256.new()
 defer { unsafe { state.free() } }
 mut buffer := []u8{len: 1024 * 1024}
 defer { unsafe { buffer.free() } }
 for {
  count := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
  if count == 0 { break }
  state.write(buffer[..count])!
 }
 result := state.sum([]u8{})
 defer { unsafe { result.free() } }
 return result.hex()
}

fn invoke(args []string, log string) !string {
	os.write_file(log + '.argv.json', json2.encode(args))!
	mut child := os.new_process(args[0])
	defer { child.close() }
	child.set_args(args[1..]); child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	os.write_file(log, output)!
	if child.code != 0 { return error(args[0] + ' failed; see ' + log) }
	return output
}

fn required(options map[string]string, name string) !string {
	return os.abs_path(options[name] or { return error('required ' + name) })
}

fn tree_hashes(root string) !map[string]string {
	mut hashes := map[string]string{}
	for directory in ['tools/accounts', 'tools/packages', 'build-support/xorg-server/winehost',
		'build-support/native-compat-tools/compathost', 'tools/qmpclient', 'build-support/screenshotcore', 'tests/hardware-platform/hwhost',
		'tests/hardware-platform/plainiso'] {
		for path in os.walk_ext(root + '/' + directory, '.v') {
			if !path.ends_with('_test.v') { hashes[path] = digest(path)! }
		}
	}
	for name in ['tests/software-hosted-x11/check.v', 'tests/software-hosted-x11/guest/main.v',
		'build-support/xorg-server/wine-host-v-abi.h', 'build-support/xorg-server/build-wine-host.sh',
		'build-support/xorg-server/compile-v-host', 'build-support/native-compat-tools/main.v'] {
		hashes[root + '/' + name] = digest(root + '/' + name)!
	}
	return hashes
}

fn verify(hashes map[string]string) ! {
	for path, hash in hashes { if digest(path)! != hash { return error('input changed: ' + path) } }
}

fn copy_needed(binary string, sysroot string, destination string, readelf string, work string, mut inputs map[string]string) ! {
	mut pending := [binary]
	mut seen := map[string]bool{}
	for pending.len > 0 {
		path := pending.pop()
		if path in seen { continue }
		seen[path] = true
		inputs[path] = digest(path)!
		output := invoke([readelf, '-d', path], work + '/needed-' + seen.len.str() + '-' + os.base(binary) + '.log')!
		for line in output.split_into_lines() {
			if !line.contains('(NEEDED)') { continue }
			name := line.all_after('[').all_before(']')
			if name == '' || name.contains('/') { return error('invalid ELF dependency') }
			mut source := ''
			for directory in [sysroot + '/lib', sysroot + '/usr/lib'] {
				if os.is_file(directory + '/' + name) { source = directory + '/' + name; break }
			}
			if source == '' { return error('missing ELF dependency ' + name) }
			if !os.exists(destination + '/' + name) { os.cp(source, destination + '/' + name)! }
			pending << source
		}
	}
}

fn build_program(v string, clang string, sysroot string, gcc string, source_root string, source string,
	name string, arch string, work string, dynamic bool) !string {
	directory := work + '/build-' + name
	os.mkdir_all(directory)!
	cfile := directory + '/' + name + '.c'
	invoke([v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-gc', 'none', '-manualfree', '-enable-globals', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-path', '@vlib|' + source_root + '|' + source_root + '/tools/accounts|@vmodules', '-o', cfile, source], directory + '/v.log')!
	// Include the compiler's existing runtime helper implementations; no fixture
	// implementation is added to the generated C.
	vlib := os.dir(v) + '/vlib'
	os.write_file(directory + '/runtime.c', '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "' +
		vlib + '/os/execute_capture_nix.h"\n#define V_SYNC_THREAD_SCOPE\n#include "' + vlib + '/sync/thread_helper.h"\n')!
	mut flags := [clang, '--target=' + arch + '-linux-musl', '--sysroot=' + sysroot,
		'--gcc-install-dir=' + gcc, '-fuse-ld=lld', '-O1', '-w', '-fno-stack-protector',
		'-Wno-error=incompatible-pointer-types',
		'-D_GNU_SOURCE', '-L' + sysroot + '/lib', '-L' + sysroot + '/usr/lib',
		'-Wl,-rpath-link,' + sysroot + '/lib', '-Wl,-rpath-link,' + sysroot + '/usr/lib']
	if !dynamic { flags << '-static' } else { flags << '-static-libgcc' }
	flags << [cfile, directory + '/runtime.c', '-lm', '-lpthread']
	if dynamic { flags << '-lX11' }
	flags << ['-o', directory + '/' + name]
	invoke(flags, directory + '/cc.log')!
	return directory + '/' + name
}

// Retain every consumed source and command rather than the production helper's
// temporary project, which is intentionally retired when that helper returns.
fn build_bridge(v string, clang string, sysroot string, gcc string, source_root string, arch string, work string) !string {
	directory := work + '/build-bridge'
	project := directory + '/project'
	os.mkdir_all(project)!
	invoke(['cp', '-Rp', source_root + '/build-support/xorg-server/winehost', project + '/winehost'], directory + '/copy-winehost.log')!
	invoke(['cp', '-Rp', source_root + '/tools/packages/x11auth', project + '/x11auth'], directory + '/copy-x11auth.log')!
	proof.copied_sources(project + '/winehost', proof.tree(source_root + '/build-support/xorg-server/winehost', true)!)!
	proof.copied_sources(project + '/x11auth', proof.tree(source_root + '/tools/packages/x11auth', true)!)!
	os.write_file(project + '/v.mod', "Module { name: 'x11_bridge' }\n")!
	os.write_file(project + '/entry.v', 'module main\nimport winehost as _\n')!
	cfile := directory + '/bridge.c'
	invoke([v, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-o', cfile, '-d', 'x11_host_libc', project], directory + '/v.log')!
	os.write_file(cfile, '#define VINIX_XINPUT_V_RUNTIME 1\n#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-label"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n' + os.read_file(cfile)!)!
	invoke([clang, '--target=' + arch + '-linux-musl', '--sysroot=' + sysroot, '--gcc-install-dir=' + gcc,
		'-static-libgcc', '-O2', '-Wall', '-Wextra', '-Werror', '-D__vinix__', '-I' + sysroot + '/usr/include',
		cfile, '-I' + source_root + '/build-support/xorg-server', '-fuse-ld=lld',
		'-L' + sysroot + '/usr/lib', '-L' + sysroot + '/lib', '-Wl,-rpath-link,' + sysroot + '/usr/lib',
		'-Wl,-rpath-link,' + sysroot + '/lib', '-lXtst', '-lXdamage', '-lX11', '-lXext', '-lxcb', '-o', directory + '/bridge'], directory + '/cc.log')!
	return directory + '/bridge'
}



#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <errno.h>

struct C.pollfd { pub mut: fd i32 events i16 revents i16 }
fn C.poll(&C.pollfd, usize, i32) i32

fn shutdown_line(mut connection unix.StreamConn, deadline u64) !string {
	mut line := []u8{}
	for {
		if time.sys_mono_now() >= deadline { return error('QMP shutdown deadline expired') }
		mut descriptor := C.pollfd{fd: connection.sock.handle, events: i16(C.POLLIN)}
		ready := C.poll(&descriptor, 1, 50)
		if ready == 0 { continue }
		if ready < 0 { if C.errno == C.EINTR { continue }; return os.error_posix() }
		mut byte := u8(0)
		count := C.recv(connection.sock.handle, &byte, 1, 0)
		if count == 0 { return error('QMP closed before guest shutdown') }
		if count < 0 { if C.errno in [C.EAGAIN, C.EINTR] { continue }; return os.error_posix() }
		if byte == `\n` { return line.bytestr() }
		if line.len >= 1024 * 1024 { return error('QMP shutdown line exceeds limit') }
		line << byte
	}
	return error('QMP shutdown stream ended')
}

fn shutdown_record(mut connection unix.StreamConn, mut transcript os.File, deadline u64) !map[string]json2.Any {
	line := shutdown_line(mut connection, deadline)!
	transcript.writeln(line)!
	return json2.decode[json2.Any](line)!.as_map()
}

fn shutdown_connect(path string, mut transcript os.File, deadline u64, boot int) !&unix.StreamConn {
	mut connection := unix.connect_stream(path)!
	mut admitted := false
	defer { if !admitted { connection.close() or {} } }
	if C.fcntl(connection.sock.handle, C.F_SETFD, C.FD_CLOEXEC) != 0 ||
		C.fcntl(connection.sock.handle, C.F_SETFL, C.O_NONBLOCK) != 0 { return os.error_posix() }
	transcript.writeln(json2.encode({'graphical_boot': boot}))!
	greeting := shutdown_record(mut connection, mut transcript, deadline)!
	if 'QMP' !in greeting { return error('invalid shutdown QMP greeting') }
	request := '{"execute":"qmp_capabilities"}\n'
	if C.send(connection.sock.handle, request.str, usize(request.len), 0) != request.len {
		return error('could not enable shutdown QMP events')
	}
	reply := shutdown_record(mut connection, mut transcript, deadline)!
	if 'return' !in reply { return error('shutdown QMP capabilities refused') }
	admitted = true
	return connection
}

fn shutdown_event(mut connection unix.StreamConn, mut transcript os.File, deadline u64) ! {
	for _ in 0 .. 128 {
		reply := shutdown_record(mut connection, mut transcript, deadline)!
		event := (reply['event'] or { json2.Any('') }).str()
		if event in ['RESET', 'GUEST_PANICKED'] { return error('forbidden QMP power event: ' + event) }
		if event == 'SHUTDOWN' {
			data := (reply['data'] or { return error('QMP shutdown has no data') }).as_map()
			if (data['guest'] or { json2.Any(false) }) != json2.Any(true) ||
				(data['reason'] or { json2.Any('') }) != json2.Any('guest-shutdown') {
				return error('QMP did not report guest-initiated shutdown')
			}
			return
		}
	}
	return error('too many QMP shutdown events')
}


fn point(mut monitor qmpclient.Monitor, x int, y int) ! {
	monitor.command('input-send-event', {
		'events': json2.Any([
			json2.Any({
				'type': json2.Any('abs')
				'data': json2.Any({
					'axis':  json2.Any('x')
					'value': json2.Any(x * 32767 / 1024)
				})
			}),
			json2.Any({
				'type': json2.Any('abs')
				'data': json2.Any({
					'axis':  json2.Any('y')
					'value': json2.Any(y * 32767 / 768)
				})
			}),
		])
	})!
	// QMP acknowledges queued input before the compositor repaints the pointer.
	// Keep canonical framebuffer captures and subsequent button events settled.
	time.sleep(200 * time.millisecond)
}

fn button(mut monitor qmpclient.Monitor, down bool) ! {
	monitor.command('input-send-event', {
		'events': json2.Any([json2.Any({
			'type': json2.Any('btn')
			'data': json2.Any({
				'button': json2.Any('left')
				'down':   json2.Any(down)
			})
		})])
	})!
}

fn press_before_shutdown(mut monitor qmpclient.Monitor, x int, y int) ! {
	point(mut monitor, x, y)!
	// USB HID samples button state: down/up in one request can coalesce before
	// the guest observes a press. Hold it across at least one device poll.
	button(mut monitor, true)!
	time.sleep(200 * time.millisecond)
	// The release reply may race a fast guest shutdown. The independent QMP
	// guest-SHUTDOWN event and successful process exit remain mandatory below.
	button(mut monitor, false) or {}
}

fn click(mut monitor qmpclient.Monitor, x int, y int) ! {
	point(mut monitor, x, y)!
	for down in [true, false] {
		button(mut monitor, down)!
		time.sleep(100 * time.millisecond)
	}
	time.sleep(500 * time.millisecond)
}

fn region_changes(before screenshotcore.Image, after screenshotcore.Image, x int, y int, width int, height int) int {
	mut changed := 0
	for row in y .. y + height {
		for col in x .. x + width {
			index := (row * before.width + col) * 3
			if before.pixels[index..index + 3] != after.pixels[index..index + 3] { changed++ }
		}
	}
	return changed
}

fn shot(mut monitor qmpclient.Monitor, work string, name string) !screenshotcore.Image {
	path := work + '/' + name + '.ppm'
	monitor.command('screendump', {
		'filename': json2.Any(path)
	})!
	image := screenshotcore.read(path)!
	if image.width != 1024 || image.height != 768 { return error('requires 1024x768 framebuffer') }
	stbi.stbi_write_png(work + '/' + name + '.png', image.width, image.height,
		image.channels, image.pixels.data, image.width * image.channels)!
	os.rm(path)!
	return image
}

fn admit_desktop(desktop string, ordinary bool) ! {
	directory := os.dir(desktop)
	path := directory + '/desktop-build.json'
	if !os.is_file(path) {
		if ordinary { return error('ordinary seat requires a frozen desktop-build.json') }
		return
	}
	manifest := json2.decode[map[string]string](os.read_file(path)!)!
	if manifest['vinix-desktop'] != digest(desktop)! {
		return error('desktop build receipt does not match the supplied compositor')
	}
	for name, expected in manifest {
		if name in ['compiler', 'repository-head'] { continue }
		if name.starts_with('/') || '..' in name.split('/') {
			return error('desktop build receipt contains an invalid path')
		}
		input := directory + if name.starts_with('app/') || name == 'vinix-desktop' {
			'/' + name
		} else {
			'/source/' + name
		}
		if digest(input)! != expected {
			return error('desktop source/build input changed after compilation: ' + name)
		}
	}
}

fn healthy(mut child os.Process, log string, deadline u64) !string {
	transcript := os.read_file(log) or { '' }
	if ['SOFTWARE X11 FAIL', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION'].any(transcript.contains(it)) {
		return error('guest failed: ' + log)
	}
	if !child.is_alive() || time.sys_mono_now() >= deadline {
		return error('guest exited or timed out: ' + log)
	}
	return transcript
}

fn check() ! {
	$if prod {} $else { return error('compile native-check with -prod') }
	root := hwhost.find_root(@FILE)!
	if digest(root + '/tests/software-hosted-x11/check.v')! != sha256.hexhash($embed_file('check.v').to_string()) {
		return error('controller source changed after compilation')
	}
	if digest(root + '/tests/software-hosted-x11/proof/admit.v')! != sha256.hexhash(proof.source()) { return error('proof source changed after compilation') }
	mut options := map[string]string{}
	for argument in os.args[1..] {
		if !argument.starts_with('--') || !argument.contains('=') { return error('expected --name=value') }
		name := argument.all_before('=')
		if name !in ['--arch', '--out', '--kernel', '--rootfs', '--desktop', '--stage', '--sysroot', '--userland', '--x11', '--shell'] || name in options || argument.all_after('=') == '' { return error('unknown, duplicate or empty option: ' + name) }
		options[name] = argument.all_after('=')
	}
	arch := options['--arch'] or { 'aarch64' }
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	work := required(options, '--out')!
	if os.exists(work) { return error('output directory already exists') }
	os.mkdir_all(work)!
	host := hwhost.find_host(root, arch, '')!
	kernel := required(options, '--kernel')!
	rootfs := required(options, '--rootfs')!
 desktop := required(options, '--desktop')!
 stage := required(options, '--stage')!
 admit_desktop(desktop, true)!
	sysroot := required(options, '--sysroot')!
	userland := required(options, '--userland')!
	x11 := required(options, '--x11')!
	shell := required(options, '--shell')!
	clang := os.find_abs_path_of_executable(os.getenv_opt('CLANG') or { '/opt/homebrew/opt/llvm/bin/clang' })!
	readelf := os.find_abs_path_of_executable(os.getenv_opt('READELF') or { '/opt/homebrew/opt/llvm/bin/llvm-readelf' })!
	gcc_parent := userland + '/usr/lib/gcc/' + arch + '-alpine-linux-musl'
	mut versions := os.ls(gcc_parent)!
	versions.sort()
	if versions.len == 0 { return error('missing musl compiler runtime') }
	gcc := gcc_parent + '/' + versions.last()
	mut inputs := tree_hashes(root)!
	mut trees := map[string]TreeInput{}
	for name in ['tools/accounts', 'tools/packages', 'build-support/xorg-server', 'build-support/native-compat-tools',
		'tools/qmpclient', 'build-support/screenshotcore', 'tests/hardware-platform/hwhost', 'tests/hardware-platform/plainiso', 'tests/software-hosted-x11/proof'] {
		remember_tree('source:' + name, root + '/' + name, true, mut trees, mut inputs)!
	}
	for name, directory in {'compiler-vlib': os.dir(host.v) + '/vlib', 'compiler-thirdparty': os.dir(host.v) + '/thirdparty',
		'sysroot': sysroot, 'gcc': gcc, 'rootfs': rootfs, 'stage': stage, 'xkb': x11 + '/usr/share/X11/xkb',
		'desktop-sysroot-include': userland + '/usr/include', 'desktop-sysroot-lib': userland + '/usr/lib',
		'desktop-shim': root + '/build-support/aarch64-cc-shim',
		'archived-desktop-source': os.dir(desktop) + '/source', 'archived-stage-source': os.dir(stage) + '/source',
		'clang-resource': os.dir(os.dir(clang)) + '/lib/clang', 'lld-libraries': os.dir(os.dir(os.real_path(os.find_abs_path_of_executable('ld.lld')!))) + '/lib'} {
		remember_tree(name, directory, false, mut trees, mut inputs)!
	}
	assembled := proof.assembled(os.dir(desktop), os.dir(stage), arch, host.v)!
	for _, path in assembled { inputs[path] = digest(path)! }
	for path in [os.executable(), host.v, clang, readelf, kernel, host.qemu, host.firmware,
		os.dir(host.v) + '/vlib/os/execute_capture_nix.h', os.dir(host.v) + '/vlib/sync/thread_helper.h'] {
		inputs[path] = digest(path)!
	}
	if host.firmware_vars != '' { inputs[host.firmware_vars] = digest(host.firmware_vars)! }
	for path in [os.find_abs_path_of_executable('ld.lld')!, os.dir(os.dir(clang)) + '/lib/libclang-cpp.23.1.dylib',
		os.dir(os.dir(clang)) + '/lib/libLLVM.23.1.dylib', '/usr/bin/tar', '/bin/cp', '/bin/sh', root + '/build-support/find-v.sh'] {
		inputs[path] = digest(path)!
	}
	if arch == 'x86_64' { for _, path in plainiso.inputs(root)! { inputs[path] = digest(path)! } }
	for directory in [sysroot + '/usr/include', gcc] {
		for path in os.walk_ext(directory, '') { if os.is_file(path) && !os.is_link(path) { inputs[path] = digest(path)! } }
	}
	for name in ['libc.a', 'crt1.o', 'crti.o', 'crtn.o'] {
		path := sysroot + '/usr/lib/' + name
		inputs[path] = digest(path)!
	}
	source := work + '/source'
	os.mkdir_all(source + '/tools')!
	for name in ['tools/accounts', 'tools/packages'] { invoke(['cp', '-Rp', root + '/' + name, source + '/' + name], work + '/copy-' + os.base(name) + '.log')! }
	for name in ['tools/accounts', 'tools/packages'] { proof.copied_sources(source + '/' + name, trees['source:' + name]!.entries)! }
	for name in ['build-support/xorg-server', 'build-support/native-compat-tools'] {
		os.mkdir_all(source + '/' + os.dir(name))!
		invoke(['cp', '-Rp', root + '/' + name, source + '/' + name], work + '/copy-' + os.base(name) + '.log')!
		proof.copied_sources(source + '/' + name, trees['source:' + name]!.entries)!
	}
	os.cp(root + '/build-support/find-v.sh', source + '/build-support/find-v.sh')!
	os.mkdir_all(source + '/tests/software-hosted-x11/guest')!
	os.cp(root + '/tests/software-hosted-x11/guest/main.v', source + '/tests/software-hosted-x11/guest/main.v')!
	os.cp(root + '/tests/software-hosted-x11/check.v', source + '/tests/software-hosted-x11/check.v')!
	os.write_file(work + '/inputs-before-build.json', json2.encode(inputs))!
	extras := work + '/extras'
	os.mkdir_all(extras)!
	invoke(['cp', '-cRp', rootfs + '/.', extras], work + '/copy-rootfs.log')!
 proof.copied(extras, trees['rootfs']!.entries, true)!
 invoke(['cp', '-cRp', stage + '/.', extras], work + '/copy-stage.log')!
 proof.copied(extras, trees['stage']!.entries, false)!
 os.cp(desktop, extras + '/usr/bin/vinix-desktop')!
 for relative, _ in json2.decode[map[string]string](os.read_file(os.dir(desktop) + '/desktop-build.json')!)! {
  if relative in ['compiler', 'repository-head'] { continue }
  path := os.dir(desktop) + if relative.starts_with('app/') || relative == 'vinix-desktop' { '/' + relative } else { '/source/' + relative }
  inputs[path] = digest(path)!
 }
 inputs[os.dir(desktop) + '/desktop-build.json'] = digest(os.dir(desktop) + '/desktop-build.json')!
 for path in os.walk_ext(stage, '') { if os.is_file(path) && !os.is_link(path) { inputs[path] = digest(path)! } }
 for path in ['/usr/share/vinix-packages/applications.json'] { if os.exists(extras + path) { os.rm(extras + path)! } }
	for path in os.walk_ext(rootfs, '') { if os.is_file(path) && !os.is_link(path) { inputs[path] = digest(path)! } }
	for directory in ['/bin', '/usr/bin', '/usr/sbin', '/usr/lib', '/lib', '/usr/share/vinix/actions', '/usr/share/X11'] { os.mkdir_all(extras + directory)! }
	os.cp(shell, extras + '/bin/sh')!
	inputs[shell] = digest(shell)!
	invoke(['cp', '-Rp', x11 + '/usr/share/X11/xkb', extras + '/usr/share/X11/xkb'], work + '/copy-xkb.log')!
	for path in os.walk_ext(x11 + '/usr/share/X11/xkb', '') { if os.is_file(path) && !os.is_link(path) { inputs[path] = digest(path)! } }
	os.cp(x11 + '/usr/bin/xkbcomp', extras + '/usr/bin/xkbcomp')!
	inputs[x11 + '/usr/bin/xkbcomp'] = digest(x11 + '/usr/bin/xkbcomp')!
	for name in ['account', 'session', 'authd'] {
		binary := build_program(host.v, clang, sysroot, gcc, source, source + '/tools/accounts/' + name + '.v', 'vinix-' + name, arch, work, false)!
		os.cp(binary, extras + '/usr/sbin/vinix-' + name)!
	}
	package := build_program(host.v, clang, sysroot, gcc, source, source + '/tools/packages/main.v', 'vinix-package', arch, work, false)!
	os.cp(package, extras + '/usr/bin/vinix-package')!
	guest := build_program(host.v, clang, sysroot, gcc, source, source + '/tests/software-hosted-x11/guest', 'guest', arch, work, true)!
	bridge := build_bridge(host.v, clang, sysroot, gcc, source, arch, work)!
	os.cp(bridge, extras + '/usr/bin/vinix-wine-host')!
	os.cp(x11 + '/usr/bin/Xvfb', extras + '/usr/bin/Xvfb')!
	inputs[x11 + '/usr/bin/Xvfb'] = digest(x11 + '/usr/bin/Xvfb')!
	for binary in [guest, bridge, x11 + '/usr/bin/Xvfb', x11 + '/usr/bin/xkbcomp', shell] {
		copy_needed(binary, sysroot, extras + '/usr/lib', readelf, work, mut inputs)!
	}
	loader := '/lib/ld-musl-' + arch + '.so.1'
	os.cp(sysroot + loader, extras + loader)!
	inputs[sysroot + loader] = digest(sysroot + loader)!
	if os.exists(extras + '/var/lib/vinix-packages') { os.rmdir_all(extras + '/var/lib/vinix-packages')! }
	os.mkdir_all(extras + '/etc/vinix-packages')!
	publisher := work + '/publisher'
	os.mkdir_all(publisher + '/payload/bin')!
	os.mkdir_all(publisher + '/payload/lib')!
	os.cp(guest, publisher + '/payload/bin/client')!
	os.chmod(publisher + '/payload/bin/client', 0o755)!
	copy_needed(guest, sysroot, publisher + '/payload/lib', readelf, work, mut inputs)!
	key := pkgcore.keygen(publisher + '/seed')!
	manifest := pkgcore.Package{ id: 'org.fixture.x11', version: '1.0.0', architecture: arch,
		name: 'Authenticated X11 fixture', license: 'MIT', kind: 'native', entrypoint: 'bin/client',
		arguments: ['--signed-child'], permissions: ['display', 'files'] }
	os.write_file(publisher + '/manifest.json', json2.encode(manifest))!
	mut packed := pkgcore.pack(publisher + '/manifest.json', publisher + '/payload', publisher + '/repository')!
	packed.close()
	pkgcore.publish(publisher + '/repository', 'trusted', publisher + '/seed', 1, time.now().unix() + 3600)!
	config := pkgcore.Config{ architecture: arch, launch_user: 'alex', policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 },
		repositories: [pkgcore.Repository{ id: 'trusted', url: 'file://' + publisher + '/repository', public_key: key }] }
	os.write_file(extras + '/etc/vinix-packages/config.json', json2.encode(config))!
	service := pkgcore.Service{ root: extras }
	mut catalog := service.refresh()!; catalog.close()
	mut state := service.transact('install', ['org.fixture.x11'], pkgcore.TransactionOptions{})!; state.close()
	os.write_file(extras + '/usr/share/vinix/actions/packages-launch',
		'description=Launch a signed application without account groups\nauth=account\nexec=/usr/sbin/vinix-session\narg=package-launch\ninput=secret\n')!
	// The seed stays in publisher/, outside every guest filesystem and archive.
	os.cp(guest, extras + '/sbin/init')!
	os.chmod(extras + '/sbin/init', 0o755)!
	os.write_file(extras + '/.vinix-image-id', 'vinix-software-hosted-x11-1\n')!
	mut guest_proof := map[string]string{}
	for path in ['/sbin/init', '/usr/bin/vinix-desktop', '/usr/bin/vinix-package',
		'/usr/bin/vinix-sandbox', '/usr/sbin/vinix-account', '/usr/sbin/vinix-authd',
		'/usr/sbin/vinix-session', '/usr/bin/vinix-wine-host', '/usr/bin/Xvfb',
		'/usr/share/vinix/actions/packages-launch', '/etc/vinix-packages/config.json',
		'/var/lib/vinix-packages/generations/1/state.json', '/var/lib/vinix-packages/catalog.json'] {
		guest_proof[path] = digest(extras + path)!
	}
	os.write_file(extras + '/usr/share/software-hosted-x11.json', json2.encode(guest_proof))!
	if !os.is_link(extras + '/usr/bin/vinix-software') || os.readlink(extras + '/usr/bin/vinix-software')! != '/usr/bin/vinix-desktop' {
		return error('staged Software link differs')
	}
	remember_tree('staged', extras, false, mut trees, mut inputs)!
	for path in os.walk_ext(work, '') {
		if os.is_file(path) && !os.is_link(path) && !path.starts_with(work + '/publisher/') &&
			(!path.ends_with('.json') || path.ends_with('.argv.json')) { inputs[path] = digest(path)! }
	}
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	os.write_file(work + '/system.vjfs', '')!
	os.truncate(work + '/system.vjfs', u64(4096) << 20)!
	os.setenv('COPYFILE_DISABLE', '1', true)
	invoke(['tar', '--format=ustar', '-cf', work + '/initramfs.tar', '-C', extras, '.'], work + '/tar.log')!
	runtime_host := if arch == 'x86_64' { hwhost.Host{ ...host, root: plainiso.prepare(root, work)! } } else { host }
	media := hwhost.boot_media(runtime_host, kernel, work + '/initramfs.tar', 'quiet vinix.disk=auto', work)!
	qmp := '/tmp/vinix-software-x11-' + os.getpid().str() + '.qmp'
	mut arguments := if arch == 'aarch64' {
		['-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-device', 'ramfb',
			'-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device']
	} else {
		['-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-vga', 'std',
			'-device', 'qemu-xhci,id=gui-input', '-device', 'usb-kbd,bus=gui-input.0',
			'-device', 'usb-tablet,bus=gui-input.0']
	}
	arguments << ['-m', if arch == 'aarch64' { '2048' } else { '1024' }, '-smp', '2', ...media,
		'-display', 'none', '-qmp', 'unix:' + qmp + ',server=on,wait=off', '-no-reboot',
		'-qmp', 'unix:' + qmp + '.power,server=on,wait=off', '-nic', 'none']
	arguments << if arch == 'aarch64' {
		['-drive', 'if=none,id=system,format=raw,cache=writeback,file=' + work + '/system.vjfs',
			'-device', 'virtio-blk-device,drive=system']
	} else { ['-drive', 'if=ide,format=raw,cache=writeback,file=' + work + '/system.vjfs'] }
	os.write_file(work + '/qemu-arguments.json', json2.encode(arguments))!
	verify(inputs)!
	verify_trees(trees)!
	graphical_boot(host.qemu, arguments, qmp, work, arch)!
	verify(inputs)!
	verify_trees(trees)!
	admit_desktop(desktop, true)!
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	mut outputs := map[string]string{}
	for directory in ['build-vinix-account', 'build-vinix-session', 'build-vinix-authd', 'build-vinix-package', 'build-guest', 'build-bridge'] {
		for path in os.walk_ext(work + '/' + directory, '') { if os.is_file(path) && !os.is_link(path) { outputs[path[work.len + 1..]] = digest(path)! } }
	}
	for name in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json'] { outputs[name] = digest(work + '/' + name)! }
	for name in ['serial.log', 'shutdown-1.jsonl', 'qemu-exit.json', 'system.vjfs', 'initramfs.tar', 'qemu-arguments.json',
		'01-catalog.png', '02-painted.png', '03-pointer.png', '04-closed.png',
		'extras/usr/share/software-hosted-x11.json', 'extras/etc/vinix-packages/config.json',
		'extras/sbin/init', 'publisher/manifest.json', 'publisher/repository/index.json',
		'publisher/repository/index.sig'] {
		outputs[name] = digest(work + '/' + name)!
	}
	if arch == 'x86_64' { outputs['test.iso'] = digest(work + '/test.iso')! }
	os.write_file(work + '/qualification.json', json2.encode(Qualification{
		architecture: arch, desktop: desktop, desktop_receipt: os.dir(desktop) + '/desktop-build.json',
		inputs: inputs, outputs: outputs, trees: trees, passed: true}))!
	println('SOFTWARE HOSTED X11 PASS ' + arch + ': ' + work)
}

struct Qualification {
	format int = 1
	architecture string
	desktop string
	desktop_receipt string
	inputs map[string]string
	outputs map[string]string
	trees map[string]TreeInput
	passed bool
}

fn wait_marker(mut child os.Process, log string, deadline u64, marker string) ! {
	for {
		if healthy(mut child, log, deadline)!.contains(marker) { return }
		time.sleep(100 * time.millisecond)
	}
}

fn color_count(image screenshotcore.Image, red u8, green u8, blue u8) int {
	mut count := 0
	for i := 0; i + 2 < image.pixels.len; i += image.channels {
		if image.pixels[i] == red && image.pixels[i + 1] == green && image.pixels[i + 2] == blue { count++ }
	}
	return count
}

fn wait_paint(mut child os.Process, mut monitor qmpclient.Monitor, log string, deadline u64,
	work string, name string, blue bool) ! {
	point(mut monitor, 800, 650)!
	for {
		healthy(mut child, log, deadline)!
		image := shot(mut monitor, work, name)!
		if color_count(image, 0x21, 0x6a, 0x43) > 1000 && color_count(image,
			if blue { u8(0x54) } else { u8(0xb6) }, if blue { u8(0x68) } else { u8(0x42) },
			if blue { u8(0xc9) } else { u8(0x6f) }) > 1000 { return }
		time.sleep(200 * time.millisecond)
	}
}

fn graphical_boot(qemu string, arguments []string, qmp string, work string, arch string) ! {
	log := work + '/serial.log'
	mut child := os.new_process(qemu)
	defer {
		if child.is_alive() { child.signal_kill(); child.wait() }
		child.close()
		os.rm(qmp) or {}; os.rm(qmp + '.power') or {}
	}
	child.set_args([...arguments, '-serial', 'file:' + log])
	child.run()
	deadline := u64(time.sys_mono_now() + 1200 * time.second)
	wait_marker(mut child, log, deadline, 'SOFTWARE X11 START')!
	mut monitor := qmpclient.connect_bounded(qmp, deadline, unsafe { nil })!
	defer { monitor.close() }
	mut shutdown_log := os.create(work + '/shutdown-1.jsonl')!
	defer { shutdown_log.close() }
	mut shutdown := shutdown_connect(qmp + '.power', mut shutdown_log, deadline, 1)!
	defer { shutdown.close() or {} }
	wait_marker(mut child, log, deadline, 'SOFTWARE X11 ordinary-compositor uid=1000 home=/home/alex PASS')!
	wait_marker(mut child, log, deadline, 'vinix-desktop: ready')!
	time.sleep(2 * time.second)
	shot(mut monitor, work, '01-catalog')!
	click(mut monitor, 984, 57)!
	click(mut monitor, 140, 138)!
	click(mut monitor, 930, 94)!
	wait_marker(mut child, log, deadline, 'SOFTWARE X11 painted-client ready PASS')!
	wait_paint(mut child, mut monitor, log, deadline, work, '02-painted', false)!
	click(mut monitor, 200, 200)!
	wait_marker(mut child, log, deadline, 'SOFTWARE X11 actual-pointer ButtonPress repainted lease-held PASS')!
	wait_paint(mut child, mut monitor, log, deadline, work, '03-pointer', true)!
	click(mut monitor, 1008, 10)!
	wait_marker(mut child, log, deadline, 'SOFTWARE X11 UI-close bridge+Xvfb reaped authority+socket removed live-child-lease-held PASS')!
	point(mut monitor, 800, 650)!
	image := shot(mut monitor, work, '04-closed')!
	if color_count(image, 0x54, 0x68, 0xc9) > 1000 || color_count(image, 0x21, 0x6a, 0x43) > 1000 {
		return error('closed Software window retained the X11 surface')
	}
	shutdown_event(mut shutdown, mut shutdown_log, deadline)!
	for child.is_alive() {
		text := os.read_file(log) or { '' }
		if text.contains('SOFTWARE X11 FAIL') || u64(time.sys_mono_now()) >= deadline {
			return error('guest did not finish shutdown')
		}
		time.sleep(100 * time.millisecond)
	}
	child.wait()
	text := os.read_file(log)!
	if child.code != 0 || !text.contains('SOFTWARE X11 INSTALLED signed-launch painted pointer close-reap lease-lifecycle PASS') ||
		!text.contains('SOFTWARE X11 natural-child-exit actual-reap lease-released PASS') ||
		(arch == 'aarch64' && !text.contains('syspower: power off: stopping devices')) {
		return error('actual guest poweroff/exit0 or terminal markers missing')
	}
	os.write_file(work + '/qemu-exit.json', '{"exit_code":0,"reaped":true,"guest_shutdown":true}\n')!
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	check() or { eprintln(err); exit(1) }
}
