// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import crypto.sha256
import json2
import strconv

struct Entry {
	arch    string
	number  int
	name    string
	handler string
	status  string
	// File and function of the registration that boot leaves in place.
	source string
}

struct Registration {
	number  int
	handler string
	source  string
}

struct Coverage {
	baseline string
	inputs   map[string]string
	syscalls []Entry
}

fn definitions(source string) !map[int]string {
	mut result := map[int]string{}
	for line in source.split_into_lines() {
		words := line.fields()
		if words.len != 3 || words[0] != '#define' || !words[1].starts_with('__NR_') { continue }
		number := strconv.atoi(words[2])!
		if number < 0 || number >= 512 || number in result {
			return error('duplicate or out-of-range Linux number: ' + line)
		}
		result[number] = words[1].all_after('__NR_')
	}
	if result.len < 250 { return error('incomplete Linux reference') }
	return result
}

// handlers parses the assignments of one registration function, in order. A
// function never assigns the same number twice; a later function may.
fn handlers(source string) !map[int]string {
	mut result := map[int]string{}
	for raw in source.split_into_lines() {
		line := raw.all_before('//').trim_space()
		if !line.starts_with('syscall_table[') { continue }
		if !line.contains('= voidptr(') { return error('unrecognised dispatch: ' + line) }
		index := line.all_after('syscall_table[').all_before(']')
		if index == 'i' { continue }
		number := if index == 'seccomp_verdict_nr' { 511 } else { strconv.atoi(index)! }
		if number < 0 || number >= 512 || number in result {
			return error('duplicate or out-of-range dispatch: ' + line)
		}
		name := line.all_after('= voidptr(').all_before(')')
		if name == '' { return error('empty syscall handler') }
		result[number] = name
	}
	return result
}

// The kernel is compiled for exactly one architecture; build options such as
// `$if prod {` vary between the kernels this inventory describes, so a
// registration under one would be unknowable here and is refused.
fn arch_condition(condition string, arch string) !int {
	negated := condition.starts_with('!')
	name := condition.trim_left('!').trim_space()
	value := match name {
		'amd64', 'x64' { arch == 'x86_64' }
		'arm64', 'aarch64' { arch == 'aarch64' }
		else { return -1 }
	}
	return if value != negated { 1 } else { 0 }
}

// compiled_lines keeps the lines an architecture compiles. Blocks are tracked
// by their braces; each records 1 (compiled), 0 (not) or -1 (build option).
fn is_registration(line string) bool {
	return line.starts_with('syscall_table[') || line.starts_with('init_')
		|| line.starts_with('table.init_')
}

fn compiled_lines(lines []string, arch string) ![]string {
	mut result := []string{}
	mut states := []int{}
	mut conditions := []string{}
	for raw in lines {
		line := raw.all_before('//').trim_space()
		if line.starts_with(r'$if ') && !line.ends_with('{') {
			if line.contains('syscall_table[') || line.contains('init_syscall') || line.contains('_syscalls()') {
				return error('one-line conditional registration: ' + line)
			}
			continue
		}
		if line.starts_with(r'$if ') {
			condition := line.all_after(r'$if ').all_before_last('{').trim_space()
			states << arch_condition(condition, arch)!
			conditions << condition
			continue
		}
		if line == r'} $else {' {
			if conditions.len == 0 || conditions.last() == '' {
				return error(r'$else without $if')
			}
			state := arch_condition(conditions.last(), arch)!
			states[states.len - 1] = if state < 0 { -1 } else { 1 - state }
			conditions[conditions.len - 1] = ''
			continue
		}
		mut enabled := 1
		for state in states {
			if state < enabled { enabled = state }
		}
		if enabled == 1 {
			result << line
		} else if enabled < 0 && is_registration(line) {
			return error('registration under a build option: ' + line)
		}
		// Count the line's net braces: `} else {` and `unsafe { nil }` balance.
		net := line.count('{') - line.count('}')
		for _ in 0 .. -net {
			if states.len == 0 { return error('unbalanced braces: ' + line) }
			states.delete_last()
			conditions.delete_last()
		}
		for _ in 0 .. net {
			states << 1
			conditions << ''
		}
	}
	if states.len != 0 { return error('unterminated block') }
	return result
}

