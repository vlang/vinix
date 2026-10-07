module comparecore

import encoding.utf8
import json2
import math
import math.big
import os
import strconv

fn C.strtod(source &char, end &&char) f64
fn C.snprintf(buffer &char, size usize, format &char, ...) i32

pub const compile_flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-builtin']
pub const config_fields = ['qemu_version', 'machine', 'accelerator', 'cpu', 'smp', 'memory_mb',
	'source_sha256']
pub const meta_fields = ['schema', 'arch', 'pointer_bits', 'page_size', 'clock', 'threads', 'iterations',
	'samples', 'touch_stride', 'large_bytes', 'mixed_sizes']
const mixed_sizes = '16,32,64,96,128,256,512,1024,2048,4096,8192,16384'

pub struct Workload {
pub:
	name      string
	category  string
	operation string
	divisor   u64
	size      u64
	batch     u64
	stride    u64
}

pub const workloads = [
	Workload{'malloc_hot_64', 'userspace', 'alloc_free_pair', 1, 64, 1, 0},
	Workload{'malloc_mixed_batch_64', 'userspace', 'alloc_free_pair', 1, 0, 64, 0},
	Workload{'malloc_touch_262144', 'userspace', 'alloc_free_pair', 20, 262144, 1, 4096},
	Workload{'mmap_anon_4096', 'kernel_syscall', 'map_unmap_pair', 20, 4096, 1, 0},
	Workload{'mmap_touch_262144', 'kernel_syscall', 'map_unmap_pair', 20, 262144, 1, 4096},
	Workload{'pipe_create_close', 'kernel_syscall', 'create_close_pair', 20, 0, 1, 0},
]

// Raw numeric tokens keep JSON integers distinct from bools and floats, and
// preserve integers above 2^53 in configuration comparisons and diagnostics.
pub struct Number {
pub mut:
	text string
}

pub fn (mut n Number) from_json_number(text string) ! { n.text = text }

pub fn (n Number) to_json() string { return n.text }

pub type Value = Number | []Value | bool | json2.Null | map[string]Value | string
pub type Config = map[string]Value

pub fn decode_config(text string) !Config {
	item := json2.decode[Value](text)!
	if item is map[string]Value { return item }
	return error('config must be a JSON object')
}

fn value(data Config, key string) Value { return data[key] or { Value(json2.null) } }

fn is_integer(n Number) bool { return !n.text.contains_any('.eE') }

fn native_float(text string) f64 {
	terminated := text.clone()
	return unsafe { C.strtod(&char(terminated.str), nil) }
}

fn float_text(text string) string {
	shortest := native_float(text).str()
	if shortest == '+inf' { return 'inf' }
	if position := shortest.index('e') {
		exponent := shortest[position + 1..].int()
		if exponent >= 0 && exponent < 16 {
			mantissa := shortest[..position]
			sign := if mantissa.starts_with('-') { '-' } else { '' }
			unsigned := mantissa.trim_left('-')
			digits := unsigned.replace('.', '')
			decimal := unsigned.all_before('.').len + exponent
			if decimal >= digits.len {
				return sign + digits + '0'.repeat(decimal - digits.len) + '.0'
			}
			return sign + digits[..decimal] + '.' + digits[decimal..]
		}
	}
	return shortest
}

pub fn quoted(text string) string {
	quote := if text.contains("'") && !text.contains('"') { '"' } else { "'" }
	mut output := quote
	for r in text.runes() {
		match r {
			`\\` { output += '\\\\' }
			`\n` { output += '\\n' }
			`\r` { output += '\\r' }
			`\t` { output += '\\t' }
			else {
				if r.str() == quote {
					output += '\\' + quote
				} else if r < 32 || r == 127 {
					output += '\\x${int(r):02x}'
				} else {
					output += r.str()
				}
			}
		}
	}
	return output + quote
}

fn repr(item Value) string {
	return match item {
		string { quoted(item) }
		bool {
			if item { 'True' } else { 'False' }
		}
		json2.Null { 'None' }
		Number {
			if is_integer(item) {
				(big.integer_from_string(item.text) or { big.zero_int }).str()
			} else {
				float_text(item.text)
			}
		}
		[]Value { '[' + item.map(repr(it)).join(', ') + ']' }
		map[string]Value {
			mut parts := []string{}
			for key, entry in item { parts << quoted(key) + ': ' + repr(entry) }
			'{' + parts.join(', ') + '}'
		}
	}
}

