// SPDX-License-Identifier: GPL-2.0-or-later
// Restore the complete bounded UART archive from the credential-free probe.
module main

import crypto.sha256
import encoding.base64
import json2
import os
import time

#include <sys/stat.h>

const browser_prefix = 'VINIX-BROWSER-RESULTS-1 '
const headless_prefix = 'VINIX-HEADLESS-RESULTS-1 '
const chunk_bytes = 512
const max_file = 8 * 1024 * 1024
const max_total = 16 * 1024 * 1024
const max_archive = 32 * 1024 * 1024

struct Entry {
	path   string
	kind   string
	mode   u32
	size   u64
	sha256 string
	data   string
	link   string
}

struct Archive {
	version   int = 1
	root_mode u32
	entries   []Entry
}

struct Export {
	sha256  string
	bytes   int
	chunks  int
	payload string
}

struct Protocol {
	prefix string = browser_prefix
	label string = 'BROWSER-COLLECT'
	scope string = 'Exact credential-free browser diagnostic UART archive; not Google authentication proof.'
}

fn protocol(headless bool) Protocol {
	return if headless {
		Protocol{prefix: headless_prefix, label: 'HEADLESS-COLLECT',
			scope: 'Exact synthetic headless service lifecycle UART archive; no account, token or Google authentication proof.'}
	} else { Protocol{} }
}

fn decimal(text string, limit int) !int {
	if text == '' || text.len > 10 || (text.len > 1 && text[0] == `0`)
		|| !text.bytes().all(it >= `0` && it <= `9`) {
		return error('noncanonical decimal')
	}
	n := text.u64()
	if n > u64(limit) { return error('decimal exceeds limit') }
	return int(n)
}

