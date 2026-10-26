// SPDX-License-Identifier: GPL-2.0-or-later
// Retained, isolated correction of the selected compiler library's C wait ABI.
module main

import crypto.sha256
import json2
import nativeguard
import os
import recoveryguard
import time

#include <errno.h>

const wait_base = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain'
const wait_work = '/Users/alex/.cache/vinix-waitpid-width-20261026-02'
const wait_root = '/Users/alex/Library/Caches/vinix-codex/section14/sdk-contract-20261026/worktree'
const wait_clang = '/opt/homebrew/opt/llvm/bin/clang'
const wait_sdk_c = '/Users/alex/.cache/vinix-sdk-arm-20261026-01/s/guest/program-0/vinix-package.c'
const wait_sdk_c_hash = '96942711e1c98e4045f0a2ed5310eefeca60dbd6c7c545983199234cc151824e'
const wait_cap = u64(384) << 20
const wait_reserve = u64(4) << 20

struct WaitPin { path string sha256 string }
struct WaitBaseline { path string value string }
struct WaitPatch { path string old string replacement string count int }
struct WaitChange { path string before string after string replacements int }
struct WaitGenerated { roots []string status_i32 bool status_i64 bool }
struct WaitEstimate {
	regular_files int
	directories int
	logical_bytes u64
	rounded_file_bytes u64
	directory_reserve_bytes u64
	copy_estimate_bytes u64
	existing_namespace_bytes u64
	build_and_evidence_reserve_bytes u64
	required_bytes u64
	cap_bytes u64
}

fn wait_require(ok bool, message string) ! { if !ok { return error(message) } }

fn wait_hash(path string) !string {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return sha256.sum(bytes).hex()
}

fn wait_sources() ! {
	for name, embedded in {
		'waitpid-toolchain-build.v': $embed_file('waitpid-toolchain-build.v').to_string()
		'waitpid-width-check.v': $embed_file('waitpid-width-check.v').to_string()
	} {
		wait_require(wait_hash(wait_root + '/tests/packages/' + name)! == sha256.hexhash(embedded),
			'wait ABI source differs from executable: ' + name)!
	}
}

fn wait_tools() ![]WaitPin {
	mut pins := []WaitPin{}
	start := time.sys_mono_now()
	for path in [wait_clang, '/opt/homebrew/bin/ld.lld', '/opt/homebrew/opt/llvm/lib/clang/23/include',
		'/Users/alex/code/vinix/build/package-rollback-transaction-work/sysroot',
		wait_root + '/tests/packages/waitpid-toolchain-build.v', wait_root + '/tests/packages/waitpid-width-check.v',
		wait_root + '/tests/software-hosted-x11/nativeguard',
		wait_root + '/tests/software-hosted-x11/diagnostics/recoveryguard', '/bin/df', os.executable(), wait_sdk_c] {
		// Tool symlinks are explicitly recorded and their resolved roots walked.
		if os.is_link(path) {
			pins << WaitPin{path + ':link', os.readlink(path)! + '\nresolved=' + os.real_path(path)}
		}
		wait_walk('/', os.real_path(path).trim_left('/'), start, mut pins)!
	}
	pins.sort(a.path < b.path)
	return pins
}

fn wait_walk(root string, relative string, start i64, mut pins []WaitPin) ! {
	wait_require(pins.len < 200000 && time.sys_mono_now() - start < 120 * time.second,
		'bounded compiler inventory exceeded')!
	path := root + '/' + relative
	wait_require(!os.is_link(path), 'compiler input unexpectedly contains a symlink: ' + path)!
	if os.is_dir(path) {
		pins << WaitPin{relative, 'directory'}
		mut names := os.ls(path)!; names.sort()
		for name in names { wait_walk(root, relative + '/' + name, start, mut pins)! }
	} else {
		wait_require(os.is_file(path), 'missing compiler input: ' + path)!
		pins << WaitPin{relative, wait_hash(path)!}
	}
}

