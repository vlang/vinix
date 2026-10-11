// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import workflowbuild

fn main() {
	root := os.real_path('.')
	v := os.getenv_opt('V') or { '/Users/alex/code/v/v' }
	work := os.join_path(os.temp_dir(), 'vinix-workflows-${os.getpid()}')
	defer { os.rmdir_all(work) or {} }
	// Other sessions share this checkout. Freeze committed desktop sources and
	// overlay only this workstream when explicitly requested for uncommitted work.
	os.mkdir_all('${work}/source') or { panic(err) }
	workflowbuild.run('git', ['archive', 'HEAD', 'desktop', '-o', '${work}/source.tar']) or { panic(err) }
	workflowbuild.run('tar', ['-xf', '${work}/source.tar', '-C', '${work}/source']) or { panic(err) }
	if patch := os.getenv_opt('VINIX_WORKFLOW_PATCH') {
		os.chdir('${work}/source') or { panic(err) }
		workflowbuild.run('git', ['apply', patch]) or { panic(err) }
		os.chdir(root) or { panic(err) }
	}
	if os.getenv('VINIX_WORKFLOW_OVERLAY') == '1' {
	for name in os.ls('${root}/desktop') or { panic(err) } {
		if os.getenv('VINIX_WORKFLOW_SKIP_OVERLAY') == name { continue }
		if name.ends_with('.v') && (name.starts_with('files') || name.starts_with('notes') || name.starts_with('grapher') || name in ['create_context_menu.c.v', 'file_context_ops.c.v', 'quick_launch.v', 'document_open.v', 'editor_documents.v', 'preview_app_ui.v', 'workflow_elements.v', 'render.v']) {
			os.cp('${root}/desktop/${name}', '${work}/source/desktop/${name}') or { panic(err) }
		}
	}
	if os.is_dir('${root}/desktop/workflowcore') { os.cp_all('${root}/desktop/workflowcore', '${work}/source/desktop/workflowcore', true) or { panic(err) } }
	}
	ui := os.getenv_opt('VINIX_UI2_SOURCE') or { if os.is_file('${root}/../ui2/v.mod') { '${root}/../ui2' } else { '${root}/third_party/ui2' } }
	app := '${work}/app'
	workflowbuild.stage('${work}/source', ui, app, false) or { eprintln(err); exit(1) }
	os.rm('${app}/main.v') or { panic(err) }
	mut tests := os.args[1..].clone()
	if tests.len == 0 { tests = ['files_trash', 'files_quicklook', 'editor_workflow'] }
	for name in tests {
		os.cp('${root}/desktop/tools/tests/${name}_test.v', '${app}/${name}_test.v') or { panic(err) }
		mut args := ['-new-compiler', '-nocache', '-cc', 'clang', '-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless', '-d', 'workflow_test', '-path', '@vlib|${app}/modules|@vmodules|${root}|${root}/third_party']
		if name.ends_with('_memory') {
			os.cp('${root}/desktop/tools/tests/heap_tracker.h', '${app}/heap_tracker.h') or { panic(err) }
			args << ['-d', 'track_heap']
		}
		args << '${app}/${name}_test.v'
		workflowbuild.test(v, args, app, name) or { eprintln(err); exit(1) }
		os.rm('${app}/${name}_test.v') or { panic(err) }
	}
}