// Python compares numeric JSON values by value, including bool/int equality.
// Keep integer comparison exact before handling a float alternative.
fn equal(a Value, b Value) bool {
	if a is Number && b is Number {
		if is_integer(a) && is_integer(b) {
			return big.integer_from_string(a.text) or { return false } ==
				big.integer_from_string(b.text) or { return false }
		}
		if is_integer(a) != is_integer(b) {
			integer := if is_integer(a) { a } else { b }
			floating := if is_integer(a) { b } else { a }
			return integer_equal_float(integer.text, native_float(floating.text))
		}
		return native_float(a.text) == native_float(b.text)
	}
	if a is bool && b is Number {
		return equal(Value(Number{if a { '1' } else { '0' }}), b)
	}
	if b is bool && a is Number { return equal(b, a) }
	if a is []Value && b is []Value {
		if a.len != b.len { return false }
		for index, entry in a { if !equal(entry, b[index]) { return false } }
		return true
	}
	if a is map[string]Value && b is map[string]Value {
		if a.len != b.len { return false }
		for key, entry in a { if key !in b || !equal(entry, value(b, key)) { return false } }
		return true
	}
	return a == b
}

fn integer_equal_float(text string, floating f64) bool {
	if math.is_nan(floating) || math.is_inf(floating, 0) { return false }
	integer := big.integer_from_string(text) or { return false }
	if floating == 0 { return integer == big.zero_int }
	bits := math.f64_bits(floating)
	exponent := int((bits >> 52) & 0x7ff) - 1023 - 52
	mantissa := big.integer_from_u64((bits & ((u64(1) << 52) - 1)) | (u64(1) << 52))
	mut actual := mantissa
	if exponent >= 0 {
		actual = mantissa.left_shift(u32(exponent))
	} else {
		actual = mantissa.right_shift(u32(-exponent))
		if actual.left_shift(u32(-exponent)) != mantissa { return false }
	}
	if bits >> 63 != 0 { actual = actual.neg() }
	return integer == actual
}

fn whitespace(r rune) bool { return utf8.is_space(r) || r in [`\x1c`, `\x1d`, `\x1e`, `\x1f`] }

fn tokens(text string) []string {
	mut parts := []string{}
	mut current := []rune{}
	for r in text.runes() {
		if whitespace(r) {
			if current.len > 0 {
				parts << current.string()
				current.clear()
			}
		} else {
			current << r
		}
	}
	if current.len > 0 { parts << current.string() }
	return parts
}

fn lines(text string) []string {
	mut parts := []string{}
	mut current := []rune{}
	mut after_cr := false
	for r in text.runes() {
		if r == `\n` && after_cr {
			after_cr = false
			continue
		}
		after_cr = r == `\r`
		if r in [`\n`, `\r`, `\v`, `\f`, `\x1c`, `\x1d`, `\x1e`, `\u0085`, `\u2028`, `\u2029`] {
			parts << current.string()
			current.clear()
		} else {
			current << r
		}
	}
	if current.len > 0 { parts << current.string() }
	return parts
}

pub fn fields(payload string, context string) !map[string]string {
	mut parsed := map[string]string{}
	for token in tokens(payload) {
		position := token.index('=') or { return error('${context}: expected key=value, got ${quoted(token)}') }
		key := token[..position]
		entry := token[position + 1..]
		if key == '' || entry == '' || key in parsed {
			return error('${context}: empty or duplicate field ${quoted(key)}')
		}
		parsed[key] = entry
	}
	return parsed
}

fn require(record map[string]string, keys []string, context string) ! {
	mut missing := keys.filter(it !in record)
	missing.sort()
	if missing.len > 0 { return error('${context}: missing fields ' + missing.join(', ')) }
}

pub fn number(record map[string]string, key string, context string, minimum u64, maximum u64) !u64 {
	text := record[key] or { '' }
	if text == '' || text.bytes().any(it < `0` || it > `9`) {
		return error('${context}: ${key} must be an unsigned integer')
	}
	parsed := strconv.parse_uint(text, 10, 64) or { return error('${context}: ${key} is outside ${minimum}..${maximum}') }
	if parsed < minimum || parsed > maximum {
		return error('${context}: ${key} is outside ${minimum}..${maximum}')
	}
	return parsed
}

