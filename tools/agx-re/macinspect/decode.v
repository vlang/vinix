module macinspect

import traceanalysis as j
import math.big

pub const sgx_u32_properties = ['gpu-num-perf-states', 'gpu-perf-base-pstate', 'gpu-power-sample-period',
	'perf-state-count', 'perf-state-table-count', 'ttbat-phys-addr-base']
pub const sgx_u64_properties = ['gfx-data-base', 'gfx-data-size', 'gfx-handoff-base', 'gfx-handoff-size',
	'gfx-shared-l2-region-base', 'gfx-shared-l2-region-size', 'gfx-shared-region-base',
	'gfx-shared-region-size', 'gpu-region-base', 'gpu-region-size', 'rtkit-private-vm-region-base',
	'rtkit-private-vm-region-size']
pub const gpu_config_properties = ['core_mask_list', 'gpu_gen', 'gpu_var', 'is_sksm', 'kickid_qid_mask',
	'kickid_qid_shift', 'num_cores', 'num_frags', 'num_gps', 'num_mgpus', 'usc_gen']
pub const rtbuddy_firmware_source_properties = ['pre-loaded', 'running', 'no-firmware-service']

pub fn decode_uint(p Property, bits int, name string) !j.Value {
	if p.kind == .boolean || (p.kind == .number && is_integer(p.json())) { return p.json() }
	size := if bits >= 0 { bits / 8 } else { bits / 8 - if bits % 8 != 0 { 1 } else { 0 } }
	if p.kind != .bytes || p.bytes.len != size {
		return error('${name} must be a ${size}-byte value')
	}
	return j.Value(j.Number{big.integer_from_bytes(p.bytes.reverse(), signum: 1).str()})
}

pub fn decode_compatibles(p Property) ![]j.Value {
	if p.kind == .string { return [j.Value(p.text)] }
	if p.kind != .bytes { return error('compatible must be bytes or a string') }
	mut out := []j.Value{}
	for part in p.bytes.bytestr().split('\x00') {
		if part != '' { out << j.Value(ascii(part.bytes())!) }
	}
	return out
}

pub fn decode_reg(p Property) ![]j.Value {
	if p.kind != .bytes || p.bytes.len % 16 != 0 {
		return error('reg must contain little-endian 64-bit base/size pairs')
	}
	mut out := []j.Value{}
	for i := 0; i < p.bytes.len; i += 16 {
		out << j.Value(map[string]j.Value{
			'base': number(le(p.bytes, i, 8))
			'size': number(le(p.bytes, i + 8, 8))
		})
	}
	return out
}

pub fn decode_segment_names(p Property) ![]string {
	if p.kind != .bytes { return error('segment-names must be bytes') }
	mut out := []string{}
	for name in trim_nul(p.bytes).bytestr().split(';') {
		if name != '' { out << ascii(name.bytes())! }
	}
	return out
}

pub fn decode_segment_ranges(p Property) ![]j.Value {
	if p.kind != .bytes || p.bytes.len % 32 != 0 {
		return error('segment-ranges must contain 32-byte Apple ADT entries')
	}
	mut out := []j.Value{}
	for i := 0; i < p.bytes.len; i += 32 {
		out << j.Value(map[string]j.Value{
			'physical': number(le(p.bytes, i, 8))
			'iova':     number(le(p.bytes, i + 8, 8))
			'remap':    number(le(p.bytes, i + 16, 8))
			'size':     number(le(p.bytes, i + 24, 4))
			'flags':    number(le(p.bytes, i + 28, 4))
		})
	}
	return out
}

