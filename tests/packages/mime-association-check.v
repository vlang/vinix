@[has_globals]
module main

import crypto.sha256
import json2
import nativeguard
import os

const compiler = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const baseline = '9f8609211'

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn tree(path string, mut found map[string]string) ! {
	kind := os.lstat(path)!.mode & 0o170000
	if kind == 0o040000 {
		mut names := os.ls(path)!
		names.sort()
		found['directory:' + path] = 'directory'
		for name in names { tree(path + '/' + name, mut found)! }
	} else if kind == 0o100000 { found[path] = digest(path)! }
	else if kind == 0o120000 {
		found['link:' + path] = os.readlink(path)!
		resolved := os.real_path(path)
		if os.lstat(resolved)!.mode & 0o170000 != 0o100000 { return error('nonregular link referent: ' + path) }
		found['resolved:' + path] = resolved
		found[path] = digest(resolved)!
	}
	else { return error('nonregular input: ' + path) }
}

fn retain_origins(work string, profile string) ! {
	mut found := map[string]string{}
	// This compiler retains source origins in anonymous C type identifiers even
	// when normal/production builds omit literal #line paths.
	root := os.dir(compiler)
	encoded := root.replace('/', '_x2f_').replace('-', '_x2d_').replace('.', '_x2e_')
	for path in os.walk_ext(work + '/scratch', '.c') {
		text := os.read_file(path)!
		if (!text.contains(root + '/vlib/builtin/')
			&& !text.contains('AnonStruct_' + encoded + '_x2f_vlib_x2f_builtin_x2f_'))
			|| text.contains('/v3-selfhost-performance/vlib/')
			|| text.contains('_x2f_v3_x2d_selfhost_x2d_performance_x2f_vlib_x2f_') {
			return error('generated C compiler root differs: ' + path)
		}
		found[path] = digest(path)!
	}
	// -keepc leaves the output-side file and may retain its temporary copy.
	// Require one translation unit; duplicate paths must have identical bytes.
	if found.len < 1 || found.len > 2 { return error('expected one generated translation unit: ' + profile) }
	mut translation_unit := ''
	for _, sum in found {
		if translation_unit != '' && translation_unit != sum { return error('generated C copies differ: ' + profile) }
		translation_unit = sum
	}
	for path, _ in found { os.rm(path)! }
	found['observed_builtin_source_root'] = root + '/vlib/builtin/'
	os.write_file(work + '/' + profile + '.generated-c.json', json2.encode(found) + '\n')!
}

fn snapshot(root string) !map[string]string {
	mut found := map[string]string{}
	for part in ['tools/packages', 'tools/accounts', 'desktop/packagecore', 'desktop/workflowcore',
		'compat/ios/plist', 'tests/software-hosted-x11/nativeguard', 'tests/software-hosted-x11/diagnostics/recoveryguard'] {
		for path in os.walk_ext(root + '/' + part, '.v') { found[path] = digest(path)! }
	}
	for path in [@FILE, os.executable(), root + '/desktop/tools/tests/heap_tracker.h', compiler, clang,
		os.dir(compiler) + '/v.mod', os.dir(compiler) + '/snapshot.json'] { found[path] = digest(path)! }
	for part in ['vlib', 'thirdparty'] { tree(os.dir(compiler) + '/' + part, mut found)! }
	if found[compiler] != 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		|| found[clang] != '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8' {
		return error('reviewed compiler digest differs')
	}
	for key in ['PATH', 'HOME', 'TMPDIR', 'VTMP', 'VHOME', 'VMODULES', 'SDKROOT', 'DEVELOPER_DIR',
		'MACOSX_DEPLOYMENT_TARGET', 'CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'LIBRARY_PATH',
		'CLANG_CONFIG_FILE_SYSTEM_DIR', 'CLANG_CONFIG_FILE_USER_DIR', 'V', 'VEXE',
		'V_MACOS_V3_CALLER_VEXE', 'V_MACOS_V3_CALLER_VEXE_PRESENT', 'V_MACOS_V3_CALLER_VCHILD_PRESENT',
		'V_MACOS_V3_NO_FALLBACK', 'V_MACOS_V3_CALLER_NO_FALLBACK',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT', 'CFLAGS', 'CPPFLAGS', 'LDFLAGS', 'VFLAGS'] {
		if value := os.getenv_opt(key) { found['env:' + key] = value }
		else { found['absent-env:' + key] = 'absent' }
	}
	return found
}

fn invoke(name string, argv []string, work string, cwd string, expected string) ! {
	os.write_file(work + '/' + name + '.argv.json', json2.encode(argv) + '\n')!
	result := nativeguard.supervise(argv, cwd, work, [work], work + '/' + name + '.log',
		work + '/' + name + '.df', nativeguard.Limits{start_bytes: u64(2) * 1024 * 1024 * 1024,
		floor_bytes: u64(1) * 1024 * 1024 * 1024, cap_bytes: 80 * 1024 * 1024, wall_ms: 300000})!
	os.write_file(work + '/' + name + '.result.json', json2.encode(result) + '\n')!
	text := os.read_file(work + '/' + name + '.log')!
	if result.reason != '' || !result.cleanup.reaped || !result.cleanup.group_empty
		|| text.len > 4 * 1024 * 1024 { return error(name + ': supervision refused') }
	if expected == '' {
		if result.cleanup.exit_code != 0 { return error(name + ': nonzero exit') }
	} else if result.cleanup.exit_code == 0 || !text.contains(expected) {
		return error(name + ': negative control failed to detect old behavior')
	}
	println(name + ' PASS')
}

