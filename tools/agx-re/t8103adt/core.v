module t8103adt

import appleadt as a
import g17decode as g
import imageextract as image
import traceanalysis as j

#include <stdlib.h>

fn C.strtod(&char, &&char) f64

fn truthy(value j.Value) bool {
	return match value {
		j.Number {
			if value.text.contains_any('.eE') {
				C.strtod(&char(value.text.str), unsafe { nil }) != 0
			} else {
				value.text.bytes().any(it >= `1` && it <= `9`)
			}
		}
		bool { value }
		i64, int, u8, u32, u64 { value != 0 }
		[]j.Value, map[string]j.Value, string { value.len != 0 }
		else { false }
	}
}

pub const base_m1_platform = 'mac13g'
pub const base_m1_boards = ['j274ap', 'j293ap', 'j313ap', 'j456ap', 'j457ap']
pub const default_board = 'j313ap'
pub const sgx_path = '/device-tree/arm-io/sgx'
pub const agx_g13g_entry = 'com.apple.AGXG13G'
pub const fdt_prefix = 'apple,'
pub const adt_prefix = 'gpu-'
pub const mapping_exceptions = {
	'operating-points-v2':      ['perf-state-count', 'gpu-num-perf-states']
	'opp-hz':                   ['perf-states']
	'opp-microvolt':            ['perf-states']
	'opp-microwatt':            []
	'apple,min-sram-microvolt': []
	'apple,core-leak-coef':     []
	'apple,sram-leak-coef':     []
	'apple,power-zones':        ['gpu-power-zone-target-0', 'gpu-power-zone-target-offset-0',
		'gpu-power-zone-filter-tc-0']
	'apple,firmware-abi':       []
	'apple,firmware-version':   []
}
pub const required_fdt_properties = ['operating-points-v2', 'opp-hz', 'opp-microvolt', 'opp-microwatt',
	'apple,min-sram-microvolt', 'apple,power-sample-period', 'apple,core-leak-coef',
	'apple,sram-leak-coef', 'apple,avg-power-filter-tc-ms', 'apple,avg-power-ki-only',
	'apple,avg-power-kp', 'apple,avg-power-min-duty-cycle', 'apple,avg-power-target-filter-tc',
	'apple,fast-die0-integral-gain', 'apple,fast-die0-proportional-gain',
	'apple,perf-filter-drop-threshold', 'apple,perf-filter-time-constant',
	'apple,perf-filter-time-constant2', 'apple,perf-integral-gain2', 'apple,perf-integral-min-clamp',
	'apple,perf-proportional-gain2', 'apple,perf-tgt-utilization', 'apple,ppm-filter-time-constant-ms',
	'apple,ppm-ki', 'apple,ppm-kp', 'apple,pwr-min-duty-cycle']
pub const optional_fdt_properties = ['apple,firmware-abi', 'apple,firmware-version',
	'apple,perf-base-pstate', 'apple,power-zones', 'apple,fast-die0-prop-tgt-delta',
	'apple,fast-die0-release-temp', 'apple,fender-idle-off-delay-ms', 'apple,fw-early-wake-timeout-ms',
	'apple,idle-off-delay-ms', 'apple,idleoff-standby-timer', 'apple,perf-boost-ce-step',
	'apple,perf-boost-min-util', 'apple,perf-integral-gain', 'apple,perf-proportional-gain',
	'apple,perf-reset-iters', 'apple,pwr-filter-time-constant', 'apple,pwr-integral-gain',
	'apple,pwr-integral-min-clamp', 'apple,pwr-proportional-gain', 'apple,pwr-sample-period-aic-clks',
	'apple,se-engagement-criteria', 'apple,se-filter-time-constant', 'apple,se-filter-time-constant-1',
	'apple,se-inactive-threshold', 'apple,se-ki', 'apple,se-ki-1', 'apple,se-kp', 'apple,se-kp-1',
	'apple,se-reset-criteria']
pub const max_power_properties = ['gpu-device-max-power', 'gpu-max-power']
pub const setup_config_symbol = '__ZN11AGXFirmware11setupConfigEv'
pub const leakage_symbols = ['__ZN21AGXAcceleratorG13G_A019calculateGPULeakageEPv',
	'__ZN21AGXAcceleratorG13G_B019calculateGPULeakageEPv']

fn null_value() j.Value { return j.value(map[string]j.Value{}, '') }

