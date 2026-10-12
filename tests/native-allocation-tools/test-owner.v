// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import sourcecommand
import time

#include <signal.h>
#include <fcntl.h>
#include <unistd.h>

fn C.kill(i32, i32) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...int) i32

struct Context {
	work string
	fail bool
}

fn observed(pid int, pointer voidptr) ! {
	context := unsafe { &Context(pointer) }
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for !sourcecommand.child_exited(pid)! {
		if context.fail && os.exists(context.work + '/ready') { return error('observer failure') }
		if time.sys_mono_now() >= deadline { return error('owner fixture timeout') }
		time.sleep(10 * time.millisecond)
	}
}

fn cancelled() bool { return true }

fn ready(pid int, pointer voidptr) ! {
	context := unsafe { &Context(pointer) }
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for !os.exists(context.work + '/ready') {
		if sourcecommand.child_exited(pid)! || time.sys_mono_now() >= deadline {
			return error('owner fixture did not become ready')
		}
		time.sleep(10 * time.millisecond)
	}
}

fn retired(work string) ! {
	ids := os.read_file(work + '/pids')!.split_into_lines().map(it.int())
	deadline := time.sys_mono_now() + u64(5 * time.second)
	for ids.any(C.kill(it, 0) == 0) && time.sys_mono_now() < deadline {
		time.sleep(10 * time.millisecond)
	}
	assert ids.all(C.kill(it, 0) != 0), 'log owner retained a descendant'
}

fn child(mode string, work string) ! {
	if mode == 'write' {
		println(os.getwd())
		print('o'.repeat(200000))
		flush_stdout()
		eprint('e'.repeat(200000))
		flush_stderr()
		return
	}
	mut descendant := os.new_process('/bin/sleep')
	descendant.set_args(['600'])
	descendant.run()
	os.write_file(work + '/pids', os.getpid().str() + '\n' + descendant.pid.str() + '\n')!
	println('partial log')
	flush_stdout()
	os.write_file(work + '/ready', 'ready')!
	if mode == 'exit' { exit(7) }
	for { time.sleep(20 * time.millisecond) }
}

fn descriptors() int {
	mut count := 0
	for fd in 0 .. 4096 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn cases(input string) ! {
	os.mkdir(input)!
	work := os.real_path(input)
	context := Context{work, false}
	log := work + '/output'
	for append in [false, true] {
		result := sourcecommand.run_logged_owned([os.executable(), '--child', 'write', work], os.environ(), unsafe { nil }, log, append, work, observed, unsafe { &context }, 0)!
		assert result.status == 0 && result.stdout == '' && result.stderr == ''
		assert os.read_file(log)! == (work + '\n' + 'o'.repeat(200000) + 'e'.repeat(200000)).repeat(if append {
			2
		} else {
			1
		})
	}
	before := descriptors()
	for index in 0 .. 100 {
		result := sourcecommand.run_logged_owned(['/usr/bin/true'], os.environ(), unsafe { nil }, log, index > 0, work, observed, unsafe { &context }, 0)!
		assert result.status == 0
		assert descriptors() == before
	}
	for mode in ['exit', 'observer', 'cancel'] {
		state := work + '/' + mode
		os.mkdir(state)!
		data := Context{state, mode == 'observer'}
		if mode == 'exit' {
			result := sourcecommand.run_logged_owned([os.executable(), '--child', 'exit', state], os.environ(), unsafe { nil }, state + '/log', false, '', observed, unsafe { &data }, 0)!
			assert result.status == 7
		} else {
			sourcecommand.run_logged_owned([os.executable(), '--child', 'block', state], os.environ(), if mode == 'cancel' {
				cancelled
			} else {
				unsafe { nil }
			}, state + '/log', false, '', if mode == 'cancel' { ready } else { observed }, unsafe { &data }, 0) or {
				assert err.msg() == if mode == 'cancel' {
					'command interrupted'
				} else {
					'observer failure'
				}
				retired(state)!
				assert os.read_file(state + '/log')! == 'partial log\n'
				continue
			}
			return error('owner failure was swallowed')
		}
		retired(state)!
	}
	for command in [['/does-not-exist'], ['/usr/bin/true']] {
		sourcecommand.run_logged_owned(command, os.environ(), unsafe { nil }, log, false, if command[0] == '/usr/bin/true' {
			'/does-not-exist'
		} else {
			''
		}, observed, unsafe { &context }, 0) or {
			assert descriptors() == before
			continue
		}
		return error('spawn failure was swallowed')
	}
	result := sourcecommand.capture([os.executable(), '--closed', work], os.environ(), 30, 1024, unsafe { nil })!
	assert result.status == 0, result.str()
	assert os.read_file(work + '/closed.log')!.starts_with(work + '\n')
	println('LOG OWNER / ordered large streams / append / cwd / failures / closed stdio / 100 flat descriptor runs / exited leader descendants: PASS')
}

fn main() {
	if os.args.len == 4 && os.args[1] == '--child' {
		child(os.args[2], os.args[3]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 3 && os.args[1] == '--closed' {
		work := os.args[2]
		context := Context{work, false}
		for fd in [0, 1, 2] { C.close(fd) }
		result := sourcecommand.run_logged_owned([os.executable(), '--child', 'write', work], os.environ(), unsafe { nil }, work + '/closed.log', false, work, observed, unsafe { &context }, 0) or { exit(1) }
		exit(if result.status == 0 { 0 } else { 1 })
	}
	if os.args.len != 2 {
		eprintln('usage: test-owner NEW_STATE')
		exit(2)
	}
	cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
