// SPDX-License-Identifier: GPL-2.0-or-later
// Metadata-only framing audit; never an import or byte repair.
module main
import crypto.sha256
import json2
import os
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
fn C.open(&char, int, ...int) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.close(int) int
fn C.fstat(int, &C.stat) int
const raw_limit = 8 * 1024 * 1024
const archive_limit = 4 * 1024 * 1024
const prefix = 'VINIX-MAPS-ACCOUNT-RESULTS-1 '

struct FrameAnomaly {
	offset int
	line int
	frame int
	chunk int = -1
	kind string
	control int = -1
	expected_chunk int = -1
}
struct Report {
	scope string = 'Metadata-only diagnostic; no payload output, import, removal or archive-success claim.'
	raw_sha256 string
	raw_bytes int
	frame_prefix string = prefix
mut:
	frames int
	chunks_seen int
	archive_sha256 string
	archive_bytes int
	archive_chunks int
	metadata_ready bool
	bounds_ready bool
	signals []FrameAnomaly
}
struct Removal {
	offset int
	expected string
}
struct Plan {
	version int = 2
	frame_prefix string = prefix
	serial_sha256 string
	archive_sha256 string
	archive_bytes int
	archive_chunks int
	removals []Removal
}
fn pin(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}
fn decimal(value string, limit int) !int {
	if value == '' || value.len > 10 || (value.len > 1 && value[0] == `0`)
		|| !value.bytes().all(it >= `0` && it <= `9`) || value.u64() > u64(limit) {
		return error('invalid bounded decimal')
	}
	return value.int()
}
fn signal(mut report Report, item FrameAnomaly) ! {
	if report.signals.len >= 64 { return error('more than 64 anomalies; audit output bound reached') }
	report.signals << item
}

