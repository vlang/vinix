// SPDX-License-Identifier: GPL-2.0-or-later
module guardcore

import hosttest
import os

fn scratch_definition(name string, body string) string {
	return 'void ${name}(void) {\n${body}\n}\n'
}

fn procfs_scratch_fixture() string {
	mut source := ''
	for name in procfs_scratch_functions {
		source += scratch_definition(name, if name == 'table__linux_getdents' {
			'\tvinix_stack_alloc(Text);\n\tvinix_stack_alloc(Entry);\n\twhile (ready) { copy(); }'
		} else {
			'\tvinix_stack_alloc(Text);\n\treturn 0;'
		})
	}
	return source
}

fn ipv6_fixture() string {
	return ipv6_functions.map(scratch_definition(it, if it == 'inet__fill_endpoint' {
		'\tcopy();'
	} else {
		'\tvinix_stack_alloc(Endpoint);\n\tfor (int i = 0; i < 4; i++) { copy(); }'
	})).join('\n')
}

fn timer_fixture() string {
	return scratch_definition('userland__sleep_for_signal', '\tvinix_stack_alloc(voidptr);\n' +
		'\tArray events = event__stack_list(storage, count);\n\tevent__await_masked(&events, signal);') +
		scratch_definition('event__await_masked', '\tfor (;;) { if (ready) { return true; } }') +
		scratch_definition('event__stack_list', '\treturn header;')
}

fn unix_fixture(name string) string {
	return scratch_definition('unix__UnixSocket__' + name, '\tvinix_stack_alloc(sizeof(unix__PendingFdGroup));\n' +
		'\tarray__push_many(&group->fds, fds.data, fds.len);\n\tgroup->fds.flags |= 1;\n' +
		'\tunix__PendingFdGroup queued = *group;\n\tarray_push(&peer->pending_fd_groups, &queued);\n' +
		'\tpeer->pending_fd_groups.flags |= 1;')
}

fn socket_fixture() string {
	mut source := ''
	for index, name in socket_names {
		source += scratch_definition('socket__' + name, '\tvinix_stack_alloc(Scratch);\n'.repeat(socket_slots[index]) +
			'\tfor (int i = 0; i < 4; i++) { if (ready) { copy(); } }\n\tv_free(sock);')
	}
	return source + unix_fixture('write_with_fds') + unix_fixture('send_datagram')
}

fn churn_fixture() string {
	return scratch_definition('fs__slabinfo_text', '\tvinix_stack_alloc(Text);\n\tarray__free(&classes);\n\treturn lib__finish_text(*text);') +
		scratch_definition('lib__finish_text', '\ts = Array_u8__bytestr(t.bytes);\n\tarray__free(&t.bytes);\n\treturn s;') +
		scratch_definition('file__do_select', '\tvinix_stack_alloc(Timeout);\n\tremaining = deadline;\n\tfile__ppoll(polls);\n\tarray__free(&polls);\n\tarray__free(&indexes);') +
		scratch_definition('sched__new_process', '\tnew_proc->executable_path = string__clone(old_process->executable_path);') +
		scratch_definition('userland__clone_new_process', '\treturn new_process;')
}

fn check_family(generated Generated, family string, operations bool) ! {
	match family {
		'procfs-scratch' {
			for name in procfs_scratch_functions { procfs_scratch_check(generated, name)! }
		}
		'ipv6' {
			for name in ipv6_functions { ipv6_check(generated, name)! }
		}
		'socket' {
			for index, name in socket_names { socket_check(generated, name, socket_slots[index])! }
			for name in ['write_with_fds', 'send_datagram'] { unix_socket_check(generated, name)! }
		}
		'timer' { timer_check(generated)! }
		'churn' {
			churn_check(generated)!
			if operations {
				select_check(generated)!
				clone_check(generated)!
			}
		}
		else { return error('unknown test family') }
	}
}

fn rejected(source string, family string, expected string) {
	generated := parse(source) or { panic(err) }
	check_family(generated, family, true) or {
		assert err.msg() == expected
		return
	}
	assert false, 'accepted ${family} ownership regression: ${expected}'
}

