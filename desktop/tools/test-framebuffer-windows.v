// SPDX-License-Identifier: GPL-2.0-or-later
// Run with: v run desktop/tools/test-framebuffer-windows.v
module main

import os
import workflowbuild
import hosttest

fn cross(root string, source string, ui string, work string, v string, arch string) ! {
	app := work + '/' + arch
	workflowbuild.stage(source, ui, app, true)!
	flags := ['-new-compiler', '-nocache', '-w', '-prod', '-os', 'linux', '-arch', arch, '-gc',
		'none', '-manualfree', '-enable-globals', '-d', 'no_segfault_handler', '-d', 'ui2_headless',
		'-path',
		'@vlib|' + app + '/modules|@vmodules|' + source + '|' + root + '|' + root + '/third_party']
	mut generate := flags.clone()
	generate << ['-o', app + '/desktop.c', app]
	workflowbuild.run(v, generate)!
	hosttest.generate_module(root + '/desktop/execinfocore', app + '/execinfo.c', arch, [])!
	generate = flags.clone()
	generate << ['-o', app + '/demo.c', root + '/examples/framebuffer']
	workflowbuild.run(v, generate)!
	generate = flags.clone()
	generate << ['-o', app + '/guest.c', root + '/desktop/tools/tests/framebuffer_guest.v']
	workflowbuild.run(v, generate)!
	target := if arch == 'arm64' { 'aarch64' } else { 'x86_64' }
	sysroot := if arch == 'arm64' {
		root + '/build-aarch64-userland/staging'
	} else {
		root + '/build/session-amd64-sysroot'
	}
	mut versions := os.ls(sysroot + '/usr/lib/gcc/' + target + '-alpine-linux-musl')!
	versions.sort()
	gcc := sysroot + '/usr/lib/gcc/' + target + '-alpine-linux-musl/' + versions.last()
	llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
	base := ['--target=' + target + '-linux-musl', '-static', '-nostdinc', '-nostdlib', '-isystem',
		root + '/build-support/aarch64-cc-shim', '-isystem', gcc + '/include', '-isystem',
		sysroot + '/usr/include', '-I', app, '-D_GNU_SOURCE', '-O2', '-fno-stack-protector', '-w',
		sysroot + '/usr/lib/crt1.o', sysroot + '/usr/lib/crti.o', gcc + '/crtbeginT.o']
	libs := ['-L' + sysroot + '/usr/lib', '-L' + gcc, '-lgcc_eh', '-lc', '-lgcc', '-lm',
		gcc + '/crtend.o', sysroot + '/usr/lib/crtn.o', '-fuse-ld=lld', '-B' + llvm]
	mut link := base.clone()
	link << [app + '/desktop.c', app + '/execinfo.c', app + '/presenter.c']
	link << libs
	link << ['-o', app + '/vinix-desktop']
	workflowbuild.run(llvm + '/clang', link)!
	link = base.clone()
	link << [app + '/guest.c']
	link << libs
	link << ['-o', app + '/framebuffer-guest']
	workflowbuild.run(llvm + '/clang', link)!
	link = base.clone()
	link << [app + '/demo.c']
	link << libs
	link << ['-o', app + '/framebuffer-demo']
	workflowbuild.run(llvm + '/clang', link)!
	println('Built ' + arch + ' desktop and framebuffer demo: ' + app)
}

fn main() {
	root := os.real_path(@DIR + '/../..')
	v := os.getenv_opt('V') or { os.find_abs_path_of_executable('v')! }
	work := os.join_path(os.temp_dir(), 'vinix-framebuffer-tests-${os.getpid()}')
	os.mkdir_all(work + '/source')!
	defer { if os.getenv('VINIX_FRAMEBUFFER_KEEP') != '1' { os.rmdir_all(work) or {} } }
	if os.getenv('VINIX_FRAMEBUFFER_KEEP') == '1' { println('Framebuffer test artifacts: ' + work) }
	// Freeze the compositor and overlay only this feature's sources. Other
	// sessions have unrelated edits and generated sources in this checkout.
	workflowbuild.run('git', ['-C', root, 'archive', 'HEAD', 'desktop', '-o', work + '/source.tar'])!
	workflowbuild.run('tar', ['-xf', work + '/source.tar', '-C', work + '/source'])!
	for name in ['main.v', 'wm.v', 'framebuffer_server.v', 'input.v', 'keyboard_protocol.v', 'keyboard_events.v'] {
		os.cp(root + '/desktop/' + name, work + '/source/desktop/' + name)!
	}
	os.cp(root + '/desktop/ptycore/pty.c.v', work + '/source/desktop/ptycore/pty.c.v')!
	if os.exists(work + '/source/desktop/windowfb') {
		os.rmdir_all(work + '/source/desktop/windowfb')!
	}
	os.cp_all(root + '/desktop/windowfb', work + '/source/desktop/windowfb', true)!
	ui := os.getenv_opt('VINIX_UI2_SOURCE') or { if os.is_file(root + '/../ui2/v.mod') {
		root + '/../ui2'
	} else {
		root + '/third_party/ui2'
	} }
	app := work + '/app'
	workflowbuild.stage(work + '/source', ui, app, false)!
	// The upstream macOS control helper still selects AppKit in a headless
	// build. Exclude that branch in this isolated test snapshot.
	control := app + '/modules/ui2/ui/control_state.c.v'
	if os.is_file(control) {
		os.write_file(control, os.read_file(control)!.replace('$else $if macos {', '$else $if macos && !ui2_headless ? {').replace('$else $if windows {', '$else $if windows && !ui2_headless ? {'))!
	}
	os.rm(app + '/main.v')!
	os.cp(root + '/desktop/tools/tests/framebuffer_window_test.v', app + '/framebuffer_window_test.v')!
	workflowbuild.test(v, ['-new-compiler', '-nocache', '-w', '-gc', 'none', '-manualfree',
		'-enable-globals', '-d', 'no_segfault_handler', '-d', 'ui2_headless', '-path',
		'@vlib|' + app + '/modules|@vmodules|' + work + '/source|' + root + '|' + root + '/third_party',
		app + '/framebuffer_window_test.v'], app, 'framebuffer windows')!
	if os.args.contains('--cross') {
		for arch in ['arm64', 'amd64'] { cross(root, work + '/source', ui, work, v, arch)! }
	}
}
