// SPDX-License-Identifier: GPL-2.0-or-later
// Metadata-only audit; checksum-attested deletion plans remain diagnostic.
module main

import crypto.sha256
import encoding.base64
import os

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

fn C.open(&char, int, ...int) int
fn C.read(int, voidptr, u64) i64
fn C.write(int, voidptr, u64) i64
fn C.close(int) int
fn C.fstat(int, &C.stat) int
fn C.mkdir(&char, int) int
fn C.mkfifo(&char, u32) i32

const raw_limit = 8 * 1024 * 1024
const archive_limit = 4 * 1024 * 1024
const selected = 'VINIX-MAPS-ACCOUNT-RESULTS-1 '
const prefixes = ['VINIX-BROWSER-RESULTS-1 ', 'VINIX-HEADLESS-RESULTS-1 ', 'VINIX-ACCOUNT-UI-RESULTS-1 ',
	selected, 'VINIX-ACCOUNT-TOKEN-CACHE-RESULTS-1 ', 'VINIX-SERVICE-QUERY-RESULTS-1 ']

struct Frame {
	start      int
	line       int
	end        int
	terminated bool
}

struct Anomaly {
	classification         string = 'noncanonical CHUNK payload'
	chunk_index            int
	line                   int
	frame_offset           int
	physical_line_bytes    int
	physical_fields        int
	payload_offset         int
	payload_span_bytes     int
	payload_span_sha256    string
	expected_encoded_bytes int
	nonalphabet_bytes      int
	nonalphabet_codes      []int
}

struct Removal {
	offset   int
	expected string
}

struct Plan {
	version        int    = 2
	frame_prefix   string = selected
	serial_sha256  string
	archive_sha256 string
	archive_bytes  int
	archive_chunks int
	removals       []Removal
}

struct Report {
	version       int    = 1
	semantics     string = 'metadata-only audit; any plan is a diagnostic derivation, never strict import'
	serial_sha256 string
	serial_bytes  int
mut:
	status             string = 'unrecoverable'
	reason             string
	archive_sha256     string
	archive_bytes      int
	archive_chunks     int
	selected_frames    int
	anomalies          []Anomaly
	matching_deletions int
	removal_offset     int = -1
	removal_bytes      int
	removal_sha256     string
	plan_sha256        string
}

struct Analysis {
	report   Report
	plan     Plan
	has_plan bool
}

fn hash(raw string) string { return sha256.sum(raw.bytes()).hex() }

// Only the private, bounded, ASCII removal text needs escaping. All other
// serialized strings are fixed labels or already validated lowercase digests.
fn quoted_ascii(value string) string {
	mut bytes := []u8{cap: value.len * 2 + 2}
	bytes << `"`
	for c in value.bytes() {
		match c {
			`"` {
				bytes << `\\`
				bytes << `"`
			}
			`\\` {
				bytes << `\\`
				bytes << `\\`
			}
			`\t` {
				bytes << `\\`
				bytes << `t`
			}
			`\r` {
				bytes << `\\`
				bytes << `r`
			}
			`\n` {
				bytes << `\\`
				bytes << `n`
			}
			else { bytes << c }
		}
	}
	bytes << `"`
	return bytes.bytestr()
}

fn plan_text(plan Plan) string {
	mut removals := []string{cap: plan.removals.len}
	for item in plan.removals {
		removals << '{"offset":${item.offset},"expected":' + quoted_ascii(item.expected) + '}'
	}
	return '{"version":2,"frame_prefix":"${selected}","serial_sha256":"${plan.serial_sha256}","archive_sha256":"${plan.archive_sha256}","archive_bytes":${plan.archive_bytes},"archive_chunks":${plan.archive_chunks},"removals":[' + removals.join(',') + ']}\n'
}