fn wait_inventory(root string) ![]WaitPin {
	mut pins := []WaitPin{}
	start := time.sys_mono_now()
	for path in ['v', 'vlib', 'thirdparty', 'v.mod', 'snapshot.json'] {
		wait_walk(root, path, start, mut pins)!
	}
	pins.sort(a.path < b.path)
	return pins
}

fn wait_budget(label string) ! {
	df := nativeguard.actual_df(wait_work, wait_work + '/' + label + '-df.log')!
	allocated := nativeguard.allocated([wait_work], os.lstat(wait_work)!.dev)!
	os.write_file(wait_work + '/' + label + '-budget.json', json2.encode({'available_bytes': df.available.str(),
		'namespace_allocated_bytes': allocated.str(), 'cap_bytes': wait_cap.str()}))!
	wait_require(df.available >= u64(1) << 30 && allocated <= wait_cap - wait_reserve,
		'compiler prerequisite namespace cap or actual df floor refused')!
}

fn wait_estimate(pins []WaitPin) !WaitEstimate {
	mut files := 0
	mut directories := 1 // New toolchain root.
	mut logical := u64(0)
	mut rounded := u64(0)
	for pin in pins {
		if pin.sha256 == 'directory' { directories++; continue }
		size := os.lstat(wait_base + '/' + pin.path)!.size
		wait_require(size <= u64(1) << 30, 'compiler input size exceeds estimate bound')!
		files++
		logical += u64(size)
		rounded += (u64(size) + 4095) / 4096 * 4096
	}
	directory_bytes := u64(directories) * 4096
	current := nativeguard.allocated([wait_work], os.lstat(wait_work)!.dev)!
	// This estimate assumes fresh 4KiB file allocation, reserves one block per
	// directory and 96MiB for builds/evidence. The sampled guard still applies.
	reserve := u64(96) << 20
	estimate := WaitEstimate{files, directories, logical, rounded, directory_bytes,
		rounded + directory_bytes, current, reserve, current + rounded + directory_bytes + reserve, wait_cap}
	os.write_file(wait_work + '/copy-estimate.json', json2.encode(estimate))!
	wait_require(estimate.required_bytes <= wait_cap - wait_reserve,
		'fresh compiler copy plus builds/evidence estimate exceeds namespace cap')!
	return estimate
}

fn wait_patches() []WaitPatch {
	mut patches := [WaitPatch{'vlib/builtin/cfns.c.v', 'status &int', 'status &i32', 2},
		WaitPatch{'vlib/os/process_nix.c.v', 'mut cstatus := 0', 'mut cstatus := i32(0)', 1},
		WaitPatch{'vlib/os/process_nix.c.v', 'posix_wait4_to_exit_status(cstatus)', 'posix_wait4_to_exit_status(int(cstatus))', 1},
		WaitPatch{'vlib/os/os_nix.c.v', 'mut status := 0', 'mut status := i32(0)', 2},
		WaitPatch{'vlib/os/os_nix.c.v', 'posix_wait4_to_exit_status(status)', 'posix_wait4_to_exit_status(int(status))', 2},
		WaitPatch{'vlib/os/os.c.v', 'status := 0', 'status := i32(0)', 1},
		WaitPatch{'vlib/os/os.c.v', 'posix_wait_status_exited(status)', 'posix_wait_status_exited(int(status))', 1},
		WaitPatch{'vlib/os/os.c.v', 'posix_wait_status_exit_code(status)', 'posix_wait_status_exit_code(int(status))', 1},
		WaitPatch{'vlib/builtin/backtraces_nix.c.v', 'mut status := 0', 'mut status := i32(0)', 1},
		WaitPatch{'vlib/builtin/backtraces_nix.c.v', 'return output, status', 'return output, int(status)', 1}]
	for platform in ['darwin', 'linux', 'freebsd', 'openbsd'] {
		path := 'vlib/os/debugger_' + platform + '.c.v'
		patches << WaitPatch{path, 'mut status := 0', 'mut status := i32(0)', 1}
		patches << WaitPatch{path, 'posix_wait_status_exit_code(status)', 'posix_wait_status_exit_code(int(status))', 1}
	}
	for path, count in {'vlib/os/process_reap_test.c.v': 4,
		'vlib/os/write_file_array_macos_test.c.v': 1,
		'vlib/picohttpparser/response_sigpipe_test.c.v': 1,
		'vlib/v/diagserver/diagserver_linux.c.v': 3,
		'vlib/v/driver/instance_check_nix.c.v': 1,
		'vlib/v/gen/fastc/unit_compile_nix.c.v': 1} {
		patches << WaitPatch{path, 'mut status := 0', 'mut status := i32(0)', count}
		if !path.starts_with('vlib/os/') {
			patches << WaitPatch{path, 'status &int', 'status &i32', 1}
		}
	}
	patches << WaitPatch{'vlib/v/diagserver/diagserver_linux.c.v', 'exit_code_of(status)', 'exit_code_of(int(status))', 2}
	return patches
}

