// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit, checksum-gated diagnostic derivation; never a strict UART import.
module main

import crypto.sha256
import encoding.base64
import json2
import os
import time

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

fn C.open(&char, int, ...int) int
fn C.read(int, voidptr, u64) i64
fn C.write(int, voidptr, u64) i64
fn C.close(int) int
fn C.fstat(int, &C.stat) int

const prefix = 'VINIX-MAPS-ACCOUNT-RESULTS-1 '
const raw_limit = 8 * 1024 * 1024
const archive_limit = 4 * 1024 * 1024
const known_prefixes = ['VINIX-BROWSER-RESULTS-1 ', 'VINIX-HEADLESS-RESULTS-1 ',
	'VINIX-ACCOUNT-UI-RESULTS-1 ', prefix, 'VINIX-ACCOUNT-TOKEN-CACHE-RESULTS-1 ',
	'VINIX-SERVICE-QUERY-RESULTS-1 ']

struct Removal {
	offset int
	expected string
}

struct Span {
	start int
	end int
}

struct Plan {
	version int
	serial_sha256 string
	archive_sha256 string
	archive_bytes int
	archive_chunks int
	removals []Removal
}

struct Entry {
	path string
	kind string
	mode u32
	size u64
	sha256 string
	data string
	link string
}

struct Archive {
	version int
	root_mode u32
	entries []Entry
}

fn hash(data string) string { return sha256.sum(data.bytes()).hex() }

fn digest(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn read_bounded(path string, limit int) !string {
	if os.real_path(path) != path { return error('canonical regular input required') }
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('input open failed') }
	defer { C.close(fd) }
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 || st.st_mode & C.S_IFMT != C.S_IFREG || st.st_size <= 0 || st.st_size > limit {
		return error('input size/type rejected')
	}
	mut bytes := []u8{len: int(st.st_size)}
	mut count := 0
	for count < bytes.len {
		n := unsafe { C.read(fd, &u8(bytes.data) + count, u64(bytes.len - count)) }
		if n <= 0 { return error('input truncated or read failed') }
		count += int(n)
	}
	mut extra := u8(0)
	if C.read(fd, &extra, 1) != 0 { return error('input changed size') }
	return bytes.bytestr()
}

fn decimal(value string, limit int) !int {
	if value == '' || value.len > 10 || (value.len > 1 && value[0] == `0`)
		|| !value.bytes().all(it >= `0` && it <= `9`) || value.u64() > u64(limit) {
		return error('noncanonical/out-of-bounds decimal')
	}
	return value.int()
}

// Audit original frame occurrences and protect their headers before deleting
// any byte. Adjacent removal ranges cannot disguise a removed frame prefix.
fn protected_headers(raw string, plan Plan) ![]Span {
	for known in known_prefixes {
		if known != prefix && raw.contains(known) { return error('foreign raw frame') }
	}
	mut spans := []Span{cap: plan.archive_chunks + 2}
	mut start := 0
	mut ordinal := 0
	for start < raw.len {
		pos := raw[start..].index(prefix) or { break }
		at := start + pos
		if at != 0 && raw[at - 1] != `\n` { return error('embedded raw frame') }
		if ordinal > plan.archive_chunks + 1 { return error('extra raw frame') }
		header := if ordinal == 0 {
			prefix + 'BEGIN ' + plan.archive_sha256 + ' ' + plan.archive_bytes.str() + ' ' + plan.archive_chunks.str()
		} else if ordinal == plan.archive_chunks + 1 {
			prefix + 'END ' + plan.archive_sha256 + ' ' + plan.archive_bytes.str() + ' ' + plan.archive_chunks.str()
		} else {
			prefix + 'CHUNK ' + plan.archive_sha256 + ' ' + (ordinal - 1).str() + ' '
		}
		if !raw[at..].starts_with(header) { return error('original frame header rejected') }
		if ordinal == 0 || ordinal == plan.archive_chunks + 1 {
			tail := raw[at + header.len..]
			if !tail.starts_with('\n') && !tail.starts_with('\r\n') { return error('original boundary rejected') }
		}
		spans << Span{start: at, end: at + header.len}
		ordinal++
		start = at + prefix.len
	}
	if ordinal != plan.archive_chunks + 2 { return error('raw frame count rejected') }
	return spans
}

