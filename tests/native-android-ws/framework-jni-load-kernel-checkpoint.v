// SPDX-License-Identifier: GPL-2.0-or-later
// Seal an unbooted, known-profile kernel patch without changing its ancestry.
module main

import crypto.sha256
import json2
import mapsaccountstage as stage
import modulestream
import os

const state = '/Users/alex/.local/state/vinix/android/'
const prepared_root = state + 'maps-framework-boot-r1'
const prepared_seal = '43309208792e5ce55ed9c4b8af9e0ae5b6ff1f849f43b27a04948659224dd499'
const original_stage_pin = 'a87760cf0daef526558da7b2b24068b868fe16f194e2f8692da8548eed8f465b'
const kernel_root = state + 'pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2'
const kernel_manifest = '32a134cc1ee3d02bfb56d91ee429ac3f5fb9895ba525021eb7aa84a7ec64f6ee'
const kernel_build = '1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d'
const kernel_inputs = '67df3894959d2535c96a56957101cc8b40f288e3d96ffdef0c7da34bdc1591a8'
const kernel_pin = 'a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151'
const old_kernel_pin = 'f8d86366353da19545fa6814b7b54d53973e59fdbafe2575c96c13594284b352'
const kernel_tool = '864cd44a611fc4e2f0a5ecb5bc85f2fecaed4ef0768e598a2769b817cc481542'
const kernel_source = '42de9aa5b6671b0c6ab08c68666b040be2ce90da9be17896e165abe8a917b623'
const mtools_pin = 'e8310ca53ac5f471b7cd8b0b4dacd2ef11a57e399e35d034d1b6899e49dd48a6'
const baseline_root = state + 'maps-webview-package-r1'
const baseline_boot = '638f4a8802751cb316c0318158504692bcdb9351f8f29dbbb5979624a8b655d8'
const source = $embed_file(@FILE).to_string()
const clone_tool = '9d1cb6aaeb23bf65ae41fe718f4b020bfc556e1cbc83b41df6ce1d86bb287346'
const clone_source = 'f7f4a61de7a7792c91da821def0fe02d1a3e7cd7ebfe5f0abd0c175a3b584cc5'
const clone_sources = {
	'build-support/android/modulestream/spawn_abi.h': '9b0185468cd58b36dfdf4a17d776ef44fd30006947f2d54b80bf07b18d886b24'
	'build-support/android/modulestream/stream.v': '714dfed4f3abf49db63055f9048bfa1b69c1cdb5d943bd762683fee0e6e827ad'
	'build-support/tarcore/gzip.v': '075408301157a547349b72eaf6d191be97afcb46293df39e570740559bb5b2eb'
	'build-support/tarcore/writer.v': 'c8acbe08a97d19820148ff476ccf7084054577d7a4be75b7b8c762b5855938af'
	'build-support/tarstream/filter_abi.h': '1db70a64f89647f080933cc7ce8cb797f4a4ff9fa4aca51c515c7fb559525ad6'
	'build-support/tarstream/reader.v': 'dd34ba8b9359edc0911a2523b69054f401e55235a2514faa6a24cb5bfd254d07'
	'build-support/tarstream/sparse.v': '482fab1e74d88bce2b53edab9d98d68699dee869b5568cb33b9522d828cb0e61'
	'tests/native-android-ws/clone-maps-account-stage.v': 'f7f4a61de7a7792c91da821def0fe02d1a3e7cd7ebfe5f0abd0c175a3b584cc5'
	'tests/native-android-ws/mapsaccountstage/bundle.v': 'e402af00600af840aacbb929e0d0379402879340db37c7745f089dd131ce5cef'
	'tests/native-android-ws/mapsaccountstage/elf.v': '3579a6b68d8477d94559611d9f843c3124995c79200fb6d7676679a1eeb36a2f'
	'tests/native-android-ws/mapsaccountstage/headless.v': 'a43fb79d36828ef83f4af9650b78dc53dba22f035e5666fbc082b197d12fb2ac'
	'tests/native-android-ws/mapsaccountstage/hostsha.v': 'd16c58dcbe5ae8ad5af2a1332f4a08cfe600d908e5a8c4c54d7e47a8f77a5bbf'
	'tests/native-android-ws/mapsaccountstage/media.v': 'd1227ec37c79dcff2b40e7e265aceb24550e7e1a1cbbb0e728114aca6f91314c'
}

struct Tree {
mut:
	files map[string]string
	regular_modes map[string]u32
	directories map[string]u32
	links map[string]string
}

struct KernelInventory {
	files map[string]string
	links map[string]string
}

struct Metadata {
	kind string
	mode u32
	size u64
}

struct Clone {
	kind string
	source string
	output string
	manifest_sha256 string
	verified_files int
	verified_tree_metadata map[string]Metadata
	tool_sha256 string
	source_sha256 string
	source_closure string
	source_closure_sha256 map[string]string
	scope string
}