fn inspect(raw string) !Report {
	if raw.len == 0 || raw.len > raw_limit { return error('bounded nonempty UART required') }
	mut report := Report{raw_sha256: sha256.hexhash(raw), raw_bytes: raw.len}
	mut begun := false
	mut ended := false
	mut headers_valid := true
	mut end_bounds_valid := false
	mut next_chunk := 0
	mut base := 0
	lines := raw.split('\n')
	for ordinal, raw_line in lines {
		line_base := base
		base += raw_line.len + 1
		line := if raw_line.ends_with('\r') { raw_line[..raw_line.len - 1] } else { raw_line }
		if !line.contains(prefix) { continue }
		if line.count(prefix) != 1 { return error('multiple selected prefixes on one physical line') }
		frame := report.frames
		report.frames++
		if report.frames > (archive_limit + 511) / 512 + 2 || line.len > 4096 {
			return error('frame count or physical frame length exceeds audit bound')
		}
		if !line.starts_with(prefix) {
			headers_valid = false
			position := line.index(prefix) or { return error('prefix disappeared') }
			signal(mut report, FrameAnomaly{offset: line_base + position, line: ordinal + 1, frame: frame, kind: 'embedded_prefix'})!
			continue
		}
		fields := line[prefix.len..].split(' ')
		mut chunk := -1
		if fields.len >= 3 && fields[0] == 'CHUNK' {
			chunk = decimal(fields[2], (archive_limit + 511) / 512) or { -1 }
		}
		for index, value in line.bytes() {
			if value < 32 || value == 127 {
				signal(mut report, FrameAnomaly{offset: line_base + index, line: ordinal + 1, frame: frame,
					chunk: chunk, kind: 'interior_control', control: int(value)})!
			}
		}
		// Match the strict parser's CR/LF split without exposing the line.
		strict_lines := line.split_into_lines()
		strict_head := if strict_lines.len > 0 { strict_lines[0] } else { line }
		rest := strict_head[prefix.len..]
		if rest == '' {
			signal(mut report, FrameAnomaly{offset: line_base + prefix.len, line: ordinal + 1,
				frame: frame, chunk: chunk, kind: 'strict_empty_space_field'})!
		}
		for index, value in rest.bytes() {
			if value != ` ` { continue }
			if index == 0 || rest[index - 1] == ` ` {
				signal(mut report, FrameAnomaly{offset: line_base + prefix.len + index, line: ordinal + 1,
					frame: frame, chunk: chunk, kind: 'strict_empty_space_field'})!
			}
			if index + 1 == rest.len {
				signal(mut report, FrameAnomaly{offset: line_base + strict_head.len, line: ordinal + 1,
					frame: frame, chunk: chunk, kind: 'strict_empty_space_field'})!
			}
		}
		if ordinal + 1 == lines.len {
			headers_valid = false
			signal(mut report, FrameAnomaly{offset: line_base + raw_line.len, line: ordinal + 1, frame: frame,
				chunk: chunk, kind: 'missing_final_lf'})!
		}
		if fields.len < 3 || fields[1] == '' { headers_valid = false; continue }
		match fields[0] {
			'BEGIN' {
				if begun || ended || fields.len != 4 || !pin(fields[1]) { headers_valid = false; continue }
				bytes := decimal(fields[2], archive_limit) or { headers_valid = false; continue }
				chunks := decimal(fields[3], (archive_limit + 511) / 512) or { headers_valid = false; continue }
				if bytes == 0 || chunks != (bytes + 511) / 512 { headers_valid = false; continue }
				report.archive_sha256 = fields[1]
				report.archive_bytes = bytes
				report.archive_chunks = chunks
				begun = true
			}
			'CHUNK' {
				if chunk != next_chunk {
					signal(mut report, FrameAnomaly{offset: line_base, line: ordinal + 1, frame: frame,
						chunk: chunk, expected_chunk: next_chunk, kind: 'chunk_index_sequence_mismatch'})!
				}
				if !begun || ended || fields[1] != report.archive_sha256 || chunk != next_chunk {
					headers_valid = false
				}
				if chunk >= 0 { next_chunk = chunk + 1 }
				report.chunks_seen++
			}
			'END' {
				if !begun || ended || fields.len != 4 || fields[1] != report.archive_sha256
					|| fields[2] != report.archive_bytes.str() || fields[3] != report.archive_chunks.str() {
					headers_valid = false
				} else {
					end_bounds_valid = true
				}
				ended = true
			}
			else { headers_valid = false }
		}
	}
	report.metadata_ready = headers_valid && begun && ended && report.chunks_seen == report.archive_chunks
		&& report.frames == report.archive_chunks + 2
	// Bounds alone can form an explicit empty-removal diagnostic plan. They do
	// not qualify frame completeness; the unchanged reconstructor decides it.
	report.bounds_ready = begun && ended && end_bounds_valid
		&& raw.count(prefix + 'BEGIN ') == 1 && raw.count(prefix + 'END ') == 1
	return report
}

fn immutable(path string) !string {
	if !os.is_abs_path(path) || os.real_path(path) != path { return error('canonical immutable input required') }
	fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('input open failed') }
	defer { C.close(fd) }
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 || st.st_mode & C.S_IFMT != C.S_IFREG || st.st_nlink != 1
		|| st.st_mode & 0o777 != 0o400 || st.st_size <= 0 || st.st_size > raw_limit {
		return error('single-link mode-0400 regular bounded input required')
	}
	mut bytes := []u8{len: int(st.st_size)}
	mut at := 0
	for at < bytes.len {
		n := unsafe { C.read(fd, &u8(bytes.data) + at, usize(bytes.len - at)) }
		if n <= 0 { return error('input truncated') }
		at += int(n)
	}
	mut extra := u8(0)
	if C.read(fd, &extra, 1) != 0 { return error('input changed size') }
	return bytes.bytestr()
}

fn write_fresh(path string, data string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o400)
	if fd < 0 { return error('fresh output file required') }
	mut at := 0
	for at < data.len {
		n := unsafe { C.write(fd, data.str + at, usize(data.len - at)) }
		if n <= 0 { C.close(fd); return error('output write failed') }
		at += int(n)
	}
	if C.close(fd) != 0 || immutable(path)! != data { return error('output close/readback differs') }
}

