// SPDX-License-Identifier: GPL-2.0-or-later
// Build committed kernel sources in a detached sparse worktree.
module main

import crypto.sha256
import json2
import os

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn object(values map[string]string) json2.Any {
	mut result := map[string]json2.Any{}
	for key, value in values { result[key] = value }
	return result
}

fn command(root string, label string, args []string) !string {
	executable := os.find_abs_path_of_executable(args[0])!
	pin := hash(executable)!
	result := os.exec(args)
	os.write_file(root + '/' + label + '.log', result.output)!
	os.write_file(root + '/' + label + '-command.json', json2.encode({
		'argv':              json2.Any(args)
		'executable':        json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'exit_code':         json2.Any(result.exit_code)
	}, prettify: true) + '\n')!
	if hash(executable)! != pin { return error('tool changed during command') }
	if result.exit_code != 0 { return error(label + ' failed; retained command and log') }
	return result.output
}

fn copy_pin(source string, target string, mut pins map[string]string) ! {
	if !os.is_file(source) { return error('regular input required: ' + source) }
	pin := hash(source)!
	os.mkdir_all(os.dir(target))!
	os.cp(source, target)!
	if hash(target)! != pin { return error('source changed during copy') }
	pins[source] = pin
}

fn freeze_tree(source string, target string, mut pins map[string]string) ! {
	if os.is_dir(source) {
		for name in os.ls(source)! {
			if name == '.git' { continue }
			freeze_tree(source + '/' + name, target + '/' + name, mut pins)!
		}
	} else {
		copy_pin(source, target, mut pins)!
	}
}

// Dependencies remain shared with the checkout. Compare their complete path and
// type set as well as hashes so newly added Makefile inputs cannot evade pins.
fn dependency_inventory(path string, mut entries map[string]string) ! {
	match os.lstat(path)!.get_filetype() {
		.directory {
			entries[path] = 'directory'
			for name in os.ls(path)! {
				if name != '.git' { dependency_inventory(path + '/' + name, mut entries)! }
			}
		}
		.regular { entries[path] = 'file:' + hash(path)! }
		else { return error('dependency must contain only regular files and directories: ' + path) }
	}
}

fn verify_dependency_inventory(roots []string, expected map[string]string) ! {
	mut actual := map[string]string{}
	for path in roots { dependency_inventory(path, mut actual)! }
	if actual != expected { return error('shared dependency path, type or contents changed') }
}

fn self_test(root string) ! {
	if os.exists(root) || os.is_link(root) { return error('fresh self-test root required') }
	os.mkdir_all(root + '/dependency')!
	os.write_file(root + '/dependency/old.c', 'original')!
	roots := [root + '/dependency']
	mut expected := map[string]string{}
	dependency_inventory(roots[0], mut expected)!
	verify_dependency_inventory(roots, expected)!
	os.write_file(root + '/dependency/new.c', 'added')!
	mut rejected := false
	verify_dependency_inventory(roots, expected) or { rejected = true }
	if !rejected { return error('added file accepted') }
	os.rm(root + '/dependency/new.c')!
	os.write_file(root + '/dependency/old.c', 'modified')!
	rejected = false
	verify_dependency_inventory(roots, expected) or { rejected = true }
	if !rejected { return error('changed contents accepted') }
	os.rm(root + '/dependency/old.c')!
	rejected = false
	verify_dependency_inventory(roots, expected) or { rejected = true }
	if !rejected { return error('removed path accepted') }
	os.mkdir(root + '/dependency/old.c')!
	rejected = false
	verify_dependency_inventory(roots, expected) or { rejected = true }
	if !rejected { return error('changed type accepted') }
	os.rmdir(root + '/dependency/old.c')!
	os.symlink('/dev/null', root + '/dependency/old.c')!
	rejected = false
	verify_dependency_inventory(roots, expected) or { rejected = true }
	if !rejected { return error('symbolic dependency accepted') }
	println('UNIX-RECVMSG-KERNEL-INVENTORY-PASS unchanged=1 rejected=5')
}

fn freeze_library(source string, target string, mut pins map[string]string) ! {
	for name in os.ls(source)! {
		if name == '.git' { continue }
		path := source + '/' + name
		if os.is_dir(path) {
			freeze_library(path, target + '/' + name, mut pins)!
		} else if os.file_ext(path) in ['.v', '.h', '.c', '.S', '.inc', '.mod'] {
			copy_pin(path, target + '/' + name, mut pins)!
		}
	}
}

fn inventory(root string, prefix string, mut files map[string]string, mut links map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut files, mut links)! }
			.regular { files[key] = hash(root + '/' + key)! }
			.symbolic_link { links[key] = os.readlink(root + '/' + key)! }
			else { return error('unexpected artifact type') }
		}
	}
}

