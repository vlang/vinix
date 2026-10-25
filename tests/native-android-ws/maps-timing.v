// SPDX-License-Identifier: GPL-2.0-or-later
// Summarize retained WS-TIMING231 diagnostics, never all frames or interactions.
module main

import crypto.sha256
import json2
import os
import strconv

const phase_names = ['looper', 'frame_callbacks', 'render_total', 'input', 'loop_total']
const scope_note = 'Phase statistics describe only logged WS-TIMING231 samples with duration_ms > 100. Shorter phases are unobserved, not zero.'
const overlap_note = 'Phase totals overlap: loop_total includes the other phases. Do not add their totals. The native 16 ms loop sleep is outside loop_total.'
const limits_note = 'These samples do not establish overall latency percentiles, interaction latency, frame rate, or time spent in unlogged phases.'
const input_note = 'input_done is summarized separately without a duration threshold. No samples does not establish that no input occurred; the retained Maps283 source defines this helper without a callsite. Its duration starts at native input read, not pointer-to-presentation.'
const comparison_note = 'This is a descriptive comparison of diagnostic samples from nonidentical interaction workloads. It does not isolate a causal effect or establish an overall performance change.'
const scan_note = 'Scan mode accepts a complete, strictly valid record after exactly one WS-TIMING231 marker on a line, discarding only its preceding console prefix. It rejects malformed, truncated, suffixed or multiple-marker lines without repairing them. Statistics exclude rejected lines; scan counts are not a completeness guarantee.'

struct SampleStats {
	name             string
	has_samples      bool
	count            int
	sampled_total_ms u64
	min_ms           u64
	median_ms        f64
	p95_ms           u64
	max_ms           u64
}

struct RunSummary {
	source_path        string
	source_sha256      string
	line_count         int
	phase_sample_count int
	phases             []SampleStats
	input_done         SampleStats
}

struct Analysis {
	schema            string = 'vinix.maps-timing231.v1'
	scope             string = scope_note
	phase_overlap     string = overlap_note
	limits            string = limits_note
	input_done_scope  string = input_note
	median_definition string = 'Middle value for odd counts; arithmetic mean of the two middle values for even counts.'
	p95_definition    string = 'Nearest rank: sorted sample at ceil(0.95 * count), using one-based ranks.'
	empty_definition  string = 'has_samples=false and zero numeric fields mean no logged samples, not measured zero duration.'
	comparison        string
	runs              []RunSummary
}

struct RejectedRecord {
	line   int
	reason string
}

struct ScanSummary {
	marker_line_count      int
	accepted_record_count  int
	recovered_prefix_count int
	rejected_record_count  int
	rejected_records       []RejectedRecord
}

struct ScannedAnalysis {
	schema   string = 'vinix.maps-timing231.scan.v1'
	scope    string = scan_note
	scan     ScanSummary
	analysis Analysis
}

fn natural(value string, key string) !u64 {
	if value.len == 0 || !value.bytes().all(it >= `0` && it <= `9`) {
		return error('invalid unsigned ${key}: ${value}')
	}
	return strconv.parse_uint(value, 10, 64)
}

fn signed(value string, key string) !i64 {
	digits := if value.starts_with('-') { value[1..] } else { value }
	if digits.len == 0 || !digits.bytes().all(it >= `0` && it <= `9`) {
		return error('invalid signed ${key}: ${value}')
	}
	return strconv.parse_int(value, 10, 64)
}

fn fields(tokens []string, expected []string) !map[string]string {
	mut values := map[string]string{}
	for token in tokens {
		parts := token.split('=')
		if parts.len != 2 || parts[0] !in expected || parts[0] in values {
			return error('unexpected or duplicate field: ${token}')
		}
		values[parts[0]] = parts[1]
	}
	if values.len != expected.len {
		return error('missing fields; expected ${expected.join(',')}')
	}
	return values
}

fn summarize(name string, samples []u64) !SampleStats {
	if samples.len == 0 {
		return SampleStats{ name: name }
	}
	mut sorted := samples.clone()
	sorted.sort()
	mut total := u64(0)
	for value in sorted {
		if value > ~u64(0) - total {
			return error('${name}: sampled duration total overflows u64')
		}
		total += value
	}
	middle := sorted.len / 2
	median := if sorted.len % 2 == 0 {
		f64(sorted[middle - 1]) / 2 + f64(sorted[middle]) / 2
	} else {
		f64(sorted[middle])
	}
	return SampleStats{
		name:             name
		has_samples:      true
		count:            sorted.len
		sampled_total_ms: total
		min_ms:           sorted[0]
		median_ms:        median
		p95_ms:           sorted[sorted.len - sorted.len / 20 - 1]
		max_ms:           sorted.last()
	}
}

