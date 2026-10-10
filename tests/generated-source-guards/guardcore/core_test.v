// SPDX-License-Identifier: GPL-2.0-or-later
module guardcore

import hosttest
import os

fn definition(name string, body string) string {
	return 'void ${name}(void) {\n${body}\n}\n'
}

fn accounting_fixture() string {
	return accounting_functions.map(definition(it, if it in ['sys__syscall_getrusage',
		'userland__write_child_rusage'] {
		'\tvinix_stack_alloc(sizeof(Record));\n\treturn 0;'
	} else {
		'\treturn 0;'
	})).join('\n')
}

fn pagecache_fixture() string {
	return pagecache_functions.map(definition(it, if it == 'pagecache__Cache__prefetch' {
		'\tvinix_stack_alloc(sizeof(Slots));\n\twhile (ready) {}\n\treturn 0;'
	} else {
		'\treturn 0;'
	})).join('\n')
}

fn procfs_fixture() string {
	return definition('fs__new_mount', '\tif (other) {\n\t} else if (procfs) {\n' +
		'\t\ttemplate = map__get(&fs__filesystems, name);\n\t\tif (template->_typ == PROC) {\n' +
		'\t\t\tfs__ProcFS__mount_checked((fs__ProcFS*)(template->_object), parent, name, target);\n\t\t}\n\t} else {\n\t}\n') +
		definition('fs__ProcFS__mount_checked', '\tklock__Lock__acquire(&fs__procfs_lock);\n' +
			'\tif (fs__is_beneath(target, existing)) { errno__set(errno__ebusy); klock__Lock__release(&fs__procfs_lock); return denied; }\n' +
			'\tif (fs__is_beneath(target, reused)) { errno__set(errno__ebusy); klock__Lock__release(&fs__procfs_lock); return denied; }\n' +
			'\tnode = (Node){.ns = (void*)(view);};\n\tfs__retarget_view(reused, (void*)(view));\n' +
			'\tif (fs__is_beneath(target, root)) { errno__set(errno__ebusy); klock__Lock__release(&fs__procfs_lock); return denied; }\n' +
			'\tklock__Lock__release(&fs__procfs_lock);\n\treturn root;') +
		definition('fs__ProcFS__mount', '\treturn fs__ProcFS__mount_checked(this, parent, name, NULL);') +
		definition('fs__ProcFS__build_root', '\treturn fs__create_node((Resource){._object = this});') +
		definition('fs__is_beneath', '\tfor (int i = 0; i < 4096; i++) { current = current->parent; }\n\treturn false;')
}

fn test_function_selection_prototypes_prefix_boundaries_and_truncation() {
	valid := definition('target', '\tvalue();')
	for prefix in ['', 'static ', 'Type* ', 'Type *'] {
		generated := parse('void target(void);\n' + prefix + valid)!
		assert generated.body('target', 'accounting')! == '\tvalue();'
	}
	for source in [' void target(void) {\n\tvalue();\n}\n', 'void prefix_target(void) {\n\tvalue();\n}\n',
		'void target(void);\n', 'void\ttarget(void) {\n\tvalue();\n}\n'] {
		parse(source)!.body('target', 'accounting') or {
			assert err.msg() == 'missing function target'
			continue
		}
		assert false, 'accepted a nonmatching resource definition'
	}
	assert parse(' void target(void) {\n\tvalue();\n}\n')!.body('target', 'pagecache')! == '\tvalue();'
	parse('void target(int x; int y) {\n\tvalue();\n}\n')!.body('target', 'procfs') or {
		assert err.msg() == 'missing target definition'
	}
	parse('void ém_target(void) {\n\tvalue();\n}\n')!.body('m_target', 'pagecache') or {
		assert err.msg() == 'missing function m_target'
	}
	assert parse(valid.replace('\n', '\r\n'))!.body('target', 'accounting')! == '\tvalue();'
	assert parse(valid.replace('\n', '\r'))!.body('target', 'accounting')! == '\tvalue();'
	parse('\xff') or { assert err.msg().contains('UTF-8') }
	parse('void target(void) {\n\tvalue();\n')!.body('target', 'accounting') or {
		assert err.msg() == 'substring not found'
		return
	}
	assert false, 'accepted a truncated function'
}

fn test_allocation_word_boundaries_and_unicode_whitespace() {
	for name in ['memdup', 'new_array_from_c_array', 'builtin__memdup', 'v_malloc'] {
		for whitespace in ['', ' ', '\t', '\n', '\u0085', '\u00a0', '\u2003', '\u2028', '\u3000',
			'\x1c'] {
			assert hidden_allocation('x = ${name}${whitespace}(data);')
		}
		for prefix in ['my_', 'é', '猫', '1'] {
			assert !hidden_allocation('${prefix}${name}(data);')
		}
		assert !hidden_allocation('${name}_extra(data);')
		assert !hidden_allocation('${name};')
	}
	assert !hidden_allocation('memcpy(a, b); malloc(n); array__clone(a);')
}

fn test_accounting_all_functions_and_stack_slot_counts() {
	generated := parse(accounting_fixture())!
	for name in accounting_functions {
		assert allocation_check(generated, name, 'accounting')! == 'PASS ${name}: no compiler-generated heap copy'
		bad := parse(definition(name, '\tmemdup (record);'))!
		allocation_check(bad, name, 'accounting') or {
			assert err.msg() == 'hidden allocation in ${name}'
			continue
		}
		assert false, 'accepted an allocation in ${name}'
	}
	for name in accounting_functions[..2] {
		for count in [0, 2] {
			body := '\tvinix_stack_alloc(record);\n'.repeat(count) + '\treturn 0;'
			allocation_check(parse(definition(name, body))!, name, 'accounting') or {
				assert err.msg() == '${name}: expected one synchronous caller-stack record'
				continue
			}
			assert false, 'wrong stack count was accepted'
		}
	}
}

