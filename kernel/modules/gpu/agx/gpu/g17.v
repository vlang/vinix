module gpu

// Ownership graph for the dual-role G17 firmware bootstrap. Every allocation
// below has an independently recovered size and publication site. The graph
// is constructed separately from the legacy G13 InitData so an incomplete
// G17 bring-up can never fall through to the older ABI.

import gpu.agx.fw

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
	if !fw.initialize_g17_runtime_power_policy(graph.runtime.cpu_address(), fw.g17_runtime_data_size) {
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
		}
		if !fw.initialize_g17_firmware_shared_data(graph.firmware_shared[role].cpu_address(), fw.g17_firmware_shared_data_size, bindings) {
			return false
		}
	}

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
// The remaining platform scalars/calibration are populated by Apple-specific
// producers that are not implemented yet.
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
	C.printf(c'agx: G17 graph and zero DPE/PPT policy ready, but platform values are incomplete\n')
	return graph.structurally_ready && graph.runtime_policy_ready && graph.platform_values_ready
}
