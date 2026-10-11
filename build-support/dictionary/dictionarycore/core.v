// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module dictionarycore

import crypto.sha256
import encoding.binary
import encoding.utf8
import os
import sourcecommand
import strconv
import tarstream

pub const url = 'https://wordnetcode.princeton.edu/3.0/WordNet-3.0.tar.gz'
pub const archive_sha256 = '640db279c949a88f61f851dd54ebbb22d003f8b90b85267042ef85a3781d3a52'
pub const max_entries = 200000
pub const max_key = 128
pub const max_definition = 64 * 1024
pub const max_file = 64 * 1024 * 1024

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>

fn C.mkstemp(&u8) i32
fn C.chmod(&char, u32) int
fn C.rename(&char, &char) int
fn C.signal(i32, voidptr) voidptr
fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)

__global ( pending_signal i32 )
fn interrupted(signal i32) { unsafe { C.__atomic_store_n(&pending_signal, signal, C.__ATOMIC_RELAXED) } }
fn cancelled() bool { return unsafe { C.__atomic_load_n(&pending_signal, C.__ATOMIC_RELAXED) } != 0 }
fn failure_status() int { return if cancelled() { 128 + int(unsafe { C.__atomic_load_n(&pending_signal, C.__ATOMIC_RELAXED) }) } else { 1 } }
fn checkpoint() ! { if cancelled() { return error('dictionary preparation interrupted') } }

fn word(mut data []u8, value int) {
	mut bytes := []u8{len: 4}
	binary.little_endian_put_u32(mut bytes, u32(value))
	data << bytes
}

fn valid(text string, definition bool) bool {
	return utf8.validate_str(text) && text.runes().all((it >= 32 || (definition && it == `\n`)) && (it < 127 || it > 159))
}

pub fn encode(entries map[string]string) ![]u8 {
	if entries.len == 0 || entries.len > max_entries { return error('invalid lexicon entry count') }
	mut names := entries.keys()
	names.sort()
	mut table := []u8{cap: entries.len * 16}
	mut keys := []u8{}
	mut definitions := []u8{}
	for name in names {
		checkpoint()!
		definition := entries[name]
		if name.len == 0 || name.len > max_key || definition.len == 0 || definition.len > max_definition {
			return error('lexicon entry exceeds bounds')
		}
		if !valid(name, false) { return error('invalid headword') }
		if !valid(definition, true) { return error('invalid definition text') }
		if 24 + entries.len * 16 + keys.len + name.len + definitions.len + definition.len > max_file {
			return error('lexicon exceeds file bound')
		}
		for value in [keys.len, name.len, definitions.len, definition.len] { word(mut table, value) }
		keys << name.bytes()
		definitions << definition.bytes()
	}
	mut result := 'VNXDICT1'.bytes()
	for value in [entries.len, keys.len, definitions.len, 0] { word(mut result, value) }
	result << table
	result << keys
	result << definitions
	return result
}

struct Payload {
	valid bool
	data []u8
}

pub struct Lexicon {
pub:
	entries map[string]string
	license []u8
}

pub fn parse_wordnet(path string) !Lexicon {
	mut file := os.open(path)!
	mut magic := []u8{len: 2}
	read := file.read(mut magic) or { file.close(); return err }
	file.close()
	if read != 2 || magic != [u8(0x1f), 0x8b] { return error('WordNet archive must be gzip compressed') }
	names := ['WordNet-3.0/LICENSE', 'WordNet-3.0/dict/data.noun', 'WordNet-3.0/dict/data.verb',
		'WordNet-3.0/dict/data.adj', 'WordNet-3.0/dict/data.adv']
	mut contents := map[string]Payload{}
	mut reader := tarstream.open(path)!
	defer { reader.close() }
	for {
		checkpoint()!
		member := reader.next() or { if err is tarstream.End { break }; return err }
		if member.name !in names { continue }
		limit := if member.name == names[0] { 16384 } else { max_file }
		if !member.regular() || member.size > limit {
			contents[member.name] = Payload{}
			continue
		}
		mut body := []u8{len: int(member.size)}
		mut position := 0
		for position < body.len {
			mut part := unsafe { body[position..] }
			count := reader.read(mut part)!
			if count == 0 { return error('truncated WordNet member') }
			position += count
		}
		// tarfile.getmember selected the last matching member in the original.
		contents[member.name] = Payload{true, body}
	}
	for name in names {
		if name !in contents || !contents[name].valid { return error('missing or invalid WordNet member: ' + name) }
	}
	mut senses := map[string][]string{}
	for index, label in ['noun', 'verb', 'adjective', 'adverb'] {
		for raw in contents[names[index + 1]].data.bytestr().split('\n') {
			checkpoint()!
			if raw.starts_with(' ') || raw.trim(' \t\r\n\x0b\x0c') == '' { continue }
			if !utf8.validate_str(raw) { return error('WordNet member contains invalid UTF-8') }
			at := raw.index(' | ') or { return error('invalid WordNet data line') }
			fields := raw[..at].fields()
			if fields.len < 4 { return error('invalid WordNet metadata') }
			count := strconv.parse_int(fields[3], 16, 32)!
			if count < 0 || count > (fields.len - 4) / 2 { return error('invalid WordNet word count') }
			mut words := []string{}
			for i in 0 .. int(count) {
				mut name := fields[4 + i * 2]
				for suffix in ['(a)', '(p)', '(ip)'] { if name.ends_with(suffix) { name = name[..name.len - suffix.len] } }
				name = utf8.to_lower(name.replace('_', ' '))
				if name !in words { words << name }
			}
			definition := '[' + label + '] ' + raw[at + 3..].trim_space() + '\nRelated: ' + words.join(', ')
			for name in words {
				mut values := senses[name]
				if definition !in values { values << definition; senses[name] = values }
			}
		}
	}
	mut entries := map[string]string{}
	for name, definitions in senses { entries[name] = definitions.join('\n\n') }
	return Lexicon{entries, contents[names[0]].data}
}

