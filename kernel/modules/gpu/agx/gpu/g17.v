module gpu

// Ownership graph for the dual-role G17 firmware bootstrap. Every allocation
// below has an independently recovered size and publication site. The graph
// is constructed separately from the legacy G13 InitData so an incomplete
// G17 bring-up can never fall through to the older ABI.

import gpu.agx.fw
import gpu.agx.pgtable
import lib

// GART range 10 in the pinned G17C host driver. Apple dedicates this 20 MiB
// canonical-high interval to firmware PIO mappings. Vinix leaves a deliberate
// fault-catching UAT guard page between independently mapped records.
const g17_pio_va_start = u64(0xfffffc2180000000)
const g17_pio_va_end = u64(0xfffffc2181400000)

struct G17FirmwareGraph {
mut:
	roots                 [2]SharedBuffer
	bootstrap_region      SharedBuffer
	firmware_shared       [2]SharedBuffer
	runtime               SharedBuffer
	small_shared          [2]SharedBuffer
	primary_region        SharedBuffer
	secondary_region      SharedBuffer
	secondary_aux         SharedBuffer
	hardware_config       SharedBuffer
	common_control        SharedBuffer
	large_regions         [2]SharedBuffer
	role0_regions         [5]SharedBuffer
	role1_secondary       SharedBuffer
	accelerator_state     [2]SharedBuffer
	accelerator_entries   [2]SharedBuffer
	auxiliary             [2][8]SharedBuffer
	structurally_ready    bool
	runtime_policy_ready  bool
	platform_values_ready bool
	pio_mappings_ready    bool
	hardware_config_ready bool
}

@[inline]
fn (buffer &SharedBuffer) cpu_address() voidptr {
	return voidptr(buffer.phys + higher_half)
}

fn role0_region_size(index int) ?u64 {
	return match index {
		0 { fw.g17_role0_bootstrap_254_size }
		1 { fw.g17_role0_bootstrap_25c_size }
		2 { fw.g17_role0_bootstrap_264_size }
		3 { fw.g17_role0_bootstrap_26c_size }
		4 { fw.g17_role0_bootstrap_274_size }
		else { none }
	}
}

fn (mut mgr GpuManager) allocate_g17_firmware_graph() ?&G17FirmwareGraph {
	mut graph := &G17FirmwareGraph{}

	graph.bootstrap_region = mgr.alloc_shared_buffer(fw.g17_bootstrap_region_size) or {
		return none
	}
	graph.runtime = mgr.alloc_shared_buffer(fw.g17_runtime_data_size) or { return none }
	graph.primary_region = mgr.alloc_shared_buffer(fw.g17_primary_region_size) or {
		return none
	}
	graph.secondary_region = mgr.alloc_shared_buffer(fw.g17_secondary_region_size) or {
		return none
	}
	graph.secondary_aux = mgr.alloc_shared_buffer(fw.g17_secondary_aux_size) or {
		return none
	}
	graph.hardware_config = mgr.alloc_shared_buffer(fw.g17_hardware_config_size) or {
		return none
	}
	graph.common_control = mgr.alloc_shared_buffer(fw.g17_common_control_size) or {
		return none
	}
	graph.role1_secondary = mgr.alloc_shared_buffer(fw.g17_role1_secondary_471_size) or {
		return none
	}

	for role := 0; role < 2; role++ {
		graph.roots[role] = mgr.alloc_shared_buffer(fw.g17_bootstrap_page_size) or {
			return none
		}
		graph.firmware_shared[role] = mgr.alloc_shared_buffer(fw.g17_firmware_shared_data_size) or {
			return none
		}
		graph.small_shared[role] = mgr.alloc_shared_buffer(fw.g17_small_shared_data_size) or {
			return none
		}
		graph.large_regions[role] = mgr.alloc_shared_buffer(fw.g17_role_large_region_size) or {
			return none
		}
		graph.accelerator_state[role] = mgr.alloc_shared_buffer(fw.g17_accelerator_ring_state_size) or {
			return none
		}
		graph.accelerator_entries[role] = mgr.alloc_shared_buffer(fw.g17_accelerator_ring_entries_size) or {
			return none
		}
		for index := 0; index < fw.g17_auxiliary_ring_address_count; index++ {
			size := fw.g17_auxiliary_ring_size(u32(index)) or { return none }
			graph.auxiliary[role][index] = mgr.alloc_shared_buffer(size) or { return none }
		}
	}

	for index := 0; index < 5; index++ {
		size := role0_region_size(index) or { return none }
		graph.role0_regions[index] = mgr.alloc_shared_buffer(size) or { return none }
	}

	return graph
}

