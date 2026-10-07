module kernelcompare

import comparecore as common
import math.big
import encoding.utf8

pub const compile_flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-builtin',
	'-ffreestanding', '-fno-stack-protector', '-mno-red-zone', '-mno-80387', '-mno-mmx', '-mno-sse',
	'-mno-sse2']
pub const metadata_tags = ['KALLOC-META', 'KALLOC-VALIDATION', 'KALLOC-COMPILER']
pub const metadata = {
	'schema':       '3'
	'timer':        'x86-tsc'
	'samples':      '5'
	'hot_pairs':    '100000'
	'batch_rounds': '48'
	'batch_width':  '256'
	'big_pairs':    '128'
	'big_bytes':    '262144'
	'operation':    'alloc_free_pair'
}
pub const validation = {
	'sizes':                 '16,32,48,64,96,128,192,256,384,512,768,1024,1536,2048'
	'zero_validation':       'warmup_every_requested_byte'
	'payload_validation':    'endpoints'
	'timed_zero_validation': '0'
}

pub struct Phase {
pub:
	name     string
	pairs    u64
	checksum u64
}

pub const phases = [Phase{'hot64', 100000, 25486688}, Phase{'mixed256', 12288, 1855488},
	Phase{'big262144', 128, 16256}]

pub struct Run {
pub mut:
	meta    map[string]string
	samples map[string][]u64
	results map[string]map[string]string
}

pub fn number(fields map[string]string, key string, context string, minimum u64) !u64 {
	return common.number(fields, key, context, minimum, ~u64(0)) or {
		return error('${context}: invalid unsigned integer ${key}=${common.quoted(fields[key] or { '' })}')
	}
}

fn expect(fields map[string]string, expected map[string]string, context string) ! {
	for key, entry in expected {
		if key !in fields || fields[key] != entry {
			found := if key in fields { common.quoted(fields[key]) } else { 'None' }
			return error('${context}: expected ${key}=${entry}, found ${found}')
		}
	}
}

// Strip only complete ECMA-48 CSI sequences. Other escape sequences remain
// visible to the strict record recognizer, as in the independent validator.
fn strip_csi(line string) string {
	mut output := []u8{cap: line.len}
	mut cursor := 0
	for cursor < line.len {
		if line[cursor] == 0x1b && cursor + 1 < line.len && line[cursor + 1] == `[` {
			mut end := cursor + 2
			for end < line.len && line[end] >= 0x30 && line[end] <= 0x3f { end++ }
			for end < line.len && line[end] >= 0x20 && line[end] <= 0x2f { end++ }
			if end < line.len && line[end] >= 0x40 && line[end] <= 0x7e {
				cursor = end + 1
				continue
			}
		}
		output << line[cursor]
		cursor++
	}
	return output.bytestr()
}

