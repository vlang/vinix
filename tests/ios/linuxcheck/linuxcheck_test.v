// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os

#include <sys/stat.h>
fn C.mkfifo(&char, u32) int

fn output_refused(root string, path string) bool {
	fresh_output(root, path) or { return true }
	return false
}

fn test_generated_evidence_cannot_replace_existing_files_or_enter_git_via_symlinks() {
	base := os.join_path(os.temp_dir(), 'vinix-linux-output-${os.getpid()}')
	os.mkdir(base) or { panic(err) }
	defer { os.rmdir_all(base) or {} }
	root := base + '/repo'
	os.mkdir(root) or { panic(err) }
	assert output_refused(root, root + '/generated')
	os.symlink(root, base + '/alias') or { panic(err) }
	assert output_refused(root, base + '/alias/generated')
	assert !os.exists(root + '/generated')
	out := fresh_output(root, base + '/external result') or { panic(err) }
	os.write_file(out + '/receipt.txt', 'preserve') or { panic(err) }
	assert output_refused(root, out)
	assert os.read_file(out + '/receipt.txt') or { panic(err) } == 'preserve'
}

fn test_execution_refuses_an_x86_elf_instead_of_using_abi_stubs() {
	path := os.join_path(os.temp_dir(), 'vinix-linux-wrong-elf-${os.getpid()}')
	defer { os.rm(path) or {} }
	mut header := []u8{len: 64}
	header[0] = 0x7f
	header[1] = `E`
	header[2] = `L`
	header[3] = `F`
	header[4] = 2
	header[5] = 1
	header[6] = 1
	header[16] = 2
	header[18] = 62
	os.write_file_array(path, header) or { panic(err) }
	mut rejected := false
	require_arm64_elf(path) or { rejected = true }
	assert rejected
}

fn test_inventory_includes_hidden_files_and_refuses_external_links() {
	base := os.join_path(os.temp_dir(), 'vinix-linux-inventory-${os.getpid()}')
	os.mkdir(base) or { panic(err) }
	defer { os.rmdir_all(base) or {} }
	os.mkdir(base + '/.hidden') or { panic(err) }
	os.write_file(base + '/.hidden/input', 'complete') or { panic(err) }
	mut items := []FileDigest{}
	inventory_files(base, '', mut items) or { panic(err) }
	assert items.len == 1
	assert items[0].path == '.hidden/input'
	os.symlink(base + '/.hidden/input', base + '/alias') or { panic(err) }
	mut rejected := false
	inventory_files(base, '', mut items) or { rejected = true }
	assert rejected
}

fn test_inventory_rejects_fifo_without_opening_it() {
	base := os.join_path(os.temp_dir(), 'vinix-linux-inventory-fifo-${os.getpid()}')
	os.mkdir(base) or { panic(err) }
	defer { os.rmdir_all(base) or {} }
	pipe := base + '/pipe'
	assert unsafe { C.mkfifo(pipe.str, 0o600) } == 0
	assert (os.lstat(pipe) or { panic(err) }).get_filetype() == .fifo
	// No writer exists: opening this FIFO for hashing would hang the test.
	mut items := []FileDigest{}
	mut rejected := false
	inventory_files(base, '', mut items) or {
		rejected = err.msg().contains('unsupported entry: ' + pipe)
	}
	assert rejected
	assert items.len == 0
}

fn test_zero_exit_without_cookie_or_race_coverage_is_not_a_pass() {
	mut rejected := false
	require_markers('ns_data_http_test.v', 'IOS-HTTP-TRANSPORT: PASS') or { rejected = true }
	assert rejected
	rejected = false
	require_markers('storekit_purchase_test.v', 'IOS-STOREKIT-PURCHASE: PASS') or { rejected = true }
	assert rejected
}
