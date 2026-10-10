// SPDX-License-Identifier: GPL-2.0-or-later
module guardcore

fn delegate_definition(name string, body string) string {
	return 'void ${name}(void) {\n${body}\n}\n'
}

fn test_ipv6_delegate_reaches_scratch_and_preserves_all_rejections() {
	call := 'return inet__InetSocket__recvfrom_flags(this, handle, buf, count, _addr, addrlen, 0);'
	owner := 'vinix_stack_alloc(Endpoint);\nfor (;;) { copy(); }'
	fixture := delegate_definition('inet__InetSocket__recvfrom', call) +
		delegate_definition('inet__InetSocket__recvfrom_flags', owner)
	assert ipv6_check(parse(fixture)!, 'inet__InetSocket__recvfrom')! == 'PASS inet__InetSocket__recvfrom: endpoint/Text scratch stays on caller stack'
	for before, after in {
		call:                           call.replace(', 0);', ', flags);')
		'vinix_stack_alloc(Endpoint);': 'copy();'
		'for (;;) { copy(); }':         'for (;;) { vinix_stack_alloc(Endpoint); }'
	} {
		ipv6_check(parse(fixture.replace(before, after))!, 'inet__InetSocket__recvfrom') or { continue }
		assert false, 'accepted broken IPv6 delegate/scratch: ${before}'
	}
	for name in ['inet__InetSocket__recvfrom', 'inet__InetSocket__recvfrom_flags'] {
		for call_name in scratch_allocations {
			bad := fixture.replace('void ${name}(void) {', 'void ${name}(void) {\n${call_name}(data);')
			ipv6_check(parse(bad)!, 'inet__InetSocket__recvfrom') or {
				assert err.msg() == 'heap-promoted scratch in ${name}'
				continue
			}
			assert false, 'accepted allocator in receive delegate chain'
		}
	}
	for source in [delegate_definition('inet__InetSocket__recvfrom', call),
		fixture.replace(call, call + '\n' + call),
		fixture.replace(call, 'vinix_stack_alloc(Endpoint);\n' + call)] {
		ipv6_check(parse(source)!, 'inet__InetSocket__recvfrom') or { continue }
		assert false, 'accepted missing or duplicated receive delegate'
	}
}

fn test_process_inheritance_delegate_chain_preserves_one_path_owner() {
	outer := 'return sched__new_process_in_group(old_process, pagemap, account);'
	inner := 'return sched__new_process_with_vm(old_process, pagemap, account, false);'
	clone := 'new_proc->executable_path = string__clone(old_process->executable_path);'
	fixture := delegate_definition('sched__new_process', outer) +
		delegate_definition('sched__new_process_in_group', inner) +
		delegate_definition('sched__new_process_with_vm', clone) +
		delegate_definition('userland__clone_new_process', 'return new_process;')
	assert clone_check(parse(fixture)!)! == 'PASS process clone: one inherited executable-path owner'
	for before, after in {
		outer: outer.replace(', account);', ', other);')
		inner: inner.replace(', false);', ', true);')
		clone: 'borrow(old_process->executable_path);'
	} {
		clone_check(parse(fixture.replace(before, after))!) or { continue }
		assert false, 'accepted broken process inheritance delegate/owner: ${before}'
	}
	for call in [outer, inner, clone] {
		clone_check(parse(fixture.replace(call, call + '\n' + call))!) or { continue }
		assert false, 'accepted duplicate inheritance delegate/owner'
	}
	for name in ['sched__new_process', 'sched__new_process_in_group', 'userland__clone_new_process'] {
		bad := fixture.replace('void ${name}(void) {', 'void ${name}(void) {\nnew_process->executable_path = extra;')
		clone_check(parse(bad)!) or { continue }
		assert false, 'accepted a wrapper/caller overwriting the path owner'
	}
	for name in ['sched__new_process_in_group', 'sched__new_process_with_vm'] {
		missing := fixture.replace('void ${name}(void) {', 'void different(void) {')
		clone_check(parse(missing)!) or {
			assert err.msg() == 'missing ${name} definition'
			continue
		}
		assert false, 'accepted missing process delegate definition'
	}
}
