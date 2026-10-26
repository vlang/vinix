// SPDX-License-Identifier: GPL-2.0-or-later
// Retained host-only profile; accepts no arbitrary commands or output paths.
module main

import crypto.sha256
import json2
import nativeguard
import os
import recoveryguard
import time

#include <errno.h>

const source = '/Users/alex/Library/Caches/vinix-codex/section14/nativeguard-wait-width-20261026/worktree'
const state = '/Users/alex/.cache/vinix-nativeguard-width-20261026-01'
const toolchain = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain'
const clang = '/opt/homebrew/opt/llvm/bin/clang'
const cap = u64(64) << 20
const reserve = u64(2) << 20

struct Pin { path string value string }
struct Generated { path string sha256 string roots []string i32_slots int i64_slots int }

fn need(ok bool, message string) ! { if !ok { return error(message) } }

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or { if err.code() == 0 { break }; return err }
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

fn walk(root string, relative string, started i64, depth int, mut pins []Pin) ! {
	need(depth < 64 && pins.len < 200000 && !recoveryguard.deadline_expired(started, 120000), 'inventory bound')!
	path := root + '/' + relative
	need(!os.is_link(path), 'unexpected source link: ' + path)!
	if os.is_dir(path) {
		pins << Pin{relative, 'directory'}
		mut names := os.ls(path)!; names.sort()
		for name in names { walk(root, relative + '/' + name, started, depth + 1, mut pins)! }
	} else {
		need(os.is_file(path), 'missing regular input: ' + path)!
		pins << Pin{relative, digest(path)!}
	}
}

fn inventory(root string, paths []string) ![]Pin {
	mut pins := []Pin{}
	started := time.sys_mono_now()
	for path in paths { walk(root, path, started, 0, mut pins)! }
	pins.sort(a.path < b.path)
	return pins
}

fn sources() ! {
	for path, embedded in {
		'nativeguard-width-run.v': $embed_file('nativeguard-width-run.v').to_string()
		'nativeguard-width-check.v': $embed_file('nativeguard-width-check.v').to_string()
		'nativeguard/guard.v': $embed_file('nativeguard/guard.v').to_string()
		'diagnostics/recoveryguard/recoveryguard.v': $embed_file('diagnostics/recoveryguard/recoveryguard.v').to_string()
	} { need(digest(source + '/tests/software-hosted-x11/' + path)! == sha256.hexhash(embedded), 'compiled source differs: ' + path)! }
}

fn environment() ! {
	os.write_file(state + '/environment-before.json', json2.encode(os.environ()))!
	for name, _ in os.environ() { os.unsetenv(name) }
	for name, value in {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex', 'LANG': 'en_US.UTF-8',
		'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
		'TMPDIR': state + '/tmp', 'VTMP': state + '/tmp', 'VMODULES': state + '/modules',
		'V': toolchain + '/v', 'VEXE': toolchain + '/v', 'V_MACOS_V3_CALLER_VEXE': toolchain + '/v',
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'V_C_ERROR_BUG_REPORT_DISABLED': '1'} { os.setenv(name, value, true) }
	os.write_file(state + '/environment-selected.json', json2.encode(os.environ()))!
}

fn budget(label string, started i64) ! {
	df := nativeguard.actual_df(state, state + '/' + label + '-df')!
	allocated := nativeguard.allocated([state, source], os.lstat(state)!.dev)!
	os.write_file(state + '/' + label + '-budget.json', json2.encode({'available_bytes': df.available.str(), 'allocated_bytes': allocated.str()}))!
	need(df.available >= u64(1) << 30 && allocated <= cap - reserve, 'disk floor or namespace cap')!
	need(!recoveryguard.deadline_expired(started, 300000), 'overall five-minute deadline')!
}

fn command(label string, argv []string, expected int, started i64) ! {
	remaining := 300000 - int((time.sys_mono_now() - started) / 1_000_000)
	need(remaining > 0, 'overall command deadline')!
	base := state + '/' + label
	os.write_file(base + '.argv.json', json2.encode(argv))!
	mut run_error := ''
	result := nativeguard.supervise(argv, source, state, [state, source], base + '.log', base + '-df',
		nativeguard.Limits{start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30, cap_bytes: cap - reserve,
			wall_ms: remaining, sample_ms: 1000}) or { run_error = recoveryguard.bounded_message(err.msg()); nativeguard.Result{} }
	os.write_file(base + '.result.json', json2.encode(result))!
	os.write_file(base + '.error.json', json2.encode({'error': run_error}))!
	need(run_error == '' && result.reason == '' && result.cleanup.exit_code == expected
		&& result.group_observed && result.cleanup.reaped && result.cleanup.group_empty
		&& result.cleanup.final_wait == -1 && result.cleanup.final_errno == C.ECHILD,
		'command or cleanup differs: ' + label)!
	budget(label, started)!
}