struct PreparedStage {
	format int
	inputs_sha256 map[string]string
	original_modules_sha256 map[string]string
	preserved_modules_sha256 map[string]string
	overlay_sha256 string
	limine_before_sha256 string
	limine_after_sha256 string
	staged_boot_sha256 string
	staged_efivars_sha256 string
}

struct KernelPatch {
	format int
	scope string
	profile string
	created_utc string
	baseline_boot_path string
	baseline_boot_sha256 string
	original_stage_sha256 string
	original_kernel_sha256 string
	kernel_member string
	kernel_sha256 string
	kernel_build_root string
	kernel_build_receipt_sha256 string
	kernel_build_receipts_sha256 map[string]string
	kernel_source_revision string
	kernel_unix_source_sha256 string
	preserved_modules_sha256 map[string]string
	limine_sha256 string
	efivars_sha256 string
	staged_boot_sha256 string
	tool_sha256 string
	tool_source_sha256 string
	mcopy_sha256 string
	mtype_sha256 string
}

struct KernelRequest {
	profile string
	created_utc string
	original_stage_sha256 string
	baseline_boot_sha256 string
	kernel_build_receipt_sha256 string
	original_kernel_sha256 string
	replacement_kernel_sha256 string
}

struct KernelBuild {
	format int
	architecture string
	source_revision string
	kernel_path string
	kernel_sha256 string
	kernel_unix_source_sha256 string
	generated_c_sha256 string
	compiler_sha256 string
	guest_executed bool
	link_seed int
}

struct Command {
	argv []string
	exit_code int
	stdout string
	stderr string
}

fn read_text(path string) !string {
	info := os.lstat(path)!
	if info.get_filetype() != .regular || info.nlink != 1 || info.size > 16 * 1024 * 1024 {
		return error('bounded single-linked regular evidence required: ' + path)
	}
	return os.read_file(path)
}

fn walk(root string, relative string, allow_links bool, mut tree Tree) ! {
	if tree.files.len + tree.links.len + tree.directories.len > 20000 { return error('bounded complete tree required') }
	path := if relative == '' { root } else { root + '/' + relative }
	info := os.lstat(path)!
	match info.get_filetype() {
		.regular {
			if info.nlink != 1 || info.mode & 0o7022 != 0 { return error('unsafe regular evidence inode: ' + path) }
			if relative != 'sha256.json' {
				tree.files[relative] = stage.hash(path)!
				tree.regular_modes[relative] = info.mode & 0o777
			}
		}
		.directory {
			if info.mode & 0o7022 != 0 { return error('unsafe evidence directory: ' + path) }
			tree.directories[relative] = info.mode & 0o777
			for child in os.ls(path)! {
				name := if relative == '' { child } else { relative + '/' + child }
				if !stage.relative_file(name) { return error('unsafe relative inventory name') }
				walk(root, name, allow_links, mut tree)!
			}
		}
		.symbolic_link {
			if !allow_links { return error('symlink not permitted in checkpoint tree: ' + path) }
			tree.links[relative] = os.readlink(path)!
		}
		else { return error('special inode not permitted: ' + path) }
	}
}

fn tree(root string, allow_links bool) !Tree {
	mut result := Tree{}
	walk(root, '', allow_links, mut result)!
	return result
}

fn exact_keys(actual []string, expected []string, label string) ! {
	if actual.sorted() != expected.sorted() { return error('exact ' + label + ' membership required') }
}

fn exact_object(path string, keys []string) !string {
	text := read_text(path)!
	object := json2.decode[map[string]json2.Any](text)!
	exact_keys(object.keys(), keys, 'JSON evidence field')!
	return text
}

fn clone_directory_modes() map[string]u32 {
	mut expected := {'': u32(0o700)}
	for name in clone_sources.keys() {
		mut parent := os.dir(name)
		for parent !in ['', '.'] {
			expected[parent] = 0o700
			parent = os.dir(parent)
		}
	}
	return expected
}

fn validate_closure_dirs(actual map[string]u32) ! {
	if actual != clone_directory_modes() { return error('exact private clone source ancestor directories required') }
}