pub fn adt_name_for(name string) ![]string {
	if name in mapping_exceptions { return mapping_exceptions[name].clone() }
	if !name.starts_with(fdt_prefix) {
		return error('${name} is neither an apple, property nor an exception')
	}
	return [adt_prefix + name[fdt_prefix.len..]]
}

pub fn describe_value(data []u8) map[string]j.Value {
	mut zero := true
	for byte in data {
		if byte != 0 {
			zero = false
			break
		}
	}
	mut result := map[string]j.Value{
		'bytes':    j.Value(data.len)
		'all_zero': j.Value(zero)
	}
	if data.len == 4 {
		result['u32'] = j.Value(image.u32_at(data, 0))
	} else if data.len == 8 {
		result['u64'] = j.Value(image.u64_at(data, 0))
	}
	return result
}

pub fn sgx_inventory(root a.Node) !map[string]j.Value {
	mut found := false
	mut properties := map[string]a.Property{}
	for visit in a.walk_adt(root, '')! {
		if visit.path == sgx_path {
			found = true
			properties = visit.node.properties
		}
	}
	if !found { return error('DeviceTree has no ${sgx_path} node') }
	mut names := properties.keys()
	names.sort()
	mut inventory := map[string]j.Value{}
	for name in names { inventory[name] = j.Value(describe_value(properties[name].data)) }
	return inventory
}

pub fn decode_perf_states(data []u8) ![]j.Value {
	if data.len % 8 != 0 { return error('perf-states is not an array of 32-bit pairs') }
	mut result := []j.Value{}
	for offset := 0; offset < data.len; offset += 8 {
		result << j.Value(map[string]j.Value{
			'frequency_hz': j.Value(image.u32_at(data, offset))
			'voltage_mv':   j.Value(image.u32_at(data, offset + 4))
		})
	}
	return result
}

pub fn recover_mapping(inventory map[string]j.Value, driver_strings []string) ![]j.Value {
	mut all := required_fdt_properties.clone()
	all << optional_fdt_properties
	mut result := []j.Value{}
	for name in all {
		names := adt_name_for(name)!
		mut entries := []j.Value{}
		for adt_name in names {
			entries << j.Value(map[string]j.Value{
				'adt_property':      j.Value(adt_name)
				'in_device_tree':    j.Value(adt_name in inventory)
				'in_driver_strings': j.Value(adt_name in driver_strings)
				'value':             j.value(inventory, adt_name)
			})
		}
		result << j.Value(map[string]j.Value{
			'fdt_property':       j.Value(name)
			'required_by_vinix':  j.Value(name in required_fdt_properties)
			'has_adt_equivalent': j.Value(names.len != 0)
			'adt':                j.Value(entries)
		})
	}
	return result
}

