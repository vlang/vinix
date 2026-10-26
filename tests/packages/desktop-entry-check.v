// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct DesktopInput { path string sha256 string }
struct DesktopCheck { name string code int binary_sha256 string seconds f64 output_kib u64 }
struct DesktopReceipt {
	format int = 1
	scope string
	source_revision string
	baseline_revision string
	compiler string
	compiler_sha256 string
	inputs []DesktopInput
	checks []DesktopCheck
}

fn desktop_command(argv []string, directory string) (int, string) {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_work_folder(directory)
	child.set_redirect_stdio_merged(); child.run(); output := child.stdout_slurp(); child.wait()
	code := child.code; child.close(); return code, output
}

fn desktop_capacity(work string) !u64 {
	code, output := desktop_command(['/bin/df', '-m', work], work)
	if code != 0 { return error('cannot measure available disk') }
	lines := output.trim_space().split_into_lines()
	fields := lines.last().fields()
	if fields.len < 4 || fields[3].i64() < 650 { return error('less than 650 MiB available for qualification') }
	bytes_code, bytes := desktop_command(['/usr/bin/du', '-sk', work], work)
	// Leave room for the sparse source checkout and this small controller.
	if bytes_code != 0 || bytes.fields()[0].u64() > 48 * 1024 { return error('qualification exceeded its 48 MiB output budget') }
	return bytes.fields()[0].u64()
}

fn desktop_run(name string, argv []string, work string, expected_failure bool) !DesktopCheck {
	desktop_capacity(work)!
	started := time.now()
	code, output := desktop_command(argv, work + '/scratch')
	if output.len > 1024 * 1024 { return error(name + ': unexpectedly large output') }
	os.write_file(work + '/' + name + '.txt', output)!
	accepted := if expected_failure { code != 0 && output.contains('XDG Name/Comment bytes differ from canonical string encoding') }
		else { code == 0 }
	if !accepted { return error(name + ' failed (' + code.str() + '):\n' + output) }
	mut digest := ''
	if !name.ends_with('-compile') { digest = sha256.sum(os.read_bytes(argv[0])!).hex() }
	println(name + ' PASS')
	output_kib := desktop_capacity(work)!
	return DesktopCheck{ name: name, code: code, binary_sha256: digest, seconds: f64(time.since(started).milliseconds()) / 1000.0, output_kib: output_kib }
}

fn desktop_record(mut checks []DesktopCheck, check DesktopCheck, work string) ! {
	checks << check
	os.write_file(work + '/checks.json', json2.encode(checks) + '\n')!
}

fn desktop_retire_binary(binary string) ! {
	os.rm(binary)!
	if os.exists(binary + '.c') { os.rm(binary + '.c')! }
}