fn summary(record map[string]string, key string, actual f64, context string) ! {
	text := record[key] or { return error('${context}: invalid ${key}') }
	parsed := parse_float(text) or { return error('${context}: invalid ${key}') }
	if math.is_nan(parsed) || math.is_inf(parsed, 0) || math.abs(parsed - actual) > 0.00051 {
		return error('${context}: ${key} disagrees with raw samples')
	}
}

fn parse_float(text string) !f64 {
	parts := tokens(text)
	if parts.len != 1 { return error('invalid float') }
	mut compact := ''
	for index, ch in parts[0].bytes() {
		if ch == `_` {
			if index == 0 || index + 1 >= parts[0].len || parts[0][index - 1] < `0` || parts[0][index - 1] > `9` || parts[0][index + 1] < `0` || parts[0][index + 1] > `9` {
				return error('invalid float')
			}
		} else {
			compact += ch.ascii_str()
		}
	}
	lower := if compact.starts_with('+') || compact.starts_with('-') {
		compact[1..].to_lower()
	} else {
		compact.to_lower()
	}
	if lower in ['nan', 'inf', 'infinity'] { return native_float(compact) }
	mut cursor := 0
	if compact.starts_with('+') || compact.starts_with('-') { cursor++ }
	mut digits := 0
	for cursor < compact.len && compact[cursor] >= `0` && compact[cursor] <= `9` {
		cursor++
		digits++
	}
	if cursor < compact.len && compact[cursor] == `.` {
		cursor++
		for cursor < compact.len && compact[cursor] >= `0` && compact[cursor] <= `9` {
			cursor++
			digits++
		}
	}
	if digits == 0 { return error('invalid float') }
	if cursor < compact.len && compact[cursor] in [`e`, `E`] {
		cursor++
		if cursor < compact.len && compact[cursor] in [`+`, `-`] { cursor++ }
		start := cursor
		for cursor < compact.len && compact[cursor] >= `0` && compact[cursor] <= `9` { cursor++ }
		if cursor == start { return error('invalid float') }
	}
	if cursor != compact.len { return error('invalid float') }
	return native_float(compact)
}

// Round an integer quotient once, as Python's integer true division does.
// Converting a duration above 2^53 to f64 before dividing loses a low bit.
fn ratio(numerator u64, denominator u64) f64 {
	if numerator == 0 { return 0 }
	a := big.integer_from_u64(numerator)
	b := big.integer_from_u64(denominator)
	mut exponent := 0
	if a >= b {
		for a >= b.left_shift(u32(exponent + 1)) { exponent++ }
	} else {
		for a.left_shift(u32(-exponent)) < b { exponent-- }
	}
	shift := 52 - exponent
	scaled_a := if shift >= 0 { a.left_shift(u32(shift)) } else { a }
	scaled_b := if shift >= 0 { b } else { b.left_shift(u32(-shift)) }
	quotient, remainder := scaled_a.div_mod(scaled_b)
	mut mantissa := quotient.str().u64()
	if remainder + remainder > scaled_b || (remainder + remainder == scaled_b && mantissa % 2 != 0) {
		mantissa++
	}
	return math.ldexp(f64(mantissa), exponent - 52)
}

fn median(mut values []f64) f64 {
	values.sort()
	if values.len % 2 != 0 { return values[values.len / 2] }
	return (values[values.len / 2 - 1] + values[values.len / 2]) / 2
}

pub struct Run {
pub mut:
	name    string
	meta    map[string]string
	samples map[string][]map[string]string
	results map[string]map[string]string
	done    map[string]string
	config  Config
}

pub fn (run Run) median(workload string) f64 {
	mut values := run.samples[workload].map(it['elapsed_ns'].u64())
	values.sort()
	center := values.len / 2
	pairs := run.results[workload]['pairs'].u64()
	if values.len % 2 != 0 { return ratio(values[center], pairs) }
	// The original takes a median of raw integers before dividing by pairs.
	// The sum may need 65 bits even though each duration is a bounded u64.
	sum := big.integer_from_u64(values[center - 1]) + big.integer_from_u64(values[center])
	return native_float(sum.str()) / 2 / f64(pairs)
}

