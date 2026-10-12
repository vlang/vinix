// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import hosttest
import json2
import os

fn copy_file(source string, target string) ! { os.write_file_array(target, os.read_bytes(source)!)! }

pub fn copy_tree_merge(source string, target string) ! {
	mkdirs(target)!
	for name in os.ls(source)! {
		from := source + '/' + name
		to := target + '/' + name
		if os.is_dir(from) { copy_tree_merge(from, to)! }
		else { hosttest.module_copy_file_preserving_stat(from, to)! }
	}
	hosttest.module_copy_directory_stat(source, target)!
}

pub fn prepare_arm_v5(context Context) !int {
	return prepare_arm(context, 'v5')!
}

pub fn prepare_arm(context Context, version string) !int {
	if version !in ['v5', 'v6'] { return error('invalid ARM preparation version') }
	previous := if version == 'v5' { 'v4' } else { 'v5' }
	state := if context.state == os.dir(context.origin) { context.root + '/build/useralloc-arm-' + version + '-final' } else { context.state }
	old := context.root + '/build/useralloc-arm-' + previous + '-final'
	libs := context.root + '/third_party/useralloc-libc/build/useralloc'
	captured(['cp', '-cR', old + '/rootfs', state + '/rootfs'])!
	rootfs := state + '/rootfs'
	for name in ['verify.c', 'verify-all-classes.c', 'clock.c'] { copy_file(context.root + '/tests/user-alloc/' + name, state + '/' + name)! }
	copy_file(old + '/launcher.c', state + '/launcher.c')!
	for policy in ['optimized', 'disabled'] {
		stage := libs + '/' + policy + '-arm126-' + version + '-final'
		sysroot := state + '/sysroot-' + policy
		captured(['cp', '-cR', old + '/sysroot-' + policy, sysroot])!
		copy_tree_merge(stage + '/usr/include', sysroot + '/include')!
		for name in ['libc.a', 'libc.so'] {
			path := sysroot + '/lib/' + name
			os.rm(path) or { if os.exists(path) || os.is_link(path) { return err } }
			copy_file(stage + '/usr/lib/' + name, path)!
		}
		manifest := read_json(stage + '/usr/share/vinix/musl-build.json')!
		write_json(state + '/musl-' + policy + '.json', manifest)!
		loader := rootfs + '/lib/ld-musl-aarch64-' + policy + '.so.1'
		copy_file(stage + '/lib/ld-musl-aarch64.so.1', loader)!
		os.chmod(loader, 0o755)!
		checked_hash(loader, manifest['libc_so_sha256']!.str())!
		checked_hash(sysroot + '/lib/libc.a', manifest['libc_a_sha256']!.str())!
	}
	mut commands := []json2.Any{}
	for value in read_json(old + '/build.json')!['commands']!.as_array() {
		command := strings(value)!.map(it.replace('useralloc-arm-' + previous + '-final', 'useralloc-arm-' + version + '-final').replace(context.root + '/build/useralloc-arm-' + version + '-final', state))
		captured(command)!
		commands << json2.Any(command.map(json2.Any(it)))
	}
	if commands.len == 0 { return error('ARM compile commands are missing') }
	// parents=True, exist_ok=False: a previously built kernel is retained.
	if os.exists(state + '/kernel/bin') { return error('ARM kernel output already exists') }
	mkdirs(state + '/kernel/bin')!
	kernel := context.root + '/build/useralloc-kernel-speed-' + previous + '/aarch64/vinix-aarch64'
	checked_hash(kernel, if version == 'v5' { 'c617cb9d695bccc3c7ada841fa60ac65fd45b942f45d3462b44c3f0378a995c9' } else { core_kernel('aarch64')! })!
	copy_file(kernel, state + '/kernel/bin/vinix')!
	mut env := os.environ()
	env['COPYFILE_DISABLE'] = '1'
	checked(['tar', '--format=ustar', '-cf', state + '/initramfs.tar', '-C', rootfs, '.'], '', env, state + '/archive.log')!
	versions := captured([commands[0].as_array()[0].str(), '--version'])!.split_into_lines()
	if versions.len == 0 { return error('ARM compiler version missing') }
	mut sources := map[string]json2.Any{}
	for name in ['verify.c', 'verify-all-classes.c', 'clock.c', 'launcher.c'] { sources[name] = digest(state + '/' + name)! }
	mut artifacts := map[string]json2.Any{}
	artifact_hashes(rootfs, rootfs, mut artifacts)!
	build := map[string]json2.Any{
		'commands': json2.Any(commands)
		'compiler': json2.Any(versions[0])
		'source_sha256': json2.Any(sources)
		'artifacts_sha256': json2.Any(artifacts)
		'kernel_sha256': json2.Any(digest(state + '/kernel/bin/vinix')!)
		'initramfs_sha256': json2.Any(digest(state + '/initramfs.tar')!)
	}
	write_json(state + '/build.json', build)!
	println(json2.encode(build, prettify: true))
	return 0
}

fn artifact_hashes(directory string, root string, mut result map[string]json2.Any) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		if os.is_file(path) { result[path[root.len + 1..]] = digest(path)! }
		else if os.is_dir(path) && !os.is_link(path) { artifact_hashes(path, root, mut result)! }
	}
}
