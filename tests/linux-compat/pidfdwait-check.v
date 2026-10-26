// SPDX-License-Identifier: GPL-2.0-or-later
// This checker uses explicit errors: validation remains active under -prod.
module main

import os

fn case_order() []string {
	return ['live', 'nonblock', 'nonblock_nohang', 'nowait', 'consume', 'reaped', 'identity',
		'negative_fd', 'missing_fd', 'wrong_type', 'nonchild', 'options', 'copyout_error',
		'copyout_nowait', 'copyout_consume', 'rusage_order', 'null_info', 'blocked_close',
		'sibling_reap', 'plain_wait4']
}

fn expected_cases() map[string]u64 {
	return {
		'live':            u64(8)
		'nonblock':        8
		'nonblock_nohang': 8
		'nowait':          8
		'consume':         1
		'reaped':          2
		'identity':        4
		'negative_fd':     16
		'missing_fd':      9
		'wrong_type':      2
		'nonchild':        2
		'options':         3
		'copyout_error':   4
		'copyout_nowait':  2
		'copyout_consume': 2
		'rusage_order':    2
		'null_info':       2
		'blocked_close':   16
		'sibling_reap':    16
		'plain_wait4':     2
	}
}

fn decimal(token string) !u64 {
	if token == '' || !token.bytes().all(it >= `0` && it <= `9`)
		|| (token.len > 1 && token[0] == `0`) {
		return error('noncanonical decimal token: ' + token)
	}
	value := token.u64()
	if value.str() != token { return error('decimal token overflow: ' + token) }
	return value
}

fn semantics(log string, mode string) ! {
	if mode !in ['native', 'reference'] { return error('mode must be native or reference') }
	if log.contains('\x00') { return error('NUL byte in log') }
	for marker in ['LINUX PIDFDWAIT DETAIL:', 'LINUX PIDFDWAIT FAIL', 'LINUX PIDFDWAIT REFERENCE FAIL',
		'LINUX PIDFDWAIT: FAIL', 'Kernel panic', 'KERNEL PANIC', 'FATAL EXCEPTION'] {
		if log.contains(marker) { return error('failure marker in log: ' + marker) }
	}
	if mode == 'reference' && !log.contains('Linux version ') {
		return error('missing Linux kernel boot marker')
	}
	expected := expected_cases()
	order := case_order()
	verdict := if mode == 'native' {
		'LINUX PIDFDWAIT: PASS'
	} else {
		'LINUX PIDFDWAIT REFERENCE: PASS'
	}
	mut seen := map[string]bool{}
	mut passed := false
	for raw in log.split_into_lines() {
		line := raw.trim_right('\r')
		if line.contains('LINUX PIDFDWAIT: PASS') || line.contains('LINUX PIDFDWAIT REFERENCE: PASS') {
			if line != verdict || passed { return error('wrong, malformed or duplicate verdict') }
			if seen.len != expected.len { return error('verdict before all case rows') }
			passed = true
			continue
		}
		if !line.contains('LINUX PIDFDWAIT CASE:') { continue }
		if passed { return error('case row after verdict') }
		fields := line.fields()
		if fields.len != 6 || fields[0] != 'LINUX' || fields[1] != 'PIDFDWAIT'
			|| fields[2] != 'CASE:' || !fields[3].starts_with('name=')
			|| !fields[4].starts_with('calls=') || !fields[5].starts_with('failures=') {
			return error('malformed case row: ' + line)
		}
		name := fields[3].all_after('=')
		if name !in expected { return error('unknown case: ' + name) }
		if name in seen { return error('duplicate case: ' + name) }
		if seen.len >= order.len || name != order[seen.len] {
			return error('wrong case order: ' + name)
		}
		calls := decimal(fields[4].all_after('='))!
		failures := decimal(fields[5].all_after('='))!
		if calls != expected[name] { return error('wrong exact call count for ' + name) }
		if failures != 0 { return error('case failures for ' + name) }
		seen[name] = true
	}
	if !passed { return error('missing verdict') }
	for name, _ in expected {
		if name !in seen { return error('missing case: ' + name) }
	}
}

