// SPDX-License-Identifier: GPL-2.0-or-later
module launcherfixtures

import cachecli
import gamehost
import os
import sourcecommand
import tarcore
import tarstream
import time

fn C.fork() i32
fn C.kill(i32, i32) i32

pub fn reader_mock() !bool {
	if os.args.len == 3 && os.args[1] in ['closed-stdio', 'cancel-reader'] {
		work := os.args[2]
		guard := cachecli.own_commands()
		defer { guard.close() }
		if os.args[1] == 'closed-stdio' {
			for fd in 0 .. 3 { C.close(fd) }
		}
		mut child := sourcecommand.spawn_reader([work + '/mock-reader',
			if os.args[1] == 'cancel-reader' { 'hang' } else { 'complete' }, work], os.environ())!
		pid := child.pid
		if os.args[1] == 'cancel-reader' {
			mut reader := tarstream.from_descriptor_cancelled(child.descriptor, cachecli.cancelled)!
			reader.next() or {
				assert cachecli.cancelled()
				reader.close()
				child.close()!
				assert C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH
				os.write_file(work + '/cancel-passed', 'PASS\n')!
				exit(cachecli.interrupt_status())
			}
			return error('hanging reader unexpectedly returned')
		}
		mut buffer := []u8{len: 65536}
		mut count := 0
		for {
			n := C.read(child.descriptor, buffer.data, usize(buffer.len))
			if n > 0 {
				count += int(n)
			} else if n == 0 {
				break
			} else {
				assert C.errno in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR]
				time.sleep(time.millisecond)
			}
		}
		child.close()!
		assert count == int(os.file_size(work + '/input.tar'))
		assert C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH
		os.write_file(work + '/stdio-passed', 'PASS\n')!
		return true
	}
	if os.args.len != 3 || !os.executable().ends_with('/mock-reader') { return false }
	mode := os.args[1]
	work := os.args[2]
	os.write_file(work + '/child.pid', os.getpid().str())!
	if mode == 'descendant' {
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			os.write_file(work + '/descendant.pid', os.getpid().str())!
			for { time.sleep(10 * time.millisecond) }
		}
		for !os.exists(work + '/descendant.pid') { time.sleep(time.millisecond) }
	}
	if mode == 'hang' {
		for { time.sleep(10 * time.millisecond) }
	}
	bytes := os.read_bytes(work + '/input.tar')!
	mut stdout := os.stdout()
	unsafe { stdout.write_full_buffer(bytes.data, usize(bytes.len))! }
	stdout.flush()
	exit(if mode == 'failure' { 7 } else { 0 })
	return true
}

pub fn reader_cases(work string) ! {
	gamehost.mkdir(work)!
	path := work + '/mock-reader'
	os.cp(os.executable(), path)!
	os.chmod(path, 0o755)!
	mut writer := tarcore.create(work + '/input.tar')!
	data := 'owned decoder payload'.repeat(60000).bytes()
	writer.add(tarcore.Member{ name: 'large', size: data.len }, data)!
	writer.finish()!
	writer.close()
	baseline := os.ls('/dev/fd')!.len
	for mode in ['complete', 'failure', 'descendant', 'hang'] {
		os.rm(work + '/child.pid') or {}
		mut child := sourcecommand.spawn_reader([path, mode, work], os.environ())!
		mut buffer := []u8{len: 65536}
		mut count := 0
		deadline := time.sys_mono_now() + 5 * time.second
		for time.sys_mono_now() < deadline {
			if mode == 'hang' && os.exists(work + '/child.pid') { break }
			n := C.read(child.descriptor, buffer.data, usize(buffer.len))
			if n > 0 {
				count += int(n)
			} else if n == 0 {
				break
			} else {
				assert C.errno in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR]
				time.sleep(time.millisecond)
			}
		}
		if mode != 'hang' {
			assert count == int(os.file_size(work + '/input.tar'))
		}
		pid := child.pid
		child.close()!
		child.close()!
		assert C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH
		if mode == 'descendant' {
			descendant := os.read_file(work + '/descendant.pid')!.int()
			until := time.sys_mono_now() + 5 * time.second
			for C.kill(i32(descendant), 0) == 0 && time.sys_mono_now() < until {
				time.sleep(10 * time.millisecond)
			}
			assert C.kill(i32(descendant), 0) != 0 && C.errno == C.ESRCH
		}
		assert os.ls('/dev/fd')!.len == baseline
	}
	for _ in 0 .. 100 {
		sourcecommand.spawn_reader([work + '/missing-reader'], os.environ()) or {
			assert os.ls('/dev/fd')!.len == baseline
			continue
		}
		return error('missing decoder unexpectedly started')
	}
	mut closed := sourcecommand.spawn_reader([os.executable(), 'closed-stdio', work], os.environ())!
	deadline := time.sys_mono_now() + 10 * time.second
	for !closed.poll()!.exited && time.sys_mono_now() < deadline {
		time.sleep(10 * time.millisecond)
	}
	assert closed.poll()!.exited
	closed.close()!
	assert os.read_file(work + '/stdio-passed')! == 'PASS\n'
	for signal in [C.SIGINT, C.SIGTERM] {
		os.rm(work + '/child.pid')!
		os.rm(work + '/cancel-passed') or {}
		mut controller := sourcecommand.spawn_reader([os.executable(), 'cancel-reader', work], os.environ())!
		until := time.sys_mono_now() + 10 * time.second
		for !os.exists(work + '/child.pid') && time.sys_mono_now() < until {
			time.sleep(10 * time.millisecond)
		}
		assert os.exists(work + '/child.pid')
		assert C.kill(i32(controller.pid), signal) == 0
		for !controller.poll()!.exited && time.sys_mono_now() < until {
			time.sleep(10 * time.millisecond)
		}
		assert controller.poll()!.exited
		controller.close()!
		assert os.read_file(work + '/cancel-passed')! == 'PASS\n'
		assert os.ls('/dev/fd')!.len == baseline
	}
	println('PASS closed standard descriptors and interrupted blocking reads: SIGINT/SIGTERM retire the exact decoder PID')
	println('PASS streamed decoder bytes, nonzero exit, hanging child, descendant group, 100 failed spawns and exact PID/descriptor retirement')
}
