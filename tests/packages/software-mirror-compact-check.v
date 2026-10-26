// SPDX-License-Identifier: GPL-2.0-or-later
// Frozen project/UI source host checks; transitive toolchain is not frozen.
module main

import crypto.sha256
import compress.gzip
import json2
import os

#include <unistd.h>

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

// Actual df Available blocks are KiB. Older V os.disk_usage mis-scales macOS.
fn admit_space(log string) ! {
	code, text := invoke(['/bin/df', '-k', os.dir(log)], log + '.space.log')!
	rows := text.trim_space().split_into_lines()
	require(code == 0 && rows.len >= 2, 'cannot read actual free space')!
	fields := rows.last().fields()
	require(fields.len >= 4 && fields[3].len > 0 && fields[3].bytes().all(it >= `0` && it <= `9`)
		&& fields[3].u64() >= 1048576, 'actual df Available must be at least 1 GiB before build/run')!
}

fn observed_size(output string, label string) !u64 {
	// Count earlier attempts and the driver too, in a dedicated output parent.
	code, text := invoke(['/usr/bin/du', '-sk', os.dir(output)], output + '/' + label + '.size.log')!
	fields := text.fields()
	require(code == 0 && fields.len >= 2 && fields[0].bytes().all(it >= `0` && it <= `9`), 'cannot measure retained output')!
	size := fields[0].u64()
	require(size <= 102400, 'observed generated output exceeds 100 MiB; preserve it and stop')!
	return size
}

fn preserve_c(path string) ! {
	if !os.is_file(path) { return }
	bytes := os.read_bytes(path)!
	compressed := gzip.compress(bytes)!
	os.write_file_array(path + '.gz', compressed)!
	require(gzip.decompress(os.read_bytes(path + '.gz')!)! == bytes, 'retained C compression did not round-trip')!
	os.rm(path)!
}

// Preserve earlier owned failed-attempt C/binaries without discarding bytes.
// The explicit ledger is written before each original is removed.
fn preserve_generated(root string) ! {
	require(os.args.len >= 4, 'usage: CHECK preserve-generated NEW_EXTERNAL_RECEIPT GENERATED_PATH...')!
	receipt := os.abs_path(os.args[2])
	parent := os.real_path(os.dir(receipt))
	require(os.is_dir(os.dir(receipt)) && !os.exists(receipt) && !os.is_link(receipt)
		&& parent != root && !parent.starts_with(root + '/'),
		'preservation receipt must be new and external')!
	admit_space(receipt)!
	mut copies := map[string][]string{}
	for requested in os.args[3..] {
		path := os.abs_path(requested)
		name := os.file_name(path)
		require(os.is_file(path) && !os.is_link(path) && os.real_path(path).starts_with(parent + '/')
			&& (name.ends_with('.c') || name in ['normal', 'prod', 'tracked', 'tracked-prod', 'sanitized']!)
			&& !os.exists(path + '.gz') && !os.is_link(path + '.gz'), 'provide only owned generated C/binaries with fresh gzip destinations')!
		bytes := os.read_bytes(path)!
		original := sha256.sum(bytes).hex()
		mode := (os.lstat(path)!).mode & 0o777
		os.write_file_array(path + '.gz', gzip.compress(bytes)!)!
		require(gzip.decompress(os.read_bytes(path + '.gz')!)! == bytes, 'prior generated evidence did not round-trip')!
		copies[path] = [original, digest(path + '.gz')!, mode.str(),
			'restore by gzip decompression to this exact path, then chmod to the recorded decimal permission mode']
		os.write_file(receipt, json2.encode(copies) + '\n')!
		require(digest(path)! == original, 'generated original changed during preservation')!
		os.rm(path)!
	}
}

fn invoke(argv []string, log string) !(int, string) {
	if argv[0] !in ['/bin/df', '/usr/bin/du', '/usr/bin/git']! { admit_space(log)! }
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..]); child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp(); child.wait()
	os.write_file(log, text)!
	for forbidden in ['V panic:', 'ERROR: AddressSanitizer', 'SUMMARY: AddressSanitizer',
		'UndefinedBehaviorSanitizer', 'runtime error:'] {
		require(!text.contains(forbidden), 'unexpected runtime diagnostic; see ' + log)!
	}
	return child.code, text
}

