module power

// Read-only native Apple DeviceTree validation for the T6050 GPU power path.
// Actual PMP transitions remain disabled until service/initial-sync ordering,
// transport ownership, and failure recovery are implemented.

import devicetree

const pmgr_device_record_size = u32(48)
const pmgr_device_flags_offset = u32(0)
const pmgr_device_selector_offset = u32(3)
const pmgr_device_virtual_class_offset = u32(15)
const pmgr_device_handle_offset = u32(26)
const pmgr_device_name_offset = u32(32)
const pmgr_device_name_size = u32(16)
const pmp_ptd_record_size = u32(32)
const pmp_ptd_name_offset = u32(16)
const pmp_ptd_name_size = u32(16)
const t6050_ptd_reg_index = 7
const t6050_ptd_base = u64(0x84240000)
const t6050_ptd_size = u64(0x40000)
const t6050_die_stride = u64(0x4000000000)

fn read_native_u8(data voidptr, offset u32) u8 {
	value := unsafe { &u8(u64(data) + offset) }
	return unsafe { value[0] }
}

fn read_native_u16(data voidptr, offset u32) u16 {
	value := unsafe { &u8(u64(data) + offset) }
	return unsafe { u16(value[0]) | (u16(value[1]) << 8) }
}

fn read_native_u32(data voidptr, offset u32) u32 {
	value := unsafe { &u8(u64(data) + offset) }
	return unsafe {
		u32(value[0]) | (u32(value[1]) << 8) | (u32(value[2]) << 16) |
			(u32(value[3]) << 24)
	}
}

fn fixed_native_name_matches(data voidptr, size u32, expected string) bool {
	if expected.len >= int(size) {
		return false
	}
	value := unsafe { &u8(data) }
	for index := 0; index < expected.len; index++ {
		if unsafe { value[index] } != expected[index] {
			return false
		}
	}
	return unsafe { value[expected.len] } == 0
}

fn node_string_contains(node &devicetree.DTNode, property string, expected string) bool {
	values := devicetree.get_string_list(node, property) or { return false }
	for value in values {
		if value == expected {
			return true
		}
	}
	return false
}

fn native_properties_equal(left &devicetree.DTNode, right &devicetree.DTNode,
	property string) bool {
	left_value := devicetree.get_property(left, property) or { return false }
	right_value := devicetree.get_property(right, property) or { return false }
	if left_value.len != right_value.len {
		return false
	}
	left_bytes := unsafe { &u8(left_value.data) }
	right_bytes := unsafe { &u8(right_value.data) }
	for index := u32(0); index < left_value.len; index++ {
		if unsafe { left_bytes[index] } != unsafe { right_bytes[index] } {
			return false
		}
	}
	return true
}

fn find_native_asc_node(role u32) ?&devicetree.DTNode {
	name := if role == 0 { 'gfx-asc' } else { 'gfx1-asc' }
	if node := devicetree.find_node('/arm-io/${name}') {
		return node
	}
	if node := devicetree.find_node('/soc/${name}') {
		return node
	}
	return none
}

fn validate_gate_array(node &devicetree.DTNode, property string, expected []u32) bool {
	values := devicetree.get_le_u32_array(node, property) or {
		C.printf(c'agx: native node %s has malformed %s\n', node.name.str, property.str)
		return false
	}
	if values.len != expected.len {
		C.printf(c'agx: native node %s has unexpected %s count\n', node.name.str, property.str)
		return false
	}
	for index := 0; index < expected.len; index++ {
		if values[index] != expected[index] {
			C.printf(c'agx: native node %s has unexpected %s[%u]=0x%x\n', node.name.str,
				property.str, u32(index), values[index])
			return false
		}
	}
	return true
}

fn validate_u32_array(node &devicetree.DTNode, property string, expected []u32) bool {
	values := devicetree.get_le_u32_array(node, property) or {
		C.printf(c'agx: native node %s has malformed %s\n', node.name.str, property.str)
		return false
	}
	if values.len != expected.len {
		C.printf(c'agx: native node %s has unexpected %s count\n', node.name.str, property.str)
		return false
	}
	for index := 0; index < expected.len; index++ {
		if values[index] != expected[index] {
			C.printf(c'agx: native node %s has unexpected %s[%u]=0x%x\n', node.name.str,
				property.str, u32(index), values[index])
			return false
		}
	}
	return true
}

