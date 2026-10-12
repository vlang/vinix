// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import hosttest
import json2
import os

pub fn static_desktop(context Context) !int {
	state := if context.state == os.dir(context.origin) { context.root + '/build/useralloc-pipe/static-desktop-v5' } else { context.state }
	private := context.root + '/third_party/useralloc-pipe'
	mut env := os.environ()
	settings := {'V': context.root + '/build/useralloc-final-audit/compiler/v', 'VINIX_AARCH64_SYSROOT': state + '/sysroot', 'VINIX_AARCH64_APP_CACHE': state + '/app-cache', 'VINIX_MUSL_BUILD_DIR': state + '/musl-cache', 'VINIX_MUSL_CC_AARCH64': '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/aarch64-linux-musl-gcc', 'VINIX_UI2_SOURCE': state + '/ui2', 'LLVM_BIN': state + '/llvm-bin'}
	for key, value in settings { env[key] = value }
	command := ['/bin/bash', '-x', private + '/scripts/build-desktop-aarch64.sh', '--no-initramfs']
	// An old private checkout must be updated to native producer entrypoints
	// explicitly before its builder can be executed under the V-only rule.
	ensure_native_script(command[2])!
	status := logged(command, state + '/build.log', env, private, state + '/build.pid')!
	mut manifest := read_json(state + '/preparation.json')!
	manifest['command'] = command.map(json2.Any(it))
	manifest['environment'] = hosttest.string_map(settings)
	manifest['build_exit_code'] = status
	if status == 0 {
		checked_hash(state + '/sysroot/usr/lib/libc.a', manifest['static_libc_sha256']!.str())!
		if text(state + '/linked-libc.sha256')!.trim_space() != manifest['static_libc_sha256']!.str() || !text(state + '/linked-symbols.txt')!.contains('malloc_trim') { return error('static desktop libc linkage proof failed') }
		output := private + '/build/vinix-desktop'
		hosttest.module_copy_file_preserving_stat(output, state + '/vinix-desktop')!
		manifest['desktop_sha256'] = digest(output)!
		manifest['link_map_sha256'] = digest(state + '/link.map')!
		manifest['linked_symbol_checks'] = [json2.Any('malloc_trim exists in final linked binary; final libc.a hash matched before and after production hook')]
	}
	write_json(state + '/build.json', manifest)!
	println(json2.encode(manifest, prettify: true))
	flush_stdout()
	return status
}

pub fn ensure_native_script(path string) ! {
	// Let the actual launcher record a missing builder's ordinary exit status.
	if !os.is_file(path) { return }
	bytes := os.read_bytes(path)!
	if !bytes.bytestr().starts_with('#!') { return }
	for line in bytes.bytestr().split_into_lines() {
		if line.trim_space().starts_with('#') { continue }
		if line.contains('python3') && (line.contains('.py') || line.trim_space().starts_with('python3 ') || line.contains('<<')) {
			return error('Private builder requires native producer replacements: ' + path)
		}
	}
}

pub fn perf_driver(context Context, profile string, arguments []string) !int {
	if arguments.len != 3 || profile !in ['final', 'v4'] { return error('STATE SCENARIOS KERNEL required for saved performance driver') }
	setup := context.root + '/build/useralloc-pipe/perf-' + if profile == 'final' { 'final' } else { 'v4' } + '-preparation'
	command := [hosttest.root() + '/tests/desktop-perf/run-saved-driver', 'run-driver-profile', profile, setup, ...arguments]
	return logged_grace(command, arguments[0] + '.controller.log', os.environ(), '', '', 15)!
}

pub fn perf_validate(context Context) !int {
	command := [hosttest.root() + '/tests/desktop-perf/run-saved-driver', 'validate-completed', context.root + '/build/useralloc-pipe/perf-v6-preparation', context.root + '/build/useralloc-desktop-perf-v6']
	return logged(command, context.state + '/validation-controller.log', os.environ(), '', '')!
}
