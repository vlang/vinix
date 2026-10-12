// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import hosttest
import json2
import os
import crypto.sha256

pub fn compile_core(context Context, arch string) !map[string]json2.Any {
	state := context.state + '/core-' + arch
	mkdirs(state)!
	if os.exists(state + '/compile.json') {
		manifest := read_json(state + '/compile.json')!
		for key, file in {'init_sha256': 'init', 'initramfs_sha256': 'initramfs.tar', 'test_source_sha256': 'test.c', 'boundary_supplement_sha256': 'pagetable.c'} { checked_hash(state + '/' + file, manifest[key]!.str())! }
		checked_hash(manifest['stage']!.str() + '/usr/lib/libc.a', manifest['static_libc_sha256']!.str())!
		return manifest
	}
	old := context.root + '/build/useralloc-kernel-speed-v5'
	stage := context.root + '/third_party/useralloc-libc/build/useralloc/' + if arch == 'x86_64' { 'optimized-v6-final' } else { 'optimized-arm126-v6-final' }
	provenance := read_json(stage + '/usr/share/vinix/musl-build.json')!
	patches := provenance['patches']!.as_array().filter(it.as_map()['name']!.str() == 'malloc-retain.patch')
	if patches.len == 0 || patches[0].as_map()['sha256']!.str() != core_patch { return error('core allocator patch differs') }
	lib := stage + '/usr/lib/libc.a'
	checked_hash(lib, provenance['libc_a_sha256']!.str())!
	for name, expected in {'test.c': core_test, 'pagetable.c': core_table} {
		checked_hash(old + '/core-' + arch + '/' + name, expected)!
		os.cp(old + '/core-' + arch + '/' + name, state + '/' + name)!
		checked_hash(state + '/' + name, expected)!
	}
	os.cp(stage + '/usr/share/vinix/musl-build.json', state + '/musl-build.json')!
	prior := read_json(old + '/core-' + arch + '/compile.json')!
	command := strings(prior['compile_command']!)!.map(it.replace(old + '/core-' + arch, state).replace('optimized-v5-final', 'optimized-v6-final').replace('optimized-arm126-v5-final', 'optimized-arm126-v6-final'))
	if command.len < 4 { return error('core compile command is incomplete') }
	diagnostics := [...command[..command.len - 4], '-Wl,-Map,' + state + '/link.map', '-Wl,-t', ...command[command.len - 4..]]
	versions := captured([command[0], '--version'])!.split_into_lines()
	if versions.len == 0 || versions[0] != provenance['compiler_version']!.str() || !versions[0].contains('14.2.0') { return error('core compiler identity differs') }
	checked(diagnostics, context.root, os.environ(), state + '/compile.log')!
	if !text(state + '/compile.log')!.contains(lib) || !text(state + '/link.map')!.contains(lib) { return error('static core archive linkage not proved') }
	readelf := '/opt/homebrew/opt/musl-cross/bin/' + arch + '-linux-musl-readelf'
	checked([readelf, '-h', '-l', '-d', state + '/init'], context.root, os.environ(), state + '/elf.log')!
	elf := text(state + '/elf.log')!
	if elf.contains('INTERP') || !elf.contains('There is no dynamic section') { return error('core executable is not static') }
	rootfs := state + '/rootfs'
	for name in ['', '/sbin', '/root', '/dev', '/tmp'] { mkdirs(rootfs + name)! }
	if arch == 'x86_64' { os.cp(state + '/init', rootfs + '/sbin/init')!; os.chmod(rootfs + '/sbin/init', 0o755)! }
	deterministic_archive(rootfs, state + '/initramfs.tar')!
	// The saved wrapper is now native; compiled artifacts carry its new name.
	if os.is_file(context.state + '/run') { os.cp(context.state + '/run', state + '/run')!; os.chmod(state + '/run', 0o755)! }
	mut crt := map[string]json2.Any{}
	for name in os.ls(stage + '/usr/lib')! { if name.starts_with('crt') && name.ends_with('.o') { crt[name] = digest(stage + '/usr/lib/' + name)! } }
	manifest := map[string]json2.Any{
		'compile_command': json2.Any(command.map(json2.Any(it)))
		'diagnostic_compile_command': json2.Any(diagnostics.map(json2.Any(it)))
		'diagnostics_note': json2.Any('Only -Wl,-Map and -Wl,-t added for actual archive linkage proof; identical prior core code generation flags.')
		'stage': json2.Any(stage)
		'test_source_sha256': json2.Any(core_test)
		'original_core_source_sha256': prior['original_core_source_sha256']!
		'boundary_supplement_sha256': json2.Any(core_table)
		'core_source_bundle_sha256': json2.Any(core_bundle(state)!)
		'init_sha256': json2.Any(digest(state + '/init')!)
		'static_libc_sha256': json2.Any(digest(lib)!)
		'crt_sha256': json2.Any(crt)
		'allocator_patch_sha256': json2.Any(core_patch)
		'compiler': json2.Any(versions[0])
		'initramfs_sha256': json2.Any(digest(state + '/initramfs.tar')!)
		'kernel_sha256': json2.Any(core_kernel(arch)!)
		'harness_sha256': json2.Any('3f3d4852c58548bc7ade08a1c8f4850c259f592f3816f71d78fda8c45d38eb8c')
		'archive_linkage_verified': json2.Any(true)
		'static_elf_verified': json2.Any(true)
		'link_map_sha256': json2.Any(digest(state + '/link.map')!)
		'compile_log_sha256': json2.Any(digest(state + '/compile.log')!)
		'musl_build_sha256': json2.Any(digest(state + '/musl-build.json')!)
		'built_utc': json2.Any(now())
	}
	atomic_json(state + '/compile.json', manifest)!
	return manifest
}