fn validate_clone(root string, prepared map[string]string, prepared_tree Tree) !Clone {
	text := exact_object(root + '-clone.json', ['kind', 'source', 'output', 'manifest_sha256',
		'verified_files', 'verified_tree_metadata', 'tool_sha256', 'source_sha256',
		'source_closure', 'source_closure_sha256', 'scope'])!
	receipt := json2.decode[Clone](text)!
	if receipt.kind != 'vinix-maps-account-exact-stage-clone-v1' || receipt.source != prepared_root
		|| receipt.output != root || receipt.manifest_sha256 != prepared_seal || receipt.verified_files != prepared.len
		|| receipt.tool_sha256 != clone_tool || receipt.source_sha256 != clone_source
		|| receipt.source_closure != root + '-clone-sources' || receipt.source_closure_sha256 != clone_sources
		|| receipt.scope != 'source and copy complete inventories and inode kinds, modes, sizes rechecked; no media mutation or guest execution'
		|| stage.hash(root + '-clone-tool')! != clone_tool || stage.hash(root + '-clone-source.v')! != clone_source {
		return error('exact qualified source/clone provenance required')
	}
	closure := tree(root + '-clone-sources', false)!
	if closure.files != clone_sources { return error('complete clone source closure differs') }
	validate_closure_dirs(closure.directories)!
	mut expected_metadata := map[string]Metadata{}
	for name, mode in prepared_tree.directories { expected_metadata[name] = Metadata{'directory', mode, 0} }
	mut files := prepared.keys()
	files << 'sha256.json'
	for name in files {
		info := os.lstat(prepared_root + '/' + name)!
		expected_metadata[name] = Metadata{'regular', info.mode & 0o777, info.size}
	}
	if receipt.verified_tree_metadata != expected_metadata { return error('complete original clone metadata differs') }
	return receipt
}

fn copy_clone(root string) !Tree {
	target := root + '/checkpoint-clone'
	os.mkdir(target, mode: 0o700)!
	for pair in [['-clone.json', 'clone.json'], ['-clone-tool', 'clone-tool'], ['-clone-source.v', 'clone-source.v']] {
		os.cp(root + pair[0], target + '/' + pair[1])!
		if stage.hash(root + pair[0])! != stage.hash(target + '/' + pair[1])! { return error('clone provenance copy differs') }
	}
	closure := tree(root + '-clone-sources', false)!
	mut directories := closure.directories.keys()
	directories.sort()
	for name in directories { os.mkdir(if name == '' { target + '/sources' } else { target + '/sources/' + name }, mode: 0o700)! }
	for name, pin in clone_sources {
		os.cp(root + '-clone-sources/' + name, target + '/sources/' + name)!
		if stage.hash(target + '/sources/' + name)! != pin { return error('clone source copy differs') }
	}
	return tree(target, false)
}

fn kernel_inventory() !KernelInventory {
	if stage.hash(kernel_root + '/sha256.json')! != kernel_manifest
		|| stage.hash(kernel_root + '/build.json')! != kernel_build
		|| stage.hash(kernel_root + '/input-pins.json')! != kernel_inputs {
		return error('exact frozen kernel manifests required')
	}
	manifest := json2.decode[KernelInventory](read_text(kernel_root + '/sha256.json')!)!
	if manifest.files.len == 0 { return error('complete frozen kernel inventory required') }
	actual := tree(kernel_root, true)!
	if actual.files != manifest.files || actual.links != manifest.links { return error('complete frozen kernel inventory differs') }
	for name, pin in manifest.files {
		if !stage.relative_file(name) || !stage.valid_pin(pin) { return error('invalid frozen kernel file entry') }
	}
	for name, target in manifest.links {
		if !stage.relative_file(name) || target == '' || target.contains_any('\x00\r\n') { return error('invalid frozen kernel link entry') }
	}
	build := json2.decode[KernelBuild](read_text(kernel_root + '/build.json')!)!
	if build.format != 1 || build.architecture != 'aarch64' || build.guest_executed
		|| build.source_revision != 'ecbd3964aff243304e16df45271c7de8dee4d2da'
		|| build.kernel_path != kernel_root + '/source/kernel/bin/vinix' || build.kernel_sha256 != kernel_pin
		|| build.kernel_unix_source_sha256 != '287c78126cda7407f91494297494e029fef35aa93ada1dedd216cf9305d1013c'
		|| build.compiler_sha256 != '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
		|| build.link_seed != 20261026 || !stage.valid_pin(build.generated_c_sha256)
		|| manifest.files['source/kernel/bin/vinix'] or { '' } != kernel_pin {
		return error('typed frozen AArch64 kernel receipt differs')
	}
	return manifest
}

fn module_set(old PreparedStage) !map[string]string {
	if old.format != 1 || old.original_modules_sha256.len != 58
		|| old.original_modules_sha256 != old.preserved_modules_sha256
		|| !stage.valid_pin(old.overlay_sha256) || 'maps-framework-boot.tar' in old.original_modules_sha256 {
		return error('known 58-parent plus framework-boot overlay required')
	}
	mut modules := old.original_modules_sha256.clone()
	modules['maps-framework-boot.tar'] = old.overlay_sha256
	for name, pin in modules {
		if !stage.relative_file(name) || name.contains('/') || !name.ends_with('.tar') || !stage.valid_pin(pin) {
			return error('exact safe module member and pin required')
		}
	}
	return modules
}

