// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import hosttest
import net
import os
import policyhost
import systemhost
import time

#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

fn C.fcntl(i32, i32, ...int) i32
fn C.kill(i32, i32) i32
fn C.getppid() i32
fn C.recvfrom(i32, voidptr, usize, i32, voidptr, &u32) i32

fn put(mut bytes []u8, at int, value u32, size int) {
	for index in 0 .. size { bytes[at + index] = u8(value >> u32((size - index - 1) * 8)) }
}

fn ipv4(sequence int, udp bool) []u8 {
	mut bytes := []u8{len: 54}
	for at, byte in [u8(0x52), 0x54, 0, 0x12, 0x34, 0x56] { bytes[6 + at] = byte }
	bytes[12], bytes[13], bytes[14] = 8, 0, 0x45
	put(mut bytes, 18, u32(sequence * 2107 + 13), 2)
	bytes[23] = if udp { 17 } else { 6 }
	bytes[30], bytes[31], bytes[32], bytes[33] = 10, 0, 2, 2
	put(mut bytes, 34, u32(55000 + sequence * 197), 2)
	put(mut bytes, 36, 9, 2)
	put(mut bytes, 38, u32(sequence) * 0x10000001 + 19, 4)
	bytes[47] = 2
	return bytes
}

fn ipv6(kind u8, incoming bool, extension bool) []u8 {
	mut bytes := []u8{len: if extension { 63 } else { 55 }}
	if !incoming {
		for at, byte in [u8(0x52), 0x54, 0, 0x12, 0x34, 0x56] { bytes[6 + at] = byte }
	}
	bytes[12], bytes[13] = 0x86, 0xdd
	bytes[20] = if extension {
		0
	} else if kind in [u8(6), 17] {
		kind
	} else {
		58
	}
	if extension { bytes[54] = 58 }
	bytes[if extension { 62 } else { 54 }] = kind
	return bytes
}

fn ipv6_frames() [][]u8 {
	mut result := [][]u8{}
	for kind in [u8(133), 135, 131] { result << ipv6(kind, false, kind == 131) }
	for kind in [u8(134), 136] { result << ipv6(kind, true, false) }
	result << ipv6(6, false, false)
	result << ipv6(17, false, false)
	mut igmp := ipv4(0, true)
	igmp[23] = 2
	result << igmp
	return result
}

fn write_pcap(path string, frames [][]u8, little bool, nano bool) ! {
	mut bytes := []u8{len: 24}
	magic := if nano { u32(0xa1b23c4d) } else { u32(0xa1b2c3d4) }
	put(mut bytes, 0, magic, 4)
	if little {
		first := bytes[..4].clone()
		for index in 0 .. 4 { bytes[index] = first[3 - index] }
	}
	for frame in frames {
		mut record := []u8{len: 16}
		put(mut record, 8, u32(frame.len), 4)
		if little {
			first := record[8..12].clone()
			for index in 0 .. 4 { record[8 + index] = first[3 - index] }
		}
		bytes << record
		bytes << frame
	}
	os.write_file_array(path, bytes)!
}

