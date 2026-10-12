// SPDX-License-Identifier: GPL-2.0-or-later
module armcpu

import strconv

pub struct Info {
pub:
	cpu_count     int
	implementers  []string
	architectures []string
	variants      []string
	parts         []string
	revisions     []string
	flags         []string
	has_features  bool
}

// Retain reported numeric IDs rather than inferring a model or capabilities
// from them. A heterogeneous system only advertises features shared by every
// processor; a missing Features field makes that information unknown.
pub fn parse(text string) !Info {
	mut records := []map[string]string{}
	mut record := map[string]string{}
	for line in text.split_into_lines() {
		if line.trim_space() == '' {
			if record.len != 0 {
				records << record
				record = map[string]string{}
			}
			continue
		}
		if !line.contains(':') { continue }
		key := line.all_before(':').trim_space()
		if key !in ['processor', 'Features', 'CPU implementer', 'CPU architecture', 'CPU variant',
			'CPU part', 'CPU revision'] {
			continue
		}
		if key in record { return error('duplicate CPU information field: ' + key) }
		record[key] = line.all_after(':').trim_space()
	}
	if record.len != 0 { records << record }
	mut ids := map[int]bool{}
	mut values := map[string][]string{}
	mut flags := []string{}
	mut has_features := true
	for item in records {
		if 'processor' !in item { continue }
		id_text := item['processor']
		if id_text.len == 0 || id_text.bytes().any(it < `0` || it > `9`) {
			return error('invalid processor ID')
		}
		id := strconv.atoi(id_text)!
		if id in ids { return error('duplicate processor ID') }
		ids[id] = true
		for key in ['CPU implementer', 'CPU architecture', 'CPU variant', 'CPU part', 'CPU revision'] {
			value := if item[key] == '' { 'Unknown' } else { item[key] }
			mut seen := values[key]
			if value !in seen { seen << value }
			values[key] = seen
		}
		if 'Features' !in item { has_features = false }
		features := item['Features'].fields()
		if ids.len == 1 {
			for feature in features {
				if feature !in flags { flags << feature }
			}
		} else {
			flags = flags.filter(it in features)
		}
	}
	if ids.len == 0 { return error('no processors reported') }
	flags.sort()
	return Info{
		cpu_count:     ids.len
		implementers:  values['CPU implementer']
		architectures: values['CPU architecture']
		variants:      values['CPU variant']
		parts:         values['CPU part']
		revisions:     values['CPU revision']
		flags:         flags
		has_features:  has_features
	}
}

pub fn (info Info) text() string {
	return [
		'Architecture:     aarch64',
		'CPU op-mode(s):   64-bit',
		'Byte Order:       Little Endian',
		'CPU Count:        ${info.cpu_count}',
		'CPU implementer:  ${info.implementers.join(', ')}',
		'CPU architecture: ${info.architectures.join(', ')}',
		'CPU variant:      ${info.variants.join(', ')}',
		'CPU part:         ${info.parts.join(', ')}',
		'CPU revision:     ${info.revisions.join(', ')}',
		'Flags:            ${if info.has_features { info.flags.join(', ') } else { 'Unknown' }}',
	].join('\n')
}

pub fn (info Info) print() {
	println(info.text())
}
