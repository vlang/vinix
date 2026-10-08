module macinspect

import traceanalysis as j
import math.big

fn contains(values j.Value, expected string) bool {
	return match values {
		string { values.contains(expected) }
		[]j.Value { values.any(eq(it, j.Value(expected))) }
		map[string]j.Value { expected in values }
		else { false }
	}
}

fn required(fields map[string]j.Value, name string) !j.Value {
	return fields[name] or { return error(j.quoted(name)) }
}

fn frequencies(table j.Value) !j.Value {
	mut output := []j.Value{}
	for state in list_value(table) { output << required(object(state), 'frequency_hz')! }
	return j.Value(output)
}

fn expected_pmp_segments(base u64) j.Value {
	mut output := []j.Value{}
	for index, name in ['__TEXT', '__DATA'] {
		address := base + if index == 0 { u64(0) } else { u64(0x5e000) }
		output << j.Value(map[string]j.Value{
			'name':                       j.Value(name)
			'physical':                   number(address)
			'iova':                       number(if index == 0 { 0x1000000 } else { 0x105e000 })
			'remap':                      number(address)
			'size':                       number(if index == 0 { 0x5e000 } else { 0x9a000 })
			'flags':                      number(if index == 0 { 3 } else { 6 })
			'apple_driver_mapper_insert': j.Value(false)
			'mapping_owner':              j.Value('iboot-preinstalled')
			'writable':                   j.Value(index == 1)
		})
	}
	return j.Value(output)
}