pub fn parse_log(contents string, platform string) !Run {
	mut run := Run{}
	for phase in phases { run.samples[phase.name] = []u64{} }
	mut metadata_count := 0
	mut complete := false
	for line_number, raw_line in common.lines(contents) {
		line := strip_csi(raw_line)
		context := '${platform}:${line_number + 1}'
		if line.contains('KERNEL PANIC') || line.contains('FATAL EXCEPTION') || line.contains('panic(cpu') {
			return error('${context}: kernel reported a fatal error')
		}
		if !line.contains('KALLOC-') { continue }
		parts := common.tokens(line)
		mut tag_index := -1
		for index, token in parts {
			if token.starts_with('KALLOC-') && token.len > 7 && token[7..].bytes().all(it >= `A` && it <= `Z`) {
				tag_index = index
				break
			}
		}
		if tag_index < 0 || complete {
			return error('${context}: malformed record or record after KALLOC-DONE')
		}
		tag := parts[tag_index]
		mut fields := map[string]string{}
		for token in parts[tag_index + 1..] {
			separator := token.index('=') or { return error('${context}: malformed or duplicate field ${common.quoted(token)}') }
			key := token[..separator]
			entry := token[separator + 1..]
			if key == '' || entry == '' || key in fields {
				return error('${context}: malformed or duplicate field ${common.quoted(token)}')
			}
			fields[key] = entry
		}
		if tag in metadata_tags {
			if metadata_count >= 3 || tag != metadata_tags[metadata_count] {
				return error('${context}: duplicate or out-of-order metadata')
			}
			mut expected := match metadata_count {
				0 { metadata.clone() }
				1 { validation.clone() }
				else {
					map[string]string{
						'compiler': 'gcc'
					}
				}
			}
			expected['platform'] = platform
			expect(fields, expected, context)!
			mut allowed := expected.keys()
			if tag == 'KALLOC-COMPILER' {
				allowed << ['compiler_major', 'compiler_minor', 'compiler_patch']
			}
			if fields.keys().any(it !in allowed) {
				return error('${context}: unexpected metadata fields')
			}
			if tag == 'KALLOC-COMPILER' {
				_ := number(fields, 'compiler_major', context, 1)!
				_ := number(fields, 'compiler_minor', context, 0)!
				_ := number(fields, 'compiler_patch', context, 0)!
			}
			for key, entry in fields { run.meta[key] = entry }
			metadata_count++
		} else if tag in ['KALLOC-SAMPLE', 'KALLOC-RESULT'] {
			if metadata_count != 3 {
				return error('${context}: measurement before all three metadata records')
			}
			phase_name := fields['phase'] or { '' }
			if !phases.any(it.name == phase_name) || phase_name in run.results {
				return error('${context}: unknown phase, duplicate result or sample after result')
			}
			if phase_name != phases[run.results.len].name {
				return error('${context}: phases interleaved or out of order')
			}
			phase := phases[run.results.len]
			expect(fields, {
				'platform': platform
				'pairs':    phase.pairs.str()
				'checksum': phase.checksum.str()
			}, context)!
			if tag == 'KALLOC-SAMPLE' {
				expect(fields, {
					'sample': (run.samples[phase_name].len + 1).str()
				}, context)!
				if run.samples[phase_name].len >= 5 {
					return error('${context}: more than five samples')
				}
				ticks := number(fields, 'ticks', context, 1)!
				expect(fields, {
					'ticks_per_pair': (ticks / phase.pairs).str()
				}, context)!
				run.samples[phase_name] << ticks
			} else {
				if run.samples[phase_name].len != 5 {
					return error('${context}: five raw samples required before result')
				}
				mut ordered := run.samples[phase_name].clone()
				ordered.sort()
				expect(fields, {
					'samples':               '5'
					'warmup_pairs':          phase.pairs.str()
					'median_ticks':          ordered[2].str()
					'min_ticks':             ordered[0].str()
					'max_ticks':             ordered.last().str()
					'median_ticks_per_pair': (ordered[2] / phase.pairs).str()
				}, context)!
				run.results[phase_name] = fields
			}
		} else if tag == 'KALLOC-DONE' {
			if run.meta.len == 0 || run.results.len != phases.len {
				return error('${context}: completion before all measurements')
			}
			expect(fields, {
				'platform': platform
				'phases':   '3'
				'checksum': '27358432'
			}, context)!
			complete = true
		} else {
			return error('${context}: unexpected ${tag}')
		}
	}
	if !complete {
		return error('${platform}: schema 3 metadata, three phases and KALLOC-DONE required')
	}
	return run
}

pub fn check_configs(left common.Value, right common.Value) ! {
	mut configs := []map[string]common.Value{}
	for index, item in [left, right] {
		name := if index == 0 { 'Vinix' } else { 'XNU' }
		config := config_object(item) or { return error('${name}: manifest must be a JSON object') }
		for key in common.config_fields {
			entry := common.value(config, key)
			mut valid := false
			if key == 'memory_mb' {
				if entry is common.Number {
					if !entry.text.contains_any('.eE') {
						valid = (big.integer_from_string(entry.text) or { big.zero_int }) > big.zero_int
					}
				}
			} else if entry is string {
				valid = common.tokens(entry).len != 0
			}
			if !valid { return error('${name}: missing or invalid config ${key}') }
		}
		if !common.sha(common.value(config, 'source_sha256')) {
			return error('${name}: invalid shared sampler source_sha256')
		}
		accelerator := common.value(config, 'accelerator')
		if accelerator is string {
			if accelerator.all_before(',') != 'tcg' {
				return error('${name}: QEMU TCG required for this comparison')
			}
		}
		flags := common.value(config, 'compile_flags')
		mut flag_count := -1
		mut actual := []string{}
		if flags is []common.Value {
			flag_count = flags.len
			for flag in flags { if flag is string { actual << flag } }
		}
		mut expected := compile_flags.clone()
		expected.sort()
		actual.sort()
		if flag_count != actual.len || actual != expected {
			return error('${name}: compile_flags must contain exactly the common GCC sampler flags')
		}
		if 'arch' in config && common.value(config, 'arch') != common.Value('x86_64') {
			return error('${name}: x86_64 sampler required')
		}
		configs << config
	}
	for key in common.config_fields {
		if !common.equal(common.value(configs[0], key), common.value(configs[1], key)) {
			return error('unmatched config ${key}: ${common.repr(common.value(configs[0], key))} versus ${common.repr(common.value(configs[1], key))}')
		}
	}
	if configs.any('sampler_header_sha256' in it || 'sampler_language' in it) {
		if configs.any(common.value(it, 'sampler_language') != common.Value('V')) {
			return error('both V sampler manifests must identify sampler_language=V')
		}
		for index, config in configs {
			if !common.sha(common.value(config, 'sampler_header_sha256')) {
				return error('${if index == 0 { 'Vinix' } else { 'macOS' }}: invalid shared sampler header hash')
			}
		}
		if common.value(configs[0], 'sampler_header_sha256') != common.value(configs[1], 'sampler_header_sha256') {
			return error('shared V sampler ABI headers differ')
		}
	}
}

