// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the real controller before host discovery or any target build.
module main

import crypto.sha256
import json2
import os

struct StateEntry { path string value string }
struct StateReply { status int output string }
struct StateCase { path string message string }

fn state_require(ok bool, message string) ! { if !ok { return error(message) } }

fn state_walk(root string, relative string, mut entries []StateEntry) ! {
	state_require(entries.len < 200, 'fixture tree exceeded its bounded scope')!
	path := root + '/' + relative
	if os.is_link(path) {
		entries << StateEntry{relative, 'link:' + os.readlink(path)!}
	} else if os.is_dir(path) {
		entries << StateEntry{relative, 'directory'}
		mut names := os.ls(path)!; names.sort()
		for name in names { state_walk(root, relative + '/' + name, mut entries)! }
	} else {
		state_require(os.is_file(path), 'unexpected fixture node')!
		entries << StateEntry{relative, sha256.hexhash(os.read_file(path)!)}
	}
}

fn state_snapshot(root string) ![]StateEntry {
	mut entries := []StateEntry{}
	mut names := os.ls(root)!; names.sort()
	for name in names { state_walk(root, name, mut entries)! }
	return entries
}

fn state_invoke(controller string, kernel string, state string) StateReply {
	mut child := os.new_process(controller)
	defer { child.close() }
	child.set_args(['--arch', 'aarch64', '--kernel', kernel, '--state-dir', state])
	child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp(); child.wait()
	return StateReply{child.code, output}
}

fn state_check() ! {
	state_require(os.args.len == 3, 'requires controller executable and new fixture directory')!
	controller := os.real_path(os.args[1])
	root := os.abs_path(os.args[2])
	state_require(os.is_file(controller) && !os.exists(root) && !os.is_link(root), 'requires an executable and fresh ordinary fixture path')!
	os.mkdir(root, mode: 0o700)!
	kernel := root + '/malformed-kernel'
	os.write_file(kernel, 'preserve this exact malformed kernel\n')!
	os.mkdir(root + '/empty')!
	os.mkdir(root + '/filled')!
	os.mkdir(root + '/filled/work')!
	os.write_file(root + '/filled/work/sentinel', 'retain existing work\n')!
	os.write_file(root + '/file', 'retain existing file\n')!
	os.mkdir(root + '/target')!
	os.mkdir(root + '/target/nested')!
	os.write_file(root + '/target/sentinel', 'retain symlink target\n')!
	os.symlink(root + '/filled', root + '/state-link')!
	os.symlink(root + '/absent-target', root + '/dangling-state-link')!
	os.symlink(root + '/target', root + '/parent-link')!
	mut replies := map[string]StateReply{}
	for item in [StateCase{'empty', '--state-dir requires a new state container'},
		StateCase{'filled', '--state-dir requires a new state container'},
		StateCase{'file', '--state-dir requires a new state container'},
		StateCase{'state-link', '--state-dir requires a new state container'},
		StateCase{'dangling-state-link', '--state-dir requires a new state container'},
		StateCase{'parent-link/new-state', '--state-dir requires an existing ordinary canonical parent'},
		StateCase{'parent-link/nested/new-state', '--state-dir requires an existing ordinary canonical parent'},
		StateCase{'missing-parent/new-state', '--state-dir requires an existing ordinary canonical parent'},
		StateCase{'file/new-state', '--state-dir requires an existing ordinary canonical parent'}] {
		before := state_snapshot(root)!
		reply := state_invoke(controller, kernel, root + '/' + item.path)
		state_require(reply.status == 1 && reply.output == item.message + '\n', 'unexpected refusal: ' + item.path)!
		state_require(state_snapshot(root)! == before, 'refusal modified the private tree: ' + item.path)!
		replies[item.path] = reply
	}
	// A fresh control reaches kernel validation and retains only its own copy;
	// no harness discovery, target compile or VM is reachable with this kernel.
	fresh := root + '/fresh'
	reply := state_invoke(controller, kernel, fresh)
	state_require(reply.status == 1 && reply.output == 'kernel: wrong native ELF architecture\n', 'fresh control did not reach kernel validation')!
	state_require(os.ls(fresh)! == ['work'] && os.ls(fresh + '/work')! == ['kernel']
		&& os.read_file(fresh + '/work/kernel')! == os.read_file(kernel)!, 'fresh failed kernel copy was not retained in state/work')!
	replies['fresh'] = reply
	os.write_file(root + '/evidence.json', json2.encode(replies))!
	println('SDK STATE real controller nine unchanged refusals and retained fresh state/work kernel PASS')
}

fn state_source_check() ! {
	state_require(os.args.len == 4, 'requires stale-source controller and new fixture directory')!
	root := os.abs_path(os.args[3])
	state_require(!os.exists(root) && !os.is_link(root), 'source control requires a fresh fixture directory')!
	os.mkdir(root, mode: 0o700)!
	os.write_file(root + '/sentinel', 'source refusal must precede all state writes\n')!
	before := state_snapshot(root)!
	reply := state_invoke(os.real_path(os.args[2]), root + '/missing-kernel', root + '/missing-state')
	state_require(reply.status == 1 && reply.output == 'controller source differs from executable\n'
		&& state_snapshot(root)! == before, 'stale source control did not refuse before state writes')!
	os.write_file(root + '/evidence.json', json2.encode(reply))!
	println('SDK STATE real controller stale source refuses before state writes PASS')
}

fn main() {
	if os.args.len > 1 && os.args[1] == '--source-refusal' {
		state_source_check() or { eprintln(err); exit(1) }
	} else { state_check() or { eprintln(err); exit(1) } }
}
