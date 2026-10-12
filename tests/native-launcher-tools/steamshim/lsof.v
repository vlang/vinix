// SPDX-License-Identifier: GPL-2.0-or-later
module steamshim

import encoding.hex
import os
import perfreport
import strconv

pub struct Report {
pub:
	status     int
	output     string
	error_text string
}

struct StatIndexError {}

fn (e StatIndexError) msg() string { return 'invalid process stat fields' }

fn (e StatIndexError) code() int { return 0 }

fn ascii_file(path string) !string {
	text := os.read_file(path)!
	if text.bytes().any(it >= 128) { return error('invalid ASCII procfs data') }
	return text.replace('\r\n', '\n').replace('\r', '\n')
}

pub fn ipv4(value string) !string {
	bytes := hex.decode(value)!
	if bytes.len != 4 { return error('invalid IPv4 address') }
	return bytes.reverse().map(it.str()).join('.')
}

pub fn tcp_sockets(table string, host string, port string) !map[string]string {
	source := ascii_file(table)!
	lines := source.split_into_lines()
	if lines.len == 0 { return error('empty TCP socket table') }
	mut sockets := map[string]string{}
	for line in lines[1..] {
		fields := line.fields()
		if fields.len < 10 { continue }
		local := fields[1].split(':')
		remote := fields[2].split(':')
		if local.len != 2 || remote.len != 2 { return error('invalid TCP socket address') }
		address := ipv4(local[0])!
		peer := ipv4(remote[0])!
		number := strconv.parse_uint(local[1], 16, 64)!.str()
		peer_number := strconv.parse_uint(remote[1], 16, 64)!.str()
		if (address != host || number != port) && (peer != host || peer_number != port) { continue }
		mut name := address + ':' + number
		if fields[3] != '0a' { name += '->' + peer + ':' + peer_number }
		sockets[fields[9]] = name
	}
	return sockets
}

pub fn process_parent(path string) !string {
	text := ascii_file(path)!
	if !text.contains(')') { return StatIndexError{} }
	fields := text.all_after_last(')').fields()
	if fields.len < 2 { return StatIndexError{} }
	return fields[1]
}

fn decimal_name(text string) bool {
	return text != '' && text.runes().all(perfreport.decimal(it) >= 0)
}

pub fn lsof_report(proc string, argv []string) !Report {
	if argv.len != 5 || argv[..3] != ['-P', '-F', 'upnR'] || argv[3] != '-i' || !argv[4].starts_with('TCP@') {
		return Report{ status: 1, error_text: 'lsof: unsupported arguments\n' }
	}
	query := argv[4][4..]
	if !query.contains(':') {
		return Report{ status: 1, error_text: 'lsof: expected TCP@host:port\n' }
	}
	host := query.all_before_last(':')
	port := perfreport.integer_text(query.all_after_last(':')) or { return Report{ status: 1, error_text: 'lsof: expected TCP@host:port\n' } }
	sockets := tcp_sockets(proc + '/net/tcp', host, port)!
	mut output := ''
	mut found := false
	for pid in os.ls(proc)! {
		if !decimal_name(pid) { continue }
		directory := proc + '/' + pid + '/fd'
		descriptors := os.ls(directory) or { continue }
		mut matches := []string{}
		for fd in descriptors {
			target := os.readlink(directory + '/' + fd) or { continue }
			if target.starts_with('socket:[') && target.ends_with(']') {
				inode := target[8..target.len - 1]
				if name := sockets[inode] { matches << 'f' + fd + '\nn' + name + '\n' }
			}
		}
		if matches.len == 0 { continue }
		parent := process_parent(proc + '/' + pid + '/stat') or {
			if err is StatIndexError { return err }
			continue
		}
		information := os.stat(proc + '/' + pid) or { continue }
		output += 'p' + pid + '\nR' + parent + '\nu' + information.uid.str() + '\n' + matches.join('')
		found = true
	}
	return Report{ status: if found { 0 } else { 1 }, output: output }
}

pub fn lsof_cli(argv []string) !int {
	report := lsof_report('/proc', argv)!
	print(report.output)
	eprint(report.error_text)
	return report.status
}