fn kernel_output_names(modules map[string]string) []string {
	mut names := ['stage-before-kernel.json', 'kernel-patch.json', 'kernel-patch-request.json',
		'kernel-patch-source.v', 'kernel-patch-tool', 'kernel-patch-build/build.json',
		'kernel-patch-build/input-pins.json', 'kernel-patch-build/sha256.json']
	for label in ['process-check', 'baseline-limine', 'stage-limine-before', 'install-kernel', 'stage-limine-after'] {
		names << 'kernel-patch-commands/' + label + '.json'
	}
	for label in ['baseline-kernel', 'staged-kernel-before', 'staged-kernel-after'] {
		names << 'kernel-patch-commands/' + label + '.sha256'
	}
	for name in modules.keys() {
		for label in ['before-', 'after-'] { names << 'kernel-patch-commands/' + label + name + '.sha256' }
		if name != 'maps-framework-boot.tar' { names << 'kernel-patch-commands/baseline-' + name + '.sha256' }
	}
	return names.sorted()
}

fn validate_changes(prepared map[string]string, current map[string]string, additions []string) ! {
	mut expected := prepared.keys()
	expected << additions
	exact_keys(current.keys(), expected, 'patched clone file')!
	for name, pin in prepared {
		if name !in ['boot.img', 'stage.json'] && current[name] or { '' } != pin {
			return error('unexpected prepared clone change: ' + name)
		}
	}
	if current['boot.img'] or { '' } == prepared['boot.img'] or { '' }
		|| current['stage.json'] or { '' } == prepared['stage.json'] or { '' } {
		return error('kernel patch must change both image and typed stage')
	}
}

fn validate_modes(expected map[string]u32, current map[string]u32) ! {
	for name, mode in expected {
		if current[name] or { u32(0) } != mode { return error('preserved regular file mode changed: ' + name) }
	}
}

fn command(root string, label string, argv []string, stdout string) ! {
	value := json2.decode[Command](exact_object(root + '/kernel-patch-commands/' + label + '.json', ['argv', 'exit_code', 'stdout', 'stderr'])!)!
	if value.argv != argv || value.exit_code != 0 || value.stderr != '' || value.stdout != stdout {
		return error('exact successful kernel command required: ' + label)
	}
}

fn hash_record(root string, label string, pin string) ! {
	if read_text(root + '/kernel-patch-commands/' + label + '.sha256')! != pin + '  -\n' {
		return error('exact successful FAT hash record required: ' + label)
	}
}

fn validate_patch(old PreparedStage, patch KernelPatch, preserved map[string]string, boot_pin string) ! {
	build_receipts := {'build.json': kernel_build, 'input-pins.json': kernel_inputs, 'sha256.json': kernel_manifest}
	if patch.format != 1 || patch.profile != 'maps-framework-boot' || patch.created_utc.len != 19
		|| patch.scope != 'Fresh diagnostic stage only; prepared payload preserved byte-for-byte; no guest execution or Google login evidence.'
		|| patch.baseline_boot_path != baseline_root + '/boot.img' || patch.baseline_boot_sha256 != baseline_boot
		|| patch.original_stage_sha256 != original_stage_pin || patch.original_kernel_sha256 != old_kernel_pin
		|| patch.kernel_member != 'vinix' || patch.kernel_sha256 != kernel_pin
		|| patch.kernel_build_root != kernel_root || patch.kernel_build_receipt_sha256 != kernel_build
		|| patch.kernel_build_receipts_sha256 != build_receipts
		|| patch.kernel_source_revision != 'ecbd3964aff243304e16df45271c7de8dee4d2da'
		|| patch.kernel_unix_source_sha256 != '287c78126cda7407f91494297494e029fef35aa93ada1dedd216cf9305d1013c'
		|| patch.preserved_modules_sha256 != preserved || patch.limine_sha256 != old.limine_after_sha256
		|| patch.efivars_sha256 != old.staged_efivars_sha256 || patch.staged_boot_sha256 != boot_pin
		|| patch.tool_sha256 != kernel_tool || patch.tool_source_sha256 != kernel_source
		|| patch.mcopy_sha256 != mtools_pin || patch.mtype_sha256 != mtools_pin {
		return error('typed known-profile kernel patch receipt differs')
	}
}