fn self_test() ! {
	digest := 'a'.repeat(64)
	frame := prefix + 'BEGIN ${digest} 2 1\r\n' + prefix + 'CHUNK ${digest} 0 e30=\r\n'
		+ prefix + 'END ${digest} 2 1\r\n'
	good := inspect(frame)!
	assert good.metadata_ready && good.frames == 3 && good.signals.len == 0
	damaged := frame.replace('0 e30=', '0 \rNOISE\r\r\ne30=')
	bad := inspect(damaged)!
	assert bad.metadata_ready && bad.frames == 3 && bad.signals.len == 3
	assert bad.signals.filter(it.kind == 'interior_control').len == 2
	assert bad.signals.filter(it.kind == 'strict_empty_space_field').len == 1
	assert bad.signals.all(it.chunk == 0)
	for text in [frame + frame, frame.replace(' 2 1', ' 02 1'), frame.replace('CHUNK ${digest} 0', 'CHUNK ${digest} 1'),
		frame.replace('END ${digest}', 'END ' + 'b'.repeat(64)), frame.all_before(prefix + 'END'),
		frame.trim_right('\r\n'), 'chatter ' + frame] {
		assert !inspect(text)!.metadata_ready
	}
	assert !json2.encode(bad).contains('NOISE') && !json2.encode(bad).contains('e30=')
	embedded := inspect('chatter ' + frame)!
	assert embedded.signals[0].offset == 8 && embedded.signals[0].kind == 'embedded_prefix'
	chunk_at := frame.index(prefix + 'CHUNK') or { return error('fixture chunk absent') }
	leading := inspect(frame.replace(prefix + 'CHUNK', prefix + ' CHUNK'))!
	assert leading.signals[0].offset == chunk_at + prefix.len
	repeated := inspect(frame.replace('CHUNK ', 'CHUNK  '))!
	assert repeated.signals[0].offset == chunk_at + prefix.len + 'CHUNK '.len
	trailing := inspect(frame.replace('e30=', 'e30= '))!
	assert trailing.signals[0].offset == (frame.index('e30=') or { 0 }) + 5
	if _ := inspect(frame.replace('e30=', prefix + 'e30=')) { return error('multiple prefixes accepted') }
	prefix_only := inspect(prefix + '\n')!
	assert prefix_only.signals.len == 1 && !prefix_only.bounds_ready
	missing := inspect(frame.replace(prefix + 'CHUNK ${digest} 0 e30=\r\n', ''))!
	assert missing.bounds_ready && !missing.metadata_ready && missing.chunks_seen == 0
	println('UART-FRAME-AUDIT SELFTEST PASS metadata-only controls empty-fields header-count decimal order final-LF no-payload-output')
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test()!; return }
	if os.args.len != 5 || os.args[1] != '--maps-account' { return error('usage: uart-frame-audit --maps-account IMMUTABLE_UART SHA256 FRESH_OUTPUT | --self-test') }
	raw := immutable(os.args[2])!
	if !pin(os.args[3]) || sha256.hexhash(raw) != os.args[3] { return error('explicit input SHA256 differs') }
	output := os.args[4]
	if !os.is_abs_path(output) || os.real_path(os.dir(output)) != os.dir(output)
		|| output != os.dir(output) + '/' + os.file_name(output) || output.contains_any('\x00\r\n\\')
		|| os.file_name(output) in ['', '.', '..'] { return error('canonical fresh external output required') }
	mut ancestor := os.dir(output)
	for {
		if os.exists(ancestor + '/.git') { return error('output inside checkout rejected') }
		if ancestor == '/' { break }
		ancestor = os.dir(ancestor)
	}
	result := inspect(raw)!
	if immutable(os.args[2])! != raw { return error('input changed during audit') }
	if C.mkdir(output.str, 0o700) != 0 { return error('fresh output required') }
	write_fresh(output + '/audit.json', json2.encode(result, prettify: true) + '\n')!
	if result.bounds_ready {
		write_fresh(output + '/zero-removal-plan.json', json2.encode(Plan{
			serial_sha256: result.raw_sha256, archive_sha256: result.archive_sha256,
			archive_bytes: result.archive_bytes, archive_chunks: result.archive_chunks}, prettify: true) + '\n')!
	}
	println('UART-FRAME-AUDIT PASS frames=' + result.frames.str() + ' anomalies=' + result.signals.len.str()
		+ ' metadata_ready=' + result.metadata_ready.str() + '; diagnostic only, no archive success claim')
}

fn main() { run() or { eprintln(err); exit(1) } }
