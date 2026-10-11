// SPDX-License-Identifier: GPL-2.0-only
@[has_globals]
module applehost

import fixturehost
import guesthost
import hosttest
import os
import policyhost
import strconv

#include <signal.h>
#include <stdlib.h>

fn C.signal(i32, voidptr) voidptr
fn C.mkdtemp(&char) &char
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32

__global apple_suite_interrupted i32

fn apple_suite_signal(_signal i32) {
	unsafe { C.__atomic_store_n(&apple_suite_interrupted, i32(1), C.__ATOMIC_RELAXED) }
}

fn apple_suite_cancelled() bool {
	return unsafe { C.__atomic_load_n(&apple_suite_interrupted, C.__ATOMIC_RELAXED) } != 0
}

pub struct Runtime {
pub:
	options     map[string]string
	root        string
	work        string
	host_arch   string
	caller_arch string
	arch        string
	kernel      string
	guest       string
	build_only  bool
	timeout     string
	owned       bool
	previous    voidptr
}

// All former frontends used /tmp explicitly, regardless of TMPDIR. An explicit
// state directory must be fresh and remains available after success or failure.
fn private_work(prefix string) !string {
	return private_work_in('/tmp', prefix)!
}

fn private_work_in(base string, prefix string) !string {
	mut pattern := (base.trim_right('/') + '/' + prefix + 'XXXXXX\x00').bytes()
	result := unsafe { C.mkdtemp(&char(pattern.data)) }
	if result == unsafe { nil } { return error('Cannot create private Apple test directory') }
	return unsafe { result.vstring().clone() }
}

fn temporary_work(prefix string) !string {
	// Hotplug's original tempfile owner honours the caller's temporary base.
	// Try writable candidates in order instead of os.temp_dir's cached value.
	mut bases := ['TMPDIR', 'TEMP', 'TMP'].map(os.getenv(it)).filter(it != '')
	bases << ['/tmp', '/var/tmp', '/usr/tmp', os.getwd()]
	for base in bases {
		resolved := hosttest.module_resolve(base) or { continue }
		if path := private_work_in(resolved, prefix) { return path }
	}
	return error('Cannot create private hotplug temporary directory')
}

pub struct FrontendError {
pub:
	message string
}

pub fn (failure FrontendError) msg() string { return failure.message }

pub fn (failure FrontendError) code() int { return 2 }

pub fn runtime(family string, args []string) !Runtime {
	mut specs := [hosttest.Option{'--state-dir', true, []},
		hosttest.Option{'--arch', true, ['aarch64', 'x86_64']},
		hosttest.Option{'--build-only', false, []}, hosttest.Option{'--kernel-dir', true, []},
		hosttest.Option{'--guest-state-dir', true, []}]
	if family != 'ans' { specs << hosttest.Option{'--host-arch', true, ['arm64', 'amd64']} }
	if family == 'wifi-control' { specs << hosttest.Option{'--vm', false, []} }
	if family == 'hotplug' { specs << hosttest.Option{'--original-reference', true, []} }
	if family == 'ans' { specs << hosttest.Option{'--fixture', true, ['ext2', 'ans']} }
	if family == 'spi' {
		specs << hosttest.Option{'--suite', true, ['keyboard', 'touchpad', 'both']}
	}
	if family in ['wifi-control', 'wifi-helpers'] {
		specs << hosttest.Option{'--timeout', true, []}
	}
	if family == 'wifi-helpers' {
		specs << [hosttest.Option{'--provider-source', true, []},
			hosttest.Option{'--provider-header', true, []}]
	}
	parsed := hosttest.parse_arguments(args, specs, 0, 'Native V ' + family + ' tests',
		'--state-dir PATH retains fresh artifacts; --host-arch arm64|amd64\n' +
			'--arch aarch64|x86_64 requires --kernel-dir PATH and --guest-state-dir PATH\n' +
			'--build-only stops after strict native objects and ELF') or { return FrontendError{err.msg()} }
	mut values := parsed.options.clone()
	// Path('') names the current directory; an omitted path owns a temporary.
	for name in ['--state-dir', '--kernel-dir', '--guest-state-dir', '--provider-source', '--provider-header', '--original-reference'] {
		if name in values && values[name] == '' { values[name] = '.' }
	}
	arch := values['--arch']
	if '--vm' in values {
		for name in ['--arch', '--kernel-dir', '--state-dir'] {
			if name !in values { return FrontendError{'missing required ' + name} }
		}
		values['--kernel-dir'] = hosttest.module_resolve(values['--kernel-dir'])!
		values['--state-dir'] = hosttest.module_resolve(values['--state-dir'])!
		values['--guest-state-dir'] = values['--state-dir'] + '/guest'
	}
	if family == 'hotplug' && arch != '' && '--state-dir' !in values {
		return FrontendError{'native run needs --state-dir'}
	}
	if arch != '' && !(family == 'hotplug' && '--build-only' in values)
		&& ('--kernel-dir' !in values || '--guest-state-dir' !in values) {
		return FrontendError{'--arch requires --kernel-dir and --guest-state-dir'}
	}
	if family == 'spi' {
		values['--suite'] = values['--suite'] or { 'both' }
		if arch != '' && values['--suite'] == 'both' {
			return FrontendError{'native checks require one migrated --suite'}
		}
	}
	if family == 'ans' { values['--fixture'] = values['--fixture'] or { 'ext2' } }
	timeout := values['--timeout'] or { '300' }
	number := strconv.parse_int(timeout, 10, 32) or { return FrontendError{'invalid integer --timeout'} }
	if number <= 0 { return FrontendError{'--timeout must be positive'} }
	root := hosttest.root()
	caller := policyhost.caller_arch()
	state := values['--state-dir']
	work := if state == '' {
		if family == 'hotplug' { temporary_work('vinix-hotplug-')! }
		else { private_work('vinix-' + family + '-')! }
	} else {
		hosttest.work_dir(state, '')!
	}
	unsafe { C.__atomic_store_n(&apple_suite_interrupted, i32(0), C.__ATOMIC_RELAXED) }
	previous := C.signal(C.SIGINT, voidptr(apple_suite_signal))
	if previous == voidptr(-1) {
		if state == '' { hosttest.remove_work_dir(work)! }
		return error('Cannot install Apple test interrupt handler')
	}
	return Runtime{
		options:     values
		root:        root
		work:        work
		host_arch:   values['--host-arch'] or { caller }
		caller_arch: caller
		arch:        arch
		kernel:      values['--kernel-dir']
		guest:       values['--guest-state-dir']
		build_only:  '--build-only' in values
		timeout:     number.str()
		owned:       state == ''
		previous:    previous
	}
}