fn check_receipts(root string, old PreparedStage, patch KernelPatch, preserved map[string]string, boot_pin string) ! {
	validate_patch(old, patch, preserved, boot_pin)!
	build_receipts := {'build.json': kernel_build, 'input-pins.json': kernel_inputs, 'sha256.json': kernel_manifest}
	if stage.hash(root + '/kernel-patch-tool')! != kernel_tool || stage.hash(root + '/kernel-patch-source.v')! != kernel_source {
		return error('qualified archived kernel patcher identity differs')
	}
	for name, pin in build_receipts {
		if stage.hash(root + '/kernel-patch-build/' + name)! != pin { return error('copied complete kernel receipt differs') }
	}
	request := json2.decode[KernelRequest](exact_object(root + '/kernel-patch-request.json',
		['profile', 'created_utc', 'original_stage_sha256', 'baseline_boot_sha256', 'kernel_build_receipt_sha256', 'original_kernel_sha256', 'replacement_kernel_sha256'])!)!
	if request.profile != patch.profile || request.created_utc.len != 19 || request.original_stage_sha256 != original_stage_pin
		|| request.baseline_boot_sha256 != baseline_boot || request.kernel_build_receipt_sha256 != kernel_build
		|| request.original_kernel_sha256 != old_kernel_pin || request.replacement_kernel_sha256 != kernel_pin {
		return error('typed kernel patch request differs')
	}
	before_text := read_text(root + '/limine-before.conf')!
	after_text := read_text(root + '/limine-after.conf')!
	command(root, 'baseline-limine', ['/opt/homebrew/bin/mtype', '-i', baseline_root + '/boot.img', '::/boot/limine.conf'], before_text)!
	command(root, 'stage-limine-before', ['/opt/homebrew/bin/mtype', '-i', root + '/boot.img', '::/boot/limine.conf'], after_text)!
	command(root, 'stage-limine-after', ['/opt/homebrew/bin/mtype', '-i', root + '/boot.img', '::/boot/limine.conf'], after_text)!
	command(root, 'install-kernel', ['/opt/homebrew/bin/mcopy', '-o', '-i', root + '/boot.img',
		kernel_root + '/source/kernel/bin/vinix', '::/boot/vinix'], '')!
	process := json2.decode[Command](exact_object(root + '/kernel-patch-commands/process-check.json', ['argv', 'exit_code', 'stdout', 'stderr'])!)!
	if process.argv != ['/bin/ps', '-axo', 'pid=,command='] || process.exit_code != 0 || process.stderr != ''
		|| process.stdout == '' || process.stdout.split_into_lines().any(it.contains('qemu-system-') && it.contains(root + '/')) {
		return error('unlaunched process-check evidence differs')
	}
	hash_record(root, 'baseline-kernel', old_kernel_pin)!
	hash_record(root, 'staged-kernel-before', old_kernel_pin)!
	hash_record(root, 'staged-kernel-after', kernel_pin)!
	for name, pin in preserved {
		hash_record(root, 'before-' + name, pin)!
		hash_record(root, 'after-' + name, pin)!
		if name != 'maps-framework-boot.tar' { hash_record(root, 'baseline-' + name, pin)! }
	}
}

fn readback(root string, member string, pin string) ! {
	result := modulestream.hash_member(root + '/boot.img', member, root + '/checkpoint-readback/' + member + '.sha256')!
	if result.statuses.producer != 0 || result.statuses.consumer != 0 || result.sha256 != pin {
		return error('independent FAT readback differs: ' + member)
	}
}

