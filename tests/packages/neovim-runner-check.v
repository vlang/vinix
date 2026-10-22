// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the real adapter and inspect the child process boundary.
module main

import json2
import os

#include <sys/stat.h>
fn C.mkfifo(&char, u32) int

struct Observation {
	arguments []string
	runtime string
	vim string
	libraries string
}

fn invoke(arguments []string) !(int, string) {
	mut child := os.new_process(arguments[0])
	defer { child.close() }
	child.set_args(arguments[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	return child.code, output
}

fn check() ! {
	$if prod { return error('compile this assertion-based validator without -prod') }
	if os.args.len != 3 { return error('usage: neovim-runner-check REAL_RUNNER NEW_DIRECTORY') }
	runner := os.real_path(os.args[1])
	work := os.abs_path(os.args[2])
	if os.exists(work) { return error('test directory must be fresh') }
	os.mkdir(work, mode: 0o700)!
	observer := work + '/observer'
	os.cp(os.executable(), observer)!
	os.chmod(observer, 0o755)!
	runtime := work + '/runtime data'
	os.mkdir(runtime)!
	invalid := work + '/invalid-executable'
	os.write_file(invalid, 'ordinary test executable\n')!; os.chmod(invalid, 0o755)!
	result := work + '/observed.json'
	os.setenv('VINIX_NEOVIM_OBSERVATION', result, true)
	os.setenv('VIMRUNTIME', '/ambient/untrusted/runtime', true)
	os.setenv('VIM', '/ambient/untrusted/vim', true)
	os.setenv('LD_LIBRARY_PATH', '/signed/generation/lib:/signed/runtime/lib', true)
	literal := ['', 'é 🚀 two words', ';touch ' + work + '/must-not-exist', '$HOME', '--cmd', '-u', '@literal']
	code, output := invoke([runner, runtime, observer, ...literal])!
	if code != 0 { return error('literal launch failed: ' + output) }
	observed := json2.decode[Observation](os.read_file(result)!)!
	assert observed.arguments == [observer, ...literal]
	assert observed.runtime == runtime && observed.vim == ''
	assert observed.libraries == '/signed/generation/lib:/signed/runtime/lib'
	assert !os.exists(work + '/must-not-exist')
	os.rm(result)!
	println('NEOVIM RUNNER actual-child literal empty/Unicode/shell-looking/unknown argv, fixed runtime, cleared VIM, inherited signed library path PASS')
	symlink := work + '/runtime-link'; os.symlink(runtime, symlink)!
	program_link := work + '/program-link'; os.symlink(observer, program_link)!
	fifo := work + '/fifo'; if C.mkfifo(fifo.str, 0o600) != 0 { return error('mkfifo failed') }
	for arguments in [[runner], [runner, 'relative/runtime', observer],
		[runner, symlink, observer], [runner, runtime, program_link],
		[runner, observer, observer], [runner, runtime, fifo],
		[runner, runtime, work + '/missing']] {
		status, diagnostic := invoke(arguments)!
		assert status == 126 && diagnostic != '' && !os.exists(result), diagnostic
	}
	os.chmod(observer, 0o644)!
	status, diagnostic := invoke([runner, runtime, observer])!
	assert status == 126 && diagnostic.contains('ordinary absolute packaged paths') && !os.exists(result)
	os.chmod(observer, 0o755)!
	// An ordinary executable that execv cannot load must report refusal itself.
	failed, reason := invoke([runner, runtime, invalid])!
	assert failed == 126 && reason.contains('could not be executed') && !os.exists(result)
	println('NEOVIM RUNNER missing/relative/symlink/special/nondirectory/nonexecutable paths and failed exec refuse without child or shell fallback PASS')
}

fn main() {
	if os.base(os.executable()) == 'observer' {
		os.write_file(os.getenv('VINIX_NEOVIM_OBSERVATION'), json2.encode(Observation{
			arguments: os.args, runtime: os.getenv('VIMRUNTIME'), vim: os.getenv('VIM'), libraries: os.getenv('LD_LIBRARY_PATH')
		}) + '\n') or { eprintln(err); exit(1) }
		return
	}
	check() or { eprintln(err); exit(1) }
}
