// SPDX-License-Identifier: GPL-2.0-or-later
module main

import campaignhost
import hosttest
import json2
import os

fn qualify(work string, image bool) ! {
	os.mkdir(work)!
	context := campaignhost.Context{root: hosttest.root(), state: work, origin: work + '/origin'}
	for arch in ['x86_64', 'aarch64'] {
		manifest := campaignhost.compile_core(context, arch)!
		assert manifest['archive_linkage_verified']!.bool() && manifest['static_elf_verified']!.bool()
		assert manifest['test_source_sha256']!.str() == campaignhost.core_test
		assert manifest['boundary_supplement_sha256']!.str() == campaignhost.core_table
		assert manifest['allocator_patch_sha256']!.str() == campaignhost.core_patch
		campaignhost.checked(campaignhost.strings(manifest['compile_command']!)!, context.root, os.environ(), work + '/core-' + arch + '/compile-exact.log')!
		assert campaignhost.digest(work + '/core-' + arch + '/init')! == manifest['init_sha256']!.str(), 'diagnostic linker flags changed the executable'
		hosttest.write_json(work + '/core-' + arch + '/compile-exact-flags.json', {'diagnostic_and_exact_flags_binary_identical': json2.Any(true), 'init_sha256': manifest['init_sha256']!})!
		assert manifest == campaignhost.compile_core(context, arch)!
		state := work + '/core-' + arch
		original := os.read_bytes(state + '/init')!
		os.write_file_array(state + '/init', [...original, u8(0)])!
		mut refused := false
		campaignhost.compile_core(context, arch) or { refused = true }
		assert refused, 'changed executable accepted by resume'
		os.write_file_array(state + '/init', original)!
		assert manifest == campaignhost.compile_core(context, arch)!
		println('REAL GNU CORE COMPILE / static ELF / linker map / immutable C sources / resume and changed executable refusal: PASS ' + arch)
		flush_stdout()
	}
	if image {
		base := campaignhost.read_json(work + '/core-x86_64/compile.json')!
		proof := campaignhost.core_image(context, base)!
		assert proof['independent_completed_iso_extraction']!.bool()
		assert proof['embedded_init_sha256']! == base['init_sha256']!
		assert proof == campaignhost.core_image(context, base)!
		println('REAL CORE ISO / independent kernel, archive, init and image-ID extraction / resume: PASS')
		flush_stdout()
	}
	hosttest.write_json(work + '/qualification.json', {'status': json2.Any('PASS'), 'architectures': json2.Any(['x86_64', 'aarch64'].map(json2.Any(it))), 'image': json2.Any(image)})!
}

fn main() {
	if os.args.len !in [2, 3] || (os.args.len == 3 && os.args[2] != '--image') { eprintln('usage: test-core-build NEW_STATE [--image]'); exit(2) }
	qualify(os.args[1], os.args.len == 3) or { eprintln(err); exit(1) }
}