fn project_sources(root string) ![]string {
	mut paths := ['tests/packages/software-mirror-compact-check.v', 'desktop/tools/tests/heap_tracker.h']
	for directory in ['tools/packages', 'tools/accounts', 'desktop/packagecore', 'desktop/workflowcore',
		'desktop/sessioncore', 'desktop/sessionipc', 'desktop/sessionruntime', 'compat/ios/plist']! {
		for path in os.walk_ext(root + '/' + directory, '.v') {
			if !path.ends_with('_test.v') { paths << path[root.len + 1..] }
		}
	}
	for name in os.ls(root + '/desktop')! {
		if name.starts_with('software_') && name.ends_with('.v') { paths << 'desktop/' + name }
	}
	for name in os.ls(root + '/tests/packages')! {
		if name.starts_with('software_') && name.ends_with('_fixture.v') && name != 'software_image_fixture.v' {
			paths << 'tests/packages/' + name
		}
	}
	paths.sort()
	return paths
}

fn ui_sources(modules string) []string {
	mut paths := ['ui2/v.mod']
	for path in os.walk_ext(modules + '/ui2/ui', '.v') {
		if !path.ends_with('_test.v') { paths << path[modules.len + 1..] }
	}
	paths.sort()
	return paths
}

fn verify(root string, paths []string, hashes map[string]string) ! {
	for path in paths { require(digest(root + '/' + path)! == hashes[path], 'source changed: ' + path)! }
}