pub fn macho_cstrings(data []u8) []string {
	mut found := map[string]bool{}
	for chunk in data.bytestr().split('\x00') {
		if chunk.len == 0 || chunk.len > 64 || !(chunk.starts_with('gpu-') || chunk.starts_with('perf-') || chunk.starts_with('gfx-')) {
			continue
		}
		mut valid := true
		for byte in chunk.bytes() {
			if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`) || (byte >= `0` && byte <= `9`) || byte in [
				`-`,
				`_`,
			]) {
				valid = false
				break
			}
		}
		if valid { found[chunk] = true }
	}
	mut result := found.keys()
	result.sort()
	return result
}

pub fn decode_add_immediate_64(word u32) ?[3]u32 {
	if word & 0xff000000 != 0x91000000 { return none }
	immediate := ((word >> 10) & 4095) << if word & (1 << 22) != 0 { 12 } else { 0 }
	return [word & 31, (word >> 5) & 31, immediate]!
}

pub fn decode_ldr_unsigned(word u32, opcode u32, scale int) ?[3]int {
	if word & 0xffc00000 != opcode { return none }
	return [int(word & 31), int((word >> 5) & 31), int((word >> 10) & 4095) * scale]!
}

pub fn recover_gpu_leakage_code(address u64, code []u8, symbol string) !map[string]j.Value {
	words := g.words(code)
	if words.len < 14 { return error('${symbol} is too short to be the recovered leakage read') }
	if words[0].word != 0xd503245f { return error('${symbol} does not open with bti c') }
	base := decode_add_immediate_64(words[1].word) or { return error('${symbol} does not derive a shifted field base from this') }
	if base[1] != 0 || words[1].word & (1 << 22) == 0 {
		return error('${symbol} does not derive a shifted field base from this')
	}
	names := ['fuse_byte_offset', 'shift', 'mask', 'scale_f32']!
	indices := [2, 5, 7, 11]!
	opcodes := [u32(0xb9400000), 0xb9400000, 0xb9400000, 0xbd400000]!
	mut fields := map[string]j.Value{}
	for i, name in names {
		decoded := decode_ldr_unsigned(words[indices[i]].word, opcodes[i], 4) or { return error('${symbol} field load ${name} does not match the recovery') }
		if decoded[1] != int(base[0]) {
			return error('${symbol} field load ${name} does not match the recovery')
		}
		fields[name] = j.Value(base[2] + u32(decoded[2]))
	}
	expected_indices := [3, 4, 6, 8, 9, 10, 12, 13]!
	expected_words := [u32(0x8b010129), 0xf9400129, 0x9aca2529, 0x8a0a0129, 0x91000529, 0x9e230120,
		0x1e200820, 0xd65f03c0]!
	for i, index in expected_indices {
		if words[index].word != expected_words[i] {
			return error('${symbol} word ${index} is not the recovered leakage read')
		}
	}
	return {
		'symbol':     j.Value(symbol)
		'address':    j.Value(address)
		'field_base': j.Value(base[2])
		'fields':     j.Value(fields)
		'equation':   j.Value('leakage = scale_f32 * (((fuses[fuse_byte_offset] >> shift) & mask) + 1)')
		'inputs':     j.Value('one fused 64-bit word; no DeviceTree or temperature input')
	}
}

pub fn recover_gpu_leakage_read(data []u8, symbol string) !map[string]j.Value {
	address, code := g.symbol_code(data, symbol)!
	return recover_gpu_leakage_code(address, code, symbol)
}

pub fn recover_max_power_properties(data []u8) !map[string]j.Value {
	address, code := g.symbol_code(data, setup_config_symbol)!
	strings := macho_cstrings(data)
	mut order := []j.Value{}
	for name in max_power_properties { if name in strings { order << j.Value(name) } }
	return {
		'symbol':            j.Value(setup_config_symbol)
		'address':           j.Value(address)
		'bytes':             j.Value(code.len)
		'read_order':        j.Value(order)
		'computed_fallback': j.Value(false)
	}
}

pub fn recover(inventory map[string]j.Value, source string, live bool, driver_data ?[]u8, perf_states ?[]u8) !map[string]j.Value {
	mut strings := []string{}
	mut driver := map[string]j.Value{
		'available': j.Value(false)
	}
	if data := driver_data {
		strings = macho_cstrings(data)
		symbols := g.macho_symbols(data)!
		mut leakage := []j.Value{}
		for symbol in leakage_symbols {
			if symbol in symbols { leakage << j.Value(recover_gpu_leakage_read(data, symbol)!) }
		}
		driver = {
			'available': j.Value(true)
			'uuid':      g.macho_uuid(data)!
			'leakage':   j.Value(leakage)
			'max_power': j.Value(recover_max_power_properties(data)!)
		}
	}
	mapping := recover_mapping(inventory, strings)!
	mut mapped := map[string]bool{}
	mut missing := []j.Value{}
	for value in mapping {
		record := value.as_map()
		mut present := true
		for entry_value in j.value(record, 'adt').arr() {
			entry := entry_value.as_map()
			mapped[j.string_value(j.value(entry, 'adt_property'))] = true
			if j.value(entry, 'in_device_tree') == j.Value(false) { present = false }
		}
		if j.value(record, 'required_by_vinix') == j.Value(true) && (j.value(record, 'has_adt_equivalent') == j.Value(false) || !present) {
			missing << j.value(record, 'fdt_property')
		}
	}
	mut unmapped := []string{}
	for name, _ in inventory {
		if name.starts_with(adt_prefix) && name !in mapped { unmapped << name }
	}
	unmapped.sort()
	described := j.value(inventory, 'perf-states').as_map()
	mut states := null_value()
	if data := perf_states {
		if data.len != 0 { states = j.Value(decode_perf_states(data)!) }
	}
	return {
		'schema':                       j.Value(2)
		'source':                       j.Value(source)
		'live':                         j.Value(live)
		'platform':                     j.Value(base_m1_platform)
		'sgx_property_count':           j.Value(inventory.len)
		'sgx_properties':               j.Value(inventory)
		'mapping':                      j.Value(mapping)
		'adt_properties_vinix_ignores': j.Value(unmapped.map(j.Value(it)))
		'missing_required_inputs':      j.Value(missing)
		'perf_states_is_template':      j.Value(truthy(j.value(described, 'all_zero')))
		'perf_states':                  states
		'driver':                       j.Value(driver)
	}
}
