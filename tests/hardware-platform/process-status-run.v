// SPDX-License-Identifier: GPL-2.0-or-later
// Retained host-only, source-bound qualification of hwhost's C status slot.
module main

import crypto.sha256
import json2
import nativeguard
import os
import recoveryguard
import time

#include <errno.h>

const status_source = '/Users/alex/code/vinix/build/hwhost-waitpid-status-worktree'
const status_base = '/Users/alex/.cache/vinix-hwhost-status-20261026-01'
const status_state = status_base + '/qualification-07'
const status_toolchain = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain'
const status_original = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain'
const status_clang = '/opt/homebrew/opt/llvm/bin/clang'
const status_cap = u64(64) << 20
const status_reserve = u64(2) << 20

struct StatusPin { path string value string }
struct StatusEnvironment { name string present bool value string }
struct StatusGenerated { path string sha256 string roots []string poll_i32 bool poll_i64 bool }

fn run_require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn run_hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	defer { unsafe { digest.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or { if err.code() == 0 { break }; return err }
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	return digest.sum([]u8{}).hex()
}

fn run_walk(root string, relative string, started i64, mut pins []StatusPin) ! {
	run_require(pins.len < 200000 && time.sys_mono_now() - started < 60 * time.second,
		'input inventory exceeds bound')!
	path := root + '/' + relative
	run_require(!os.is_link(path), 'unexpected input link: ' + path)!
	if os.is_dir(path) {
		pins << StatusPin{relative, 'directory'}
		mut names := os.ls(path)!; names.sort()
		for name in names { run_walk(root, relative + '/' + name, started, mut pins)! }
	} else {
		run_require(os.is_file(path), 'missing input: ' + path)!
		pins << StatusPin{relative, run_hash(path)!}
	}
}

fn run_inventory(root string, paths []string) ![]StatusPin {
	mut pins := []StatusPin{}
	started := time.sys_mono_now()
	for path in paths { run_walk(root, path, started, mut pins)! }
	pins.sort(a.path < b.path)
	return pins
}

fn run_sources() ! {
	for name, embedded in {
		'process-status-run.v': $embed_file('process-status-run.v').to_string()
		'process-status-check.v': $embed_file('process-status-check.v').to_string()
		'hwhost/process.v': $embed_file('hwhost/process.v').to_string()
	} {
		run_require(run_hash(status_source + '/tests/hardware-platform/' + name)! == sha256.hexhash(embedded),
			'compiled source binding differs: ' + name)!
	}
}

fn run_environment() ! {
	run_require(os.is_dir(status_state + '/modules') && os.ls(status_state + '/modules')!.len == 0,
		'requires owned empty VMODULES')!
	mut observations := []StatusEnvironment{}
	for name in ['VFLAGS', 'CFLAGS', 'LDFLAGS', 'VTEST_ONLY_FN', 'V3CACHE', 'VTMP', 'TMPDIR', 'V', 'VEXE',
		'V_MACOS_V3_CALLER_VEXE', 'VCHILD', 'V_MACOS_V3_CALLER_VCHILD_PRESENT', 'VMODULES'] {
		value := os.getenv_opt(name) or { '' }
		observations << StatusEnvironment{name, name in os.environ(), value}
	}
	os.write_file(status_state + '/environment-before.json', json2.encode(observations))!
	for name, _ in os.environ() { os.unsetenv(name) }
	for name, value in {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex', 'LANG': 'en_US.UTF-8',
		'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
		'VMODULES': status_state + '/modules',
		'TMPDIR': status_state + '/tmp', 'VTMP': status_state + '/tmp', 'V': status_toolchain + '/v',
		'VEXE': status_toolchain + '/v', 'V_MACOS_V3_CALLER_VEXE': status_toolchain + '/v',
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'V_C_ERROR_BUG_REPORT_DISABLED': '1'} {
		os.setenv(name, value, true)
	}
	for name in ['VFLAGS', 'CFLAGS', 'LDFLAGS', 'VTEST_ONLY_FN', 'V3CACHE'] {
		run_require(name !in os.environ(), 'ambient compiler flag survived filtering')!
	}
	os.write_file(status_state + '/environment-selected.json', json2.encode(os.environ()))!
}

fn run_budget(label string, started i64) ! {
	df := nativeguard.actual_df(status_state, status_state + '/' + label + '-df')!
	allocated := nativeguard.allocated([status_base, status_source], os.lstat(status_state)!.dev)!
	os.write_file(status_state + '/' + label + '-budget.json', json2.encode({'available_bytes': df.available.str(),
		'namespace_allocated_bytes': allocated.str(), 'elapsed_ns': (time.sys_mono_now() - started).str()}))!
	run_require(df.available >= u64(1) << 30 && allocated <= status_cap - status_reserve,
		'actual df floor or total namespace cap refused')!
	run_require(time.sys_mono_now() - started < 300 * time.second, 'overall five-minute deadline')!
}

fn run_command(label string, argv []string, expected int, started i64) ! {
	remaining := 300000 - int((time.sys_mono_now() - started) / 1_000_000)
	run_require(remaining > 0, 'overall deadline before command')!
	base := status_state + '/' + label
	os.write_file(base + '.argv.json', json2.encode(argv))!
	mut run_error := ''
	result := nativeguard.supervise(argv, status_source, status_state, [status_base, status_source],
		base + '.log', base + '-df', nativeguard.Limits{start_bytes: u64(2) << 30,
			floor_bytes: u64(1) << 30, cap_bytes: status_cap - status_reserve,
			wall_ms: remaining, sample_ms: 1000}) or {
		run_error = recoveryguard.bounded_message(err.msg()); nativeguard.Result{}
	}
	os.write_file(base + '.result.json', json2.encode(result))!
	os.write_file(base + '.error.json', json2.encode({'error': run_error}))!
	run_require(run_error == '' && result.reason == '' && result.cleanup.exit_code == expected
		&& result.group_observed && result.cleanup.reaped && result.cleanup.group_empty
		&& result.cleanup.final_wait == -1 && result.cleanup.final_errno == C.ECHILD,
		'unexpected command or cleanup: ' + label)!
	run_budget(label, started)!
}

fn run_generated(path string, mut entries []StatusGenerated) ! {
	if os.is_dir(path) {
		mut names := os.ls(path)!; names.sort()
		for name in names { run_generated(path + '/' + name, mut entries)! }
	} else if path.ends_with('.c') {
		text := os.read_file(path)!
		mut roots := []string{}
		for line in text.split_into_lines() {
			if !line.starts_with('typedef struct ') || !line.contains('_x2f_vlib_x2f_') { continue }
			start := line.index('_x2f_') or { continue }
			root := line[start..].all_before('_x2f_vlib_x2f_').replace('_x2f_', '/').replace('_x2d_', '-').replace('_x2e_', '.') + '/vlib'
			if root !in roots { roots << root }
		}
		roots.sort()
		// Match the complete definition signature, including its opening
		// brace, so a prototype cannot select an unrelated function body.
		definition := '\nbool hwhost__Child__poll(hwhost__Child* c) {'
		function := if text.count(definition) == 1 { text.all_after(definition).all_before('\n}') }
			else { '' }
		entries << StatusGenerated{path, run_hash(path)!, roots, function.contains('i32 status ='), function.contains('i64 status =')}
	}
}

fn run_check() ! {
	started := time.sys_mono_now()
	run_sources()!
	run_require(!os.exists(status_state + '/result.json'), 'completed or reused state refused')!
	nativeguard.watch_interrupts()!
	df := nativeguard.actual_df(status_state, status_state + '/start-df')!
	run_require(df.available >= u64(2) << 30, 'actual df below2GiB start')!
	run_require(run_hash(status_toolchain + '/v')! == 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		&& run_hash(status_original + '/v')! == run_hash(status_toolchain + '/v')!, 'selected compiler identity differs')!
	for path, expected in {
		'/Users/alex/.cache/vinix-waitpid-width-20261026-02/overlay-before.json': '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f'
		'/Users/alex/.cache/vinix-waitpid-width-20261026-02/changes.json': '4941c055c018c321d7a4cc94c054b26ba6494bc6be7fa508d99a1bb10b7b2b21'
		status_original + '/snapshot.json': 'c71817ec23314dd58eedeb963c87e8b035baaabbd4eebf1eb9498ab449cf2f51'
	} { run_require(run_hash(path)! == expected, 'qualified compiler provenance differs: ' + path)! }
	compiler_before := run_inventory(status_toolchain, ['v', 'vlib', 'thirdparty', 'v.mod', 'snapshot.json'])!
	qualified := json2.decode[[]StatusPin](os.read_file('/Users/alex/.cache/vinix-waitpid-width-20261026-02/overlay-before.json')!.replace('"sha256":', '"value":'))!
	run_require(compiler_before == qualified, 'selected complete compiler root differs from qualified overlay')!
	os.write_file(status_state + '/compiler-before.json', json2.encode(compiler_before))!
	input_paths := ['tests/hardware-platform/hwhost', 'tests/hardware-platform/process-status-check.v',
		'tests/hardware-platform/process-status-run.v', 'tests/software-hosted-x11/nativeguard',
		'tests/software-hosted-x11/diagnostics/recoveryguard']
	inputs := run_inventory(status_source, input_paths)!
	os.write_file(status_state + '/inputs-before.json', json2.encode(inputs))!
	mut tools := []StatusPin{}
	for path in [status_clang, '/bin/df', os.executable()] {
		resolved := os.real_path(path)
		tools << StatusPin{path, resolved + ':' + run_hash(resolved)!}
	}
	os.write_file(status_state + '/tools-before.json', json2.encode(tools))!
	os.mkdir(status_state + '/tmp')!
	os.mkdir(status_state + '/modules')!
	os.mkdir(status_state + '/old')!
	os.mkdir(status_state + '/old/hwhost')!
	os.mkdir(status_state + '/sources')!
	for name in ['process-status-check.v', 'process-status-run.v'] {
		os.cp(status_source + '/tests/hardware-platform/' + name, status_state + '/sources/' + name)!
	}
	for name in os.ls(status_source + '/tests/hardware-platform/hwhost')! {
		if !name.ends_with('.v') || name.ends_with('_test.v') { continue }
		text := os.read_file(status_source + '/tests/hardware-platform/hwhost/' + name)!
		if name == 'process.v' {
			run_require(text.count('mut status := i32(0)') == 1 && text.count('c.status = int(status)') == 1,
				'exact two-line production patch differs')!
			os.write_file(status_state + '/old/hwhost/' + name,
				text.replace('mut status := i32(0)', 'mut status := 0').replace('c.status = int(status)', 'c.status = status'))!
		} else { os.write_file(status_state + '/old/hwhost/' + name, text)! }
	}
	os.write_file(status_state + '/old-inputs.json', json2.encode(run_inventory(status_state + '/old', ['hwhost'])!))!
	run_environment()!
	// Keep the common fixture outside both module roots. V must resolve each
	// hwhost import through the explicit old/fixed -path, not its input folder.
	fixture := status_state + '/sources/process-status-check.v'
	for mode in ['normal', 'prod'] {
		mut flags := ['-nocache', '-gc', 'none', '-manualfree', '-enable-globals', '-d', 'no_backtrace',
			'-d', 'no_segfault_handler', '-showcc', '-keepc', '-cstrict', '-cc', status_clang,
			// Retained builtin rune_maps discards const. Keep that separate
			// warning visible; differing pointee types remain hard errors.
			'-cflags', '-Werror=incompatible-pointer-types -Werror=int-conversion -Wno-error=incompatible-pointer-types-discards-qualifiers']
		if mode == 'prod' { flags << '-prod' }
		old_binary := status_state + '/old-' + mode
		run_command('old-' + mode + '-compile', [status_toolchain + '/v', ...flags, '-path',
			status_toolchain + '/vlib|' + status_state + '/old', '-o', old_binary, fixture], 1, started)!
		old_log := os.read_file(status_state + '/old-' + mode + '-compile.log')!
		old_errors := old_log.split_into_lines().filter(it.contains(': error: '))
		run_require(old_errors.len == 1 && old_errors[0].contains("incompatible pointer types passing 'i64 *'")
			&& old_log.contains('waitpid(c->pid, &status, WNOHANG)'),
			'baseline refused outside the intended hwhost pointer boundary')!
		binary := status_state + '/fixed-' + mode
		run_command('fixed-' + mode + '-compile', [status_toolchain + '/v', ...flags, '-path',
			status_toolchain + '/vlib|' + status_source + '/tests/hardware-platform', '-o', binary, fixture], 0, started)!
		fixed_log := os.read_file(status_state + '/fixed-' + mode + '-compile.log')!
		run_require(!fixed_log.contains(': error: ') && !fixed_log.all_before('\n').contains(' -w ')
			&& fixed_log.all_before('\n').contains('-Werror=incompatible-pointer-types'),
			'fixed strict Clang command or diagnostics differ')!
		os.mkdir(status_state + '/runtime-' + mode)!
		run_command('fixed-' + mode + '-run', [binary, status_state + '/runtime-' + mode], 0, started)!
		expected := ['exit-0', 'exit-37', 'exit-255', 'sigterm', 'sigkill', 'externally-reaped'].map('PASS ' + it + ' live/WNOHANG/outcome/repeat/ECHILD/canaries').join('\n')
			+ '\nHWHOST status explicit-i32 normal/255/signal/live/repeat/lost/ECHILD PASS\n'
		run_require(os.read_file(status_state + '/fixed-' + mode + '-run.log')! == expected, 'exact runtime cases differ')!
	}
	mut generated := []StatusGenerated{}
	run_generated(status_state + '/tmp', mut generated)!
	os.write_file(status_state + '/generated-c.json', json2.encode(generated))!
	for label in ['old-normal', 'old-prod', 'fixed-normal', 'fixed-prod'] {
		matches := generated.filter(it.path.contains('/' + label + '.'))
		run_require(matches.len == 1 && matches[0].roots == [status_toolchain + '/vlib'], 'generated C root differs: ' + label)!
		run_require(if label.starts_with('old-') { matches[0].poll_i64 && !matches[0].poll_i32 }
			else { matches[0].poll_i32 && !matches[0].poll_i64 }, 'generated hwhost status width differs: ' + label)!
	}
	compiler_after := run_inventory(status_toolchain, ['v', 'vlib', 'thirdparty', 'v.mod', 'snapshot.json'])!
	os.write_file(status_state + '/compiler-after.json', json2.encode(compiler_after))!
	inputs_after := run_inventory(status_source, input_paths)!
	os.write_file(status_state + '/inputs-after.json', json2.encode(inputs_after))!
	run_require(compiler_before == compiler_after && inputs == inputs_after, 'selected compiler or sources changed')!
	mut tools_after := []StatusPin{}
	for path in [status_clang, '/bin/df', os.executable()] {
		resolved := os.real_path(path)
		tools_after << StatusPin{path, resolved + ':' + run_hash(resolved)!}
	}
	os.write_file(status_state + '/tools-after.json', json2.encode(tools_after))!
	run_require(tools == tools_after, 'selected executable tools changed')!
	run_sources()!
	run_budget('final', started)!
	os.write_file(status_state + '/result.json', json2.encode({'outcome': 'PASS', 'modes': 'normal,prod',
		'old_hwhost_strict_refusals': '2', 'fixed_runtime_cases_per_mode': '6',
		'elapsed_ns': (time.sys_mono_now() - started).str()}))!
	println('PASS hwhost explicit i32 status: old normal/prod strict refusal; fixed normal/prod six runtime cases each; complete selected compiler/source/tools unchanged; no guest')
}

fn main() {
	if os.args.len != 2 || os.args[1] !in ['--check', '--seal'] { eprintln('requires --check or --seal exact retained host profile'); exit(2) }
	if !os.is_dir(status_state) || os.is_link(status_state) { eprintln('requires fresh observed bootstrap namespace'); exit(2) }
	if os.args[1] == '--check' { run_check() or { eprintln(err); exit(1) } }
	else {
		run_sources() or { eprintln(err); exit(1) }
		if !os.exists(status_state + '/result.json') || os.exists(status_base + '/bundle.json') {
			eprintln('requires completed unsealed evidence'); exit(2)
		}
		run_budget('before-seal', time.sys_mono_now()) or { eprintln(err); exit(1) }
		pins := run_inventory(status_base, os.ls(status_base) or { eprintln(err); exit(1) }) or { eprintln(err); exit(1) }
		os.write_file(status_base + '/bundle.json', json2.encode(pins)) or { eprintln(err); exit(1) }
		println('PASS retained bundle inventory SHA256=' + (run_hash(status_base + '/bundle.json') or { eprintln(err); exit(1) }))
	}
}
