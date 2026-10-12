// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import alpinecore
import hosttest
import json2
import os

pub fn packaging_admission(prior string, arch string, target string) ! {
	if arch !in ['amd64', 'aarch64'] { return error('invalid production packaging architecture') }
	if os.exists(target) { return error('Refusing to reuse a previous output root: ' + target) }
	mkdirs(target)!
	downloads := prior + '/' + arch + '/downloads'
	indexes := [alpinecore.Index{'main', downloads + '/main_APKINDEX'}, alpinecore.Index{'community', downloads + '/community_APKINDEX'}]
	for requests in [['build-base', 'vim'], if arch == 'amd64' { ['zsh', 'vim', 'libuuid'] } else { ['zsh', 'vim'] }] {
		for line in alpinecore.manifest(indexes, requests)!.split_into_lines() {
			parts := line.split('\t')
			if parts.len != 2 || !os.is_file(downloads + '/' + parts[1]) { return error('Missing cached package: ' + line) }
		}
	}
	if os.ls(downloads)!.filter(it.starts_with('oh-my-zsh-') && it.ends_with('.tar.gz')).len == 0 { return error('cached oh-my-zsh archive missing') }
	os.symlink(downloads, target + '/downloads')!
	if arch == 'amd64' {
		archive := prior + '/' + arch + '/alpine-minirootfs-3.21.7-x86_64.tar.gz'
		if !os.is_file(archive) { return error('cached amd64 minirootfs missing') }
		os.symlink(archive, target + '/' + os.base(archive))!
	} else if !os.is_file(downloads + '/alpine-minirootfs-3.21.7-aarch64.tar.gz') { return error('cached ARM minirootfs missing') }
}

pub fn verify_packaging(stage string, archive string, arch string, patch string) !map[string]json2.Any {
	machine := if arch == 'amd64' { 'x86_64' } else { 'aarch64' }
	manifest := read_json(stage + '/usr/share/vinix/musl-build.json')!
	if manifest['arch']!.str() != machine || !gate_passed(manifest['retention']!, json2.Any(true)) || manifest['optimize']!.str() != 'internal,malloc,malloc/mallocng/*.c,string' { return error('production libc recipe differs') }
	patches := manifest['patches']!.as_array().filter(it.as_map()['name']!.str() == 'malloc-retain.patch')
	if patches.len == 0 || patches[0].as_map()['sha256']!.str() != patch || !manifest['compiler_version']!.str().contains('(GCC) 14.2.0') { return error('production libc patch or compiler differs') }
	for name, field in {'lib/ld-musl-' + machine + '.so.1': 'libc_so_sha256', 'usr/lib/libc.a': 'libc_a_sha256'} {
		checked_hash(stage + '/' + name, manifest[field]!.str())!
		bytes := archive_bytes(archive, './' + name)!
		if hosttest.text_sha(bytes.bytestr()) != manifest[field]!.str() { return error('embedded production libc differs: ' + name) }
	}
	if !text(stage + '/usr/include/malloc.h')!.contains('int malloc_trim(size_t);') { return error('production malloc_trim header missing') }
	if os.readlink(stage + '/usr/lib/libc.so')! != '../../lib/ld-musl-' + machine + '.so.1' { return error('production libc link differs') }
	embedded := archive_bytes(archive, './usr/share/vinix/musl-build.json')!
	if hosttest.decode_json(embedded.bytestr())!.as_map() != manifest { return error('embedded production libc manifest differs') }
	return manifest
}

pub fn production_packaging(context Context, arch string) !int {
	if arch == 'both' { production_packaging(context, 'amd64')!; return production_packaging(context, 'aarch64')! }
	work := context.root + '/third_party/useralloc-libc'
	prior := work + '/build/useralloc-production'
	base := if context.state == os.dir(context.origin) { work + '/build/useralloc-production-v3' } else { context.state }
	patch := 'fe6f1a94a9f568823a72ba032ceaa4159adfd529988336dd9fcb5763a21d2578'
	checked_hash(context.root + '/build-support/musl/malloc-retain.patch', patch)!
	target := base + '/' + arch
	packaging_admission(prior, arch, target)!
	prefix := if arch == 'amd64' { 'VINIX_AMD64' } else { 'VINIX_AARCH64' }
	// Keep the archived top-level builder path: it is an explicit prerequisite
	// of this v3 attempt rather than substituting today's image recipe.
	script := context.root + '/build-userland-' + arch + '.sh'
	settings := {prefix + '_USERLAND_BUILD_DIR': target, prefix + '_INITRAMFS': target + '/initramfs.tar', 'VINIX_MUSL_BUILD_DIR': work + '/build/musl', 'VINIX_MUSL_RETAIN': '1', 'VINIX_OPTIMIZED_MUSL': '1', 'VINIX_ALPINE_DEVTOOLS': '1', 'VINIX_ALPINE_BASE_ONLY': '1', 'NPROC': '2', 'ALPINE_VERSION': '3.21.7', 'ALPINE_BRANCH': 'v3.21'}
	inputs := map[string]json2.Any{'builder': json2.Any(script), 'builder_sha256': json2.Any(digest(script)!), 'stage_helper_sha256': json2.Any(digest(hosttest.root() + '/build-support/musl/stage.v')!), 'settings': json2.Any(hosttest.string_map(settings)), 'native_stage': json2.Any(hosttest.root() + '/build-support/musl/stage.v')}
	write_json(target + '/inputs.json', inputs)!
	mut env := os.environ()
	for key, value in settings { env[key] = value }
	ensure_native_script(script)!
	checked([script], context.root, env, target + '/builder.log')!
	archive := target + '/initramfs.tar'
	manifest := verify_packaging(target + '/staging', archive, arch, patch)!
	checked_hash(script, inputs['builder_sha256']!.str())!
	result := map[string]json2.Any{'status': json2.Any('PASS'), 'arch': json2.Any(arch), 'inputs': json2.Any(inputs), 'libc_build': json2.Any(manifest), 'initramfs_sha256': json2.Any(digest(archive)!), 'builder_log_sha256': json2.Any(digest(target + '/builder.log')!)}
	write_json(target + '/results.json', result)!
	println('Production v3 packaging PASS ' + arch + ' ' + target + '/results.json')
	flush_stdout()
	return 0
}