fn digest(text string) bool {
	return text.len == 64 && text.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn parse_export(log string, selected Protocol) !Export {
	prefix := selected.prefix
	mut begun := false
	mut ended := false
	mut sha := ''
	mut bytes := 0
	mut chunks := 0
	mut index := 0
	mut parts := []string{}
	for raw in log.split_into_lines() {
		line := raw.trim_right('\r')
		if (line.starts_with(browser_prefix) || line.starts_with(headless_prefix)) && !line.starts_with(prefix) {
			return error('foreign archive protocol')
		}
		if !line.starts_with(prefix) { continue }
		if line.len > 1024 || ended { return error('oversized frame or repeated export') }
		fields := line[prefix.len..].split(' ')
		if fields.any(it == '') { return error('noncanonical frame whitespace') }
		if fields.len == 4 && fields[0] == 'BEGIN' {
			if begun || !digest(fields[1]) { return error('duplicate/invalid BEGIN') }
			sha = fields[1]
			bytes = decimal(fields[2], max_archive)!
			chunks = decimal(fields[3], (max_archive + chunk_bytes - 1) / chunk_bytes)!
			if bytes == 0 || chunks != (bytes + chunk_bytes - 1) / chunk_bytes {
				return error('invalid export bounds')
			}
			begun = true
		} else if fields.len == 4 && fields[0] == 'CHUNK' {
			if !begun || fields[1] != sha || index >= chunks
				|| decimal(fields[2], chunks)! != index {
				return error('out-of-order/foreign chunk')
			}
			data := base64.decode(fields[3])
			expected := if index + 1 == chunks { bytes - index * chunk_bytes } else { chunk_bytes }
			if data.len != expected || base64.encode(data) != fields[3] {
				return error('invalid chunk encoding/length')
			}
			parts << data.bytestr()
			index++
		} else if fields.len == 4 && fields[0] == 'END' {
			if !begun || index != chunks || fields[1] != sha || decimal(fields[2], max_archive)! != bytes
				|| decimal(fields[3], chunks)! != chunks {
				return error('incomplete/foreign END')
			}
			ended = true
		} else {
			return error('unknown export frame')
		}
	}
	if !ended { return error('complete export absent') }
	payload := parts.join('')
	if payload.len != bytes || sha256.sum(payload.bytes()).hex() != sha {
		return error('archive size/hash mismatch')
	}
	return Export{sha, bytes, chunks, payload}
}

fn safe_relative(path string) bool {
	return path != '' && path.len <= 4096 && !path.starts_with('/')
		&& !path.contains_any('\x00\n\r\\') && !path.split('/').any(it in ['', '.', '..'])
}

fn validate(payload string) !Archive {
	if payload.len > max_archive { return error('archive exceeds limit') }
	archive := json2.decode[Archive](payload)!
	if archive.version != 1 || archive.entries.len > 4096 || archive.root_mode > 0o777 {
		return error('unsupported archive version/count/root mode')
	}
	mut seen := map[string]string{}
	mut total := u64(0)
	for entry in archive.entries {
		if !safe_relative(entry.path) || entry.path in seen || entry.mode > 0o777 {
			return error('unsafe/duplicate path or mode')
		}
		parent := os.dir(entry.path)
		if parent != '.' && (seen[parent] or { '' }) != 'directory' {
			return error('missing/non-directory parent')
		}
		match entry.kind {
			'directory' {
				if entry.size != 0 || entry.sha256 != '' || entry.data != '' || entry.link != '' {
					return error('invalid directory fields')
				}
			}
			'regular' {
				if entry.size > max_file || total + entry.size > max_total || !digest(entry.sha256) || entry.link != ''
					|| entry.data.len > (max_file + 2) / 3 * 4 {
					return error('regular file exceeds bounds')
				}
				data := base64.decode(entry.data)
				if u64(data.len) != entry.size || base64.encode(data) != entry.data
					|| sha256.sum(data).hex() != entry.sha256 {
					return error('regular file size/hash/encoding mismatch')
				}
				total += entry.size
			}
			'symlink' {
				if entry.link == '' || entry.link.len > 4096 || entry.link.contains('\x00')
					|| entry.size != 0 || entry.sha256 != '' || entry.data != '' {
					return error('invalid symlink')
				}
			}
			else { return error('unsupported archive inode type') }
		}
		seen[entry.path] = entry.kind
	}
	return archive
}

fn restore(root string, archive Archive, exported Export, serial string, serial_sha string, selected Protocol) ! {
	if os.exists(root) || os.is_link(root) { return error('fresh external output required') }
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('cannot exclusively create output') }
	os.mkdir(root + '/results')!
	for entry in archive.entries {
		path := root + '/results/' + entry.path
		match entry.kind {
			'directory' { os.mkdir(path)! }
			'regular' {
				mut file := os.open_file(path, 'wx', 0o600)!
				file.write_string(base64.decode(entry.data).bytestr()) or {
					file.close()
					return err
				}
				file.close()
				if sha256.sum(os.read_bytes(path)!).hex() != entry.sha256 {
					return error('restored file readback mismatch')
				}
				os.chmod(path, int(entry.mode))!
			}
			'symlink' { os.symlink(entry.link, path)! }
			else { return error('internal unsupported inode') }
		}
	}
	// Apply directory modes after children, so an evidence mode cannot block extraction.
	for entry in archive.entries.reverse() {
		if entry.kind == 'directory' { os.chmod(root + '/results/' + entry.path, int(entry.mode))! }
	}
	os.chmod(root + '/results', int(archive.root_mode))!
	os.write_file(root + '/archive.json', exported.payload)!
	if sha256.sum(os.read_bytes(root + '/archive.json')!).hex() != exported.sha256 {
		return error('archive readback mismatch')
	}
	os.write_file(root + '/import.json', json2.encode({
		'format':         json2.Any(1)
		'created_utc':    json2.Any(time.utc().str())
		'serial_path':    json2.Any(os.real_path(serial))
		'serial_sha256':  json2.Any(serial_sha)
		'archive_sha256': json2.Any(exported.sha256)
		'archive_bytes':  json2.Any(exported.bytes)
		'archive_chunks': json2.Any(exported.chunks)
		'entries':        json2.Any(archive.entries.len)
		'scope':          json2.Any(selected.scope)
	}, prettify: true) + '\n')!
}

fn frames(payload string, selected Protocol) string {
	prefix := selected.prefix
	sha := sha256.sum(payload.bytes()).hex()
	count := (payload.len + chunk_bytes - 1) / chunk_bytes
	header := sha + ' ' + payload.len.str() + ' ' + count.str() + '\n'
	mut result := prefix + 'BEGIN ' + header
	for offset := 0; offset < payload.len; offset += chunk_bytes {
		end := if offset + chunk_bytes < payload.len { offset + chunk_bytes } else { payload.len }
		result += prefix + 'CHUNK ' + sha + ' ' + (offset / chunk_bytes).str() + ' ' + base64.encode(payload[offset..end].bytes()) + '\n'
	}
	return result + prefix + 'END ' + header
}

