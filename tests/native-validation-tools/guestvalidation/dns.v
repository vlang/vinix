// SPDX-License-Identifier: GPL-2.0-or-later
module guestvalidation

import cachecli
import net
import os
import time

pub const dns_query = '\x56\x4e\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01'

pub fn dns_reply(data []u8) bool {
	return data.len >= 12 && data[..2] == dns_query.bytes()[..2] && data[2] & 0x80 != 0
}

pub fn dns_answers(server string, port int, timeout f64) bool {
	mut connection := net.dial_udp('${server}:${port}') or { return false }
	defer { connection.close() or {} }
	connection.set_read_timeout(time.Duration(timeout * f64(time.second)))
	connection.set_write_timeout(time.Duration(timeout * f64(time.second)))
	connection.write(dns_query.bytes()) or { return false }
	mut bytes := []u8{len: 512}
	count, _ := connection.read(mut bytes) or { return false }
	return dns_reply(bytes[..count])
}

pub struct DnsTools {
pub:
	answer  fn (string, int, f64, voidptr) bool = unsafe { nil }
	sleep   fn (f64, voidptr) !                 = unsafe { nil }
	context voidptr
}

fn (tools DnsTools) answers(server string, timeout f64) bool {
	if tools.answer != unsafe { nil } { return tools.answer(server, 53, timeout, tools.context) }
	return dns_answers(server, 53, timeout)
}

fn is_proxy(line string) bool {
	mut words := []string{}
	mut word := ''
	for point in line.runes() {
		letter := point.str()
		if unicode_space(point) {
			if word != '' {
				words << word
				word = ''
			}
		} else {
			word += letter
		}
	}
	if word != '' { words << word }
	return words == ['nameserver', '10.0.2.3']
}

pub fn update_dns(path string, tools DnsTools) !int {
	bytes := os.read_file(path) or { return 0 }
	strict_utf8(bytes)!
	original := bytes.replace('\r\n', '\n').replace('\r', '\n')
	// Keep complete text lines and comments while removing only exact directives.
	mut lines := []string{}
	mut begin := 0
	mut offset := 0
	for point in original.runes() {
		offset += point.str().len
		if point in [`\n`, `\v`, `\f`, rune(28), rune(29), rune(30), rune(133), rune(0x2028),
			rune(0x2029)] {
			lines << original[begin..offset]
			begin = offset
		}
	}
	if begin < original.len { lines << original[begin..] }
	if !lines.any(is_proxy(it)) { return 0 }
	mut working := ''
	for _ in 0 .. 15 {
		cachecli.checkpoint()!
		for server in ['1.1.1.1', '8.8.8.8'] {
			if tools.answers(server, 1) {
				working = server
				break
			}
		}
		if working != '' { break }
		if tools.sleep != unsafe { nil } {
			tools.sleep(1, tools.context)!
		} else {
			guest_pause(1)!
		}
	}
	if working == '' || tools.answers('10.0.2.3', 2) { return 0 }
	mut kept := lines.filter(!is_proxy(it))
	kept << ['nameserver 1.1.1.1\n', 'nameserver 8.8.8.8\n']
	temporary := path + '.steam-tmp'
	publish_dns(temporary, path, kept.join('')) or {
		println("steam: could not update QEMU's unresponsive DNS: " + err.msg())
		flush_stdout()
		os.rm(temporary) or {}
		return 1
	}
	println('steam: QEMU DNS at 10.0.2.3 is unresponsive; using ' + working)
	flush_stdout()
	return 0
}

fn publish_dns(temporary string, path string, text string) ! {
	os.write_file(temporary, text)!
	if C.rename(temporary.str, path.str) != 0 { return os.error_posix() }
}

pub fn dns_cli(argv []string) !int {
	cachecli.arguments(argv, [], [], [], 0, 0, "Replace QEMU's DNS proxy only after real failed queries.\nUsage: qemu-dns") or { return error_with_code(err.msg(), 2) }
	return update_dns(env('VINIX_STEAM_RESOLV_CONF', '/etc/resolv.conf'), DnsTools{})!
}