pub fn verified_archive(path string) bool {
	if !os.is_file(path) { return false }
	data := os.read_bytes(path) or { return false }
	return sha256.sum(data).hex() == archive_sha256
}

pub fn atomic_write(path string, data []u8) ! {
	checkpoint()!
	mut name := (path + '.XXXXXX\x00').bytes()
	mut fd := unsafe { C.mkstemp(&u8(name.data)) }
	if fd < 0 { return os.error_posix() }
	temporary := name.bytestr().all_before('\x00')
	defer { if fd >= 0 { C.close(fd) }; os.rm(temporary) or {} }
	if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 { return os.error_posix() }
	mut position := 0
	for position < data.len {
		checkpoint()!
		count := unsafe { C.write(fd, &data[position], usize(data.len - position)) }
		if count < 0 { if C.errno == C.EINTR { continue }; return os.error_posix() }
		if count == 0 { return error('cannot write dictionary data') }
		position += int(count)
	}
	closed := C.close(fd)
	fd = -1
	if closed != 0 || C.chmod(temporary.str, 0o444) != 0 || C.rename(temporary.str, path.str) != 0 {
		return os.error_posix()
	}
}

pub fn stage(archive string, destination string) !int {
	lexicon := parse_wordnet(archive)!
	data := encode(lexicon.entries)!
	os.mkdir_all(destination)!
	atomic_write(destination + '/dictionary.vnd', data)!
	atomic_write(destination + '/LICENSE.WordNet', lexicon.license)!
	println('Dictionary: staged ${lexicon.entries.len} offline headwords (${data.len} bytes)')
	return lexicon.entries.len
}

pub fn cli(argv []string, root string) int {
	if argv.any(it in ['--help', '-h']) {
		println('prepare --destination DIR [--cache DIR] [--archive PATH]')
		return 0
	}
	mut options := {'cache': root + '/build/dictionary'}
	mut index := 0
	for index < argv.len {
		arg := argv[index]
		name := arg.all_before('=').trim_left('-')
		if !arg.starts_with('--') || name !in ['destination', 'cache', 'archive'] { eprintln('unrecognized option ' + arg); return 2 }
		value := if arg.contains('=') { arg.all_after('=') } else {
			index++
			if index >= argv.len || argv[index].starts_with('--') { eprintln('missing option value'); return 2 }
			argv[index]
		}
		options[name] = if value == '' { '.' } else { value }
		index++
	}
	if 'destination' !in options { eprintln('--destination is required'); return 2 }
	unsafe { C.__atomic_store_n(&pending_signal, 0, C.__ATOMIC_RELAXED) }
	interrupt := unsafe { C.signal(C.SIGINT, voidptr(interrupted)) }
	terminate := unsafe { C.signal(C.SIGTERM, voidptr(interrupted)) }
	pipe := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	defer { unsafe { C.signal(C.SIGINT, interrupt); C.signal(C.SIGTERM, terminate); C.signal(C.SIGPIPE, pipe) } }
	os.mkdir_all(options['cache']) or { eprintln(err); return failure_status() }
	archive := options['archive'] or { options['cache'] + '/WordNet-3.0.tar.gz' }
	if !verified_archive(archive) {
		if 'archive' in options { eprintln('archive does not match the pinned WordNet 3.0 SHA-256'); return 2 }
		curl := os.find_abs_path_of_executable('curl') or { eprintln(err); return failure_status() }
		result := sourcecommand.capture([curl, '--location', '--fail', '--silent', '--show-error', '--max-time', '60', url], os.environ(), 60, 16 * 1024 * 1024 + 1, cancelled) or { eprintln(err); return failure_status() }
		if result.status != 0 || result.stdout.len > 16 * 1024 * 1024 || sha256.sum(result.stdout.bytes()).hex() != archive_sha256 {
			eprintln('download does not match the pinned WordNet archive'); return 1
		}
		atomic_write(archive, result.stdout.bytes()) or { eprintln(err); return failure_status() }
	}
	stage(archive, options['destination']) or { eprintln(err); return failure_status() }
	return if cancelled() { failure_status() } else { 0 }
}