fn test_new_selectors_unicode_prefixes_trailing_code_and_brace_rules() {
	for prefix in ['void', '_type', '猫', 'é', '٢'] {
		source := '${prefix} target(void) {\n\tvalue();\n}\n'
		assert parse(source)!.selected('target', 'word')! == source
		assert parse(source)!.selected('target', 'churn')! == '\tvalue();'
	}
	for source in ['void* target(void) {\n\tvalue();\n}\n', 'void  target(void) {\n\tvalue();\n}\n',
		'void\ttarget(void) {\n\tvalue();\n}\n', ' void target(void) {\n\tvalue();\n}\n',
		'void prefix_target(void) {\n\tvalue();\n}\n', 'void target(void);\n'] {
		parse(source)!.selected('target', 'word') or { continue }
		assert false, 'accepted a nonmatching word-prefix definition'
	}
	for prefix in ['static void*', ' void', 'X', '  '] {
		source := '${prefix} target(void) {\n\tvalue();\n}\n'
		assert parse(source)!.selected('target', 'socket')! == source
	}
	trailing := 'void target(void) { comment\n\tvalue();\n}\n'
	assert parse(trailing)!.selected('target', 'word')! == trailing
	mut refused := false
	parse(trailing)!.selected('target', 'churn') or {
		assert err.msg() == 'missing target definition'
		refused = true
	}
	assert refused, 'accepted trailing signature text in churn selector'
	for selector in ['word', 'socket', 'churn'] {
		parse('void target(void) {\n\tvalue();\n')!.selected('target', selector) or {
			assert err.msg() == 'substring not found'
			continue
		}
		assert false, 'accepted truncated C'
	}
	multiline := ' static void target(\nint first,\nint second) {\n{ nested(); }\n}\n'
	assert parse(multiline)!.timer_body('target')! == '{\n{ nested(); }\n}'
	for source in ['void target(void);\n', 'void x_target(void) {\n}\n', 'void étarget(void) {\n}\n',
		'void target(int x; int y) {\n}\n'] {
		parse(source)!.timer_body('target') or { continue }
		assert false, 'accepted a nonmatching timer definition'
	}
	parse('void target(void) {\n { unmatched;\n}\n')!.timer_body('target') or {
		assert err.msg() == 'unterminated brace block'
		return
	}
	assert false, 'accepted truncated timer braces'
}

fn test_procfs_scratch_each_function_text_promotion_and_directory_bounds() {
	fixture := procfs_scratch_fixture()
	check_family(parse(fixture)!, 'procfs-scratch', true)!
	for name in procfs_scratch_functions {
		mut refused := false
		procfs_scratch_check(parse(scratch_definition(name, '\treturn 0;'))!, name) or {
			assert err.msg() == 'missing caller stack scratch: ${name}'
			refused = true
		}
		assert refused, 'accepted missing procfs scratch'
		body := '\tvinix_stack_alloc(Text);\n\tmy_memdup(x, sizeof(lib__Text));'
		procfs_scratch_check(parse(scratch_definition(name, body))!, name) or {
			assert err.msg() == 'heap-promoted text descriptor: ${name}'
			continue
		}
		assert false, 'accepted heap Text descriptor'
	}
	for before, after in {
		'vinix_stack_alloc(Entry);': 'copy();'
		'while (ready) { copy(); }': 'while (ready) { vinix_stack_alloc(Entry); }'
	} {
		rejected(fixture.replace(before, after), 'procfs-scratch', 'directory scratch must be bounded once per call')
	}
	for call in ['memdup', 'malloc', 'array_new', 'new_array_from_c_array'] {
		rejected(fixture.replace('while (ready) { copy(); }', 'while (ready) { ${call}(entry); }'), 'procfs-scratch', 'heap allocation in directory entry loop')
	}
	rejected(fixture.replace('void fs__syscall_readdir(void) {', 'void fs__syscall_readdir(void) {\n\tmemdup(snapshot);'), 'procfs-scratch', 'heap-promoted directory snapshot scratch')
	// A newline interrupts the original Text-descriptor pattern.
	assert procfs_scratch_check(parse(scratch_definition('fs__machine_stat_text', '\tvinix_stack_alloc(Text); memdup(data,\nsizeof(lib__Text));'))!, 'fs__machine_stat_text')!.starts_with('PASS')
}