fn function_body(source string, name string) ?[]string {
	lines := source.split_into_lines()
	for i, line in lines {
		if line.starts_with('fn ${name}() {') || line.starts_with('pub fn ${name}() {') {
			for j in i + 1 .. lines.len {
				if lines[j] == '}' { return lines[i + 1..j] }
			}
			return none
		}
	}
	return none
}

fn table_file_for(root string, arch string, name string) !string {
	excluded := if arch == 'aarch64' { '_amd64.v' } else { '_arm64.v' }
	mut found := []string{}
	mut files := os.ls(root + '/kernel/syscall/table')!
	files.sort()
	for file in files {
		if !file.ends_with('.v') || file.ends_with('_test.v') || file.ends_with(excluded) { continue }
		path := 'kernel/syscall/table/' + file
		if _ := function_body(os.read_file(root + '/' + path)!, name) { found << path }
	}
	if found.len != 1 { return error('expected one definition of ${name} for ${arch}: ${found}') }
	return found[0]
}

// registrations follows boot: kmain calls the table's init functions in order,
// and each may call another; a later assignment replaces an earlier one.
fn registrations(root string, arch string, name string, mut inputs map[string]string, depth int) ![]Registration {
	if depth > 4 { return error('registration calls nest too deeply: ' + name) }
	path := table_file_for(root, arch, name)!
	source := os.read_file(root + '/' + path)!
	inputs[path] = sha256.sum(source.bytes()).hex()
	body := function_body(source, name) or { return error('missing ' + name) }
	lines := compiled_lines(body, arch)!
	mut result := []Registration{}
	mut own := []string{}
	for line in lines {
		if line.starts_with('init_') && line.ends_with('()') {
			result << registrations(root, arch, line.all_before('('), mut inputs, depth + 1)!
		} else if line.starts_with('syscall_table[') {
			own << line
			for number, handler in handlers(line)! {
				result << Registration{number, handler, path + ':' + name}
			}
		}
	}
	// Within one function a number is assigned once.
	handlers(own.join('\n'))!
	return result
}

fn dispatch_for(root string, arch string, mut inputs map[string]string) !map[int]Registration {
	main_path := 'kernel/main_' + if arch == 'aarch64' { 'arm64.v' } else { 'amd64.v' }
	main_source := os.read_file(root + '/' + main_path)!
	inputs[main_path] = sha256.sum(main_source.bytes()).hex()
	mut result := map[int]Registration{}
	mut calls := 0
	for line in compiled_lines(main_source.split_into_lines(), arch)! {
		if !line.starts_with('table.init_') { continue }
		if !line.ends_with('()') { return error('unrecognised registration call: ' + line) }
		calls++
		for registration in registrations(root, arch, line.all_after('table.').all_before('('), mut
			inputs, 0)! {
			result[registration.number] = registration
		}
	}
	if calls == 0 || result.len < 200 { return error('incomplete syscall dispatch') }
	return result
}

