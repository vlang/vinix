// SPDX-License-Identifier: GPL-2.0-or-later
// Stage current desktop code with the existing V-only host fixture builder.
module main

import os
import desktop.tools.workflowbuild

fn check() ! {
	if os.args.len != 2 { return error('usage: launcher-check WORK_DIRECTORY') }
	repository := os.dir(os.dir(os.dir(@FILE)))
	work := os.args[1] + '/launcher-desktop'
	v := os.getenv_opt('V') or { 'v' }
	ui := os.getenv_opt('VINIX_UI2_SOURCE') or {
		if os.is_file(repository + '/../ui2/v.mod') {
			repository + '/../ui2'
		} else {
			repository + '/third_party/ui2'
		}
	}
	workflowbuild.stage(repository, ui, work, false)!
	os.rm(work + '/main.v')!
	os.cp(repository + '/desktop/tools/tests/package_launcher_test.v', work + '/package_launcher_test.v')!
	os.cp(repository + '/desktop/tools/tests/heap_tracker.h', work + '/heap_tracker.h')!
	// The native control-state helper must follow the same headless exclusion
	// as its platform backend. Adapt only the staged fixture, never ui2 sources.
	control := work + '/modules/ui2/ui/control_state.c.v'
	if os.is_file(control) {
		os.write_file(control, os.read_file(control)!.replace('$else $if macos {', '$else $if macos && !ui2_headless ? {')
			.replace('$else $if windows {', '$else $if windows && !ui2_headless ? {'))!
	}
	workflowbuild.run(v, ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless',
		'-d', 'no_segfault_handler',
		'-d', 'track_heap', '-path',
		'@vlib|' + repository + '|' + repository + '/tools/accounts|' + work + '/modules|@vmodules|' + repository + '/third_party',
		'-o', work + '/test.c', work + '/package_launcher_test.v'])!
	mut source := os.read_file(work + '/test.c')!
	source = source.replace('\t#endif#define V_MANUAL_STDLIB_HEADERS 1', '\t#endif\n};\n#endif\n#undef V_CRT_STDIO_LINKAGE\n#undef V_CRT_LINKAGE\n#undef V_CRT_CALL\n#define V_MANUAL_STDLIB_HEADERS 1')
	$if macos { source = source.replace('ptrdiff_t offset);', 'int64_t offset);') }
	os.write_file(work + '/test.c', source)!
	// The pinned compiler's separately linked Unix process/thread helpers need
	// their implementation scopes even with its crash handler disabled.
	toolchain := os.dir(os.real_path(os.find_abs_path_of_executable(v)!)) + '/vlib'
	os.write_file(work + '/runtime.c', '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n'
		+ '#define V_OS_EXECUTE_SCOPE\n#include "' + toolchain + '/os/execute_capture_nix.h"\n'
		+ '#define V_SYNC_THREAD_SCOPE\n#include "' + toolchain + '/sync/thread_helper.h"\n')!
	mut cflags := ['-w', '-O0', '-I', work]
	$if macos { cflags << ['-x', 'objective-c', '-framework', 'Cocoa', '-framework', 'QuartzCore'] }
	cflags << [work + '/test.c', work + '/runtime.c']
	$if macos { cflags << ['-x', 'none'] }
	cflags << [work + '/presenter.o', '-lpthread', '-lm', '-o', work + '/test']
	workflowbuild.run('clang', cflags)!
	println('Running package launchers')
	workflowbuild.run(work + '/test', [])!
	println('Package launcher assertions passed')
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
