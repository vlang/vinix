// SPDX-License-Identifier: GPL-2.0-or-later
module winesource

import os

fn require_check(ok bool) { if !ok { panic('WINE helper control failed') } }
fn require_refusal(ok bool) { if !ok { panic('WINE helper expected refusal') } }

fn test_source_closure_captures_hidden_imports_and_refuses_changed_or_omitted_inputs() {
	root := os.join_path(os.temp_dir(), 'vinix-source-closure-' + os.getpid().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	visible := root + '/runner.v'
	hidden := root + '/imported.v'
	os.write_file(visible, 'module main\n')!
	os.write_file(hidden, 'module imported\nconst token = 1\n')!
	mut listed := [visible, hidden]
	listed.sort()
	os.write_file(root + '/before', listed.join('\n') + '\n')!
	os.write_file(root + '/built', listed.join('\n') + '\n')!
	mut inputs := {visible: file_digest(visible)!}
	capture(root + '/before', mut inputs)!
	require_check(hidden in inputs)
	admit(root + '/before', root + '/built', inputs)!
	// A transitive import outside the caller's manual seed list must be bound.
	mut missing := inputs.clone()
	missing.delete(hidden)
	mut refused := false
	admit(root + '/before', root + '/built', missing) or { refused = true }
	require_refusal(refused)
	os.write_file(hidden, 'module imported\nconst token = 2\n')!
	refused = false
	admit(root + '/before', root + '/built', inputs) or { refused = true }
	require_refusal(refused)
	require_check(inputs[visible] == file_digest(visible)!)
	refused = false
	capture(root + '/before', mut inputs) or { refused = true }
	require_refusal(refused)
	os.write_file(root + '/built', visible + '\n')!
	refused = false
	admit(root + '/before', root + '/built', inputs) or { refused = true }
	require_refusal(refused)
}

fn test_source_closure_refuses_ambiguous_and_nonregular_manifests() {
	root := os.join_path(os.temp_dir(), 'vinix-source-list-' + os.getpid().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	file := root + '/source.v'
	os.write_file(file, 'module main\n')!
	for contents in ['', 'relative.v\n', file + '\n' + file + '\n', root + '/missing.v\n', file + '\r\n'] {
		os.write_file(root + '/list', contents)!
		mut inputs := map[string]string{}
		mut refused := false
		capture(root + '/list', mut inputs) or { refused = true }
		require_refusal(refused)
	}
	os.symlink(file, root + '/alias')!
	mut inputs := map[string]string{}
	mut refused := false
	capture(root + '/alias', mut inputs) or { refused = true }
	require_refusal(refused)
}