fn derived_payload(raw string, plan Plan) !string {
	if plan.version != 1 || !digest(plan.serial_sha256) || !digest(plan.archive_sha256)
		|| hash(raw) != plan.serial_sha256 || raw.len > raw_limit || plan.archive_bytes <= 0
		|| plan.archive_bytes > archive_limit || plan.archive_chunks != (plan.archive_bytes + 511) / 512
		|| plan.removals.len == 0 || plan.removals.len > 32 {
		return error('plan bounds or raw SHA256 rejected')
	}
	headers := protected_headers(raw, plan)!
	mut segments := []string{}
	mut previous := 0
	mut removed := 0
	for item in plan.removals {
		if item.offset < previous || item.offset > raw.len || item.expected == '' || item.expected.len > 512
			|| item.expected.len > raw.len - item.offset || item.expected.contains('VINIX-') {
			return error('overlapping or out-of-bounds byte removal')
		}
		end := item.offset + item.expected.len
		if headers.any(item.offset < it.end && end > it.start)
			|| raw[item.offset..end] != item.expected {
			return error('nonexact, overlapping or invalid byte removal')
		}
		removed += item.expected.len
		if removed > 4096 { return error('removal bound exceeded') }
		segments << raw[previous..item.offset]
		previous = end
	}
	segments << raw[previous..]
	// This ephemeral parsing view is never written as a replacement serial log.
	view := segments.join('')
	mut begun := false
	mut ended := false
	mut index := 0
	mut parts := []string{cap: plan.archive_chunks}
	for raw_line in view.split_into_lines() {
		line := raw_line.trim_right('\r')
		for known in known_prefixes {
			if pos := line.index(known) {
				if pos != 0 || known != prefix { return error('embedded/foreign frame') }
			}
		}
		if !line.starts_with(prefix) { continue }
		if ended || line.len > 1024 { return error('repeated/oversized frame') }
		fields := line[prefix.len..].split(' ')
		if fields.len != 4 || fields.any(it == '') || fields[1] != plan.archive_sha256 {
			return error('frame syntax or digest mismatch')
		}
		match fields[0] {
			'BEGIN' {
				if begun || decimal(fields[2], archive_limit)! != plan.archive_bytes
					|| decimal(fields[3], (archive_limit + 511) / 512)! != plan.archive_chunks {
					return error('BEGIN rejected')
				}
				begun = true
			}
			'CHUNK' {
				if !begun || index >= plan.archive_chunks || decimal(fields[2], plan.archive_chunks)! != index {
					return error('chunk order/count rejected')
				}
				data := base64.decode(fields[3])
				expected := if index + 1 == plan.archive_chunks { plan.archive_bytes - index * 512 } else { 512 }
				if data.len != expected || base64.encode(data) != fields[3] { return error('chunk encoding/size rejected') }
				parts << data.bytestr()
				index++
			}
			'END' {
				if !begun || index != plan.archive_chunks || decimal(fields[2], archive_limit)! != plan.archive_bytes
					|| decimal(fields[3], plan.archive_chunks)! != plan.archive_chunks { return error('END rejected') }
				ended = true
			}
			else { return error('unknown frame') }
		}
	}
	payload := parts.join('')
	if !ended || payload.len != plan.archive_bytes || hash(payload) != plan.archive_sha256 {
		return error('complete archive size/SHA256 rejected')
	}
	return payload
}

fn safe_relative(path string) bool {
	return path != '' && path.len <= 4096 && !path.starts_with('/') && !path.contains_any('\x00\r\n\\')
		&& !path.split('/').any(it in ['', '.', '..'])
}

