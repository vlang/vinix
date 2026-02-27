@[has_globals]
module driver

// Top-level GPU driver probe and registration
// Discovers the Apple AGX GPU from the device tree, initializes all
// subsystems (DART, UAT, channels, firmware, RTKit), creates the
// GpuManager, and registers a DRM driver with GEM, render, and compute
// capabilities.

import gpu.agx.gpu
import gpu.agx.hw
import gpu.agx.regs
import gpu.agx.mmu
import gpu.agx.event
import gpu.agx.file as agx_file
import gpu.dcp
import drm
import apple.rtkit
import apple.dart
import devicetree
import klock
import memory

pub struct AgxDriver {
pub mut:
	gpu         &gpu.GpuManager = unsafe { nil }
	dcp         &dcp.AppleDCP   = unsafe { nil }
	drm_dev     &drm.DrmDevice  = unsafe { nil }
	hw_config   &hw.HwConfig    = unsafe { nil }
	initialized bool
}

__global (
	agx_driver_inst AgxDriver
)

// Probe GPU from device tree and bring up all subsystems.
pub fn initialise() {
	println('agx: Probing Apple GPU')

	// Step 1: Find GPU node (compatible "apple,agx-t8103") from device tree
	gpu_node := devicetree.find_compatible('apple,agx-t8103') or {
		println('agx: GPU not found in device tree')
		return
	}

	// Step 2: Get registers from device tree
	gpu_regs := devicetree.get_reg(gpu_node) or {
		println('agx: Failed to get GPU registers from device tree')
		return
	}

	if gpu_regs.len < 2 {
		println('agx: Insufficient register ranges in device tree')
		return
	}

	gpu_base := gpu_regs[0]

	// Step 3: Create HwConfig via hw.t8103_config()
	cfg := hw.t8103_config()
	agx_driver_inst.hw_config = &cfg

	println('agx: GPU chip 0x8103, ${cfg.gpu_core_count} cores, gen G13')

	// Find ASC mailbox and DART from device tree
	asc_node := devicetree.find_compatible('apple,asc-mailbox') or {
		println('agx: ASC mailbox not found in device tree')
		return
	}
	asc_regs := devicetree.get_reg(asc_node) or {
		println('agx: Failed to get ASC registers')
		return
	}
	asc_base := asc_regs[0]

	dart_node := devicetree.find_compatible('apple,t8103-dart') or {
		println('agx: DART not found in device tree')
		return
	}
	dart_regs := devicetree.get_reg(dart_node) or {
		println('agx: Failed to get DART registers')
		return
	}
	dart_base := dart_regs[0]

	// Step 4: Init DART for GPU
	mut gpu_dart := dart.new_dart(dart_base, 0)
	gpu_dart.init()
	println('agx: DART IOMMU initialized')

	// Step 5: Init UAT manager
	ttbat_base := gpu_base + 0x100000
	_ := mmu.new_manager(ttbat_base) or {
		println('agx: Failed to initialize UAT manager')
		return
	}

	// Step 6: Init GPU resources (event manager)
	stamp_pages := u64(mmu.uat_num_contexts)
	stamp_phys := u64(memory.pmm_alloc(stamp_pages))
	if stamp_phys == 0 {
		println('agx: Failed to allocate stamp memory')
		return
	}
	stamp_va := u64(0x10_0000)
	stamp_size := stamp_pages * page_size
	if !gpu_dart.map(stamp_va, stamp_phys, stamp_size) {
		println('agx: Failed to map stamp buffer in DART')
		return
	}
	if uat_mgr != unsafe { nil } {
		if !uat_mgr.map_kernel(stamp_va, stamp_phys, stamp_size, 0x43) {
			println('agx: Failed to map stamp buffer in UAT')
			return
		}
	}
	gpu_event_mgr = event.new_event_manager(stamp_va, stamp_phys)

	// Step 7: Create GPU resources, RTKit, and GpuManager
	gpu_res := regs.new_resources(gpu_base)
	gpu_rtk := rtkit.new_rtkit(asc_base, 'agx')

	mut mgr := gpu.new_gpu_manager(&gpu_res, &cfg, &gpu_rtk, &gpu_dart) or {
		println('agx: Failed to create GPU manager')
		return
	}

	// Step 8: Init GPU (RTKit boot, firmware init)
	if !mgr.init() {
		println('agx: GPU initialization failed')
		return
	}

	agx_driver_inst.gpu = &mgr
	gpu.set_global_manager(agx_driver_inst.gpu)

	// Step 10: Register DRM driver (name "asahi", features GEM|RENDER|COMPUTE)
	agx_drm_driver := &drm.DrmDriver{
		name:       'asahi'
		desc:       'Apple AGX GPU'
		major:      1
		minor:      0
		patchlevel: 0
		features:   drm.driver_gem | drm.driver_render | drm.driver_compute
		ioctls:     agx_file.drm_ioctls()
		file_close: agx_file.release_handle
	}

	agx_driver_inst.drm_dev = drm.register_driver(agx_drm_driver) or {
		println('agx: Failed to register DRM driver')
		return
	}

	agx_driver_inst.initialized = true

	// Step 11: Log success
	println('agx: Apple GPU driver initialized successfully')
	println('agx: DRM device registered as card${agx_driver_inst.drm_dev.dev_id}')
}

// Tear down the GPU driver and release all resources.
pub fn shutdown() {
	if !agx_driver_inst.initialized {
		return
	}

	println('agx: Shutting down Apple GPU driver')

	// Unregister DRM device
	if agx_driver_inst.drm_dev != unsafe { nil } {
		drm.unregister_device(agx_driver_inst.drm_dev)
		agx_driver_inst.drm_dev = unsafe { nil }
	}

	// Shutdown GPU manager (stops firmware, ASC)
	if agx_driver_inst.gpu != unsafe { nil } {
		mut g := unsafe { agx_driver_inst.gpu }
		g.shutdown()
		gpu.set_global_manager(unsafe { nil })
		agx_driver_inst.gpu = unsafe { nil }
	}

	agx_driver_inst.initialized = false
	println('agx: GPU driver shutdown complete')
}
