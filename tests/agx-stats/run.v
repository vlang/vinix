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