pub fn (r Runtime) close() ! {
	C.signal(C.SIGINT, r.previous)
	if r.owned { hosttest.remove_work_dir(r.work)! }
}

pub fn environment() map[string]string { return policyhost.environment() }

pub fn capture_result(argv []string, env map[string]string, host_arch string, directory string) !fixturehost.CapturedCommand {
	return capture_timeout(argv, env, host_arch, directory, -1)!
}

pub fn capture_timeout(argv []string, env map[string]string, host_arch string, directory string, timeout int) !fixturehost.CapturedCommand {
	return fixturehost.capture_bounded(argv, env, host_arch, directory, timeout, apple_suite_cancelled) or {
		if err.code() == 130 { return err }
		return error(err.msg())
	}
}

pub fn capture(argv []string, env map[string]string, host_arch string, directory string, binary bool) !string {
	result := capture_result(argv, env, host_arch, directory)!
	eprint(result.stderr)
	if result.status != 0 {
		return error('Command failed (' + result.status.str() + '): ' + argv[0])
	}
	if binary { return result.stdout }
	// Source files and symbol tools have an explicit UTF-8 contract. Binary Git
	// objects and fixture goldens bypass decoding, preserving every output byte.
	hosttest.module_decode_utf8(result.stdout)!
	return result.stdout.replace('\r\n', '\n').replace('\r', '\n')
}

pub fn inherited(argv []string, env map[string]string, host_arch string) ! {
	result := capture_result(argv, env, host_arch, '')!
	print(result.stdout)
	eprint(result.stderr)
	if result.status != 0 {
		return error('Command failed (' + result.status.str() + '): ' + argv[0])
	}
}

pub fn generate(source string, output string, arch string, defines []string) ! {
	mut argv := [hosttest.root() + '/build-support/compile-v-module', source, output, '--arch',
		arch]
	for define in defines { argv << ['-d', define] }
	inherited(argv, environment(), policyhost.caller_arch())!
}

// Keep the serial constructor's existing link-flag filtering, PIC, warning
// exceptions and native producer options exactly as compile_module does.
pub fn serial(output string, arch string, flags []string) ! {
	module_path := hosttest.root() + '/tests/kernel-gaps/serialcore'
	source := hosttest.replace_suffix(output, '.c')
	generate(module_path, source, if arch == 'aarch64' { 'arm64' } else { 'amd64' }, ['nofloat'])!
	mut options := flags.filter(it !in ['-static', '-nostdlib', '-pie'] && !it.starts_with('-L')
		&& !it.starts_with('-l') && !it.starts_with('-Wl,') && !it.starts_with('-fuse-ld='))
	options << ['-Wno-unused-function', '-Wno-unused-parameter', '-fPIC', '-I', module_path, '-c',
		source, '-o', output]
	inherited(options, environment(), policyhost.caller_arch())!
}

pub fn guest_command(root string, init string, arch string, kernel string, state string, timeout string,
	markers []string, failures []string) []string {
	mut argv := [root + '/build-support/run-v-tool.sh',
		root + '/tests/native-guest-tools/generic-main.v', '--arch', arch, '--prebuilt-init', init,
		'--kernel-dir', kernel, '--state-dir', state, '--no-network', '--timeout', timeout]
	for marker in markers { argv << ['--expect', marker] }
	for failure in failures { argv << ['--fail', failure] }
	return argv
}

// Invoke the native guest API in this process so its supervisor owns QEMU and
// its signal handler. Recorded argv remains a directly executable equivalent.
pub fn guest(init string, arch string, kernel string, state string, timeout string,
	markers []string, failures []string) ! {
	if apple_suite_cancelled() { return error_with_code('Host test interrupted', 130) }
	code := guesthost.guest('', init, state, kernel, arch, markers, failures, false, true, timeout.int())!
	if code != 0 { return error_with_code('Native Apple guest failed', code) }
}

pub fn report(failure IError) {
	eprintln(failure.msg())
	exit(if failure is FrontendError { 2 } else if failure.code() == 130 { 130 } else { 1 })
}