fn report_text(report Report) string {
	mut anomalies := []string{cap: report.anomalies.len}
	for item in report.anomalies {
		codes := item.nonalphabet_codes.map(it.str()).join(',')
		anomalies << '{"classification":"noncanonical CHUNK payload","chunk_index":${item.chunk_index},"line":${item.line},"frame_offset":${item.frame_offset},"physical_line_bytes":${item.physical_line_bytes},"physical_fields":${item.physical_fields},"payload_offset":${item.payload_offset},"payload_span_bytes":${item.payload_span_bytes},"payload_span_sha256":"${item.payload_span_sha256}","expected_encoded_bytes":${item.expected_encoded_bytes},"nonalphabet_bytes":${item.nonalphabet_bytes},"nonalphabet_codes":[${codes}]}'
	}
	return '{"version":1,"semantics":"metadata-only audit; any plan is a diagnostic derivation, never strict import","serial_sha256":"${report.serial_sha256}","serial_bytes":${report.serial_bytes},"status":"${report.status}","reason":"${report.reason}","archive_sha256":"${report.archive_sha256}","archive_bytes":${report.archive_bytes},"archive_chunks":${report.archive_chunks},"selected_frames":${report.selected_frames},"anomalies":[' + anomalies.join(',') + '],"matching_deletions":${report.matching_deletions},"removal_offset":${report.removal_offset},"removal_bytes":${report.removal_bytes},"removal_sha256":"${report.removal_sha256}","plan_sha256":"${report.plan_sha256}"}\n'
}

