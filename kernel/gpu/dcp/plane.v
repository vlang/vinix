@[has_globals]
module dcp

// DRM plane and CRTC atomic operations for DCP display
// Handles format validation, scaling checks, and atomic commit helpers
// for the Apple DCP display pipeline.

import drm.mode
import drm.gem
import klock

// Supported pixel formats (DRM fourcc codes)
pub const dcp_format_xrgb8888 = u32(0x34325258) // XR24
pub const dcp_format_argb8888 = u32(0x34325241) // AR24
pub const dcp_format_xbgr8888 = u32(0x34324258) // XB24

// Scaling limits in 16.16 fixed-point representation.
// DCP supports 0.5x to 4x scaling on both axes.
pub const dcp_min_scale_fp = u32(0x8000)  // 0.5 in 16.16 fixed point
pub const dcp_max_scale_fp = u32(0x40000) // 4.0 in 16.16 fixed point

// Array of all supported formats for quick lookup
const supported_formats = [
	dcp_format_xrgb8888,
	dcp_format_argb8888,
	dcp_format_xbgr8888,
]

// Plane state for atomic commit. Describes the source region within the
// framebuffer and the destination region on the CRTC. Source coordinates
// use 16.16 fixed-point to support sub-pixel addressing.
pub struct DcpPlaneState {
pub mut:
	fb       &mode.DrmFramebuffer = unsafe { nil }
	src_x    u32 // 16.16 fixed point
	src_y    u32
	src_w    u32
	src_h    u32
	crtc_x   i32
	crtc_y   i32
	crtc_w   u32
	crtc_h   u32
	format   u32
	rotation u32
	alpha    u16
	visible  bool
}

// CRTC state for atomic commit. Tracks whether the mode or active state
// has changed so that the commit path knows which hardware updates to
// perform.
pub struct DcpCrtcState {
pub mut:
	mode           mode.DrmDisplayMode
	enabled        bool
	planes_changed bool
	mode_changed   bool
	active         bool
}

// Validate a plane state against DCP hardware constraints.
// Checks format support, non-zero dimensions, and scaling bounds.
pub fn validate_plane_state(state &DcpPlaneState) bool {
	// A disabled plane (no framebuffer) is always valid
	if state.fb == unsafe { nil } {
		return true
	}

	// Check format support
	if !is_format_supported(state.format) {
		C.printf(c'dcp: Unsupported pixel format 0x%x\n', state.format)
		return false
	}

	// Verify source dimensions are non-zero (in 16.16 fixed-point)
	if state.src_w == 0 || state.src_h == 0 {
		return false
	}

	// Verify destination dimensions are non-zero
	if state.crtc_w == 0 || state.crtc_h == 0 {
		return false
	}

	// Check scaling bounds (convert src from 16.16 fixed-point to integer
	// for the scaling ratio calculation)
	src_w_int := state.src_w >> 16
	src_h_int := state.src_h >> 16

	if src_w_int == 0 || src_h_int == 0 {
		return false
	}

	// Horizontal scale in 16.16 fixed-point
	h_scale := (u64(src_w_int) << 16) / u64(state.crtc_w)
	if h_scale < u64(dcp_min_scale_fp) || h_scale > u64(dcp_max_scale_fp) {
		C.printf(c'dcp: Horizontal scale out of range\n')
		return false
	}

	// Vertical scale in 16.16 fixed-point
	v_scale := (u64(src_h_int) << 16) / u64(state.crtc_h)
	if v_scale < u64(dcp_min_scale_fp) || v_scale > u64(dcp_max_scale_fp) {
		C.printf(c'dcp: Vertical scale out of range\n')
		return false
	}

	// Validate alpha (0 = transparent, 0xFFFF = opaque)
	// Non-alpha formats must have full opacity
	if !format_has_alpha(state.format) && state.alpha != 0xFFFF {
		C.printf(c'dcp: Non-alpha format requires alpha=0xFFFF\n')
		return false
	}

	return true
}

// Check if a pixel format is supported by the DCP hardware.
pub fn is_format_supported(format u32) bool {
	for f in supported_formats {
		if f == format {
			return true
		}
	}
	return false
}

