// SPDX-License-Identifier: GPL-2.0-or-later
module guardcore

pub const procfs_scratch_functions = ['fs__ProcFSResource__contents', 'fs__machine_stat_text',
	'fs__maps_text', 'proc__process_stat_line', 'proc__process_status_text', 'table__linux_getdents',
	'fs__syscall_readdir']
pub const ipv6_functions = ['inet__fill_endpoint', 'inet__copy_endpoint_out',
	'inet__InetSocket__set_structured_ip_option', 'inet__InetSocket__sendto',
	'inet__InetSocket__recvfrom', 'inet__InetSocket__bind', 'inet__InetSocket__connect',
	'inet__socket_name', 'inet__proc_net_tcp_text', 'inet__proc_net_tcp6_text',
	'inet__proc_net_if_inet6_text']
const scratch_allocations = ['memdup', 'malloc', 'array_new', 'new_array_from_c_array']

pub fn procfs_scratch_check(generated Generated, name string) !string {
	function := generated.selected(name, 'word')!
	if !function.contains('vinix_stack_alloc(') {
		return error('missing caller stack scratch: ${name}')
	}
	for line in function.split('\n') {
		if at := line.index('memdup(') {
			if line[at + 7..].contains('sizeof(lib__Text)') {
				return error('heap-promoted text descriptor: ${name}')
			}
		}
	}
	if name == 'fs__syscall_readdir' && function.contains('memdup(') {
		return error('heap-promoted directory snapshot scratch')
	}
	if name == 'table__linux_getdents' {
		if word_calls(function, scratch_allocations, false).len > 0 {
			return error('heap allocation in directory entry loop')
		}
		at := required_index(function, 'while (')!
		if function[..at].count('vinix_stack_alloc(') != 2 || function[at..].contains('vinix_stack_alloc(') {
			return error('directory scratch must be bounded once per call')
		}
	}
	return 'PASS ${name}: measured scratch storage stays on caller stack'
}

pub fn ipv6_check(generated Generated, name string) !string {
	function := generated.selected(name, 'word')!
	if word_calls(function, scratch_allocations, false).len > 0 {
		return error('heap-promoted scratch in ${name}')
	}
	if name == 'inet__InetSocket__recvfrom' && function.contains('inet__InetSocket__recvfrom_flags(') {
		if function.contains('vinix_stack_alloc(') {
			return error('receive wrapper must not allocate scratch')
		}
		checked_delegate(function, 'inet__InetSocket__recvfrom_flags',
			'return inet__InetSocket__recvfrom_flags(this, handle, buf, count, _addr, addrlen, 0);')!
		ipv6_check(generated, 'inet__InetSocket__recvfrom_flags')!
		return 'PASS ${name}: endpoint/Text scratch stays on caller stack'
	}
	if name != 'inet__fill_endpoint' && !function.contains('vinix_stack_alloc(') {
		return error('missing caller stack scratch: ${name}')
	}
	loops := word_calls(function, ['for'], true)
	if loops.len > 0 && function[loops[0]..].contains('vinix_stack_alloc(') {
		return error('scratch allocated repeatedly inside loop: ${name}')
	}
	return 'PASS ${name}: endpoint/Text scratch stays on caller stack'
}

pub fn timer_check(generated Generated) !string {
	sleep := generated.timer_body('userland__sleep_for_signal')!
	if sleep.count('vinix_stack_alloc(') != 1 {
		return error('wait list must use one caller-stack pointer slot')
	}
	if !sleep.contains('Array events = event__stack_list(storage, count);') {
		return error('array header must remain by value')
	}
	if !sleep.contains('event__await_masked(&events') {
		return error('wait must use explicit signal mask')
	}
	for name in ['userland__sleep_for_signal', 'event__await_masked', 'event__stack_list'] {
		body := generated.timer_body(name)!
		if word_calls(body, ['memdup', 'v_malloc', '_v_malloc', '_v_malloc_noscan', 'new_array',
			'__new_array'], true).len > 0 {
			return error(name)
		}
	}
	return 'POSIX timer generated-C caller ownership: PASS'
}

pub const socket_names = ['syscall_sendto', 'syscall_recvfrom', 'syscall_sendmsg', 'syscall_recvmsg',
	'send_message', 'receive_message', 'iovec_from_user', 'send_with_control', 'send_from_kernel',
	'receive_to_kernel', 'receive_into']
pub const socket_slots = [2, 3, 1, 1, 2, 4, 1, 2, 1, 1, 1]

