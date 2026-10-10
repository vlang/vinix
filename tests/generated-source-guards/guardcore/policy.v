// SPDX-License-Identifier: GPL-2.0-or-later
module guardcore

import os

pub const accounting_functions = ['sys__syscall_getrusage', 'userland__write_child_rusage',
	'proc__account_disk_io', 'proc__account_page_fault', 'proc__account_context_switch',
	'proc__account_reaped_usage', 'proc__fill_rusage', 'proc__fill_process_rusage', 'proc__fill_times',
	'proc__fill_usage', 'proc__peak_rss', 'proc__maximum_counter', 'memory__Pagemap__account_resident']
pub const pagecache_functions = ['resource__advise_resource', 'file__Handle__sequential_read',
	'ext2__EXT2Resource__advise', 'pagecache__Cache__prefetch']

fn creation_line(body string) string {
	mut text := body
	for delimiter in ['\v', '\f', '\x1c', '\x1d', '\x1e', '\u0085', '\u2028', '\u2029'] {
		text = text.replace(delimiter, '\n')
	}
	for line in text.split('\n') {
		if line.contains('fs__create_node(') { return line }
	}
	return ''
}

pub fn allocation_check(generated Generated, name string, family string) !string {
	body := generated.body(name, family)!
	if hidden_allocation(body) { return error('hidden allocation in ${name}') }
	if family == 'accounting' && name in ['sys__syscall_getrusage', 'userland__write_child_rusage']
		&& body.count('vinix_stack_alloc(') != 1 {
		return error('${name}: expected one synchronous caller-stack record')
	}
	if family == 'pagecache' && name == 'pagecache__Cache__prefetch' {
		if body.count('vinix_stack_alloc(') != 1 {
			return error('prefetch slots must be allocated once before its loop')
		}
		if required_index(body, 'vinix_stack_alloc(')! > required_index(body, 'while (')! {
			return error('prefetch slots must be allocated once before its loop')
		}
	}
	return 'PASS ${name}: no compiler-generated heap copy'
}

pub fn procfs_check(generated Generated) ! {
	mount := generated.body('fs__new_mount', 'procfs')!
	call := 'fs__ProcFS__mount_checked('
	if mount.count(call) != 1 {
		return error('new_mount must use exactly one checked procfs dispatch')
	}
	at := required_index(mount, call)!
	start := mount[..at].last_index('\t} else if ') or { -1 }
	end := mount.index_after('\n\t} else {', at) or { return error('substring not found') }
	if start < 0 { return error('procfs must borrow the registered concrete template object') }
	branch := mount[start..end]
	if !branch.contains('map__get(&fs__filesystems') || !branch.contains('template->_typ ==')
		|| !branch.contains('(fs__ProcFS*)(template->_object)') {
		return error('procfs must borrow the registered concrete template object')
	}
	allocations := ['memdup(', 'HEAP(', 'malloc(', 'calloc(']
	for word in [...allocations, 'instantiate', 'to_Interface'] {
		if branch.contains(word) {
			return error('procfs denial dispatch creates an unused instance or box')
		}
	}
	helper := generated.body('fs__ProcFS__mount_checked', 'procfs')!
	acquire := 'klock__Lock__acquire(&fs__procfs_lock)'
	release := 'klock__Lock__release(&fs__procfs_lock)'
	if helper.count(acquire) != 1 || helper.count(release) != helper.count('return ') {
		return error('checked selection must lock once and unlock every return')
	}
	if helper.count('fs__is_beneath(target,') != 3 || helper.count('errno__set(errno__ebusy)') != 3
		|| required_index(helper, acquire)! > required_index(helper, 'fs__is_beneath(target,')! {
		return error('all cached-root ancestry checks must run under the lock')
	}
	check := required_index(helper, 'if (fs__is_beneath(target, reused))')!
	assignment := required_index(helper, '.ns = (void*)(view);')!
	retarget := required_index(helper, 'fs__retarget_view(reused, (void*)(view))')!
	if !(check < assignment && assignment < retarget) || allocations.any(helper.contains(it)) {
		return error('inactive selection allocates or mutates before ancestry check')
	}
	if !generated.body('fs__ProcFS__mount', 'procfs')!.contains('fs__ProcFS__mount_checked(this, parent, name, NULL)') {
		return error('interface mount must preserve the nil-target delegate')
	}
	creation := creation_line(generated.body('fs__ProcFS__build_root', 'procfs')!)
	if !creation.contains('._object = this') {
		return error('constructed roots must retain the persistent receiver')
	}
	ancestry := generated.body('fs__is_beneath', 'procfs')!
	if !ancestry.contains('4096') || !ancestry.contains('current = current->parent;')
		|| [...allocations, 'array_'].any(ancestry.contains(it)) {
		return error('ancestry must remain a bounded allocation-free parent walk')
	}
}

pub fn run(args []string, family string) int {
	if args == ['--help'] || args == ['-h'] {
		println('Usage: check-generated BLOB.c')
		return 0
	}
	mut paths := []string{}
	mut positional := false
	for argument in args {
		if argument == '--' && !positional {
			positional = true
			continue
		}
		if !positional && argument.starts_with('-') && argument != '-' {
			eprintln('Usage: check-generated BLOB.c')
			return 2
		}
		paths << argument
	}
	if paths.len != 1 {
		eprintln('Usage: check-generated BLOB.c')
		return 2
	}
	generated := parse(os.read_file(paths[0]) or {
		eprintln(if family == 'procfs' { 'FAIL: ${err}' } else { err.msg() })
		return 1
	}) or {
		eprintln(if family == 'procfs' { 'FAIL: ${err}' } else { err.msg() })
		return 1
	}
	if family == 'procfs' {
		procfs_check(generated) or {
			eprintln('FAIL: ${err}')
			return 1
		}
		println('PASS: permanent procfs template, locked ancestry before retarget, no denial boxing')
	} else {
		for name in if family == 'accounting' { accounting_functions } else { pagecache_functions } {
			message := allocation_check(generated, name, family) or {
				eprintln(err)
				return 1
			}
			println(message)
		}
	}
	return 0
}
