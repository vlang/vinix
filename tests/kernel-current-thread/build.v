// SPDX-License-Identifier: GPL-2.0-or-later
// Build only committed kernel sources plus the two checked accessor inputs.
module main

import crypto.sha256
import json2
import os

fn main() {
	if os.args.len != 3 { panic('usage: build ISOLATED_WORKTREE CURRENT_V') }
	repo := os.real_path(os.getwd())
	worktree := os.real_path(os.args[1])
	v := os.real_path(os.args[2])
	assert worktree != repo && !worktree.starts_with(repo + '/')
	identity := os.exec(['git', '-C', worktree, 'rev-parse', 'HEAD'])
	assert identity.exit_code == 0
	mut hashes := map[string]json2.Any{}
	for file in ['kernel/proc/proc_arm64.v', 'kernel/aarch64/cpu/cpu.v'] {
		original := os.exec(['git', '-C', worktree, 'show', 'HEAD:' + file])
		assert original.exit_code == 0 && os.read_file(worktree + '/' + file)! == original.output
		input := os.read_file(repo + '/' + file)!
		hashes[file] = json2.Any(sha256.sum(input.bytes()).hex())
		os.write_file(worktree + '/' + file, input)!
	}
	for dep in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/lwip', 'c/uacpi', 'c/nanoprintf.h'] {
		assert os.exists(repo + '/kernel/' + dep)
		assert !os.exists(worktree + '/kernel/' + dep)
		os.symlink(repo + '/kernel/' + dep, worktree + '/kernel/' + dep)!
	}
	os.write_file(os.dir(worktree) + '/inputs.json', json2.encode({
		'kernel_revision': json2.Any(identity.output.trim_space()),
		'compiler': json2.Any(v), 'overrides_sha256': json2.Any(hashes)
	}, prettify: true))!
	os.chdir(worktree + '/kernel')!
	mut process := os.new_process('make')
	defer { process.close() }
	process.set_args(['-j1', 'ARCH=aarch64', 'LIMINE_MP=1',
		'CC=/opt/homebrew/opt/llvm/bin/clang',
		'LD_AARCH64=/opt/homebrew/opt/lld/bin/ld.lld',
		'AR=/opt/homebrew/opt/llvm/bin/llvm-ar', 'V=' + v,
		'VFLAGS=-new-compiler -no-parallel -nocache', 'PROD=1'])
	// Inherit stdout/stderr so guard termination still retains build diagnostics.
	process.run()
	process.wait()
	if process.code != 0 { exit(process.code) }
	bytes := os.read_bytes('bin/vinix')!
	os.write_file(os.dir(worktree) + '/kernel-sha256', sha256.sum(bytes).hex() + '\n')!
	println('CURRENT-THREAD-KERNEL-BUILD-PASS')
}