fn checks() ! {
	if os.args.len != 2 { return error('usage: mime-association-check NEW_OUTPUT_DIRECTORY') }
	root := os.dir(os.dir(os.dir(@FILE)))
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('output must be new') }
	os.mkdir_all(work + '/scratch/tmp')!
	nativeguard.watch_interrupts()!
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(key, compiler, true) }
	for key in ['V_MACOS_V3_CALLER_VEXE_PRESENT', 'V_MACOS_V3_NO_FALLBACK', 'V_C_ERROR_BUG_REPORT_DISABLED'] {
		os.setenv(key, '1', true)
	}
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('VFLAGS', '', true)
	os.setenv('TMPDIR', work + '/scratch/tmp', true)
	os.setenv('VTMP', work + '/scratch/tmp', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0:halt_on_error=1', true)
	os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	before := snapshot(root)!
	os.write_file(work + '/inputs-before.json', json2.encode(before) + '\n')!
	flags := ['-backend', 'c', '-cc', clang, '-nocache', '-gc', 'none', '-manualfree',
		'-cflags', '-O1', '-keepc', '-path', '@vlib|' + root + '|' + root + '/tools/accounts|@vmodules']
	for part in ['pkgcore', 'pkgprotocol'] {
		base_dir := work + '/baseline/' + part
		os.mkdir_all(os.dir(base_dir))!
		os.cp_all(root + '/tools/packages/' + part, base_dir, false)!
		name := if part == 'pkgcore' { 'model.v' } else { 'registration.v' }
		invoke('baseline-source-' + part, ['/usr/bin/git', 'show', baseline + ':tools/packages/' + part + '/' + name], work, root, '')!
		os.cp(work + '/baseline-source-' + part + '.log', base_dir + '/' + name)!
		for mode in ['normal', 'production'] {
			profile := 'baseline-' + part + '-' + mode
			binary := work + '/scratch/' + profile
			extra := if mode == 'production' { ['-prod'] } else { []string{} }
			source := if part == 'pkgcore' { 'association_test.v' } else { 'registration_test.v' }
			invoke(profile + '-compile', [compiler, ...flags, ...extra, '-o', binary, base_dir + '/' + source], work, root, '')!
			retain_origins(work, profile)!
			invoke(profile + '-run', [binary], work, root, 'admitted malformed MIME association')!
			os.write_file(work + '/' + profile + '.binary.sha256', digest(binary)! + '\n')!
			os.rm(binary)!
			os.rmdir_all(work + '/scratch/tmp')!; os.mkdir_all(work + '/scratch/tmp')!
		}
	}
	os.rmdir_all(work + '/baseline')!
	for source in ['pkgprotocol/mime_test.v', 'pkgprotocol/registration_test.v', 'pkgcore/association_test.v'] {
		for mode in ['normal', 'production', 'sanitized'] {
			profile := source.replace('/', '-').replace('_test.v', '') + '-' + mode
			binary := work + '/scratch/' + profile
			mut extra := []string{}
			if mode == 'production' { extra << '-prod' }
			if mode == 'sanitized' { extra << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
			if source == 'pkgprotocol/mime_test.v' { extra << ['-d', 'track_heap'] }
			invoke(profile + '-compile', [compiler, ...flags, ...extra, '-o', binary, root + '/tools/packages/' + source], work, root, '')!
			retain_origins(work, profile)!
			invoke(profile + '-run', [binary], work, root, '')!
			os.write_file(work + '/' + profile + '.binary.sha256', digest(binary)! + '\n')!
			os.rm(binary)!
			os.rmdir_all(work + '/scratch/tmp')!; os.mkdir_all(work + '/scratch/tmp')!
		}
	}
	after := snapshot(root)!
	os.write_file(work + '/inputs-after.json', json2.encode(after) + '\n')!
	if before != after { return error('observed inputs changed during qualification') }
	os.rmdir_all(work + '/scratch')!
	os.write_file(work + '/qualification.json', json2.encode({'source_revision': baseline,
		'scope': 'host MIME syntax, manifest and registration admission, literal launcher metadata; four old-validator controls and nine fixed profile runs; no guest execution',
		'compiler_sha256': digest(compiler)!, 'inputs_equal': 'true'}) + '\n')!
	mut sums := ''
	mut names := os.ls(work)!
	names.sort()
	for name in names { if os.is_file(work + '/' + name) { sums += digest(work + '/' + name)! + '  ' + name + '\n' } }
	os.write_file(work + '/SHA256SUMS', sums)!
	println('MIME qualification PASS; SHA256SUMS ' + sha256.hexhash(sums))
}

fn main() { checks() or { eprintln(err); exit(1) } }