fn parse_log(path string, raw string) !RunSummary {
	mut samples := map[string][]u64{}
	mut inputs := []u64{}
	mut phase_count := 0
	lines := raw.split_into_lines()
	for index, line in lines {
		text := line.trim_space()
		if !text.contains('WS-TIMING231') { continue }
		tokens := text.fields()
		if tokens.len < 2 || tokens[0] != 'WS-TIMING231' {
			return error('${path}:${index + 1}: malformed timing record')
		}
		if tokens[1] == 'phase' {
			values := fields(tokens[2..], ['loop', 'name', 'duration_ms', 'now_ms']) or {
				return error('${path}:${index + 1}: ${err}')
			}
			loop := natural(values['loop'], 'loop')!
			now := natural(values['now_ms'], 'now_ms')!
			duration := natural(values['duration_ms'], 'duration_ms')!
			name := values['name']
			if loop == 0 || name !in phase_names || duration <= 100 || duration > now {
				return error('${path}:${index + 1}: unsupported phase, loop, clock, or non-thresholded duration')
			}
			samples[name] << duration
			phase_count++
		} else if tokens[1] == 'input_done' {
			values := fields(tokens[2..], ['loop', 'sequence', 'now_ms', 'duration_ms', 'ready',
				'revents', 'running']) or {
				return error('${path}:${index + 1}: ${err}')
			}
			loop := natural(values['loop'], 'loop')!
			sequence := natural(values['sequence'], 'sequence')!
			now := natural(values['now_ms'], 'now_ms')!
			duration := natural(values['duration_ms'], 'duration_ms')!
			ready := signed(values['ready'], 'ready')!
			signed(values['revents'], 'revents')!
			running := signed(values['running'], 'running')!
			if loop == 0 || sequence == 0 || duration > now || ready < -1 || ready > 1 || running !in [
				i64(0),
				1,
			] {
				return error('${path}:${index + 1}: invalid input completion values')
			}
			inputs << duration
		} else {
			return error('${path}:${index + 1}: unknown timing record ${tokens[1]}')
		}
	}
	mut phases := []SampleStats{}
	for name in phase_names { phases << summarize(name, samples[name])! }
	return RunSummary{
		source_path:        path
		source_sha256:      sha256.hexhash(raw)
		line_count:         lines.len
		phase_sample_count: phase_count
		phases:             phases
		input_done:         summarize('input_done', inputs)!
	}
}

// Keep the historical parser strict. Recovery is an explicit, separately
// reported operation, and only whole validated records reach its statistics.
fn scan_log(path string, raw string) !(RunSummary, ScanSummary) {
	mut records := []string{}
	mut rejected := []RejectedRecord{}
	mut marker_lines := 0
	mut prefixed := 0
	lines := raw.split_into_lines()
	for index, line in lines {
		count := line.count('WS-TIMING231')
		if count == 0 { continue }
		marker_lines++
		if count != 1 {
			rejected << RejectedRecord{index + 1, 'multiple timing markers on one line'}
			continue
		}
		start := line.index('WS-TIMING231') or { return error('timing marker count/index disagree') }
		record := line[start..].trim_space()
		parse_log('record', record) or {
			rejected << RejectedRecord{index + 1, err.msg().all_after('record:1: ')}
			continue
		}
		records << record
		if line[..start].trim_space() != '' { prefixed++ }
	}
	parsed := parse_log(path, records.join('\n'))!
	return RunSummary{
		source_path:        path
		source_sha256:      sha256.hexhash(raw)
		line_count:         lines.len
		phase_sample_count: parsed.phase_sample_count
		phases:             parsed.phases
		input_done:         parsed.input_done
	}, ScanSummary{
		marker_line_count:      marker_lines
		accepted_record_count:  records.len
		recovered_prefix_count: prefixed
		rejected_record_count:  rejected.len
		rejected_records:       rejected
	}
}

fn stat_line(sample SampleStats) string {
	if !sample.has_samples { return '${sample.name}: count=0 (no logged samples)' }
	return '${sample.name}: count=${sample.count} sampled_total_ms=${sample.sampled_total_ms} min_ms=${sample.min_ms} median_ms=${sample.median_ms} p95_ms=${sample.p95_ms} max_ms=${sample.max_ms}'
}

