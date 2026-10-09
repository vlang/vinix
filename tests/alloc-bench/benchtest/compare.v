module benchtest

import androidhost as ah
import runtimebuild as rb

fn invoke_program(exe ah.Value, args ah.Value, mode ah.Value, index ah.Value) !ah.Value {
	run_ := factory('subprocess', 'run')!
	argument0 := str(exe)!
	argv := list([o(argument0)])!
	release([argument0])!
	extend(argv, args)!
	environ := attr(target('os')!, 'environ')!
	env := rb.callback('mapping_unpack', {'id': environ})!
	release([environ])!
	put(env, 'VAB_FAIL', mode)!
	value := str(index)!
	put(env, 'VAB_FAIL_INDEX', value)!
	release([value])!
	discard(method(env, '__setitem__', [v('ASAN_OPTIONS'), v('detect_leaks=1')])!)!
	discard(method(env, '__setitem__', [v('UBSAN_OPTIONS'), v('halt_on_error=1')])!)!
	return temporary_call(run_, [o(argv)], {'capture_output': ah.Value(true), 'timeout': ah.Value(180)}, {'env': env}, [argv, env])!
}
fn normalize(contents ah.Value, help_text ah.Value) !ah.Value {
	mut result := invoke(factory('re', 'sub')!, [bytes('Usage: [^\\n]+'), bytes('Usage: PROGRAM [--iterations N] [--samples N] [--quick] [--label NAME]'), o(contents)], {})!
	rb.callback('consume_argument', {'name': ah.Value('contents')})!
	release([contents])!
	if truth(help_text)! {
		changed := invoke(factory('re', 'sub')!, [bytes('Build: [^\\n]+'), bytes('Build: generated benchmark'), o(result)], {})!
		release([result])!
		result = changed
	}
	return result
}
fn add_case(cases ah.Value, name string, args ah.Value, mode string, index int) ! {
	value := tuple([v(name), o(args), v(mode), n(index)])!
	append(cases, value)!
	release([value])!
}
fn cases() !ah.Value {
	values := list([])!
	for pair in [[1, 5]!, [63, 6]!, [64, 5]!, [65, 6]!, [257, 31]!, [2000, 5]!] {
		args := list([v('--iterations'), v(pair[0].str()), v('--samples'), v(pair[1].str()), v('--label'), v('a_Z-0.1')])!
		add_case(values, 'success-${pair[0]}-${pair[1]}', args, 'none', 1)!
		release([args])!
	}
	for entry in [['ordered', '--quick', '--iterations', '65', '--samples', '6'], ['help', '--help'], ['help_after_quick', '--quick', '--help']] {
		args := list(entry[1..].map(v(it)))!
		add_case(values, entry[0], args, 'none', 1)!
		release([args])!
	}
	mut invalid := [][]string{len: 0}
	invalid << [['--unknown'], ['--unknown', 'value'], ['--samples'], ['--iterations'], ['--label']]
	for item in ['', '0', '-1', '+1', ' 1', '1x', '1000000001', '18446744073709551616'] { invalid << ['--iterations', item] }
	for item in ['', '4', '32', '6x', '18446744073709551616'] { invalid << ['--samples', item] }
	for item in ['', 'a'.repeat(65), 'a b', 'a=b', '\u00ff'] { invalid << ['--label', item] }
	for index, row in invalid {
		args := list(row.map(v(it)))!
		add_case(values, 'invalid-${index}', args, 'none', 1)!
		release([args])!
	}
	base := list([v('--iterations'), v('65'), v('--samples'), v('6')])!
	mut malloc_positions := [1, 2, 65, 66, 130, 455]
	for index in 456 .. 520 { malloc_positions << index }
	malloc_positions << [520, 521, 910, 911, 912, 914, 915]
	for index in malloc_positions { add_case(values, 'malloc-${index}', base, 'malloc', index)! }
	modes := ['mmap', 'munmap', 'pipe', 'close', 'clock', 'close_both', 'constant_clock', 'uname', 'resolution', 'pagesize']
	positions := [[1, 2, 28, 29, 30], [1, 28, 29], [1, 2, 5], [1, 2, 3, 4], [1, 2, 3, 13, 24, 36, 72], [1], [1], [1], [1], [1]]
	for i, mode in modes {
		for index in positions[i] { add_case(values, '${mode}-${index}', base, mode, index)! }
	}
	release([base])!
	return values
}
fn case_bool(name ah.Value, prefix string) !bool { return truth_value(method(name, 'startswith', [v(prefix)])!)! }
fn error_description(name ah.Value, v_ ah.Value, c ah.Value, v_out ah.Value, c_out ah.Value) !ah.Value {
	return tuple([o(name), temp(attr(v_, 'returncode')!), temp(attr(c, 'returncode')!), o(v_out), o(c_out), temp(attr(v_, 'stderr')!), temp(attr(c, 'stderr')!)])!
}
fn compare(v_exe ah.Value, c_exe ah.Value, work ah.Value, debug bool) ! {
	mut f := Frame{}
	all_cases := f.named('cases', cases()!)!
	proofs := f.named('proofs', list([])!)!
	iterator := item_iter(all_cases)!
	for {
		row := rb.next(iterator)!
		if row == rb.null() { break }
		name := f.named('name', get_index(row, 0)!)!
		args := f.named('args', get_index(row, 1)!)!
		mode := f.named('mode', get_index(row, 2)!)!
		index := f.named('index', get_index(row, 3)!)!
		c := f.named('c', invoke(target('invoke')!, [o(c_exe), o(args), o(mode), o(index)], {})!)!
		v_ := f.named('v', invoke(target('invoke')!, [o(v_exe), o(args), o(mode), o(index)], {})!)!
		expected_help := f.named('expected_help', method(name, 'startswith', [v('help')])!)!
		cn := target('normalize')!
		c_stdout := attr(c, 'stdout')!
		c_new := temporary_call(cn, [o(c_stdout), o(expected_help)], {}, {}, [c_stdout])!
		vn := target('normalize')!
		v_stdout := attr(v_, 'stdout')!
		v_new := temporary_call(vn, [o(v_stdout), o(expected_help)], {}, {}, [v_stdout]) or { release([c_new])!; return err }
		c_out := f.named('c_out', c_new)!
		v_out := f.named('v_out', v_new)!
		if debug {
			left := tuple([temp(attr(v_, 'returncode')!), o(v_out), temp(attr(v_, 'stderr')!)])!
			right := tuple([temp(attr(c, 'returncode')!), o(c_out), temp(attr(c, 'stderr')!)])!
			compared := op('eq', left, o(right))!
			release([left, right])!
			equal := truth_value(compared)!
			if !equal { fail_message(error_description(name, v_, c, v_out, c_out)!)! }
			search := factory('re', 'search')!
			v_error := attr(v_, 'stderr')!
			c_error := attr(c, 'stderr')!
			joined := op('add', v_error, o(c_error))!
			release([v_error, c_error])!
			if truth_value(temporary_call(search, [bytes('runtime error|AddressSanitizer|LeakSanitizer'), o(joined)], {}, {}, [joined])!)! { fail_plain()! }
		}
		if case_bool(name, 'success')! || truth_value(op('eq', name, v('ordered'))!)! {
			if debug {
				if !attr_compare(v_, 'returncode', 'eq', n(0))! || !truth_value(op('contains', v_out, bytes('ALLOC-DONE'))!)! { fail_plain()! }
				len_ := target('len')!
				find := factory('re', 'findall')!
				multiline := attr(target('re')!, 'M')!
				matches := temporary_call(find, [bytes('^ALLOC-RESULT '), o(v_out), o(multiline)], {}, {}, [multiline])!
				count := temporary_call(len_, [o(matches)], {}, {}, [matches])!
				if !truth_value(op('eq', count, n(6))!)! { fail_plain()! }
			}
		} else if case_bool(name, 'invalid')! {
			if debug && !attr_compare(v_, 'returncode', 'eq', n(2))! { fail_plain()! }
		} else if !truth(expected_help)! {
			if debug && (!attr_compare(v_, 'returncode', 'eq', n(1))! || !attr_compare(v_, 'stderr', 'contains', bytes('ALLOC-ERROR'))!) { fail_plain()! }
		}
        stdout_file := plus(name, '.stdout')!
        stdout_path := op('truediv', work, o(stdout_file))!
        release([stdout_file])!
        statement(receiver(stdout_path, 'write_bytes')!, [o(v_out)], {})!
        stderr_file := plus(name, '.stderr')!
        stderr_path := op('truediv', work, o(stderr_file))!
        release([stderr_file])!
        statement(receiver(stderr_path, 'write_bytes')!, [temp(attr(v_, 'stderr')!)], {})!
		proof := dict(['case', 'argv', 'fault', 'index', 'returncode', 'stdout_sha256', 'stderr_sha256'], [o(name), o(args), o(mode), o(index), temp(attr(v_, 'returncode')!), temp(digest_bytes(v_out)!), temp(digest_attr(v_, 'stderr')!)])!
		append(proofs, proof)!
		release([row, proof])!
	}
	release([iterator])!
	write_json(join(work, 'differential.json')!, proofs)!
	printer := target('print')!
	length := call('len', [o(all_cases)])!
	formatted := format(length)!
	message := plus(op('add', literal('Portable allocation benchmark: ')!, o(formatted))!, ' C/V differential cases passed, including all 64 mixed-batch OOM prefixes')!
	discard(temporary_call(printer, [o(message)], {}, {}, [length, formatted, message])!)!
}
