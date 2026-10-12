// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import sourcecommand
import time

fn C.getpgid(int) int
fn C.kill(int, int) int

fn qualify(work string) ! {
	os.mkdir(work)!
	before := os.ls('/dev/fd')!.len
	mut child := sourcecommand.spawn_pty(['/bin/sh', '-c', 'printf "PTY-PART"; sleep 0.05; printf "IAL\n"; printf "%s\n" "$MARKER"; exit 7'], {'PATH': '/usr/bin:/bin', 'MARKER': 'explicit environment'}, work)!
	assert C.getpgid(child.pid) == child.pid
	mut buffer := []u8{len: 3}
	mut text := ''
	for {
		count := child.read(mut buffer, 100)!
		if count == 0 { break }
		if count > 0 { text += buffer[..count].bytestr() }
	}
	assert text.replace('\r', '') == 'PTY-PARTIAL\nexplicit environment\n'
	assert child.settle(1)!
	assert child.poll()!.return_code == 7
	assert child.poll()!.return_code == 7, 'observation unexpectedly released the PID'
	child.close()!
	child.close()!
	assert C.kill(child.pid, 0) != 0
	mut command := sourcecommand.spawn_pty(['/bin/sh', '-c', 'sleep 30 & printf "%s\n" "$!"; wait'], os.environ(), work)!
	mut pid_text := ''
	mut large := []u8{len: 128}
	for !pid_text.contains('\n') {
		count := command.read(mut large, 1000)!
		if count > 0 { pid_text += large[..count].bytestr() }
	}
	descendant := pid_text.trim_space().int()
	assert descendant > 0 && C.getpgid(descendant) == command.pid
	command.close()!
	deadline := time.sys_mono_now() + time.second
	for C.kill(descendant, 0) == 0 && time.sys_mono_now() < deadline { time.sleep(10 * time.millisecond) }
	assert C.kill(descendant, 0) != 0, 'private descendant survived retirement'
	mut input := sourcecommand.spawn_pty(['/bin/sh', '-c', 'read answer; printf "ACK=%s\n" "$answer"'], os.environ(), work)!
	input.write('owned input\n'.bytes())!
	mut observed := ''
	for {
		count := input.read(mut large, 1000)!
		if count == 0 { break }
		if count > 0 { observed += large[..count].bytestr() }
	}
	assert observed.contains('ACK=owned input')
	input.close()!
	mut failed := sourcecommand.spawn_pty(['/missing-vinix-pty-command'], os.environ(), work)!
	assert failed.settle(1)! && failed.poll()!.return_code == 127
	failed.close()!
	mut signalled := sourcecommand.spawn_pty(['/bin/sh', '-c', 'kill -TERM $$'], os.environ(), work)!
	assert signalled.settle(1)! && signalled.poll()!.return_code == -15
	signalled.close()!
	for _ in 0 .. 100 {
		mut owner := sourcecommand.spawn_pty(['/usr/bin/true'], os.environ(), work)!
		assert owner.settle(1)!
		assert owner.poll()!.exited
		owner.close()!
	}
	assert os.ls('/dev/fd')!.len == before
	os.write_file(work + '/passed', 'PASS\n')!
	println('SDK PTY OWNER / actual split serial and explicit environment / private process group / signed exit and repeated unreaped observation / descendant retirement / input echo / exec failure / 100 owners and flat descriptors: PASS')
}

fn main() {
	if os.args.len != 2 { eprintln('usage: test-source-pty NEW_STATE'); exit(2) }
	qualify(os.args[1]) or { eprintln(err); exit(1) }
}