fn config_object(item common.Value) !map[string]common.Value {
	match item {
		map[string]common.Value { return item }
		else { return error('not a config object') }
	}
}

pub fn compare(left Run, right Run, left_config common.Value, right_config common.Value) !string {
	check_configs(left_config, right_config)!
	if left.meta['compiler_major'] != right.meta['compiler_major'] {
		return error('GCC major versions differ')
	}
	mut output := ['Matched QEMU direct kernel allocation workloads.', '']
	for index, run in [left, right] {
		name := if index == 0 { 'Vinix' } else { 'XNU' }
		version := ['compiler_major', 'compiler_minor', 'compiler_patch'].map(run.meta[it]).join('.')
		output << '${name}: GCC ${version}; five measured samples and one full warmup per phase.'
	}
	if ['compiler_minor', 'compiler_patch'].any(left.meta[it] != right.meta[it]) {
		output << 'GCC minor/patch versions differ and may affect generated code.'
	}
	output << ['', '| Phase | Pairs/sample | Vinix ticks/pair | XNU ticks/pair | Vinix/XNU |',
		'| --- | ---: | ---: | ---: | ---: |']
	for phase in phases {
		mut left_ticks := left.samples[phase.name].clone()
		left_ticks.sort()
		mut right_ticks := right.samples[phase.name].clone()
		right_ticks.sort()
		output << '| ${phase.name} | ${phase.pairs} | ${common.fixed(common.ratio(left_ticks[2], phase.pairs))} | ${common.fixed(common.ratio(right_ticks[2], phase.pairs))} | ${common.fixed(common.ratio(left_ticks[2], right_ticks[2]))}× |'
	}
	output << ['',
		'Medians are recomputed from raw TSC ticks per allocation/free pair; a ratio above 1 means Vinix took longer. Full zero checks run only during the unrecorded warmup; timed samples write and verify payload endpoints.',
		'',
		'TCG ticks reflect emulated execution and host scheduling, not native CPU cycles. Vinix runs before its scheduler; XNU runs from a loaded kext with its scheduler and interrupts active. These execution contexts differ despite matching QEMU settings, so this workload comparison does not establish native allocator speed.']
	return output.join('\n') + '\n'
}

// Match Python read_text(errors="replace"): consume a valid UTF-8 prefix of
// a malformed sequence once, while leaving the next invalid byte for decoding.
pub fn log_text(text string) string {
	if utf8.validate_str(text) { return text }
	mut out := []u8{cap: text.len}
	mut i := 0
	for i < text.len {
		first := text[i]
		if first < 0x80 {
			out << first
			i++
			continue
		}
		width := if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			0
		}
		mut consumed := 1
		for width > 0 && consumed < width && i + consumed < text.len {
			byte := text[i + consumed]
			if byte < 0x80 || byte > 0xbf { break }
			if consumed == 1 && ((first == 0xe0 && byte < 0xa0) || (first == 0xed && byte > 0x9f) || (first == 0xf0 && byte < 0x90) || (first == 0xf4 && byte > 0x8f)) {
				break
			}
			consumed++
		}
		if width > 0 && consumed == width {
			out << text[i..i + width].bytes()
		} else {
			out << [u8(0xef), 0xbf, 0xbd]
		}
		i += consumed
	}
	return out.bytestr()
}