fn digest(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn decimal(value string, limit int) !int {
	if value == '' || value.len > 10 || (value.len > 1 && value[0] == `0`)
		|| !value.bytes().all(it >= `0` && it <= `9`) || value.u64() > u64(limit) {
		return error('noncanonical decimal')
	}
	return value.int()
}

fn alphabet(c u8) bool {
	return (c >= `A` && c <= `Z`) || (c >= `a` && c <= `z`)
		|| (c >= `0` && c <= `9`) || c in [`+`, `/`, `=`]
}

fn canonical(payload string, expected int) bool {
	if payload.len != ((expected + 2) / 3) * 4 || !payload.bytes().all(alphabet(it)) {
		return false
	}
	decoded := base64.decode(payload)
	return decoded.len == expected && base64.encode(decoded) == payload
}

fn line_text(raw string, frame Frame) string {
	mut end := frame.end
	if end > frame.start && raw[end - 1] == `\r` { end-- }
	return raw[frame.start..end]
}

fn field_count(text string) int {
	mut count := 1
	for index in selected.len .. text.len {
		if text[index] == ` ` { count++ }
	}
	return count
}

fn scan(raw string) ![]Frame {
	mut frames := []Frame{}
	mut at := 0
	mut line := 1
	for at < raw.len {
		end := raw.index_after('\n', at) or { raw.len }
		text := raw[at..end]
		for known in prefixes {
			if pos := text.index(known) {
				if pos != 0 { return error('embedded known export prefix') }
			}
		}
		if text.starts_with(selected) {
			frames << Frame{at, line, end, end < raw.len}
			if frames.len > (archive_limit + 511) / 512 + 2 { return error('frame count bound') }
		}
		at = end + 1
		line++
	}
	return frames
}

// Enumerate exact offsets, never infer deletion boundaries from console text.
// A plan requires one unique deletion yielding the complete advertised archive.
fn analyze(raw string, pin string) !Analysis {
	mut report := Report{ serial_sha256: pin, serial_bytes: raw.len }
	frames := scan(raw) or {
		report.reason = err.msg()
		return Analysis{ report: report }
	}
	report.selected_frames = frames.len
	if frames.len < 3 {
		report.reason = 'incomplete selected export'
		return Analysis{ report: report }
	}
	first := line_text(raw, frames[0])
	if first.len > 128 {
		report.reason = 'oversized BEGIN'
		return Analysis{ report: report }
	}
	fields := first[selected.len..].split(' ')
	if !frames[0].terminated || fields.len != 4 || fields[0] != 'BEGIN' || !digest(fields[1]) {
		report.reason = 'noncanonical BEGIN'
		return Analysis{ report: report }
	}
	bytes := decimal(fields[2], archive_limit) or {
		report.reason = 'noncanonical BEGIN size'
		return Analysis{ report: report }
	}
	chunks := decimal(fields[3], (archive_limit + 511) / 512) or {
		report.reason = 'noncanonical BEGIN chunks'
		return Analysis{ report: report }
	}
	if bytes <= 0 || chunks != (bytes + 511) / 512 || frames.len != chunks + 2 {
		report.reason = 'archive bounds or selected frame count'
		return Analysis{ report: report }
	}
	report.archive_sha256 = fields[1]
	report.archive_bytes = bytes
	report.archive_chunks = chunks
	last := line_text(raw, frames.last())
	if !frames.last().terminated || last != selected + 'END ${fields[1]} ${bytes} ${chunks}' {
		report.reason = 'noncanonical END'
		return Analysis{ report: report }
	}
	selection := raw[frames[0].start..frames.last().end]
	for known in prefixes {
		if known != selected && selection.contains(known) {
			report.reason = 'foreign selected export'
			return Analysis{ report: report }
		}
	}
	mut parts := []string{len: chunks}
	mut anomalous := -1
	mut span_start := 0
	mut span_end := 0
	for index in 0 .. chunks {
		frame := frames[index + 1]
		header := selected + 'CHUNK ${fields[1]} ${index} '
		if !frame.terminated || frame.end < frame.start + header.len
			|| raw[frame.start..frame.start + header.len] != header {
			report.reason = 'original CHUNK header rejected'
			return Analysis{ report: report }
		}
		text := line_text(raw, frame)
		expected := if index + 1 == chunks { bytes - index * 512 } else { 512 }
		payload := text[header.len..]
		if canonical(payload, expected) {
			parts[index] = base64.decode(payload).bytestr()
			continue
		}
		// Preserve the final frame newline. Interior line breaks may only be
		// removed inside a uniquely checksum-attested insertion.
		start := frame.start + header.len
		mut end := frames[index + 2].start
		if end <= start || raw[end - 1] != `\n` {
			report.reason = 'payload boundary rejected'
			return Analysis{ report: report }
		}
		end--
		if end > start && raw[end - 1] == `\r` { end-- }
		span := raw[start..end]
		mut codes := []int{}
		mut invalid := 0
		for c in span.bytes() {
			if !alphabet(c) {
				invalid++
				if int(c) !in codes { codes << int(c) }
			}
		}
		codes.sort()
		report.anomalies << Anomaly{
			chunk_index:            index
			line:                   frame.line
			frame_offset:           frame.start
			physical_line_bytes:    text.len
			physical_fields:        field_count(text)
			payload_offset:         start
			payload_span_bytes:     span.len
			payload_span_sha256:    hash(span)
			expected_encoded_bytes: ((expected + 2) / 3) * 4
			nonalphabet_bytes:      invalid
			nonalphabet_codes:      codes
		}
		anomalous = index
		span_start = start
		span_end = end
	}
	base_plan := Plan{ serial_sha256: pin, archive_sha256: fields[1], archive_bytes: bytes, archive_chunks: chunks }
	if report.anomalies.len == 0 {
		if hash(parts.join('')) != fields[1] {
			report.reason = 'archive digest mismatch'
			return Analysis{ report: report }
		}
		report.status = 'canonical'
		report.reason = 'all selected frames and complete archive digest verified'
		return Analysis{report, base_plan, true}
	}
	if report.anomalies.len != 1 {
		report.reason = 'multiple anomalous chunks'
		return Analysis{ report: report }
	}
	anomaly := report.anomalies[0]
	span := raw[span_start..span_end]
	excess := span.len - anomaly.expected_encoded_bytes
	if excess <= 0 || excess > 512 || anomaly.nonalphabet_bytes == 0 {
		report.reason = 'single insertion bounds rejected'
		return Analysis{ report: report }
	}
	expected := if anomalous + 1 == chunks { bytes - anomalous * 512 } else { 512 }
	mut chosen := Removal{}
	for offset in 0 .. anomaly.expected_encoded_bytes + 1 {
		removed := span[offset..offset + excess]
		if removed.contains('VINIX-') || removed.bytes().all(alphabet(it))
			|| !removed.bytes().all((it >= 32 && it <= 126) || it in [`\t`, `\r`, `\n`]) {
			continue
		}
		candidate := span[..offset] + span[offset + excess..]
		if !canonical(candidate, expected) { continue }
		parts[anomalous] = base64.decode(candidate).bytestr()
		if hash(parts.join('')) != fields[1] { continue }
		report.matching_deletions++
		chosen = Removal{span_start + offset, removed}
	}
	if report.matching_deletions != 1 {
		report.reason = 'no unique archive-digest-attested deletion'
		return Analysis{ report: report }
	}
	report.status = 'diagnostic-plan'
	report.reason = 'one exact insertion uniquely attested by complete original archive digest'
	report.removal_offset = chosen.offset
	report.removal_bytes = chosen.expected.len
	report.removal_sha256 = hash(chosen.expected)
	return Analysis{report, Plan{ ...base_plan, removals: [chosen] }, true}
}

fn read_immutable(path string) !string {
	if !os.is_abs_path(path) || os.real_path(path) != path {
		return error('canonical input required')
	}
	fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('input open failed') }
	defer { C.close(fd) }
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 || st.st_mode & C.S_IFMT != C.S_IFREG || st.st_nlink != 1
		|| st.st_mode & 0o777 != 0o400 || st.st_size <= 0 || st.st_size > raw_limit {
		return error('immutable regular input bounds rejected')
	}
	mut bytes := []u8{len: int(st.st_size)}
	mut at := 0
	for at < bytes.len {
		n := unsafe { C.read(fd, &u8(bytes.data) + at, u64(bytes.len - at)) }
		if n <= 0 { return error('input truncated or read failed') }
		at += int(n)
	}
	mut extra := u8(0)
	if C.read(fd, &extra, 1) != 0 { return error('input changed size') }
	mut after := C.stat{}
	if C.fstat(fd, &after) != 0 || after.st_dev != st.st_dev || after.st_ino != st.st_ino
		|| after.st_size != st.st_size || after.st_nlink != 1 || after.st_mode != st.st_mode {
		return error('input metadata changed')
	}
	return bytes.bytestr()
}