fn valid_log(mode string) !string {
	expected := expected_cases()
	mut lines := []string{}
	if mode == 'reference' { lines << 'Linux version checker-self-test' }
	for name in case_order() {
		lines << 'LINUX PIDFDWAIT CASE: name=${name} calls=${expected[name]} failures=0'
	}
	lines << if mode == 'native' {
		'LINUX PIDFDWAIT: PASS'
	} else {
		'LINUX PIDFDWAIT REFERENCE: PASS'
	}
	return lines.join('\n') + '\n'
}

fn reject_control(name string, log string, mode string) ! {
	mut rejected := false
	semantics(log, mode) or { rejected = true }
	if !rejected { return error('negative control accepted: ' + name) }
}

fn self_test() ! {
	mut controls := 0
	for mode in ['native', 'reference'] {
		good := valid_log(mode)!
		semantics(good, mode)!
		verdict := if mode == 'native' {
			'LINUX PIDFDWAIT: PASS'
		} else {
			'LINUX PIDFDWAIT REFERENCE: PASS'
		}
		rows := good.split_into_lines().filter(it.starts_with('LINUX PIDFDWAIT CASE:'))
		first := rows[0]
		name := first.fields()[3].all_after('=')
		count := expected_cases()[name]
		reject_control('missing case', good.replace(first + '\n', ''), mode)!
		reject_control('changed count', good.replace(first, first.replace('calls=${count}', 'calls=${count + 1}')), mode)!
		reject_control('case failure', good.replace(first, first.replace('failures=0', 'failures=1')), mode)!
		reject_control('duplicate case', first + '\n' + good, mode)!
		reject_control('unknown case', good.replace(first, first.replace('name=${name}', 'name=unknown')), mode)!
		reject_control('late failure', good + 'LINUX PIDFDWAIT FAIL: late\n', mode)!
		reject_control('late detail', good + 'LINUX PIDFDWAIT DETAIL: late\n', mode)!
		reject_control('late case', good + first + '\n', mode)!
		reject_control('duplicate verdict', good + verdict + '\n', mode)!
		reject_control('wrong verdict mode', good, if mode == 'native' {
			'reference'
		} else {
			'native'
		})!
		reject_control('noncanonical count', good.replace(first, first.replace('calls=${count}', 'calls=0${count}')), mode)!
		reject_control('overflow count', good.replace(first, first.replace('calls=${count}', 'calls=18446744073709551616')), mode)!
		reject_control('malformed row', good.replace(first, first + ' extra=0'), mode)!
		reject_control('NUL byte', good + '\x00', mode)!
		reject_control('case order', good.replace(first + '\n' + rows[1], rows[1] + '\n' + first), mode)!
		controls += 15
	}
	println('pidfdwait checker self-test: PASS (${controls} negative controls)')
}

fn run() ! {
	args := os.args[1..]
	if args == ['--self-test'] { return self_test() }
	if args == ['--help'] || args == ['-h'] {
		println('Usage: pidfdwait-check --log PATH --mode native|reference\n       pidfdwait-check --self-test')
		return
	}
	mut options := map[string]string{}
	mut index := 0
	for index < args.len {
		key := args[index]
		if key !in ['--log', '--mode'] || key in options || index + 1 >= args.len {
			return error('expected unique --log PATH and --mode native|reference')
		}
		options[key] = args[index + 1]
		index += 2
	}
	if '--log' !in options || '--mode' !in options {
		return error('required: --log PATH --mode native|reference')
	}
	semantics(os.read_file(options['--log'])!, options['--mode'])!
	println('pidfdwait semantic log check: PASS (mode=${options['--mode']})')
}

fn main() {
	run() or {
		eprintln('pidfdwait check: ' + err.msg())
		exit(1)
	}
}
