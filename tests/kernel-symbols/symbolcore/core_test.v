// SPDX-License-Identifier: GPL-2.0-or-later
module symbolcore

import hosttest
import math.big
import os

fn test_allocation_labels_counts_spacing_and_zero_spelling() {
	site := allocation_line('serial: PERF-SITE tmpfs open 002 ６４ 0 1000 00 2000\r\n') or { panic('missing site') }
	assert site == Site{'tmpfs open', '002', '６４', ['00', '2000']}
	assert allocation_line('PERF-SITE  1 2 0')? == Site{'', '1', '2', []string{}}
	assert allocation_line('PERF-SITE a 1 2 3 4 5')? == Site{'a', '1', '2', ['4', '5']}
	assert allocation_line('PERF-SITE a 1 2 invalid 3 4 5')? == Site{'a 1 2 invalid', '3', '4', []string{}}
}

fn test_allocation_pattern_rejects_invalid_hex_and_delimiters() {
	for bad in ['PERF-SITE a 1 2 ABC', 'PERF-SITE a 1 2 1  2', 'PERF-SITE a -1 2 3',
		'PERF-SITE a 1 2 0x30', 'PERF-SITE a 1 2 ', 'PERF-SITE a\t1 2 3'] {
		allocation_line(bad) or { continue }
		assert false, bad
	}
	site := allocation_line('PERF-SITE a 1 2 3 4 5 6') or { panic('missing site') }
	assert site.label == 'a' && site.count == '1' && site.size == '2' && site.addresses == [
		'4',
		'5',
		'6',
	]
	assert allocation_key(site) == allocation_key(Site{'a', '999', '2', ['4', '5', '6']})
	assert allocation_key(site) != allocation_key(Site{'a', '1', '2', ['04', '5', '6']})
}

fn test_return_address_adjustment_preserves_arbitrary_width() {
	assert subtract('100000000000000000000000000000000', 4, false)! == '0xfffffffffffffffffffffffffffffffc'
	assert subtract('00', 4, false)! == '-0x4'
	assert subtract('3', 4, false)! == '-0x1'
	assert subtract('0', 1, true)! == '0'
	assert subtract('01', 1, true)! == '0'
	assert subtract('10000000000000000', 1, true)! == 'ffffffffffffffff'
}

fn test_allocator_frames_ignore_internal_prefixes_and_incomplete_pairs() {
	text := 'malloc_noscan\na:1\nwork\nb:2\n\n??\n??:0\nmemdup_more\nc:3\ninline\nd:4\n\nunpaired'
	assert allocation_frames(text) == ['work', 'inline']
	assert allocation_frames(text.replace('\n', '\r\n')) == ['work', 'inline']
}

fn hit(kind string, pc string, lr string, frames []string, process string) string {
	return 'user-access: ${kind} 0x55 at pc 0x${pc} lr 0x${lr} < 0x${frames[0]} 0x${frames[1]} 0x${frames[2]} 0x${frames[3]} (${process})'
}

fn test_access_byte_pattern_greedy_process_and_replacement_decoding() {
	text := 'serial ' + hit('read', '0010', '20', ['30', '0', '40', '50'], 'p(a)th') + ' suffix)\n' +
		hit('wrote', 'ff', '0', ['0', '0', '0', '0'], 'bad\xff\xe2\x82') + '\n' +
		hit('read', 'ABC', '0', ['0', '0', '0', '0'], 'ignored')
	assert access_hits(text) == [
		Hit{'read', '0010', '20', ['30', '0', '40', '50'], 'p(a)th) suffix'},
		Hit{'wrote', 'ff', '0', ['0', '0', '0', '0'], 'bad��'},
	]
	assert replacement_utf8('é\xe0\x80\x80\xed\xa0\x80\xf0\x90\x80') == 'é�������'
}

