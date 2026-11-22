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
		for name, number in {'futex_waitv': 449, 'futex_wake': 454, 'futex_wait': 455,
			'futex_requeue': 456} {
			futex := report.syscalls.filter(it.arch == arch && it.name == name)
			assert futex.len == 1 && futex[0].number == number
			assert futex[0].status == 'wired; unqualified'
		}
	}
}

fn test_semantic_source_changes_invalidate_fingerprints_without_qualifying_dispatch() {
	root := os.real_path(os.dir(@FILE) + '/../..')
	original := coverage(root)!
	work := os.join_path(os.temp_dir(), 'vinix-coverage-inputs-' + os.getpid().str())
	assert !os.exists(work)
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or { panic(err) } }
	for path in original.inputs.keys() {
		os.mkdir_all(os.dir(work + '/' + path))!
		os.cp(root + '/' + path, work + '/' + path)!
	}
	assert coverage(work)!.inputs == original.inputs
	for change in [
		['kernel/proc/seccomp.v', 'instructions.len == 0', 'instructions.len == 1'],
		['kernel/userland/linux_task.v', 'pid := int(i32(pid_word))', 'pid := int(pid_word)'],
	] {
		path := change[0]
		old := change[1]
		new := change[2]
		source := os.read_file(work + '/' + path)!
		assert source.contains(old)
		os.write_file(work + '/' + path, source.replace(old, new))!
		changed := coverage(work)!
		assert changed.inputs[path] != original.inputs[path]
		assert changed.syscalls == original.syscalls
		os.write_file(work + '/' + path, source)!
	}
}

fn test_compiled_lines_follow_architecture_blocks_and_refuse_build_options() {
	body := [r'	$if amd64 {', '		syscall_table[68] = voidptr(x86)', r'	} $else {',
		'		syscall_table[186] = voidptr(arm)', '	}', '	for i := 0; i < max; i++ {',
		'		if a != unsafe { nil } && b != unsafe { nil } {', '		}', '	}']
	x86 := compiled_lines(body, 'x86_64')!
	assert x86.any(it.contains('voidptr(x86)')) && !x86.any(it.contains('voidptr(arm)'))
	arm := compiled_lines(body, 'aarch64')!
	assert arm.any(it.contains('voidptr(arm)')) && !arm.any(it.contains('voidptr(x86)'))
	for bad in [[r'$if prod {', 'syscall_table[1] = voidptr(x)', '}'],
		[r'$if prod {', 'table.init_storage_syscalls()', '}'],
		[r'$if amd64 { syscall_table[1] = voidptr(x) }'], ['}'], ['{'],
		[r'} $else {']] {
		compiled_lines(bad, 'x86_64') or { continue }
		assert false, 'accepted ${bad}'
	}
}

fn test_later_boot_registrations_replace_the_generic_table() {
	root := os.real_path(os.dir(@FILE) + '/../..')
	report := coverage(root)!
	for row in [
		['aarch64', '90', 'syscall_linux_capget', 'kernel/syscall/table/container_arm64.v:init_container_syscalls'],
		['aarch64', '222', 'security_linux_mmap', 'kernel/syscall/table/storage_arm64.v:init_storage_syscalls'],
		['aarch64', '171', 'sys.syscall_adjtimex', 'kernel/syscall/table/clock_control_arm64.v:init_clock_control_syscalls'],
		['x86_64', '68', 'sysvmsg.syscall_msgget', 'kernel/syscall/table/sysv_message.v:init_sysv_message_syscalls'],
		['x86_64', '9', 'syscall_linux_mmap_hardened', 'kernel/syscall/table/security_amd64.v:init_security_syscalls'],
		['x86_64', '0', 'syscall_linux_read', 'kernel/syscall/table/linux_table_amd64.v:init_syscall_table'],
	] {
		rows := report.syscalls.filter(it.arch == row[0] && it.number == row[1].int())
		assert rows.len == 1, row.str()
		assert rows[0].handler == row[2] && rows[0].source == row[3], rows[0].str()
	}
	for arch in ['aarch64', 'x86_64'] {
		assert report.inputs.keys().contains('kernel/main_' + if arch == 'aarch64' { 'arm64.v' } else { 'amd64.v' })
	}
}
