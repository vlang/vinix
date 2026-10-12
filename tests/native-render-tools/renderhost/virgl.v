// SPDX-License-Identifier: GPL-2.0-or-later
module renderhost

import cachecli
import cachekey
import gamehost
import math
import os
import perfreport
import sourcecommand
import strconv
import time

pub const desktop_stages = ['entered main', 'using captured arguments without slicing',
	'command line parsed', 'first frame ready; entering graphics mode', 'first canvas presented']

pub fn virgl_line(text string, desktop bool, failed bool) bool {
	marker := (if desktop { 'VINIX_GPU_DESKTOP_VM_' } else { 'VINIX_VIRGL_VM_' }) + if failed {
		'FAIL:'
	} else {
		'PASS'
	}
	mut cursor := 0
	for cursor <= text.len - marker.len {
		found := text[cursor..].index(marker) or { return false }
		at := cursor + found
		cursor = at + marker.len
		if at != 0 && text[at - 1] != `\n` { continue }
		mut end := cursor
		if failed {
			for end < text.len && text[end].is_digit() { end++ }
			if end == cursor { continue }
		}
		if !desktop { return true }
		for end < text.len && text[end] == `\r` { end++ }
		if end == text.len || text[end] == `\n` { return true }
	}
	return false
}

fn renderer(output string, desktop bool) bool {
	prefix := if desktop { 'vinix-desktop: gpu presentation enabled on ' } else { 'gl_renderer=' }
	for line in output.replace('\r', '\n').split('\n') {
		lower := ascii_lower(line)
		if lower.contains(prefix) && lower.all_after(prefix).contains('virgl') && lower.all_after(prefix).all_after('virgl').contains('apple') {
			return true
		}
	}
	return false
}

fn ascii_lower(text string) string {
	mut bytes := text.bytes()
	for i, ch in bytes { if ch >= `A` && ch <= `Z` { bytes[i] = ch + 32 } }
	return bytes.bytestr()
}

pub fn virgl_missing(output string, desktop bool, passed bool, failed bool, forced bool, exited bool, status int) []string {
	mut missing := []string{}
	if output.count('smp: 4 CPUs online') != 1 { missing << 'exactly four QEMU CPUs online' }
	if desktop {
		if !renderer(output, true) {
			missing << 'desktop VirGL renderer backed by an Apple host GPU'
		}
		for stage in desktop_stages {
			if !output.contains('vinix-desktop: GPU init: ' + stage) {
				missing << 'desktop stage ' + perfreport.quoted(stage)
			}
		}
		if !output.contains('vinix-desktop: ready') { missing << 'desktop ready marker' }
	} else {
		if output.count('VINIX_VIRGL_NETWORK_PASS') != 1 {
			missing << 'DHCP and package server connectivity'
		}
		if !renderer(output, false) { missing << 'VirGL renderer backed by an Apple host GPU' }
		if output.count('gl-triangle-agx: hardware frame rendered successfully') != 1 {
			missing << 'validated rendered pixels'
		}
		if output.count('VINIX VIRGL RENDER TEST: PASS') != 1 {
			missing << 'in-guest VirGL PASS marker'
		}
	}
	if output.contains('VINIX M1 AGX RENDER TEST: PASS') {
		missing << 'VM incorrectly claimed a native M1 AGX pass'
	}
	if !passed { missing << 'guest test-init PASS marker' }
	if failed { missing << 'guest test-init reported failure' }
	if forced { missing << 'VM did not exit after the result' }
	if exited && status != 0 {
		missing << 'VM exit status ' + (if status < 0 { 128 - status } else { status }).str()
	}
	if missing.len > 0 && desktop {
		mut last := ''
		for line in output.replace('\r', '\n').split('\n') {
			if line.contains('vinix-desktop: GPU init: ') && line.all_after('vinix-desktop: GPU init: ') != '' {
				last = line.all_after('vinix-desktop: GPU init: ')
			}
		}
		if last != '' {
			missing << 'last desktop stage ' + perfreport.quoted(gamehost.decode_utf8(last.bytes()))
		}
	}
	return missing
}

pub struct VirglLaunch {
pub:
	command     []string
	environment map[string]string
	desktop     bool
}

