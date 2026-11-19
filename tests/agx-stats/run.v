// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing section: ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing terminator: ${end}') }
	return source[begin..finish]
}

struct Field {
	name   string
	offset int
}

// Field offsets of every named StatsMsg variant, from the pinned Rust
// declaration: a repr(C, u32) enum whose U64 is packed, so each variant's
// fields follow the four-byte tag with no padding of their own.
fn stats_layout(channels string) !map[string][]Field {
	body := section(channels, 'pub(crate) enum StatsMsg {', '\n}\n')!
	mut variants := map[string][]Field{}
	mut current := ''
	mut offset := 4
	for raw in body.split_into_lines()[1..] {
		line := raw.trim_space()
		if line.starts_with('//') || line.len == 0 { continue }
		if line.ends_with('{') {
			current = line.all_before(' {').trim_space()
			offset = 4
			variants[current] = []Field{}
			continue
		}
		if line.starts_with('}') {
			current = ''
			continue
		}
		if current == '' { continue }
		name := line.all_before(':').trim_space()
		kind := line.all_after(':').trim_space().trim_right(',')
		size := if kind == 'U64' {
			8
		} else if kind == 'u32' {
			4
		} else if kind.starts_with('Pad<') {
			kind.all_after('<').all_before('>').int()
		} else {
			return error('unknown field type ${kind} in ${current}')
		}
		if !name.starts_with('__') { variants[current] << Field{name, offset} }
		offset += size
	}
	return variants
}

fn tag_of(channels string, variant string) !int {
	body := section(channels, 'pub(crate) enum StatsMsg {', '\n}\n')!
	mut index := 0
	for raw in body.split_into_lines()[1..] {
		line := raw.trim_space()
		if line.len == 0 || line.starts_with('//') || line.starts_with('}') || !line[0].is_capital() { continue }
		name := if line.contains('(') { line.all_before('(') } else { line.all_before(' {') }
		if name == variant { return index }
		index++
	}
	return error('no StatsMsg variant ${variant}')
}

fn offset_of(layout map[string][]Field, variant string, field string) !int {
	for item in layout[variant] or { return error('no variant ${variant}') } {
		if item.name == field { return item.offset }
	}
	return error('no field ${variant}.${field}')
}

// The names a sysfs show function prints, in order.
fn shown_names(sysfs string, function string) ![]string {
	body := section(sysfs, 'static ssize_t ${function}(', '\n}\n')!
	mut names := []string{}
	for line in body.split_into_lines() {
		quoted := line.all_after('"')
		if line.contains('"') && quoted.contains(' %') {
			name := quoted.all_before(' ')
			if name.len > 0 && name.bytes().all(it.is_letter() || it.is_digit() || it == `_`) { names << name }
		}
	}
	return names
}

struct RustField {
	name string
	kind string // U64, u32 or Pad<N>
}

struct RustVariant {
	name  string
	tuple bool // an undecoded variant: Unk1(Array<...>)
mut:
	fields []RustField
}

// Every StatsMsg variant in tag order, with every field, pads included.
fn stats_variants(channels string) ![]RustVariant {
	body := section(channels, 'pub(crate) enum StatsMsg {', '\n}\n')!
	mut variants := []RustVariant{}
	mut current := -1
	for raw in body.split_into_lines()[1..] {
		line := raw.trim_space()
		if line.len == 0 || line.starts_with('//') { continue }
		if current >= 0 {
			if line.starts_with('}') {
				current = -1
			} else {
				variants[current].fields << RustField{line.all_before(':').trim_space(), line.all_after(':').trim_space().trim_right(',')}
			}
			continue
		}
		if line.ends_with('{') {
			variants << RustVariant{name: line.all_before(' {').trim_space()}
			current = variants.len - 1
		} else if line[0].is_capital() && line.contains('(') {
			variants << RustVariant{name: line.all_before('('), tuple: true}
		}
	}
	return variants
}

fn field_size(kind string) !int {
	return if kind == 'U64' {
		8
	} else if kind == 'u32' {
		4
	} else if kind.starts_with('Pad<') {
		kind.all_after('<').all_before('>').int()
	} else {
		error('unknown field type ${kind}')
	}
}

fn rust_type(kind string) !string {
	return if kind == 'U64' || kind == 'u32' {
		kind
	} else if kind.starts_with('Pad<') {
		'[u8; ${field_size(kind)!}]'
	} else {
		error('unknown field type ${kind}')
	}
}