fn test_ipv6_allocation_boundaries_stack_exceptions_and_loop_tail() {
	check_family(parse(ipv6_fixture())!, 'ipv6', true)!
	for name in ipv6_functions {
		for call in scratch_allocations {
			ipv6_check(parse(scratch_definition(name, '\tvinix_stack_alloc(X); ${call}(x);'))!, name) or {
				assert err.msg() == 'heap-promoted scratch in ${name}'
				continue
			}
			assert false, 'accepted IPv6 heap scratch'
		}
		if name != 'inet__fill_endpoint' {
			ipv6_check(parse(scratch_definition(name, '\tcopy();'))!, name) or {
				assert err.msg() == 'missing caller stack scratch: ${name}'
				continue
			}
			assert false, 'accepted missing endpoint scratch'
		}
	}
	for space in ['', ' ', '\n', '\t', '\u0085', '\u2028', '\u3000'] {
		body := '\tfor${space}(;;) { copy(); }\n\tvinix_stack_alloc(Endpoint);'
		ipv6_check(parse(scratch_definition('inet__copy_endpoint_out', body))!, 'inet__copy_endpoint_out') or {
			assert err.msg() == 'scratch allocated repeatedly inside loop: inet__copy_endpoint_out'
			continue
		}
		assert false, 'accepted scratch after first loop'
	}
	for prefix in ['my_', 'é', '猫', '1'] {
		assert ipv6_check(parse(scratch_definition('inet__copy_endpoint_out', '\tvinix_stack_alloc(X); ${prefix}malloc(x);'))!, 'inet__copy_endpoint_out')!.starts_with('PASS')
	}
	assert word_calls('memdup (x); malloc\t(x);', scratch_allocations, false).len == 0
}

fn test_timer_stack_list_ownership_and_each_hidden_allocator() {
	fixture := timer_fixture()
	assert timer_check(parse(fixture)!)! == 'POSIX timer generated-C caller ownership: PASS'
	for before, after in {
		'vinix_stack_alloc(voidptr);':                       'copy();'
		'Array events = event__stack_list(storage, count);': 'Array* events = header;'
		'event__await_masked(&events':                       'event__await(events'
	} {
		expected := if before.starts_with('vinix') {
			'wait list must use one caller-stack pointer slot'
		} else if before.starts_with('Array') {
			'array header must remain by value'
		} else {
			'wait must use explicit signal mask'
		}
		rejected(fixture.replace(before, after), 'timer', expected)
	}
	for name in ['userland__sleep_for_signal', 'event__await_masked', 'event__stack_list'] {
		for allocator in ['memdup', 'v_malloc', '_v_malloc', '_v_malloc_noscan', 'new_array',
			'__new_array'] {
			for space in ['', ' ', '\t', '\u00a0', '\u2003', '\x1f'] {
				bad := fixture.replace('void ${name}(void) {', 'void ${name}(void) {\n\t${allocator}${space}(x);')
				rejected(bad, 'timer', name)
			}
		}
	}
}

