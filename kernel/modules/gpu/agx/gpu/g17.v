module gpu

// Ownership graph for the dual-role G17 firmware bootstrap. Every allocation
// below has an independently recovered size and publication site. The graph
// is constructed separately from the legacy G13 InitData so an incomplete
// G17 bring-up can never fall through to the older ABI.

import gpu.agx.fw
import gpu.agx.event
import gpu.agx.pgtable
import gpu.agx.regs
import aarch64.kio
import aarch64.cpu
import apple.mailbox
import klock
import lib
import memory

// GART range 10 in the pinned G17C host driver. Apple dedicates this 20 MiB
// canonical-high interval to firmware PIO mappings. Vinix leaves a deliberate
// fault-catching UAT guard page between independently mapped records.
const g17_pio_va_start = u64(0xfffffc2180000000)
const g17_pio_va_end = u64(0xfffffc2181400000)
const g17_work_command_pool_count = 4
const g17_work_channel_count = 3
const g17_work_priority_count = 4

// A Vinix DRM queue owns at most one instance of each native Apple work
// channel. The bit positions deliberately match _AGFIDataMasterType.
pub const g17_queue_channel_ta = u32(1) << fw.g17_accelerator_command_ta
pub const g17_queue_channel_3d = u32(1) << fw.g17_accelerator_command_3d
pub const g17_queue_channel_cl = u32(1) << fw.g17_accelerator_command_cl
const g17_queue_channel_mask = g17_queue_channel_ta | g17_queue_channel_3d |
	g17_queue_channel_cl

struct G17QueueChannelResources {
mut:
	state    SharedBuffer
	uncached SharedBuffer
	cached   SharedBuffer
	lock     klock.Lock
}

// Complete shared-memory ownership for one native G17 command queue. These
// allocations stay separate from the global bootstrap graph because Apple
// creates and tears them down with the userspace queue, not with firmware.
pub struct G17QueueResources {
pub:
	queue_id          u32
	owner_process_id u32
	channel_mask      u32
	ring_entries      u32
	priority          u32
mut:
	scheduler SharedBuffer
	timestamp SharedBuffer
	channels  [g17_work_channel_count]G17QueueChannelResources
	released  bool
}

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
	device_control_state   [2]SharedBuffer
	device_control_entries [2]SharedBuffer
	data_master_state      [g17_work_priority_count][g17_work_channel_count]SharedBuffer
	data_master_entries    [g17_work_priority_count][g17_work_channel_count]SharedBuffer
	data_master_locks      [g17_work_priority_count][g17_work_channel_count]klock.Lock
	auxiliary             [2][8]SharedBuffer
	event_lock            klock.Lock
	command_backings      [g17_work_command_pool_count]SharedBuffer
	command_in_use        [g17_work_command_pool_count]&u8
	command_pools         [g17_work_command_pool_count]fw.G17CommandPool
	structurally_ready    bool
	runtime_policy_ready  bool
	platform_values_ready bool
	pio_mappings_ready    bool
	hardware_config_ready bool
	command_pools_ready   bool
	leakage_calibration   fw.G17LeakageCalibration
	leakage_fuses_ready   bool
}

fn g17_work_command_element_size(index int) ?u32 {
	return match index {
		0 { fw.g17_command_ta_size }
		1 { fw.g17_command_3d_size }
		2 { fw.g17_command_fast_blit_size }
		3 { fw.g17_command_cl_size }
		else { none }
	}
}

@[inline]
fn (buffer &SharedBuffer) cpu_address() voidptr {
	return voidptr(buffer.phys + higher_half)
}

fn (mut mgr GpuManager) free_g17_queue_resources_locked(mut resources G17QueueResources) {
	if resources.released {
		return
	}
	// Close the admission gate before waiting for any in-flight producer.
	// Resource objects remain allocated after release, so a racing producer
	// can observe the flag without dereferencing freed object storage.
	resources.released = true
	for index := g17_work_channel_count - 1; index >= 0; index-- {
		resources.channels[index].lock.acquire()
		mgr.free_shared_buffer(mut resources.channels[index].cached)
		mgr.free_shared_buffer(mut resources.channels[index].uncached)
		mgr.free_shared_buffer(mut resources.channels[index].state)
		resources.channels[index].lock.release()
	}
	mgr.free_shared_buffer(mut resources.timestamp)
	mgr.free_shared_buffer(mut resources.scheduler)
	mgr.allocs.gc()
}

