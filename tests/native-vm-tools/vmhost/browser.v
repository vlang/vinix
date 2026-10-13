// SPDX-License-Identifier: GPL-2.0-or-later
module vmhost

import cachecli
import cachekey
import gamehost
import math
import net
import os
import perfreport
import sourcecommand
import strconv
import time

pub struct BrowserProfile {
pub:
	name     string
	init     string
	pass     string
	failures []string
	features []string
	persist  string = '256'
}

pub fn browser_profile(name string) !BrowserProfile {
	return match name {
		'chromium' {
			BrowserProfile{
				name:     name
				init:     'tests/browsers/chromium-init.sh'
				pass:     'VINIX CHROMIUM TEST: PASS'
				failures: ['VINIX CHROMIUM TEST: FAIL']
				features: [
					'VINIX CHROMIUM PASS: version',
					'VINIX CHROMIUM PASS: the hosted display has a framebuffer',
					'VINIX CHROMIUM PASS: browser window mapped',
					'VINIX CHROMIUM PASS: the bridge reports drawing',
				]
			}
		}
		'firefox' {
			BrowserProfile{
				name:     name
				init:     'tests/browsers/firefox-init.sh'
				pass:     'VINIX FIREFOX TEST: PASS'
				failures: ['VINIX FIREFOX TEST: FAIL']
				features: [
					'VINIX FIREFOX PASS: the hosted display has a framebuffer',
					'VINIX FIREFOX PASS: browser window mapped',
					'VINIX FIREFOX PASS: the page was drawn',
				]
			}
		}
		'desktop' {
			BrowserProfile{
				name:     name
				init:     'tests/browsers/desktop-init.sh'
				pass:     'VINIX DESKTOP FIREFOX TEST: PASS'
				failures: ['VINIX DESKTOP FIREFOX TEST: FAIL']
				features: [
					'VINIX DESKTOP FIREFOX PASS: the hosted display has a framebuffer',
					'VINIX DESKTOP FIREFOX PASS: browser window mapped',
					'VINIX DESKTOP FIREFOX PASS: the page was drawn',
				]
			}
		}
		'libreoffice' {
			BrowserProfile{
				name:     name
				init:     'tests/office/libreoffice-init.sh'
				pass:     'VINIX LIBREOFFICE TEST: PASS'
				failures: ['VINIX LIBREOFFICE TEST: FAIL']
				features: [
					'VINIX LIBREOFFICE PASS: the hosted display has a framebuffer',
					'VINIX LIBREOFFICE PASS: Writer window mapped',
					'VINIX LIBREOFFICE PASS: the document was drawn',
				]
			}
		}
		'package' {
			BrowserProfile{
				name:     name
				init:     'tests/browsers/pkg-init.sh'
				pass:     'VINIX CHROMIUM PACKAGE TEST: PASS'
				failures: ['VINIX CHROMIUM PACKAGE TEST: FAIL']
				features: [
					'VINIX CHROMIUM PASS: the image ships the launcher but not the browser',
					'VINIX CHROMIUM PASS: pkg installed Chromium and its runtime',
					'VINIX CHROMIUM PASS: the installed browser runs',
				]
			}
		}
		'first-run' {
			BrowserProfile{
				name:     name
				init:     'tests/desktop/first-run-apps-init.sh'
				pass:     'VINIX FIRST RUN TEST: PASS'
				failures: ['VINIX FIRST RUN TEST: FAIL']
				features: [
					'VINIX FIRST RUN PASS: registration created the user',
					'VINIX FIRST RUN PASS: the app picker follows registration',
					'VINIX FIRST RUN PASS: the picker finished and the desktop started',
					'VINIX FIRST RUN PASS: the Terminal installed the chosen apps',
				]
			}
		}
		'steam' {
			BrowserProfile{
				name:     name
				init:     'tests/steam/steam-init.sh'
				pass:     'VINIX STEAM TEST: PASS'
				failures: ['VINIX STEAM TEST: FAIL']
				features: [
					'VINIX STEAM PASS: translated glibc runtime',
					'VINIX STEAM PASS: System V semaphore wake',
					'VINIX STEAM PASS: the hosted display has a framebuffer',
					'VINIX STEAM PASS: client window mapped',
				]
				persist:  '12288'
			}
		}
		else { return error('unknown hosted application profile') }
	}
}