// Return true if the pixel format has an alpha channel.
pub fn format_has_alpha(format u32) bool {
	return format == dcp_format_argb8888
}

// Return the bytes per pixel for a given format.
// Returns 0 for unsupported formats.
pub fn format_bpp(format u32) u32 {
	match format {
		dcp_format_xrgb8888, dcp_format_argb8888, dcp_format_xbgr8888 {
			return 4
		}
		else {
			return 0
		}
	}
}

// Calculate the pitch (stride in bytes) for a framebuffer of the given
// width and format. The pitch is aligned to 64 bytes as required by
// the DCP hardware.
fn calc_pitch(width u32, format u32) u32 {
	bpp := format_bpp(format)
	if bpp == 0 {
		return 0
	}
	// Align pitch to 64 bytes (DCP DMA requirement)
	return (width * bpp + 63) & ~u32(63)
}

// Apply a plane state update to the DCP. Builds a swap descriptor from
// the plane state and submits it through IOMFB.
pub fn plane_update(mut dcp AppleDCP, state &DcpPlaneState) bool {
	if state.fb == unsafe { nil } {
		return true // no-op for disabled plane
	}

	if !validate_plane_state(state) {
		return false
	}

	if !dcp.started || !dcp.powered {
		C.printf(c'dcp: Cannot update plane, display not active\n')
		return false
	}

	// Map framebuffer GEM object through DART if needed
	if state.fb.gem_obj == unsafe { nil } {
		return false
	}

	fb_phys := state.fb.gem_obj.phys_addr
	fb_size := u64(state.fb.pitches[0]) * u64(state.fb.height)
	dcp.disp_dart.map(fb_phys, fb_phys, fb_size)

	// Start a swap transaction
	swap_id := iomfb_swap_start(mut dcp.rtk, &dcp.iomfb)
	if swap_id == 0 {
		return false
	}

	desc := IomfbSwapDesc{
		swap_id:    swap_id
		src_addr:   fb_phys
		src_stride: state.fb.pitches[0]
		src_width:  state.src_w >> 16 // convert from 16.16 fixed-point
		src_height: state.src_h >> 16
		src_format: state.format
		dst_x:      state.crtc_x
		dst_y:      state.crtc_y
		dst_w:      state.crtc_w
		dst_h:      state.crtc_h
	}

	if !iomfb_swap_submit(mut dcp.rtk, &dcp.iomfb, &desc) {
		return false
	}

	return iomfb_swap_complete(mut dcp.rtk, &dcp.iomfb, swap_id)
}

// Enable a CRTC with the given state. Powers on the display and sets
// the requested mode.
pub fn crtc_enable(mut dcp AppleDCP, state &DcpCrtcState) bool {
	if !dcp.started {
		C.printf(c'dcp: Cannot enable CRTC, DCP not started\n')
		return false
	}

	// Power on if needed
	if !dcp.powered {
		if !dcp.start() {
			return false
		}
	}

	// Set mode if it changed
	if state.mode_changed {
		if !dcp.set_mode(&state.mode) {
			return false
		}
	}

	if dcp.crtc != unsafe { nil } {
		dcp.crtc.enabled = true
	}

	return true
}

// Disable the CRTC and power off the display.
pub fn crtc_disable(mut dcp AppleDCP) bool {
	if !dcp.started {
		return true
	}

	dcp.stop()

	if dcp.crtc != unsafe { nil } {
		dcp.crtc.enabled = false
	}

	return true
}

// Flush all pending plane changes to the DCP hardware. This is the final
// step in an atomic commit -- after all plane states have been validated
// and applied, this function ensures the hardware processes the updates.
pub fn atomic_flush(mut dcp AppleDCP) bool {
	if !dcp.started || !dcp.powered {
		return false
	}

	// The primary plane holds the current framebuffer to scan out
	if dcp.primary == unsafe { nil } {
		return false
	}

	fb := dcp.primary.fb
	if fb == unsafe { nil } {
		// No framebuffer attached; nothing to flush
		return true
	}

	return dcp.flush(fb)
}