fn external(path string) ! {
	parent := os.dir(path)
	if !os.is_abs_path(path) || os.real_path(parent) != parent || path.ends_with('/')
		|| parent + '/' + os.file_name(path) != path || os.file_name(path) in ['', '.', '..']
		|| path.contains_any('\x00\r\n\\') {
		return error('canonical external output required')
	}
	mut ancestor := parent
	for {
		if os.exists(ancestor + '/.git') { return error('output inside checkout rejected') }
		if ancestor == '/' { break }
		ancestor = os.dir(ancestor)
	}
}

fn write_fresh(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o400)
	if fd < 0 { return error('fresh output required') }
	mut at := 0
	for at < text.len {
		n := unsafe { C.write(fd, text.str + at, u64(text.len - at)) }
		if n <= 0 {
			C.close(fd)
			return error('output write failed')
		}
		at += int(n)
	}
	if C.close(fd) != 0 { return error('output close failed') }
	if read_immutable(path)! != text { return error('output readback mismatch') }
}

fn generate(input string, pin string, output string) !Report {
	external(output)!
	if !digest(pin) { return error('explicit input digest required') }
	raw := read_immutable(input)!
	if hash(raw) != pin { return error('input pin mismatch') }
	analysis := analyze(raw, pin)!
	if read_immutable(input)! != raw { return error('input changed') }
	if C.mkdir(output.str, 0o700) != 0 { return error('fresh output directory required') }
	mut report := analysis.report
	if analysis.has_plan {
		// Removal text is private evidence, never part of the public report.
		plan := plan_text(analysis.plan)
		write_fresh(output + '/plan.json', plan)!
		report.plan_sha256 = hash(plan)
	}
	write_fresh(output + '/report.json', report_text(report))!
	return report
}

fn fixture(data string) string {
	pin := hash(data)
	chunks := (data.len + 511) / 512
	mut lines := [selected + 'BEGIN ${pin} ${data.len} ${chunks}']
	for index in 0 .. chunks {
		end := if (index + 1) * 512 < data.len { (index + 1) * 512 } else { data.len }
		lines << selected + 'CHUNK ${pin} ${index} ' + base64.encode(data[index * 512..end].bytes())
	}
	lines << selected + 'END ${pin} ${data.len} ${chunks}'
	return 'boot\r\n' + lines.join('\r\n') + '\r\nfinished\r\n'
}