fn test_socket_slots_shared_flags_box_cleanup_and_nested_loop_bounds() {
	fixture := socket_fixture()
	check_family(parse(fixture)!, 'socket', true)!
	for index, name in socket_names {
		for count in [socket_slots[index] - 1, socket_slots[index] + 1] {
			body := '\tvinix_stack_alloc(Scratch);\n'.repeat(count) + '\tv_free(sock);'
			socket_check(parse(scratch_definition('socket__' + name, body))!, name, socket_slots[index]) or {
				assert err.msg() == 'unexpected scratch count: ${name}'
				continue
			}
			assert false, 'accepted wrong socket stack count'
		}
	}
	for op in ['=', '|=', '&=', '=='] {
		for space in ['', '\n', '\u2003'] {
			bad := fixture.replace('void socket__syscall_sendto(void) {', 'void socket__syscall_sendto(void) {\n\tfd->handle->flags${space}${op}value;')
			rejected(bad, 'socket', 'per-call override writes shared flags: syscall_sendto')
		}
	}
	rejected(fixture.replace('v_free(sock);', 'keep(sock);'), 'socket', 'socket interface box lost its owner')
	for name in ['syscall_sendto', 'send_message', 'receive_message'] {
		body := '\tvinix_stack_alloc(Scratch);\n'.repeat(socket_slots[socket_names.index(name)] - 1) +
			'\tfor (;;) { if (ready) { vinix_stack_alloc(Scratch); } }\n\tv_free(sock);'
		socket_check(parse(scratch_definition('socket__' + name, body))!, name, socket_slots[socket_names.index(name)]) or {
			assert err.msg() == 'scratch allocated inside loop: ${name}'
			continue
		}
		assert false, 'accepted loop stack allocation'
	}
	// Stack storage after a closed loop is allowed; only literal "for (" matches.
	for loop in ['for (;;) { copy(); }', 'for\t(;;) { vinix_stack_alloc(Scratch); }'] {
		body := '\t${loop}\n' + '\tvinix_stack_alloc(Scratch);\n'.repeat(if loop.contains('\t') {
			1
		} else {
			2
		})
		assert socket_check(parse(scratch_definition('socket__send_message', body))!, 'send_message', 2)!.starts_with('PASS')
	}
}

fn test_unix_queue_single_shallow_transfer_and_all_owners() {
	for name in ['write_with_fds', 'send_datagram'] {
		fixture := unix_fixture(name)
		assert unix_socket_check(parse(fixture)!, name)!.starts_with('PASS')
		for before, after in {
			'vinix_stack_alloc(sizeof(unix__PendingFdGroup))':   'allocate()'
			'array__push_many(&group->fds, fds.data, fds.len);': 'borrow(fds);'
			'&queued);':                                         '&different);'
			'unix__PendingFdGroup queued = *group;':             'unix__PendingFdGroup queued = clone(group);'
			'group->fds.flags |= 1;':                            'group->fds.flags |= 0;'
			'peer->pending_fd_groups.flags |= 1;':               'peer->pending_fd_groups.flags |= 0;'
		} {
			unix_socket_check(parse(fixture.replace(before, after))!, name) or { continue }
			assert false, 'accepted queued owner regression: ${before}'
		}
		for extra in ['__derived_clone(group);', 'array__clone(fds);', 'memdup(group);',
			'array_push(&target->pending_fd_groups, &queued);'] {
			bad := fixture.replace('void unix__UnixSocket__${name}(void) {', 'void unix__UnixSocket__${name}(void) {\n\t${extra}')
			unix_socket_check(parse(bad)!, name) or { continue }
			assert false, 'accepted extra queued copy/transfer'
		}
		for space in [' ', '\n', '\u2003', '\u0085'] {
			variant := fixture.replace('peer->', 'target->').replace('queued', '猫٢').replace('unix__PendingFdGroup 猫٢ = *group;', 'unix__PendingFdGroup${space}猫٢${space}=${space}*group;${space}').replace(', &猫٢);', ',${space}&猫٢);')
			assert unix_socket_check(parse(variant)!, name)!.starts_with('PASS')
		}
	}
}

