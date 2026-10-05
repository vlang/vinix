// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_activity_resource_graphs_release_frame_text_and_arrays() {
	mut resources := ActivityResources{
		cpu_count: 8
		memory_total: 256_000_000
		memory_free: 128_000_000
		memory_cached: 12_000_000
		memory_slab: 8_000_000
		pressure: 1
		io_available: true
		previous_io: [u64(200_000), 123_000, 125_000, 63_000]!
	}
	for i in 0 .. activity_resource_samples {
		resources.cpu_history.append(f64(i % 45), u64(1000 * i), i != 3)
		resources.memory_history.append(50, u64(1000 * i), true)
		resources.disk_read_history.append(f64(i * 250), u64(1000 * i), true)
		resources.disk_write_history.append(f64(i * 750), u64(1000 * i), true)
		resources.net_recv_history.append(f64(i * 400), u64(1000 * i), true)
		resources.net_send_history.append(f64(i * 300), u64(1000 * i), true)
		for core in 0 .. resources.cpu_count { resources.core_history[core].append(f64((i + core) % 60), u64(1000 * i), true) }
	}
	for tab in [ActivityResourceTab.cpu, .memory, .disk, .network]! {
		resources.tab = tab
		begin_frame_elements()
		free_tree(resources.build(600, 360))
	}
	C.vinix_heap_begin()
	for _ in 0 .. 6 {
		for tab in [ActivityResourceTab.cpu, .memory, .disk, .network]! {
			resources.tab = tab
			begin_frame_elements()
			free_tree(resources.build(600, 360))
		}
	}
	live := C.vinix_heap_end()
	assert live == 0, 'resource panes retained ${live} bytes'
}

fn test_activity_energy_graphs_release_frame_text_and_arrays() {
	mut energy := ActivityEnergy{
		stats: ActivityEnergyStats{voltage_mv: 12080, current_ma: -875, power_mw: -10920, has_voltage: true, has_current: true, has_power: true}
		battery_percent: 75
	}
	for i in 0 .. activity_resource_samples {
		energy.power_history.append(f64(i - 30) / 3, u64(i * 1000), i != 5)
		energy.battery_history.observe(u64(i * 1000), 75)
	}
	begin_frame_elements()
	free_tree(energy.build(600, 360))
	C.vinix_heap_begin()
	for _ in 0 .. 12 {
		begin_frame_elements()
		free_tree(energy.build(600, 360))
	}
	live := C.vinix_heap_end()
	assert live == 0, 'energy pane retained ${live} bytes'
}

fn test_activity_many_core_tall_panes_keep_pool_buffer_owned() {
	mut resources := ActivityResources{}
	for core_count in [16, 64]! {
		resources.cpu_count = core_count
		for core in 0 .. core_count {
			resources.core_history[core].append(f64(core), 1000, true)
			resources.core_history[core].append(f64(core + 1), 2000, true)
		}
		// A 900x640 Activity Monitor has a 572px panel and displays up to
		// twenty core graphs, exceeding the former 32-element pool buffer.
		begin_frame_elements()
		free_tree(resources.build(900, 572))
		C.vinix_heap_begin()
		for _ in 0 .. 12 {
			begin_frame_elements()
			free_tree(resources.build(900, 572))
		}
		live := C.vinix_heap_end()
		assert live == 0, '${core_count} cores retained ${live} bytes'
	}
}

fn activity_startup_heap_model() ActivityStartup {
	mut model := ActivityStartup{ loaded: true, language: desktop_language, home: '/tmp'.clone() }
	for index in 0 .. available_apps.len {
		number := index.str()
		model.actions[index] = 'activity.startup.toggle.${number}'
		unsafe { number.free() }
		model.timing_known[index] = true
		model.timing_ms[index] = u64(index)
	}
	model.refresh_timing_text()
	return model
}

fn test_activity_startup_full_catalog_model_and_last_rows_release_owned_memory() {
	mut warm := activity_startup_heap_model()
	for width in [240, 900]! {
		for scroll in [0, available_apps.len - 1]! {
			warm.scroll = scroll
			begin_frame_elements()
			free_tree(warm.build(width, 572))
		}
	}
	warm.free()
	C.vinix_heap_begin()
	for _ in 0 .. 50 {
		mut model := activity_startup_heap_model()
		for width in [240, 900]! {
			model.scroll = available_apps.len - 1
			model.refresh_timing_text()
			begin_frame_elements()
			free_tree(model.build(width, 572))
		}
		model.free()
		model.free()
	}
	assert C.vinix_heap_end() == 0
}