pub struct BrowserOptions {
pub:
	profile BrowserProfile
	guest   string
	image   string
	state   string
	memory  string
	timeout string
	build   bool
}

pub fn browser_options(root string, argv []string) !BrowserOptions {
	args := cachecli.arguments(argv, ['--init', '--initramfs', '--state-dir', '--mem', '--timeout'], [], [
		'--firefox',
		'--desktop',
		'--package',
		'--libreoffice',
		'--first-run',
		'--steam',
		'--build',
	], 0, 0, 'Boot and enforce the hosted application result.\nUsage: run_vm [--firefox|--desktop|--package|--libreoffice|--first-run|--steam] [--init FILE --initramfs TAR --state-dir DIR --mem MB --timeout SECONDS --build]') or { return error_with_code(err.msg(), 2) }
	names := ['firefox', 'desktop', 'package', 'libreoffice', 'first-run', 'steam'].filter('--' + it in args.options)
	if names.len > 1 { return error_with_code('hosted application profiles cannot be combined', 2) }
	profile := browser_profile(if names.len == 0 { 'chromium' } else { names[0] })!
	timeout := perfreport.integer_text(args.value('--timeout', '0')) or { return error_with_code(err.msg(), 2) }
	if timeout.starts_with('-') { return error_with_code('--timeout must be positive', 2) }
	memory := perfreport.integer_text(args.value('--mem', if profile.name == 'steam' {
		'32768'
	} else {
		'8192'
	})) or { return error_with_code(err.msg(), 2) }
	return BrowserOptions{profile, cachekey.resolve_path(args.value('--init', root + '/' + profile.init))!, cachekey.resolve_path(args.value('--initramfs', root + '/build-support/init-aarch64/initramfs-desktop.tar'))!, cachekey.resolve_path(args.value('--state-dir', root + '/build/browser-vm'))!, memory, if timeout == '0' {
		if profile.name == 'package' { '5400' } else { '1800' }
	} else {
		timeout
	}, '--build' in args.options}
}

pub struct Launch {
pub:
	command     []string
	environment map[string]string
	directory   string
}

pub fn browser_launch(root string, options BrowserOptions, environment map[string]string, system string, port string) Launch {
	mut env := environment.clone()
	env['VINIX_INITRAMFS'] = options.image
	env['VINIX_INITRAMFS_COMPRESSED'] = if options.image.ends_with('.gz') { '1' } else { '0' }
	for pair in [['VINIX_BOOT_DISK', 'boot.img'], ['VINIX_EFIVARS', 'efivars.fd'],
		['VINIX_QEMU_PACKAGE_STORE', 'packages.tar'], ['VINIX_QEMU_PERSIST_DISK', 'root.ext2']] {
		env[pair[0]] = options.state + '/' + pair[1]
	}
	env['VINIX_QEMU_PERSIST_SIZE_MB'] = options.profile.persist
	env.delete('VINIX_QEMU_PERSIST')
	env['VINIX_KEEP_TEMP_BOOT_DISK'] = '1'
	if 'VINIX_QEMU_PACKAGE_STORE_PORT' !in env { env['VINIX_QEMU_PACKAGE_STORE_PORT'] = port }
	if 'VINIX_QEMU_PACKAGE_PERSIST' !in env { env['VINIX_QEMU_PACKAGE_PERSIST'] = '0' }
	if system != 'Darwin' && 'USE_TCG' !in env { env['USE_TCG'] = '1' }
	mut command := [root + '/scripts/run-aarch64.sh']
	if !options.build { command << '--no-build' }
	command << ['--serial', '--mem=' + options.memory, '--guest-init=' + options.guest]
	return Launch{command, env, root}
}

pub struct BrowserResult {
pub:
	bytes    []u8
	observed sourcecommand.ChildExit
	forced   bool
}

fn now() f64 { return f64(time.sys_mono_now()) / f64(time.second) }