pub fn validate_manifest(manifest map[string]j.Value) ![]string {
	mut warnings := []string{}
	sgx := object(required(manifest, 'device_tree')!)
	accelerator := object(required(manifest, 'accelerator')!)
	config := object(required(accelerator, 'configuration')!)
	compatible := required(sgx, 'compatible')!
	t6050 := contains(compatible, 'gpu,t6050')
	if t6050 {
		if !eq(value(config, 'gpu_gen'), number(17)) {
			warnings << 't6050 did not report GPU generation 17'
		}
		if !eq(value(config, 'gpu_var'), j.Value('C')) {
			warnings << 'this t6050 is not AGX variant C'
		}
	}
	if !eq(value(accelerator, 'gpu_core_count'), value(config, 'num_cores')) {
		warnings << 'accelerator core count differs from GPUConfigurationVariable'
	}
	masks := value(config, 'core_mask_list')
	match masks {
		[]j.Value {
			mut bits := big.zero_int
			for mask in masks {
				mut n := integer(mask)!
				if n < big.zero_int { n = n.neg() }
				for n != big.zero_int {
					_, rem := n.div_mod(big.integer_from_int(2))
					bits = bits + rem
					n = n.right_shift(u32(1))
				}
			}
			if !eq(j.Value(j.Number{bits.str()}), value(config, 'num_cores')) {
				warnings << 'active bits in core_mask_list do not equal num_cores'
			}
		}
		else {}
	}
	state_count := value(sgx, 'perf_state_count')
	max_state := value(sgx, 'gpu_num_perf_states')
	if state := integer(state_count) {
		if max := integer(max_state) {
			if max + big.one_int != state {
				warnings << 'gpu-num-perf-states is not perf-state-count minus one'
			}
		}
	}
	core := value(sgx, 'perf_states')
	match core {
		[]j.Value {
			if core.len == 0 { return error('list index out of range') }
			reference := frequencies(core[0])!
			for table in core[1..] {
				if !eq(frequencies(table)!, reference) {
					warnings << 'core performance tables disagree on frequencies'
					break
				}
			}
			sram := value(sgx, 'perf_states_sram')
			match sram {
				[]j.Value {
					for table in sram {
						if !eq(frequencies(table)!, reference) {
							warnings << 'SRAM performance tables disagree with core frequencies'
							break
						}
					}
				}
				else {}
			}
		}
		else {}
	}
	for domain in ['cs', 'afr'] {
		auxiliary := value(sgx, domain + '_perf_states')
		match auxiliary {
			map[string]j.Value {
				tables := list_value(value(auxiliary, 'tables'))
				if tables.len != 0 {
					reference := frequencies(tables[0])!
					for table in tables[1..] {
						if !eq(frequencies(table)!, reference) {
							warnings << '${domain.to_upper()} performance rails disagree on frequencies'
							break
						}
					}
				}
				if is_integer(state_count) && !eq(value(auxiliary, 'state_count'), state_count) {
					warnings << '${domain.to_upper()} and GPU performance-state counts differ'
				}
			}
			else {}
		}
	}
	if !t6050 { return warnings }
	asc := value(manifest, 'asc')
	fallback := match asc {
		map[string]j.Value { j.Value([j.Value(asc)]) }
		else { j.Value([]j.Value{}) }
	}
	asc_roles := manifest['asc_roles'] or { fallback }
	roles := list_value(asc_roles)
	if roles.len != 2 {
		warnings << 't6050 does not expose both GFX and GFX1 firmware ASCs'
	} else {
		mut names := []j.Value{}
		mut v6 := true
		for item in roles {
			match item {
				map[string]j.Value {
					names << value(item, 'role')
					if !contains(value(item, 'compatible'), 'iop,ascwrap-v6') { v6 = false }
				}
				else {}
			}
		}
		if !eq(j.Value(names), j.Value([j.Value('GFX'), j.Value('GFX1')])) {
			warnings << 't6050 firmware ASC roles are not GFX/GFX1'
		}
		if !v6 { warnings << 't6050 firmware ASC is not the observed ascwrap-v6' }
	}
	segments := list_value(value(object(asc), 'segments'))
	if segments.len >= 2 {
		t := object(segments[0])
		d := object(segments[1])
		if !eq(value(t, 'iova'), value(sgx, 'rtkit_private_vm_region_base')) {
			warnings << 'gfx-asc TEXT does not start at the RTKit private VM base'
		}
		x := integer(t['iova'] or { number(0) })! + integer(t['size'] or { number(0) })!
		if !eq(j.Value(j.Number{x.str()}), value(d, 'iova')) {
			warnings << 'gfx-asc TEXT and DATA virtual ranges are not contiguous'
		}
		if !eq(value(d, 'physical'), value(sgx, 'gfx_data_base')) {
			warnings << 'gfx-asc DATA physical address differs from gfx-data-base'
		}
		if !eq(value(d, 'size'), value(sgx, 'gfx_data_size')) {
			warnings << 'gfx-asc DATA size differs from gfx-data-size'
		}
	}
	platform_info := object(value(manifest, 'platform'))
	die_count := value(platform_info, 'die_count')
	if !contains(value(platform_info, 'compatible'), 'arm-io,t6050') {
		warnings << 't6050 platform is not arm-io,t6050'
	}
	valid_die := eq(die_count, number(1)) || eq(die_count, number(2))
	if !valid_die { warnings << 't6050 arm-io die count is not one or two' }
	pmp_roles := value(manifest, 'pmp_roles')
	pmps := list_value(pmp_roles)
	if pmps.len < 1 || pmps.len > 2 {
		warnings << 't6050 does not expose an active PMP firmware wrapper'
	} else {
		if valid_die && !eq(number(u64(pmps.len)), die_count) {
			warnings << 't6050 active PMP wrapper count differs from arm-io die count'
		}
		for index, item in pmps {
			expected_role := 'PMP${index}'
			if !eq(value(object(item), 'role'), j.Value(expected_role)) {
				warnings << 't6050 PMP firmware roles are not PMP0/PMP1'
				break
			}
			base := if index == 0 { u64(0x284500000) } else { u64(0x4284500000) }
			if !eq(value(object(item), 'segments'), expected_pmp_segments(base)) {
				warnings << 't6050 ${expected_role} iBoot firmware map changed'
			}
		}
	}
	for role in pmps {
		r := object(role)
		for segment in list_value(value(r, 'segments')) {
			s := object(segment)
			name := required(s, 'name')!
			writable := required(s, 'writable')!
			if !eq(writable, j.Value(eq(name, j.Value('__DATA')))) {
				warnings << '${j.string_value(value(r, 'role'))} ${j.string_value(name)} writability changed: ${j.string_value(writable)}'
			}
		}
	}
	if 'pmp_endpoint_services' in manifest {
		services := required(manifest, 'pmp_endpoint_services')!
		match services {
			[]j.Value {
				if services.len != pmps.len {
					warnings << 't6050 PMP endpoint-service count changed'
				} else {
					for index, service in services {
						s := object(service)
						if !eq(value(s, 'role'), j.Value('PMP${index}')) || !eq(value(s, 'service_suffix'), number(1)) || !eq(value(s, 'wire_endpoint'), number(0x20)) {
							warnings << 't6050 PMP${index} application endpoint changed'
							break
						}
					}
				}
			}
			else { warnings << 't6050 PMP endpoint-service count changed' }
		}
	}
	return warnings
}
