module t6050power

import appleadt as a
import traceanalysis as j

pub fn recover_power_topology(root a.Node) !map[string]j.Value {
	sgx_visit := find_selected(root, 'gpu,t6050 SGX node', NodeMatch{ name: 'sgx', compatible: 'gpu,t6050' })!
	sgx_path := sgx_visit.path
	sgx := sgx_visit.node
	pmgr_visit := find_selected(root, 'PMGR node', NodeMatch{ name: 'pmgr' })!
	pmgr := pmgr_visit.node
	devices := a.parse_pmgr_devices(pmgr.property('devices')!)!
	pmp_version := a.decode_integer(pmgr.property('pmp')!, 'pmgr pmp')!
	if pmp_version != 2 { return error('T6050 PMGR PMP version changed: ${pmp_version}') }
	ptd_range_ids := a.decode_u32_array(pmgr.property('ptd-ranges')!, 'pmgr ptd-ranges')!
	if ptd_range_ids != [u32(10), 11, 12, 13, 2, 4] {
		return error('T6050 PMGR PTD range bindings changed: ${words_repr(ptd_range_ids)}')
	}
	reg_regions := a.parse_reg_regions(pmgr.property('reg')!, 'pmgr reg')!
	if reg_regions.len != 60 {
		return error('T6050 PMGR register-region count changed: ${reg_regions.len}')
	}
	ptd_reg_index := 7
	ptd_region := reg_regions[ptd_reg_index]
	if ptd_region != a.Region{u64(0x84240000), u64(0x40000)} {
		return error('T6050 ApplePTD register region changed: (${ptd_region.address}, ${ptd_region.bytes})')
	}
	die_stride := a.decode_integer(pmgr.property('die-stride')!, 'pmgr die-stride')!
	if die_stride != 0x4000000000 {
		return error('T6050 PMGR die stride changed: 0x${die_stride:x}')
	}
	base_interrupts := a.parse_pmgr_interrupt_config(pmgr.property(pmgr_interrupt_config_property)!, 'pmgr interrupt-config')!
	mut variant_interrupts := map[string]j.Value{}
	for child in pmgr.children {
		if pmgr_interrupt_config_property !in child.properties { continue }
		name := a.node_name(child)!
		variant_interrupts[name] = maps_value(a.parse_pmgr_interrupt_config(child.property(pmgr_interrupt_config_property)!, 'pmgr ${name} interrupt-config')!)
	}
	ready_records := base_interrupts.filter(j.value(it, 'name') == j.Value(pmp_ready_interrupt_name))
	if ready_records.len != 1 {
		return error('T6050 PMGR PMP readiness interrupt records changed: ${map_repr(ready_records)}')
	}
	ready_slot := j.value(ready_records[0], 'slot')
	for name, records in variant_interrupts {
		for record in records.arr() {
			row := record.as_map()
			if j.value(row, 'name') == j.Value(pmp_ready_interrupt_name) {
				return error('T6050 PMGR variant ${name} redefines the PMP readiness interrupt')
			}
			if j.value(row, 'slot').u64() < u64(base_interrupts.len) {
				return error('T6050 PMGR variant ${name} reuses a base interrupt slot')
			}
		}
	}
	mut pmp_wrappers := map[string]a.Visit{}
	collect_wrappers(root, '', mut pmp_wrappers)!
	if pmp_wrappers.len != 2 || 'PMP0' !in pmp_wrappers || 'PMP1' !in pmp_wrappers {
		mut roles := pmp_wrappers.keys()
		roles.sort()
		return error('unexpected T6050 PMP die roles: ${j.string_value(j.Value(roles.map(j.Value(it))))}')
	}
	ptd_die_bases := [ptd_region.address, ptd_region.address + die_stride]
	pmp_darts := recover_pmp_darts(root, pmp_wrappers, j.Value(die_stride))!
	mut wrapper_registers := map[string][]a.Region{}
	mut wrapper_interrupts := map[string][]u32{}
	expected_wrapper_regs := [a.Region{u64(0x84e00000), u64(0x88000)},
		a.Region{u64(0x84850000), u64(0x4000)}, a.Region{u64(0x84500000), u64(0x100000)},
		a.Region{u64(0x84250000), u64(0x4000)}]
	expected_wrapper_interrupts := {
		'PMP0': [u32(0x18d), 0x18c, 0x18f, 0x18e]
		'PMP1': [u32(0xdad), 0xdac, 0xdaf, 0xdae]
	}
	expected_wrapper_gates := {
		'PMP0': [u32(0x1b), 0x1c]
		'PMP1': [u32(0x1000001b), 0x1000001c]
	}
	for die, role in ['PMP0', 'PMP1'] {
		wrapper := pmp_wrappers[role].node
		registers := a.parse_reg_regions(wrapper.property('reg')!, '${role} reg')!
		expected_registers := expected_wrapper_regs.map(a.Region{it.address + u64(die) * die_stride, it.bytes})
		interrupts := a.decode_u32_array(wrapper.property('interrupts')!, '${role} interrupts')!
		power := a.decode_u32_array(wrapper.property('power-gates')!, '${role} power-gates')!
		clock := a.decode_u32_array(wrapper.property('clock-gates')!, '${role} clock-gates')!
		if registers != expected_registers {
			return error('T6050 ${role} wrapper registers changed: ${region_repr(registers)}')
		}
		if interrupts != expected_wrapper_interrupts[role] {
			return error('T6050 ${role} interrupts changed: ${words_repr(interrupts)}')
		}
		if power != expected_wrapper_gates[role] || clock != power {
			return error('T6050 ${role} gate bindings changed: power=${words_repr(power)}, clock=${words_repr(clock)}')
		}
		if a.decode_integer(wrapper.property('iop-version')!, '${role} iop-version')! != 1 || a.decode_integer(wrapper.property('ptd-update-reg-index')!, '${role} ptd-update-reg-index')! != 3 || a.decode_integer(wrapper.property('sram-index')!, '${role} sram-index')! != 1 {
			return error('T6050 ${role} wrapper control properties changed')
		}
		if 'cpu-ctrl-filtered' in wrapper.properties {
			return error('T6050 ${role} unexpectedly filters CPU control')
		}
		wrapper_registers[role] = registers
		wrapper_interrupts[role] = interrupts
	}
	power_handles := a.decode_u32_array(sgx.property('power-gates')!, 'sgx power-gates')!
	clock_handles := a.decode_u32_array(sgx.property('clock-gates')!, 'sgx clock-gates')!
	mut power_gates := []map[string]j.Value{}
	mut clock_gates := []map[string]j.Value{}
	for handle in power_handles { power_gates << a.resolve_gate(u64(handle), devices)! }
	for handle in clock_handles { clock_gates << a.resolve_gate(u64(handle), devices)! }
	expected_gates := [HandleName{u64(0x268), 'GFX_SGX'}, HandleName{u64(0x267), 'GFX_BUSY'}]
	actual_power := power_gates.map(HandleName{j.value(it, 'handle').u64(), j.string_value(j.value(it, 'name'))})
	actual_clock := clock_gates.map(HandleName{j.value(it, 'handle').u64(), j.string_value(j.value(it, 'name'))})
	if actual_power != expected_gates || actual_clock != expected_gates {
		return error('T6050 SGX gate order changed: power=${handle_names_repr(actual_power)}, clock=${handle_names_repr(actual_clock)}')
	}
	pmp_visit := find_selected(root, 'T6050 PMP wrapper', NodeMatch{ property: 'role', value: 'PMP1', compatible: 'iop,ascwrap-v6' })!
	pmp_path := pmp_visit.path
	pmp := pmp_visit.node
	nub_visit := find_selected(pmp, 't6050pmp RTKit nub', NodeMatch{ property: 'firmware-name', value: 't6050pmp', compatible: 'iop-nub,rtbuddy-v2' })!
	nub := nub_visit.node
	nub_path := relative_path(nub_visit.path, pmp, pmp_path)!
	pmp0_visit := pmp_wrappers['PMP0']
	pmp0_path := pmp0_visit.path
	pmp0 := pmp0_visit.node
	pmp0_nub_visit := find_selected(pmp0, 't6050pmp PMP0 RTKit nub', NodeMatch{ property: 'firmware-name', value: 't6050pmp', compatible: 'iop-nub,rtbuddy-v2' })!
	pmp0_nub := pmp0_nub_visit.node
	pmp0_nub_path := relative_path(pmp0_nub_visit.path, pmp0, pmp0_path)!
	for property_name in ['soc-device', 'ptd-range', 'pm-ptd-ranges'] {
		if pmp0_nub.property(property_name)! != nub.property(property_name)! {
			return error('T6050 PMP die ${property_name} tables differ')
		}
	}
	pmp_regions := [
		a.Region{a.decode_integer(pmp0_nub.property('region-base')!, 'PMP0 region-base')!, a.decode_integer(pmp0_nub.property('region-size')!, 'PMP0 region-size')!},
		a.Region{a.decode_integer(nub.property('region-base')!, 'PMP1 region-base')!, a.decode_integer(nub.property('region-size')!, 'PMP1 region-size')!},
	]
	if pmp_regions != [a.Region{u64(0x284500000), u64(0x100000)},
		a.Region{u64(0x4284500000), u64(0x100000)}] {
		return error('T6050 PMP shared regions changed: ${region_repr(pmp_regions)}')
	}
	if pmp_regions[1].address - pmp_regions[0].address != die_stride {
		return error('T6050 PMP shared-region delta no longer matches die stride')
	}
	mut soc_devices := a.parse_pmp_soc_devices(nub.property('soc-device')!)!
	agx_devices := soc_devices.filter(j.value(it, 'name') == j.Value('AGX'))
	if agx_devices.len != 1 || j.value(agx_devices[0], 'id').u64() != 0x10 || j.value(agx_devices[0], 'index').u64() != 15 {
		return error('unexpected PMP AGX SoC-device records: ${map_repr(agx_devices)}')
	}
	ptd_ranges := a.parse_pmp_ptd_ranges(nub.property('ptd-range')!)!
	mut ptd_by_name := map[string]map[string]j.Value{}
	for item in ptd_ranges { ptd_by_name[j.string_value(j.value(item, 'name'))] = item }
	if ptd_by_name.len != ptd_ranges.len {
		return error('PMP ptd-range property contains duplicate names')
	}
	expected_dashboard := {
		'SOC-DEV-PKT':    [u64(9), 0x90, 0x150]
		'SOC-DEV-PS-REQ': [u64(10), 0x1e0, 8]
		'SOC-DEV-PS-ACK': [u64(11), 0x1e8, 8]
	}
	readiness_range := (ptd_by_name['PMP-STATUS'] or { return error('PMP DeviceTree has no PMP-STATUS PTD range') }).clone()
	readiness_actual := number_fields(readiness_range, ['id', 'entry_offset', 'entry_count', 'doorbell'])
	if !tuple_equal(readiness_actual, [u64(2), 1, 1, 16]) {
		return error('PMP readiness range changed: ${tuple_repr(readiness_actual)}')
	}
	mut dashboard := map[string]j.Value{}
	for name, expected in expected_dashboard {
		item := (ptd_by_name[name] or { return error('PMP DeviceTree has no ${name} PTD range') }).clone()
		actual := number_fields(item, ['id', 'entry_offset', 'entry_count'])
		if !tuple_equal(actual, expected) {
			return error('PMP ${name} PTD range changed: ${tuple_repr(actual)}')
		}
		dashboard[name] = j.Value(item)
	}
	power_range_ids := a.decode_u32_array(nub.property('pm-ptd-ranges')!, 'pm-ptd-ranges')!
	if power_range_ids != [u32(1), 2, 3, 4, 5, 6, 7, 8, 40, 9, 10, 11, 12, 13, 14] {
		return error('T6050 PMP power PTD bindings changed: ${words_repr(power_range_ids)}')
	}
	for item in dashboard.values() {
		if u32(j.value(item.as_map(), 'id').u64()) !in power_range_ids {
			return error('PMP power PTD list omits a device-state dashboard range')
		}
	}
	if u32(j.value(readiness_range, 'id').u64()) !in power_range_ids {
		return error('PMP power PTD list omits the readiness status range')
	}
	packet_range := j.value(dashboard, 'SOC-DEV-PKT').as_map()
	mut packet_cursor := j.value(packet_range, 'entry_offset').u64()
	mut virtual_state_index := 0
	for index in 0 .. soc_devices.len {
		mut device := soc_devices[index].clone()
		packet_bits := j.value(device, 'packet_bytes').u64() * 8
		device['packet_bit_offset'] = j.Value(packet_cursor)
		device['packet_bit_count'] = j.Value(packet_bits)
		packet_cursor += packet_bits
		if j.value(device, 'virtual_state_config').u64() != 0 {
			device['virtual_state_index'] = j.Value(virtual_state_index)
			virtual_state_index++
		} else {
			device['virtual_state_index'] = j.value(map[string]j.Value{}, '')
		}
		soc_devices[index] = device
	}
	packet_end := j.value(packet_range, 'entry_offset').u64() + j.value(packet_range, 'entry_count').u64()
	if packet_cursor > packet_end {
		return error('PMP SoC-device packet slices exceed SOC-DEV-PKT')
	}
	agx_device := soc_devices[int(j.value(agx_devices[0], 'index').u64())]
	actual_agx_layout := number_fields(agx_device, ['packet_bit_offset', 'packet_bit_count',
		'virtual_state_index', 'state_flags'])
	if !tuple_equal(actual_agx_layout, [u64(0x1c0), 8, 3, 3]) {
		return error('PMP AGX packet layout changed: ${tuple_repr(actual_agx_layout)}')
	}
	if packet_end - packet_cursor != 16 {
		return error('PMP SOC-DEV-PKT trailing reserve changed: ${packet_end - packet_cursor} bits')
	}
	mut gfx_handles := map[string]j.Value{}
	for binding in [HandleName{u64(0x266), 'GFX_ASC'}, HandleName{u64(0x291), 'GFX_ASC1'}] {
		gate := a.resolve_gate(binding.handle, devices)!
		if j.value(gate, 'name') != j.Value(binding.name) {
			return error('T6050 handle 0x${binding.handle:x} changed from ${binding.name} to ${j.string_value(j.value(gate, 'name'))}')
		}
		gfx_handles[binding.name] = j.Value(gate)
	}
	mut leaf_gates := power_gates.clone()
	for item in gfx_handles.values() { leaf_gates << item.as_map() }
	for gate in leaf_gates {
		dispatch := j.value(gate, 'pmp_dispatch').as_map()
		actual := number_fields(dispatch, ['flags', 'selector', 'virtual_class', 'emits_device_state',
			'virtual_device'])
		if !tuple_equal(actual, [u64(0x10), 0, 0, 0, 1]) {
			return error('T6050 ${j.string_value(j.value(gate, 'name'))} leaf PMP flags changed: ${tuple_repr(actual)}')
		}
	}
	gfx_devices := devices.filter(it.name == 'GFX')
	if gfx_devices.len != 1 {
		return error('unexpected aggregate GFX PMGR records: ${pmgr_devices_repr(gfx_devices)}')
	}
	gfx_device := gfx_devices[0]
	device_state_target := a.resolve_gate(u64(gfx_device.handle), devices)!
	target_dispatch := j.value(device_state_target, 'pmp_dispatch').as_map()
	actual_target := [j.value(device_state_target, 'handle'), j.value(target_dispatch, 'flags'),
		j.value(target_dispatch, 'selector'), j.value(target_dispatch, 'virtual_class'),
		j.value(target_dispatch, 'emits_device_state'), j.value(target_dispatch, 'virtual_device')]
	if !tuple_equal(actual_target, [u64(0x16a), 0x02, 0x10, 0, 1, 0]) {
		return error('T6050 aggregate GFX PMP proxy changed: ${tuple_repr(actual_target)}')
	}
	if j.value(target_dispatch, 'selector').u64() != j.value(agx_device, 'id').u64() {
		return error('aggregate GFX selector no longer targets PMP AGX')
	}
	return j.Value(map[string]j.Value{
		'schema':          j.Value(23)
		'chip':            j.Value('t6050')
		'pmgr_interrupts': j.Value(map[string]j.Value{
			'property':                   j.Value(pmgr_interrupt_config_property)
			'base_records':               maps_value(base_interrupts)
			'variant_records':            j.Value(variant_interrupts)
			'ready_interrupt_name':       j.Value(pmp_ready_interrupt_name)
			'ready_slot':                 ready_slot
			'runtime_interrupts_per_die': j.Value('length of the merged base+variant property / 20; only the running system observes the selected variant')
		})
		'sgx':             j.Value(map[string]j.Value{
			'path':        j.Value(sgx_path)
			'power_gates': maps_value(power_gates)
			'clock_gates': maps_value(clock_gates)
		})
		'gfx_asc_gates':   j.Value(gfx_handles)
		'apple_ptd_mmio':  j.Value(map[string]j.Value{
			'reg_map':               j.Value(8)
			'device_tree_reg_index': j.Value(ptd_reg_index)
			'region_size':           j.Value(ptd_region.bytes)
			'die_stride':            j.Value(die_stride)
			'die_bases':             j.Value(ptd_die_bases.map(j.Value(it)))
			'mapping':               j.Value('Device MMIO; never normal-cacheable memory')
		})
		'pmp':             j.Value(map[string]j.Value{
			'path':                          j.Value(pmp_path)
			'nub_path':                      j.Value(nub_path)
			'role':                          j.Value('PMP1')
			'firmware':                      j.Value('t6050pmp')
			'version':                       j.Value(pmp_version)
			'region_base':                   j.Value(a.decode_integer(nub.property('region-base')!, 'PMP region-base')!)
			'region_size':                   j.Value(a.decode_integer(nub.property('region-size')!, 'PMP region-size')!)
			'dies':                          j.Value([j.Value(map[string]j.Value{
				'die':                  j.Value(0)
				'role':                 j.Value('PMP0')
				'path':                 j.Value(pmp0_path)
				'nub_path':             j.Value(pmp0_nub_path)
				'region_base':          j.Value(pmp_regions[0].address)
				'region_size':          j.Value(pmp_regions[0].bytes)
				'wrapper_registers':    region_rows(wrapper_registers['PMP0'])
				'interrupts':           j.Value(wrapper_interrupts['PMP0'].map(j.Value(it)))
				'iop_version':          j.Value(1)
				'cpu_control_filtered': j.Value(false)
				'ptd_update_reg_index': j.Value(3)
				'sram_power_domain':    j.Value(map[string]j.Value{
					'property':             j.Value('sram-index')
					'selector':             j.Value(1)
					'not_a_register_index': j.Value(true)
				})
			}), j.Value(map[string]j.Value{
				'die':                  j.Value(1)
				'role':                 j.Value('PMP1')
				'path':                 j.Value(pmp_path)
				'nub_path':             j.Value(nub_path)
				'region_base':          j.Value(pmp_regions[1].address)
				'region_size':          j.Value(pmp_regions[1].bytes)
				'wrapper_registers':    region_rows(wrapper_registers['PMP1'])
				'interrupts':           j.Value(wrapper_interrupts['PMP1'].map(j.Value(it)))
				'iop_version':          j.Value(1)
				'cpu_control_filtered': j.Value(false)
				'ptd_update_reg_index': j.Value(3)
				'sram_power_domain':    j.Value(map[string]j.Value{
					'property':             j.Value('sram-index')
					'selector':             j.Value(1)
					'not_a_register_index': j.Value(true)
				})
			})])
			'darts':                         maps_value(pmp_darts)
			'agx_soc_device':                j.Value(agx_device)
			'soc_device_count':              j.Value(soc_devices.len)
			'soc_device_packet':             j.Value(map[string]j.Value{
				'unit':                   j.Value('bits')
				'consumed_bits':          j.Value(packet_cursor - j.value(packet_range, 'entry_offset').u64())
				'trailing_reserved_bits': j.Value(packet_end - packet_cursor)
			})
			'device_index_map':              j.Value(map[string]j.Value{
				'key':       j.Value('soc-device id')
				'value':     j.Value('soc-device record index')
				'agx_key':   j.value(agx_device, 'id')
				'agx_value': j.value(agx_device, 'index')
			})
			'device_state_target':           j.Value(device_state_target)
			'leaf_gate_state_notifications': j.Value(false)
			'readiness_status_range':        j.Value(readiness_range)
			'device_state_dashboard':        j.Value(dashboard)
		})
	}).as_map()
}

struct HandleName {
	handle u64
	name   string
}

fn handle_names_repr(values []HandleName) string {
	return '[' + values.map('(${it.handle}, ${j.quoted(it.name)})').join(', ') + ']'
}

fn pmgr_devices_repr(devices []a.PmgrDevice) string {
	return '[' + devices.map('PmgrDevice(index=${it.index}, handle=${it.handle}, name=${j.quoted(it.name)}, flags=${it.flags}, pmp_selector=${it.pmp_selector}, pmp_virtual_class=${it.pmp_virtual_class})').join(', ') + ']'
}
