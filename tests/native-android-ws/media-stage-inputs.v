// SPDX-License-Identifier: GPL-2.0-or-later
// Retain post-build imported V files and the actual C preprocessor closure.
module main

import json2
import os

const compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'

fn command(root string, label string, argv []string) !string {
	result := os.exec(argv)
	os.write_file(root + '/' + label + '.raw', result.output)!
	os.write_file(root + '/' + label + '.json', json2.encode({'argv': json2.Any(argv), 'exit_code': json2.Any(result.exit_code)}, prettify: true) + '\n')!
	if result.exit_code != 0 { return error('input discovery failed: ' + label) }
	return result.output
}
fn add(path string, mut selected map[string]bool) ! {
	if !os.is_abs_path(path) || !os.is_file(path) { return error('existing absolute input required: ' + path) }
	selected[path] = true
}
fn headers(directory string, mut selected map[string]bool) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		if os.is_dir(path) { headers(path, mut selected)! } else { add(path, mut selected)! }
	}
}
fn run(profile string, project string, sources string, root string) ! {
	if profile !in ['stager', 'patcher', 'persistent-stager', 'bitmap-stager', 'window-stager', 'layout-stager', 'restrictions-stager', 'bundle-cross-profile-stager', 'resources-float-stager', 'paint-drawable-stager', 'dialog-theme-stager', 'intent-extras-stager', 'resource-lock-stager', 'pending-intent-stager', 'stable-display-stager', 'asset-locales-stager', 'unmanaged-queries-stager', 'stats-unavailable-stager', 'subscription-service-stager', 'autofill-service-stager', 'keyguard-policy-stager', 'broadcast-permission-stager', 'secure-settings-stager', 'usage-inactive-stager', 'messenger-binder-stager', 'component-parcel-stager', 'event-log-stager'] { return error('literal media discovery profile required') }
	if os.real_path(project) != project || !os.is_dir(project) || os.real_path(sources) != sources || !os.is_dir(sources)
		|| os.exists(root) || os.is_link(root) || os.real_path(os.dir(root)) != os.dir(root) { return error('canonical project/frozen sources and fresh discovery output required') }
	main_relative := match profile {
		'stager' { '/tests/native-android-ws/maps-seed-account-companion-stage.v' }
		'persistent-stager' { '/tests/native-android-ws/maps-persistent-data-block-stage.v' }
		'bitmap-stager' { '/tests/native-android-ws/maps-bitmap-tiles-stage.v' }
		'window-stager' { '/tests/native-android-ws/maps-window-animations-stage.v' }
		'layout-stager' { '/tests/native-android-ws/maps-layout-alignment-stage.v' }
		'restrictions-stager' { '/tests/native-android-ws/maps-user-restrictions-stage.v' }
		'bundle-cross-profile-stager' { '/tests/native-android-ws/maps-bundle-cross-profile-stage.v' }
		'resources-float-stager' { '/tests/native-android-ws/maps-resources-float-stage.v' }
		'paint-drawable-stager' { '/tests/native-android-ws/maps-paint-drawable-stage.v' }
		'dialog-theme-stager' { '/tests/native-android-ws/maps-dialog-theme-stage.v' }
		'intent-extras-stager' { '/tests/native-android-ws/maps-intent-extras-stage.v' }
		'resource-lock-stager' { '/tests/native-android-ws/maps-resource-lock-stage.v' }
		'pending-intent-stager' { '/tests/native-android-ws/maps-pending-intent-stage.v' }
		'stable-display-stager' { '/tests/native-android-ws/maps-stable-display-stage.v' }
		'asset-locales-stager' { '/tests/native-android-ws/maps-asset-locales-stage.v' }
		'unmanaged-queries-stager' { '/tests/native-android-ws/maps-unmanaged-queries-stage.v' }
		'stats-unavailable-stager' { '/tests/native-android-ws/maps-stats-unavailable-stage.v' }
		'subscription-service-stager' { '/tests/native-android-ws/maps-subscription-service-stage.v' }
		'autofill-service-stager' { '/tests/native-android-ws/maps-autofill-service-stage.v' }
		'keyguard-policy-stager' { '/tests/native-android-ws/maps-keyguard-policy-stage.v' }
		'broadcast-permission-stager' { '/tests/native-android-ws/maps-broadcast-permission-stage.v' }
		'secure-settings-stager' { '/tests/native-android-ws/maps-secure-settings-stage.v' }
		'usage-inactive-stager' { '/tests/native-android-ws/maps-usage-inactive-stage.v' }
		'messenger-binder-stager' { '/tests/native-android-ws/maps-messenger-binder-stage.v' }
		'component-parcel-stager' { '/tests/native-android-ws/maps-component-parcel-stage.v' }
		'event-log-stager' { '/tests/native-android-ws/maps-event-log-stage.v' }
		else { '/tests/android-webview-browser-probe/patch-kernel.v' }
	}
	main_source := sources + main_relative
	name := os.file_name(main_source).all_before_last('.v')
	if !os.is_file(main_source) { return error('exact frozen media source required') }
	os.mkdir(root, mode: 0o700)!
	listing := command(root, 'v-inputs', ['/usr/bin/env', 'VROOT=' + os.dir(compiler), 'V=' + compiler, 'VINIX_V_COMPILER=' + compiler,
		compiler, '-new-compiler', '-prod', '-gc', 'boehm', '-nocache', '-cc', 'cc', '-no-parallel', '-print-v-files', '-path',
		sources + '/tests/native-android-ws|' + sources + '/build-support|' + sources + '/build-support/android|@vlib', main_source])!
	mut v_inputs := map[string]bool{}
	for line in listing.split_into_lines() { if line.starts_with('/') && line.ends_with('.v') { add(line, mut v_inputs)! } }
	if v_inputs.len < 100 || main_source !in v_inputs { return error('complete frozen imported V listing absent') }
	// The generated command uses whitespace-free canonical paths and no shell
	// expansions. Its exact production invocation was already run unchanged.
	text := os.read_file(project + '/build_command.txt')!.trim_space()
	if text.contains_any("'\"`\n\r") { return error('unexpected quoting in emitted C command') }
	tokens := text.fields()
	if tokens.len < 10 || tokens[0] != 'cc' { return error('expected emitted host C compiler command') }
	mut dependency_argv := ['/usr/bin/cc', '-M']
	mut c_inputs := map[string]bool{}
	mut skip := false
	for token in tokens[1..] {
		if skip { skip = false; continue }
		if token == '-o' { skip = true; continue }
		dependency_argv << token
		if token.starts_with('/') && os.is_file(token) { add(token, mut c_inputs)! }
	}
	if skip { return error('truncated emitted output selector') }
	dependencies := command(root, 'c-inputs', dependency_argv)!
	for token in dependencies.replace('\\\n', ' ').fields() {
		if token.starts_with('/') { add(token, mut c_inputs)! }
	}
	for path in [name + '.c', 'Makefile', 'build_command.txt', 'build.sh', 'build.bat'] { add(project + '/' + path, mut c_inputs)! }
	tool := root + '/input-discovery-tool'
	os.cp(os.real_path(os.executable()), tool)!
	os.chmod(tool, 0o700)!
	for path in [sources + '/build-support/android/modulestream/spawn_abi.h', sources + '/build-support/tarstream/filter_abi.h', os.abs_path(@FILE), tool] { add(path, mut c_inputs)! }
	mut missing_include_directories := []string{}
	for directory in ['/Users/alex/code/v-tccbin-bootstrap-20261026/thirdparty/libgc/include', '/Users/alex/code/v-tccbin-bootstrap-20261026/thirdparty/stdatomic/nix', '/Users/alex/code/v-tccbin-bootstrap-20261026/thirdparty/legacy/include/LegacySupport'] {
		if os.is_dir(directory) { headers(directory, mut c_inputs)! } else { missing_include_directories << directory }
	}
	// Unused emitted -I paths can be absent. Every header actually required by
	// the emitted C command above remains a required existing regular input.
	os.write_file(root + '/missing-include-directories.json', json2.encode(missing_include_directories, prettify: true) + '\n')!
	os.write_file(root + '/v-inputs.txt', v_inputs.keys().sorted().join('\n') + '\n')!
	os.write_file(root + '/c-inputs.txt', c_inputs.keys().sorted().join('\n') + '\n')!
	println('MEDIA-STAGE-INPUTS PASS profile=' + profile + ' V=' + v_inputs.len.str() + ' C=' + c_inputs.len.str() + ' post-build discovery only')
}
fn main() {
	if os.args.len != 5 { eprintln('usage: media-stage-inputs stager|patcher|persistent-stager|bitmap-stager|window-stager|layout-stager|restrictions-stager|bundle-cross-profile-stager|resources-float-stager|paint-drawable-stager|dialog-theme-stager|intent-extras-stager|resource-lock-stager|pending-intent-stager|stable-display-stager|asset-locales-stager|unmanaged-queries-stager|stats-unavailable-stager|subscription-service-stager|autofill-service-stager|keyguard-policy-stager|broadcast-permission-stager|secure-settings-stager|usage-inactive-stager|messenger-binder-stager|component-parcel-stager|event-log-stager GENERATED_PROJECT FROZEN_SOURCES FRESH_DISCOVERY_OUTPUT'); exit(2) }
	run(os.args[1], os.args[2], os.args[3], os.args[4]) or { eprintln(err); exit(1) }
}