fn render(analysis Analysis) string {
	mut lines := ['WS-TIMING231 diagnostic sample analysis', analysis.scope, analysis.phase_overlap,
		analysis.limits, analysis.input_done_scope, analysis.median_definition,
		analysis.p95_definition, analysis.empty_definition]
	if analysis.comparison != '' { lines << analysis.comparison }
	for run in analysis.runs {
		lines << ''
		lines << 'Source: ${run.source_path}'
		lines << 'SHA-256: ${run.source_sha256}'
		lines << 'Lines: ${run.line_count}; logged phase samples: ${run.phase_sample_count}'
		for phase in run.phases { lines << stat_line(phase) }
		lines << stat_line(run.input_done)
	}
	return lines.join('\n') + '\n'
}

fn render_scan(scan ScanSummary, analysis Analysis) string {
	mut lines := [scan_note,
		'Marker lines: ${scan.marker_line_count}; accepted records: ${scan.accepted_record_count}; recovered prefixes: ${scan.recovered_prefix_count}; rejected records: ${scan.rejected_record_count}']
	for rejected in scan.rejected_records {
		lines << 'Rejected line ${rejected.line}: ${rejected.reason}'
	}
	return lines.join('\n') + '\n\n' + render(analysis)
}

fn guard_outputs(prefix string, inputs []string) ! {
	for suffix in ['.json', '.txt'] {
		target := prefix + suffix
		if os.exists(target) && os.real_path(target) in inputs {
			return error('refusing to overwrite input log: ${target}')
		}
	}
}