pub fn decode_perf_states(p Property, state_count j.Value, table_count j.Value, name string) ![]j.Value {
	states := integer(state_count)!
	tables := integer(table_count)!
	if p.kind != .bytes || states * tables * big.integer_from_int(8) != big.integer_from_int(p.bytes.len) {
		return error('${name} must contain ${j.string_value(state_count)} x ${j.string_value(table_count)} records')
	}
	mut output := []j.Value{}
	if tables <= big.zero_int { return output }
	// Positive dimensions with nonzero product are bounded by the actual input.
	// Keep the original empty-table behavior for a zero state count.
	if tables > big.integer_from_int(max_int) {
		return error('performance table count exceeds the host index range')
	}
	table_n := tables.str().i64()
	state_n := states.str().i64()
	for table := i64(0); table < table_n; table++ {
		mut records := []j.Value{}
		for state := i64(0); state < state_n; state++ {
			i := int((table * state_n + state) * 8)
			records << j.Value(map[string]j.Value{
				'frequency_hz': number(le(p.bytes, i, 4))
				'voltage_mv':   number(le(p.bytes, i + 4, 4))
			})
		}
		output << j.Value(records)
	}
	return output
}

pub fn decode_aux_perf_states(p Property, name string) !map[string]j.Value {
	if p.kind != .bytes || p.bytes.len < 16 || p.bytes.len % 8 != 0 {
		return error('${name} must contain little-endian 64-bit words')
	}
	rails := le(p.bytes, 0, 8)
	states := le(p.bytes, 8, 8)
	if rails < 1 || rails > 2 || states < 1 || states > 16 {
		return error('${name} has invalid rail/state dimensions')
	}
	if p.bytes.len != 16 + rails * (states * 16 + 8) {
		return error('${name} must contain ${rails} x ${states} records and SRAM defaults')
	}
	mut tables := []j.Value{}
	mut offset := 16
	for _ in 0 .. int(rails) {
		mut records := []j.Value{}
		for _ in 0 .. int(states) {
			records << j.Value(map[string]j.Value{
				'frequency_hz': number(le(p.bytes, offset + 8, 8))
				'voltage_uv':   number(le(p.bytes, offset, 8))
			})
			offset += 16
		}
		tables << j.Value(records)
	}
	mut defaults := []j.Value{}
	for i in 0 .. int(rails) { defaults << number(le(p.bytes, offset + i * 8, 8)) }
	return {
		'state_count':             number(states)
		'rail_count':              number(rails)
		'tables':                  j.Value(tables)
		'default_sram_voltage_uv': j.Value(defaults)
	}
}

pub fn parse_sgx(node map[string]Property) !map[string]j.Value {
	if 'compatible' !in node || 'reg' !in node {
		return error('sgx node is missing compatible or reg')
	}
	mut out := map[string]j.Value{
		'compatible':      j.Value(decode_compatibles(node['compatible'])!)
		'register_ranges': j.Value(decode_reg(node['reg'])!)
	}
	for name in sgx_u32_properties {
		if name in node { out[name.replace('-', '_')] = decode_uint(node[name], 32, name)! }
	}
	for name in sgx_u64_properties {
		if name in node { out[name.replace('-', '_')] = decode_uint(node[name], 64, name)! }
	}
	interrupts := get(node, 'interrupts')
	if interrupts.kind != .null {
		if interrupts.kind != .bytes || interrupts.bytes.len % 4 != 0 {
			return error('interrupts must contain little-endian 32-bit specifiers')
		}
		mut records := []j.Value{}
		for i := 0; i < interrupts.bytes.len; i += 4 {
			records << number(le(interrupts.bytes, i, 4))
		}
		out['interrupts'] = j.Value(records)
		out['interrupt_count'] = number(u64(records.len))
	}
	if 'interrupts-valid' in node {
		out['interrupts_valid'] = decode_uint(node['interrupts-valid'], 32, 'interrupts-valid')!
	}
	state_count := value(out, 'perf_state_count')
	table_count := value(out, 'perf_state_table_count')
	if is_integer(state_count) && is_integer(table_count) {
		for name in ['perf-states', 'perf-states-sram'] {
			if name in node {
				out[name.replace('-', '_')] = j.Value(decode_perf_states(node[name], state_count, table_count, name)!)
			}
		}
	}
	for name in ['cs-perf-states', 'afr-perf-states'] {
		if name in node {
			out[name.replace('-', '_')] = j.Value(decode_aux_perf_states(node[name], name)!)
		}
	}
	return out
}

