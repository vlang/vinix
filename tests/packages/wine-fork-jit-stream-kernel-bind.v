// SPDX-License-Identifier: GPL-2.0-or-later
// Adapt the real matched build receipt; this does not build or boot a kernel.
module main

import hwhost
import json2
import os
import tools.packages.winejitstream

const base = '/Users/alex/Library/Caches/vinix-codex/section14'
const audit = base + '/matched-peer-frame-20261026'
const build = audit + '/build-05'
const manifest = base + '/matched-peer-frame-20261026-seal-01/complete/inventory.json'
const checker = base + '/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const checker_source = '/Users/alex/code/vinix/tests/kernel-allocs/frame-page-seal.v'
const revision = '9acefa77bee69247c837e97987a2377536aa41cc'
const kernel = build + '/aarch64/bin/vinix'
const kernel_sha = 'e805a73154d61503d6427f1ccc4d19b1eb9ec802ed38255e059e0b2bd1e83174'
const pins = {
	manifest: '1be74ac86fd98743e6691e9d29e44a20f1476bbc2cb494d157f70de618fa4165'
	checker: 'fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6'
	checker_source: '8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4'
	build + '/qualification.json': '05ea81df65e801356fe4a5dbf185a914dd07b39f927508ec47d036580e02f65c'
	build + '/aarch64/build.status.json': '4d8b2017f87e186416a2e0ade55390ee1ef6b89ed5da75e28fd08c7303ed2fec'
	build + '/source-revision.txt': '03cb3a485a13a0dfa36f70cd5312b7ed6585d7cc469d50f898fdd19d9c416c18'
	build + '/source.patch': '75bef4f8af266a27a4af777c133f6cf4931e7daae73f7d2bb82f4aa560c17e3a'
	kernel: kernel_sha
}

struct BuildStatus {
	cleanup string
	elapsed_ms string
	exit_code string
	reason string
}

struct Qualification {
	aarch64_c string
	aarch64_elf string
	x86_64_c string
	x86_64_elf string
}

struct KernelBinding {
	architecture string = 'arm'
	profile string = 'prod'
	build_executed bool = true
	build_exit_code int
	candidate_commit string = revision
	outputs map[string]string
	source_patch_path string = build + '/source.patch'
	source_patch_sha256 string = pins[build + '/source.patch']
	original_build_status_path string = build + '/aarch64/build.status.json'
	original_build_status BuildStatus
	qualification_path string = build + '/qualification.json'
	qualification_sha256 string = pins[build + '/qualification.json']
	audit_root string = audit
	audit_manifest_path string = manifest
	audit_manifest_sha256 string = pins[manifest]
	audit_checker_path string = checker
	audit_checker_sha256 string = pins[checker]
	audit_check_log_sha256 string
	scope string = 'Receipt adaptation of the real matched05 production ALLOC_TRACK ARM build: base9ace plus seven reviewed peer/frame production patch files. Original complete audit checked at adaptation time. No new kernel build, target program build or VM. Signal/clone/process sources remain those of the earlier failing c6b kernel; this is an unchanged-signal controlled retest input, not current-main signal qualification.'
}

fn selected(root string) !map[string]winejitstream.NativePin {
	mut result := map[string]winejitstream.NativePin{}
	for path, sum in pins {
		if os.real_path(path) != path || os.lstat(path)!.get_filetype() != .regular
			|| os.lstat(path)!.size > 128 * 1024 * 1024
			|| winejitstream.native_input_digest(path)! != sum {
			return error('matched build input differs: ' + path)
		}
		winejitstream.native_input_add(path, mut result)!
	}
	for path in [os.executable(), root + '/tests/packages/wine-fork-jit-stream-kernel-bind.v'] {
		winejitstream.native_input_add(path, mut result)!
	}
	return result
}

fn bind() ! {
	$if prod {} $else { return error('kernel binding adapter requires production embedded sources') }
	if os.args.len != 3 { return error('usage: kernel-bind ROOT NEW_FIXED_KERNEL_BIND_01_OUTPUT') }
	root := os.args[1]
	output := os.args[2]
	if os.real_path(root) != root || os.lstat(root)!.get_filetype() != .directory
		|| output != base + '/wine-jit-stream-native-kernel-bind-01'
		|| os.exists(output) || os.is_link(output) || os.real_path(os.dir(output)) != os.dir(output) {
		return error('requires canonical source root and fresh fixed binding output')
	}
	if os.read_file(root + '/tests/packages/wine-fork-jit-stream-kernel-bind.v')!
		!= $embed_file('wine-fork-jit-stream-kernel-bind.v').to_string() {
		return error('compiled binding source differs')
	}
	winejitstream.native_require_free(base, winejitstream.native_free_floor(true))!
	before := selected(root)!
	status := json2.decode[BuildStatus](os.read_file(build + '/aarch64/build.status.json')!)!
	qualification := json2.decode[Qualification](os.read_file(build + '/qualification.json')!)!
	if status != BuildStatus{cleanup: 'leader reaped; group absent', elapsed_ms: '207711', exit_code: '0'}
		|| qualification.aarch64_elf != kernel_sha
		|| qualification.aarch64_c != '928c4999d3524052aff22526c3daa34c5bf242e7b58364b45e6bfd564ff59c9d'
		|| os.read_file(build + '/source-revision.txt')! != revision + '\n' {
		return error('matched actual build status, source revision or qualification differs')
	}
	os.mkdir(output)!
	os.write_file(output + '/inputs-before.json', json2.encode(before) + '\n')!
	argv := [checker, 'check', audit, manifest]
	os.write_file(output + '/check.argv.json', json2.encode(argv) + '\n')!
	// The pinned checker is a leaf. Inherit the outer owner's process group;
	// run_tool imposes its deadline and reaps it without a nested guard group.
	hwhost.run_tool(argv, map[string]string{}, output + '/check.log', 300)!
	if os.read_file(output + '/check.log')! != 'FRAME-PAGE COMPLETE STATE CHECK PASS\n' {
		return error('original complete matched audit did not pass')
	}
	after := selected(root)!
	if before != after { return error('binding inputs changed during full audit') }
	os.write_file(output + '/inputs-after.json', json2.encode(after) + '\n')!
	binding := KernelBinding{outputs: {kernel: kernel_sha}, original_build_status: status,
		audit_check_log_sha256: winejitstream.native_input_digest(output + '/check.log')!}
	os.write_file(output + '/kernel-binding.json', json2.encode(binding) + '\n')!
	winejitstream.native_require_free(output, winejitstream.native_free_floor(false))!
	println('PASS adapted original matched05 ARM build receipt (no target execution)')
}

fn main() { bind() or { eprintln(err); exit(1) } }
