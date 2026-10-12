// SPDX-License-Identifier: GPL-2.0-or-later
// Native staging and regression runner: v run desktop/tools/test-cursor-rendering.v
module main

import os

fn run(command []string) ! {
	mut process := os.new_process(command[0])
	process.set_args(command[1..])
	process.run()
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('command failed (${code}): ${command.join(' ')}') }
}

fn main() {
	root := os.real_path(@DIR + '/../..')
	v := os.getenv_opt('V') or { os.find_abs_path_of_executable('v')! }
	ui2 := os.getenv_opt('VINIX_UI2_SOURCE') or { if os.is_file(root + '/../ui2/v.mod') {
		root + '/../ui2'
	} else {
		root + '/third_party/ui2'
	} }
	work := os.join_path(os.temp_dir(), 'vinix-cursor-render-${os.getpid()}')
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	bounds := os.read_file(root + '/desktop/tools/ui2_headless_bounds.v')!.replace('(linux || vinix)', '(linux || vinix || macos)')
	os.write_file(work + '/headless_bounds.v', bounds)!
	run([root + '/desktop/tools/stage_ui2', work + '/modules/ui2', ui2, work + '/headless_bounds.v'])!
	run([root + '/desktop/tools/stage_app', work + '/ui', root + '/desktop',
		ui2 + '/examples/calculator'])!
	for name in os.ls(work + '/ui')! {
		path := work + '/ui/' + name
		if os.is_link(path) && os.is_file(path) {
			bytes := os.read_bytes(path)!
			os.rm(path)!
			os.write_file_array(path, bytes)!
		}
	}
	run([root + '/desktop/tools/stage_host_gpu', work + '/ui', '--v', v])!
	os.rm(work + '/ui/main.v')!
	os.write_file(work + '/ui/v.mod', "Module { name: 'cursor_render_tests' }\n")!
	suites := if os.args.len > 1 {
		os.args[1..]
	} else {
		['cursor_render', 'window_edges', 'glass', 'switcher']
	}
	for suite in suites {
		if !suite.bytes().all(it.is_alnum() || it == `_`) { panic('invalid suite name') }
		name := suite + '_test.v'
		os.cp(root + '/desktop/tools/tests/' + name, work + '/ui/' + name)!
		println('==> ${suite}')
		run([v, '-new-compiler', '-nocache', '-w', '-gc', 'none', '-manualfree', '-enable-globals',
			'-d', 'ui2_headless', '-path',
			'@vlib|' + work + '/modules|@vmodules|' + root + '|' + root + '/third_party',
			work + '/ui/' + name])!
		os.rm(work + '/ui/' + name)!
	}
}