fn selftest(output string) ! {
	$if prod {
		return error('assertions required for selftest')
	}
	external(output)!
	if C.mkdir(output.str, 0o700) != 0 { return error('fresh selftest directory required') }
	data := 'private archive fixture payload '.repeat(40)
	raw := fixture(data)
	clean := analyze(raw, hash(raw))!
	assert clean.has_plan && clean.report.status == 'canonical' && clean.plan.removals.len == 0
	start := raw.index(selected + 'CHUNK ') or { return error('fixture CHUNK absent') }
	header_end := start + selected.len + 'CHUNK '.len + 64 + ' 0 '.len
	at := header_end + 101
	for index, insertion in [' [console diagnostic] ', '\r\n[kernel] diagnostic\r\n'] {
		bad := raw[..at] + insertion + raw[at..]
		result := analyze(bad, hash(bad))!
		assert result.has_plan && result.report.status == 'diagnostic-plan'
		assert result.report.matching_deletions == 1 && result.plan.removals == [Removal{at, insertion}]
		public := report_text(result.report)
		assert !public.contains('console') && !public.contains('kernel') && !public.contains('private archive')
		input := output + '/input-${index}.log'
		write_fresh(input, bad)!
		report := generate(input, hash(bad), output + '/generated-${index}')!
		assert report.plan_sha256 != ''
		if _ := generate(input, '0'.repeat(64), output + '/bad-pin-${index}') {
			return error('bad pin accepted')
		}
		if _ := generate(input, hash(bad), output + '/generated-${index}') {
			return error('existing output accepted')
		}
	}
	for bad in [raw[..raw.index(selected + 'END ') or { 0 }], raw.replace('CHUNK ', 'WRONG '),
		raw[..at] + 'AAAA' + raw[at..], raw[..at] + '!' + raw[at + 1..],
		raw[..at] + '\x01!' + raw[at..], raw.replace(' 0 ', ' 00 '), raw + raw,
		raw.replace('CHUNK ', 'xCHUNK ')] {
		if result := analyze(bad, hash(bad)) {
			assert !result.has_plan
		}
	}
	second := raw.index(selected + 'CHUNK ${hash(data)} 1 ') or { return error('second fixture chunk absent') }
	two := raw[..at] + ' ! ' + raw[at..second + selected.len + 80] + ' ! ' + raw[second + selected.len + 80..]
	assert !analyze(two, hash(two))!.has_plan
	// Equal adjacent base64 characters make distinct deletion offsets yield
	// identical original bytes. Even a correct digest must not choose one.
	repeated := fixture('\x00'.repeat(512))
	repeated_start := repeated.index(selected + 'CHUNK ') or { return error('repeated fixture absent') }
	repeated_at := repeated_start + selected.len + 'CHUNK '.len + 64 + ' 0 '.len + 100
	ambiguous := repeated[..repeated_at] + ' A' + repeated[repeated_at..]
	ambiguous_result := analyze(ambiguous, hash(ambiguous))!
	assert !ambiguous_result.has_plan && ambiguous_result.report.matching_deletions > 1
	input := output + '/regular.log'
	write_fresh(input, raw)!
	os.symlink(input, output + '/link.log')!
	if _ := read_immutable(output + '/link.log') { return error('symlink accepted') }
	if C.mkfifo((output + '/fifo').str, 0o400) != 0 { return error('FIFO fixture failed') }
	if _ := read_immutable(output + '/fifo') { return error('FIFO accepted') }
	os.rm(output + '/fifo')!
	os.chmod(input, 0o600)!
	if _ := read_immutable(input) { return error('writable input accepted') }
	os.chmod(input, 0o400)!
	embedded := analyze('x' + raw.replace('boot\r\n', ''), hash(raw))!
	assert !embedded.has_plan && embedded.report.reason == 'embedded known export prefix'
	assert scan('\n'.repeat(20000))!.len == 0
	oversized := raw.replace('BEGIN ', 'BEGIN ' + ' '.repeat(20000))
	assert analyze(oversized, hash(oversized))!.report.reason == 'oversized BEGIN'
	assert quoted_ascii('"\\\t\r\n') == '"\\"\\\\\\t\\r\\n"'
	println('UART-FRAME-AUDIT SELFTEST PASS')
}

fn run() ! {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		selftest(os.args[2])!
		return
	}
	if os.args.len != 4 {
		return error('usage: uart-frame-audit IMMUTABLE_UART SHA256 FRESH_EXTERNAL_DIR | --self-test FRESH_EXTERNAL_DIR')
	}
	report := generate(os.args[1], os.args[2], os.args[3])!
	println('UART-FRAME-AUDIT PASS status=' + report.status + ' report=' + hash(read_immutable(os.args[3] + '/report.json')!))
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