fn desktop_checks() ! {
	if os.args.len !in [2, 3] { return error('usage: desktop-entry-check NEW_WORK_DIRECTORY [BASELINE_REVISION]; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification directory must be new') }
	os.mkdir_all(work + '/scratch/tmp')!
	repository := os.dir(os.dir(os.dir(@FILE)))
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	for key in ['VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(key, v, true) }
	for key in ['V_MACOS_V3_CALLER_VEXE_PRESENT', 'V_MACOS_V3_NO_FALLBACK', 'V_C_ERROR_BUG_REPORT_DISABLED'] { os.setenv(key, '1', true) }
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('TMPDIR', work + '/scratch/tmp', true); os.setenv('VTMP', work + '/scratch/tmp', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	code, revision := desktop_command(['git', 'rev-parse', 'HEAD'], repository)
	if code != 0 { return error('cannot pin source revision') }
	baseline := if os.args.len == 3 { os.args[2] } else { '92d1bf687' }
	base_code, base_source := desktop_command(['git', 'show', baseline + ':tools/packages/pkgcore/transaction.v'], repository)
	if base_code != 0 { return error('cannot read baseline transaction serializer') }
	mut inputs := []DesktopInput{}
	mut paths := [@FILE, repository + '/desktop/tools/tests/heap_tracker.h']
	for part in ['tools/packages', 'tools/accounts', 'desktop/packagecore', 'desktop/workflowcore', 'compat/ios/plist'] {
		paths << os.walk_ext(repository + '/' + part, '.v')
	}
	paths.sort()
	for path in paths { inputs << DesktopInput{ path: path, sha256: sha256.sum(os.read_bytes(path)!).hex() } }
	inputs << DesktopInput{ path: baseline + ':tools/packages/pkgcore/transaction.v', sha256: sha256.hexhash(base_source) }
	os.write_file(work + '/inputs.json', json2.encode(inputs) + '\n')!
	baseline_dir := work + '/baseline/pkgcore'
	os.mkdir_all(os.dir(baseline_dir))!
	os.cp_all(repository + '/tools/packages/pkgcore', baseline_dir, false)!
	os.write_file(baseline_dir + '/transaction.v', base_source)!
	flags := ['-backend', 'c', '-cc', 'clang', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree',
		'-cflags', '-O1', '-path', '@vlib|' + repository + '|' + repository + '/tools/accounts|@vmodules']
	mut checks := []DesktopCheck{}
	for mode in ['normal', 'production'] {
		extra := if mode == 'production' { ['-prod'] } else { []string{} }
		binary := work + '/scratch/baseline-' + mode
		name := 'baseline-' + mode
		desktop_record(mut checks, desktop_run(name + '-compile', [v, ...flags, ...extra, '-o', binary, baseline_dir + '/desktop_entry_test.v'], work, false)!, work)!
		desktop_record(mut checks, desktop_run(name + '-run', [binary], work, true)!, work)!
		desktop_retire_binary(binary)!
	}
	os.rmdir_all(work + '/baseline')!
	for name in ['strings-normal', 'strings-production', 'strings-tracked', 'strings-sanitize', 'lifecycle-normal', 'lifecycle-production', 'installed-health', 'installed-health-tracked'] {
		mut extra := []string{}
		if name.ends_with('-production') { extra << '-prod' }
		if name.ends_with('-tracked') { extra << ['-d', 'track_heap'] }
		if name.ends_with('-sanitize') { extra << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
		source := if name.starts_with('strings-') { 'desktop_entry' } else if name.starts_with('lifecycle-') { 'registration' } else { 'installed_health' }
		binary := work + '/scratch/' + name
		desktop_record(mut checks, desktop_run(name + '-compile', [v, ...flags, ...extra, '-o', binary, repository + '/tools/packages/pkgcore/' + source + '_test.v'], work, false)!, work)!
		desktop_record(mut checks, desktop_run(name + '-run', [binary], work, false)!, work)!
		desktop_retire_binary(binary)!
	}
	// Successful builds are pinned above; only logs and receipts form this small
	// audit bundle. Compiler temporaries and synthetic signed installs are scratch.
	os.rmdir_all(work + '/scratch')!
	for input in inputs {
		if os.is_abs_path(input.path) && sha256.sum(os.read_bytes(input.path)!).hex() != input.sha256 {
			return error('qualification source changed during checks: ' + input.path)
		}
	}
	os.write_file(work + '/qualification.json', json2.encode(DesktopReceipt{
		scope: 'host XDG string encoding, real signed install/repair/update/remove/rollback on both declared architectures and installed-health regressions; no guest execution',
		source_revision: revision.trim_space(), baseline_revision: baseline, compiler: v, compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(), inputs: inputs, checks: checks }) + '\n')!
	mut sums := ''
	files := os.ls(work)!
	for file in files { sums += sha256.sum(os.read_bytes(work + '/' + file)!).hex() + '  ' + file + '\n' }
	os.write_file(work + '/SHA256SUMS', sums)!
	println('XDG desktop strings: twenty host build/control/test checks PASS')
	println('SHA256SUMS sha256 ' + sha256.hexhash(sums))
}

fn main() { desktop_checks() or { eprintln(err); exit(1) } }
