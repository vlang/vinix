@[has_globals]
module mode

// DRM KMS (Kernel Mode Setting) types.
// Minimal implementation for Asahi DCP display driver.
// Skips legacy mode setting, DRM leases, and writeback connectors.

import drm.gem
import klock
import katomic

// Connector status
pub const connector_status_connected = u32(1)
pub const connector_status_disconnected = u32(2)
pub const connector_status_unknown = u32(3)

// Plane types
pub const plane_type_overlay = u32(0)
pub const plane_type_primary = u32(1)
pub const plane_type_cursor = u32(2)

// DRM fourcc pixel format codes
pub const drm_format_xrgb8888 = u32(0x34325258) // XR24
pub const drm_format_argb8888 = u32(0x34325241) // AR24
pub const drm_format_xbgr8888 = u32(0x34324258) // XB24

pub struct DrmDisplayMode {
pub mut:
	hdisplay    u32
	vdisplay    u32
	hsync_start u32
	hsync_end   u32
	htotal      u32
	vsync_start u32
	vsync_end   u32
	vtotal      u32
	clock       u32 // pixel clock in kHz
	flags       u32
	name        string
}

pub struct DrmConnector {
pub mut:
	id             u32
	status         u32 // ConnectorStatus constant
	modes          []DrmDisplayMode
	current_mode   &DrmDisplayMode = unsafe { nil }
	encoder        &DrmEncoder     = unsafe { nil }
	connector_type u32
	lock           klock.Lock
}

pub struct DrmEncoder {
pub mut:
	id           u32
	encoder_type u32
	crtc         &DrmCrtc = unsafe { nil }
}

pub struct DrmCrtc {
pub mut:
	id           u32
	primary      &DrmPlane = unsafe { nil }
	cursor       &DrmPlane = unsafe { nil }
	mode         DrmDisplayMode
	enabled      bool
	lock         klock.Lock
	vblank_count u64
}

pub struct DrmPlane {
pub mut:
	id         u32
	plane_type u32 // PlaneType constant
	fb         &DrmFramebuffer = unsafe { nil }
	crtc       &DrmCrtc        = unsafe { nil }
	src_x      u32
	src_y      u32
	src_w      u32
	src_h      u32
	crtc_x     i32
	crtc_y     i32
	crtc_w     u32
	crtc_h     u32
}

pub struct DrmFramebuffer {
pub mut:
	id       u32
	width    u32
	height   u32
	pitches  [4]u32
	offsets  [4]u32
	format   u32 // fourcc format code
	modifier u64
	gem_obj  &gem.GemObject = unsafe { nil }
	refcount u64
}

__global (
	mode_next_connector_id = u32(1)
	mode_next_crtc_id      = u32(1)
	mode_next_encoder_id   = u32(1)
	mode_next_plane_id     = u32(1)
	mode_next_fb_id        = u32(1)
	mode_id_lock           klock.Lock
)

// Allocate a new connector with the given type.
pub fn new_connector(connector_type u32) &DrmConnector {
	mode_id_lock.acquire()
	id := mode_next_connector_id
	mode_next_connector_id++
	mode_id_lock.release()

	return &DrmConnector{
		id:             id
		status:         connector_status_unknown
		connector_type: connector_type
	}
}

// Allocate a new CRTC.
pub fn new_crtc() &DrmCrtc {
	mode_id_lock.acquire()
	id := mode_next_crtc_id
	mode_next_crtc_id++
	mode_id_lock.release()

	return &DrmCrtc{
		id: id
	}
}

// Allocate a new encoder with the given type.
pub fn new_encoder(encoder_type u32) &DrmEncoder {
	mode_id_lock.acquire()
	id := mode_next_encoder_id
	mode_next_encoder_id++
	mode_id_lock.release()

	return &DrmEncoder{
		id:           id
		encoder_type: encoder_type
	}
}

// Allocate a new plane with the given type (overlay, primary, cursor).
pub fn new_plane(plane_type u32) &DrmPlane {
	mode_id_lock.acquire()
	id := mode_next_plane_id
	mode_next_plane_id++
	mode_id_lock.release()

	return &DrmPlane{
		id:         id
		plane_type: plane_type
	}
}

// Create a framebuffer backed by a GEM object.
pub fn create_framebuffer(width u32, height u32, format u32, gem_obj &gem.GemObject, pitch u32) ?&DrmFramebuffer {
	if gem_obj == unsafe { nil } {
		return none
	}

	// Verify the GEM object is large enough for the framebuffer
	required := u64(pitch) * u64(height)
	if gem_obj.size < required {
		return none
	}

	mode_id_lock.acquire()
	id := mode_next_fb_id
	mode_next_fb_id++
	mode_id_lock.release()

	// Take a reference on the backing GEM object
	gem.ref_obj(gem_obj)

	mut pitches := [4]u32{}
	pitches[0] = pitch

	return &DrmFramebuffer{
		id:       id
		width:    width
		height:   height
		pitches:  pitches
		format:   format
		gem_obj:  unsafe { gem_obj }
		refcount: 1
	}
}
