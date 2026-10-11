// SPDX-License-Identifier: BSD-2-Clause
@[has_globals]
module main

import evidencearchive as archive
import os
import reportfixture as fixture
import time

#include <fcntl.h>
#include <signal.h>
#include <errno.h>

fn C.kill(i32, i32) i32
fn C.killpg(i32, i32) i32

fn descriptors() []int {
	mut result := []int{}
	for fd in 0 .. 1024 { if C.fcntl(fd, C.F_GETFD) >= 0 { result << fd } }
	return result
}

fn await_file(path string) !int {
	deadline := time.now().unix_milli() + 10000
	for !os.exists(path) {
		if time.now().unix_milli() > deadline { return error('Owned Git fixture did not start') }
		time.sleep(10 * time.millisecond)
	}
	pid := os.read_file(path)!.trim_space().int()
	if pid <= 0 { return error('Invalid owned Git PID receipt') }
	return pid
}

fn gone(pid int) ! {
	deadline := time.now().unix_milli() + 5000
	for C.kill(pid, 0) == 0 || C.errno != C.ESRCH {
		if time.now().unix_milli() > deadline { return error('Owned Git PID remains: ${pid}') }
		time.sleep(10 * time.millisecond)
	}
}

fn read_owned(root string) ! {
	guard := archive.own_commands()
	defer { guard.close() }
	mut reader := archive.reader(root)!
	defer { reader.close() }
	reader.read('a'.repeat(40))!
}

fn failed_read(root string) ! {
	mut reader := archive.reader(root)!
	defer { reader.close() }
	mut rejected := false
	reader.read('a'.repeat(40)) or { rejected = true }
	if !rejected { return error('Malformed owned Git reply accepted') }
}

fn standin() ! {
	mode := os.getenv('VINIX_REPORT_OWNER_MODE')
	receipt := os.getenv('VINIX_REPORT_OWNER_RECEIPT')
	if mode in ['hang', 'orphan'] {
		os.write_file(receipt + '.git', os.getpid().str())!
		mut child := os.new_process(os.executable())
		child.set_args(['--descendant'])
		child.run()
		assert child.pid > 0
		await_file(receipt + '.child')!
		if mode == 'orphan' {
			print('malformed\n')
			return
		}
		for { time.sleep(10 * time.millisecond) }
	}
	print('malformed\n')
}

fn qualification(root string) ! {
	guard := archive.own_commands()
	defer { guard.close() }
	temp := fixture.temporary('vinix-evidence-owner-')!
	defer { os.rmdir_all(temp) or {} }
	os.symlink(os.executable(), temp + '/git')!
	previous := os.environ()
	defer {
		for key in ['PATH', 'VINIX_REPORT_OWNER_MODE', 'VINIX_REPORT_OWNER_RECEIPT'] {
			if key in previous { os.setenv(key, previous[key], true) } else { os.unsetenv(key) }
		}
	}
	os.setenv('PATH', temp + ':' + os.getenv('PATH'), true)
	os.setenv('VINIX_REPORT_OWNER_MODE', 'broken', true)
	failed_read(root)!
	before := descriptors()
	for _ in 0 .. 100 { failed_read(root)! }
	assert descriptors() == before, 'Git reader descriptors accumulate after failure'
	println('100 failed Git reads: descriptors stay flat')
	for signal in [2, 15] {
		receipt := temp + '/signal-${signal}'
		os.setenv('VINIX_REPORT_OWNER_MODE', 'hang', true)
		os.setenv('VINIX_REPORT_OWNER_RECEIPT', receipt, true)
		mut owner := os.new_process(os.executable())
		owner.set_args(['--owned-read'])
		owner.use_pgroup = true
		owner.run()
		defer {
			owner.signal_pgkill()
			owner.signal_kill()
			owner.wait()
			owner.close()
		}
		git_pid := await_file(receipt + '.git')!
		child_pid := await_file(receipt + '.child')!
		mut active := true
		defer { if active {
			C.killpg(git_pid, C.SIGKILL)
			C.kill(child_pid, C.SIGKILL)
		} }
		assert C.kill(owner.pid, signal) == 0
		deadline := time.now().unix_milli() + 10000
		for owner.is_alive() {
			if time.now().unix_milli() > deadline {
				return error('Owned reader did not handle signal')
			}
			time.sleep(10 * time.millisecond)
		}
		assert owner.code == 128 + signal, 'Owned reader returned the wrong interrupt status'
		gone(git_pid)!
		gone(child_pid)!
		active = false
		println('SIGNAL ${signal}: owner status ${owner.code}, Git and descendant reaped/retired')
	}
	// A leader may exit with a malformed reply while its child retains the
	// pipes. The group still belongs to the reader until retirement completes.
	receipt := temp + '/orphan'
	os.setenv('VINIX_REPORT_OWNER_MODE', 'orphan', true)
	os.setenv('VINIX_REPORT_OWNER_RECEIPT', receipt, true)
	failed_read(root)!
	git_pid := await_file(receipt + '.git')!
	child_pid := await_file(receipt + '.child')!
	mut active := true
	defer { if active {
		C.killpg(git_pid, C.SIGKILL)
		C.kill(child_pid, C.SIGKILL)
	} }
	gone(git_pid)!
	gone(child_pid)!
	active = false
	assert descriptors() == before, 'Signal/EOF cleanup leaked descriptors'
	println('Exited Git leader and surviving descendant retirement PASS')
}

fn main() {
	if os.args.len > 1 && os.args[1] == '--descendant' {
		os.write_file(os.getenv('VINIX_REPORT_OWNER_RECEIPT') + '.child', os.getpid().str())!
		for { time.sleep(10 * time.millisecond) }
	}
	if os.args.len > 1 && os.args[1] == 'cat-file' {
		standin()!
		return
	}
	root := os.real_path(os.dir(@FILE) + '/../..')
	if os.args.len > 1 && os.args[1] == '--owned-read' {
		read_owned(root) or {
			eprintln(err)
			exit(if err.code() in [130, 143] { err.code() } else { 1 })
		}
		return
	}
	qualification(root)!
	println('Owned evidence reader qualification PASS')
}
