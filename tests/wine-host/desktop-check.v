// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import desktop.tools.workflowbuild

fn check() ! {
	if os.args.len != 3 { return error('usage: desktop-check WORK_DIRECTORY UI2_SOURCE') }
	root := os.dir(os.dir(os.dir(@FILE)))
	work := os.abs_path(os.args[1])
	v := os.getenv_opt('V') or { 'v' }
	workflowbuild.stage(root, os.args[2], work, false)!
	os.cp(root+'/tests/wine-host/desktop-fixture.v', work+'/main.v')!
	control := work+'/modules/ui2/ui/control_state.c.v'
	if os.is_file(control) { os.write_file(control, os.read_file(control)!.replace('$else $if macos {', '$else $if macos && !ui2_headless ? {').replace('$else $if windows {', '$else $if windows && !ui2_headless ? {'))! }
	workflowbuild.run(v, ['-backend', 'c', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless', '-d', 'no_segfault_handler',
		'-path', '@vlib|'+root+'|'+root+'/tools/accounts|'+work+'/modules|@vmodules|'+root+'/third_party', '-o', work+'/test.c', work])!
	mut source := os.read_file(work+'/test.c')!
	source = source.replace('\t#endif#define V_MANUAL_STDLIB_HEADERS 1', '\t#endif\n};\n#endif\n#undef V_CRT_STDIO_LINKAGE\n#undef V_CRT_LINKAGE\n#undef V_CRT_CALL\n#define V_MANUAL_STDLIB_HEADERS 1')
	$if macos { source = source.replace('ptrdiff_t offset);', 'int64_t offset);') }
	os.write_file(work+'/test.c', source)!
	toolchain := os.dir(os.real_path(os.find_abs_path_of_executable(v)!))+'/vlib'
	os.write_file(work+'/runtime.c', '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "'+toolchain+'/os/execute_capture_nix.h"\n#define V_SYNC_THREAD_SCOPE\n#include "'+toolchain+'/sync/thread_helper.h"\n')!
	mut flags := ['-w', '-O0', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-I', work]
	$if macos { flags << ['-x', 'objective-c', '-framework', 'Cocoa', '-framework', 'QuartzCore'] }
	flags << [work+'/test.c', work+'/runtime.c']
	$if macos { flags << ['-x', 'none'] }
	flags << [work+'/presenter.o', '-lpthread', '-lm', '-o', work+'/test']
	workflowbuild.run('clang', flags)!
	workflowbuild.run(work+'/test', [])!
}

fn main() { check() or { eprintln(err); exit(1) } }