pub fn parse_log(contents string, name string, config Config) !Run {
	mut run := Run{ name: name, config: config }
	for index, line in lines(contents) {
		parts := tokens(line)
		mut tag_index := -1
		for i, token in parts {
			if token.starts_with('ALLOC-') && token.len > 6 && token[6..].bytes().all(it >= `A` && it <= `Z`) {
				tag_index = i
				break
			}
		}
		if tag_index < 0 { continue }
		tag := parts[tag_index]
		context := '${name}:${index + 1} ${tag}'
		if run.done.len > 0 { return error('${context}: benchmark record after ALLOC-DONE') }
		if tag == 'ALLOC-ERROR' { return error('${context}: benchmark reported an error') }
		record := fields(parts[tag_index + 1..].join(' '), context)!
		match tag {
			'ALLOC-META' {
				if run.meta.len > 0 || run.samples.len > 0 || run.results.len > 0 {
					return error('${context}: duplicate or misplaced metadata')
				}
				run.meta = record
			}
			'ALLOC-SAMPLE', 'ALLOC-RESULT' {
				if run.meta.len == 0 {
					return error('${context}: metadata must precede measurements')
				}
				require(record, ['workload', 'label'], context)!
				workload := record['workload']
				if !workloads.any(it.name == workload) {
					return error('${context}: unknown workload ${quoted(workload)}')
				}
				if workload in run.results {
					return error('${context}: duplicate result or sample after result')
				}
				if tag == 'ALLOC-SAMPLE' {
					run.samples[workload] << record
				} else {
					run.results[workload] = record
				}
			}
			'ALLOC-DONE' { run.done = record }
			else { return error('${context}: unknown benchmark record') }
		}
	}
	if run.meta.len == 0 || run.done.len == 0 {
		return error('${name}: complete ALLOC-META and ALLOC-DONE required')
	}
	meta := run.meta
	mut required_meta := meta_fields.clone()
	required_meta << ['label', 'platform', 'release', 'compiler', 'compiler_major', 'compiler_minor',
		'compiler_patch', 'compiler_version', 'clock_resolution_ns']
	require(meta, required_meta, name)!
	if meta['schema'] != '1' {
		return error('${name}: unsupported schema ${quoted(meta['schema'])}')
	}
	count := number(meta, 'samples', name, 5, 31)!
	iterations := number(meta, 'iterations', name, 1, 1000000000)!
	for key in ['compiler_major', 'compiler_minor', 'compiler_patch'] {
		_ := number(meta, key, name, 0, ~u64(0))!
	}
	for key in ['page_size', 'clock_resolution_ns'] { _ := number(meta, key, name, 1, ~u64(0))! }
	for key, expected in {
		'pointer_bits': '64'
		'threads':      '1'
		'clock':        'CLOCK_MONOTONIC'
		'touch_stride': '4096'
		'large_bytes':  '262144'
		'mixed_sizes':  mixed_sizes
	} {
		if meta[key] != expected {
			return error('${name}: unsupported ${key}=${quoted(meta[key])}')
		}
	}
	if run.results.len != workloads.len || run.samples.len != workloads.len {
		mut missing := workloads.filter(it.name !in run.results || it.name !in run.samples).map(it.name)
		missing.sort()
		return error('${name}: missing workloads ' + missing.join(', '))
	}
	for workload in workloads {
		context := '${name} ${workload.name}'
		result := run.results[workload.name]
		require(result, ['label', 'category', 'operation', 'pairs', 'samples', 'warmup_pairs',
			'bytes', 'batch', 'touch_stride', 'median_ns_per_pair', 'min_ns_per_pair', 'max_ns_per_pair'], context)!
		pairs := (iterations + workload.divisor - 1) / workload.divisor
		for key, expected in {
			'label':        meta['label']
			'category':     workload.category
			'operation':    workload.operation
			'pairs':        pairs.str()
			'samples':      count.str()
			'warmup_pairs': pairs.str()
			'bytes':        workload.size.str()
			'batch':        workload.batch.str()
			'touch_stride': workload.stride.str()
		} {
			if result[key] != expected {
				return error('${context}: inconsistent ${key}=${quoted(result[key])}, expected ${quoted(expected)}')
			}
		}
		records := run.samples[workload.name]
		if u64(records.len) != count {
			return error('${context}: expected ${count} samples, found ${records.len}')
		}
		mut indices := map[u64]bool{}
		mut checksums := map[u64]bool{}
		mut durations := []f64{}
		for sample in records {
			require(sample, ['label', 'sample', 'pairs', 'elapsed_ns', 'ns_per_pair', 'checksum'], context)!
			index := number(sample, 'sample', context, 1, count)!
			if index in indices { return error('${context}: duplicate sample ${index}') }
			indices[index] = true
			if sample['label'] != meta['label'] || number(sample, 'pairs', context, 1, ~u64(0))! != pairs {
				return error('${context}: sample label or pair count differs')
			}
			elapsed := number(sample, 'elapsed_ns', context, 1, ~u64(0))!
			actual := ratio(elapsed, pairs)
			summary(sample, 'ns_per_pair', actual, context)!
			checksums[number(sample, 'checksum', context, 0, ~u64(0))!] = true
			durations << actual
		}
		if checksums.len != 1 {
			return error('${context}: checksum differs between repeated samples')
		}
		summary(result, 'median_ns_per_pair', median(mut durations), context)!
		summary(result, 'min_ns_per_pair', durations[0], context)!
		summary(result, 'max_ns_per_pair', durations.last(), context)!
	}
	require(run.done, ['label', 'workloads', 'checksum'], name)!
	if run.done['label'] != meta['label'] || number(run.done, 'workloads', name, 0, ~u64(0))! != u64(workloads.len) {
		return error('${name}: ALLOC-DONE label or workload count differs')
	}
	mut checksum := u64(0)
	if (count + 1) % 2 != 0 {
		for records in run.samples.values() { checksum ^= records[0]['checksum'].u64() }
	}
	if number(run.done, 'checksum', name, 0, ~u64(0))! != checksum {
		return error('${name}: ALLOC-DONE checksum differs')
	}
	return run
}

