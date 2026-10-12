// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidhost as ah
import androidtools
import encoding.binary
import os

fn dex(size u32) []u8 {
	mut data := []u8{len: 72}
	copy(mut data, 'dex\n'.bytes())
	binary.little_endian_put_u32(mut data[52..56], 56)
	binary.little_endian_put_u32(mut data[56..60], 1)
	binary.little_endian_put_u16(mut data[60..62], 7)
	binary.little_endian_put_u32(mut data[64..68], size)
	return data
}

fn qualify(work string) ! {
	os.mkdir(work)!
	source := work + '/source.jar'
	ah.write_archive(source, [ah.ArchiveItem{name: 'A.class', data: 'class'.bytes()}, ah.ArchiveItem{name: 'asset.txt', data: 'first resource'.bytes()}, ah.ArchiveItem{name: 'asset.txt', data: 'last resource'.bytes()}, ah.ArchiveItem{name: 'directory/', data: []u8{}}, ah.ArchiveItem{name: 'assets/name with spaces.txt', data: [u8(0), 255, 1]}])!
	archive := ah.open_archive(source)!
	assert archive.names().filter(it == 'asset.txt').len == 2
	assert archive.read('asset.txt')! == 'last resource'.bytes()
	root := work + '/dex'
	os.mkdir(root)!
	os.write_file_array(root + '/classes.dex', dex(0))!
	os.write_file_array(root + '/classes2.dex', dex(0))!
	output := work + '/completed.jar'
	androidtools.dex_package(source, root, output)!
	result := ah.open_archive(output)!
	assert result.names() == ['asset.txt', 'assets/name with spaces.txt', 'classes.dex', 'classes2.dex']
	assert result.read('asset.txt')! == 'last resource'.bytes()
	assert result.read('assets/name with spaces.txt')! == [u8(0), 255, 1]
	assert result.read('classes.dex')! == dex(0)
	original := os.read_bytes(output)!
	for invalid in [dex(1), 'dex\n'.bytes(), 'wrong magic'.bytes()] {
		os.write_file_array(root + '/classes.dex', invalid)!
		mut refused := false
		androidtools.dex_package(source, root, output) or { refused = true }
		assert refused
		assert os.read_bytes(output)! == original, 'invalid DEX replaced completed archive'
	}
	os.rm(root + '/classes.dex')!
	mut absent := false
	androidtools.dex_package(source, root, output) or { absent = true }
	assert absent && os.read_bytes(output)! == original
	assert !os.exists(work + '/completed.jar.next')
	declaration := 'runtimecore__ForkThunks runtimecore__fork_thunks[128];'
	initializer := '\tmemmove(runtimecore__fork_thunks, (runtimecore__ForkThunks[128]){{.prepare=a,.parent=b,.child=c}}, sizeof(runtimecore__fork_thunks));\n'
	converted := androidtools.restore_fork_table(declaration + '\n' + initializer)!
	assert converted.contains('static const ' + declaration.all_before_last(';') + ' = {{.prepare=a,.parent=b,.child=c}};')
	assert !converted.contains('\tmemmove(')
	assert converted.contains('sizeof(runtimecore__ForkHandler) == 80') && converted.contains('sizeof(runtimecore__ForkThunks) == 24')
	for bad in [declaration, initializer, declaration + declaration + initializer, declaration + initializer.replace('.prepare=a,', '.prepare=a,\n')] {
		mut refused := false
		androidtools.restore_fork_table(bad) or { refused = true }
		assert refused
	}
	os.write_file(work + '/passed', 'PASS\n')!
	println('NATIVE ANDROID ARCHIVES / repeated member lookup / resource retention / deterministic ordered dex packaging / callsite, missing and malformed rejection / prior output retained / literal static callback table conversion and shape guards: PASS')
	flush_stdout()
}

fn main() {
	if os.args.len != 2 { eprintln('usage: test-archives NEW_STATE'); exit(2) }
	qualify(os.args[1]) or { eprintln(err); exit(1) }
}