pub fn parse_firmware_node(node map[string]Property, description string) !map[string]j.Value {
	missing := ['compatible', 'reg', 'segment-names', 'segment-ranges'].filter(it !in node)
	if missing.len != 0 { return error('${description} node is missing ${missing.join(', ')}') }
	names := decode_segment_names(node['segment-names'])!
	ranges := decode_segment_ranges(node['segment-ranges'])!
	if names.len != ranges.len {
		return error('${description} names/ranges differ in length (${names.len} != ${ranges.len})')
	}
	mut segments := []j.Value{}
	for i, name in names {
		mut record := object(ranges[i])
		record['name'] = j.Value(name)
		segments << j.Value(record)
	}
	mut out := map[string]j.Value{
		'compatible':      j.Value(decode_compatibles(node['compatible'])!)
		'register_ranges': j.Value(decode_reg(node['reg'])!)
		'segments':        j.Value(segments)
	}
	role := get(node, 'role')
	if role.kind == .bytes {
		out['role'] = j.Value(ascii(trim_nul(role.bytes))!)
	} else if role.kind == .string {
		out['role'] = j.Value(role.text)
	}
	return out
}

pub fn parse_asc(node map[string]Property) !map[string]j.Value {
	return parse_firmware_node(node, 'gfx-asc')
}

pub fn parse_pmp(node map[string]Property) !map[string]j.Value {
	mut out := parse_firmware_node(node, 'PMP')!
	if j.string_value(value(out, 'role')) !in ['PMP0', 'PMP1'] {
		return error('PMP node has an unexpected role')
	}
	mut segments := []j.Value{}
	for item in list_value(value(out, 'segments')) {
		mut segment := object(item)
		flags := uword(value(segment, 'flags'))
		segment['apple_driver_mapper_insert'] = j.Value(flags & 2 == 0)
		segment['mapping_owner'] = j.Value(if flags & 2 == 0 {
			'apple-driver'
		} else {
			'iboot-preinstalled'
		})
		segment['writable'] = j.Value(flags & 1 == 0)
		segments << j.Value(segment)
	}
	out['segments'] = j.Value(segments)
	return out
}

pub fn parse_arm_io(node map[string]Property) !map[string]j.Value {
	if 'compatible' !in node || 'die-count' !in node {
		return error('arm-io node is missing compatible or die-count')
	}
	return {
		'compatible': j.Value(decode_compatibles(node['compatible'])!)
		'die_count':  decode_uint(node['die-count'], 32, 'die-count')!
	}
}

pub fn parse_accelerator(node map[string]Property) !map[string]j.Value {
	raw := get(node, 'GPUConfigurationVariable')
	if raw.kind != .object { return error('accelerator is missing GPUConfigurationVariable') }
	mut config := map[string]j.Value{}
	for name in gpu_config_properties {
		if name in raw.fields { config[name] = raw.fields[name].json() }
	}
	mut out := map[string]j.Value{
		'configuration': j.Value(config)
	}
	for source, target in {
		'gpu-core-count':       'gpu_core_count'
		'model':                'model'
		'MetalPluginClassName': 'metal_plugin_class'
		'MetalPluginName':      'metal_plugin'
	} {
		if source in node { out[target] = node[source].json() }
	}
	return out
}

pub fn parse_driver_info(node map[string]Property) map[string]j.Value {
	mut out := map[string]j.Value{}
	for source, target in {
		'CFBundleIdentifier':         'bundle_id'
		'CFBundleShortVersionString': 'version'
		'CFBundleVersion':            'build'
	} {
		if source in node { out[target] = node[source].json() }
	}
	mut names := []string{}
	for _, personality in get(node, 'IOKitPersonalities').fields {
		if personality.kind != .object { continue }
		raw := get(personality.fields, 'IONameMatch')
		items := if raw.kind == .string { [raw] } else { raw.array }
		for name in items {
			if name.kind == .string && name.text.starts_with('gpu,') && name.text !in names {
				names << name.text
			}
		}
	}
	names.sort()
	if names.len != 0 { out['device_matches'] = j.Value(names.map(j.Value(it))) }
	return out
}