fn unmap_g17_pio_prefix(mapped_vas &[fw.g17_io_mapping_count]u64,
	mapped_sizes &[fw.g17_io_mapping_count]u64, count int) {
	if uat_mgr == unsafe { nil } {
		return
	}
	for index := 0; index < count; index++ {
		if mapped_sizes[index] != 0 {
			uat_mgr.unmap_kernel(mapped_vas[index], mapped_sizes[index])
		}
	}
}

// Install the active hardware-config PIO records into Apple's firmware MMIO
// aperture. A single unaligned physical record is page-aligned exactly as
// createFWPIOMapping does, while the published firmware VA retains its byte
// offset within that page. G17C's selected address converter is the identity.
fn (mut mgr GpuManager) map_g17_pio_records(mut graph G17FirmwareGraph) bool {
	if uat_mgr == unsafe { nil } {
		return false
	}

	mut mapped_vas := [fw.g17_io_mapping_count]u64{}
	mut mapped_sizes := [fw.g17_io_mapping_count]u64{}
	mut mapped_count := 0
	mut next_va := g17_pio_va_start
	unsafe {
		mut config := &fw.G17HardwareConfig(graph.hardware_config.cpu_address())
		for index := 0; index < fw.g17_io_mapping_count; index++ {
			mut record := &config.io_mappings_640[index]
			if record.physical_address == 0 && record.total_size == 0 {
				continue
			}
			// The recovered G17 records all have one physical element. Reject
			// unsupported scatter mappings instead of treating them as linear.
			if record.physical_address == 0 || record.total_size == 0
				|| record.element_size != record.total_size || record.flags & 1 != 0 {
				unmap_g17_pio_prefix(mapped_vas, mapped_sizes, mapped_count)
				return false
			}

			page_offset := record.physical_address & pgtable.uat_pg_mask
			physical_page := record.physical_address & ~pgtable.uat_pg_mask
			span := page_offset + u64(record.total_size)
			if span < page_offset {
				unmap_g17_pio_prefix(mapped_vas, mapped_sizes, mapped_count)
				return false
			}
			map_size := lib.align_up(span, pgtable.uat_pgsz)
			if map_size == 0 || next_va > g17_pio_va_end
				|| map_size > g17_pio_va_end - next_va {
				unmap_g17_pio_prefix(mapped_vas, mapped_sizes, mapped_count)
				return false
			}

			protection := if record.flags & 2 != 0 {
				pgtable.gpu_prot_fw_mmio_rw
			} else {
				pgtable.gpu_prot_fw_mmio_ro
			}
			if !uat_mgr.map_kernel(next_va, physical_page, map_size, protection) {
				unmap_g17_pio_prefix(mapped_vas, mapped_sizes, mapped_count)
				return false
			}
			record.virtual_address = next_va + page_offset
			mapped_vas[mapped_count] = next_va
			mapped_sizes[mapped_count] = map_size
			mapped_count++

			if map_size + pgtable.uat_pgsz < map_size
				|| map_size + pgtable.uat_pgsz > g17_pio_va_end - next_va {
				next_va = g17_pio_va_end
			} else {
				next_va += map_size + pgtable.uat_pgsz
			}
		}
	}
	graph.pio_mappings_ready = mapped_count == 12
	return graph.pio_mappings_ready
}

