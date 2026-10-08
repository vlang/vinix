module t6050power

import appleadt as a
import math.big
import strconv
import json2
import traceanalysis as j

fn expected_registers_equal(regions []a.Region, die int, stride j.Value) !bool {
	bases := [u64(0x841a0000), u64(0x841b0000)]!
	sizes := [u64(0xc000), u64(0x4000)]!
	match stride {
		string { return error("TypeError: unsupported operand type(s) for +: 'int' and 'str'") }
		[]j.Value { return error("TypeError: unsupported operand type(s) for +: 'int' and 'list'") }
		map[string]j.Value {
			return error("TypeError: unsupported operand type(s) for *: 'int' and 'dict'")
		}
		json2.Null {
			return error("TypeError: unsupported operand type(s) for *: 'int' and 'NoneType'")
		}
		else {}
	}
	if regions.len != 2 { return false }
	for index, region in regions {
		if region.bytes != sizes[index] { return false }
		if stride is j.Number {
			if stride.text.contains_any('.eE') {
				floating := unsafe { C.strtod(&char(stride.text.str), nil) }
				expected := f64(bases[index]) + f64(die) * floating
				if !integer_equal(j.Value(region.address), j.Value(j.Number{expected.str()})) {
					return false
				}
				continue
			}
		}
		number := exact_integer(stride) or { return false }
		if big.integer_from_u64(region.address) != big.integer_from_u64(bases[index]) + big.integer_from_int(die) * number {
			return false
		}
	}
	return true
}

pub fn recover_pmp_darts(root a.Node, wrappers map[string]a.Visit, die_stride j.Value) ![]map[string]j.Value {
	expected_sids := [u32(0), 1, 2, 5, 6, 7, 8, 9]
	expected_bypassed := [u64(2), 5, 6, 7, 8, 9]
	expected_translated := [u32(0), 1]
	mut result := []map[string]j.Value{}
	for die, role in ['PMP0', 'PMP1'] {
		dart_name := 'dart-pmp${die}'
		dart_visit := find_selected(root, dart_name, NodeMatch{ name: dart_name, compatible: 'dart,t8110' })!
		dart_path := dart_visit.path
		dart := dart_visit.node
		registers := a.parse_reg_regions(dart.property('reg')!, '${dart_name} reg')!
		registers_match := expected_registers_equal(registers, die, die_stride)!
		sids := a.decode_u32_array(dart.property('sid')!, '${dart_name} sid')!
		page_size := a.decode_integer(dart.property('page-size')!, '${dart_name} page-size')!
		sid_count := a.decode_integer(dart.property('sid-count')!, '${dart_name} sid-count')!
		options := a.decode_integer(dart.property('dart-options')!, '${dart_name} dart-options')!
		flush := a.decode_integer(dart.property('flush-by-dva')!, '${dart_name} flush-by-dva')!
		vm_base := a.decode_integer(dart.property('vm-base')!, '${dart_name} vm-base')!
		vm_size := a.decode_integer(dart.property('vm-size')!, '${dart_name} vm-size')!
		mut bypassed := []u64{}
		// Iterate only published bypass names, then sort them as the original range
		// scan does. This also bounds malformed huge sid-counts without changing keys.
		for name, _ in dart.properties {
			if !name.starts_with('bypass-') { continue }
			text := name['bypass-'.len..]
			sid := strconv.parse_uint(text, 10, 64) or { continue }
			if text == sid.str() && sid < sid_count { bypassed << sid }
		}
		bypassed.sort()
		for sid in bypassed {
			if dart.property('bypass-${sid}')!.len != 0 {
				return error('T6050 ${dart_name} bypass-${sid} is no longer an empty boolean')
			}
		}
		translated := sids.filter(u64(it) !in bypassed)
		if !registers_match || sids != expected_sids || bypassed != expected_bypassed || translated != expected_translated || page_size != 0x4000 || sid_count != 16 || options != 0x65 || flush != 0 || vm_base != 0x10000000000 || vm_size != 0x1000000000 {
			return error('T6050 ${dart_name} contract changed: regs=${region_repr(registers)}, sids=${words_repr(sids)}, bypassed=${j.string_value(j.Value(bypassed.map(j.Value(it))))}, translated=${words_repr(translated)}, page=0x${page_size:x}, count=${sid_count}, options=0x${options:x}, flush=${flush}, vm=0x${vm_base:x}+0x${vm_size:x}')
		}
		mapper_name := 'mapper-pmp${die}'
		mapper_visit := find_selected(dart, mapper_name, NodeMatch{ name: mapper_name, compatible: 'iommu-mapper' })!
		mapper_path := relative_path(mapper_visit.path, dart, dart_path)!
		mapper_index := a.decode_integer(mapper_visit.node.property('reg')!, '${mapper_name} reg')!
		mapper_phandle := a.decode_integer(mapper_visit.node.property('AAPL,phandle')!, '${mapper_name} phandle')!
		wrapper := wrappers[role] or { return error('KeyError: ' + role) }
		wrapper_parent := a.decode_integer(wrapper.node.property('iommu-parent')!, '${role} iommu-parent')!
		if mapper_index != 0 || wrapper_parent != mapper_phandle {
			return error('T6050 ${role} mapper binding changed: index=${mapper_index}, wrapper=0x${wrapper_parent:x}, mapper=0x${mapper_phandle:x}')
		}
		result << {
			'die':                                  j.Value(die)
			'path':                                 j.Value(dart_path)
			'compatible':                           j.Value('dart,t8110')
			'registers':                            region_rows(registers)
			'page_size':                            j.Value(page_size)
			'sid_count':                            j.Value(sid_count)
			'active_sids':                          j.Value(sids.map(j.Value(it)))
			'bypassed_sids':                        j.Value(bypassed.map(j.Value(it)))
			'translated_sids':                      j.Value(translated.map(j.Value(it)))
			'mapper':                               j.Value(map[string]j.Value{
				'path':                 j.Value(mapper_path)
				'index':                j.Value(mapper_index)
				'phandle':              j.Value(mapper_phandle)
				'wrapper_iommu_parent': j.Value(wrapper_parent)
			})
			'managed_vm':                           j.Value(map[string]j.Value{
				'base': j.Value(vm_base)
				'size': j.Value(vm_size)
			})
			'iboot_firmware_iova_below_managed_vm': j.Value(u64(0x1000000) < vm_base)
			'dart_options':                         j.Value(options)
			'flush_by_dva':                         j.Value(flush != 0)
		}
	}
	return result
}