fn coverage(root string) !Coverage {
	mut entries := []Entry{}
	mut inputs := map[string]string{}
	for path in ['tools/linux-compat/coverage.v',
		'kernel/syscall/table/linux_compat.v', 'kernel/syscall/table/linux_common.v',
		'kernel/syscall/table/container.v', 'kernel/syscall/table/trace_amd64.v',
		'kernel/syscall/table/process_madvise.v', 'kernel/proc/inspect.v',
		'kernel/syscall/table/move_pages.v', 'kernel/memory/mmap/page_location.v',
		'kernel/syscall/table/mempolicy.v', 'kernel/numa/numa.v',
		'kernel/memory/mmap/mempolicy.v', 'kernel/numa/range_policy.v',
		'kernel/fs/sysfs.v', 'kernel/fs/sysfs_numa.v',
		'kernel/memory/physical_numa.v',
		'kernel/memory/mmap/page_in.v', 'kernel/memory/mmap/mmap_amd64.v',
		'kernel/memory/mmap/page_source.v',
		'kernel/file/file.v', 'kernel/resource/resource.v', 'kernel/resource/cache.v',
		'kernel/socket/unix/unix.v', 'kernel/pipe/pipe.v', 'kernel/pipe/usercopy.v', 'kernel/fs/vfs.v', 'kernel/fs/mount_policy.v',
		'kernel/fs/stat.v',
		'kernel/fs/mount_query.v',
		'kernel/fs/move_mount.v',
		'kernel/fs/open_tree.v',
		'kernel/fs/statmount.v',
		'kernel/fs/mount.v', 'kernel/fs/tmpfs.v', 'kernel/fs/procfs.v', 'kernel/fs/memfd_policy.v',
		'kernel/fs/cachestat.v',
		'kernel/fs/namespaces.v', 'kernel/fs/removed.v',
		'kernel/proc/proc.v', 'kernel/proc/proc_arm64.v', 'kernel/proc/proc_amd64.v',
		'kernel/proc/pidns.v',
		'kernel/proc/job_groups.v', 'kernel/userland/cred.v',
		'kernel/proc/state.v', 'kernel/kprint/printf_policy.v',
		'kernel/kprint/kprint_amd64.v', 'kernel/kprint/kprint_arm64.v',
		'kernel/proc/container.v', 'kernel/proc/seccomp.v',
		'kernel/proc/thread_attach.v',
		'kernel/proc/securebits.v',
		'kernel/sched/sched_arm64.v', 'kernel/sched/sched_amd64.v',
		'kernel/sched/inherit.v', 'kernel/sched/reap.v',
		'kernel/lib/stubs/pthread.v', 'kernel/c/pthread.h',
		'kernel/userland/exit.v',
		'kernel/userland/linux_task.v',
		'kernel/userland/userland.v',
		'kernel/kbudget/budget.v', 'kernel/proc/kernel_budget.v',
		'kernel/vmstorage/storage.v',
		'kernel/futex/futex.v', 'kernel/futex/futex2.v', 'kernel/futex/pi.v', 'kernel/event/event.v',
		'kernel/time/time.v',
		'kernel/usercopy/usercopy.v', 'kernel/usercopy/word_atomic_arm64.v',
		'kernel/usercopy/word_atomic_amd64.v',
		'kernel/userland/clone_arm64.v', 'kernel/userland/clone_amd64.v',
		'kernel/userland/userland_arm64.v', 'kernel/userland/linux_signal_amd64.v',
		'kernel/userland/seccomp_signal.v', 'kernel/memory/mmap/linux.v',
		'kernel/memory/mmap/lock.v', 'kernel/memory/mmap/inherit.v',
		'kernel/memory/mmap/immutable.v', 'kernel/memory/mmap/paging.v',
		'kernel/memory/mmap/remap_file.v', 'kernel/memory/mmap/process_advice.v',
		'kernel/memory/mmap/mmap_arm64.v', 'kernel/memory/activity_arm64.v',
		'kernel/memory/activity_amd64.v',
		'kernel/memory/mmap/seal.v', 'kernel/memory/virtual.v',
		'kernel/memory/mmap/mmap.v', 'kernel/memory/table_budget.v',
		'kernel/memory/physical.v', 'kernel/memory/slab.v',
		'kernel/memory/virtual_arm64.v', 'kernel/memory/virtual_amd64.v'] {
		inputs[path] = sha256.sum(os.read_bytes(root + '/' + path)!).hex()
	}
	supplement := 'tools/linux-compat/reference/linux-6.12-syscalls.h'
	supplement_text := os.read_file(root + '/' + supplement)!
	inputs[supplement] = sha256.sum(supplement_text.bytes()).hex()
	for arch in ['aarch64', 'x86_64'] {
		reference := 'tools/linux-compat/reference/' + arch + '-syscall.h'
		ref_text := os.read_file(root + '/' + reference)!
		inputs[reference] = sha256.sum(ref_text.bytes()).hex()
		names := definitions(ref_text + '\n' + supplement_text)!
		dispatch := dispatch_for(root, arch, mut inputs)!
		for number in 0 .. 512 {
			if number !in names && number !in dispatch { continue }
			name := names[number] or { 'vinix_private' }
			registration := dispatch[number] or { Registration{number, 'vacant', ''} }
			// Wiring is evidence of dispatch only, never semantic qualification.
			status := if number !in names {
				'private'
			} else if number !in dispatch || name in ['bpf', 'rseq'] {
				'unavailable'
			} else {
				'wired; unqualified'
			}
			entries << Entry{arch, number, name, registration.handler, status, registration.source}
		}
	}
	return Coverage{'Native ELF64 syscall numbers from musl 1.2.5 and selected Linux 6.12 additions', inputs, entries}
}