fn test_access_numeric_order_dedup_and_symbol_block_pairing() {
	hits := [Hit{'read', '0100', '11', ['00', '2', '101', '10000000000000000'], 'p'}]
	assert access_addresses(hits)! == ['1', '10', '100', 'ffffffffffffffff']
	assert access_names(['1', '2', '3'], 'f\nloc\ninlined\nloc\n\ng\nloc\n\nodd\n') == {
		'1': ['f', 'inlined']
		'2': ['g']
		'3': ['odd']
	}
}

fn test_access_leaf_link_register_architecture_and_path_dedup() {
	table := {
		'10': ['memcpy']
		'20': ['worker']
		'1f': ['caller']
		'2f': ['outer']
		'3f': ['outer', '??', 'top']
	}
	hits := [Hit{'read', '10', '20', ['30', '40', '0', '0'], 'first'},
		Hit{'read', '010', '020', ['030', '040', '0', '0'], 'duplicate'},
		Hit{'wrote', '20', '20', ['30', '0', '0', '0'], 'writer'}]
	arm, arm_code := access_report(hits, table, false)
	assert arm == 'read  memcpy < caller < outer < top   [first]\nwrote worker < outer   [writer]\n2 paths\n'
	assert arm_code == 1
	x86, x86_code := access_report(hits, table, true)
	assert x86 == 'read  memcpy < caller < outer < top   [first]\nwrote worker < caller < outer   [writer]\n2 paths\n'
	assert x86_code == 1
}

