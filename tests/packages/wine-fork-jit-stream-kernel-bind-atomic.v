// SPDX-License-Identifier: GPL-2.0-or-later
// Bind the retained atomic kernel to its real build and original complete audit.
module main

import hwhost
import json2
import os
import tools.packages.winejitstream

const base = '/Users/alex/Library/Caches/vinix-codex/section14'
const audit = base + '/matched-peer-frame-atomic-20261026'
const build = audit + '/build-02'
const retained = base + '/matched-peer-frame-atomic-kernel-20261026'
const retained_receipt = retained + '/kernel-seal.json'
const retained_manifest = retained + '-seal-01/complete/inventory.json'
const manifest = audit + '-seal-01/complete/inventory.json'
const checker = base + '/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const checker_source = '/Users/alex/code/vinix/tests/kernel-allocs/frame-page-seal.v'
const revision = '9acefa77bee69247c837e97987a2377536aa41cc'
const kernel = retained + '/kernel-aarch64/bin/vinix'
const kernel_sha = '1111f8d6451a0ab94361c3ebf006e9ceed62baea9dd395ac0a5c3caa7fb3a254'
const pins = {
	manifest: 'd7764b47d4c617550ed67af5eee5167392f818ea51e884d1a6abaf3469acf118'
	checker: 'fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6'
	checker_source: '8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4'
	build + '/qualification.json': '7c8af86382b7df1a131cc9bf0cdaa2dadf87719e4d33a9dfa011ffaf2e259fef'
	build + '/aarch64/build.status.json': 'ea19723ed44c833fa1f2e727a28a9078177ff2c9dfd04e0a32fca7c9359edf2d'
	build + '/source-revision.txt': '03cb3a485a13a0dfa36f70cd5312b7ed6585d7cc469d50f898fdd19d9c416c18'
	build + '/source.patch': 'c1891d5ffe3823d9d7bfe9b3b47ba14fab590f8e8e12f2afb0d47b28cc2bb5f6'
	build + '/aarch64/bin/vinix': kernel_sha
	retained_receipt: '2d93f496c9f17a029eff5691070fb6093cad741380b28a87736f12ebfa35e5cb'
	retained_manifest: '3a36d8ec634fa43d416fa3a4ce0ba726eea35527dc8c1faac893faa0feab4a1f'
	retained + '/original-check.status.json': '8dee23d939022eed0cb6a42bb9120729135bb2e04cadf043f3b5c03c15130d3e'
	retained + '/original-check.log': 'a0f49b6703f4c067b1166aebd9cfe67bdc22b9c52ab17c7dbbacea91a20e82b7'
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

struct RetainedKernel {
	elf_path string
	elf_sha256 string
}

struct RetainedReceipt {
	format int
	profile string
	source_revision string
	source_patch_sha256 string
	kernels map[string]RetainedKernel
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
	retained_receipt_path string = retained_receipt
	retained_receipt_sha256 string = pins[retained_receipt]
	retained_manifest_path string = retained_manifest
	retained_manifest_sha256 string = pins[retained_manifest]
	audit_root string = audit
	audit_manifest_path string = manifest
	audit_manifest_sha256 string = pins[manifest]
	audit_checker_path string = checker
	audit_checker_sha256 string = pins[checker]
	audit_check_log_sha256 string
	scope string = 'Receipt adaptation of the real atomic build02 production ALLOC_TRACK ARM build: base9ace plus seven reviewed atomic peer/frame production patch files. Retained kernel bytes equal the original qualified ELF. Original complete raw audit checked at adaptation time; selected-copy manifest retained as a pinned reference, without another full selected-copy audit. No new kernel build, target program build or VM. Signal/clone/process sources remain base9ace; this is an unchanged-signal controlled retest input, not current-main signal qualification.'
}

fn selected(root string) !map[string]winejitstream.NativePin {
	mut result := map[string]winejitstream.NativePin{}
	for path, sum in pins {
		if os.real_path(path) != path || os.lstat(path)!.get_filetype() != .regular
			|| os.lstat(path)!.size > 128 * 1024 * 1024
			|| winejitstream.native_input_digest(path)! != sum {
			return error('atomic matched build input differs: ' + path)
		}
		winejitstream.native_input_add(path, mut result)!
	}
	for path in [os.executable(), root + '/tests/packages/wine-fork-jit-stream-kernel-bind-atomic.v'] {
		winejitstream.native_input_add(path, mut result)!
	}
	return result
}

fn bind() ! {
	$if prod {} $else { return error('kernel binding adapter requires production embedded sources') }
	if os.args.len != 3 { return error('usage: kernel-bind-atomic ROOT NEW_FIXED_ATOMIC_BIND_01_OUTPUT') }
	root := os.args[1]
	output := os.args[2]
	if os.real_path(root) != root || os.lstat(root)!.get_filetype() != .directory
		|| output != base + '/wine-jit-stream-native-kernel-bind-atomic-01'
		|| os.exists(output) || os.is_link(output) || os.real_path(os.dir(output)) != os.dir(output) {
		return error('requires canonical source root and fresh fixed atomic binding output')
	}
	if os.read_file(root + '/tests/packages/wine-fork-jit-stream-kernel-bind-atomic.v')!
		!= $embed_file('wine-fork-jit-stream-kernel-bind-atomic.v').to_string() {
		return error('compiled atomic binding source differs')
	}
	winejitstream.native_require_free(base, winejitstream.native_free_floor(true))!
	before := selected(root)!
	status := json2.decode[BuildStatus](os.read_file(build + '/aarch64/build.status.json')!)!
	qualification := json2.decode[Qualification](os.read_file(build + '/qualification.json')!)!
	copy := json2.decode[RetainedReceipt](os.read_file(retained_receipt)!)!
	if status != BuildStatus{cleanup: 'leader reaped; group absent', elapsed_ms: '95824', exit_code: '0'}
		|| qualification.aarch64_elf != kernel_sha
		|| qualification.aarch64_c != '87166ca286e94f5cf9b827e1ffd09bc8c1b6aebf5994188de0b0e3e30a454855'
		|| os.read_file(build + '/source-revision.txt')! != revision + '\n'
		|| copy.format != 2 || copy.profile != 'matched-peer-frame-atomic-20261026'
		|| copy.source_revision != revision || copy.source_patch_sha256 != pins[build + '/source.patch']
		|| copy.kernels['aarch64'] != RetainedKernel{elf_path: 'kernel-aarch64/bin/vinix', elf_sha256: kernel_sha} {
		return error('atomic actual build status, qualification or retained receipt differs')
	}
	os.mkdir(output)!
	os.write_file(output + '/inputs-before.json', json2.encode(before) + '\n')!
	argv := [checker, 'check', audit, manifest]
	os.write_file(output + '/check.argv.json', json2.encode(argv) + '\n')!
	// The unchanged original checker is a leaf, with no nested guard group.
	hwhost.run_tool(argv, map[string]string{}, output + '/check.log', 300)!
	if os.read_file(output + '/check.log')! != 'FRAME-PAGE COMPLETE STATE CHECK PASS\n' {
		return error('original complete atomic matched audit did not pass')
	}
	after := selected(root)!
	if before != after { return error('atomic binding inputs changed during full audit') }
	os.write_file(output + '/inputs-after.json', json2.encode(after) + '\n')!
	binding := KernelBinding{outputs: {kernel: kernel_sha}, original_build_status: status,
		audit_check_log_sha256: winejitstream.native_input_digest(output + '/check.log')!}
	os.write_file(output + '/kernel-binding.json', json2.encode(binding) + '\n')!
	winejitstream.native_require_free(output, winejitstream.native_free_floor(false))!
	println('PASS adapted original atomic build02 ARM receipt and retained kernel (no target execution)')
}

fn main() { bind() or { eprintln(err); exit(1) } }