fn test_pagecache_all_functions_prefetch_loop_order_and_missing_loop() {
	generated := parse(pagecache_fixture())!
	for name in pagecache_functions { allocation_check(generated, name, 'pagecache')! }
	for body in ['\twhile (ready) {}\n\tvinix_stack_alloc(slot);', '\twhile (ready) {}',
		'\tvinix_stack_alloc(slot);\n\tvinix_stack_alloc(slot);\n\twhile (ready) {}'] {
		allocation_check(parse(definition('pagecache__Cache__prefetch', body))!, 'pagecache__Cache__prefetch', 'pagecache') or {
			assert err.msg() == 'prefetch slots must be allocated once before its loop'
			continue
		}
		assert false, 'accepted an unbounded prefetch scratch slot'
	}
	allocation_check(parse(definition('pagecache__Cache__prefetch', '\tvinix_stack_alloc(slot);'))!, 'pagecache__Cache__prefetch', 'pagecache') or {
		assert err.msg() == 'substring not found'
		return
	}
	assert false, 'missing prefetch loop was accepted'
}

fn test_procfs_complete_guard_and_each_ownership_rejection() {
	source := procfs_fixture()
	procfs_check(parse(source)!)!
	for before, after in {
		'fs__ProcFS__mount_checked((fs__ProcFS*)(template->_object),': 'unchecked((fs__ProcFS*)(template->_object),'
		'map__get(&fs__filesystems':                                   'map__get(&other'
		'template->_typ ==':                                           'template->_kind =='
		'(fs__ProcFS*)(template->_object)':                            '(fs__ProcFS*)(other->_object)'
		'\t\ttemplate =':                                              '\t\tmemdup(temporary); template ='
		'klock__Lock__acquire(&fs__procfs_lock);':                     'unlocked();'
		'klock__Lock__release(&fs__procfs_lock);':                     'unreleased();'
		'errno__set(errno__ebusy)':                                    'errno__set(errno__einval)'
		'fs__is_beneath(target, existing)':                            'unchecked(target, existing)'
		'.ns = (void*)(view);':                                        '.ns = view;'
		'fs__retarget_view(reused, (void*)(view))':                    'unchecked(reused, (void*)(view))'
		'\treturn root;':                                              '\tmalloc(8); return root;'
		'this, parent, name, NULL':                                    'this, parent, name, target'
		'._object = this':                                             '._object = temporary'
		'4096':                                                        '8192'
		'current = current->parent;':                                  'current = other;'
	} {
		procfs_check(parse(source.replace(before, after))!) or { continue }
		assert false, 'procfs ownership regression was accepted: ${before}'
	}
	for word in ['memdup(', 'HEAP(', 'malloc(', 'calloc(', 'instantiate', 'to_Interface'] {
		procfs_check(parse(source.replace('\t\ttemplate =', '\t\t${word}; template ='))!) or {
			assert err.msg() == 'procfs denial dispatch creates an unused instance or box'
			continue
		}
		assert false, 'procfs denial allocation was accepted'
	}
}

fn test_procfs_creation_uses_the_first_unicode_line() {
	for separator in ['\n', '\v', '\f', '\x1c', '\x1d', '\x1e', '\u0085', '\u2028', '\u2029'] {
		assert creation_line('prefix${separator}fs__create_node(._object = this)${separator}tail') == 'fs__create_node(._object = this)'
		bad := procfs_fixture().replace('fs__create_node((Resource){._object = this})', 'fs__create_node((Resource){._object = temporary})${separator}._object = this')
		procfs_check(parse(bad)!) or {
			assert err.msg() == 'constructed roots must retain the persistent receiver'
			continue
		}
		assert false, 'later line hid a temporary root receiver'
	}
}

fn test_cli_success_partial_stdout_errors_and_usage() {
	tools := os.getenv('VINIX_GUARD_TOOLS')
	if tools == '' { return }
	work := hosttest.work_dir('', 'vinix-source-guard-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for family, source in {
		'accounting': accounting_fixture()
		'pagecache':  pagecache_fixture()
		'procfs':     procfs_fixture()
	} {
		tool := tools + '/' + family
		os.write_file(work + '/blob.c', source)!
		result := hosttest.capture([tool, work + '/blob.c'], '', 30, os.environ())!
		assert result.code == 0 && result.stderr == '' && result.stdout.starts_with('PASS')
		assert result.stdout.count('\n') == if family == 'accounting' {
			13
		} else if family == 'pagecache' {
			4
		} else {
			1
		}
		for args in [[]string{}, ['--unknown'], ['a', 'b']] {
			mut argv := [tool]
			argv << args
			usage := hosttest.capture(argv, '', 30, os.environ())!
			assert usage.code == 2 && usage.stdout == '' && usage.stderr != ''
		}
		missing := hosttest.capture([tool, work + '/missing'], '', 30, os.environ())!
		assert missing.code == 1 && missing.stdout == '' && missing.stderr != ''
		os.write_file(work + '/blob.c', '\xff')!
		invalid := hosttest.capture([tool, work + '/blob.c'], '', 30, os.environ())!
		assert invalid.code == 1 && invalid.stdout == '' && invalid.stderr.contains('UTF-8')
	}
	os.write_file(work + '/blob.c', accounting_fixture().replace('void proc__account_disk_io(void) {\n', 'void proc__account_disk_io(void) {\n\tmemdup(data);\n'))!
	partial := hosttest.capture([tools + '/accounting', work + '/blob.c'], '', 30, os.environ())!
	assert partial.code == 1 && partial.stdout.count('\n') == 2
	assert partial.stderr == 'hidden allocation in proc__account_disk_io\n'
}
