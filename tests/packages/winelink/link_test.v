// SPDX-License-Identifier: GPL-2.0-or-later
module winelink

import strconv
import os
import json2

fn require_check(ok bool) { if !ok { panic('WINE helper control failed') } }
fn require_refusal(ok bool) { if !ok { panic('WINE helper expected refusal') } }

// The actual linker replay is exercised by the production probe and fresh Wine
// producers. These archive controls deliberately contain no executable code.
fn member(name string, data string, kind u8) []u8 {
	mut header := []u8{len: 512}
	for index, byte in name.bytes() { header[index] = byte }
	for index, byte in '0000644\x00'.bytes() { header[100 + index] = byte }
	for index, byte in strconv.format_int(i64(data.len), 8).bytes() { header[124 + index] = byte }
	header[156] = kind
	for index, byte in 'ustar\x0000'.bytes() { header[257 + index] = byte }
	mut sum := 0
	for index, byte in header { sum += if index >= 148 && index < 156 { 32 } else { int(byte) } }
	for index, byte in strconv.format_int(i64(sum), 8).bytes() { header[148 + index] = byte }
	header[154] = 0; header[155] = ` `
	header << data.bytes()
	header << []u8{len: (512 - data.len % 512) % 512}
	return header
}

fn fixture(response string) []u8 {
	mut bytes := member('link-inputs/response.txt', response, `0`)
	bytes << member('link-inputs/version.txt', 'LLD fixture\n', `0`)
	bytes << member('link-inputs/one.o', 'one', `0`)
	bytes << member('link-inputs/two.o', 'two', `0`)
	bytes << member('link-inputs/lib.a', 'library', `0`)
	bytes << []u8{len: 1024}
	return bytes
}

fn test_archive_profile_and_response_refusals() {
	response := '--chroot .\n--sysroot root/sysroot\n-m elf_x86_64\n--Bstatic\n-o program\none.o\ntwo.o\nlib.a\n'
	bytes := fixture(response)
	archive := parse(bytes)!
	require_check(archive.members.len == 5)
	response_check(archive, 'program')!
	for changed in [response + '--plugin evil.so\n', response.replace('one.o', '../one.o'),
		response.replace('-o program', '-o /outside'), response + '-o program\n', response.replace('--chroot .\n', '')] {
		mut refused := false
		response_check(parse(fixture(changed))!, 'program') or { refused = true }
		require_refusal(refused)
	}
	mut changed := bytes.clone(); changed[0] ^= 1
	mut refused := false
	parse(changed) or { refused = true }
	require_refusal(refused)
	for extra in [member('link-inputs/../escape', 'bad', `0`), member('link-inputs/one.o', 'dup', `0`),
		member('link-inputs/ONE.o', 'case alias', `0`), member('link-inputs/one.o/child', 'collision', `0`),
		member('link-inputs/link', 'one.o', `2`)] {
		mut malformed := bytes[..bytes.len - 1024].clone()
		malformed << extra; malformed << []u8{len: 1024}
		refused = false
		parse(malformed) or { refused = true }
		require_refusal(refused)
	}
	refused = false
	parse(bytes[..bytes.len - 512]) or { refused = true }
	require_refusal(refused)
	changed = bytes.clone(); changed[changed.len - 1] = 1
	refused = false
	parse(changed) or { refused = true }
	require_refusal(refused)
}

fn test_optional_real_link_replay() {
	manifest := os.getenv('VINIX_LINK_PROBE_ARGV')
	if manifest == '' { return }
	root := os.abs_path(os.getenv('VINIX_LINK_PROBE_OUTPUT'))
	if os.getenv('VINIX_LINK_PROBE_OUTPUT') == '' || os.exists(root) { panic('fresh external linker probe output required') }
	os.mkdir_all(root)!
	mut command := json2.decode[[]string](os.read_file(manifest)!)!.filter(it != '-H' && !it.starts_with('-Wl,--reproduce='))
	for index, arg in command { if arg.starts_with('-fuse-ld=') { command[index] = '-fuse-ld=' + linker } }
	command[command.len - 1] = root + '/program'
	build(command, root, root)!
	admit(root, root, root + '/program')!
}
