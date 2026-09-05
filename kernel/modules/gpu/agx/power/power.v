module power

// Read-only native Apple DeviceTree validation for the T6050 GPU power path.
// Actual PMP transitions remain disabled until its runtime device-index table,
// request/ack synchronization, and failure recovery are implemented.

import devicetree

const pmgr_device_record_size = u32(48)
const pmgr_device_handle_offset = u32(26)
const pmgr_device_name_offset = u32(32)
const pmgr_device_name_size = u32(16)
const pmp_ptd_record_size = u32(32)
const pmp_ptd_name_offset = u32(16)
const pmp_ptd_name_size = u32(16)

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

// Apple DeviceTree gate values are public u16 handles at +0x1a in PMGR's
// 48-byte device records. They are not MMIO offsets. Require one exact name
// match so an OS/device-tree change cannot turn a handle into a raw write.
fn validate_pmgr_handle(pmgr_node &devicetree.DTNode, handle u16,
	expected_name string) bool {
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
		matches++
	}
	if matches != 1 {
		C.printf(c'agx: t6050 PMGR handle 0x%x resolved %u times\n', u32(handle), matches)
		return false
	}
	return true
}

fn validate_ptd_range(nub &devicetree.DTNode, expected_name string,
	expected_id u32, expected_offset u32, expected_count u32) bool {
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
			|| read_native_u32(ranges.data, record + 8) != expected_count {
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

fn power_range_contains(nub &devicetree.DTNode, expected_id u32) bool {
	ranges := devicetree.get_le_u32_array(nub, 'pm-ptd-ranges') or { return false }
	for range_id in ranges {
		if range_id == expected_id {
			return true
		}
	}
	return false
}

// Validate only the read-only ownership contract here. The running PMP still
// has to publish its device-index translation before SOC-DEV-PS-REQ can be
// written, so this function deliberately performs no mapping or MMIO access.
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
	pmp_nub := devicetree.find_node('/arm-io/pmp1/iop-pmp1-nub') or {
		println('agx: native t6050 PMP1 RTKit nub not found')
		return false
	}
	if !node_string_contains(pmp, 'compatible', 'iop,ascwrap-v6')
		|| !node_string_contains(pmp, 'role', 'PMP1')
		|| !node_string_contains(pmp_nub, 'compatible', 'iop-nub,rtbuddy-v2')
		|| !node_string_contains(pmp_nub, 'firmware-name', 't6050pmp') {
		println('agx: native t6050 PMP1 ownership changed')
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
	if !validate_pmgr_handle(pmgr_node, 0x268, 'GFX_SGX')
		|| !validate_pmgr_handle(pmgr_node, 0x267, 'GFX_BUSY')
		|| !validate_pmgr_handle(pmgr_node, 0x266, 'GFX_ASC')
		|| !validate_pmgr_handle(pmgr_node, 0x291, 'GFX_ASC1') {
		return false
	}
	if !validate_ptd_range(pmp_nub, 'SOC-DEV-PKT', 9, 0x90, 0x150)
		|| !validate_ptd_range(pmp_nub, 'SOC-DEV-PS-REQ', 10, 0x1e0, 8)
		|| !validate_ptd_range(pmp_nub, 'SOC-DEV-PS-ACK', 11, 0x1e8, 8)
		|| !power_range_contains(pmp_nub, 9)
		|| !power_range_contains(pmp_nub, 10)
		|| !power_range_contains(pmp_nub, 11) {
		return false
	}
	println('agx: validated native t6050 PMP power ownership (read-only)')
	return true
}