fn test_churn_formatter_select_timeout_and_inherited_path_owners() {
	fixture := churn_fixture()
	check_family(parse(fixture)!, 'churn', true)!
	for before, after in {
		'vinix_stack_alloc(Text);':                    'memdup(Text);'
		'array__free(&classes);':                      'keep(classes);'
		'return lib__finish_text(*text);':             'return text;'
		'Array_u8__bytestr(t.bytes)':                  'borrow(t.bytes)'
		'array__free(&t.bytes);':                      'keep(t.bytes);'
		'return s;':                                   'return other;'
		'vinix_stack_alloc(Timeout);':                 'memdup(Timeout);'
		'array__free(&polls);':                        'keep(polls);'
		'array__free(&indexes);':                      'keep(indexes);'
		'remaining = deadline;':                       'remaining = 0;'
		'file__ppoll(polls);':                         'async_poll(polls);'
		'string__clone(old_process->executable_path)': 'old_process->executable_path'
	} {
		check_family(parse(fixture.replace(before, after))!, 'churn', true) or { continue }
		assert false, 'accepted churn ownership regression: ${before}'
	}
	for space in ['', ' ', '\n', '\u2028'] {
		rejected(fixture.replace('return new_process;', 'new_process->executable_path${space}= another;'), 'churn', 'process clone overwrites its inherited path owner')
	}
}

fn test_native_scratch_cli_options_errors_partial_output_and_cleanup() {
	tools := os.getenv('VINIX_SCRATCH_TOOLS')
	if tools == '' { return }
	work := hosttest.work_dir('', 'vinix-scratch-cli-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for family, fixture in {
		'procfs-scratch': procfs_scratch_fixture()
		'ipv6':           ipv6_fixture()
		'socket':         socket_fixture()
		'timer':          timer_fixture()
		'churn':          churn_fixture()
	} {
		tool := tools + '/' + family
		path := work + '/blob.c'
		for newline in ['\n', '\r\n', '\r'] {
			os.write_file(path, fixture.replace('\n', newline))!
			result := hosttest.capture([tool, '--', path], '', 30, os.environ())!
			assert result.code == 0 && result.stderr == ''
			assert result.stdout.count('\n') == match family {
				'procfs-scratch' { 7 }
				'ipv6' { 11 }
				'socket' { 13 }
				else { 1 }
			}
		}
		for argv in [[]string{}, ['--unknown'], ['a', 'b']] {
			mut command := [tool]
			command << argv
			result := hosttest.capture(command, '', 30, os.environ())!
			assert result.code == 2 && result.stdout == '' && result.stderr.starts_with('Usage:')
		}
		for option in ['-h', '--help'] {
			result := hosttest.capture([tool, option], '', 30, os.environ())!
			assert result.code == 0 && result.stderr == '' && result.stdout.starts_with('Usage:')
		}
		missing := hosttest.capture([tool, path + '.missing'], '', 30, os.environ())!
		assert missing.code == 1 && missing.stdout == '' && missing.stderr != ''
		os.write_file(path, '\xff')!
		invalid := hosttest.capture([tool, path], '', 30, os.environ())!
		assert invalid.code == 1 && invalid.stdout == '' && invalid.stderr.contains('UTF-8')
	}
	path := work + '/blob.c'
	os.write_file(path, churn_fixture())!
	for argv in [[path, '--operations'], ['--oper', path], [path, '--operations', '--operations']] {
		mut command := [tools + '/churn']
		command << argv
		result := hosttest.capture(command, '', 30, os.environ())!
		assert result.code == 0 && result.stderr == '' && result.stdout.count('\n') == 3
	}
	os.write_file(path, churn_fixture().replace('array__free(&indexes);', 'keep(indexes);'))!
	ignored := hosttest.capture([tools + '/churn', path], '', 30, os.environ())!
	assert ignored.code == 0 && ignored.stdout.count('\n') == 1
	failed := hosttest.capture([tools + '/churn', path, '--operations'], '', 30, os.environ())!
	assert failed.code == 1 && failed.stdout.count('\n') == 1 && failed.stderr.contains('poll/index')
	os.write_file(path, ipv6_fixture().replace('void inet__copy_endpoint_out(void) {', 'void inet__copy_endpoint_out(void) {\n\tmalloc(4);'))!
	partial := hosttest.capture([tools + '/ipv6', path], '', 30, os.environ())!
	assert partial.code == 1 && partial.stdout == 'PASS inet__fill_endpoint: endpoint/Text scratch stays on caller stack\n'
	assert partial.stderr == 'heap-promoted scratch in inet__copy_endpoint_out\n'
	assert os.ls(work)!.sorted() == ['blob.c']
}