fn validate(payload string) !Archive {
	if payload.len > archive_limit { return error('archive size rejected') }
	archive := json2.decode[Archive](payload)!
	if archive.version != 1 || archive.root_mode > 0o777 || archive.entries.len > 4096 { return error('archive header rejected') }
	mut seen := map[string]string{}
	mut total := u64(0)
	for entry in archive.entries {
		if !safe_relative(entry.path) || entry.path in seen || entry.mode > 0o777
			|| os.file_name(entry.path) in ['broker.log', 'maps.log'] { return error('unsafe/duplicate/private archive path') }
		parent := os.dir(entry.path)
		if parent != '.' && (seen[parent] or { '' }) != 'directory' { return error('archive parent rejected') }
		match entry.kind {
			'directory' {
				if entry.size != 0 || entry.sha256 != '' || entry.data != '' || entry.link != '' { return error('directory fields rejected') }
			}
			'regular' {
				if entry.size > u64(archive_limit) || total + entry.size > u64(archive_limit)
					|| entry.data.len > (archive_limit + 2) / 3 * 4 || !digest(entry.sha256) || entry.link != '' {
					return error('regular fields/bounds rejected')
				}
				data := base64.decode(entry.data)
				if u64(data.len) != entry.size || base64.encode(data) != entry.data || sha256.sum(data).hex() != entry.sha256 {
					return error('entry size/encoding/SHA256 rejected')
				}
				total += entry.size
			}
			'symlink' {
				if entry.link == '' || entry.link.len > 4096 || entry.link.contains('\x00') || entry.size != 0
					|| entry.sha256 != '' || entry.data != '' { return error('symlink fields rejected') }
			}
			else { return error('archive kind rejected') }
		}
		seen[entry.path] = entry.kind
	}
	return archive
}

fn external(path string) ! {
	parent := os.dir(path)
	if !path.starts_with('/') || os.real_path(parent) != parent || parent + '/' + os.file_name(path) != path
		|| os.file_name(path) in ['', '.', '..'] || path.contains_any('\x00\r\n\\') { return error('canonical external output required') }
	mut ancestor := parent
	for {
		if os.exists(ancestor + '/.git') { return error('output inside checkout rejected') }
		if ancestor == '/' { break }
		ancestor = os.dir(ancestor)
	}
}

fn write_private(path string, text string) ! {
	// This V version's os.open_file ignores x; request exclusive native creation.
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('fresh private file required') }
	mut written := 0
	for written < text.len {
		n := unsafe { C.write(fd, text.str + written, u64(text.len - written)) }
		if n <= 0 { C.close(fd); return error('output write failed') }
		written += int(n)
	}
	if C.close(fd) != 0 { return error('output close failed') }
	if read_bounded(path, archive_limit)! != text { return error('output readback mismatch') }
}

fn reconstruct(serial string, plan_path string, output string) ! {
	external(output)!
	raw := read_bounded(serial, raw_limit)!
	plan_text := read_bounded(plan_path, 65536)!
	plan := json2.decode[Plan](plan_text)!
	payload := derived_payload(raw, plan)!
	archive := validate(payload)!
	// Recheck the complete immutable inputs before creating any output.
	if read_bounded(serial, raw_limit)! != raw || read_bounded(plan_path, 65536)! != plan_text { return error('inputs changed') }
	if os.exists(output) || os.is_link(output) || unsafe { C.mkdir(output.str, 0o700) } != 0 { return error('fresh output required') }
	write_private(output + '/archive.json', payload)!
	for entry in archive.entries {
		if entry.kind == 'regular' && entry.path in ['receipt.json', 'private-log-sha256.json'] {
			write_private(output + '/exported-' + entry.path, base64.decode(entry.data).bytestr())!
		}
	}
	write_private(output + '/diagnostic.json', json2.encode({
		'kind': json2.Any('vinix-explicit-byte-removal-diagnostic-v1')
		'created_utc': json2.Any(time.utc().str())
		'raw_uart_path': json2.Any(serial)
		'raw_uart_sha256': json2.Any(plan.serial_sha256)
		'plan_path': json2.Any(plan_path)
		'plan_sha256': json2.Any(hash(plan_text))
		'archive_sha256': json2.Any(plan.archive_sha256)
		'archive_bytes': json2.Any(plan.archive_bytes)
		'archive_chunks': json2.Any(plan.archive_chunks)
		'entries': json2.Any(archive.entries.len)
		'removals': json2.Any(plan.removals.len)
		'scope': json2.Any('Derived diagnostic only; original strict UART collection failed. Private app logs excluded. No strict import, authentication or Maps success claim.')
	}, prettify: true) + '\n')!
	println('DIAGNOSTIC DERIVATION PASS archive=' + plan.archive_sha256 + ' entries=' + archive.entries.len.str())
}

