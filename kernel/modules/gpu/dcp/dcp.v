@[has_globals]
module dcp

// Apple DCP (Display Coprocessor) driver
// Manages the M1's display pipeline via RTKit/IOMFB protocol.
// Translated from drm_apple/dcp.c (~1.8K lines C)
//
// The DCP is a coprocessor that controls the display pipeline on Apple
// Silicon. Communication happens via RTKit mailbox messages, with the
// IOMFB protocol layered on top for display-specific operations.

import apple.rtkit
import apple.dart
import drm.mode
import drm.gem
import devicetree
import klock
import memory
import aarch64.cpu

// Default shared memory region size for DCP communication
const dcp_shmem_size = u64(0x100000) // 1 MiB

// IOVA base for DCP shared memory region
const dcp_shmem_iova = u64(0x1_0000_0000)

// Vblank counter managed globally for the DCP CRTC
__global (
	dcp_vblank_count = u64(0)
)

pub struct AppleDCP {
pub mut:
	rtk          rtkit.RTKit
	disp_dart    dart.DART
	crtc         &mode.DrmCrtc      = unsafe { nil }
	connector    &mode.DrmConnector = unsafe { nil }
	encoder      &mode.DrmEncoder   = unsafe { nil }
	primary      &mode.DrmPlane     = unsafe { nil }
	iomfb        IomfbState
	shmem_base   u64 // shared memory IOVA
	shmem_size   u64
	modes        []mode.DrmDisplayMode
	current_mode &mode.DrmDisplayMode = unsafe { nil }
	powered      bool
	started      bool
	width        u32
	height       u32
	lock         klock.Lock
}

// Create a new Apple DCP instance from mailbox and DART MMIO base addresses.
pub fn new_dcp(mbox_base u64, dart_base u64) ?&AppleDCP {
	mut dcp := &AppleDCP{
		rtk:        rtkit.new_rtkit(mbox_base, 'dcp')
		disp_dart:  dart.new_dart(dart_base, 0)
		shmem_base: dcp_shmem_iova
		shmem_size: dcp_shmem_size
	}

	return dcp
}

// Boot DCP via RTKit, initialise IOMFB endpoint, enumerate display modes,
// and create all DRM mode-setting objects (CRTC, connector, encoder, plane).
pub fn (mut dcp AppleDCP) initialise() bool {
	dcp.lock.acquire()
	defer {
		dcp.lock.release()
	}

	println('dcp: Initializing Apple Display Controller')

	// Step 1: Initialise DART IOMMU for display DMA
	dcp.disp_dart.init()

	// Step 2: Allocate shared memory and map it through DART
	shmem_pages := dcp.shmem_size / u64(0x1000)
	shmem_phys := u64(memory.pmm_alloc(shmem_pages))
	if shmem_phys == 0 {
		C.printf(c'dcp: Failed to allocate shared memory\n')
		return false
	}

	if !dcp.disp_dart.map(dcp.shmem_base, shmem_phys, dcp.shmem_size) {
		C.printf(c'dcp: Failed to map shared memory in DART\n')
		return false
	}

	// Step 3: Boot RTKit firmware on DCP coprocessor
	if !dcp.rtk.boot() {
		C.printf(c'dcp: RTKit boot failed\n')
		return false
	}

	// Step 4: Initialise IOMFB protocol state and start endpoint
	dcp.iomfb = iomfb_init(mut dcp.rtk)

	if !iomfb_start_endpoint(mut dcp.rtk) {
		C.printf(c'dcp: Failed to start IOMFB endpoint\n')
		return false
	}

	// Step 5: Create DRM mode-setting objects
	dcp.crtc = mode.new_crtc()
	dcp.connector = mode.new_connector(0) // Internal panel
	dcp.encoder = mode.new_encoder(0)
	dcp.primary = mode.new_plane(mode.plane_type_primary)

	// Link the mode-setting pipeline together
	dcp.encoder.crtc = dcp.crtc
	dcp.connector.encoder = dcp.encoder
	dcp.crtc.primary = dcp.primary

	// Internal panel is always connected
	dcp.connector.status = mode.connector_status_connected

	// Step 6: Enumerate display modes from DCP firmware
	dcp.modes = get_modes_internal(mut dcp)
	dcp.connector.modes = dcp.modes

	dcp.started = true
	println('dcp: Display controller initialized')

	return true
}

