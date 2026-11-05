module launchproof

import os

fn put_u64(mut data []u8, offset int, value u64) {
	for index in 0 .. 8 { data[offset + index] = u8(value >> (8 * index)) }
}

fn sample_elf(arch string, dynamic bool) []u8 {
	interpreter := '/lib/ld-musl-' + arch + '.so.1\x00'
	mut data := []u8{len: if dynamic { 176 + interpreter.len } else { 120 }}
	for index, byte in [u8(0x7f), `E`, `L`, `F`, 2, 1] { data[index] = byte }
	data[16] = if dynamic { 3 } else { 2 }
	data[18] = if arch == 'aarch64' { 183 } else { 62 }
	put_u64(mut data, 32, 64)
	data[54] = 56
	data[56] = if dynamic { 2 } else { 1 }
	data[64] = 1
	put_u64(mut data, 96, u64(data.len))
	put_u64(mut data, 104, u64(data.len))
	if dynamic {
		data[120] = 3
		put_u64(mut data, 128, 176)
		put_u64(mut data, 152, u64(interpreter.len))
		for index, byte in interpreter { data[176 + index] = byte }
	}
	return data
}

fn test_elf_admits_only_correct_architecture_and_bounded_expected_interpreter() {
	for arch in ['aarch64', 'x86_64'] {
		for dynamic in [false, true] {
			data := sample_elf(arch, dynamic)
			elf_bytes(data, arch, dynamic)!
			other := if arch == 'aarch64' { 'x86_64' } else { 'aarch64' }
			if _ := elf_bytes(data, other, dynamic) { assert false } else { assert err.msg().contains('architecture or type') }
			if dynamic {
				if _ := elf_bytes(data, arch, false) { assert false } else { assert err.msg() != '' }
				mut executable := data.clone()
				executable[16] = 2
				if _ := elf_bytes(executable, arch, true) { assert false } else { assert err.msg().contains('architecture or type') }
				mut wrong := data.clone()
				wrong[176] = `!`
				if _ := elf_bytes(wrong, arch, true) { assert false } else { assert err.msg() == 'supplemental ELF interpreter differs' }
			}
			mut beyond := data.clone()
			put_u64(mut beyond, 96, u64(data.len) + 1)
			if _ := elf_bytes(beyond, arch, dynamic) { assert false } else { assert err.msg().contains('segment extends') }
			mut overflow := data.clone()
			put_u64(mut overflow, 32, ~u64(0))
			if _ := elf_bytes(overflow, arch, dynamic) { assert false } else { assert err.msg().contains('program headers') }
		}
	}
}

fn test_paths_and_complete_inventory_refuse_aliases_and_hidden_extra_files() {
	for bad in ['', '/absolute', '../escape', 'a/../escape', 'a//b', 'a/./b', 'a\\b', 'a\x00b', 'a\nb', 'a\tb'] {
		if _ := relative(bad) { assert false } else { assert err.msg().starts_with('unsafe supplemental path:') }
	}
	relative('source/desktop/software_launch.v')!
	root := os.temp_dir() + '/vinix-hosted-launch-proof-inventory-' + os.getpid().str()
	os.mkdir_all(root + '/nested')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/nested/input.v', 'module input\n')!
	before := inventory(root)!
	same(before, inventory(root)!)!
	os.write_file(root + '/.hidden', 'added\n')!
	if _ := same(before, inventory(root)!) { assert false } else { assert err.msg().contains('file count') }
	os.rm(root + '/.hidden')!
	os.mkdir(root + '/.hidden-directory')!
	os.write_file(root + '/.hidden-directory/input.v', 'module hidden\n')!
	if _ := same(before, inventory(root)!) { assert false } else { assert err.msg().contains('file count') }
	os.rmdir_all(root + '/.hidden-directory')!
	os.symlink('nested/input.v', root + '/alias.v')!
	if _ := inventory(root) { assert false } else { assert err.msg().contains('file alias: alias.v') }
}

fn test_import_refuses_unreviewed_bundle_before_creating_destination() {
	root := os.temp_dir() + '/vinix-hosted-launch-proof-import-' + os.getpid().str()
	os.mkdir_all(root + '/bundle')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/bundle/bundle.sha256', 'unreviewed fixture\n')!
	if _ := import_build(root + '/bundle', 'aarch64', root + '/output') {
		assert false
	} else { assert err.msg() in ['hosted launch-options target bundle has no reviewed seal', 'hosted launch-options supplemental seal differs'] }
	assert !os.exists(root + '/output')
}

fn test_historical_stage_remains_bound_to_original_receipt() {
	root := os.temp_dir() + '/vinix-hosted-launch-proof-stage-' + os.getpid().str()
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/stage-build.json', '{}\n')!
	for arch in ['aarch64', 'x86_64'] {
		if _ := historical_stage(root, arch, '/unconsumed/compiler') { assert false }
		else { assert err.msg() == 'assembled input digest differs: stage receipt' }
	}
}