fn frames(payload string) string {
	sha := hash(payload)
	count := (payload.len + 511) / 512
	mut result := prefix + 'BEGIN ' + sha + ' ' + payload.len.str() + ' ' + count.str() + '\n'
	for index in 0 .. count {
		end := int_min((index + 1) * 512, payload.len)
		result += prefix + 'CHUNK ' + sha + ' ' + index.str() + ' ' + base64.encode(payload[index * 512..end].bytes()) + '\n'
	}
	return result + prefix + 'END ' + sha + ' ' + payload.len.str() + ' ' + count.str() + '\n'
}

fn expect_rejection(raw string, plan Plan, expected string) ! {
	_ := derived_payload(raw, plan) or {
		if err.msg() != expected { return error('wrong guard: expected ' + expected + ', got ' + err.msg()) }
		return
	}
	return error('expected rejection: ' + expected)
}

fn self_test() ! {
	data := 'bounded diagnostic fixture'.repeat(40)
	entry := Entry{path: 'receipt.json', kind: 'regular', mode: 0o600, size: u64(data.len), sha256: hash(data), data: base64.encode(data.bytes())}
	payload := json2.encode(Archive{version: 1, root_mode: 0o700, entries: [entry]})
	clean := frames(payload)
	at := (clean.index('CHUNK ') or { return error('fixture chunk absent') }) + ('CHUNK ' + hash(payload) + ' 0 ').len + 70
	noise := 'exec: diagnostic insertion\r\n'
	raw := clean[..at] + noise + clean[at..]
	plan := Plan{version: 1, serial_sha256: hash(raw), archive_sha256: hash(payload), archive_bytes: payload.len,
		archive_chunks: (payload.len + 511) / 512, removals: [Removal{offset: at, expected: noise}]}
	assert derived_payload(raw, plan)! == payload
	assert validate(payload)!.entries == [entry]
	// Two separate inserted fragments preserve payload between them.
	split := clean[..at] + 'EL' + clean[at..at + 11] + 'F auxval: diagnostic\r\n' + clean[at + 11..]
	split_plan := Plan{...plan, serial_sha256: hash(split), removals: [
		Removal{offset: at, expected: 'EL'}, Removal{offset: at + 13, expected: 'F auxval: diagnostic\r\n'}]}
	assert derived_payload(split, split_plan)! == payload
	mut rejected := 0
	for bad in [Plan{...plan, serial_sha256: '0'.repeat(64)}, Plan{...plan, archive_sha256: '0'.repeat(64)},
		Plan{...plan, archive_bytes: plan.archive_bytes + 1}, Plan{...plan, archive_chunks: plan.archive_chunks + 1},
		Plan{...plan, removals: []}, Plan{...plan, removals: [Removal{offset: at + 1, expected: noise}]},
		Plan{...plan, removals: [plan.removals[0], plan.removals[0]]},
		Plan{...plan, removals: [Removal{offset: -1, expected: noise}]},
		Plan{...plan, removals: [Removal{offset: 2147483647, expected: noise}]}] {
		if _ := derived_payload(raw, bad) { return error('malformed plan accepted') }
		rejected++
	}
	for changed in [raw + clean, raw.all_before(prefix + 'END'), raw.replace('CHUNK ', 'OTHER '),
		raw.replace(' 1 ', ' 0 '), raw.replace('END ', 'END  ')] {
		candidate := Plan{...plan, serial_sha256: hash(changed)}
		if _ := derived_payload(changed, candidate) { return error('damaged export accepted') }
		rejected++
	}
	// Reinsert noise at its changed position, so these exercise framing guards
	// rather than failing because an old byte-removal offset no longer matches.
	for specimen in [
		{'text': 'foreign ' + clean, 'error': 'embedded raw frame'},
		{'text': clean.replace('BEGIN ', 'BEGIN 0'), 'error': 'original frame header rejected'},
		{'text': clean.replace('CHUNK ', 'VINIX-BROWSER-RESULTS-1 CHUNK '), 'error': 'foreign raw frame'}
	] {
		changed_clean := specimen['text']
		changed_at := (changed_clean.index('CHUNK ' + hash(payload) + ' 0 ') or { return error('changed fixture chunk absent') }) + ('CHUNK ' + hash(payload) + ' 0 ').len + 70
		changed := changed_clean[..changed_at] + noise + changed_clean[changed_at..]
		candidate := Plan{...plan, serial_sha256: hash(changed), removals: [Removal{offset: changed_at, expected: noise}]}
		expect_rejection(changed, candidate, specimen['error'])!
		rejected++
	}
	// Prefix fragments in adjacent removals cannot erase an extra original frame.
	extra := prefix + 'junk '
	prefix_raw := extra + clean
	prefix_plan := Plan{...plan, serial_sha256: hash(prefix_raw), removals: [
		Removal{offset: 0, expected: 'VIN'}, Removal{offset: 3, expected: extra[3..]}]}
	expect_rejection(prefix_raw, prefix_plan, 'original frame header rejected')!
	rejected++
	// Even an exact deletion of ordinary header bytes is disallowed.
	chunk_at := clean.index(prefix + 'CHUNK ') or { return error('fixture header absent') }
	header_plan := Plan{...plan, serial_sha256: hash(clean), removals: [Removal{offset: chunk_at + prefix.len, expected: 'C'}]}
	expect_rejection(clean, header_plan, 'nonexact, overlapping or invalid byte removal')!
	rejected++
	for bad in [Entry{...entry, path: '../x'}, Entry{...entry, path: 'broker.log'}, Entry{...entry, path: 'missing/x'},
		Entry{...entry, sha256: '0'.repeat(64)}, Entry{...entry, size: entry.size + 1}, Entry{...entry, data: entry.data + 'A'},
		Entry{...entry, mode: 0o1000}, Entry{...entry, kind: 'device'}] {
		if _ := validate(json2.encode(Archive{version: 1, root_mode: 0o700, entries: [bad]})) { return error('bad archive accepted') }
		rejected++
	}
	if _ := validate(json2.encode(Archive{version: 1, root_mode: 0o700, entries: [entry, entry]})) { return error('duplicate accepted') }
	// Exercise actual buffered file close/readback, not just the pure parser.
	fixture_dir := os.real_path(os.temp_dir()) + '/vinix-uart-diagnostic-' + os.getpid().str() + '-' + time.now().unix_nano().str()
	external(fixture_dir)!
	if unsafe { C.mkdir(fixture_dir.str, 0o700) } != 0 { return error('self-test directory creation failed') }
	defer { os.rmdir_all(fixture_dir) or {} }
	write_private(fixture_dir + '/readback', data.repeat(8))!
	if _ := write_private(fixture_dir + '/readback', data) { return error('existing output accepted') }
	println('DIAGNOSTIC SELF-TEST PASS positive=4 rejected=' + (rejected + 2).str())
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test()!; return }
	if os.args.len == 5 && os.args[1] == '--find' {
		raw := read_bounded(os.args[2], raw_limit)!
		if !digest(os.args[3]) || hash(raw) != os.args[3] || os.args[4] == '' || os.args[4].len > 512 { return error('find bounds/pin rejected') }
		mut found := []int{}
		mut start := 0
		for start < raw.len {
			pos := raw[start..].index(os.args[4]) or { break }
			found << start + pos
			start += pos + os.args[4].len
		}
		println(json2.encode(found))
		return
	}
	if os.args.len != 4 { return error('usage: diagnostic-uart-reconstruct SERIAL PLAN_JSON FRESH_OUTPUT | --self-test | --find SERIAL SHA256 LITERAL') }
	reconstruct(os.args[1], os.args[2], os.args[3])!
}

fn main() { run() or { eprintln(err); exit(1) } }
