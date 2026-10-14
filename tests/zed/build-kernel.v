// SPDX-License-Identifier: GPL-2.0-or-later
// Freeze the kernel and build it away from the concurrently edited checkout.
module main

import os

fn run(program string, args []string) ! {
	mut process := os.new_process(program)
	defer { process.close() }
	process.set_args(args)
	process.run()
	process.wait()
	if process.code != 0 { return error('${program} failed (${process.code})') }
}

fn copy_changed(source string, destination string) ! {
	current := os.read_file(source)!
	previous := os.read_file(destination) or { '' }
	if current != previous { os.cp(source, destination)! }
}

fn main() {
	root := os.real_path('.')
	arch := if os.args.len > 1 { os.args[1] } else { 'aarch64' }
	if arch !in ['aarch64', 'x86_64'] { panic('expected aarch64 or x86_64') }
	work := '${root}/build-aarch64-zed/kernel-source-${arch}'
	if !os.is_dir('${work}/kernel') {
		run('git', ['worktree', 'add', '--detach', work, 'HEAD'])!
	}
	for dependency in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/lwip', 'c/uacpi',
		'c/nanoprintf.h', 'uacpi-repository', 'lwip-repository'] {
		destination := '${work}/kernel/${dependency}'
		if !os.exists(destination) {
			os.mkdir_all(os.dir(destination))!
			os.symlink('${root}/kernel/${dependency}', destination)!
		}
	}
	for path in ['memory/virtual.v', 'aarch64/gic/gic.v', 'sched/sched_arm64.v',
		'sched/membarrier_arm64.v', 'sched/membarrier_amd64.v', 'syscall/table/linux_compat.v'] {
		copy_changed('${root}/kernel/${path}', '${work}/kernel/${path}')!
	}
	// Older snapshots use integer zero for this two-pointer return. Normalize
	// only the frozen build input for current V, without editing shared VFS.
	vfs := '${work}/kernel/fs/vfs.v'
	vfs_source := os.read_file(vfs)!
	vfs_normalized := vfs_source
		.replace('return 0, 0,', 'return unsafe { nil }, unsafe { nil },')
		.replace('return current_node, 0,', 'return current_node, unsafe { nil },')
		.replace('return 0\n', 'return unsafe { nil }\n')
	if vfs_source != vfs_normalized { os.write_file(vfs, vfs_normalized)! }
	llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
	v := os.getenv_opt('V') or { 'v' }
	linker := os.getenv_opt('LD_LLD') or { '/opt/homebrew/opt/lld/bin/ld.lld' }
	run('make', ['-C', '${work}/kernel', '-j4', 'ARCH=${arch}', 'LIMINE_MP=1', 'CC=${llvm}/clang',
		'LD_AARCH64=${linker}', 'LD_X86_64=${linker}', 'AR=${llvm}/llvm-ar', 'V=${v}',
		'VFLAGS=-new-compiler -no-memory-limit', 'PROD=1'])!
	os.cp('${work}/kernel/bin/vinix', '${root}/build-aarch64-zed/kernel-${arch}')!
}