pub fn core_image(context Context, manifest map[string]json2.Any) !map[string]json2.Any {
	state := context.state + '/core-x86_64'
	if os.exists(state + '/embedded-input-check.json') {
		proof := read_json(state + '/embedded-input-check.json')!
		checked_hash(state + '/test.iso', proof['iso_sha256']!.str())!
		checked_hash(state + '/embedded-kernel', core_kernel('x86_64')!)!
		checked_hash(state + '/embedded-initramfs.tar', proof['embedded_initramfs_sha256']!.str())!
		return proof
	}
	build := state + '/iso-build'
	mkdirs(build + '/limine')!
	prior := context.root + '/build/useralloc-kernel-speed-v5/core-x86_64/iso-build/limine'
	for name in os.ls(prior)! { hosttest.module_copy_file_preserving_stat(prior + '/' + name, build + '/limine/' + name)! }
	mut env := os.environ()
	configured := {
		'VINIX_AMD64_ISO_BUILD_DIR': build
		'VINIX_AMD64_KERNEL': context.root + '/build/useralloc-kernel-speed-v5/x86_64/vinix-x86_64'
		'VINIX_AMD64_INITRAMFS': state + '/initramfs.tar'
		'VINIX_AMD64_ISO': state + '/test.iso'
	}
	for key, value in configured { env[key] = value }
	script := context.root + '/third_party/useralloc-speed-v5/build-support/build-amd64-iso.sh'
	atomic_json(state + '/image-build.json', {'command': json2.Any([json2.Any(script)]), 'environment': json2.Any(hosttest.string_map(configured)), 'script_sha256': json2.Any(digest(script)!)})!
	checked([script], context.root, env, state + '/image-build.log')!
	checked(['xorriso', '-osirrox', 'on', '-indev', state + '/test.iso', '-extract', '/boot/vinix', state + '/embedded-kernel', '-extract', '/boot/initramfs.tar', state + '/embedded-initramfs.tar'], context.root, os.environ(), state + '/embedded-input-check.log')!
	checked_hash(state + '/embedded-kernel', core_kernel('x86_64')!)!
	init := archive_bytes(state + '/embedded-initramfs.tar', './sbin/init')!
	image_id_bytes := archive_bytes(state + '/embedded-initramfs.tar', './.vinix-image-id')!
	hosttest.module_decode_utf8(image_id_bytes.bytestr())!
	image_id := image_id_bytes.bytestr().trim_space()
	init_sha := sha256.sum(init).hex()
	if init_sha != manifest['init_sha256']!.str() || image_id != manifest['initramfs_sha256']!.str()[..16] { return error('completed core image payload differs') }
	proof := map[string]json2.Any{
		'iso_sha256': json2.Any(digest(state + '/test.iso')!)
		'embedded_kernel_sha256': json2.Any(digest(state + '/embedded-kernel')!)
		'embedded_initramfs_sha256': json2.Any(digest(state + '/embedded-initramfs.tar')!)
		'embedded_init_sha256': json2.Any(init_sha)
		'pre_image_id_initramfs_sha256': manifest['initramfs_sha256']!
		'image_id': json2.Any(image_id)
		'verified_utc': json2.Any(now())
		'independent_completed_iso_extraction': json2.Any(true)
	}
	atomic_json(state + '/embedded-input-check.json', proof)!
	return proof
}
