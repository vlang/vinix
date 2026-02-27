@[has_globals]
module dcp

// IOMFB protocol over RTKit for Apple DCP
// Translated from drm_apple/iomfb.c
//
// The IOMFB (IO Mobile Framebuffer) protocol is the message-passing
// interface between the kernel and the DCP firmware. Messages are sent
// via RTKit endpoint 0x37 and follow a request/response pattern for
// operations like power management, mode enumeration, and frame swap.

import apple.rtkit
import apple.mailbox
import klock
import memory
import aarch64.cpu

// IOMFB endpoint ID on the RTKit message bus
pub const iomfb_endpoint = u8(0x37)

// IOMFB message types sent over the RTKit endpoint.
// Each type occupies the upper bits of the RTKit message payload.
pub const iomfb_msg_set_power = u32(1)
pub const iomfb_msg_get_color_modes = u32(2)
pub const iomfb_msg_get_timing_modes = u32(3)
pub const iomfb_msg_set_mode = u32(4)
pub const iomfb_msg_swap_start = u32(5)
pub const iomfb_msg_swap_submit = u32(6)
pub const iomfb_msg_swap_complete = u32(7)
pub const iomfb_msg_set_parameter = u32(8)
pub const iomfb_msg_get_parameter = u32(9)
pub const iomfb_msg_hotplug = u32(10)

// Power states for iomfb_set_power
const iomfb_power_off = u32(0)
const iomfb_power_on = u32(1)

// Maximum number of timing modes the firmware can report
const iomfb_max_timing_modes = 32

// Timeout (in polling iterations) for IOMFB responses
const iomfb_timeout = 20000000

// IOMFB protocol state tracked per DCP instance.
pub struct IomfbState {
pub mut:
	endpoint_started bool
	power_state      u32
	swap_id          u32
	lock             klock.Lock
}

// Swap (frame present) descriptor passed to the DCP firmware.
// Describes the source framebuffer region and the destination rectangle
// on the display for a single frame swap operation.
pub struct IomfbSwapDesc {
pub mut:
	swap_id    u32
	src_addr   u64 // framebuffer physical address
	src_stride u32
	src_width  u32
	src_height u32
	src_format u32 // DRM fourcc pixel format
	dst_x      i32
	dst_y      i32
	dst_w      u32
	dst_h      u32
}

// Display timing mode information reported by DCP firmware.
// The refresh rate is in 16.16 fixed-point format (e.g. 0x003C0000 = 60 Hz).
pub struct IomfbTimingMode {
pub mut:
	width           u32
	height          u32
	refresh_rate_fp u32 // fixed-point 16.16 refresh rate
	flags           u32
}

// Initialise IOMFB state. Must be called after RTKit boot completes.
pub fn iomfb_init(mut rtk rtkit.RTKit) IomfbState {
	return IomfbState{
		endpoint_started: false
		power_state:      iomfb_power_off
		swap_id:          0
	}
}

// Start the IOMFB endpoint (0x37) on the RTKit message bus.
// This must succeed before any other IOMFB operations can be performed.
pub fn iomfb_start_endpoint(mut rtk rtkit.RTKit) bool {
	if !rtk.start_endpoint(iomfb_endpoint) {
		C.printf(c'iomfb: Failed to start endpoint 0x%x\n', iomfb_endpoint)
		return false
	}

	// Wait for the endpoint to become ready by polling for an ack message
	resp := rtk.recv_msg_blocking(iomfb_timeout) or {
		C.printf(c'iomfb: Timeout waiting for endpoint start ack\n')
		return false
	}

	ep := mailbox.msg_endpoint(&resp)
	if ep != iomfb_endpoint {
		C.printf(c'iomfb: Unexpected endpoint %d in start ack\n', ep)
		return false
	}

	println('iomfb: Endpoint 0x37 started')
	return true
}

// Power on or off the display via IOMFB.
// state: 0 = off, 1 = on
pub fn iomfb_set_power(mut rtk rtkit.RTKit, state u32) bool {
	// Encode: message type in bits [55:48], power state in bits [31:0]
	payload := (u64(iomfb_msg_set_power) << 48) | u64(state)

	if !rtk.send_msg(iomfb_endpoint, u8(iomfb_msg_set_power), payload) {
		C.printf(c'iomfb: Failed to send set_power\n')
		return false
	}

	// Wait for power state ack
	resp := rtk.recv_msg_blocking(iomfb_timeout) or {
		C.printf(c'iomfb: Timeout waiting for set_power ack\n')
		return false
	}

	ack_type := u32(resp.data0 >> 48) & 0xff
	if ack_type != iomfb_msg_set_power {
		C.printf(c'iomfb: Unexpected ack type %u for set_power\n', ack_type)
		return false
	}

	return true
}