fn generated(path string, started i64, depth int, mut entries []Generated) ! {
	need(depth < 64 && entries.len < 2000 && !recoveryguard.deadline_expired(started, 120000), 'generated inventory bound')!
	if os.is_dir(path) {
		for name in os.ls(path)! { generated(path + '/' + name, started, depth + 1, mut entries)! }
	} else if path.ends_with('.c') {
		text := os.read_file(path)!
		defer { unsafe { text.free() } }
		mut roots := []string{}
		for line in text.split_into_lines() {
			if !line.starts_with('typedef struct ') || !line.contains('_x2f_vlib_x2f_') { continue }
			start := line.index('_x2f_') or { continue }
			root := line[start..].all_before('_x2f_vlib_x2f_').replace('_x2f_', '/').replace('_x2d_', '-').replace('_x2e_', '.') + '/vlib'
			if root !in roots { roots << root }
		}
		roots.sort()
		mut narrow := 0
		mut wide := 0
		for name in ['nativeguard__poll', 'nativeguard__cleanup', 'recoveryguard__terminate_group'] {
			mut bodies := []string{}
			for chunk in text.split('\n}') {
				// Require a definition line, never a prototype or call site.
				for line in chunk.split_into_lines() {
					if line.contains(' ' + name + '(') && line.ends_with(' {') { bodies << chunk.all_after(line); break }
				}
			}
			need(bodies.len == 1, 'missing unique generated function: ' + name + ' in ' + path)!
			narrow += bodies[0].count('i32 status =')
			wide += bodies[0].count('i64 status =')
		}
		entries << Generated{path, digest(path)!, roots, narrow, wide}
	}
}