pub fn socket_check(generated Generated, name string, count int) !string {
	body := generated.selected('socket__' + name, 'socket')!
	if body.count('vinix_stack_alloc(') != count {
		return error('unexpected scratch count: ${name}')
	}
	if name != 'receive_into' && body.contains('memdup(') {
		return error('heap-promoted scratch: ${name}')
	}
	if has_assignment(body, 'fd->handle->flags', true) {
		return error('per-call override writes shared flags: ${name}')
	}
	if name == 'receive_into' && !body.contains('v_free(sock)') {
		return error('socket interface box lost its owner')
	}
	if name in ['syscall_sendto', 'send_message', 'receive_message'] {
		// The socket policy matches a literal space, unlike the IPv6 policy.
		for at in word_calls(body, ['for'], true) {
			if !body[at..].starts_with('for (') { continue }
			opening := body.index_after('{', at) or { return error('substring not found') }
			end := balanced_end(body, opening)!
			if body[opening..end].contains('vinix_stack_alloc(') {
				return error('scratch allocated inside loop: ${name}')
			}
		}
	}
	return 'PASS socket__${name}: caller-owned scratch and flags'
}

pub fn unix_socket_check(generated Generated, name string) !string {
	body := generated.selected('unix__UnixSocket__' + name, 'socket')!
	if body.count('vinix_stack_alloc(sizeof(unix__PendingFdGroup))') != 1 {
		return error('queued FD record must use one caller-stack slot: ${name}')
	}
	if body.count('array__push_many(&group->fds, fds.data, fds.len);') != 1 {
		return error('queued record must own exactly one descriptor-list copy: ${name}')
	}
	pushes := body.count('array_push(&peer->pending_fd_groups,') + body.count('array_push(&target->pending_fd_groups,')
	if queued_transfers(body) != 1 || pushes != 1 {
		return error('missing single shallow owned record transfer: ${name}')
	}
	if !body.contains('group->fds.flags |= 1;')
		|| (!body.contains('peer->pending_fd_groups.flags |= 1;') && !body.contains('target->pending_fd_groups.flags |= 1;')) {
		return error('owned queues must release old growth buffers: ${name}')
	}
	if ['__derived_clone', 'array__clone(', 'memdup('].any(body.contains(it)) {
		return error('descriptor-list clone or heap record leaks source: ${name}')
	}
	return 'PASS unix__UnixSocket__${name}: one queued descriptor-list owner'
}

pub fn churn_check(generated Generated) !string {
	body := generated.selected('fs__slabinfo_text', 'churn')!
	if body.count('vinix_stack_alloc(') != 1 || body.contains('memdup(') {
		return error('slabinfo Text metadata must use one caller-stack slot')
	}
	if body.count('array__free(&classes);') != 1 || !body.contains('return lib__finish_text(*text);') {
		return error('existing class-array/string ownership was lost')
	}
	finish := generated.selected('lib__finish_text', 'churn')!
	if finish.count('Array_u8__bytestr(t.bytes)') != 1 || finish.count('array__free(&t.bytes);') != 1 || !finish.contains('return s;') {
		return error('finish_text must return one string and free its consumed buffer')
	}
	return 'PASS fs__slabinfo_text: caller-stack metadata, existing buffer ownership'
}

pub fn select_check(generated Generated) !string {
	body := generated.selected('file__do_select', 'churn')!
	if body.count('vinix_stack_alloc(') != 1 || body.contains('memdup(') {
		return error('do_select scratch must use one caller-stack slot')
	}
	if !body.contains('array__free(&polls);') || !body.contains('array__free(&indexes);') {
		return error('do_select poll/index array ownership was lost')
	}
	if !body.contains('remaining = deadline;') || !body.contains('file__ppoll(') {
		return error('do_select timeout initialization/consumer was lost')
	}
	return 'PASS file__do_select: caller-stack scratch, synchronous ppoll consumer'
}

pub fn clone_check(generated Generated) !string {
	mut inherited := generated.selected('sched__new_process', 'churn')!
	if inherited.contains('sched__new_process_in_group(') {
		checked_path_delegate(inherited, 'sched__new_process_in_group',
			'return sched__new_process_in_group(old_process, pagemap, account);')!
		group := generated.selected('sched__new_process_in_group', 'churn')!
		checked_path_delegate(group, 'sched__new_process_with_vm',
			'return sched__new_process_with_vm(old_process, pagemap, account, false);')!
		inherited = generated.selected('sched__new_process_with_vm', 'churn')!
	}
	if inherited.count('new_proc->executable_path = string__clone(old_process->executable_path);') != 1 {
		return error('new_process must establish exactly one inherited path owner')
	}
	clone := generated.selected('userland__clone_new_process', 'churn')!
	if has_assignment(clone, 'new_process->executable_path', false) {
		return error('process clone overwrites its inherited path owner')
	}
	return 'PASS process clone: one inherited executable-path owner'
}

fn checked_delegate(body string, name string, expected string) ! {
	if body.count(name + '(') != 1 || body.count(expected) != 1 {
		return error('expected one unchanged ownership delegate: ${name}')
	}
}

fn checked_path_delegate(body string, name string, expected string) ! {
	checked_delegate(body, name, expected)!
	if body.contains('executable_path') {
		return error('process inheritance wrapper must not create or overwrite a path owner')
	}
}