fn run() ! {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		self_test(os.abs_path(os.args[2]))!
		return
	}
	if os.args.len != 6 {
		return error('usage: kernel-build REPO V_COMPILER FRESH_ROOT REVISION aarch64|x86_64')
	}
	repo, compiler, root := os.real_path(os.args[1]), os.real_path(os.args[2]), os.abs_path(os.args[3])
	revision, arch := os.args[4], os.args[5]
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	if os.exists(root) || os.is_link(root) || root == repo || root.starts_with(repo + '/') {
		return error('fresh external root required')
	}
	os.mkdir_all(root)!
	if os.real_path(root) != root { return error('canonical artifact root required') }
	os.chdir(repo)!
	resolved := command(root, 'revision', ['git', 'rev-parse', revision + '^{commit}'])!.trim_space()
	worktree := root + '/source'
	command(root, 'worktree-add', ['git', 'worktree', 'add', '--detach', '--no-checkout', worktree,
		resolved])!
	command(root, 'sparse', ['git', '-C', worktree, 'sparse-checkout', 'set', 'kernel',
		'tests/unix-recvmsg-flags'])!
	command(root, 'checkout', ['git', '-C', worktree, 'checkout', '--detach', resolved])!
	mut pins := map[string]string{}
	copy_pin(os.real_path(@FILE), root + '/builder.v', mut pins)!
	mut shared := map[string]string{}
	mut dependency_roots := []string{}
	mut dependency_entries := map[string]string{}
	for relative in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/lwip', 'c/uacpi',
		'c/nanoprintf.h'] {
		source, target := repo + '/kernel/' + relative, worktree + '/kernel/' + relative
		if os.exists(target) || os.is_link(target) {
			return error('dependency already tracked: ' + relative)
		}
		dependency_roots << source
		dependency_inventory(source, mut dependency_entries)!
		freeze_tree(source, root + '/dependencies/' + relative, mut pins)!
		os.symlink(source, target)!
		shared[target] = source
	}
	// Accept already frozen library closures; source extensions exclude binaries.
	vroot := os.dir(compiler)
	freeze_library(vroot + '/vlib', root + '/compiler/vlib', mut pins)!
	if os.is_dir(vroot + '/thirdparty') {
		freeze_library(vroot + '/thirdparty', root + '/compiler/thirdparty', mut pins)!
	}
	if os.is_file(vroot + '/v.mod') {
		copy_pin(vroot + '/v.mod', root + '/compiler/v.mod', mut pins)!
	}
	copy_pin(compiler, root + '/compiler/v', mut pins)!
	os.chmod(root + '/compiler/v', 0o755)!
	kfiles := command(root, 'kernel-files', ['git', '-C', worktree, 'ls-files', '-z', 'kernel'])!
	mut kernel_pins := map[string]string{}
	for relative in kfiles.split('\x00') {
		if relative == '' { continue }
		kernel_pins[relative] = hash(worktree + '/' + relative)!
	}
	mut tools := map[string]string{}
	for tool in ['/usr/bin/clang', '/opt/homebrew/bin/ld.lld', '/opt/homebrew/opt/llvm/bin/llvm-ar',
		'/usr/bin/make'] {
		tools[tool] = hash(tool)!
	}
	os.write_file(root + '/input-pins.json', json2.encode({
		'compiler_and_dependencies': object(pins)
		'kernel':                    object(kernel_pins)
		'tools':                     object(tools)
		'shared_dependency_links':   object(shared)
		'shared_dependency_entries': object(dependency_entries)
	}, prettify: true) + '\n')!
	verify_dependency_inventory(dependency_roots, dependency_entries)!
	command(root, 'make', ['/usr/bin/make', '-C', worktree + '/kernel', '-j4', 'ARCH=' + arch,
		'LIMINE_MP=1', 'V=' + root + '/compiler/v', 'CC=/usr/bin/clang',
		'LD_AARCH64=/opt/homebrew/bin/ld.lld', 'LD_X86_64=/opt/homebrew/bin/ld.lld',
		'AR=/opt/homebrew/opt/llvm/bin/llvm-ar', 'KERNEL_LINK_SEED=20261026'])!
	verify_dependency_inventory(dependency_roots, dependency_entries)!
	for path, pin in pins { if hash(path)! != pin { return error('shared build input changed') } }
	for relative, pin in kernel_pins {
		if hash(worktree + '/' + relative)! != pin { return error('kernel source changed') }
	}
	for path, pin in tools { if hash(path)! != pin { return error('build tool changed') } }
	for target, source in shared {
		if os.readlink(target)! != source { return error('dependency link changed') }
	}
	elf := worktree + '/kernel/bin/vinix'
	inspection := command(root, 'kernel-elf', ['aarch64-linux-musl-readelf', '-h', '-l', elf])!
	if !(if arch == 'aarch64' {
		inspection.contains('AArch64')
	} else {
		inspection.contains('Advanced Micro Devices X86-64')
	}) || inspection.contains('INTERP') {
		return error('unexpected kernel ELF')
	}
	os.write_file(root + '/build.json', json2.encode({
		'format':                    json2.Any(1)
		'source_revision':           json2.Any(resolved)
		'architecture':              json2.Any(arch)
		'kernel_path':               json2.Any(elf)
		'kernel_sha256':             json2.Any(hash(elf)!)
		'kernel_unix_source_sha256': json2.Any(kernel_pins['kernel/socket/unix/unix.v']!)
		'generated_c_sha256':        json2.Any(hash(worktree + '/kernel/obj/blob.c')!)
		'compiler_sha256':           json2.Any(hash(root + '/compiler/v')!)
		'builder_source_sha256':     json2.Any(hash(root + '/builder.v')!)
		'guest_executed':            json2.Any(false)
		'link_seed':                 json2.Any(20261026)
	}, prettify: true) + '\n')!
	mut files := map[string]string{}
	mut links := map[string]string{}
	inventory(root, '', mut files, mut links)!
	os.write_file(root + '/sha256.json', json2.encode({
		'files': object(files)
		'links': object(links)
	},
		prettify: true
	) + '\n')!
	println('UNIX-RECVMSG-KERNEL-BUILD-PASS root=' + root + ' manifest_sha256=' + hash(root + '/sha256.json')!)
}

run() or {
	eprintln(err)
	exit(1)
}