// Power on the display via IOMFB set_power command.
pub fn (mut dcp AppleDCP) start() bool {
	dcp.lock.acquire()
	defer {
		dcp.lock.release()
	}

	if dcp.powered {
		return true
	}

	if !iomfb_set_power(mut dcp.rtk, 1) {
		C.printf(c'dcp: Failed to power on display\n')
		return false
	}

	dcp.powered = true
	println('dcp: Display powered on')
	return true
}

// Power off the display.
pub fn (mut dcp AppleDCP) stop() {
	dcp.lock.acquire()
	defer {
		dcp.lock.release()
	}

	if !dcp.powered {
		return
	}

	iomfb_set_power(mut dcp.rtk, 0)
	dcp.powered = false
	println('dcp: Display powered off')
}

// Set the display mode. Sends the mode dimensions to DCP firmware via IOMFB
// and updates the CRTC state.
pub fn (mut dcp AppleDCP) set_mode(m &mode.DrmDisplayMode) bool {
	dcp.lock.acquire()
	defer {
		dcp.lock.release()
	}

	if !dcp.started {
		return false
	}

	// Send mode change to DCP firmware
	if !iomfb_set_mode(mut dcp.rtk, &dcp.iomfb, m.hdisplay, m.vdisplay) {
		C.printf(c'dcp: IOMFB set_mode failed for %ux%u\n', m.hdisplay, m.vdisplay)
		return false
	}

	dcp.width = m.hdisplay
	dcp.height = m.vdisplay
	dcp.current_mode = unsafe { m }
	dcp.crtc.mode = unsafe { *m }
	dcp.crtc.enabled = true

	println('dcp: Set mode ${m.name}')
	return true
}

// Present a framebuffer to the display. Builds an IOMFB swap descriptor
// from the framebuffer and submits it through the DCP swap pipeline.
pub fn (mut dcp AppleDCP) flush(fb &mode.DrmFramebuffer) bool {
	if !dcp.started || !dcp.powered {
		return false
	}

	if fb.gem_obj == unsafe { nil } {
		return false
	}

	// Start a new swap transaction
	swap_id := iomfb_swap_start(mut dcp.rtk, &dcp.iomfb)
	if swap_id == 0 {
		C.printf(c'dcp: swap_start failed\n')
		return false
	}

	// Build the swap descriptor from the framebuffer
	desc := IomfbSwapDesc{
		swap_id:    swap_id
		src_addr:   fb.gem_obj.phys_addr
		src_stride: fb.pitches[0]
		src_width:  fb.width
		src_height: fb.height
		src_format: fb.format
		dst_x:      0
		dst_y:      0
		dst_w:      fb.width
		dst_h:      fb.height
	}

	// Submit the swap
	if !iomfb_swap_submit(mut dcp.rtk, &dcp.iomfb, &desc) {
		C.printf(c'dcp: swap_submit failed\n')
		return false
	}

	// Wait for completion
	if !iomfb_swap_complete(mut dcp.rtk, &dcp.iomfb, swap_id) {
		C.printf(c'dcp: swap_complete timeout\n')
		return false
	}

	return true
}

// Return available display modes. Uses cached modes if already enumerated,
// otherwise queries IOMFB.
pub fn (mut dcp AppleDCP) get_modes() []mode.DrmDisplayMode {
	if dcp.modes.len > 0 {
		return dcp.modes
	}

	return get_modes_internal(mut dcp)
}