fn browser_drive(child &sourcecommand.PtyChild, profile BrowserProfile, seconds f64, inherit bool, mut bytes []u8) !sourcecommand.ChildExit {
	if math.is_inf(seconds, 0) { return error('int too large to convert to float') }
	mut deadline := now() + seconds
	mut shutting_down := false
	mut buffer := []u8{len: 65536}
	for now() < deadline {
		cachecli.checkpoint()!
		observed := child.poll()!
		if observed.exited { return observed }
		count := child.read(mut buffer, 250)!
		if count > 0 {
			bytes << buffer[..count]
			if inherit {
				mut output := os.stdout()
				unsafe { output.write_full_buffer(buffer.data, usize(count))! }
				output.flush()
			}
		}
		recent := bytes[if bytes.len > 131072 { bytes.len - 131072 } else { 0 }..].bytestr()
		if !shutting_down && (recent.contains(profile.pass) || [...profile.failures, 'FATAL EXCEPTION',
			'KERNEL PANIC'].any(recent.contains(it))) {
			child.write([u8(1), `x`]) or { if err.code() != C.EIO { return err } }
			shutting_down = true
			limit := now() + 10
			if limit < deadline { deadline = limit }
		}
		if count == 0 { time.sleep(time.millisecond) }
	}
	return child.poll()!
}

fn browser_stop(child &sourcecommand.PtyChild) ! {
	child.write([u8(1), `x`]) or {}
	if child.settle(5)! { return }
	child.signal(C.SIGTERM)!
	if child.settle(2)! { return }
	child.signal(C.SIGKILL)!
	child.settle(2)!
}

pub fn browser_capture(launch Launch, profile BrowserProfile, seconds f64, inherit bool) !BrowserResult {
	mut child := sourcecommand.spawn_pty(launch.command, launch.environment, launch.directory)!
	defer { child.close() or {} }
	mut bytes := []u8{}
	mut cause := IError(none)
	mut failed := false
	observed := browser_drive(&child, profile, seconds, inherit, mut bytes) or {
		failed = true
		cause = err
		sourcecommand.ChildExit{}
	}
	previous_int := unsafe { C.signal(C.SIGINT, C.SIG_IGN) }
	previous_term := unsafe { C.signal(C.SIGTERM, C.SIG_IGN) }
	defer {
		unsafe {
			C.signal(C.SIGINT, previous_int)
			C.signal(C.SIGTERM, previous_term)
		}
	}
	forced := !observed.exited
	if forced { browser_stop(&child)! }
	child.close()!
	if failed { return cause }
	return BrowserResult{bytes, observed, forced}
}

pub fn browser_failures(profile BrowserProfile, result BrowserResult) []string {
	output := result.bytes.bytestr()
	mut failures := []string{}
	for marker in [...profile.features, profile.pass] {
		if !output.contains(marker) {
			failures << 'ERROR: missing expected browser result: ' + marker
		}
	}
	for marker in [...profile.failures, 'FATAL EXCEPTION', 'KERNEL PANIC'] {
		if output.contains(marker) { failures << 'ERROR: observed browser failure: ' + marker }
	}
	if result.observed.exited && result.observed.return_code != 0 {
		code := result.observed.return_code
		failures << 'ERROR: observed browser failure: VM runner exit status ' + (if code < 0 {
			128 - code
		} else {
			code
		}).str()
	}
	if result.forced {
		failures << 'ERROR: observed browser failure: VM did not exit after the test'
	}
	return failures
}

pub fn browser_cli(root string, argv []string) !int {
	options := browser_options(root, argv)!
	gamehost.mkdir(options.state)!
	port := available_port()!
	launch := browser_launch(root, options, os.environ(), os.uname().sysname, port)
	println('==> Starting AArch64 QEMU browser boot')
	seconds := strconv.atof64(options.timeout, allow_overflow: true)!
	result := browser_capture(launch, options.profile, seconds, true)!
	failures := browser_failures(options.profile, result)
	for failure in failures { eprintln(failure) }
	if failures.len > 0 { return 1 }
	println('==> AArch64 QEMU browser boot passed')
	return 0
}

pub fn available_port() !string {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	return listener.addr()!.port()!.str()
}