pub fn virgl_launch(root string, qemu string, image string, guest string, desktop bool, scratch string, environment map[string]string) VirglLaunch {
	mut env := environment.clone()
	env['VINIX_VIRGL_QEMU'] = qemu
	env['TMPDIR'] = scratch
	for name in ['QEMU_DISPLAY_BACKEND', 'VINIX_QEMU_PERSIST', 'VINIX_QEMU_PERSIST_DISK',
		'VINIX_QEMU_PERSIST_SEED', 'VINIX_QEMU_PERSIST_SIZE_MB', 'VINIX_QEMU_ROOT_DISK',
		'VINIX_QEMU_ROOT_IMAGE', 'VINIX_BOOT_DISK', 'VINIX_EFIVARS', 'VINIX_QEMU_PACKAGE_STORE'] {
		env.delete(name)
	}
	if 'VINIX_QEMU_MEM' !in env { env['VINIX_QEMU_MEM'] = if desktop { '12288' } else { '8192' } }
	mut command := if desktop {
		[root + '/scripts/run-desktop-aarch64.sh', '--no-build', '--no-disk-root', '--ephemeral',
			'gpuvm']
	} else {
		[root + '/scripts/run-aarch64.sh', '--no-build', '--no-persist', '--ephemeral', '--virgl']
	}
	if !desktop { env['VINIX_INITRAMFS'] = image }
	command << '--guest-init=' + guest
	return VirglLaunch{command, env, desktop}
}

pub fn virgl_prepare(tools Tools, desktop bool, machine string, system string) !VirglLaunch {
	if system != 'Darwin' || machine != 'arm64' {
		return error_with_code('this test requires an Apple-silicon macOS host', 2)
	}
	override := os.getenv_opt('VINIX_VIRGL_QEMU') or { '' }
	qemu := if override != '' {
		cachekey.resolve_path(cachekey.expand_user(override)!)!
	} else {
		gamehost.parent(tools.root) + '/kekvm/.tools/qemu-virgl/bin/kekvm-qemu-system-aarch64'
	}
	info := os.stat(qemu) or { return error_with_code("KekVM's VirGL QEMU is missing: " + qemu + '\nRun `make setup-gpu` in ~/code/kekvm first.', 2) }
	if info.get_filetype() != .regular || C.access(qemu.str, C.X_OK) != 0 {
		return error_with_code("KekVM's VirGL QEMU is missing: " + qemu + '\nRun `make setup-gpu` in ~/code/kekvm first.', 2)
	}
	devices := tools.command([qemu, '-device', 'help'], os.environ())!
	if devices.status != 0 || !devices.stdout.contains('virtio-gpu-gl-device') {
		return error_with_code('KekVM QEMU has no MMIO virtio-gpu-gl-device', 2)
	}
	image := tools.root + '/build-support/init-aarch64/' + if desktop {
		'initramfs-desktop.tar'
	} else {
		'initramfs.tar'
	}
	for i, path in [tools.root + '/kernel/bin/vinix', image] {
		label := ['kernel', 'initramfs'][i]
		regular := if state := os.stat(path) { state.get_filetype() == .regular } else { false }
		if !regular {
			return error_with_code('Vinix ' + label + ' is missing: ' + path, 2)
		}
	}
	println('Host transport: ' + qemu)
	println('Path: Vinix VirtIO-GPU -> VirGL -> virglrenderer -> host Apple GPU')
	println('Boundary: this does not emulate native AGX RTKit/UAT/firmware')
	if desktop { println('Workload: full vinix-desktop-gpu startup through its first frame') }
	guest := tools.root + '/tests/virtio-gpu-virgl/' + if desktop {
		'desktop-guest-init.sh'
	} else {
		'guest-init.sh'
	}
	return virgl_launch(tools.root, qemu, image, guest, desktop, '', os.environ())
}

fn virgl_now() f64 { return f64(time.sys_mono_now()) / f64(time.second) }