fn (mut mgr GpuManager) populate_g17_firmware_graph(mut graph G17FirmwareGraph) bool {
	if !fw.initialize_g17_bootstrap_region(graph.bootstrap_region.cpu_address(), fw.g17_bootstrap_region_size) {
		return false
	}
	if !fw.initialize_g17_role0_region_25c(graph.role0_regions[1].cpu_address(), fw.g17_role0_bootstrap_25c_size) {
		return false
	}
	if !fw.initialize_g17_hardware_config(graph.hardware_config.cpu_address(), fw.g17_hardware_config_size, &mgr.hw_config) {
		return false
	}
	if !mgr.map_g17_pio_records(mut graph) {
		return false
	}
	if !fw.initialize_g17_runtime_power_policy(graph.runtime.cpu_address(), fw.g17_runtime_data_size) {
		return false
	}
	if !fw.initialize_g17_runtime_performance_policy(graph.runtime.cpu_address(), fw.g17_runtime_data_size) {
		return false
	}
	if !fw.initialize_g17_runtime_platform_policy(graph.runtime.cpu_address(), fw.g17_runtime_data_size) {
		return false
	}
	graph.runtime_policy_ready = true

	for role := 0; role < 2; role++ {
		if !fw.initialize_g17_small_shared_data(graph.small_shared[role].cpu_address(), fw.g17_small_shared_data_size, 0) {
			return false
		}

		accelerator := fw.G17AcceleratorRingAddresses{
			read_index_address: graph.accelerator_state[role].va
			cfi_index_address: graph.accelerator_state[role].va + 0x10
			write_index_address: graph.accelerator_state[role].va + 0x20
			entries_address: graph.accelerator_entries[role].va
		}
		mut auxiliary := [8]u64{}
		for index := 0; index < fw.g17_auxiliary_ring_address_count; index++ {
			auxiliary[index] = graph.auxiliary[role][index].va
		}
		mut role0_addresses := [5]u64{}
		for index := 0; index < 5; index++ {
			role0_addresses[index] = graph.role0_regions[index].va
		}
		bindings := fw.G17FirmwareSharedBindings{
			role: u32(role)
			hardware_config_address: graph.hardware_config.va
			common_control_address: graph.common_control.va
			large_region_address: graph.large_regions[role].va
			role0_bootstrap_addresses: role0_addresses
			accelerator_ring: accelerator
			auxiliary_ring_addresses: auxiliary
			role1_secondary_address: graph.role1_secondary.va
			// G17's selected halGetDefaultUscMaxTgmem implementation returns
			// 12. GVDM mode starts at its zero/default sentinel, and the
			// shared calibration source is explicitly cleared by configureDevice.
			platform_value_300: fw.g17_default_usc_max_tgmem
			platform_value_304: 0
		}
		if !fw.initialize_g17_firmware_shared_data(graph.firmware_shared[role].cpu_address(), fw.g17_firmware_shared_data_size, bindings) {
			return false
		}
	}
	graph.platform_values_ready = true

	platform_config := fw.new_g17_platform_config()
	if !fw.initialize_g17_bootstrap_page(graph.roots[0].cpu_address(), fw.g17_bootstrap_page_size, 0, graph.bootstrap_region.va, graph.firmware_shared[0].va, graph.runtime.va, graph.small_shared[0].va, graph.primary_region.va, 0, 0, voidptr(&platform_config), fw.g17_platform_config_size) {
		return false
	}
	if !fw.initialize_g17_bootstrap_page(graph.roots[1].cpu_address(), fw.g17_bootstrap_page_size, 1, graph.bootstrap_region.va, graph.firmware_shared[1].va, graph.runtime.va, graph.small_shared[1].va, 0, graph.secondary_region.va, graph.secondary_aux.va, voidptr(&platform_config), fw.g17_platform_config_size) {
		return false
	}

	graph.structurally_ready = true
	return true
}

// Construct the recovered allocation graph, but fail closed before MSG_INIT.
// Hardware-config scalar and derived-power producers remain incomplete.
fn (mut mgr GpuManager) init_g17_firmware_data() bool {
	mut graph := mgr.allocate_g17_firmware_graph() or {
		C.printf(c'agx: failed to allocate G17 firmware graph\n')
		return false
	}
	if !mgr.populate_g17_firmware_graph(mut graph) {
		C.printf(c'agx: failed to populate G17 firmware graph\n')
		return false
	}
	mgr.initdata_va = graph.roots[0].va
	mgr.initdata_phys = graph.roots[0].phys
	C.printf(c'agx: G17 graph, runtime policy, mapped PIO records, and shared platform values ready; hardware config remains incomplete\n')
	return graph.structurally_ready && graph.runtime_policy_ready && graph.platform_values_ready
		&& graph.pio_mappings_ready && graph.hardware_config_ready
}