fn run(root string) ! {
	if os.real_path(root) != root || !os.is_dir(root) || !root.starts_with(state + 'maps-framework-jni-load-kernel-base-') {
		return error('canonical fresh external JNI kernel-base clone required')
	}
	for name in ['prepared-sha256.json', 'checkpoint.json', 'checkpoint-source.v', 'checkpoint-tool', 'checkpoint-readback', 'checkpoint-clone', 'sha256.next.json'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) { return error('once-only checkpoint output exists: ' + name) }
	}
	prepared := stage.load_inventory(prepared_root, prepared_seal)!
	prepared_tree := tree(prepared_root, false)!
	if prepared_tree.files != prepared || prepared['stage.json'] or { '' } != original_stage_pin
		|| stage.hash(root + '/sha256.json')! != prepared_seal {
		return error('exact original prepared inventory must remain before checkpoint')
	}
	kernel_before := kernel_inventory()!
	clone_before := validate_clone(root, prepared, prepared_tree)!
	old_text := read_text(prepared_root + '/stage.json')!
	old := json2.decode[PreparedStage](old_text)!
	preserved := module_set(old)!
	current := tree(root, false)!
	validate_changes(prepared, current.files, kernel_output_names(preserved))!
	validate_modes(prepared_tree.regular_modes, current.regular_modes)!
	mut expected_dirs := prepared_tree.directories.clone()
	for name in ['kernel-patch-build', 'kernel-patch-commands'] { expected_dirs[name] = current.directories[name] or { return error('kernel evidence directory missing') } }
	if current.directories != expected_dirs { return error('unexpected clone directory change') }
	if read_text(root + '/stage-before-kernel.json')! != old_text { return error('exact stage-before-kernel bytes required') }
	patch_text := exact_object(root + '/kernel-patch.json', ['format', 'scope', 'profile', 'created_utc',
		'baseline_boot_path', 'baseline_boot_sha256', 'original_stage_sha256', 'original_kernel_sha256',
		'kernel_member', 'kernel_sha256', 'kernel_build_root', 'kernel_build_receipt_sha256',
		'kernel_build_receipts_sha256', 'kernel_source_revision', 'kernel_unix_source_sha256',
		'preserved_modules_sha256', 'limine_sha256', 'efivars_sha256', 'staged_boot_sha256',
		'tool_sha256', 'tool_source_sha256', 'mcopy_sha256', 'mtype_sha256'])!
	patch := json2.decode[KernelPatch](patch_text)!
	check_receipts(root, old, patch, preserved, current.files['boot.img']!)!
	mut expected_stage := json2.decode[map[string]json2.Any](old_text)!
	expected_stage['kernel_patch'] = json2.decode[json2.Any](patch_text)!
	expected_stage['kernel_patch_receipt_sha256'] = json2.Any(current.files['kernel-patch.json']!)
	expected_stage['staged_boot_sha256'] = json2.Any(current.files['boot.img']!)
	if json2.decode[map[string]json2.Any](read_text(root + '/stage.json')!)! != expected_stage {
		return error('stage differs beyond exact kernel receipt and boot pin')
	}
	if current.files['efivars.fd']! != old.staged_efivars_sha256 || stage.hash('/opt/homebrew/bin/mcopy')! != mtools_pin
		|| stage.hash('/opt/homebrew/bin/mtype')! != mtools_pin { return error('firmware or qualified FAT reader changed') }
	os.setenv('PATH', '/opt/homebrew/bin:' + os.getenv('PATH'), true)
	if os.find_abs_path_of_executable('mcopy')! != '/opt/homebrew/bin/mcopy' { return error('exact qualified FAT stream reader required') }
	os.mkdir(root + '/checkpoint-readback', mode: 0o700)!
	readback(root, 'vinix', kernel_pin)!
	for name, pin in preserved { readback(root, name, pin)! }
	limine := os.exec(['/opt/homebrew/bin/mtype', '-i', root + '/boot.img', '::/boot/limine.conf'])
	os.write_file(root + '/checkpoint-readback/limine.json', json2.encode(Command{argv: ['/opt/homebrew/bin/mtype', '-i', root + '/boot.img', '::/boot/limine.conf'], exit_code: limine.exit_code, stdout: limine.output}, prettify: true) + '\n')!
	os.chmod(root + '/checkpoint-readback/limine.json', 0o600)!
	if limine.exit_code != 0 || limine.output != read_text(root + '/limine-after.conf')! { return error('independent Limine FAT readback differs') }
	if stage.hash(root + '/boot.img')! != current.files['boot.img']! || stage.load_inventory(prepared_root, prepared_seal)! != prepared
		|| kernel_inventory()! != kernel_before || stage.hash('/opt/homebrew/bin/mcopy')! != mtools_pin
		|| stage.hash('/opt/homebrew/bin/mtype')! != mtools_pin { return error('complete input changed during independent readback') }
	os.cp(root + '/sha256.json', root + '/prepared-sha256.json')!
	if stage.hash(root + '/prepared-sha256.json')! != prepared_seal { return error('prepared manifest preservation differs') }
	os.write_file(root + '/checkpoint-source.v', source)!
	os.cp(os.executable(), root + '/checkpoint-tool')!
	os.chmod(root + '/checkpoint-tool', 0o755)!
	clone_copy := copy_clone(root)!
	if validate_clone(root, prepared, prepared_tree)! != clone_before { return error('clone inputs changed during preservation') }
	mut kernel_outputs := map[string]string{}
	for name, pin in current.files { if name !in prepared { kernel_outputs[name] = pin } }
	before_receipt := tree(root, false)!
	mut new_modes := map[string]u32{}
	mut new_directory_modes := map[string]u32{}
	for name, mode in before_receipt.regular_modes { if name !in current.regular_modes { new_modes[name] = mode } }
	for name, mode in before_receipt.directories { if name !in current.directories { new_directory_modes[name] = mode } }
	new_modes['checkpoint.json'] = 0o600
	os.write_file(root + '/checkpoint.json', json2.encode({
		'kind': json2.Any('vinix-framework-jni-load-kernel-checkpoint-v1'), 'format': json2.Any(1),
		'root': json2.Any(root), 'prepared_root': json2.Any(prepared_root),
		'prepared_manifest_sha256': json2.Any(prepared_seal), 'original_stage_sha256': json2.Any(original_stage_pin),
		'staged_boot_sha256': json2.Any(current.files['boot.img']!), 'stage_sha256': json2.Any(current.files['stage.json']!),
		'kernel_patch_receipt_sha256': json2.Any(current.files['kernel-patch.json']!),
		'kernel_build_root': json2.Any(kernel_root), 'kernel_build_manifest_sha256': json2.Any(kernel_manifest),
		'kernel_build_receipt_sha256': json2.Any(kernel_build), 'kernel_sha256': json2.Any(kernel_pin),
		'kernel_patch_tool_sha256': json2.Any(kernel_tool), 'prepared_efivars_sha256': json2.Any(old.staged_efivars_sha256),
		'preserved_modules_sha256': json2.decode[json2.Any](json2.encode(preserved))!,
		'collector_source_sha256': json2.Any(sha256.sum(source.bytes()).hex()),
		'collector_tool_sha256': json2.Any(stage.hash(root + '/checkpoint-tool')!),
		'clone_receipt_sha256': json2.Any(stage.hash(root + '/checkpoint-clone/clone.json')!),
		'clone_tool_sha256': json2.Any(clone_tool), 'clone_source_sha256': json2.Any(clone_source),
		'preserved_regular_modes': json2.decode[json2.Any](json2.encode(current.regular_modes))!,
		'new_output_modes': json2.decode[json2.Any](json2.encode(new_modes))!,
		'new_output_directory_modes': json2.decode[json2.Any](json2.encode(new_directory_modes))!,
		'manifest_mode': json2.Any(0o644),
		'kernel_outputs_sha256': json2.decode[json2.Any](json2.encode(kernel_outputs))!,
		'scope': json2.Any('Complete unbooted kernel-only checkpoint; original prepared ancestry retained; no native successor overlay or guest execution.'),
	}, prettify: true) + '\n')!
	os.chmod(root + '/checkpoint.json', 0o600)!
	final := tree(root, false)!
	for name, pin in current.files { if final.files[name] or { '' } != pin { return error('kernel-base input changed before final inventory: ' + name) } }
	validate_modes(current.regular_modes, final.regular_modes)!
	validate_modes(new_modes, final.regular_modes)!
	mut expected_final := current.files.keys()
	expected_final << ['prepared-sha256.json', 'checkpoint-source.v', 'checkpoint-tool', 'checkpoint.json',
		'checkpoint-readback/vinix.sha256', 'checkpoint-readback/limine.json']
	for name in preserved.keys() { expected_final << 'checkpoint-readback/' + name + '.sha256' }
	for name in clone_copy.files.keys() { expected_final << 'checkpoint-clone/' + name }
	exact_keys(final.files.keys(), expected_final, 'complete checkpoint file')!
	mut expected_final_dirs := current.directories.clone()
	expected_final_dirs['checkpoint-readback'] = 0o700
	for name, mode in clone_copy.directories { expected_final_dirs[if name == '' { 'checkpoint-clone' } else { 'checkpoint-clone/' + name }] = mode }
	if final.directories != expected_final_dirs { return error('unexpected checkpoint output directory') }
	os.write_file(root + '/sha256.next.json', json2.encode(final.files, prettify: true) + '\n')!
	os.chmod(root + '/sha256.next.json', 0o644)!
	seal := stage.hash(root + '/sha256.next.json')!
	os.mv(root + '/sha256.next.json', root + '/sha256.json')!
	if stage.load_inventory(root, seal)! != final.files || os.lstat(root + '/sha256.json')!.mode & 0o777 != 0o644 {
		return error('complete checkpoint inventory readback differs')
	}
	println('FRAMEWORK-JNI-LOAD-KERNEL-CHECKPOINT-PASS root=' + root + ' manifest=' + seal + ' modules=59 independent-FAT-readbacks=61')
}