fn check() ! {
	$if prod {} $else { return error('runner requires -prod for embedded source binding') }
	started := time.sys_mono_now()
	sources()!
	need(os.is_dir(state) && !os.is_link(state) && !os.exists(state + '/result.json'), 'requires fresh observed bootstrap state')!
	for name in ['tmp', 'modules', 'old', 'cases-normal', 'cases-prod'] { need(!os.exists(state + '/' + name), 'refuses reused output path')! }
	nativeguard.watch_interrupts()!
	df := nativeguard.actual_df(state, state + '/start-df')!
	need(df.available >= u64(2) << 30, 'actual df below2GiB admission')!
	need(digest(toolchain + '/v')! == 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5', 'compiler identity')!
	map_path := os.dir(toolchain) + '/overlay-before.json'
	need(digest(map_path)! == '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f', 'overlay map identity')!
	compiler := inventory(toolchain, ['v', 'vlib', 'thirdparty', 'v.mod', 'snapshot.json'])!
	qualified := json2.decode[[]Pin](os.read_file(map_path)!.replace('"sha256":', '"value":'))!
	need(compiler == qualified, 'complete compiler differs from qualified overlay')!
	os.write_file(state + '/compiler-before.json', json2.encode(compiler))!
	paths := ['tests/software-hosted-x11/nativeguard', 'tests/software-hosted-x11/diagnostics/recoveryguard',
		'tests/software-hosted-x11/nativeguard-width-check.v', 'tests/software-hosted-x11/nativeguard-width-run.v']
	inputs := inventory(source, paths)!
	os.write_file(state + '/inputs-before.json', json2.encode(inputs))!
	mut tools := []Pin{}
	for path in [clang, '/bin/df', os.executable()] { tools << Pin{path, os.real_path(path) + ':' + digest(os.real_path(path))!} }
	os.write_file(state + '/tools-before.json', json2.encode(tools))!
	for name in ['tmp', 'modules', 'old', 'old/nativeguard', 'old/recoveryguard', 'sources'] { os.mkdir(state + '/' + name, mode: 0o700)! }
	os.cp(source + '/tests/software-hosted-x11/nativeguard-width-check.v', state + '/sources/check.v')!
	for relative in ['nativeguard/guard.v', 'diagnostics/recoveryguard/recoveryguard.v'] {
		text := os.read_file(source + '/tests/software-hosted-x11/' + relative)!
		need(text.count('mut status := i32(0)') == if relative.starts_with('nativeguard/') { 2 } else { 1 }, 'exact old patch scope differs')!
		old := text.replace('mut status := i32(0)', 'mut status := 0')
		os.write_file(state + '/old/' + relative.replace('diagnostics/', ''), old)!
	}
	os.write_file(state + '/old-inputs.json', json2.encode(inventory(state + '/old', ['nativeguard', 'recoveryguard'])!))!
	environment()!
	for mode in ['normal', 'prod'] {
		mut flags := ['-nocache', '-enable-globals', '-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
			'-showcc', '-keepc', '-cstrict', '-cc', clang, '-cflags', '-Werror=incompatible-pointer-types -Werror=int-conversion -Wno-error=incompatible-pointer-types-discards-qualifiers']
		if mode == 'prod' { flags << '-prod' }
		command('old-' + mode + '-compile', [toolchain + '/v', ...flags, '-path', '@vlib|@vmodules|' + state + '/old',
			'-o', state + '/old-' + mode, state + '/sources/check.v'], 1, started)!
		old_log := os.read_file(state + '/old-' + mode + '-compile.log')!
		errors := old_log.split_into_lines().filter(it.contains(': error: '))
		need(errors.len == 3 && errors.all(it.contains("incompatible pointer types passing 'i64 *'")), 'old strict refusal differs')!
		command('fixed-' + mode + '-compile', [toolchain + '/v', ...flags, '-path', '@vlib|@vmodules|' + source + '/tests/software-hosted-x11|' + source + '/tests/software-hosted-x11/diagnostics',
			'-o', state + '/fixed-' + mode, state + '/sources/check.v'], 0, started)!
		os.mkdir(state + '/cases-' + mode)!
		command('fixed-' + mode + '-run', [state + '/fixed-' + mode, state + '/cases-' + mode], 0, started)!
		need(os.read_file(state + '/fixed-' + mode + '-run.log')! == 'NATIVEGUARD WIDTH i32 canaries, WNOHANG/exit/signal/ECHILD, poll/cleanup and Process wait/repeat PASS\n', 'runtime marker differs')!
	}
	mut outputs := []Generated{}
	generated(state + '/tmp', time.sys_mono_now(), 0, mut outputs)!
	os.write_file(state + '/generated-c.json', json2.encode(outputs))!
	for label in ['old-normal', 'old-prod', 'fixed-normal', 'fixed-prod'] {
		matches := outputs.filter(it.path.contains('/' + label + '.'))
		need(matches.len == 1 && matches[0].roots == [toolchain + '/vlib'], 'generated C root differs: ' + label)!
		need(if label.starts_with('old-') { matches[0].i64_slots == 3 && matches[0].i32_slots == 0 }
			else { matches[0].i32_slots == 3 && matches[0].i64_slots == 0 }, 'generated C status width differs: ' + label)!
	}
	after := inventory(source, paths)!
	compiler_after := inventory(toolchain, ['v', 'vlib', 'thirdparty', 'v.mod', 'snapshot.json'])!
	os.write_file(state + '/inputs-after.json', json2.encode(after))!
	os.write_file(state + '/compiler-after.json', json2.encode(compiler_after))!
	mut tools_after := []Pin{}
	for path in [clang, '/bin/df', os.executable()] { tools_after << Pin{path, os.real_path(path) + ':' + digest(os.real_path(path))!} }
	os.write_file(state + '/tools-after.json', json2.encode(tools_after))!
	need(inputs == after && compiler == compiler_after && tools == tools_after, 'selected inputs changed')!
	sources()!
	budget('final', started)!
	os.write_file(state + '/result.json', json2.encode({'outcome': 'PASS', 'old_strict_pointer_errors_per_mode': '3', 'modes': 'normal,prod', 'elapsed_ns': (time.sys_mono_now() - started).str()}))!
	println('PASS nativeguard/recoveryguard three explicit-i32 wait slots; old normal/prod strict refusal; real fixed normal/prod child lifecycle; full selected inputs unchanged; no guest')
}

fn main() {
	if os.args != [os.executable(), '--check'] { eprintln('requires exact --check retained host profile'); exit(2) }
	check() or { eprintln(err); exit(1) }
}