pub fn virgl_capture(launch VirglLaunch, directory string, timeout f64, inherit bool) !(int, string) {
	mut child := sourcecommand.spawn_pty(launch.command, launch.environment, directory)!
	defer { child.close() or {} }
	mut state := VirglState{}
	mut failed_capture := false
	mut capture_error := IError(none)
	virgl_drive(&child, launch.desktop, timeout, inherit, mut state) or {
		failed_capture = true
		capture_error = err
	}
	// Complete finally's original shutdown sequence before returning an error.
	// Further signals cannot abandon the privately owned child during retirement.
	previous_int := unsafe { C.signal(C.SIGINT, C.SIG_IGN) }
	previous_term := unsafe { C.signal(C.SIGTERM, C.SIG_IGN) }
	defer {
		unsafe {
			C.signal(C.SIGINT, previous_int)
			C.signal(C.SIGTERM, previous_term)
		}
	}
	forced := !state.observed.exited
	if forced { virgl_stop(&child)! }
	child.close()!
	if failed_capture { return capture_error }
	output := state.bytes.bytestr()
	missing := virgl_missing(output, launch.desktop, state.passed, state.failed, forced, state.observed.exited, state.observed.return_code)
	if missing.len > 0 {
		eprintln('\nFAIL KekVM ' + if launch.desktop {
			'GPU desktop startup'
		} else {
			'VirGL smoke test'
		} + ': ' + missing.join(', '))
		return 1, output
	}
	println(if launch.desktop {
		'\nPASS Vinix GPU desktop reached its first presented frame in KekVM'
	} else {
		'\nPASS Vinix rendered validated pixels through KekVM and the host Apple GPU'
	})
	println('NOTE native Apple AGX firmware execution remains a physical-hardware test')
	return 0, output
}

struct VirglState {
mut:
	bytes    []u8
	passed   bool
	failed   bool
	shutdown bool
	observed sourcecommand.ChildExit
}

fn virgl_drive(child &sourcecommand.PtyChild, desktop bool, timeout f64, inherit bool, mut state VirglState) ! {
	if math.is_inf(timeout, 0) { return error('int too large to convert to float') }
	mut deadline := virgl_now() + timeout
	mut buffer := []u8{len: 65536}
	for virgl_now() < deadline {
		cachecli.checkpoint()!
		state.observed = child.poll()!
		if state.observed.exited { break }
		count := child.read(mut buffer, 250)!
		if count > 0 {
			state.bytes << buffer[..count]
			if inherit {
				mut out := os.stdout()
				unsafe { out.write_full_buffer(buffer.data, usize(count))! }
				out.flush()
			}
			text := state.bytes[if state.bytes.len > 131072 { state.bytes.len - 131072 } else { 0 }..].bytestr()
			state.passed = state.passed || virgl_line(text, desktop, false)
			state.failed = state.failed || virgl_line(text, desktop, true)
			if (state.passed || state.failed) && !state.shutdown {
				child.write([u8(1), `x`])!
				state.shutdown = true
				limit := virgl_now() + 10
				if limit < deadline { deadline = limit }
			}
		} else if count == 0 {
			time.sleep(time.millisecond)
		}
	}
	if !state.observed.exited { state.observed = child.poll()! }
}

fn virgl_stop(child &sourcecommand.PtyChild) ! {
	child.write([u8(1), `x`]) or {}
	if !child.settle(5)! {
		child.signal(C.SIGTERM)!
		if !child.settle(2)! {
			child.signal(C.SIGKILL)!
			child.settle(2)!
		}
	}
}

pub fn virgl_cli(tools Tools, argv []string) !int {
	args := cachecli.arguments(argv, ['--timeout'], [], ['--desktop-startup'], 0, 0, 'Render through the VirtIO/VirGL host GPU backend.\nUsage: run_vm [--timeout 900 --desktop-startup]') or { return error_with_code(err.msg(), 2) }
	timeout_text := perfreport.integer_text(args.value('--timeout', os.getenv_opt('VINIX_VIRGL_VM_TIMEOUT') or { '900' })) or { return error_with_code(err.msg(), 2) }
	if timeout_text == '0' || timeout_text.starts_with('-') {
		return error_with_code('--timeout must be positive', 2)
	}
	timeout := strconv.atof64(timeout_text, allow_overflow: true) or { return error_with_code(err.msg(), 2) }
	prepared := virgl_prepare(tools, '--desktop-startup' in args.options, os.uname().machine, $if darwin { 'Darwin' } $else { os.user_os() }) or {
		eprintln('ERROR: ' + err.msg())
		return if err.code() == 2 { 2 } else { 1 }
	}
	scratch := sourcecommand.temporary('vinix-virgl-vm')!
	defer { gamehost.remove(scratch) or {} }
	launch := virgl_launch(tools.root, prepared.environment['VINIX_VIRGL_QEMU'], prepared.environment['VINIX_INITRAMFS'],
		tools.root + '/tests/virtio-gpu-virgl/' + if prepared.desktop {
			'desktop-guest-init.sh'
		} else {
			'guest-init.sh'
		}, prepared.desktop, scratch, prepared.environment)
	status, _ := virgl_capture(launch, tools.root, f64(timeout), true)!
	return status
}