fn self_test() ! {
	base := {'boot.img': 'old-image', 'stage.json': 'old-stage', 'efivars.fd': 'firmware', 'payload/file': 'payload'}
	good := {'boot.img': 'new-image', 'stage.json': 'new-stage', 'efivars.fd': 'firmware', 'payload/file': 'payload', 'kernel-patch.json': 'receipt'}
	validate_changes(base, good, ['kernel-patch.json'])!
	mut controls := 0
	validate_modes({'tool': u32(0o755)}, {'tool': u32(0o755)})!
	for modes in [{'tool': u32(0o644)}, map[string]u32{}] {
		validate_modes({'tool': u32(0o755)}, modes) or { controls++; continue }
		return error('safe permission drift or missing mode accepted')
	}
	good_dirs := clone_directory_modes()
	validate_closure_dirs(good_dirs)!
	mut extra_dir := good_dirs.clone()
	extra_dir['unexpected-empty'] = 0o700
	mut missing_dir := good_dirs.clone()
	missing_dir.delete('tests')
	mut changed_dir := good_dirs.clone()
	changed_dir['tests'] = 0o755
	for dirs in [extra_dir, missing_dir, changed_dir] {
		validate_closure_dirs(dirs) or { controls++; continue }
		return error('unknown, missing or changed clone source directory accepted')
	}
	mut missing := good.clone()
	missing.delete('efivars.fd')
	for bad in [missing, {'boot.img': 'new-image', 'stage.json': 'new-stage', 'efivars.fd': 'changed', 'payload/file': 'payload', 'kernel-patch.json': 'receipt'},
		{'boot.img': 'old-image', 'stage.json': 'new-stage', 'efivars.fd': 'firmware', 'payload/file': 'payload', 'kernel-patch.json': 'receipt'},
		{'boot.img': 'new-image', 'stage.json': 'old-stage', 'efivars.fd': 'firmware', 'payload/file': 'payload', 'kernel-patch.json': 'receipt'},
		{'boot.img': 'new-image', 'stage.json': 'new-stage', 'efivars.fd': 'firmware', 'payload/file': 'payload', 'kernel-patch.json': 'receipt', 'serial.log': 'booted'}] {
		validate_changes(base, bad, ['kernel-patch.json']) or { controls++; continue }
		return error('checkpoint source preservation mutation accepted')
	}
	mut parent_modules := map[string]string{}
	for i in 0 .. 58 { parent_modules['module-' + i.str() + '.tar'] = 'a'.repeat(64) }
	old := PreparedStage{format: 1, original_modules_sha256: parent_modules,
		preserved_modules_sha256: parent_modules, overlay_sha256: 'b'.repeat(64),
		limine_after_sha256: 'c'.repeat(64), staged_efivars_sha256: 'd'.repeat(64)}
	modules := module_set(old)!
	names := kernel_output_names(modules)
	if modules.len != 59 || names.len != 192 { return error('complete kernel output set count differs') }
	mut seen := map[string]bool{}
	for name in names {
		if name in seen { return error('duplicate expected kernel output') }
		seen[name] = true
	}
	mut fewer := parent_modules.clone()
	fewer.delete('module-0.tar')
	for bad in [PreparedStage{...old, format: 0}, PreparedStage{...old, original_modules_sha256: fewer},
		PreparedStage{...old, preserved_modules_sha256: fewer}, PreparedStage{...old, overlay_sha256: ''}] {
		module_set(bad) or { controls++; continue }
		return error('incomplete module provenance accepted')
	}
	boot_pin := 'e'.repeat(64)
	patch := KernelPatch{
		format: 1, profile: 'maps-framework-boot', created_utc: '2026-11-04 12:00:00',
		scope: 'Fresh diagnostic stage only; prepared payload preserved byte-for-byte; no guest execution or Google login evidence.',
		baseline_boot_path: baseline_root + '/boot.img', baseline_boot_sha256: baseline_boot,
		original_stage_sha256: original_stage_pin, original_kernel_sha256: old_kernel_pin,
		kernel_member: 'vinix', kernel_sha256: kernel_pin, kernel_build_root: kernel_root,
		kernel_build_receipt_sha256: kernel_build,
		kernel_build_receipts_sha256: {'build.json': kernel_build, 'input-pins.json': kernel_inputs, 'sha256.json': kernel_manifest},
		kernel_source_revision: 'ecbd3964aff243304e16df45271c7de8dee4d2da',
		kernel_unix_source_sha256: '287c78126cda7407f91494297494e029fef35aa93ada1dedd216cf9305d1013c',
		preserved_modules_sha256: modules, limine_sha256: old.limine_after_sha256,
		efivars_sha256: old.staged_efivars_sha256, staged_boot_sha256: boot_pin,
		tool_sha256: kernel_tool, tool_source_sha256: kernel_source,
		mcopy_sha256: mtools_pin, mtype_sha256: mtools_pin,
	}
	validate_patch(old, patch, modules, boot_pin)!
	for bad in [KernelPatch{...patch, format: 0}, KernelPatch{...patch, profile: 'other'},
		KernelPatch{...patch, created_utc: ''}, KernelPatch{...patch, scope: 'guest executed'},
		KernelPatch{...patch, baseline_boot_path: 'relative/boot.img'}, KernelPatch{...patch, baseline_boot_sha256: boot_pin},
		KernelPatch{...patch, original_stage_sha256: boot_pin}, KernelPatch{...patch, original_kernel_sha256: kernel_pin},
		KernelPatch{...patch, kernel_member: 'other'}, KernelPatch{...patch, kernel_sha256: old_kernel_pin},
		KernelPatch{...patch, kernel_build_root: prepared_root}, KernelPatch{...patch, kernel_build_receipt_sha256: boot_pin},
		KernelPatch{...patch, kernel_build_receipts_sha256: {'build.json': kernel_build}},
		KernelPatch{...patch, kernel_source_revision: ''}, KernelPatch{...patch, kernel_unix_source_sha256: boot_pin},
		KernelPatch{...patch, preserved_modules_sha256: parent_modules}, KernelPatch{...patch, limine_sha256: boot_pin},
		KernelPatch{...patch, efivars_sha256: boot_pin}, KernelPatch{...patch, staged_boot_sha256: old_kernel_pin},
		KernelPatch{...patch, tool_sha256: boot_pin}, KernelPatch{...patch, tool_source_sha256: boot_pin},
		KernelPatch{...patch, mcopy_sha256: boot_pin}, KernelPatch{...patch, mtype_sha256: boot_pin}] {
		validate_patch(old, bad, modules, boot_pin) or { controls++; continue }
		return error('typed kernel receipt mutation accepted')
	}
	println('FRAMEWORK-JNI-LOAD-KERNEL-CHECKPOINT-SELFTEST-PASS controls=' + controls.str() + ' unchanged-payload exact-membership both-media-and-stage-change typed-kernel-provenance complete59modules192outputs')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 2 { eprintln('usage: framework-jni-load-kernel-checkpoint FRESH_KERNEL_BASE_ROOT | --self-test'); exit(2) }
	run(os.args[1]) or { eprintln(err); exit(1) }
}