fn test_native_allocation_command_stdin_dedup_and_failed_symbolizer() {
	tool := os.getenv('VINIX_ALLOC_SITES_TOOL')
	if tool == '' { return }
	work := hosttest.work_dir('', 'vinix-alloc-sites-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	input := work + '/run.log'
	stub := work + '/llvm-symbolizer'
	os.write_file(stub, '#!/bin/sh\nfor arg do\ncase "$arg" in\n0x10) printf "malloc_uninit\\nalloc:1\\n\\n" ;;\n0x20) printf "work\\nsource:2\\ninline\\nsource:3\\n\\n" ;;\nesac\ndone\nexit 3\n')!
	os.chmod(stub, 0o755)!
	os.write_file(input, 'ignore\nPERF-SITE ops 2 64 0 100 14 24\n\nPERF-SITE ops 9 64 0 100 14 24\nPERF-SITE churn 1 128 0 100 24\n')!
	mut env := os.environ()
	env['LLVM_BIN'] = work
	result := hosttest.capture(['/bin/sh', '-c', 'exec "$1" "$2" < "$3"', 'sh', tool, work + '/kernel',
		input], '', 30, env)!
	assert result.code == 0 && result.stderr == ''
	assert result.stdout == 'ops: 2 x 64 bytes\n    work <- inline\nchurn: 1 x 128 bytes\n    work <- inline\n'
}

fn test_native_access_command_empty_input_architecture_and_symbolizer_failure() {
	tool := os.getenv('VINIX_USER_SITES_TOOL')
	if tool == '' { return }
	work := hosttest.work_dir('', 'vinix-user-sites-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	input := work + '/run.log'
	kernel := work + '/kernel'
	stub := work + '/llvm-symbolizer'
	os.write_file(stub, '#!/bin/sh\nfor arg do\ncase "$arg" in\n0x10) printf "worker\\nsource:1\\n\\n" ;;\n0x1f) printf "caller\\nsource:2\\n\\n" ;;\n0x2f) printf "outer\\nsource:3\\n\\n" ;;\nesac\ndone\nexit "$SYMBOLIZER_EXIT"\n')!
	os.chmod(stub, 0o755)!
	mut env := os.environ()
	env['PATH'] = work + ':' + env['PATH']
	env['SYMBOLIZER_EXIT'] = '0'
	argv := ['/bin/sh', '-c', 'exec "$1" "$2" < "$3"', 'sh', tool, kernel, input]
	os.write_file(input, '')!
	empty := hosttest.capture(argv, '', 30, env)!
	assert empty.code == 0 && empty.stdout == 'no direct user accesses reported\n'
	os.write_file(input, hit('read', '10', '20', ['30', '0', '0', '0'], 'p') + '\n')!
	for arch in [u8(0xb7), 0x3e] {
		mut header := []u8{len: 20}
		header[18] = arch
		os.write_file_array(kernel, header)!
		result := hosttest.capture(argv, '', 30, env)!
		assert result.code == 1 && result.stderr == ''
		assert result.stdout == if arch == 0x3e {
			'read  worker < caller < outer   [p]\n1 paths\n'
		} else {
			'read  worker < outer   [p]\n1 paths\n'
		}
	}
	env['SYMBOLIZER_EXIT'] = '3'
	failed := hosttest.capture(argv, '', 30, env)!
	assert failed.code == 1 && failed.stdout == '' && failed.stderr.contains('llvm-symbolizer exited 3')
}

fn test_real_llvm_symbolizer_on_arm_and_x86_elfs() {
	if os.getenv('VINIX_SYMBOLIZER_REAL') != '1' { return }
	work := hosttest.work_dir('', 'vinix-real-symbols-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	source := work + '/fixture.c'
	os.write_file(source, '__attribute__((noinline)) void main__work(void) { __asm__ volatile(""); }\n__attribute__((noinline)) void main__caller(void) { main__work(); }\nvoid _start(void) { main__caller(); }\n')!
	clang := if os.exists('/opt/homebrew/opt/llvm/bin/clang') {
		'/opt/homebrew/opt/llvm/bin/clang'
	} else {
		os.find_abs_path_of_executable('clang')!
	}
	linker := os.find_abs_path_of_executable('ld.lld')!
	nm := hosttest.tool('llvm-nm')
	symbolizer := allocation_tool()!
	for target in ['aarch64-none-elf', 'x86_64-none-elf'] {
		object := work + '/' + target + '.o'
		kernel := work + '/' + target + '.elf'
		compiled := hosttest.capture([clang, '-target', target, '-g', '-O0', '-ffreestanding',
			'-fno-stack-protector', '-c', source, '-o', object], '', 30, os.environ())!
		assert compiled.code == 0, compiled.stderr
		linked := hosttest.capture([linker, '-e', '_start', '-o', kernel, object], '', 30, os.environ())!
		assert linked.code == 0, linked.stderr
		listed := hosttest.capture([nm, '-n', kernel], '', 30, os.environ())!
		assert listed.code == 0
		mut addresses := map[string]string{}
		for row in listed.stdout.split_into_lines() {
			fields := row.fields()
			if fields.len == 3 { addresses[fields[2]] = canonical(fields[0]) }
		}
		work_pc := addresses['main__work'] or { panic('missing worker') }
		caller_pc := addresses['main__caller'] or { panic('missing caller') }
		worker := big.integer_from_radix(work_pc, 16)!
		caller := big.integer_from_radix(caller_pc, 16)!
		site := Site{'real', '2', '64', [(worker + big.integer_from_int(4)).hex(),
			(caller + big.integer_from_int(4)).hex()]}
		assert allocation_report(site, kernel, symbolizer)! == 'real: 2 x 64 bytes\n    main__work <- main__caller\n'
		hits := [Hit{'read', work_pc, (caller + big.integer_from_int(1)).hex(), [
			(caller + big.integer_from_int(1)).hex(),
			'0',
			'0',
			'0',
		], 'fixture'}]
		wanted := access_addresses(hits)!
		mut argv := [symbolizer, '-e', kernel, '--inlines', '--functions=short']
		argv << wanted.map('0x' + it)
		resolved := hosttest.capture(argv, '', 30, os.environ())!
		assert resolved.code == 0
		message, code := access_report(hits, access_names(wanted, resolved.stdout), target.starts_with('x86'))
		assert message == 'read  main__work < main__caller   [fixture]\n1 paths\n' && code == 1
	}
}