// Internal mode enumeration: queries IOMFB and falls back to a default mode
// for the built-in panel if the firmware does not respond.
fn get_modes_internal(mut dcp AppleDCP) []mode.DrmDisplayMode {
	mut modes := []mode.DrmDisplayMode{}

	// Query IOMFB for timing modes from the DCP firmware
	timing_modes := iomfb_get_timing_modes(mut dcp.rtk, &dcp.iomfb)

	if timing_modes.len > 0 {
		for tm in timing_modes {
			// Convert fixed-point 16.16 refresh rate to integer Hz
			refresh_hz := tm.refresh_rate_fp >> 16
			clock := tm.width * tm.height * refresh_hz / 1000

			modes << mode.DrmDisplayMode{
				hdisplay:    tm.width
				vdisplay:    tm.height
				hsync_start: tm.width
				hsync_end:   tm.width
				htotal:      tm.width
				vsync_start: tm.height
				vsync_end:   tm.height
				vtotal:      tm.height
				clock:       clock
				flags:       tm.flags
				name:        '${tm.width}x${tm.height}@${refresh_hz}'
			}
		}
	} else {
		// Fallback: M1 Air built-in display (2560x1600@60Hz, 13.3" Retina)
		modes << mode.DrmDisplayMode{
			hdisplay:    2560
			vdisplay:    1600
			hsync_start: 2560
			hsync_end:   2560
			htotal:      2560
			vsync_start: 1600
			vsync_end:   1600
			vtotal:      1600
			clock:       245760 // ~246 MHz pixel clock
			name:        '2560x1600@60'
		}
	}

	return modes
}

// Return connector status. For the built-in panel this always reports
// connected; external displays would check hotplug state via IOMFB.
pub fn (dcp &AppleDCP) get_connector_status() u32 {
	return mode.connector_status_connected
}

// Get the DRM connector for this display.
pub fn (dcp &AppleDCP) get_connector() &mode.DrmConnector {
	return dcp.connector
}

// Get the DRM CRTC.
pub fn (dcp &AppleDCP) get_crtc() &mode.DrmCrtc {
	return dcp.crtc
}

// Handle vblank interrupt from DCP. Increments the CRTC vblank counter
// which user-space uses for frame pacing and synchronization.
pub fn (mut dcp AppleDCP) vblank_handler() {
	if dcp.crtc != unsafe { nil } {
		dcp.crtc.vblank_count++
		dcp_vblank_count++
	}
}

// Top-level DCP initialization: discover from device tree, create, and boot.
pub fn initialise() {
	println('dcp: Probing Apple Display Controller')

	// Find DCP node in device tree
	dcp_node := devicetree.find_compatible('apple,dcp') or {
		println('dcp: DCP not found in device tree')
		return
	}

	dcp_regs := devicetree.get_reg(dcp_node) or {
		println('dcp: Failed to get DCP registers from device tree')
		return
	}

	if dcp_regs.len < 2 {
		println('dcp: Insufficient register ranges')
		return
	}

	// Find DCP mailbox and DART
	mbox_node := devicetree.find_compatible('apple,dcp-mailbox') or {
		// Fall back to generic ASC mailbox for DCP
		devicetree.find_compatible('apple,asc4') or {
			println('dcp: DCP mailbox not found in device tree')
			return
		}
	}
	mbox_regs := devicetree.get_reg(mbox_node) or {
		println('dcp: Failed to get DCP mailbox registers')
		return
	}
	mbox_base := mbox_regs[0]

	dart_node := devicetree.find_compatible('apple,t8103-dcp-dart') or {
		// Try generic DART compatible
		devicetree.find_compatible('apple,t8103-dart-dcp') or {
			println('dcp: DCP DART not found in device tree')
			return
		}
	}
	dart_regs := devicetree.get_reg(dart_node) or {
		println('dcp: Failed to get DCP DART registers')
		return
	}
	dart_base := dart_regs[0]

	mut inst := new_dcp(mbox_base, dart_base) or {
		println('dcp: Failed to create DCP instance')
		return
	}

	if !inst.initialise() {
		println('dcp: DCP initialization failed')
		return
	}

	println('dcp: Apple Display Controller initialized successfully')
}