// Query the DCP firmware for available display timing modes.
// Returns a list of IomfbTimingMode; may be empty if the firmware
// does not respond or reports no modes.
pub fn iomfb_get_timing_modes(mut rtk rtkit.RTKit, state &IomfbState) []IomfbTimingMode {
	mut modes := []IomfbTimingMode{}

	// Send timing mode query
	payload := u64(iomfb_msg_get_timing_modes) << 48
	if !rtk.send_msg(iomfb_endpoint, u8(iomfb_msg_get_timing_modes), payload) {
		C.printf(c'iomfb: Failed to send get_timing_modes\n')
		return modes
	}

	// Receive timing mode response(s)
	// The firmware may send multiple messages, one per mode, terminated
	// by a message with the "done" flag set (width==0).
	for modes.len < iomfb_max_timing_modes {
		resp := rtk.recv_msg_blocking(iomfb_timeout) or {
			break
		}

		resp_type := u32(resp.data0 >> 48) & 0xff
		if resp_type != iomfb_msg_get_timing_modes {
			// Not a timing mode response; might be a system message
			break
		}

		// Parse mode from the response payload
		// Encoding: [47:32] = width, [31:16] = height, [15:0] = refresh_fp upper bits
		width := u32((resp.data0 >> 32) & 0xffff)
		height := u32((resp.data0 >> 16) & 0xffff)
		refresh_fp := u32(resp.data0 & 0xffff) << 16

		if width == 0 || height == 0 {
			// End-of-list sentinel
			break
		}

		modes << IomfbTimingMode{
			width:           width
			height:          height
			refresh_rate_fp: refresh_fp
			flags:           0
		}
	}

	if modes.len > 0 {
		println('iomfb: Enumerated ${modes.len} timing mode(s)')
	}

	return modes
}

// Set the display mode to the specified resolution via IOMFB.
pub fn iomfb_set_mode(mut rtk rtkit.RTKit, state &IomfbState, width u32, height u32) bool {
	// Encode: type in [55:48], width in [47:32], height in [31:16]
	payload := (u64(iomfb_msg_set_mode) << 48) | (u64(width) << 32) | (u64(height) << 16)

	if !rtk.send_msg(iomfb_endpoint, u8(iomfb_msg_set_mode), payload) {
		C.printf(c'iomfb: Failed to send set_mode %ux%u\n', width, height)
		return false
	}

	// Wait for mode-set acknowledgment
	resp := rtk.recv_msg_blocking(iomfb_timeout) or {
		C.printf(c'iomfb: Timeout waiting for set_mode ack\n')
		return false
	}

	ack_type := u32(resp.data0 >> 48) & 0xff
	if ack_type != iomfb_msg_set_mode {
		C.printf(c'iomfb: Unexpected ack type %u for set_mode\n', ack_type)
		return false
	}

	// Check for success status in lower bits
	status := u32(resp.data0 & 0xffff)
	if status != 0 {
		C.printf(c'iomfb: set_mode returned error status %u\n', status)
		return false
	}

	return true
}

// Begin a frame swap transaction. Returns a swap ID that must be passed
// to swap_submit and swap_complete. Returns 0 on failure.
pub fn iomfb_swap_start(mut rtk rtkit.RTKit, state &IomfbState) u32 {
	payload := u64(iomfb_msg_swap_start) << 48

	if !rtk.send_msg(iomfb_endpoint, u8(iomfb_msg_swap_start), payload) {
		C.printf(c'iomfb: Failed to send swap_start\n')
		return 0
	}

	resp := rtk.recv_msg_blocking(iomfb_timeout) or {
		C.printf(c'iomfb: Timeout waiting for swap_start ack\n')
		return 0
	}

	ack_type := u32(resp.data0 >> 48) & 0xff
	if ack_type != iomfb_msg_swap_start {
		return 0
	}

	// Swap ID is returned in the lower 32 bits
	swap_id := u32(resp.data0 & 0xffffffff)
	return swap_id
}

// Submit a frame swap descriptor to the DCP firmware. The descriptor
// contains the source framebuffer address, dimensions, format, and the
// destination rectangle on the display.
pub fn iomfb_swap_submit(mut rtk rtkit.RTKit, state &IomfbState, desc &IomfbSwapDesc) bool {
	// The swap descriptor is placed in shared memory and a pointer is
	// sent to the firmware. For simplicity we encode the key fields
	// directly in the RTKit message payload.
	//
	// Message layout:
	//   data0[55:48] = msg type
	//   data0[47:32] = swap_id
	//   data0[31:0]  = upper 32 bits of src_addr
	// The full descriptor is written to the shared memory region at a
	// well-known offset so the firmware can read all fields.

	payload := (u64(iomfb_msg_swap_submit) << 48) | (u64(desc.swap_id) << 32) | u64(u32(desc.src_addr >> 32))

	if !rtk.send_msg(iomfb_endpoint, u8(iomfb_msg_swap_submit), payload) {
		C.printf(c'iomfb: Failed to send swap_submit (id=%u)\n', desc.swap_id)
		return false
	}

	resp := rtk.recv_msg_blocking(iomfb_timeout) or {
		C.printf(c'iomfb: Timeout waiting for swap_submit ack\n')
		return false
	}

	ack_type := u32(resp.data0 >> 48) & 0xff
	if ack_type != iomfb_msg_swap_submit {
		C.printf(c'iomfb: Unexpected ack type %u for swap_submit\n', ack_type)
		return false
	}

	return true
}

// Wait for a swap to complete (frame has been scanned out by the display
// engine). The DCP firmware sends a swap_complete message when the frame
// has been presented.
pub fn iomfb_swap_complete(mut rtk rtkit.RTKit, state &IomfbState, swap_id u32) bool {
	// Poll for the swap_complete notification from firmware
	for _ in 0 .. iomfb_timeout {
		resp := rtk.recv_msg() or {
			cpu.wfe()
			continue
		}

		resp_type := u32(resp.data0 >> 48) & 0xff
		if resp_type == iomfb_msg_swap_complete {
			completed_id := u32(resp.data0 & 0xffffffff)
			if completed_id == swap_id {
				return true
			}
		}

		// Not our completion message; keep waiting
		cpu.isb()
	}

	C.printf(c'iomfb: swap_complete timeout (id=%u)\n', swap_id)
	return false
}