fn selftest() ! {
	raw := 'unrelated\r\nWS-TIMING231 phase loop=1 name=looper duration_ms=101 now_ms=200\r\n' +
		'WS-TIMING231 phase loop=2 name=looper duration_ms=301 now_ms=600\n' +
		'WS-TIMING231 phase loop=2 name=loop_total duration_ms=400 now_ms=601\n' +
		'WS-TIMING231 input_done loop=2 sequence=1 now_ms=600 duration_ms=0 ready=0 revents=0 running=1\n'
	run := parse_log('synthetic', raw)!
	assert run.phase_sample_count == 3
	assert run.phases[0].count == 2 && run.phases[0].sampled_total_ms == 402
	assert run.phases[0].min_ms == 101 && run.phases[0].median_ms == 201
	assert run.phases[0].p95_ms == 301 && run.phases[0].max_ms == 301
	assert !run.phases[1].has_samples && run.phases[1].count == 0
	assert run.input_done.has_samples && run.input_done.min_ms == 0
	assert summarize('odd', [u64(900), 101, 202])!.median_ms == 202
	mut twenty := []u64{}
	for n in 1 .. 21 { twenty << u64(n) }
	assert summarize('rank', twenty)!.p95_ms == 19
	assert parse_log('empty', 'unrelated\n')!.phase_sample_count == 0
	for bad in [
		'WS-TIMING231 phase loop=1 name=looper duration_ms=100 now_ms=200',
		'WS-TIMING231 phase loop=0 name=looper duration_ms=101 now_ms=200',
		'WS-TIMING231 phase loop=1 name=unknown duration_ms=101 now_ms=200',
		'WS-TIMING231 phase loop=1 name=looper duration_ms=-101 now_ms=200',
		'WS-TIMING231 phase loop=1 name=looper duration_ms=201 now_ms=200',
		'WS-TIMING231 phase loop=1 name=looper duration_ms=101 now_ms=200 now_ms=201',
		'WS-TIMING231 phase loop=1 name=looper duration_ms=101',
		'WS-TIMING231 other loop=1',
		'prefix WS-TIMING231 phase loop=1 name=looper duration_ms=101 now_ms=200',
		'WS-TIMING231 input_done loop=2 sequence=0 now_ms=600 duration_ms=0 ready=0 revents=0 running=1',
	] {
		if _ := parse_log('bad', bad) { return error('accepted malformed timing: ${bad}') }
	}
	if _ := summarize('overflow', [~u64(0), u64(1)]) { return error('accepted total overflow') }
	analysis := Analysis{ comparison: comparison_note, runs: [run] }
	encoded := json2.encode(analysis, escape_unicode: true, time_as_unix: true)
	output := render(analysis)
	assert output.contains(scope_note) && output.contains(limits_note)
	assert output.contains(overlap_note) && output.contains(comparison_note)
	assert output.contains('no logged samples')
	assert !encoded.contains('overall_p95') && !encoded.contains('fps')
	assert encoded.contains('sampled_total_ms') && encoded.contains('has_samples')
	complete := 'WS-TIMING231 phase loop=3 name=render_total duration_ms=123 now_ms=700'
	interleaved := 'ordinary output\nANDROID-WS-MAPS absent' + complete + '\n' +
		complete + '\n' + complete + 'WS-TIMING231 phase\n' +
		'WS-TIMING231 phase loop=4 name=looper duration_ms=\n' +
		complete + ' trailing-console-output\n'
	scanned, scan := scan_log('interleaved', interleaved)!
	assert scanned.source_sha256 == sha256.hexhash(interleaved)
	assert scanned.line_count == interleaved.split_into_lines().len
	assert scanned.phase_sample_count == 2 && scanned.phases[2].sampled_total_ms == 246
	assert scan.marker_line_count == 5 && scan.accepted_record_count == 2
	assert scan.recovered_prefix_count == 1 && scan.rejected_record_count == 3
	assert scan.rejected_records.map(it.line) == [4, 5, 6]
	assert scan.rejected_records[0].reason == 'multiple timing markers on one line'
	assert scan.rejected_records[1].reason.contains('missing fields')
	assert scan.rejected_records[2].reason.contains('unexpected or duplicate field')
	if _ := parse_log('strict', interleaved) { return error('strict parser accepted console prefix') }
	empty_run, empty_scan := scan_log('none', 'ordinary output\n')!
	assert empty_run.phase_sample_count == 0 && empty_scan.marker_line_count == 0
	assert render_scan(scan, Analysis{runs: [scanned]}).contains('Rejected line 4:')
	temporary := os.join_path(os.temp_dir(), 'vinix-maps-timing-${os.getpid()}')
	os.mkdir_all(temporary)!
	defer { os.rmdir_all(temporary) or {} }
	input := os.join_path(temporary, 'source.json')
	os.write_file(input, raw)!
	if _ := guard_outputs(os.join_path(temporary, 'source'), [os.real_path(input)]) {
		return error('accepted output collision with input log')
	}
	assert os.read_file(input)! == raw
	guard_outputs(os.join_path(temporary, 'separate'), [os.real_path(input)])!
	println('MAPS-TIMING SELFTEST PASS: thresholded samples, ranks, empty/input records, strict parsing, explicit scan recovery/rejection and claim limits')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'selftest' {
		selftest() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	compare := os.args.len == 5 && os.args[1] == 'compare'
	scan_mode := os.args.len == 4 && os.args[1] == 'scan'
	if !compare && !scan_mode && !(os.args.len == 4 && os.args[1] == 'analyze') {
		eprintln('usage: maps-timing selftest | analyze SERIAL OUTPUT_PREFIX | scan SERIAL OUTPUT_PREFIX | compare OLD_SERIAL NEW_SERIAL OUTPUT_PREFIX')
		exit(1)
	}
	mut runs := []RunSummary{}
	mut scan := ScanSummary{}
	for path in os.args[2..os.args.len - 1] {
		absolute := os.real_path(path)
		raw := os.read_file(absolute) or {
			eprintln(err)
			exit(1)
		}
		if scan_mode {
			run, scanned := scan_log(absolute, raw) or {
				eprintln(err)
				exit(1)
			}
			runs << run
			scan = scanned
		} else {
			runs << parse_log(absolute, raw) or {
				eprintln(err)
				exit(1)
			}
		}
	}
	analysis := Analysis{ comparison: if compare { comparison_note } else { '' }, runs: runs }
	prefix := os.args.last()
	guard_outputs(prefix, runs.map(it.source_path)) or {
		eprintln(err)
		exit(1)
	}
	os.mkdir_all(os.dir(prefix)) or {
		eprintln(err)
		exit(1)
	}
	output := if scan_mode { render_scan(scan, analysis) } else { render(analysis) }
	encoded := if scan_mode {
		json2.encode(ScannedAnalysis{scan: scan, analysis: analysis},
			prettify: true, legacy_layout: true, escape_unicode: true, time_as_unix: true)
	} else {
		json2.encode(analysis,
			prettify: true, legacy_layout: true, escape_unicode: true, time_as_unix: true)
	}
	os.write_file(prefix + '.json', encoded) or {
		eprintln(err)
		exit(1)
	}
	os.write_file(prefix + '.txt', output) or {
		eprintln(err)
		exit(1)
	}
	print(output)
}