fn raw_write(offset int, size int, value u64) string {
	return 'RawWrite{offset: ${offset}, size: ${size}, value: ${value}}'
}

fn raw_sample(tag int, stamp u64, writes []string) string {
	return '\t\tRawSample{tag: ${tag}, stamp: ${stamp}, writes: [${writes.join(', ')}]},\n'
}

fn replaced(text string, from string, to string) !string {
	if !text.contains(from) { return error('the pinned source no longer has: ${from}') }
	return text.replace(from, to)
}

// The reference's raw statistics, compiled from the pinned sources: its
// StatsMsg from fw/channels.rs, its RawStatsSnapshot and format_snapshot from
// stats_raw.rs and its record_raw from channel.rs, the message decoding the
// stats channel applies to every tag up to STATS_MAX. Two phases of messages
// go through both it and Vinix: some kinds, an undecoded tag and one past
// the last; then every kind, another undecoded tag and a second utilization.
// Every field gets its own value, 64-bit ones above 32 bits; Vinix's copies
// also carry junk in the pads and undecoded words.
fn raw_oracle(channels string, stats_raw string, channel string, scratch string) !string {
	variants := stats_variants(channels)!
	stats_max := section(channels, 'pub(crate) const STATS_MAX: u32 = ', ';')!.all_after('= ').int()
	assert stats_max == variants.len - 1, 'STATS_MAX ${stats_max} for ${variants.len} variants'
	mut rust := '#![allow(dead_code, unused)]\nuse core::fmt::Write;\n\n#[derive(Copy, Clone)]\nstruct U64(u64);\n\n#[derive(Copy, Clone)]\nenum StatsMsg {\n'
	for variant in variants {
		if variant.tuple {
			rust += '    ${variant.name},\n'
			continue
		}
		rust += '    ${variant.name} {'
		for field in variant.fields { rust += ' ${field.name}: ${rust_type(field.kind)!},' }
		rust += ' },\n'
	}
	rust += '}\n\n'
	rust += section(stats_raw, 'pub(crate) const STATS_FORMAT', '/// Current monotonic time in nanoseconds.')!
	mut record := section(channel, '    fn record_raw(&mut self, msg: &StatsMsg::ver) {', '\n    }\n')!
	record = replaced(record, '    fn record_raw(&mut self, msg: &StatsMsg::ver) {', 'fn record_raw(snap: &mut RawStatsSnapshot, msg: &StatsMsg, stamp: u64) {')!
	record = replaced(record, 'let stamp = crate::stats_raw::monotonic_ns();', '')!
	record = replaced(record, 'let mut snap = self.raw.lock();', '')!
	record = replaced(record, 'StatsMsg::ver::', 'StatsMsg::')!
	rust += record + '\n}\n\nfn main() {\n    let mut snap = RawStatsSnapshot::default();\n    let mut out = String::new();\n'

	named := variants.filter(!it.tuple).map(it.name)
	undecoded := variants.filter(it.tuple).map(it.name)
	phases := [['Utilization', 'Temperature', undecoded[undecoded.len - 1], 'past the last'],
		[...named, undecoded[0], 'Utilization']]
	mut v := 'struct RawWrite {\n\toffset int\n\tsize   int\n\tvalue  u64\n}\n\nstruct RawSample {\n\ttag    u32\n\twrites []RawWrite\n\tstamp  u64\n}\n\nconst oracle_raw_phases = [\n'
	mut stamp := u64(100)
	for phase, names in phases {
		v += '\t[\n'
		for sample, name in names {
			stamp += 7
			tag := if name == 'past the last' { stats_max + 1 } else { variants.map(it.name).index(name) }
			mut writes := []string{}
			if tag > stats_max || variants[tag].tuple {
				// Undecoded words: junk the decoder must not show.
				for offset := 4; offset < 0x30; offset += 4 { writes << raw_write(offset, 4, 0xa5a5a5a5) }
				if tag <= stats_max { rust += '    record_raw(&mut snap, &StatsMsg::${name}, ${stamp});\n' }
				v += raw_sample(tag, stamp, writes)
				continue
			}
			rust += '    record_raw(&mut snap, &StatsMsg::${name} {'
			mut offset := 4
			for index, field in variants[tag].fields {
				size := field_size(field.kind)!
				if field.name.starts_with('__') {
					rust += ' ${field.name}: [0; ${size}],'
					for pad := 0; pad < size; pad += 4 { writes << raw_write(offset + pad, 4, 0xa5a5a5a5) }
				} else {
					value := if size == 8 {
						(u64(tag + 1) << 32) | u64(1000 * phase + 100 * sample + index + 1)
					} else {
						u64(0x10000 * (tag + 1) + 1000 * phase + 100 * sample + index + 1)
					}
					rust += if size == 8 { ' ${field.name}: U64(${value}),' } else { ' ${field.name}: ${value},' }
					writes << raw_write(offset, size, value)
				}
				offset += size
			}
			rust += ' }, ${stamp});\n'
			v += raw_sample(tag, stamp, writes)
		}
		v += '\t],\n'
		rust += '    format_snapshot(&snap, ${(phase + 1) * 100000}, "206400000.gpu", &mut out).unwrap();\n    out.push(\'\\u{0}\');\n'
	}
	v += ']\n\nconst oracle_raw_now = [u64(100000), 200000]\n'
	rust += '    print!("{}", out);\n}\n'
	os.write_file('${scratch}/oracle.rs', rust)!
	compile := os.exec(['rustc', '--edition', '2021', '-o', '${scratch}/oracle', '${scratch}/oracle.rs'])
	if compile.exit_code != 0 { return error('the reference oracle does not compile:\n${compile.output}') }
	result := os.exec(['${scratch}/oracle'])
	if result.exit_code != 0 { return error('the reference oracle failed:\n${result.output}') }
	texts := result.output.split('\x00')
	assert texts.len == 3 && texts[2] == '', 'oracle output: ${result.output}'
	v += 'const oracle_raw_texts = [\'${texts[0].replace('\n', '\\n')}\', \'${texts[1].replace('\n', '\\n')}\']\n'
	return v
}

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	assert os.args.len == 3 && os.args[1] == '--asahi-linux', 'usage: run.v --asahi-linux PATH'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	asahi := os.join_path(os.args[2], 'drivers/gpu/drm/asahi')
	channels := os.read_file('${asahi}/fw/channels.rs')!
	sysfs := os.read_file('${asahi}/sysfs.c')!
	layout := stats_layout(channels)!
	mut oracle := 'module gpu\n\n// Generated from the pinned Asahi sources by tests/agx-stats/run.v.\n'
	for variant, fields in {
		'Utilization': ['timestamp', 'util1', 'util2', 'util3', 'util4']
		'AvgPower':    ['avg_power']
		'Temperature': ['raw_value', 'scale']
		'PowerState':  ['timestamp', 'pstate']
	} {
		snake := variant.to_lower()
		oracle += 'const oracle_tag_${snake} = u32(${tag_of(channels, variant)!})\n'
		for field in fields {
			oracle += 'const oracle_${snake}_${field} = ${offset_of(layout, variant, field)!}\n'
		}
	}
	oracle += 'const oracle_unknown_tag = u32(${tag_of(channels, 'TempSensor')! + 1})\n'
	oracle += 'const oracle_agx_stats = ${shown_names(sysfs, 'agx_stats_show')!}\n'
	oracle += 'const oracle_gpu_memory = ${shown_names(sysfs, 'gpu_memory_show')!}\n'

	scratch := os.join_path(os.temp_dir(), 'vinix-agx-stats-${os.getpid()}')
	os.mkdir_all('${scratch}/gpu/agx/gpu')!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	oracle += raw_oracle(channels, os.read_file('${asahi}/stats_raw.rs')!, os.read_file('${asahi}/channel.rs')!,
		scratch) or {
		eprintln(err.msg())
		exit(1)
	}
	for name in ['katomic', 'klock'] {
		os.cp_all('${repo}/tests/agx-g13-failure/fixture/${name}', '${scratch}/${name}', false)!
	}
	os.mkdir_all('${scratch}/lib')!
	os.cp('${repo}/kernel/lib/text.v', '${scratch}/lib/text.v')!
	for name in ['fw', 'hw'] {
		os.symlink('${repo}/kernel/gpu/agx/${name}', '${scratch}/gpu/agx/${name}')!
	}
	stats_source := os.getenv_opt('AGX_STATS_SOURCE') or { '${repo}/kernel/gpu/agx/gpu/stats.v' }
	os.cp(stats_source, '${scratch}/gpu/agx/gpu/stats.v')!
	os.write_file('${scratch}/gpu/agx/gpu/oracle.v', oracle)!
	os.cp('${repo}/tests/agx-stats/check.v', '${scratch}/gpu/agx/gpu/check.v')!
	os.write_file('${scratch}/main.v', 'import gpu.agx.gpu\nfn main() { gpu.run_checks() }\n')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
