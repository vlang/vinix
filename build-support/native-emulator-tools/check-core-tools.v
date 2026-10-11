// SPDX-License-Identifier: MIT
module main

import emulatorbuild
import hosttest
import json2
import os
import policyhost
import time

#include <signal.h>
#include <unistd.h>
#include <errno.h>
fn C.kill(i32, i32) i32
fn C.fork() i32
fn C.write(i32, voidptr, usize) isize
fn C.getpid() i32

fn raw(fd i32, text string) {
	unsafe { assert C.write(fd, text.str, usize(text.len)) == text.len }
}

fn task(work string, index int, mode string) emulatorbuild.CoreTask {
	path := work + '/input-' + index.str()
	return emulatorbuild.CoreTask{
		path: path
		target: work + '/input-' + index.str() + '.o'
		command: [os.executable(), '--leaf', work, index.str(), mode]
		stamp: 'stamp-' + index.str()
		directory: work
	}
}

fn leaf(work string, index int, mode string) {
	os.write_file(work + '/pid-' + index.str(), C.getpid().str()) or { exit(99) }
	if mode == 'sleep' {
		child := C.fork()
		if child == 0 {
			os.write_file(work + '/grandchild-' + index.str(), C.getpid().str()) or { exit(99) }
			time.sleep(30 * time.second)
			exit(0)
		}
		if child < 0 { exit(99) }
		time.sleep(30 * time.second)
		exit(0)
	}
	time.sleep((4 - index % 4) * 5 * time.millisecond)
	raw(1, 'output-' + index.str() + '\x00\xff\n')
	raw(2, 'error-' + index.str() + '\n')
	os.write_file(work + '/input-' + index.str() + '.o', 'object-' + index.str()) or { exit(99) }
	if mode == 'fail' { exit(7) }
	exit(0)
}

fn delayed_interrupt(work string, pid i32) ! {
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for !os.exists(work + '/grandchild-3') {
		if time.sys_mono_now() > deadline { return error('Parallel workers did not start') }
		time.sleep(10 * time.millisecond)
	}
	assert C.kill(pid, C.SIGINT) == 0
}

fn child_pool(work string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	mut tasks := []emulatorbuild.CoreTask{}
	for index in 0 .. 16 { tasks << task(work, index, 'sleep') }
	emulatorbuild.core_pool(tasks, 4, work + '/interrupt.log') or {
		return if err.msg() == 'Host test interrupted' { 130 } else { 1 }
	}
	return 0
}

fn descriptor_count() int {
	return (os.ls('/dev/fd') or { os.ls('/proc/self/fd') or { []string{} } }).len
}

fn check() ! {
	guard := policyhost.own_commands()
	defer { guard.close() }
	work := hosttest.work_dir('', 'vinix-core-check-')!
	defer { hosttest.remove_work_dir(work) or {} }
	assert emulatorbuild.diagnostic_text('\xe2\x82A\xff\xed\xa0\x80\xf4\x90\x80\x80') == '�A' + '�'.repeat(8)
	assert emulatorbuild.diagnostic_text('Vél🚀') == 'Vél🚀'
	assert emulatorbuild.cache_json(json2.Any([json2.Any('a'), json2.Any('é')])) == '["a", "\\u00e9"]'
	assert emulatorbuild.core_flags({'C_FLAGS': '-MMD -DA="quoted value" -DGIT_VERSION=old -I./src'}, false)! == ['-DA=quoted value', '-I./src']
	baseline := descriptor_count()
	for round in 0 .. 12 {
		mut tasks := []emulatorbuild.CoreTask{}
		for index in 0 .. 32 { tasks << task(work, index, 'ok') }
		if round > 0 {
			for index in 0 .. 32 { os.rm(work + '/input-' + index.str() + '.stamp')! }
		}
		objects := emulatorbuild.core_pool(tasks, 8, work + '/pool.log')!
		assert objects == tasks.map(it.target)
		mut expected := ''
		for index in 0 .. 32 { expected += 'output-' + index.str() + '\x00\xff\nerror-' + index.str() + '\n' }
		assert os.read_file(work + '/pool.log')! == expected
		assert descriptor_count() == baseline
		if round == 0 {
			emulatorbuild.core_pool(tasks, 8, work + '/cache.log')!
			assert os.file_size(work + '/cache.log') == 0
		}
	}
	println('PASS 384 compiler children, ordered binary logs, cache hits and descriptor retirement')
	mut failures := []emulatorbuild.CoreTask{}
	for index in 0 .. 4 {
		os.rm(work + '/input-' + index.str() + '.stamp')!
		failures << task(work, index, if index in [1, 2] { 'fail' } else { 'ok' })
	}
	mut failed := false
	emulatorbuild.core_pool(failures, 4, work + '/failed.log') or {
		failed = true
		assert err.msg() == 'compile failed: ' + work + '/input-1\noutput-1\x00�\nerror-1\n'
		assert os.read_file(work + '/failed.log')! == err.msg()
		assert descriptor_count() == baseline
		assert os.exists(work + '/input-3.stamp')
		assert !os.exists(work + '/input-1.stamp')
		println('PASS first input-order error, UTF-8 replacement and joined failure workers')
	}
	assert failed
	interrupt_work := work + '/interrupt'
	os.mkdir(interrupt_work)!
	os.write_file(interrupt_work + '/interrupt.log', 'retained')!
	mut child := os.new_process(os.executable())
	child.set_args(['--pool-child', interrupt_work])
	child.set_environment(policyhost.environment())
	child.set_redirect_stdio()
	child.run()
	mut closed := false
	defer { if !closed { child.close() } }
	mut interrupter := spawn delayed_interrupt(interrupt_work, child.pid)
	child.wait()
	interrupter.wait()!
	assert child.code == 130
	child.close()
	closed = true
	assert os.read_file(interrupt_work + '/interrupt.log')! == 'retained'
	for name in os.ls(interrupt_work)! {
		if !name.starts_with('pid-') && !name.starts_with('grandchild-') { continue }
		pid := os.read_file(interrupt_work + '/' + name)!.int()
		deadline := time.sys_mono_now() + u64(3 * time.second)
		for C.kill(pid, 0) == 0 && time.sys_mono_now() < deadline { time.sleep(10 * time.millisecond) }
		assert C.kill(pid, 0) == -1 && C.errno == C.ESRCH
	}
	assert descriptor_count() == baseline
	println('PASS SIGINT joins every worker and retires compiler children and descendants')
}

fn main() {
	if os.args.len > 1 && os.args[1] == '--leaf' { leaf(os.args[2], os.args[3].int(), os.args[4]) }
	if os.args.len > 1 && os.args[1] == '--pool-child' { exit(child_pool(os.args[2])) }
	check() or { eprintln(err.msg()); exit(1) }
}
