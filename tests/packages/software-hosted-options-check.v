// SPDX-License-Identifier: GPL-2.0-or-later
// Frozen project/UI source host checks; transitive toolchain is not frozen.
module main

import crypto.sha256
import json2
import os

#include <unistd.h>

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn invoke(argv []string, log string) !(int, string) {
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
	mut paths := ['tests/packages/software-hosted-options-check.v', 'desktop/tools/tests/heap_tracker.h',
		'build-support/xorg-server/winehost/core.v', 'build-support/xorg-server/winehost/package.v',
		'tests/packages/hosted-options/boundary.v', 'tests/packages/hosted-options/fixture.v', 'tests/packages/hosted-options/gate.v']
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
	$if prod {} $else { return error('compile software-hosted-options-check with -prod to bind its source') }
	embedded := sha256.sum($embed_file('software-hosted-options-check.v').to_bytes()).hex()
	require(digest(@FILE)! == embedded, 'driver source differs from executable')!
	if os.args.len != 4 { return error('usage: software-hosted-options-check V_EXECUTABLE UI_MODULE_DIRECTORY NEW_OUTPUT_DIRECTORY') }
	v := os.real_path(os.args[1]); modules := os.real_path(os.args[2]); output := os.abs_path(os.args[3])
	root := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	cc := os.real_path('/opt/homebrew/opt/llvm/bin/clang')
	require(os.is_file(v) && os.is_file(cc) && os.is_file(modules + '/ui2/v.mod')
		&& !os.exists(output) && !os.is_link(output) && !output.starts_with(root + '/'),
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
	require(hashes['tests/packages/software-hosted-options-check.v'] == embedded, 'captured driver differs from executable')!
	v_hash := digest(v)!; cc_hash := digest(cc)!
	os.mkdir(output, mode: 0o700)!
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
		if path == 'tests/packages/software_hosted_fixture.v' { continue }
		if path.starts_with('desktop/software_') || (path.starts_with('tests/packages/software_') && path.ends_with('_fixture.v')) {
			os.cp(source + '/' + path, app + '/' + if os.file_name(path) == 'software_fixture.v' { 'main.v' } else { os.file_name(path) })!
		}
	}
	for name in ['boundary.v', 'fixture.v', 'gate.v']! {
		os.cp(source + '/tests/packages/hosted-options/' + name, app + '/hosted_options_' + name)!
	}
	// Only this isolated boundary stage controls effective UID. Keep the real
	// production source unchanged in source/ and record staged hashes separately.
	hosted := app + '/software_hosted.v'; hosted_text := os.read_file(hosted)!
	require(hosted_text.count('C.geteuid()') == 1, 'hosted UID gate changed')!
	os.write_file(hosted, hosted_text.replace('C.geteuid()', 'hosted_options_euid()'))!
	os.mkdir_all(output + '/gate-module/winehost')!
	os.cp(source + '/build-support/xorg-server/winehost/package.v', output + '/gate-module/winehost/package.v')!
	entry := app + '/main.v'; original := os.read_file(entry)!
	needle := 'fn main() {\n\tunsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }'
	require(original.count(needle) == 1, 'historical fixture entry point changed')!
	adapter := needle + '\n\tif hosted_options_service(os.args) or { eprintln(err); exit(1) } { return }'
		+ '\n\tif os.args.len == 2 && os.args[1] == "hosted-options" { check_hosted_options() or { eprintln(err); exit(1) }; check_hosted_gate() or { eprintln(err); exit(1) }; return }'
	os.write_file(entry, original.replace(needle, adapter))!
	os.write_file(output + '/sources.json', json2.encode(hashes) + '\n')!
	os.write_file(output + '/ui-sources.json', json2.encode(ui_hashes) + '\n')!
	os.write_file(output + '/staged-ui-sources.json', json2.encode(staged_ui_hashes) + '\n')!
	verify(root, paths, hashes)!; verify(modules, ui_paths, ui_hashes)!
	mut generated := map[string]string{}
	for path in os.walk_ext(app, '.v') { generated[os.file_name(path)] = digest(path)! }
	os.write_file(output + '/staged-sources.json', json2.encode(generated) + '\n')!
	for mode in ['normal', 'prod', 'tracked', 'tracked-prod', 'sanitized']! {
		mut argv := [v, '-backend', 'c', '-keepc', '-nocache', '-no-skip-unused', '-cc', cc,
			'-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless',
			'-cflags', '-O1 -Wno-error=incompatible-pointer-types -I' + source + '/desktop', '-path', '@vlib|' + output + '/gate-module|' + source + '|' + source + '/tools/accounts|' + ui + '|@vmodules']
		if mode == 'prod' || mode == 'tracked-prod' { argv << '-prod' }
		if mode.starts_with('tracked') { argv << ['-d', 'track_heap'] }
		if mode == 'sanitized' { argv << ['-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
		argv << ['-o', output + '/' + mode, app]
		code, _ := invoke(argv, output + '/' + mode + '.build.log')!
		require(code == 0, 'build failed; see ' + output + '/' + mode + '.build.log')!
		run_code, text := invoke([output + '/' + mode, 'hosted-options'], output + '/' + mode + '.run.log')!
		require(run_code == 0, 'focused checks failed; see ' + output + '/' + mode + '.run.log')!
		for marker in ['HOSTED OPTIONS frozen installed display, native refusal and literal vector PASS',
			'HOSTED OPTIONS six admission gates and invalid draft refusal PASS',
			'HOSTED OPTIONS Terminal vector and real non-display worker barrier PASS',
			'HOSTED OPTIONS raw argv grammar, exact limits and account protocol agreement PASS',
			'HOSTED OPTIONS explicit production-safe checks PASS']! {
			require(text.split_into_lines().filter(it == marker).len == 1, 'missing/duplicate focused PASS marker')!
		}
		if mode.starts_with('tracked') {
			for marker in ['HOSTED OPTIONS 1000 ordinary/custom boundary cycles retain 0 bytes / 0 records PASS',
				'HOSTED OPTIONS 10000 raw argv validations retain 0 bytes / 0 records PASS']! {
				require(text.split_into_lines().filter(it == marker).len == 1, 'missing/duplicate ownership allocation PASS marker')!
			}
		}
		println('HOSTED OPTIONS ' + mode + ' build/check PASS')
	}
	// Historical checks contain assertion side effects and run only without -prod.
	legacy_code, legacy := invoke([output + '/normal'], output + '/normal.historical.log')!
	require(legacy_code == 0, 'historical normal Software fixture failed')!
	for marker in ['Software save navigation: literal paste/control refusal, focus-first Escape, full/compact status/failure, frozen receipt paging, partial/complete-before-exit writer guards and late failure PASS',
		'Software deployment saving: literal ordinary argv, bounded complete receipt, destination binding, both architectures, empty generation, close guard, fresh audit/review, diagnostics and compact navigation passed',
		'Software UI: catalog, package/trust review, literal confirmation, revocation, URL paging, diagnostics and close guard passed']! {
		require(legacy.split_into_lines().filter(it == marker).len == 1, 'historical normal fixture marker missing/duplicate')!
	}
	println('HOSTED OPTIONS supplementary historical normal Software fixture PASS')
	require(project_sources(root)! == paths && ui_sources(modules) == ui_paths, 'source inventory changed')!
	verify(root, paths, hashes)!; verify(source, paths, hashes)!
	verify(modules, ui_paths, ui_hashes)!; verify(ui_original, ui_paths, ui_hashes)!; verify(ui, ui_paths, staged_ui_hashes)!
	require(os.walk_ext(app, '.v').len == generated.len, 'staged fixture inventory changed')!
	for path, hash in generated { require(digest(app + '/' + path)! == hash, 'staged fixture changed')! }
	require(digest(output + '/gate-module/winehost/package.v')! == hashes['build-support/xorg-server/winehost/package.v'], 'staged raw gate changed')!
	require(digest(v)! == v_hash && digest(cc)! == cc_hash, 'compiler executable changed')!
	mut artifacts := map[string]string{}
	for path in os.walk_ext(output, '') {
		if os.is_file(path) && !path.starts_with(source + '/') && !path.starts_with(ui_original + '/') && !path.starts_with(ui + '/') { artifacts[path[output.len + 1..]] = digest(path)! }
	}
	os.write_file(output + '/artifacts.json', json2.encode(artifacts) + '\n')!
	os.write_file(output + '/result.json', json2.encode({
		'format': '1'
		'outcome': 'PASS'
		'output_directory': output
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
		'ownership_cycles_per_tracked_mode': '1000 ordinary/custom helper/capture cycles and 10000 raw argv validations; 0 retained V bytes and records'
		'boundary_adapter': 'separate capture adapter replaces fail-closed hosted stub; staged Software helper calls controlled euid function for six gate cases'
		'scope': 'host headless Software routing and raw native argv parser only; no real X11 bridge, account admission, target guest or full section 14 acceptance'
		'toolchain_limit': 'project/UI sources and V/clang executables pinned; imported vlib/thirdparty, headers, linker and transitive tools not frozen; not hermetic or reproducible'
	}) + '\n')!
	println('HOSTED OPTIONS five focused host variants PASS: ' + output)
}

fn main() { qualify() or { eprintln(err); exit(1) } }
