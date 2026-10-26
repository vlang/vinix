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

// Optional uncommitted changes are copied and pinned before application. This
// keeps a kernel candidate testable without committing it before guest checks.
fn apply_source_patch(root string, worktree string, source string, mut pins map[string]string) !string {
	copy_pin(source, root + '/source.patch', mut pins)!
	pins[root + '/source.patch'] = hash(root + '/source.patch')!
	command(root, 'patch-check', ['git', '-C', worktree, 'apply', '--check', root + '/source.patch'])!
	command(root, 'patch-apply', ['git', '-C', worktree, 'apply', root + '/source.patch'])!
	if command(root, 'patch-untracked', ['git', '-C', worktree, 'ls-files', '--others', '-z'])! != '' {
		return error('patch may only change tracked kernel files')
	}
	names := command(root, 'patch-paths', ['git', '-C', worktree, 'diff', '--name-only', '-z'])!
	if names == '' { return error('patch must change tracked kernel sources') }
	for name in names.split('\x00') {
		if name != '' && !name.starts_with('kernel/') { return error('patch may only change tracked kernel files') }
	}
	return command(root, 'patch-diff', ['git', '-C', worktree, 'diff', '--binary', '--', 'kernel'])!
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

fn tracked_pin(path string) !string {
	return match os.lstat(path)!.get_filetype() {
		.regular { hash(path)! }
		.symbolic_link { 'symlink:' + os.readlink(path)! }
		else { return error('tracked build input must be a file or symlink: ' + path) }
	}
}

fn verify_tracked_inputs(root string, expected map[string]string) ! {
	for relative, pin in expected {
		if tracked_pin(root + '/' + relative)! != pin {
			return error('tracked source changed: ' + relative)
		}
	}
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
	// The host generator imports tracked module symlinks. Preserve their
	// targets as inputs instead of hashing the directories they resolve to.
	os.mkdir(root + '/tracked')!
	os.write_file(root + '/tracked/file.v', 'module fixture')!
	os.symlink('file.v', root + '/tracked/module')!
	tracked := {
		'file.v': tracked_pin(root + '/tracked/file.v')!
		'module': tracked_pin(root + '/tracked/module')!
	}
	verify_tracked_inputs(root + '/tracked', tracked)!
	os.rm(root + '/tracked/module')!
	os.symlink('other.v', root + '/tracked/module')!
	rejected = false
	verify_tracked_inputs(root + '/tracked', tracked) or { rejected = true }
	if !rejected { return error('changed tracked symlink accepted') }
	os.rm(root + '/tracked/module')!
	os.write_file(root + '/tracked/module', 'file.v')!
	rejected = false
	verify_tracked_inputs(root + '/tracked', tracked) or { rejected = true }
	if !rejected { return error('tracked symlink replaced with file accepted') }
	println('UNIX-RECVMSG-KERNEL-TRACKED-PASS unchanged=1 rejected=2')
	os.mkdir_all(root + '/patch-repo/kernel')!
	os.mkdir(root + '/patch-good')!
	os.mkdir(root + '/patch-bad')!
	command(root, 'patch-repo-init', ['git', '-C', root + '/patch-repo', 'init'])!
	os.write_file(root + '/patch-repo/kernel/policy.v', 'old\n')!
	command(root, 'patch-repo-add', ['git', '-C', root + '/patch-repo', 'add', 'kernel/policy.v'])!
	valid_patch := 'diff --git a/kernel/policy.v b/kernel/policy.v\n--- a/kernel/policy.v\n+++ b/kernel/policy.v\n@@ -1 +1 @@\n-old\n+new\n'
	os.write_file(root + '/valid.patch', valid_patch)!
	mut patch_pins := map[string]string{}
	applied := apply_source_patch(root + '/patch-good', root + '/patch-repo', root + '/valid.patch', mut patch_pins)!
	if applied == '' || os.read_file(root + '/patch-repo/kernel/policy.v')! != 'new\n'
		|| hash(root + '/patch-good/source.patch')! != hash(root + '/valid.patch')! {
		return error('applied patch was not retained or did not change source')
	}
	rejected = false
	apply_source_patch(root + '/patch-bad', root + '/patch-repo', root + '/valid.patch', mut patch_pins) or { rejected = true }
	if !rejected { return error('inapplicable patch accepted') }
	os.mkdir(root + '/patch-outside')!
	os.write_file(root + '/patch-repo/outside.v', 'old\n')!
	command(root, 'patch-repo-add-outside', ['git', '-C', root + '/patch-repo', 'add', 'outside.v'])!
	os.write_file(root + '/outside.patch', 'diff --git a/outside.v b/outside.v\n--- a/outside.v\n+++ b/outside.v\n@@ -1 +1 @@\n-old\n+new\n')!
	rejected = false
	apply_source_patch(root + '/patch-outside', root + '/patch-repo', root + '/outside.patch', mut patch_pins) or { rejected = true }
	if !rejected { return error('patch outside kernel accepted') }
	// Restore this tracked path so the next case isolates new-file rejection.
	os.write_file(root + '/patch-repo/outside.v', 'old\n')!
	os.mkdir(root + '/patch-new')!
	os.write_file(root + '/new.patch', 'diff --git a/kernel/new.v b/kernel/new.v\nnew file mode 100644\n--- /dev/null\n+++ b/kernel/new.v\n@@ -0,0 +1 @@\n+untracked\n')!
	rejected = false
	apply_source_patch(root + '/patch-new', root + '/patch-repo', root + '/new.patch', mut patch_pins) or { rejected = true }
	if !rejected { return error('untracked patch output accepted') }
	println('UNIX-RECVMSG-KERNEL-PATCH-PASS applied=1 rejected=3')
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
	if os.args.len !in [6, 7] {
		return error('usage: kernel-build REPO V_COMPILER FRESH_ROOT REVISION aarch64|x86_64 [PATCH]')
	}
	repo, compiler, root := os.real_path(os.args[1]), os.real_path(os.args[2]), os.abs_path(os.args[3])
	revision, arch := os.args[4], os.args[5]
	patch := if os.args.len == 7 { os.real_path(os.args[6]) } else { '' }
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
	mut sparse_paths := ['kernel', 'tests/unix-recvmsg-flags']
	generator_paths := ['tests/native-generators', 'tests/linuxkpi/hosttest',
		'build-support/cachecli', 'build-support/cachekey', 'tools/sourcecommand',
		'build-support/run-v-tool.sh', 'build-support/find-v.sh']
	if arch == 'x86_64' {
		// Cone mode includes immediate parent files (the two shell entry points).
		sparse_paths << generator_paths[..5]
	}
	mut sparse_command := ['git', '-C', worktree, 'sparse-checkout', 'set']
	sparse_command << sparse_paths
	command(root, 'sparse', sparse_command)!
	command(root, 'checkout', ['git', '-C', worktree, 'checkout', '--detach', resolved])!
	mut pins := map[string]string{}
	copy_pin(os.real_path(@FILE), root + '/builder.v', mut pins)!
	applied_patch := if patch != '' { apply_source_patch(root, worktree, patch, mut pins)! } else { '' }
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
	if arch == 'x86_64' {
		// The maintained host-generator wrapper uses V's default Boehm GC.
		copy_pin(vroot + '/thirdparty/tcc/lib/libgc.a',
			root + '/compiler/thirdparty/tcc/lib/libgc.a', mut pins)!
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
	mut generator_pins := map[string]string{}
	if arch == 'x86_64' {
		mut args := ['git', '-C', worktree, 'ls-files', '-z']
		args << generator_paths
		for relative in command(root, 'generator-files', args)!.split('\x00') {
			if relative != '' { generator_pins[relative] = tracked_pin(worktree + '/' + relative)! }
		}
	}
	mut tools := map[string]string{}
	for tool in ['/usr/bin/clang', '/opt/homebrew/bin/ld.lld', '/opt/homebrew/opt/llvm/bin/llvm-ar',
		'/usr/bin/make'] {
		tools[tool] = hash(tool)!
	}
	if arch == 'x86_64' {
		host_cc := os.find_abs_path_of_executable('cc')!
		tools[host_cc] = hash(host_cc)!
	}
	os.write_file(root + '/input-pins.json', json2.encode({
		'compiler_and_dependencies': object(pins)
		'kernel':                    object(kernel_pins)
		'host_generator':            object(generator_pins)
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
	verify_tracked_inputs(worktree, kernel_pins)!
	verify_tracked_inputs(worktree, generator_pins)!
	if patch != '' && command(root, 'patch-diff-after', ['git', '-C', worktree, 'diff', '--binary', '--', 'kernel'])! != applied_patch {
		return error('applied patch changed during build')
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
	mut build_info := {
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
	}
	if patch != '' { build_info['source_patch_sha256'] = hash(root + '/source.patch')! }
	os.write_file(root + '/build.json', json2.encode(build_info, prettify: true) + '\n')!
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