fn descriptors() int {
	mut count := 0
	for fd in 0 .. 4096 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn packet_checks(work string) ! {
	mut frames := [][]u8{}
	for index in 0 .. 8 {
		frames << ipv4(index, false)
		frames << ipv4(index + 8, true)
	}
	assert systemhost.security_packets(frames).len == 0
	for little in [true, false] {
		for nano in [true, false] {
			path := work + '/capture'
			write_pcap(path, frames, little, nano)!
			assert systemhost.capture_frames(path)! == frames
			bytes := os.read_bytes(path)!
			os.write_file_array(path, bytes[..bytes.len - 7])!
			parsed := systemhost.capture_frames(path)!
			assert parsed.len == 16 && parsed.last().len == frames.last().len - 7
		}
	}
	assert systemhost.close_pairs([u32(65535), 0, 1, 1], 65536, 1) == 2
	// Included lengths are unsigned 32-bit values; even malformed lengths above
	// INT_MAX retain the original permissive truncation rather than wrapping.
	for included in [u32(0x80000000), 0xffffffff] {
		mut malformed := []u8{len: 43}
		put(mut malformed, 0, 0xa1b2c3d4, 4)
		put(mut malformed, 32, included, 4)
		malformed[40], malformed[41], malformed[42] = 1, 2, 3
		os.write_file_array(work + '/wide-length', malformed)!
		assert systemhost.capture_frames(work + '/wide-length')! == [[u8(1), 2, 3]]
	}
	assert systemhost.security_packets(frames[..15])[0].contains('only 15 packets')
	for category in ['ids', 'ports', 'isns'] {
		mut damaged := [][]u8{}
		for index, frame in frames {
			mut row := frame.clone()
			if category == 'ids' { put(mut row, 18, u32(index), 2) }
			if category == 'ports' { put(mut row, 34, u32(1000 + index), 2) }
			if category == 'isns' { put(mut row, 38, u32(index), 4) }
			damaged << row
		}
		assert systemhost.security_packets(damaged).len > 0
	}
	assert systemhost.ipv6_packets(ipv6_frames()).len == 0
	for index in 0 .. ipv6_frames().len {
		mut incomplete := ipv6_frames()
		incomplete.delete(index)
		assert systemhost.ipv6_packets(incomplete).len > 0
	}
	println('PASS all pcap byte orders, truncation, original randomness thresholds and IPv6 packet requirements')
}

fn echo_checks() ! {
	before := descriptors()
	for _ in 0 .. 4 {
		mut echo := systemhost.start_echo('[::1]:0')!
		mut tcp := net.dial_tcp(echo.address)!
		tcp.set_read_timeout(time.second)
		tcp.write('tcp\x00\xff'.bytes())!
		mut data := []u8{len: 32}
		n := tcp.read(mut data)!
		assert data[..n].bytestr() == 'tcp\x00\xff'
		tcp.close()!
		mut udp := net.dial_udp(echo.address)!
		udp.set_read_timeout(time.second)
		udp.write('udp\x00\xff'.bytes())!
		size, _ := udp.read(mut data)!
		assert data[..size].bytestr() == 'udp\x00\xff'
		udp.write([]u8{})!
		udp.wait_for_read()!
		mut peer := net.new_ip6(0, [16]u8{})
		mut peer_size := u32(sizeof(net.Addr))
		assert C.recvfrom(udp.sock.handle, data.data, usize(data.len), 0, &peer, &peer_size) == 0
		udp.close()!
		mut delayed := net.dial_tcp(echo.address)!
		delayed.set_read_timeout(time.second)
		time.sleep(250 * time.millisecond)
		delayed.write('after checkpoints'.bytes())!
		late := delayed.read(mut data)!
		assert data[..late].bytestr() == 'after checkpoints'
		delayed.close()!
		// A peer that never writes cannot keep the thread or listener alive.
		mut silent := net.dial_tcp(echo.address)!
		started := time.sys_mono_now()
		echo.close()
		assert time.sys_mono_now() - started < i64(time.second)
		silent.close()!
		assert descriptors() == before
	}
	println('PASS binary IPv6 TCP/UDP echo, silent peer retirement and repeated FD closure')
}

fn child(mode string) {
	if mode == 'interrupt' {
		C.kill(C.getppid(), C.SIGINT)
		for { time.sleep(20 * time.millisecond) }
	}
	if mode == 'idle' {
		for { time.sleep(20 * time.millisecond) }
	}
	print('fea')
	flush_stdout()
	time.sleep(20 * time.millisecond)
	println('ture')
	println('PASS')
	flush_stdout()
	if mode == 'late-failure' {
		time.sleep(50 * time.millisecond)
		println('FAIL')
		flush_stdout()
	}
	if mode == 'group' {
		mut p := os.new_process(os.executable())
		p.set_args(['--child', 'idle'])
		p.run()
		os.write_file(os.args[3], p.pid.str()) or { panic(err) }
		for { time.sleep(20 * time.millisecond) }
	}
	time.sleep(100 * time.millisecond)
	if mode == 'nonzero' { exit(7) }
}

fn session_checks(work string) ! {
	before := descriptors()
	for mode in ['pass', 'nonzero', 'late-failure'] {
		result := guesthost.boot_session([os.executable(), '--child', mode], policyhost.environment(), work,
			guesthost.SessionPolicy{ pass: 'PASS', failures: ['FAIL'], settle: 5, log: work + '/raw.log' }, 5, false)!
		assert result.finished && result.passed && !result.forced
		assert result.text.contains('feature')
		assert result.status == if mode == 'nonzero' { 7 } else { 0 }
		assert os.read_file(work + '/raw.log')! == result.text
		if mode == 'late-failure' {
			assert result.text.contains('FAIL')
		}
	}
	group := guesthost.boot_session([os.executable(), '--child', 'group', work + '/descendant.pid'], policyhost.environment(), work,
		guesthost.SessionPolicy{ pass: 'PASS', settle: 0.1, cleanup_wait: 0.1, term_wait: 0.1, kill_wait: 1 }, 5, false)!
	assert group.forced
	pid := os.read_file(work + '/descendant.pid')!.int()
	deadline := time.sys_mono_now() + i64(2 * time.second)
	for C.kill(pid, 0) == 0 && time.sys_mono_now() < deadline { time.sleep(10 * time.millisecond) }
	assert C.kill(pid, 0) != 0
	mut interrupt_seen := false
	guesthost.boot_session([os.executable(), '--child', 'interrupt'], policyhost.environment(), work,
		guesthost.SessionPolicy{ pass: 'PASS', cleanup_wait: 0.1, term_wait: 0.1, kill_wait: 1 }, 5, false) or {
		assert err.msg() == 'Guest run interrupted'
		interrupt_seen = true
	}
	assert interrupt_seen && descriptors() == before
	println('PASS fragmented serial capture, first verdict, late failure, raw log, status, descendant and SIGINT retirement')
}

fn verdict_checks() ! {
	for family in ['security', 'mount', 'ipv6'] {
		text := systemhost.features(family).join('\n') + '\n' + systemhost.security_pass(family) + '\n: pledge "rpath", syscall 1'
		assert systemhost.security_verdict(text, family, 'aarch64', true).len == 0
		for feature in systemhost.features(family) {
			assert systemhost.security_verdict(text + feature, family, 'amd64', true).len > 0
		}
		assert systemhost.security_verdict(text, family, 'amd64', false).len > 0
	}
	numa := systemhost.features('numa').join('\n') + '\n' + systemhost.numa_kernel_markers().join('\n') + '\nVINIX QEMU NUMA: PASS'
	assert systemhost.numa_verdict(guesthost.SessionResult{ text: numa }).len == 0
	assert systemhost.numa_verdict(guesthost.SessionResult{ text: numa, forced: true }).len > 0
	assert systemhost.numa_verdict(guesthost.SessionResult{ text: numa, status: 137 }).len > 0
	for marker in systemhost.numa_kernel_markers() {
		assert systemhost.numa_verdict(guesthost.SessionResult{ text: numa.replace(marker, '') }).len > 0
	}
	root := ['VINIX DISK ROOT: START', 'VINIX DISK ROOT: ON VOLUME', 'VINIX DISK ROOT: LARGE FILE OK'].join('\n').repeat(2) + '\nVINIX DISK ROOT: WROTE /etc MARKER, REBOOTING\nVINIX DISK ROOT: PASS'
	systemhost.root_verdict(root, 'disk-root')!
	for bad in [root + 'Loading saved package overlay', root.replace('ON VOLUME', ''),
		root.replace('LARGE FILE OK', '')] {
		mut failed := false
		systemhost.root_verdict(bad, 'disk-root') or { failed = true }
		assert failed
	}
	assert systemhost.securelevel_cases().len == 8
	assert systemhost.securelevel_verdict('security: invalid or duplicate vinix.securelevel boot policy\nKERNEL PANIC', 0, false)
	assert !systemhost.securelevel_verdict('security: invalid or duplicate vinix.securelevel boot policy\nKERNEL PANIC\nSECURELEVEL BOOT TEST ENTERED', 0, false)
	header := systemhost.swap_header()
	assert header[1024..1036].hex() == '01000000ffff000000000000'
	assert header[4086..].bytestr() == 'SWAPSPACE2' && header[..1024].all(it == 0) && header[1036..4086].all(it == 0)
	println('PASS exact feature counts, NUMA kernel/exit guards, root reboot checks, securelevel panic gates and swap header')
}

fn checked() ! {
	work := hosttest.work_dir('', 'vinix-system-check-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	verdict_checks()!
	packet_checks(work)!
	echo_checks()!
	session_checks(work)!
	println('PASS system controller host qualification')
}

fn main() {
	if os.args.len > 2 && os.args[1] == '--child' {
		child(os.args[2])
		return
	}
	guard := policyhost.own_commands()
	defer { guard.close() }
	checked() or {
		eprintln(err)
		exit(1)
	}
}