// Apple DeviceTree gate values are public u16 handles at +0x1a in PMGR's
// 48-byte device records. They are not MMIO offsets. Require one exact name
// match so an OS/device-tree change cannot turn a handle into a raw write.
fn validate_pmgr_device(pmgr_node &devicetree.DTNode, handle u16,
	expected_name string, expected_index u32, expected_flags u8, expected_selector u8,
	expected_virtual_class u8) bool {
	devices := devicetree.get_property(pmgr_node, 'devices') or {
		println('agx: t6050 PMGR has no device table')
		return false
	}
	if devices.len == 0 || devices.len % pmgr_device_record_size != 0 {
		println('agx: t6050 PMGR device table is malformed')
		return false
	}
	mut matches := u32(0)
	for record := u32(0); record < devices.len; record += pmgr_device_record_size {
		if read_native_u16(devices.data, record + pmgr_device_handle_offset) != handle {
			continue
		}
		name := unsafe { voidptr(u64(devices.data) + record + pmgr_device_name_offset) }
		if !fixed_native_name_matches(name, pmgr_device_name_size, expected_name) {
			C.printf(c'agx: t6050 PMGR handle 0x%x has an unexpected device name\n', u32(handle))
			return false
		}
		index := record / pmgr_device_record_size
		if index != expected_index
			|| read_native_u8(devices.data, record + pmgr_device_flags_offset) != expected_flags
			|| read_native_u8(devices.data, record + pmgr_device_selector_offset) != expected_selector
			|| read_native_u8(devices.data, record + pmgr_device_virtual_class_offset) != expected_virtual_class {
			C.printf(c'agx: t6050 PMGR device %s changed dispatch fields\n', expected_name.str)
			return false
		}
		matches++
	}
	if matches != 1 {
		C.printf(c'agx: t6050 PMGR handle 0x%x resolved %u times\n', u32(handle), matches)
		return false
	}
	return true
}

fn validate_ptd_range(nub &devicetree.DTNode, expected_name string,
	expected_id u32, expected_offset u32, expected_count u32, expected_doorbell u32) bool {
	ranges := devicetree.get_property(nub, 'ptd-range') or {
		println('agx: t6050 PMP has no PTD range table')
		return false
	}
	if ranges.len == 0 || ranges.len % pmp_ptd_record_size != 0 {
		println('agx: t6050 PMP PTD range table is malformed')
		return false
	}
	mut matches := u32(0)
	for record := u32(0); record < ranges.len; record += pmp_ptd_record_size {
		name := unsafe { voidptr(u64(ranges.data) + record + pmp_ptd_name_offset) }
		if !fixed_native_name_matches(name, pmp_ptd_name_size, expected_name) {
			continue
		}
		if read_native_u32(ranges.data, record) != expected_id
			|| read_native_u32(ranges.data, record + 4) != expected_offset
			|| read_native_u32(ranges.data, record + 8) != expected_count
			|| read_native_u32(ranges.data, record + 12) != expected_doorbell {
			C.printf(c'agx: t6050 PMP range %s changed layout\n', expected_name.str)
			return false
		}
		matches++
	}
	if matches != 1 {
		C.printf(c'agx: t6050 PMP range %s resolved %u times\n', expected_name.str, matches)
		return false
	}
	return true
}

fn validate_ptd_apertures(pmgr_node &devicetree.DTNode) bool {
	regions := devicetree.get_translated_reg_ranges(pmgr_node) or {
		println('agx: t6050 PMGR register table is malformed')
		return false
	}
	if regions.len != 60 {
		C.printf(c'agx: t6050 PMGR has %u register regions, expected 60\n', u32(regions.len))
		return false
	}
	ptd := regions[t6050_ptd_reg_index]
	if ptd.base != t6050_ptd_base || ptd.size != t6050_ptd_size {
		C.printf(c'agx: t6050 PTD reg[7] changed to 0x%llx+0x%llx\n', ptd.base,
			ptd.size)
		return false
	}
	die_stride := devicetree.get_le_u64(pmgr_node, 'die-stride') or {
		println('agx: t6050 PMGR has no die stride')
		return false
	}
	if die_stride != t6050_die_stride {
		C.printf(c'agx: t6050 PMGR die stride changed to 0x%llx\n', die_stride)
		return false
	}
	// AppleT6050PMGR maps this same RegMap entry once per die. Keep both
	// physical results explicit even though this validator performs no mapping.
	if ptd.base + die_stride != 0x4084240000 {
		println('agx: t6050 die-1 PTD aperture changed')
		return false
	}
	return true
}