// Allocate and initialize the queue-owned resources recovered from the G17C
// Apple driver. Cached and uncached pool attributes are kept distinct in the
// UAT; treating the producer ring as uncached would change firmware-visible
// ordering even though both mappings point at ordinary physical memory.
pub fn (mut mgr GpuManager) create_g17_queue_resources(queue_id u32,
	owner_process_id u32, channel_mask u32, priority u32) ?&G17QueueResources {
	if queue_id == 0 || owner_process_id == 0 || channel_mask == 0
		|| channel_mask & ~g17_queue_channel_mask != 0
		|| priority >= fw.g17_channel_priority_count {
		return none
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	if mgr.state != .running || mgr.g17_graph == unsafe { nil } {
		return none
	}

	ring_entries := fw.g17_channel_ring_entries(fw.g17_default_configured_work_queues)
	channel_bytes := fw.g17_channel_memory_size(fw.g17_default_configured_work_queues)
	if ring_entries == 0 || channel_bytes < fw.g17_channel_control_header_size {
		return none
	}

	mut resources := &G17QueueResources{
		queue_id: queue_id
		owner_process_id: owner_process_id
		channel_mask: channel_mask
		ring_entries: ring_entries
		priority: priority
	}
	mut complete := false
	defer {
		if !complete {
			mgr.free_g17_queue_resources_locked(mut resources)
		}
	}

	resources.scheduler = mgr.alloc_shared_buffer_with_protection(fw.g17_scheduler_state_size,
		pgtable.gpu_prot_fw_gpu_cached_rw) or { return none }
	resources.timestamp = mgr.alloc_shared_buffer_with_protection(fw.g17_timestamp_state_size,
		pgtable.gpu_prot_fw_gpu_shared_rw) or { return none }
	// AGXTimeStampQueue::init clears host mode +0x38 before its first reset.
	if !fw.initialize_g17_scheduler_state(resources.scheduler.cpu_address(),
		fw.g17_scheduler_state_size, fw.g17_default_app_gpu_role)
		|| !fw.initialize_g17_timestamp_state(resources.timestamp.cpu_address(),
		fw.g17_timestamp_state_size, resources.timestamp.va, false) {
		return none
	}

	for command_type := u32(0); command_type < g17_work_channel_count; command_type++ {
		if channel_mask & (u32(1) << command_type) == 0 {
			continue
		}
		mut channel := &resources.channels[command_type]
		channel.state = mgr.alloc_shared_buffer_with_protection(fw.g17_channel_state_size,
			pgtable.gpu_prot_fw_gpu_cached_rw) or { return none }
		channel.uncached = mgr.alloc_shared_buffer_with_protection(channel_bytes,
			pgtable.gpu_prot_fw_gpu_shared_rw) or { return none }
		channel.cached = mgr.alloc_shared_buffer_with_protection(channel_bytes,
			pgtable.gpu_prot_fw_gpu_cached_rw) or { return none }
		if !fw.initialize_g17_channel(channel.state.cpu_address(), fw.g17_channel_state_size,
			channel.uncached.cpu_address(), channel_bytes, channel.cached.cpu_address(),
			channel_bytes, fw.G17ChannelBindings{
				uncached_gpu_address: channel.uncached.va
				cached_gpu_address: channel.cached.va
				context_cookie: resources.timestamp.va
				owning_process_id: owner_process_id
				queue_address_09c: resources.scheduler.va
				ring_entries: ring_entries
				priority: priority
			}) {
			return none
		}
	}

	mgr.g17_queues << resources
	complete = true
	return resources
}

// Return the firmware-visible channel state used by an outer data-master
// entry. An absent capability remains absent rather than aliasing channel 0.
pub fn (resources &G17QueueResources) channel_state_address(command_type u32) ?u64 {
	if resources.released || command_type >= g17_work_channel_count
		|| resources.channel_mask & (u32(1) << command_type) == 0 {
		return none
	}
	address := resources.channels[command_type].state.va
	if address == 0 {
		return none
	}
	return address
}

// Serialize the cached-pointer producer with the matching uncached indices.
// The still-gated command encoder publishes this before the matching outer
// data-master entry, just as Apple's work-queue path does.
pub fn (mut resources G17QueueResources) enqueue_channel_command(command_type u32,
	command_gpu_address u64) bool {
	if resources.released || command_type >= g17_work_channel_count
		|| resources.channel_mask & (u32(1) << command_type) == 0 {
		return false
	}
	mut channel := &resources.channels[command_type]
	channel.lock.acquire()
	defer {
		channel.lock.release()
	}
	return fw.enqueue_g17_channel_command(channel.uncached.cpu_address(), channel.uncached.size,
		channel.cached.cpu_address(), channel.cached.size, command_gpu_address)
}

pub fn (mut mgr GpuManager) release_g17_queue_resources(resources &G17QueueResources) {
	if resources == unsafe { nil } {
		return
	}
	mgr.lock.acquire()
	defer {
		mgr.lock.release()
	}
	mut owned := unsafe { resources }
	if owned.released {
		return
	}
	for index, candidate in mgr.g17_queues {
		if voidptr(candidate) == voidptr(resources) {
			mgr.g17_queues.delete(index)
			break
		}
	}
	mgr.free_g17_queue_resources_locked(mut owned)
}

// Caller holds the manager lock during shutdown.
fn (mut mgr GpuManager) release_all_g17_queue_resources() {
	for index := mgr.g17_queues.len - 1; index >= 0; index-- {
		mut resources := unsafe { mgr.g17_queues[index] }
		mgr.free_g17_queue_resources_locked(mut resources)
	}
	mgr.g17_queues.clear()
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

// Tear down a graph only while firmware is stopped or before its roots have
// been published. Buffers are released in reverse construction order so the
// grow-only shared-VA heap can reclaim the complete suffix.
fn (mut mgr GpuManager) free_g17_firmware_graph(mut graph G17FirmwareGraph) {
	// PIO mappings point at device apertures rather than owned physical pages.
	// They use their own canonical-high range, so remove them separately.
	if uat_mgr != unsafe { nil } && graph.hardware_config.phys != 0 {
		unsafe {
			config := &fw.G17HardwareConfig(graph.hardware_config.cpu_address())
			for index := 0; index < fw.g17_io_mapping_count; index++ {
				record := config.io_mappings_640[index]
				if record.virtual_address == 0 || record.total_size == 0 {
					continue
				}
				mapping_base := record.virtual_address & ~pgtable.uat_pg_mask
				page_offset := record.virtual_address & pgtable.uat_pg_mask
				span := page_offset + u64(record.total_size)
				if span >= page_offset && span <= u64(-1) - pgtable.uat_pg_mask {
					mapping_size := (span + pgtable.uat_pg_mask) & ~pgtable.uat_pg_mask
					uat_mgr.unmap_kernel(mapping_base, mapping_size)
				}
			}
		}
	}

	for index := g17_work_command_pool_count - 1; index >= 0; index-- {
		if graph.command_in_use[index] != unsafe { nil } {
			memory.free(graph.command_in_use[index])
			graph.command_in_use[index] = unsafe { nil }
		}
		mgr.free_shared_buffer(mut graph.command_backings[index])
	}
	for priority := g17_work_priority_count - 1; priority >= 0; priority-- {
		for command_type := g17_work_channel_count - 1; command_type >= 0; command_type-- {
			mgr.free_shared_buffer(mut graph.data_master_entries[priority][command_type])
			mgr.free_shared_buffer(mut graph.data_master_state[priority][command_type])
		}
	}
	for index := 4; index >= 0; index-- {
		mgr.free_shared_buffer(mut graph.role0_regions[index])
	}
	for role := 1; role >= 0; role-- {
		for index := fw.g17_auxiliary_ring_address_count - 1; index >= 0; index-- {
			mgr.free_shared_buffer(mut graph.auxiliary[role][index])
		}
		mgr.free_shared_buffer(mut graph.device_control_entries[role])
		mgr.free_shared_buffer(mut graph.device_control_state[role])
		mgr.free_shared_buffer(mut graph.large_regions[role])
		mgr.free_shared_buffer(mut graph.small_shared[role])
		mgr.free_shared_buffer(mut graph.firmware_shared[role])
		mgr.free_shared_buffer(mut graph.roots[role])
	}
	mgr.free_shared_buffer(mut graph.role1_secondary)
	mgr.free_shared_buffer(mut graph.common_control)
	mgr.free_shared_buffer(mut graph.hardware_config)
	mgr.free_shared_buffer(mut graph.secondary_aux)
	mgr.free_shared_buffer(mut graph.secondary_region)
	mgr.free_shared_buffer(mut graph.primary_region)
	mgr.free_shared_buffer(mut graph.runtime)
	mgr.free_shared_buffer(mut graph.bootstrap_region)
	mgr.allocs.gc()
}

fn (mut mgr GpuManager) release_g17_firmware_graph() {
	if mgr.g17_graph == unsafe { nil } {
		return
	}
	mut graph := unsafe { mgr.g17_graph }
	mgr.g17_graph = unsafe { nil }
	mgr.free_g17_firmware_graph(mut graph)
}

fn (mut mgr GpuManager) fail_g17_initialization(started_roles u32) bool {
	mgr.stop_firmware_cpus(started_roles)
	mgr.release_g17_firmware_graph()
	mgr.state = .error
	return false
}

fn (mut mgr GpuManager) allocate_g17_firmware_graph() ?&G17FirmwareGraph {
	mut graph := &G17FirmwareGraph{}
	mut complete := false
	defer {
		if !complete {
			mgr.free_g17_firmware_graph(mut graph)
		}
	}

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
		graph.device_control_state[role] = mgr.alloc_shared_buffer(fw.g17_accelerator_ring_state_size) or {
			return none
		}
		graph.device_control_entries[role] = mgr.alloc_shared_buffer(fw.g17_device_control_entries_size) or {
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
	for priority := 0; priority < g17_work_priority_count; priority++ {
		for command_type := 0; command_type < g17_work_channel_count; command_type++ {
			graph.data_master_state[priority][command_type] = mgr.alloc_shared_buffer(fw.g17_accelerator_ring_state_size) or {
				return none
			}
			graph.data_master_entries[priority][command_type] = mgr.alloc_shared_buffer(fw.g17_data_master_entries_bytes) or {
				return none
			}
		}
	}

	// Use Apple's recovered fallback capacity until a device-specific override
	// source is recovered. The four work pools request 3 * 80 elements. Their
	// page-rounded allocations can contain extra complete elements, so allocate
	// one host-only use byte for every actual slot rather than only the request.
	for index := 0; index < g17_work_command_pool_count; index++ {
		element_bytes := g17_work_command_element_size(index) or { return none }
		geometry := fw.g17_command_pool_geometry(element_bytes, fw.g17_fallback_work_command_slots) or {
			return none
		}
		graph.command_backings[index] = mgr.alloc_shared_buffer(geometry.backing_bytes) or {
			return none
		}
		in_use := memory.malloc(u64(geometry.slot_count))
		if in_use == unsafe { nil } {
			return none
		}
		unsafe {
			graph.command_in_use[index] = &u8(in_use)
		}
	}

	complete = true
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
	if uat_mgr == unsafe { nil } {
		return false
	}
	if !fw.initialize_g17_bootstrap_region(graph.bootstrap_region.cpu_address(), fw.g17_bootstrap_region_size) {
		return false
	}
	if !fw.initialize_g17_role0_region_25c(graph.role0_regions[1].cpu_address(), fw.g17_role0_bootstrap_25c_size) {
		return false
	}
	// Apple's selected G17 producer maps this separate read-only eFuse
	// aperture and consumes exactly three words. Snapshot them with volatile
	// MMIO reads, then keep the decoded values in integer quarter-units for the
	// no-FPU power-model stage.
	identity := regs.decode_gpu_identity(mgr.res.sgx_read32(regs.gpu_id_clustercfg))
	chip_variant := regs.decode_gpu_chip_variant(mgr.res.sgx_read32(regs.gpu_id_version)) or {
		return false
	}
	fuse_base := memory.map_mmio(fw.g17_leakage_fuse_physical_address, fw.g17_leakage_fuse_size)
	word_198 := kio.mmin32(unsafe { &u32(fuse_base + fw.g17_leakage_fuse_word_198) })
	word_19c := kio.mmin32(unsafe { &u32(fuse_base + fw.g17_leakage_fuse_word_19c) })
	word_1a0 := kio.mmin32(unsafe { &u32(fuse_base + fw.g17_leakage_fuse_word_1a0) })
	graph.leakage_calibration = fw.decode_g17_leakage_calibration(word_198, word_19c, word_1a0, chip_variant, identity.column_count, identity.group_count) or {
		return false
	}
	graph.leakage_fuses_ready = true
	C.printf(c'agx: decoded G17 leakage calibration for %u power columns / %u groups\n', identity.column_count, identity.group_count)
	// Apple counts enabled cores from the mask registers rather than from a
	// published topology, so read both the total and each power-column slice
	// the same way.
	mut enabled_uscs := [fw.g17_leakage_core_capacity]u32{}
	for column := u32(0); column < identity.column_count; column++ {
		enabled_uscs[column] = mgr.res.enabled_gpu_usc_count(column, identity.units_per_column) or { return false }
	}
	if !fw.initialize_g17_hardware_config(graph.hardware_config.cpu_address(), fw.g17_hardware_config_size, &mgr.hw_config, uat_mgr.ttbs_base, fw.G17LateControlInputs{
		enabled_core_count: mgr.res.enabled_gpu_core_count()
		unit_mask: mgr.res.gpu_unit_count_mask()
	}) {
		return false
	}
	unsafe {
		mut config := &fw.G17HardwareConfig(graph.hardware_config.cpu_address())
		if !fw.populate_g17_power_model(mut config, &mgr.hw_config, &graph.leakage_calibration, fw.G17PowerModelInputs{
			chip_variant: chip_variant
			group_count: identity.group_count
			columns_per_group: identity.columns_per_group
			column_count: identity.column_count
			units_per_column: identity.units_per_column
			enabled_uscs: enabled_uscs
		}) {
			return false
		}
	}
	// Emitting the config is not the same as it being complete; the gate
	// tracks recovered implementation gaps rather than a bare false.
	graph.hardware_config_ready = fw.g17_hardware_config_complete()
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
	for index := 0; index < g17_work_command_pool_count; index++ {
		element_bytes := g17_work_command_element_size(index) or { return false }
		geometry := fw.g17_command_pool_geometry(element_bytes, fw.g17_fallback_work_command_slots) or {
			return false
		}
		backing := &graph.command_backings[index]
		if !fw.initialize_g17_command_pool(mut graph.command_pools[index], backing.cpu_address(), backing.va, backing.size, graph.command_in_use[index], u64(geometry.slot_count), element_bytes, fw.g17_fallback_work_command_slots) {
			return false
		}
	}
	graph.command_pools_ready = true

	for role := 0; role < 2; role++ {
		if !fw.initialize_g17_small_shared_data(graph.small_shared[role].cpu_address(), fw.g17_small_shared_data_size, 0) {
			return false
		}
		if !fw.initialize_g17_accelerator_ring(graph.device_control_state[role].cpu_address(), fw.g17_accelerator_ring_state_size, graph.device_control_entries[role].cpu_address(), fw.g17_device_control_entries_size) {
			return false
		}

		accelerator := fw.G17AcceleratorRingAddresses{
			read_index_address: graph.device_control_state[role].va
			cfi_index_address: graph.device_control_state[role].va + 0x10
			write_index_address: graph.device_control_state[role].va + 0x20
			entries_address: graph.device_control_entries[role].va
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
	// Work submission uses a separate 3 x 4 data-master matrix in the primary
	// large shared region. The role-local 0x4000-byte rings above carry device
	// control commands and have an incompatible 0x40-byte entry format.
	for priority := 0; priority < g17_work_priority_count; priority++ {
		for command_type := 0; command_type < g17_work_channel_count; command_type++ {
			state := &graph.data_master_state[priority][command_type]
			entries := &graph.data_master_entries[priority][command_type]
			if !fw.initialize_g17_accelerator_ring(state.cpu_address(), fw.g17_accelerator_ring_state_size,
				entries.cpu_address(), fw.g17_data_master_entries_bytes) {
				return false
			}
			if !fw.publish_g17_data_master_ring_addresses(graph.large_regions[0].cpu_address(),
				graph.large_regions[0].size, u32(priority), u32(command_type), fw.G17AcceleratorRingAddresses{
					read_index_address: state.va
					cfi_index_address: state.va + 0x10
					write_index_address: state.va + 0x20
					entries_address: entries.va
				}) {
				return false
			}
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

// Construct the recovered allocation graph, but fail closed before MSG_INIT
// while any firmware ABI gap remains.
fn (mut mgr GpuManager) init_g17_firmware_data() bool {
	mut graph := mgr.allocate_g17_firmware_graph() or {
		C.printf(c'agx: failed to allocate G17 firmware graph\n')
		return false
	}
	if !mgr.populate_g17_firmware_graph(mut graph) {
		C.printf(c'agx: failed to populate G17 firmware graph\n')
		mgr.free_g17_firmware_graph(mut graph)
		return false
	}
	mgr.initdata_va = graph.roots[0].va
	mgr.initdata_phys = graph.roots[0].phys
	gaps := fw.g17_hardware_config_gaps()
	if gaps == 0 {
		println('agx: G17 firmware data complete')
	} else {
		C.printf(c'agx: G17 graph ready; hardware config still has gaps 0x%x\n', gaps)
	}
	ready := graph.structurally_ready && graph.runtime_policy_ready && graph.platform_values_ready
		&& graph.pio_mappings_ready && graph.leakage_fuses_ready && graph.hardware_config_ready
		&& graph.command_pools_ready
	if ready {
		mgr.g17_graph = graph
	} else {
		mgr.free_g17_firmware_graph(mut graph)
	}
	return ready
}

// Bring up the two G17 AKF transports without passing through the legacy G13
// InitData/channel path. The whole-chip launch gate remains in driver.v until
// the work-command and completion ABIs are also complete, so this sequence is
// compiled and reviewed before it can touch an M5 Max.
fn (mut mgr GpuManager) init_g17() bool {
	if mgr.firmware_roles != 2 {
		C.printf(c'agx: G17 requires exactly two firmware roles\n')
		mgr.state = .error
		return false
	}

	// Both root mappings must exist before either role can report started: the
	// Apple callback immediately publishes the matching root IOVA.
	if !mgr.init_g17_firmware_data() || mgr.g17_graph == unsafe { nil } {
		C.printf(c'agx: Failed to initialize G17 firmware data\n')
		mgr.state = .error
		return false
	}

	for role := u32(0); role < mgr.firmware_roles; role++ {
		if !mgr.res.start_cpu(role) {
			C.printf(c'agx: Failed to start G17 ASC role %u\n', role)
			return mgr.fail_g17_initialization(role)
		}
	}
	for role := u32(0); role < mgr.firmware_roles; role++ {
		if !mgr.boot_firmware_role(role) {
			C.printf(c'agx: G17 RTKit boot failed for role %u\n', role)
			return mgr.fail_g17_initialization(mgr.firmware_roles)
		}
		if !mgr.start_firmware_endpoint(role, u8(ep_firmware)) {
			C.printf(c'agx: G17 firmware endpoint failed for role %u\n', role)
			return mgr.fail_g17_initialization(mgr.firmware_roles)
		}
	}

	// Publish the final UAT handoff after both firmware endpoints can service
	// it, but before either root is exposed for firmware dereferences.
	if uat_mgr == unsafe { nil } || !uat_mgr.initialize_handoff() {
		C.printf(c'agx: G17 UAT firmware handoff failed\n')
		return mgr.fail_g17_initialization(mgr.firmware_roles)
	}
	for role := u32(0); role < mgr.firmware_roles; role++ {
		root_iova := mgr.g17_graph.roots[role].va
		message := fw.g17_init_message_for_root(root_iova)
		if !mgr.send_role_message(role, u8(ep_firmware), message) {
			C.printf(c'agx: Failed to publish G17 root for role %u\n', role)
			return mgr.fail_g17_initialization(mgr.firmware_roles)
		}
	}

	if !mgr.wait_g17_ready() {
		C.printf(c'agx: G17 firmware ready handshake failed\n')
		return mgr.fail_g17_initialization(mgr.firmware_roles)
	}
	for role := u32(0); role < mgr.firmware_roles; role++ {
		if !mgr.start_firmware_endpoint(role, u8(ep_doorbell)) {
			C.printf(c'agx: G17 doorbell endpoint failed for role %u\n', role)
			return mgr.fail_g17_initialization(mgr.firmware_roles)
		}
	}

	mgr.state = .running
	println('agx: G17 dual-role firmware bootstrap complete')
	return true
}

// Apple decodes bits 53:48. Type 9 consumes a one-shot guard and broadcasts
// 0x89 through both transports. On an eight-interrupt t6050, type 2 signals
// interrupt source 4. Its clearOutstandingFirmwareInterrupts hook is a no-op,
// then the common handler drains both roles' firmware event rings.
fn (mut mgr GpuManager) handle_g17_akf_callback() bool {
	if mgr.g17_graph == unsafe { nil } {
		return false
	}
	mut graph := unsafe { mgr.g17_graph }
	graph.event_lock.acquire()
	defer {
		graph.event_lock.release()
	}

	mut completion_pending := false
	for role := 0; role < 2; role++ {
		state := &graph.auxiliary[role][fw.g17_firmware_event_state_auxiliary_index]
		entries := &graph.auxiliary[role][fw.g17_firmware_event_entries_auxiliary_index]
		for _ in 0 .. fw.g17_firmware_event_ring_entries {
			mut entry := fw.G17FirmwareEventRingEntry{}
			result := fw.dequeue_g17_firmware_event(state.cpu_address(),
				fw.g17_accelerator_ring_state_size, entries.cpu_address(), entries.size,
				&entry)
			if result < 0 {
				C.printf(c'agx: corrupt G17 firmware event ring for role %d\n', role)
				mgr.state = .error
				return false
			}
			if result == 0 {
				break
			}
			if entry.event_type == fw.g17_firmware_event_completion {
				if !fw.validate_g17_firmware_completion_event(&entry) {
					C.printf(c'agx: invalid G17 completion event on role %d\n', role)
					mgr.state = .error
					return false
				}
				completion_pending = completion_pending
					|| fw.g17_firmware_completion_has_firing_stamps(&entry)
				continue
			}
			// Types 2, 3, 5, 11, and 29 branch straight back to Apple's drain
			// loop. Other accepted records need their individual response ABIs
			// before Vinix may continue after them.
			if !fw.g17_firmware_event_is_host_noop(entry.event_type) {
				C.printf(c'agx: unsupported G17 firmware event %u on role %d\n',
					entry.event_type, role)
				mgr.state = .error
				return false
			}
		}
	}
	if completion_pending {
		event.scan_all_completions()
	}
	return true
}

fn (mut mgr GpuManager) wait_g17_ready() bool {
	for _ in 0 .. 10_000_000 {
		mut received := false
		for role := u32(0); role < mgr.firmware_roles; role++ {
			msg := mgr.recv_role_message(role) or { continue }
			received = true
			if mailbox.msg_endpoint(&msg) != u8(ep_firmware) {
				continue
			}
			kind := fw.g17_akf_message_type(msg.data0)
			if kind == fw.g17_akf_callback_type {
				if !mgr.handle_g17_akf_callback() {
					return false
				}
				continue
			}
			if kind != fw.g17_akf_ready_type {
				continue
			}
			for ack_role := u32(0); ack_role < mgr.firmware_roles; ack_role++ {
				if !mgr.send_role_message(ack_role, u8(ep_firmware), fw.g17_ready_ack_message) {
					return false
				}
			}
			return true
		}
		if !received {
			cpu.wfe()
		}
	}
	return false
}

// Serialize one producer per command type and queue priority, matching Apple's
// IOCommandGate around AGXAcceleratorRing::nextEntry.
fn (mut graph G17FirmwareGraph) enqueue_data_master(priority u32,
	command fw.G17DataMasterCommand) bool {
	if priority >= fw.g17_data_master_priorities
		|| command.command_type >= fw.g17_data_master_command_types {
		return false
	}
	graph.data_master_locks[priority][command.command_type].acquire()
	defer {
		graph.data_master_locks[priority][command.command_type].release()
	}
	state := &graph.data_master_state[priority][command.command_type]
	entries := &graph.data_master_entries[priority][command.command_type]
	return fw.enqueue_g17_data_master_entry(state.cpu_address(), fw.g17_accelerator_ring_state_size,
		entries.cpu_address(), fw.g17_data_master_entries_bytes, command)
}

// Stage a byte-accurate outer-ring entry once a G17 channel command has been
// built. This is intentionally unavailable until the retained bootstrap graph
// exists, and it does not imply that the still-gated firmware can be booted.
pub fn (mut mgr GpuManager) enqueue_g17_data_master(priority u32,
	command fw.G17DataMasterCommand) bool {
	if mgr.g17_graph == unsafe { nil } {
		return false
	}
	return mgr.g17_graph.enqueue_data_master(priority, command)
}

// Publish a prepared outer work entry and deliver its recovered 0x83
// doorbell through the primary transport. Once the ring entry is visible the
// submission is accepted; a transient mailbox failure may delay it but must
// not make callers retry and duplicate the command.
pub fn (mut mgr GpuManager) submit_g17_data_master(priority u32,
	command fw.G17DataMasterCommand) bool {
	channel := fw.g17_data_master_doorbell_channel(priority, command.command_type) or {
		return false
	}
	if !mgr.enqueue_g17_data_master(priority, command) {
		return false
	}
	_ = mgr.send_doorbell(channel)
	return true
}