fn qualify() ! {
	$if prod {} $else { return error('compile software-mirror-compact-check with -prod to bind its source') }
	embedded := sha256.sum($embed_file('software-mirror-compact-check.v').to_bytes()).hex()
	require(digest(@FILE)! == embedded, 'driver source differs from executable')!
	root := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	if os.args.len > 1 && os.args[1] == 'preserve-generated' { preserve_generated(root)!; return }
	if os.args.len != 5 { return error('usage: software-mirror-compact-check V_EXECUTABLE CLANG_EXECUTABLE UI_MODULE_DIRECTORY NEW_OUTPUT_DIRECTORY') }
	v := os.real_path(os.args[1]); cc := os.real_path(os.args[2]); modules := os.real_path(os.args[3])
	requested := os.abs_path(os.args[4])
	require(os.is_dir(os.dir(requested)), 'output parent directory must exist')!
	output := os.join_path(os.real_path(os.dir(requested)), os.file_name(requested))
	require(os.is_file(v) && os.is_file(cc) && os.is_file(modules + '/ui2/v.mod')
		&& !os.exists(output) && !os.is_link(output) && output != root && !output.starts_with(root + '/'),
		'provide compilers, UI modules and a fresh external output directory')!
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(key, v, true) }
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0:abort_on_error=1', true)
	os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	paths := project_sources(root)!; ui_paths := ui_sources(modules)
	mut hashes := map[string]string{}; mut ui_hashes := map[string]string{}
	for path in paths { hashes[path] = digest(root + '/' + path)! }
	for path in ui_paths { ui_hashes[path] = digest(modules + '/' + path)! }
	require(hashes['tests/packages/software-mirror-compact-check.v'] == embedded, 'captured driver differs from executable')!
	v_hash := digest(v)!; cc_hash := digest(cc)!
	os.mkdir(output, mode: 0o700)!
	revision_code, revision_text := invoke(['/usr/bin/git', '-C', root, 'rev-parse', 'HEAD'], output + '/project-revision.log')!
	require(revision_code == 0 && revision_text.trim_space().len == 40, 'cannot capture source revision')!
	source := output + '/source'; ui_original := output + '/ui-source'; ui := output + '/modules'; app := output + '/software'
	for path in paths {
		os.mkdir_all(os.dir(source + '/' + path))!
		os.cp(root + '/' + path, source + '/' + path)!
	}
	for path in ui_paths {
		os.mkdir_all(os.dir(ui_original + '/' + path))!
		os.cp(modules + '/' + path, ui_original + '/' + path)!
		os.mkdir_all(os.dir(ui + '/' + path))!
		os.cp(ui_original + '/' + path, ui + '/' + path)!
	}
	verify(source, paths, hashes)!; verify(ui_original, ui_paths, ui_hashes)!; verify(ui, ui_paths, ui_hashes)!
	// Match launcher-check.v: native mounted-control helpers need the same
	// headless exclusion as their omitted platform backend. Preserve originals.
	control := ui + '/ui2/ui/control_state.c.v'
	if os.is_file(control) {
		os.write_file(control, os.read_file(control)!.replace('$else $if macos {', '$else $if macos && !ui2_headless ? {')
			.replace('$else $if windows {', '$else $if windows && !ui2_headless ? {'))!
	}
	mut staged_ui_hashes := map[string]string{}
	for path in ui_paths { staged_ui_hashes[path] = digest(ui + '/' + path)! }
	os.mkdir(app)!
	for path in paths {
		if path.starts_with('desktop/software_') || (path.starts_with('tests/packages/software_') && path.ends_with('_fixture.v')) {
			os.cp(source + '/' + path, app + '/' + if os.file_name(path) == 'software_fixture.v' { 'main.v' } else { os.file_name(path) })!
		}
	}
	// Add only a private entry adapter; all Software and fixture source stays intact.
	entry := app + '/main.v'; original := os.read_file(entry)!
	needle := 'fn main() {\n\tunsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }'
	require(original.count(needle) == 1, 'historical fixture entry point changed')!
	adapter := needle + '\n\tif compact_mirror_service(os.args) or { eprintln(err); exit(1) } { return }'
		+ "\n\tif os.args.len == 2 && os.args[1] == 'mirror-compact' { check_software_mirror_compact() or { eprintln(err); exit(1) }; return }"
	os.write_file(entry, original.replace(needle, adapter))!
	os.write_file(output + '/sources.json', json2.encode(hashes) + '\n')!
	os.write_file(output + '/ui-sources.json', json2.encode(ui_hashes) + '\n')!
	os.write_file(output + '/staged-ui-sources.json', json2.encode(staged_ui_hashes) + '\n')!
	verify(root, paths, hashes)!; verify(modules, ui_paths, ui_hashes)!
	mut generated := map[string]string{}
	for path in os.walk_ext(app, '.v') { generated[os.file_name(path)] = digest(path)! }
	os.write_file(output + '/staged-sources.json', json2.encode(generated) + '\n')!
	for mode in ['normal', 'prod', 'tracked', 'tracked-prod', 'sanitized']! {
		mut argv := [v, '-backend', 'c', '-nocache', '-no-skip-unused', '-cc', cc,
			'-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless',
			'-cflags', '-O1 -Wno-error=incompatible-pointer-types -I' + source + '/desktop', '-path', '@vlib|' + source + '|' + source + '/tools/accounts|' + ui + '|@vmodules']
		if mode == 'prod' || mode == 'tracked-prod' { argv << '-prod' }
		if mode.starts_with('tracked') { argv << ['-d', 'track_heap'] }
		if mode == 'sanitized' { argv << ['-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
		argv << ['-o', output + '/' + mode, app]
		code, _ := invoke(argv, output + '/' + mode + '.build.log')!
		_ := observed_size(output, mode + '.build')!
		require(code == 0, 'build failed; see ' + output + '/' + mode + '.build.log')!
		preserve_c(output + '/' + mode + '.c')!
		run_code, text := invoke([output + '/' + mode, 'mirror-compact'], output + '/' + mode + '.run.log')!
		_ := observed_size(output, mode + '.run')!
		require(run_code == 0, 'focused checks failed; see ' + output + '/' + mode + '.run.log')!
		for marker in ['COMPACT MIRROR six canvas sizes, destination/source/scope authoring, literal real-child argv, saved-source/digest refusal, recovery and Stop/reaping PASS',
			'COMPACT MIRROR explicit production-safe checks PASS']! {
			require(text.split_into_lines().filter(it == marker).len == 1, 'focused marker missing/duplicate')!
		}
		if mode.starts_with('tracked') {
			require(text.split_into_lines().filter(it == 'COMPACT MIRROR 1000 steady draft/navigation cycles / 12000 trees retain zero V bytes and records PASS').len == 1,
				'tracked marker missing/duplicate')!
		}
		println('COMPACT MIRROR ' + mode + ' build/check PASS')
	}
	// Target source generation catches platform/architecture frontend errors;
	// it does not link or execute a target binary or native mounted controls.
	for architecture in ['arm64', 'amd64']! {
		code, _ := invoke([v, '-backend', 'c', '-nocache', '-no-skip-unused', '-os', 'linux',
			'-arch', architecture, '-prod', '-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless',
			'-path', '@vlib|' + source + '|' + source + '/tools/accounts|' + ui + '|@vmodules',
			'-o', output + '/' + architecture + '.c', app], output + '/' + architecture + '.cgen.log')!
		_ := observed_size(output, architecture + '.cgen')!
		require(code == 0 && os.is_file(output + '/' + architecture + '.c'), 'target C generation failed')!
		preserve_c(output + '/' + architecture + '.c')!
		println('COMPACT MIRROR ' + architecture + ' production target C generation PASS')
	}
	// Historical checks contain assertion side effects and run only without -prod.
	legacy_code, legacy := invoke([output + '/normal'], output + '/normal.historical.log')!
	_ := observed_size(output, 'normal.historical')!
	require(legacy_code == 0, 'historical normal Software fixture failed')!
	for marker in ['Software offline export navigation: compact Back/Cancel/Stop/status/progress/failures, partial and complete-before-exit review cancellation/reaping, frozen retry and protected publication passed',
		'Software saved deployment export: frozen source/digest, explicit new destination, no catalog selection, full path/package/license review, administrator apply, progress, changed-source refusal, retry and retirement passed',
		'Software UI: catalog, package/trust review, literal confirmation, revocation, URL paging, diagnostics and close guard passed']! {
		require(legacy.split_into_lines().filter(it == marker).len == 1, 'historical normal fixture marker missing/duplicate')!
	}
	println('COMPACT MIRROR supplementary historical normal Software fixture PASS')
	require(project_sources(root)! == paths && ui_sources(modules) == ui_paths, 'source inventory changed')!
	verify(root, paths, hashes)!; verify(source, paths, hashes)!
	verify(modules, ui_paths, ui_hashes)!; verify(ui_original, ui_paths, ui_hashes)!; verify(ui, ui_paths, staged_ui_hashes)!
	require(os.walk_ext(app, '.v').len == generated.len, 'staged fixture inventory changed')!
	for path, hash in generated { require(digest(app + '/' + path)! == hash, 'staged fixture changed')! }
	require(digest(v)! == v_hash && digest(cc)! == cc_hash, 'compiler executable changed')!
	final_kib := observed_size(output, 'final')!
	mut artifacts := map[string]string{}
	for path in os.walk_ext(output, '') {
		if os.is_file(path) && !path.starts_with(source + '/') && !path.starts_with(ui_original + '/') && !path.starts_with(ui + '/') { artifacts[path[output.len + 1..]] = digest(path)! }
	}
	os.write_file(output + '/artifacts.json', json2.encode(artifacts) + '\n')!
	os.write_file(output + '/result.json', json2.encode({
		'format': '1'
		'outcome': 'PASS'
		'output_directory': output
		'project_revision': revision_text.trim_space()
		'source_binding': 'source inventory binds captured bytes including any uncommitted edits; revision is provenance only'
		'project_source_files': paths.len.str()
		'project_source_inventory_sha256': digest(output + '/sources.json')!
		'ui_source_inventory_sha256': digest(output + '/ui-sources.json')!
		'staged_ui_source_inventory_sha256': digest(output + '/staged-ui-sources.json')!
		'staged_source_inventory_sha256': digest(output + '/staged-sources.json')!
		'artifact_inventory_sha256': digest(output + '/artifacts.json')!
		'driver_source_sha256': embedded
		'driver_executable_sha256': digest(os.executable())!
		'v_executable': v
		'v_sha256': v_hash
		'clang_executable': cc
		'clang_sha256': cc_hash
		'focused_modes': 'normal, production, tracked normal, tracked production, ASan/UBSan'
		'supplementary_check': 'historical full Software fixture, normal build only'
		'target_source_checks': 'Linux arm64 and amd64 production headless fixture C generation; no link or execution'
		'geometry_states': 'selected/installed/deployment draft, saved-source draft, ready, malformed/failed/changed-digest reply, held exact partial/complete review, stopped, approved publication'
		'canvas_sizes': '320x240,400x300,180x96,319x239,319x240,320x239'
		'render_cycles_per_tracked_mode': '1000 (12000 trees); 0 retained V bytes and records'
		'observed_output_parent_kib_before_receipt': final_kib.str()
		'disk_budget': 'actual df Available >=1048576 KiB before each build/run; observed parent du <=102400 KiB after each, including earlier attempts/driver; observation is not a compiler-write quota'
		'retained_c': 'successful generated C compressed and round-trip checked before removing the raw generated copy'
		'scope': 'host headless Software compact offline-export authoring only; no target guest, compositor screenshot or full section 14 acceptance'
		'toolchain_limit': 'project/UI sources and V/clang executables pinned; imported vlib/thirdparty, headers, linker and transitive tools not frozen; not hermetic or reproducible'
	}) + '\n')!
	_ := observed_size(output, 'receipt')!
	println('COMPACT MIRROR five focused host variants PASS: ' + output)
}

fn main() { qualify() or { eprintln(err); exit(1) } }
