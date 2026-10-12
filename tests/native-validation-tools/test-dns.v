// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import gamehost
import net
import os
import time
import guestvalidation

struct DnsFixture {
	mode string
mut:
	calls  []string
	sleeps int
}

fn answer(server string, port int, timeout f64, pointer voidptr) bool {
	mut f := unsafe { &DnsFixture(pointer) }
	assert port == 53
	assert timeout == if server == '10.0.2.3' { 2 } else { 1 }
	f.calls << server
	return match f.mode {
		'unavailable' { false }
		'proxy-good' { true }
		else { server == '8.8.8.8' }
	}
}

fn dns_fixture_pause(seconds f64, pointer voidptr) ! {
	mut f := unsafe { &DnsFixture(pointer) }
	assert seconds == 1
	f.sleeps++
}

fn dns_cases(work string) ! {
	path := work + '/resolv.conf'
	for mode in ['unavailable', 'proxy-good', 'replace'] {
		original := '# retain this comment\r\n\u2003nameserver\u200310.0.2.3\r\nsearch local\n nameserver 10.0.2.3 # keep commented variant\n'
		os.write_file(path, original)!
		mut f := DnsFixture{ mode: mode }
		assert guestvalidation.update_dns(path, guestvalidation.DnsTools{ answer: answer, sleep: dns_fixture_pause, context: &f })! == 0
		if mode == 'replace' {
			assert f.calls == ['1.1.1.1', '8.8.8.8', '10.0.2.3'] && f.sleeps == 0
			assert os.read_file(path)! == '# retain this comment\nsearch local\n nameserver 10.0.2.3 # keep commented variant\nnameserver 1.1.1.1\nnameserver 8.8.8.8\n'
		} else {
			assert os.read_file(path)! == original
			if mode == 'unavailable' {
				assert f.calls.len == 30 && f.sleeps == 15
			} else {
				assert f.calls == ['1.1.1.1', '10.0.2.3']
			}
		}
	}
	os.write_file(path, 'nameserver 192.168.1.1\n')!
	mut f := DnsFixture{ mode: 'replace' }
	assert guestvalidation.update_dns(path, guestvalidation.DnsTools{ answer: answer, sleep: dns_fixture_pause, context: &f })! == 0 && f.calls.len == 0
	assert guestvalidation.update_dns(work + '/absent', guestvalidation.DnsTools{})! == 0
	os.write_file(path, 'nameserver 10.0.2.3\n')!
	gamehost.mkdir(path + '.steam-tmp')!
	assert guestvalidation.update_dns(path, guestvalidation.DnsTools{ answer: answer, sleep: dns_fixture_pause, context: &f })! == 1
	assert os.read_file(path)! == 'nameserver 10.0.2.3\n'
	if os.is_dir(path + '.steam-tmp') { os.rmdir(path + '.steam-tmp')! }
	mut valid := guestvalidation.dns_query.bytes()
	valid[2] |= 0x80
	assert guestvalidation.dns_reply(valid)
	assert !guestvalidation.dns_reply(valid[..11]) && !guestvalidation.dns_reply(guestvalidation.dns_query.bytes())
	valid[0] ^= 1
	assert !guestvalidation.dns_reply(valid)
}

fn reply(mut listener net.UdpConn) ! {
	mut buffer := []u8{len: 512}
	count, address := listener.read(mut buffer)!
	assert buffer[..count] == guestvalidation.dns_query.bytes()
	mut bytes := buffer[..count].clone()
	bytes[2] |= 0x80
	listener.write_to(address, bytes)!
}

fn socket_cases() ! {
	mut listener := net.listen_udp('127.0.0.1:0')!
	listener.set_read_timeout(time.second)
	port := listener.sock.address()!.port()!
	task := spawn reply(mut listener)
	assert guestvalidation.dns_answers('127.0.0.1', int(port), 1)
	task.wait()!
	listener.close()!
	before := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		assert !guestvalidation.dns_answers('127.0.0.1', int(port), 0.001)
	}
	assert os.ls('/dev/fd')!.len == before
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	work := os.args[1]
	gamehost.mkdir(work) or { panic(err) }
	dns_cases(work) or {
		eprintln(err)
		exit(1)
	}
	socket_cases() or {
		eprintln(err)
		exit(1)
	}
	os.write_file(work + '/passed', 'PASS\n') or { panic(err) }
	println('NATIVE DNS / exact proxy admission, Unicode/newlines/comments, ordered 15 retry policy, replacement failure, real UDP query and 100 closed-port FD controls: PASS')
}
