// SPDX-License-Identifier: GPL-2.0-or-later
module main

import cachecli
import crypto.sha512
import hosttest
import json2
import muslnative
import os
import sourcecommand
import time

#include <fcntl.h>
#include <sys/file.h>
#include <signal.h>
#include <unistd.h>

fn C.flock(i32, i32) i32
fn C.kill(i32, i32) i32
fn C.fcntl(i32, i32, ...int) i32

struct SignalCase {
	signal int
	ready  string
}

fn signal_ready(pid int, pointer voidptr) ! {
	context := unsafe { &SignalCase(pointer) }
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for !os.is_file(context.ready) {
		if sourcecommand.child_exited(pid)! || time.sys_mono_now() > deadline {
			return error('stager did not reach controlled checkpoint')
		}
		time.sleep(10 * time.millisecond)
	}
	time.sleep(150 * time.millisecond)
	if C.kill(pid, context.signal) != 0 { return os.error_posix() }
}

fn invoke(command []string, env map[string]string) !sourcecommand.Output {
	return sourcecommand.capture(command, env, 30, 4 * 1024 * 1024, unsafe { nil })!
}

fn descriptors() int {
	mut count := 0
	for fd in 0 .. 4096 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn loader(machine int, version string) []u8 {
	mut data := []u8{len: 32}
	for i, value in [u8(0x7f), `E`, `L`, `F`, 2, 1] { data[i] = value }
	data[18] = u8(machine)
	data[19] = u8(machine >> 8)
	data << ('\x00' + version + '\x00').bytes()
	return data
}

fn setup(work string) !muslnative.Options {
	os.mkdir(work)!
	muslnative.parents(work + '/stage/lib')!
	muslnative.parents(work + '/support/alpine')!
	muslnative.parents(work + '/support/alpine-1.2.6')!
	os.write_file_array(work + '/stage/lib/ld-musl-x86_64.so.1', loader(62, '1.2.5'))!
	os.cp(os.executable(), work + '/cc')!
	os.chmod(work + '/cc', 0o755)!
	os.setenv('VINIX_MUSL_TEST_READELF', os.executable(), true)
	for name in ['alpine', 'alpine-1.2.6'] {
		os.write_file(work + '/support/' + name + '/manifest.json', '[]')!
	}
	os.write_file(work + '/support/malloc-retain.patch', 'controlled source patch')!
	return muslnative.Options{ root: work + '/repository', support: work + '/support', arch: 'x86_64', stage: work + '/stage', cache: work + '/cache', cc: work + '/cc' }
}

fn seed(plan muslnative.Plan) ! {
	build := plan.options.cache + '/x86_64/' + plan.key
	muslnative.parents(build + '/objects/lib')!
	muslnative.parents(build + '/musl-' + plan.version + '/include')!
	os.write_file_array(build + '/objects/lib/libc.so', loader(62, plan.version))!
	os.write_file(build + '/objects/lib/libc.a', 'controlled static archive')!
	os.write_file(build + '/musl-' + plan.version + '/COPYRIGHT', 'controlled license')!
	os.write_file(build + '/musl-' + plan.version + '/include/malloc.h', 'controlled header')!
	mut manifest := plan.manifest.clone()
	manifest['libc_so_sha256'] = muslnative.digest(build + '/objects/lib/libc.so')!
	manifest['libc_a_sha256'] = muslnative.digest(build + '/objects/lib/libc.a')!
	hosttest.write_json(build + '/build.json', manifest)!
}

fn plan_cases(options muslnative.Options) ! {
	path := options.stage + '/lib/ld-musl-x86_64.so.1'
	initial := os.read_bytes(path)!
	defer { os.write_file_array(path, initial) or {} }
	first := muslnative.plan(options, '1')!
	assert first.version == '1.2.5'
	assert muslnative.plan(options, '0')!.key != first.key
	for version in ['1.2.5', '1.2.6'] {
		os.write_file_array(path, loader(62, version))!
		assert muslnative.plan(options, '1')!.version == version
	}
	mut backported := loader(62, '1.2.5')
	backported << 'posix_getdents\x00'.bytes()
	os.write_file_array(path, backported)!
	assert muslnative.plan(options, '1')!.version == '1.2.6'
	mut adjacent := loader(62, '1.2.5')
	adjacent << '1.2.6\x00'.bytes()
	os.write_file_array(path, adjacent)!
	assert muslnative.plan(options, '1')!.version == '1.2.5'
	mut ambiguous := loader(62, '1.2.5')
	ambiguous << '\x001.2.6\x00'.bytes()
	for data in [loader(183, '1.2.5'), []u8{len: 19}, loader(62, '1.2.7'), ambiguous] {
		os.write_file_array(path, data)!
		muslnative.plan(options, '1') or { continue }
		return error('invalid ELF or version admitted')
	}
	os.write_file_array(path, initial)!
	for cache in ['/', options.root] {
		muslnative.plan(muslnative.Options{ ...options, cache: cache }, '1') or { continue }
		return error('unsafe cache admitted')
	}
	os.write_file(options.support + '/extra.patch', 'extra immutable patch')!
	extra := muslnative.plan(muslnative.Options{ ...options, extra_patches: [options.support + '/extra.patch'], max_page_size: 65536, required_exports: ['extra'] }, '1')!
	assert extra.key != first.key && extra.ldflags.ends_with(' -Wl,-z,max-page-size=65536') && extra.patches.last().name == 'extra.patch'
	extra_path := options.support + '/extra.patch'
	if extra_path.starts_with(os.home_dir().trim_right('/') + '/') {
		with_home := '~/' + extra_path[os.home_dir().trim_right('/').len + 1..]
		assert muslnative.plan(muslnative.Options{ ...options, extra_patches: [with_home], max_page_size: 65536, required_exports: ['extra'] }, '1')!.key == extra.key
	}
	muslnative.plan(muslnative.Options{ ...options, extra_patches: [options.support + '/malloc-retain.patch'] }, '1') or {
		assert err.msg().contains('distinct')
		os.write_file(options.support + '/alpine/test.patch', 'pinned patch')!
		hosttest.write_json(options.support + '/alpine/manifest.json', [json2.Any({
			'name':   json2.Any('test.patch')
			'sha512': json2.Any(sha512.sum512('pinned patch'.bytes()).hex())
		})])!
		assert muslnative.plan(options, '1')!.patches[0].name == 'test.patch'
		os.write_file(options.support + '/alpine/test.patch', 'changed patch')!
		muslnative.plan(options, '1') or {
			assert err.msg().contains('checksum')
			os.write_file(options.support + '/alpine/manifest.json', '[]')!
			println('MUSL PLAN / exact ELF and version scan / backports / retention / unsafe caches / private patches and flags / pinned patch checksums: PASS')
			return
		}
		return error('altered Alpine patch accepted')
	}
	return error('duplicate patch filename accepted')
}

fn rebuild_failures(options muslnative.Options, release string) ! {
	plan := muslnative.plan(muslnative.Options{ ...options, cache: options.cache + '-failed' }, '1')!
	archive := plan.options.cache + '/musl-1.2.5.tar.gz'
	os.cp(release, archive)!
	build := plan.options.cache + '/x86_64/' + plan.key
	before := muslnative.digest(options.stage + '/lib/ld-musl-x86_64.so.1')!
	for attempt in 0 .. 2 {
		muslnative.parents(build)!
		os.write_file(build + '/stale', attempt.str())!
		muslnative.publish(plan) or {
			assert err.msg().contains('command failed')
			assert !os.exists(build + '/stale') && !os.exists(build + '/build.json')
			assert os.is_file(build + '/build.log') && os.is_dir(build + '/musl-1.2.5')
			assert muslnative.digest(options.stage + '/lib/ld-musl-x86_64.so.1')! == before
			continue
		}
		return error('invalid source patch unexpectedly published')
	}
	os.write_file(build + '/stale', 'retain until source admission')!
	os.write_file(archive, 'poisoned cached release')!
	muslnative.publish(plan) or {
		assert err.msg().contains('release checksum') && os.is_file(build + '/stale')
		os.cp(release, archive)!
		os.rmdir_all(build)!
		protected := plan.options.cache + '/protected'
		os.mkdir(protected)!
		os.write_file(protected + '/keep', 'keep')!
		os.symlink(protected, build)!
		muslnative.publish(plan) or {
			assert err.msg().contains('symlink') && os.read_file(protected + '/keep')! == 'keep'
			println('MUSL REBUILD / pinned release checksum / repeated failed unpublished builds / retained failure logs / staged loader unchanged / source admission before cleanup / symlink protection: PASS')
			return
		}
		return error('unpublished cache followed a symlink')
	}
	return error('poisoned cached release accepted')
}

fn cases(tool string, work string) ! {
	options := setup(work)!
	plan_cases(options)!
	plan := muslnative.plan(options, '1')!
	seed(plan)!
	command := [tool, '--arch', 'x86_64', '--staging', options.stage, '--build-dir', options.cache,
		'--cc', options.cc, '--support-dir', options.support]
	for args in [command, [...command, '--require-export', 'malloc_trim']] {
		result := invoke(args, os.environ())!
		assert result.status == 0, result.str()
	}
	missing_compiler := options.stage + '/missing-target-compiler'
	missing_command := [tool, '--arch', 'x86_64', '--staging', options.stage, '--build-dir', options.cache,
		'--cc', missing_compiler, '--support-dir', options.support]
	missing_result := invoke(missing_command, os.environ())!
	assert missing_result.status == 2, missing_result.str()
	assert missing_result.str().contains('target compiler missing: ' + missing_compiler), missing_result.str()
	for arguments in [['--jobs', '0'], ['--max-page-size', '4097'], ['--arch', 'invalid'],
		['--require-export', 'absent']] {
		result := invoke([...command, ...arguments], os.environ())!
		assert result.status == if arguments[0] == '--require-export' { 1 } else { 2 }, result.str()
	}
	for key, value in {
		'VINIX_MUSL_RETAIN':       'bad'
		'VINIX_MUSL_TEST_MACHINE': 'aarch64-linux-musl'
	} {
		mut env := os.environ()
		env[key] = value
		result := invoke(command, env)!
		assert result.status == 2, result.str()
	}
	mut disabled := os.environ()
	disabled['VINIX_OPTIMIZED_MUSL'] = '0'
	disabled['VINIX_MUSL_RETAIN'] = 'bad'
	assert invoke([...command, '--cc', '/missing'], disabled)!.status == 0
	build := options.cache + '/x86_64/' + plan.key
	manifest_path := build + '/build.json'
	original_manifest := os.read_file(manifest_path)!
	mut bad_manifest := hosttest.decode_json(original_manifest)!.as_map().clone()
	bad_manifest['cflags'] = 'changed'
	hosttest.write_json(manifest_path, bad_manifest)!
	assert invoke(command, os.environ())!.status == 1
	os.write_file(manifest_path, original_manifest)!
	os.write_file(build + '/objects/lib/libc.a', 'changed archive')!
	assert invoke(command, os.environ())!.status == 1
	seed(plan)!
	mut missing_exports := os.environ()
	missing_exports['VINIX_MUSL_TEST_REMOVE_EXPORT'] = '1'
	result := invoke(command, missing_exports)!
	assert result.status == 1 && result.stderr.contains('remove existing exports'), result.str()
	println('MUSL CLI / actual child probes / cached input and library corruption / export preservation / required exports / invalid options / package opt-out: PASS')
	// The lock descriptor is close-on-exec. Interrupt an actual blocked owner,
	// then publish again to prove cancellation neither steals nor leaks it.
	fd := unsafe { C.open((options.cache + '/build.lock').str, C.O_WRONLY | C.O_CLOEXEC) }
	if fd < 0 { return os.error_posix() }
	defer { C.close(fd) }
	if C.flock(fd, C.LOCK_EX) != 0 { return os.error_posix() }
	for signal in [2, 15] {
		ready := work + '/lock-ready-' + signal.str()
		mut env := os.environ()
		env['VINIX_MUSL_TEST_READY'] = ready
		context := SignalCase{signal, ready}
		output := sourcecommand.capture_owned(command, env, 20, 4 * 1024 * 1024, unsafe { nil }, unsafe { nil }, signal_ready, unsafe { &context }, 3)!
		assert output.status == 128 + signal, output.str()
	}
	C.flock(fd, C.LOCK_UN)
	assert invoke(command, os.environ())!.status == 0
	for signal in [2, 15] {
		ready := work + '/probe-ready-' + signal.str()
		mut env := os.environ()
		env['VINIX_MUSL_TEST_BLOCK_PROBE'] = ready
		context := SignalCase{signal, ready}
		output := sourcecommand.capture_owned(command, env, 20, 4 * 1024 * 1024, unsafe { nil }, unsafe { nil }, signal_ready, unsafe { &context }, 3)!
		assert output.status == 128 + signal, output.str()
		child := os.read_file(ready)!.int()
		deadline := time.sys_mono_now() + u64(5 * time.second)
		for C.kill(child, 0) == 0 && time.sys_mono_now() < deadline {
			time.sleep(10 * time.millisecond)
		}
		assert C.kill(child, 0) != 0, 'compiler probe survived stager cancellation'
	}
	before := descriptors()
	for _ in 0 .. 20 { muslnative.publish(plan)! }
	assert descriptors() == before
	println('MUSL OWNERS / SIGINT and SIGTERM during lock wait and compiler probes / private child retirement / reuse after cancellation / flat descriptor count: PASS')
	release := os.getenv('VINIX_MUSL_TEST_RELEASE')
	if release != '' { rebuild_failures(options, release)! }
}

fn main() {
	if os.base(os.args[0]) == 'cc' {
		blocked := os.getenv('VINIX_MUSL_TEST_BLOCK_PROBE')
		if blocked != '' {
			os.write_file(blocked, os.getpid().str()) or { exit(1) }
			for { time.sleep(20 * time.millisecond) }
		}
		match os.args[1] {
			'-dumpmachine' {
				println(os.getenv_opt('VINIX_MUSL_TEST_MACHINE') or { 'x86_64-linux-musl' })
			}
			'--version' { println('gcc (controlled) 14.2.0') }
			'-print-prog-name=ar' { println('ar') }
			'-print-prog-name=ranlib' {
				ready := os.getenv('VINIX_MUSL_TEST_READY')
				if ready != '' { os.write_file(ready, 'ready') or { exit(1) } }
				println('ranlib')
			}
			'-print-prog-name=readelf' { println(os.getenv('VINIX_MUSL_TEST_READELF')) }
			else { exit(1) }
		}
		return
	}
	if os.args.len == 4 && os.args[1..3] == ['--dyn-syms', '--wide'] {
		if os.getenv('VINIX_MUSL_TEST_REMOVE_EXPORT') != '1' || !os.args[3].contains('/objects/') {
			println('1: 0 0 FUNC GLOBAL DEFAULT 1 malloc')
		}
		println('2: 0 0 FUNC WEAK DEFAULT 1 malloc_trim')
		return
	}
	if os.args.len != 3 {
		eprintln('usage: test-stage TOOL NEW_STATE')
		exit(2)
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	cases(os.args[1], os.args[2]) or {
		eprintln(err)
		exit(1)
	}
}