fn self_test_protocol(selected Protocol) ! {
	prefix := selected.prefix
	data := 'exact\x00binary\n'.bytes()
	fixture := Archive{
		root_mode: 0o700
		entries:   [
			Entry{ path: 'd', kind: 'directory', mode: 0o700 },
			Entry{ path: 'd/log', kind: 'regular', mode: 0o640, size: u64(data.len), sha256: sha256.sum(data).hex(), data: base64.encode(data) },
			Entry{ path: 'font', kind: 'symlink', mode: 0o777, link: '/pinned/font' },
		]
	}
	payload := json2.encode(fixture)
	log := frames(payload, selected)
	exported := parse_export('kernel chatter\n' + log + 'done\n', selected)!
	assert exported.payload == payload && validate(exported.payload)!.entries == fixture.entries
	changed := payload.replace('/pinned/font', '/pinned/foNt')
	changed_sha := sha256.sum(changed.bytes()).hex()
	for bad in [log.all_before(prefix + 'END'), log + log,
		log.replace('CHUNK ' + exported.sha256 + ' 0 ', 'CHUNK ' + exported.sha256 + ' 1 '),
		log.replace('BEGIN ' + exported.sha256, 'BEGIN ' + '0'.repeat(64)),
		log.replace('CHUNK ', 'OTHER '), log.replace(' 0 ', ' 00 '),
		frames(changed, selected).replace(changed_sha, exported.sha256),
		frames('test', selected).replace('dGVzdA==', 'dGVzdA'),
		log + frames(payload, protocol(selected.prefix == browser_prefix))] {
		if _ := parse_export(bad, selected) { return error('malformed export accepted') }
	}
	for bad in [
		Archive{ root_mode: 0o700, entries: [Entry{ path: '../escape', kind: 'directory' }] },
		Archive{ root_mode: 0o700, entries: [Entry{ path: '/escape', kind: 'directory' }] },
		Archive{ root_mode: 0o700, entries: [fixture.entries[1]] },
		Archive{ root_mode: 0o700, entries: [
			fixture.entries[0],
			fixture.entries[0],
		] },
		Archive{ root_mode: 0o700, entries: [
			Entry{ path: 'd', kind: 'symlink', link: '/' },
			fixture.entries[1],
		] },
		Archive{ root_mode: 0o700, entries: [Entry{ path: 'fifo', kind: 'fifo' }] },
		Archive{ root_mode: 0o700, entries: [Entry{ path: 'log', kind: 'regular', size: 1, sha256: '0'.repeat(64), data: 'YQ==' }] },
		Archive{ root_mode: 0o4700, entries: []Entry{} },
	] {
		if _ := validate(json2.encode(bad)) { return error('unsafe archive accepted') }
	}
	root := os.join_path(os.temp_dir(), 'vinix-archive-collect-selftest-' + selected.label + '-' + os.getpid().str())
	serial := root + '.serial'
	if os.exists(root) || os.exists(serial) { return error('selftest output exists') }
	defer {
		os.rmdir_all(root) or {}
		os.rm(serial) or {}
	}
	os.write_file(serial, log)!
	restore(root, fixture, exported, serial, sha256.sum(log.bytes()).hex(), selected)!
	assert os.read_bytes(root + '/results/d/log')! == data
	assert os.lstat(root + '/results/d/log')!.mode & 0o777 == 0o640
	assert os.readlink(root + '/results/font')! == '/pinned/font'
	assert os.read_file(root + '/archive.json')! == payload
	receipt := json2.decode[map[string]json2.Any](os.read_file(root + '/import.json')!)!
	assert receipt['scope']!.str() == selected.scope
	if _ := restore(root, fixture, exported, serial, sha256.sum(log.bytes()).hex(), selected) {
		return error('existing output accepted')
	}
	println(selected.label + ' SELF-TEST PASS complete-export binary modes links checksum ordering truncation duplicate traversal parent inode fresh-output foreign-protocol scope')
}

fn self_test() ! {
	self_test_protocol(protocol(false))!
	self_test_protocol(protocol(true))!
}

fn run() ! {
	headless := os.args.len == 4 && os.args[1] == '--headless'
	if !headless && os.args.len != 3 { return error('usage: collect [--headless] SERIAL_LOG FRESH_EXTERNAL_RESULTS') }
	selected := protocol(headless)
	offset := if headless { 1 } else { 0 }
	serial, root := os.args[1 + offset], os.args[2 + offset]
	st := os.lstat(serial)!
	if st.get_filetype() != .regular || st.size > 256 * 1024 * 1024 {
		return error('regular bounded serial log required')
	}
	log := os.read_file(serial)!
	if u64(log.len) != st.size { return error('serial log changed size while reading') }
	exported := parse_export(log, selected)!
	archive := validate(exported.payload)!
	restore(root, archive, exported, serial, sha256.sum(log.bytes()).hex(), selected)!
	println(selected.label + ' PASS entries=' + archive.entries.len.str() + ' sha256=' + exported.sha256)
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	run() or {
		eprintln(err.msg())
		exit(1)
	}
}