fn wait_make() ! {
	wait_sources()!
	wait_require(!os.exists(wait_work + '/toolchain') && !os.is_link(wait_work + '/toolchain'), 'overlay already exists')!
	wait_require(wait_hash(wait_base + '/v')! == 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5', 'baseline compiler differs')!
	wait_require(wait_hash(wait_base + '/snapshot.json')! == 'c71817ec23314dd58eedeb963c87e8b035baaabbd4eebf1eb9498ab449cf2f51', 'baseline snapshot differs')!
	before := wait_inventory(wait_base)!
	arm_before := '/Users/alex/.cache/vinix-sdk-arm-20261026-01/guard/inputs-before.json'
	wait_require(wait_hash(arm_before)! == '03ed76517e026701851991e5e7c45659dfdd8f38f1e7c43e432d4bef0b0ba686', 'frozen ARM01 input receipt differs')!
	mut frozen := []WaitPin{}
	for pin in json2.decode[[]WaitBaseline](os.read_file(arm_before)!)! {
		if pin.path.starts_with(wait_base + '/') { frozen << WaitPin{pin.path[wait_base.len + 1..], pin.value} }
	}
	frozen.sort(a.path < b.path)
	wait_require(before == frozen, 'baseline complete compiler root differs from frozen ARM01 input map')!
	snapshot := json2.decode[[]WaitPin](os.read_file(wait_base + '/snapshot.json')!)!
	mut expected := map[string]string{}
	for pin in snapshot { expected[pin.path] = pin.sha256 }
	for pin in before {
		if pin.sha256 == 'directory' || pin.path == 'snapshot.json' { continue }
		wait_require(pin.path in expected && expected[pin.path] == pin.sha256, 'baseline snapshot mismatch: ' + pin.path)!
		expected.delete(pin.path)
	}
	wait_require(expected.len == 0, 'baseline snapshot has missing inputs')!
	wait_estimate(before)!
	wait_budget('before-copy')!
	os.write_file(wait_work + '/baseline-before.json', json2.encode(before))!
	os.mkdir(wait_work + '/sources')!
	for name in ['waitpid-toolchain-build.v', 'waitpid-width-check.v'] {
		os.cp(wait_root + '/tests/packages/' + name, wait_work + '/sources/' + name)!
	}
	os.mkdir(wait_work + '/toolchain', mode: 0o700)!
	for index, pin in before {
		path := wait_work + '/toolchain/' + pin.path
		if pin.sha256 == 'directory' { os.mkdir(path)! }
		else { os.cp(wait_base + '/' + pin.path, path)! }
		if index % 256 == 0 { wait_budget('copy-' + index.str())! }
	}
	os.chmod(wait_work + '/toolchain/v', 0o755)!
	wait_require(wait_inventory(wait_work + '/toolchain')! == before, 'independent compiler copy differs')!
	mut changes := []WaitChange{}
	for patch in wait_patches() {
		path := wait_work + '/toolchain/' + patch.path
		text := os.read_file(path)!
		wait_require(text.count(patch.old) == patch.count, 'patch count differs: ' + patch.path + ': ' + patch.old)!
		replacement := text.replace(patch.old, patch.replacement)
		changes << WaitChange{patch.path, sha256.hexhash(text), sha256.hexhash(replacement), patch.count}
		os.write_file(path, replacement)!
	}
	os.write_file(wait_work + '/patches.json', json2.encode(wait_patches()))!
	os.write_file(wait_work + '/changes.json', json2.encode(changes))!
	os.write_file(wait_work + '/overlay-before.json', json2.encode(wait_inventory(wait_work + '/toolchain')!))!
	wait_require(wait_inventory(wait_base)! == before, 'baseline compiler tree changed while making overlay')!
	os.write_file(wait_work + '/baseline-after-copy.json', json2.encode(before))!
	wait_budget('overlay-created')!
	println('PASS independent compiler library copy; exact i32 wait status patches; original complete tree unchanged')
}

fn wait_environment(compiler string) {
	for name, _ in os.environ() { os.unsetenv(name) }
	for name, value in {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex', 'LANG': 'en_US.UTF-8',
		'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
		'TMPDIR': wait_work + '/tmp', 'VTMP': wait_work + '/tmp', 'V': compiler, 'VEXE': compiler,
		'V_MACOS_V3_CALLER_VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE_PRESENT': '1',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0', 'V_MACOS_V3_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1',
		'V_C_ERROR_BUG_REPORT_DISABLED': '1', 'VFLAGS': '',
		'ASAN_OPTIONS': 'detect_leaks=0:abort_on_error=1', 'UBSAN_OPTIONS': 'halt_on_error=1:print_stacktrace=1'} {
		os.setenv(name, value, true)
	}
}

fn wait_generated(path string, mut observations map[string]WaitGenerated) ! {
	if os.is_dir(path) {
		for name in os.ls(path)! { wait_generated(path + '/' + name, mut observations)! }
	} else if path.ends_with('.c') && !path.contains('/toolchain/') {
		text := os.read_file(path)!
		mut roots := []string{}
		for line in text.split_into_lines() {
			if !line.starts_with('typedef struct ') || !line.contains('_x2f_vlib_x2f_') { continue }
			start := line.index('_x2f_') or { continue }
			root := line[start..].all_before('_x2f_vlib_x2f_').replace('_x2f_', '/').replace('_x2d_', '-').replace('_x2e_', '.') + '/vlib'
			if root !in roots { roots << root }
		}
		roots.sort()
		observation := WaitGenerated{roots, text.contains('i32 cstatus ='), text.contains('i64 cstatus =')}
		observations[path] = observation
		if path == wait_work + '/fixture-arm.c' || path.contains('/fixture-normal.')
			|| path.contains('/fixture-prod.') || path.contains('/fixture-sanitized.') {
			wait_require(roots == [wait_work + '/toolchain/vlib'], 'fixture generated C selected a different library root: ' + path)!
			wait_require(observation.status_i32 && !observation.status_i64, 'Process C status has the wrong width: ' + path)!
		}
	}
}

fn wait_command(label string, argv []string, expected int) ! {
	log := wait_work + '/' + label
	os.write_file(log + '.argv.json', json2.encode(argv))!
	mut run_error := ''
	result := nativeguard.supervise(argv, wait_root, wait_work, [wait_work], log + '.log', log + '-df',
		nativeguard.Limits{start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: wait_cap - wait_reserve, wall_ms: 300000, sample_ms: 1000}) or {
		run_error = recoveryguard.bounded_message(err.msg()); nativeguard.Result{}
	}
	os.write_file(log + '.result.json', json2.encode(result))!
	os.write_file(log + '.error.json', json2.encode({'error': run_error}))!
	wait_require(run_error == '' && result.reason == '' && result.cleanup.exit_code == expected
		&& result.group_observed && result.cleanup.reaped && result.cleanup.group_empty
		&& result.cleanup.final_wait == -1 && result.cleanup.final_errno == C.ECHILD,
		'command or cleanup differs: ' + label)!
	wait_budget(label)!
}

fn wait_check() ! {
	wait_sources()!
	baseline := json2.decode[[]WaitPin](os.read_file(wait_work + '/baseline-before.json')!)!
	overlay := json2.decode[[]WaitPin](os.read_file(wait_work + '/overlay-before.json')!)!
	wait_require(wait_inventory(wait_base)! == baseline && wait_inventory(wait_work + '/toolchain')! == overlay,
		'prequalification compiler roots differ')!
	os.mkdir(wait_work + '/tmp')!
	tools := wait_tools()!
	wait_require(wait_hash(wait_sdk_c)! == wait_sdk_c_hash, 'frozen SDK generated C differs')!
	os.write_file(wait_work + '/tools-before.json', json2.encode(tools))!
	fixture := wait_root + '/tests/packages/waitpid-width-check.v'
	compiler := wait_work + '/toolchain/v'
	wait_environment(compiler)
	os.write_file(wait_work + '/environment.json', json2.encode(os.environ()))!
	for mode in ['normal', 'prod', 'sanitized'] {
		mut flags := ['-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
			'-showcc', '-keepc', '-cc', wait_clang, '-cflags', '-Werror=incompatible-pointer-types']
		if mode != 'normal' { flags << '-prod' }
		if mode == 'sanitized' {
			flags << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
		}
		binary := wait_work + '/fixture-' + mode
		wait_command(mode + '-compile', [compiler, ...flags, '-o', binary, fixture], 0)!
		wait_command(mode + '-run', [binary], 0)!
		wait_require(os.read_file(wait_work + '/' + mode + '-run.log')! == 'WAITPID WIDTH 4-byte status, adjacent guards, exit/signal/WNOHANG/ECHILD, Process wait/poll/repeat and execute PASS\n',
			'missing exact runtime marker: ' + mode)!
	}
	arm_c := wait_work + '/fixture-arm.c'
	// This fixture's builtin declaration permits the compiler's safe int bridge.
	// The actual package's explicit i32 C declaration excluded that bridge.
	wait_environment(wait_base + '/v')
	wait_command('arm-baseline-emit', [wait_base + '/v', '-os', 'linux', '-arch', 'arm64', '-prod', '-gc', 'none',
		'-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', wait_work + '/baseline-arm.c', fixture], 0)!
	baseline_c := os.read_file(wait_work + '/baseline-arm.c')!
	wait_require(baseline_c.contains('i64 cstatus =') && baseline_c.contains('int _cabi_out_val_0')
		&& baseline_c.contains('waitpid(p->pid, &_cabi_out_val_0, waitpid_options)'),
		'fresh baseline fixture did not retain the observed safe C int bridge')!
	compile := [wait_clang, '--target=aarch64-linux-musl', '--sysroot=/Users/alex/code/vinix/build/package-rollback-transaction-work/sysroot',
		'-O1', '-Werror=incompatible-pointer-types', '-D_GNU_SOURCE', '-fno-stack-protector', '-c']
	wait_command('arm-baseline-compile', [...compile, '-o', wait_work + '/baseline-arm.o', wait_work + '/baseline-arm.c'], 0)!
	wait_command('arm-sdk-refusal', [...compile, '-o', wait_work + '/sdk-arm.o', wait_sdk_c], 1)!
	baseline_log := os.read_file(wait_work + '/arm-sdk-refusal.log')!
	wait_require(baseline_log.contains("incompatible pointer types passing 'i64 *'") && baseline_log.contains('waitpid'),
		'baseline did not fail at the known wait status ABI boundary')!
	wait_environment(compiler)
	wait_command('arm-overlay-emit', [compiler, '-os', 'linux', '-arch', 'arm64', '-prod', '-gc', 'none', '-manualfree',
		'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', arm_c, fixture], 0)!
	wait_command('arm-overlay-compile', [...compile, '-o', wait_work + '/fixture-arm.o', arm_c], 0)!
	bytes := os.read_bytes(wait_work + '/fixture-arm.o')!
	wait_require(bytes.len >= 20 && bytes[..6] == [u8(127), `E`, `L`, `F`, 2, 1]
		&& bytes[16] == 1 && bytes[17] == 0 && bytes[18] == 183 && bytes[19] == 0,
		'strict production fixture is not an AArch64 ET_REL object')!
	baseline_after := wait_inventory(wait_base)!
	overlay_after := wait_inventory(wait_work + '/toolchain')!
	os.write_file(wait_work + '/baseline-after.json', json2.encode(baseline_after))!
	os.write_file(wait_work + '/overlay-after.json', json2.encode(overlay_after))!
	wait_require(baseline_after == baseline && overlay_after == overlay, 'compiler root changed during checks')!
	tools_after := wait_tools()!
	os.write_file(wait_work + '/tools-after.json', json2.encode(tools_after))!
	wait_require(tools_after == tools, 'selected complete tool/header/sysroot/source roots changed')!
	mut generated := map[string]WaitGenerated{}
	wait_generated(wait_work, mut generated)!
	os.write_file(wait_work + '/generated-c-roots.json', json2.encode(generated))!
	for mode in ['normal', 'prod', 'sanitized'] {
		mut found := false
		for path, _ in generated { if path.contains('/fixture-' + mode + '.') { found = true } }
		wait_require(found, 'missing checked generated C for host mode: ' + mode)!
	}
	wait_require(arm_c in generated, 'missing checked generated C for ARM fixture')!
	wait_sources()!
	wait_budget('complete')!
	println('PASS wait ABI host normal/prod/ASAN+UBSAN and strict production ARM object compile; historical SDK C refused; fresh baseline bridge accepted; both complete compiler roots unchanged; no guest executed')
}

fn wait_seal(root string, output string) ! {
	wait_sources()!
	wait_require(!os.exists(output) && !os.is_link(output), 'evidence inventory already exists')!
	wait_budget('before-seal-' + os.file_name(output))!
	mut pins := []WaitPin{}
	start := time.sys_mono_now()
	mut names := os.ls(root)!; names.sort()
	for name in names { wait_walk(root, name, start, mut pins)! }
	pins.sort(a.path < b.path)
	os.write_file(output, json2.encode(pins))!
	println('PASS complete retained inventory ' + output + ' sha256=' + wait_hash(output)!)
}

fn main() {
	if os.args.len != 2 || os.args[1] !in ['--estimate-copy', '--make-overlay', '--make-overlay-child', '--check-overlay',
		'--seal-failed', '--seal-complete'] {
		eprintln('requires an exact wait ABI qualification profile'); exit(2)
	}
	if !os.is_dir(wait_work) || os.is_link(wait_work) { eprintln('requires fresh observed bootstrap namespace'); exit(2) }
	if os.exists(wait_work + '/bundle.json') || os.is_link(wait_work + '/bundle.json') {
		eprintln('completed evidence namespace is sealed'); exit(2)
	}
	df := nativeguard.actual_df(wait_work, wait_work + '/admission-df.log') or { eprintln(err); exit(1) }
	if df.available < u64(2) << 30 { eprintln('actual df below2GiB start'); exit(1) }
	nativeguard.watch_interrupts() or { eprintln(err); exit(1) }
	if os.args[1] == '--estimate-copy' {
		wait_sources() or { eprintln(err); exit(1) }
		pins := wait_inventory(wait_base) or { eprintln(err); exit(1) }
		estimate := wait_estimate(pins) or { eprintln(err); exit(1) }
		println(json2.encode(estimate))
	} else if os.args[1] == '--seal-failed' {
		wait_seal('/Users/alex/.cache/vinix-waitpid-width-20261026-01', wait_work + '/failed01-bundle.json') or { eprintln(err); exit(1) }
	} else if os.args[1] == '--seal-complete' {
		wait_seal(wait_work, wait_work + '/bundle.json') or { eprintln(err); exit(1) }
	} else if os.args[1] == '--make-overlay' {
		wait_command('make-overlay', [os.executable(), '--make-overlay-child'], 0) or { eprintln(err); exit(1) }
	} else if os.args[1] == '--make-overlay-child' { wait_make() or { eprintln(err); exit(1) } }
	else { wait_check() or { eprintln(err); exit(1) } }
}