pub fn read_run(log string, config string, name string) !Run {
	text := os.read_file(config) or { return error('${name}: ${err}') }
	manifest := decode_config(text) or { return error('${name}: ${err}') }
	contents := os.read_file(log) or { return error('${name}: ${err}') }
	return parse_log(contents, name, manifest)
}

fn sha(item Value) bool {
	if item !is string { return false }
	return item.len == 64 && item.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

pub fn comparability(vinix Run, macos Run) ([]string, []string) {
	mut mismatches := []string{}
	mut notes := []string{}
	for index, run in [vinix, macos] {
		platforms := if index == 0 { ['Vinix', 'Linux'] } else { ['Darwin'] }
		if run.meta['platform'] !in platforms {
			mismatches << '${run.name}: platform ${quoted(run.meta['platform'])}; expected ' + platforms.join(' or ')
		}
		if run.meta['arch'] != 'x86_64' {
			mismatches << '${run.name}: expected guest arch x86_64, found ${quoted(run.meta['arch'])}'
		}
		if !run.meta['compiler'].starts_with('gcc') {
			mismatches << '${run.name}: actual GCC required, found ${quoted(run.meta['compiler'])}'
		}
		for key in config_fields {
			entry := value(run.config, key)
			if entry is json2.Null || entry == Value('') {
				mismatches << '${run.name}: missing config field ${key}'
			}
		}
		for key in ['qemu_version', 'machine', 'accelerator', 'cpu', 'smp'] {
			if key in run.config && value(run.config, key) !is string {
				mismatches << '${run.name}: config ${key} must be a string'
			}
		}
		accelerator := value(run.config, 'accelerator')
		mut tcg := false
		if accelerator is string { tcg = accelerator.all_before(',') == 'tcg' }
		if !tcg { mismatches << '${run.name}: QEMU TCG acceleration required' }
		memory := value(run.config, 'memory_mb')
		mut positive := false
		if memory is Number && is_integer(memory) {
			positive = big.integer_from_string(memory.text) or { big.zero_int } > big.zero_int
		}
		if !positive { mismatches << '${run.name}: positive integer memory_mb required' }
		if !sha(value(run.config, 'source_sha256')) {
			mismatches << '${run.name}: valid benchmark source_sha256 required'
		}
		flags := value(run.config, 'compile_flags')
		mut actual_flags := []string{}
		mut flag_count := -1
		if flags is []Value {
			flag_count = flags.len
			for flag in flags { if flag is string { actual_flags << flag } }
		}
		mut expected_flags := compile_flags.clone()
		actual_flags.sort()
		expected_flags.sort()
		if flag_count != actual_flags.len || actual_flags != expected_flags {
			mismatches << '${run.name}: compile_flags must be ' + compile_flags.join(' ')
		}
	}
	for key in meta_fields {
		if vinix.meta[key] != macos.meta[key] {
			mismatches << 'benchmark ${key}: Vinix=${quoted(vinix.meta[key])}, macOS=${quoted(macos.meta[key])}'
		}
	}
	if vinix.meta['compiler_major'] != macos.meta['compiler_major'] {
		mismatches << 'GCC major versions differ: ' + vinix.meta['compiler_major'] + ' versus ' + macos.meta['compiler_major']
	} else if ['compiler_minor', 'compiler_patch'].any(vinix.meta[it] != macos.meta[it]) {
		notes << 'GCC minor/patch versions differ; this can affect generated code and the measured ratio.'
	}
	for key in config_fields {
		if !equal(value(vinix.config, key), value(macos.config, key)) {
			mismatches << 'QEMU config ${key}: Vinix=${repr(value(vinix.config, key))}, macOS=${repr(value(macos.config, key))}'
		}
	}
	if [vinix, macos].any('v_generation' in it.config || 'native_header_sha256' in it.config) {
		for run in [vinix, macos] {
			header := value(run.config, 'native_header_sha256')
			generation := value(run.config, 'v_generation')
			if !sha(header) { mismatches << '${run.name}: valid native_header_sha256 required' }
			if generation !is map[string]Value {
				mismatches << '${run.name}: V generation manifest required'
			} else if !equal(value(generation, 'source_sha256'), value(run.config, 'source_sha256')) || !equal(value(generation, 'native_header_sha256'), header) {
				mismatches << '${run.name}: V generation manifest differs from staged artifacts'
			}
		}
		if !equal(value(vinix.config, 'native_header_sha256'), value(macos.config, 'native_header_sha256')) {
			mismatches << 'native benchmark header differs between guests'
		}
	}
	for workload in workloads {
		for key in ['category', 'operation', 'pairs', 'samples', 'warmup_pairs', 'bytes', 'batch',
			'touch_stride'] {
			if vinix.results[workload.name][key] != macos.results[workload.name][key] {
				mismatches << '${workload.name}: result ${key} differs'
			}
		}
		if vinix.samples[workload.name][0]['checksum'] != macos.samples[workload.name][0]['checksum'] {
			mismatches << '${workload.name}: payload checksum differs between guests'
		}
	}
	return mismatches, notes
}

pub fn render(vinix Run, macos Run, mismatches []string, notes []string) string {
	mut output := [
		if mismatches.len > 0 {
			'Unmatched runs — diagnostic ratios only; this is not a fair matched comparison.'
		} else {
			'Matched QEMU allocation workload comparison.'
		},
		'',
	]
	if mismatches.len > 0 {
		output << mismatches.map('- ' + it)
		output << ''
	}
	for run in [vinix, macos] {
		m := run.meta
		version := ['compiler_major', 'compiler_minor', 'compiler_patch'].map(m[it]).join('.')
		output << '${run.name}: ${m['platform']} ${m['release']}, ${m['arch']}, GCC ${version} (${m['compiler_version']}), page size ${m['page_size']} bytes; monotonic clock resolution ${m['clock_resolution_ns']} ns.'
	}
	output << notes
	output << ['', 'Medians are recomputed from raw samples. A ratio above 1 means Vinix took longer.',
		'', '| Workload | Pairs/sample | Samples | Vinix ns/pair | macOS ns/pair | Vinix/macOS |',
		'| --- | ---: | ---: | ---: | ---: | ---: |']
	for workload in workloads {
		left := vinix.median(workload.name)
		right := macos.median(workload.name)
		l := vinix.results[workload.name]
		r := macos.results[workload.name]
		pairs := if l['pairs'] == r['pairs'] { l['pairs'] } else { l['pairs'] + '/' + r['pairs'] }
		samples := if l['samples'] == r['samples'] {
			l['samples']
		} else {
			l['samples'] + '/' + r['samples']
		}
		output << '| ${workload.name} | ${pairs} | ${samples} | ${fixed(left)} | ${fixed(right)} | ${fixed(left / right)}× |'
	}
	output << ['',
		"malloc workloads compare the guests' userspace allocators and libc implementations. mmap workloads measure VM mapping, faults and teardown; pipe creation exercises syscall and object lifetimes. These do not directly compare Vinix slab allocation with XNU zone allocation."]
	return output.join('\n') + '\n'
}

// V's decimal formatter can round 500.0005 upward where Python's format
// rounds the actual binary64 value downward. libc preserves that rounding.
pub fn fixed(value f64) string {
	mut buffer := [128]u8{}
	length := unsafe { C.snprintf(&char(&buffer[0]), usize(buffer.len), c'%.3f', value) }
	if length < 0 || length >= buffer.len {
		panic('allocation timing formatter exceeded its bounded buffer')
	}
	return buffer[..int(length)].bytestr()
}