fn markdown(report Coverage) string {
	mut lines := ['# Linux syscall dispatch coverage', '',
		'Generated by `build-support/run-v-tool.sh tools/linux-compat/coverage.v`.', '',
		'The baseline combines musl 1.2.5 and selected syscall numbers from Linux 6.12.',
		'Semantics and workload qualification are recorded separately.',
		'Absent native numbers return ENOSYS. Private Vinix calls are excluded from Linux coverage.',
		'See [behavior and runtime matrix](linux-posix-compatibility.md) for qualification and limitations.',
		'']
	for arch in ['aarch64', 'x86_64'] {
		rows := report.syscalls.filter(it.arch == arch && it.status != 'private')
		wired := rows.filter(it.status.starts_with('wired')).len
		lines << ['## ' + arch, '',
			'${wired}/${rows.len} baseline calls have a non-vacant dispatch (excluding known unavailable BPF/rseq).', '',
			'| Number | Linux name | Handler | Dispatch status | Registered by |', '| --- | --- | --- | --- | --- |']
		for entry in report.syscalls.filter(it.arch == arch) {
			source := if entry.source == '' { '' } else { '`' + entry.source + '`' }
			lines << '| ${entry.number} | ${entry.name} | `${entry.handler}` | ${entry.status} | ${source} |'
		}
		lines << ''
	}
	lines << ['## Source hashes', '', '| Input | SHA-256 |', '| --- | --- |']
	mut paths := report.inputs.keys()
	paths.sort()
	for path in paths { lines << '| `${path}` | `${report.inputs[path]}` |' }
	return lines.join('\n') + '\n'
}

fn main() {
	if os.args.len > 2 || (os.args.len == 2 && os.args[1] != '--check') {
		eprintln('Usage: coverage.v [--check]')
		exit(2)
	}
	root := os.real_path(os.dir(@FILE) + '/../..')
	report := coverage(root) or {
		eprintln(err.msg())
		exit(1)
	}
	outputs := {
		'docs/linux-syscall-coverage.md':   markdown(report)
		'docs/linux-syscall-coverage.json': json2.encode(report, prettify: true) + '\n'
	}
	for path, value in outputs {
		if os.args.len == 2 {
			old := os.read_file(root + '/' + path) or {
				eprintln(err.msg())
				exit(1)
			}
			if old != value {
				eprintln('Stale coverage: ' + path)
				exit(1)
			}
		} else {
			os.write_file(root + '/' + path, value) or {
				eprintln(err.msg())
				exit(1)
			}
		}
	}
	println('Linux dispatch coverage: PASS')
}