// Validate only the read-only ownership and transport contract here. Apple's
// initial synchronization can publish a persistent request before readiness,
// but Vinix still needs mapping ownership, serialized transactions, timeout
// cleanup, and the firmware-side handoff. This function therefore performs no
// mapping or MMIO access.
pub fn validate_t6050_contract(gpu_node &devicetree.DTNode) bool {
	pmgr_node := devicetree.find_compatible('pmgr1,t6050') or {
		println('agx: native t6050 PMGR node not found')
		return false
	}
	gfx_asc := find_native_asc_node(0) or { return false }
	gfx1_asc := find_native_asc_node(1) or { return false }
	pmp := devicetree.find_node('/arm-io/pmp1') or {
		println('agx: native t6050 PMP1 node not found')
		return false
	}
	pmp0 := devicetree.find_node('/arm-io/pmp0') or {
		println('agx: native t6050 PMP0 node not found')
		return false
	}
	pmp_nub := devicetree.find_node('/arm-io/pmp1/iop-pmp1-nub') or {
		println('agx: native t6050 PMP1 RTKit nub not found')
		return false
	}
	pmp0_nub := devicetree.find_node('/arm-io/pmp0/iop-pmp0-nub') or {
		println('agx: native t6050 PMP0 RTKit nub not found')
		return false
	}
	if !node_string_contains(pmp0, 'compatible', 'iop,ascwrap-v6')
		|| !node_string_contains(pmp0, 'role', 'PMP0')
		|| !node_string_contains(pmp, 'compatible', 'iop,ascwrap-v6')
		|| !node_string_contains(pmp, 'role', 'PMP1')
		|| !node_string_contains(pmp0_nub, 'compatible', 'iop-nub,rtbuddy-v2')
		|| !node_string_contains(pmp0_nub, 'firmware-name', 't6050pmp')
		|| !node_string_contains(pmp_nub, 'compatible', 'iop-nub,rtbuddy-v2')
		|| !node_string_contains(pmp_nub, 'firmware-name', 't6050pmp') {
		println('agx: native t6050 PMP ownership changed')
		return false
	}
	pmp0_region_base := devicetree.get_le_u64(pmp0_nub, 'region-base') or { return false }
	pmp1_region_base := devicetree.get_le_u64(pmp_nub, 'region-base') or { return false }
	pmp0_region_size := devicetree.get_le_u64(pmp0_nub, 'region-size') or { return false }
	pmp1_region_size := devicetree.get_le_u64(pmp_nub, 'region-size') or { return false }
	if pmp0_region_base != 0x284500000 || pmp1_region_base != 0x4284500000
		|| pmp0_region_size != 0x100000 || pmp1_region_size != 0x100000
		|| pmp1_region_base - pmp0_region_base != t6050_die_stride
		|| !native_properties_equal(pmp0_nub, pmp_nub, 'soc-device')
		|| !native_properties_equal(pmp0_nub, pmp_nub, 'ptd-range')
		|| !native_properties_equal(pmp0_nub, pmp_nub, 'pm-ptd-ranges') {
		println('agx: native t6050 PMP die contracts differ')
		return false
	}
	pmp_version := devicetree.get_le_u32(pmgr_node, 'pmp') or {
		println('agx: t6050 PMGR has no PMP version')
		return false
	}
	if pmp_version != 2
		|| !validate_u32_array(pmgr_node, 'ptd-ranges', [u32(10), 11, 12, 13, 2, 4])
		|| !validate_ptd_apertures(pmgr_node) {
		println('agx: native t6050 ApplePTD ownership changed')
		return false
	}
	if !validate_gate_array(gpu_node, 'power-gates', [u32(0x268), 0x267])
		|| !validate_gate_array(gpu_node, 'clock-gates', [u32(0x268), 0x267])
		|| !validate_gate_array(gfx_asc, 'power-gates', [u32(0x266)])
		|| !validate_gate_array(gfx_asc, 'clock-gates', [u32(0x266)])
		|| !validate_gate_array(gfx1_asc, 'power-gates', [u32(0x291)])
		|| !validate_gate_array(gfx1_asc, 'clock-gates', [u32(0x291)]) {
		return false
	}
	if !validate_pmgr_device(pmgr_node, 0x268, 'GFX_SGX', 572, 0x10, 0, 0)
		|| !validate_pmgr_device(pmgr_node, 0x267, 'GFX_BUSY', 575, 0x10, 0, 0)
		|| !validate_pmgr_device(pmgr_node, 0x266, 'GFX_ASC', 573, 0x10, 0, 0)
		|| !validate_pmgr_device(pmgr_node, 0x291, 'GFX_ASC1', 574, 0x10, 0, 0)
		|| !validate_pmgr_device(pmgr_node, 0x16a, 'GFX', 357, 0x02, 0x10, 0) {
		return false
	}
	if !validate_ptd_range(pmp_nub, 'PMP-STATUS', 2, 1, 1, 16)
		|| !validate_ptd_range(pmp_nub, 'SOC-DEV-PKT', 9, 0x90, 0x150, 0)
		|| !validate_ptd_range(pmp_nub, 'SOC-DEV-PS-REQ', 10, 0x1e0, 8, 0)
		|| !validate_ptd_range(pmp_nub, 'SOC-DEV-PS-ACK', 11, 0x1e8, 8, 0)
		|| !validate_u32_array(pmp_nub, 'pm-ptd-ranges', [u32(1), 2, 3, 4, 5, 6,
			7, 8, 40, 9, 10, 11, 12, 13, 14]) {
		return false
	}
	println('agx: validated native t6050 PMP power ownership (read-only)')
	return true
}
