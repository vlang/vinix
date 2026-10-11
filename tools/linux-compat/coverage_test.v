module main

import os

fn test_reference_rejects_duplicates_and_malformed_numbers() {
	root := os.real_path(os.dir(@FILE) + '/../..')
	valid := os.read_file(root + '/tools/linux-compat/reference/x86_64-syscall.h')!
	assert definitions(valid)!.len > 250
	for text in ['#define __NR_other 0', '#define __NR_other abc', '#define __NR_other 512'] {
		definitions(valid + '\n' + text) or { continue }
		assert false, 'invalid reference was accepted'
	}
}

fn test_dispatch_rejects_duplicate_and_unknown_indices() {
	root := os.real_path(os.dir(@FILE) + '/../..')
	valid := os.read_file(root + '/kernel/syscall/table/linux_table_amd64.v')!
	assert handlers(valid)!.len > 200
	for text in ['syscall_table[1] = voidptr(other)', 'syscall_table[unknown_nr] = voidptr(one)',
		'syscall_table[512] = voidptr(one)'] {
		handlers(valid + '\n' + text) or { continue }
		assert false, 'invalid dispatch was accepted'
	}
}

fn test_real_tables_keep_architecture_numbers_and_private_extension() {
	root := os.real_path(os.dir(@FILE) + '/../..')
	report := coverage(root)!
	for arch, read_number in {
		'aarch64': 63
		'x86_64':  0
	} {
		read := report.syscalls.filter(it.arch == arch && it.name == 'read')
		assert read.len == 1 && read[0].number == read_number
		private := report.syscalls.filter(it.arch == arch && it.number == 511)
		assert private.len == 1 && private[0].status == 'private'
		bpf := report.syscalls.filter(it.arch == arch && it.name == 'bpf')
		assert bpf.len == 1 && bpf[0].status == 'unavailable'
	}
}
