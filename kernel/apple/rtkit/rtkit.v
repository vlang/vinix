module rtkit

// Apple RTKit protocol over an ASC mailbox.
//
// Management message types occupy bits 59:52. Application endpoint payloads
// define their own layouts and must be passed through without modification.

import apple.mailbox
import aarch64.aic
import aarch64.cpu
import aarch64.timer
import katomic
import klock
import memory

// RTKit management message types.
pub const msg_hello = u8(1)
pub const msg_hello_ack = u8(2)
pub const msg_start_ep = u8(5)
pub const msg_set_iop_power = u8(6)
pub const msg_iop_power_ack = u8(7)
pub const msg_epmap = u8(8)
pub const msg_epmap_reply = u8(8)
pub const msg_set_ap_power = u8(0xb)
pub const msg_ap_power_ack = u8(0xb)

// RTKit system endpoints.
pub const ep_mgmt = u8(0)
pub const ep_crashlog = u8(1)
pub const ep_syslog = u8(2)
pub const ep_debug = u8(3)
pub const ep_ioreport = u8(4)
pub const ep_oslog = u8(8)
pub const ep_tracekit = u8(0xa)

const management_type_shift = u32(52)
const management_type_mask = u64(0xff) << management_type_shift
const epmap_last = u64(1) << 51
const epmap_more = u64(1)
// RTBuddyManagementEndpoint::_handleEPRollCall reads the group with
// `ubfx x22, x1, #32, #6`, and echoes bits 32..37 back in its reply, so the
// field is six bits wide. Only groups 0..7 are reachable though: an RTKit
// endpoint is a byte, so group 8 would name endpoint 256. The Linux driver
// this port follows masks three bits, and that is what has actually been run
// on this hardware, so placement uses three bits and a wider group is
// reported rather than acted on.
const epmap_group_shift = u32(32)
const epmap_group_mask = u64(0x3f)
const epmap_addressable_group_mask = u32(0x7)
const epmap_group_endpoints = u32(32)
const max_endpoints = u32(256)
const start_ep_flag = u64(1) << 1
const app_endpoint_start = u8(0x20)
const min_supported_version = u16(11)
const max_supported_version = u16(12)
const power_state_on = u16(0x20)
const power_state_init = u16(0x220)
const wake_boot_poll_limit = 10_000_000
const boot_phase_timeout_ns = u64(1_000_000_000)
const boot_irq_poll_us = u64(100)
const buffer_request = u8(1)
const crash_notification = u8(1)
const syslog_log = u8(5)
const syslog_init = u8(8)
const syslog_context_offset = 8
const syslog_context_size = 24
const syslog_max_message_size = 255
const oslog_log = u8(2)
const oslog_log_reserved = u64(0xff_ffff) << 32
const buffer_iova_mask = (u64(1) << 44) - 1
const oslog_iova_mask = (u64(1) << 48) - 1
const max_system_buffer_size = u64(16 * 1024 * 1024)
const crashlog_header_size = u32(0x20)
const crashlog_entry_header_size = u32(0x10)
const crashlog_max_entries = u32(128)
const crashlog_type_header = u32(0x434c4845) // 'CLHE'
const crashlog_type_version = u32(0x43766572) // 'Cver'
const crashlog_type_string = u32(0x43737472) // 'Cstr'
const crashlog_type_mailbox = u32(0x436d6278) // 'Cmbx'
const crashlog_type_time = u32(0x4374696d) // 'Ctim'
const crashlog_type_registers = u32(0x43726738) // 'Crg8'
const crashlog_type_stack = u32(0x43637374) // 'Ccst'

pub enum RTKitState {
	idle
	hello_wait
	epmap_wait
	booting
	running
	error
}

pub struct RTKit {
pub mut:
	mbox             mailbox.Mailbox
	state            RTKitState
	endpoints        [256]bool
	lock             klock.Lock
	name             string
	protocol_version u16
	iop_power_state  u16
	ap_power_state   u16
	shmem_context    voidptr
	shmem_alloc      fn (voidptr, u64) u64 = unsafe { nil }
	shmem_read       fn (voidptr, u64, voidptr, u64) bool = unsafe { nil }
	system_iovas     [16]u64
	system_sizes     [16]u64
	syslog_entries   u32
	syslog_msg_size  u32
	oslog_ack_enabled bool
	// Log endpoint setup and acknowledgement errors can be handled locally.
	// The allocator must unwind failures before another request is accepted.
	nonfatal_log_errors bool
	// Latches the first out-of-range endpoint-map group so a repeating roll
	// call cannot flood the console during boot.
	epmap_group_warned bool
mut:
	firmware_led_boot bool
	boot_send_irq u32
	// Publish both power checks together for senders outside the receive lock.
	application_ready bool
	// A crash blocks every firmware-led endpoint until the next handshake.
	crashed bool
}

pub fn new_rtkit(mbox_base u64, name string) RTKit {
	mut result := RTKit{
		mbox: mailbox.new_mailbox(mbox_base)
		state: .idle
		name: name
	}
	result.endpoints[ep_mgmt] = true
	return result
}

// Install the client allocator used for firmware-requested system buffers.
// The returned address is the IOVA visible to RTKit; zero reports failure.
pub fn (mut rtk RTKit) set_shmem_allocator(context voidptr,
	allocator fn (voidptr, u64) u64) {
	rtk.shmem_context = context
	rtk.shmem_alloc = allocator
}

// The client copies a retained system buffer into caller-owned memory.
pub fn (mut rtk RTKit) set_shmem_reader(reader fn (voidptr, u64, voidptr, u64) bool) {
	rtk.shmem_read = reader
}

@[inline]
fn crashlog_u32(data voidptr, offset u32) u32 {
	value := unsafe { &u8(u64(data) + u64(offset)) }
	return unsafe {
		u32(value[0]) | (u32(value[1]) << 8) | (u32(value[2]) << 16) |
			(u32(value[3]) << 24)
	}
}

@[inline]
fn crashlog_u64(data voidptr, offset u32) u64 {
	return u64(crashlog_u32(data, offset)) | (u64(crashlog_u32(data, offset + 4)) << 32)
}

fn crashlog_string(data voidptr, offset u32, available u32) string {
	bytes := unsafe { &u8(u64(data) + u64(offset)) }
	mut length := u32(0)
	// Keep a corrupt record from making the console walk megabytes even when
	// the entry itself is technically inside the allocated crash buffer.
	limit := if available < 1024 { available } else { u32(1024) }
	for length < limit {
		if unsafe { bytes[length] } == 0 {
			break
		}
		length++
	}
	return unsafe { tos(bytes, int(length)) }
}

fn (rtk &RTKit) print_crashlog_entry_kind(kind u32) {
	C.kprintf(c'rtkit[%.*s]: crash entry %c%c%c%c\n', i32(rtk.name.len), rtk.name.str,
		i32(u8(kind >> 24)), i32(u8(kind >> 16)), i32(u8(kind >> 8)), i32(u8(kind)))
}

fn (rtk &RTKit) print_crashlog_message(data voidptr, offset u32, size u32) {
	id := crashlog_u32(data, offset)
	message := crashlog_string(data, offset + 4, size - 4)
	mut line := 0
	for end := 0; end <= message.len; end++ {
		if end == message.len {
			if line == end && end != 0 { break }
		} else if unsafe { message.str[end] } != `\n` {
			continue
		}
		C.kprintf(c'rtkit[%.*s]: crash message %x: %.*s\n', i32(rtk.name.len),
			rtk.name.str, id, i32(end - line), unsafe { message.str + line })
		line = end + 1
	}
}

fn (rtk &RTKit) print_crashlog_mailbox(data voidptr, offset u32, size u32) {
	// The 28-byte prefix ends at the first 24-byte history record.
	kind := crashlog_u32(data, offset + 16)
	index := crashlog_u32(data, offset + 24)
	C.kprintf(c'rtkit[%.*s]: crash mailbox history type=%u index=%u\n',
		i32(rtk.name.len), rtk.name.str, kind, index)
	count := (size - 28) / 24
	for i := u32(0); i < count; i++ {
		entry := offset + 28 + i * 24
		C.kprintf(c'rtkit[%.*s]:   #%03u@%08x: %016llx %016llx\n',
			i32(rtk.name.len), rtk.name.str, i, crashlog_u32(data, entry + 16),
			crashlog_u64(data, entry), crashlog_u64(data, entry + 8))
	}
}

fn (rtk &RTKit) print_crashlog_registers(data voidptr, offset u32) {
	sp := crashlog_u64(data, offset + 0x100)
	pc := crashlog_u64(data, offset + 0x108)
	psr := crashlog_u64(data, offset + 0x110)
	far := crashlog_u64(data, offset + 0x330)
	esr := crashlog_u64(data, offset + 0x340)
	mode := match psr & 0xf {
		0 { c'EL0t' }
		4 { c'EL1t' }
		5 { c'EL1h' }
		8 { c'EL2t' }
		9 { c'EL2h' }
		else { c'unknown' }
	}
	C.kprintf(c'rtkit[%.*s]: exception mode=%s pc=0x%llx sp=0x%llx psr=0x%llx far=0x%llx esr=0x%llx\n',
		i32(rtk.name.len), rtk.name.str, mode, pc, sp, psr, far, esr)
	for i := u32(0); i < 28; i += 4 {
		reg := offset + 8 + i * 8
		C.kprintf(c'rtkit[%.*s]:   x%02u-x%02u = %016llx %016llx %016llx %016llx\n',
			i32(rtk.name.len), rtk.name.str, i, i + 3, crashlog_u64(data, reg),
			crashlog_u64(data, reg + 8), crashlog_u64(data, reg + 16), crashlog_u64(data, reg + 24))
	}
	C.kprintf(c'rtkit[%.*s]:   x28-x30 = %016llx %016llx %016llx\n',
		i32(rtk.name.len), rtk.name.str, crashlog_u64(data, offset + 0xe8),
		crashlog_u64(data, offset + 0xf0), crashlog_u64(data, offset + 0xf8))
}

fn (rtk &RTKit) dump_crashlog() {
	iova := rtk.system_iovas[ep_crashlog]
	allocated := rtk.system_sizes[ep_crashlog]
	if iova == 0 || allocated < crashlog_header_size || allocated > max_system_buffer_size
		|| rtk.shmem_read == unsafe { nil } {
		C.kprintf(c'rtkit[%.*s]: crash log buffer is unavailable\n', i32(rtk.name.len), rtk.name.str)
		return
	}
	// A crash can arrive during the boot handshake with a spinlock held.
	// Allocate without reclaim, and never parse a borrowed firmware buffer.
	pages := (allocated + memory.page_size - 1) / memory.page_size
	physical := memory.pmm_alloc_nozero_nowait(pages) @[freed]
	if physical == unsafe { nil } {
		C.kprintf(c'rtkit[%.*s]: cannot allocate crash log snapshot\n', i32(rtk.name.len), rtk.name.str)
		return
	}
	defer { memory.pmm_free(physical, pages) }
	data := voidptr(u64(physical) + memory.get_hhdm_offset())
	// The mailbox notification is firmware's publication event for this shared
	// memory. Order subsequent CPU loads after observing it.
	cpu.dmb_ishld()
	if !rtk.shmem_read(rtk.shmem_context, iova, data, allocated) {
		C.kprintf(c'rtkit[%.*s]: cannot copy crash log at 0x%llx\n', i32(rtk.name.len),
			rtk.name.str, iova)
		return
	}
	if crashlog_u32(data, 0) != crashlog_type_header {
		C.kprintf(c'rtkit[%.*s]: invalid crash log header 0x%llx\n', i32(rtk.name.len),
			rtk.name.str, u64(crashlog_u32(data, 0)))
		return
	}
	total := crashlog_u32(data, 8)
	if total < crashlog_header_size || u64(total) > allocated {
		C.kprintf(c'rtkit[%.*s]: invalid crash log size 0x%llx (buffer 0x%llx)\n',
			i32(rtk.name.len), rtk.name.str, u64(total), u64(allocated))
		return
	}
	C.kprintf(c'rtkit[%.*s]: crash log version=%llu size=0x%llx\n', i32(rtk.name.len),
		rtk.name.str, u64(crashlog_u32(data, 4)), u64(total))
	mut offset := crashlog_header_size
	mut entries := u32(0)
	for offset <= total - crashlog_entry_header_size && entries < crashlog_max_entries {
		kind := crashlog_u32(data, offset)
		if kind == crashlog_type_header {
			return
		}
		length := crashlog_u32(data, offset + 0xc)
		if length < crashlog_entry_header_size || length > total - offset {
			C.kprintf(c'rtkit[%.*s]: invalid crash entry length 0x%llx at 0x%llx\n',
				i32(rtk.name.len), rtk.name.str, u64(length), u64(offset))
			return
		}
		// The section length includes its header. Each decoder may read only
		// the payload, even when another section follows in the snapshot.
		payload := offset + crashlog_entry_header_size
		size := length - crashlog_entry_header_size
		match kind {
			crashlog_type_string {
				if size >= 5 {
					rtk.print_crashlog_message(data, payload, size)
				} else {
					rtk.print_crashlog_entry_kind(kind)
				}
			}
			crashlog_type_version {
				if size >= 17 {
					version := crashlog_string(data, payload + 16, size - 16)
					C.kprintf(c'rtkit[%.*s]: crash firmware: %.*s\n', i32(rtk.name.len),
						rtk.name.str, i32(version.len), version.str)
				} else {
					rtk.print_crashlog_entry_kind(kind)
				}
			}
			crashlog_type_mailbox {
				if size >= 28 {
					rtk.print_crashlog_mailbox(data, payload, size)
				} else {
					rtk.print_crashlog_entry_kind(kind)
				}
			}
			crashlog_type_time {
				if size >= 8 {
					C.kprintf(c'rtkit[%.*s]: crash time: %lld\n', i32(rtk.name.len),
						rtk.name.str, i64(crashlog_u64(data, payload)))
				} else {
					rtk.print_crashlog_entry_kind(kind)
				}
			}
			crashlog_type_registers {
				if size >= 0x350 {
					rtk.print_crashlog_registers(data, payload)
				} else {
					rtk.print_crashlog_entry_kind(kind)
				}
			}
			crashlog_type_stack {
				if size >= 8 {
					C.kprintf(c'rtkit[%.*s]: crashed task %llu\n', i32(rtk.name.len),
						rtk.name.str, u64(crashlog_u32(data, payload)))
				} else {
					rtk.print_crashlog_entry_kind(kind)
				}
			}
			else {
				rtk.print_crashlog_entry_kind(kind)
			}
		}
		offset += length
		entries++
	}
	if entries == crashlog_max_entries {
		C.kprintf(c'rtkit[%.*s]: crash log entry limit reached\n', i32(rtk.name.len),
			rtk.name.str)
	} else {
		C.kprintf(c'rtkit[%.*s]: crash log has no terminator\n', i32(rtk.name.len),
			rtk.name.str)
	}
}

@[inline]
fn management_type(data u64) u8 {
	return u8((data >> management_type_shift) & 0xff)
}

@[inline]
fn management_message(kind u8, payload u64) u64 {
	return (payload & ~management_type_mask) | (u64(kind) << management_type_shift)
}

fn (mut rtk RTKit) send_management(kind u8, payload u64) bool {
	return rtk.send_message(ep_mgmt, management_message(kind, payload))
}

fn (mut rtk RTKit) send_start_endpoint(ep u8, irq u32) bool {
	payload := (u64(ep) << 32) | start_ep_flag
	message := mailbox.MboxMsg{data0: management_message(msg_start_ep, payload), data1: ep_mgmt}
	wait := mailbox.SendWait{irq: irq}
	// START_EP travels over management, but the target may need application power.
	application := ep >= app_endpoint_start
	result := rtk.send_message_result(message, wait, application)
	if result == .sent {
		return true
	}
	return rtk.firmware_led_boot && result == .timed_out
		&& rtk.send_message_result(message, wait, application) == .sent
}

fn (mut rtk RTKit) reply_boot_management(kind u8, payload u64, request_wake bool) bool {
	if rtk.send_management(kind, payload) {
		return true
	}
	if request_wake {
		return false
	}
	C.kprintf(c'rtkit[%.*s]: management reply type 0x%llx timed out\n',
		i32(rtk.name.len), rtk.name.str, u64(kind))
	return true
}

fn (mut rtk RTKit) fail(message &char) bool {
	C.kprintf(c'rtkit[%.*s]: %s\n', i32(rtk.name.len), rtk.name.str, message)
	rtk.state = .error
	return false
}

// Request IOP initialization from a client that uses the wake handshake.
pub fn (mut rtk RTKit) boot() bool {
	return rtk.boot_transport(true, 0, 0)
}

// The G13 ASC starts RTKit when the GPU driver releases its CPU. The
// initializer owns the transport until boot returns.
pub fn (mut rtk RTKit) boot_started(receive_irq u32, send_irq u32) bool {
	return rtk.boot_transport(false, receive_irq, send_irq)
}

fn (mut rtk RTKit) wait_boot_receive_irq(receive_irq u32) {
	// An empty FIFO can accept another notification. Restore the caller's
	// interrupt state while waiting and fall back to a fresh read if needed.
	aic.rearm_deferred_irq(receive_irq)
	rtk.lock.release()
	started := timer.get_us()
	for !aic.deferred_irq_pending(receive_irq) && timer.get_us() - started < boot_irq_poll_us {
		timer.busywait_us(10)
	}
	rtk.lock.acquire()
}

fn (mut rtk RTKit) boot_transport(request_wake bool, receive_irq u32, send_irq u32) bool {
	rtk.lock.acquire()
	rtk.boot_send_irq = send_irq
	defer {
		rtk.boot_send_irq = 0
		rtk.lock.release()
	}

	if rtk.state == .running {
		return true
	}
	rtk.state = .hello_wait
	rtk.firmware_led_boot = !request_wake
	rtk.iop_power_state = 0
	rtk.ap_power_state = 0
	rtk.refresh_application_ready()
	katomic.store(mut rtk.crashed, false)
	C.kprintf(c'rtkit[%.*s]: Starting boot handshake\n', i32(rtk.name.len), rtk.name.str)

	// Wake the IOP. Its acknowledgment may arrive before or after HELLO/EPMAP.
	if request_wake && !rtk.send_management(msg_set_iop_power, u64(power_state_init)) {
		return rtk.fail(c'failed to request IOP initialization')
	}

	mut endpoint_map_done := false
	mut iop_acknowledged := false
	mut ap_power_requested := false
	mut phase_started := if request_wake { u64(0) } else { timer.get_ns() }
	for polls := 0; ; polls++ {
		if request_wake {
			if polls >= wake_boot_poll_limit { break }
		} else if timer.get_ns() - phase_started >= boot_phase_timeout_ns {
			break
		}
		msg := rtk.mbox.recv() or {
			if request_wake {
				cpu.wfe()
			} else if receive_irq != 0 {
				rtk.wait_boot_receive_irq(receive_irq)
			} else {
				// The manager and RTKit locks mask interrupts. Keep the
				// deadline check runnable even without a mailbox event.
				timer.busywait_us(10)
			}
			continue
		}
		ep := mailbox.msg_endpoint(&msg)
		if ep != ep_mgmt {
			if !rtk.handle_system_message(msg) {
				return rtk.fail(c'failed to service a system endpoint')
			}
			continue
		}

		kind := management_type(msg.data0)
		match kind {
			msg_hello {
				min_version := u16(msg.data0 & 0xffff)
				max_version := u16((msg.data0 >> 16) & 0xffff)
				if min_version > max_supported_version || max_version < min_supported_version {
					C.kprintf(c'rtkit[%.*s]: unsupported protocol range %llu-%llu\n',
						i32(rtk.name.len), rtk.name.str, u64(min_version), u64(max_version))
					rtk.state = .error
					return false
				}
				version := if max_version < max_supported_version {
					max_version
				} else {
					max_supported_version
				}
				rtk.protocol_version = version
				payload := u64(version) | (u64(version) << 16)
				if !rtk.reply_boot_management(msg_hello_ack, payload, request_wake) {
					return rtk.fail(c'failed to acknowledge HELLO')
				}
				rtk.state = .epmap_wait
				C.kprintf(c'rtkit[%.*s]: negotiated protocol version %llu\n', i32(rtk.name.len),
					rtk.name.str, u64(version))
			}
			msg_epmap {
				bitmap := u32(msg.data0 & 0xffff_ffff)
				group := u32((msg.data0 >> epmap_group_shift) & epmap_group_mask)
				block := group & epmap_addressable_group_mask
				if group != block && !rtk.epmap_group_warned {
					// Never observed. If it ever fires, the upper group bits
					// carry something this decoder does not model.
					rtk.epmap_group_warned = true
					C.kprintf(c'rtkit[%.*s]: endpoint-map group %llu exceeds the addressable range\n',
						i32(rtk.name.len), rtk.name.str, u64(group))
				}
				last := msg.data0 & epmap_last != 0
				base := block * epmap_group_endpoints
				for bit := u32(0); bit < epmap_group_endpoints; bit++ {
					if bitmap & (u32(1) << bit) == 0 {
						continue
					}
					ep_id := base + bit
					if ep_id >= max_endpoints {
						continue
					}
					rtk.endpoints[ep_id] = true
				}
				// The G13 Linux handshake echoes the three-bit base. Keep
				// the six-bit echo for clients using the wake handshake.
				reply_group := if request_wake { group } else { block }
				mut reply := u64(reply_group) << epmap_group_shift
				if last {
					reply |= epmap_last
				} else {
					reply |= epmap_more
				}
				if !rtk.reply_boot_management(msg_epmap_reply, reply, request_wake) {
					return rtk.fail(c'failed to acknowledge endpoint map')
				}
				if last {
					if !start_system_endpoints(mut rtk, !request_wake) {
						return rtk.fail(c'failed to start a system endpoint')
					}
					if !request_wake && !endpoint_map_done {
						phase_started = timer.get_ns()
					}
					endpoint_map_done = true
				}
			}
			msg_iop_power_ack {
				rtk.iop_power_state = u16(msg.data0 & 0xffff)
				iop_acknowledged = true
			}
			msg_ap_power_ack {
				rtk.ap_power_state = u16(msg.data0 & 0xffff)
				if !request_wake && ap_power_requested && rtk.ap_power_state != power_state_on {
					return rtk.fail(c'AP power acknowledgement did not report ON')
				}
			}
			else {
				C.kprintf(c'rtkit[%.*s]: ignoring management message type 0x%llx\n',
					i32(rtk.name.len), rtk.name.str, u64(kind))
			}
		}

		// Firmware-led boot waits for the IOP acknowledgement independently
		// of its state. The wake handshake requires IOP ON at this point.
		iop_ready := if request_wake {
			(rtk.iop_power_state & 0xff) == power_state_on
		} else {
			iop_acknowledged
		}
		if endpoint_map_done && iop_ready && !ap_power_requested {
			if !request_wake {
				// An acknowledgement from before this request cannot
				// satisfy the AP transition, even if it reported ON.
				rtk.ap_power_state = 0
			}
			if !rtk.send_management(msg_set_ap_power, u64(power_state_on)) {
				return rtk.fail(c'failed to request AP power state')
			}
			ap_power_requested = true
			rtk.state = .booting
			if !request_wake { phase_started = timer.get_ns() }
		}
		if ap_power_requested && iop_ready && (rtk.ap_power_state & 0xff) == power_state_on {
			rtk.state = .running
			rtk.refresh_application_ready()
			C.kprintf(c'rtkit[%.*s]: Boot handshake complete\n', i32(rtk.name.len), rtk.name.str)
			return true
		}
	}

	return rtk.fail(c'boot handshake timed out')
}

// Only the system endpoints that negotiate a buffer call this handler.
fn (mut rtk RTKit) reply_system_buffer(ep u8, msg u64, wait mailbox.SendWait) bool {
	iova_mask := if ep == ep_oslog { oslog_iova_mask } else { buffer_iova_mask }
	mut size := u64(0)
	mut requested_iova := u64(0)
	if ep == ep_oslog {
		size = (msg >> 36) & 0xf_ffff
		requested_iova = (msg << 12) & iova_mask
	} else {
		size = ((msg >> 44) & 0xff) << 12
		requested_iova = msg & iova_mask
	}
	mut iova := rtk.system_iovas[ep]
	if iova != 0 {
		// Compare the address as encoded in the reply. AGX keeps the full
		// sign-extended IOVA for its UAT mapping and crash-buffer reads.
		if size != rtk.system_sizes[ep] || (requested_iova != 0 && requested_iova != (iova & iova_mask)) {
			C.kprintf(c'rtkit[%.*s]: conflicting buffer request ep=%llu size=0x%llx iova=0x%llx\n',
				i32(rtk.name.len), rtk.name.str, u64(ep), size, requested_iova)
			return true
		}
	} else {
		// Clients allocate the mapping and cannot adopt an address chosen
		// by firmware. A nonzero address can only identify a live buffer.
		if size == 0 || size > max_system_buffer_size || requested_iova != 0
			|| rtk.shmem_alloc == unsafe { nil } {
			C.kprintf(c'rtkit[%.*s]: invalid buffer request ep=%llu size=0x%llx iova=0x%llx\n',
				i32(rtk.name.len), rtk.name.str, u64(ep), size, requested_iova)
			return rtk.nonfatal_log_errors
		}
		iova = rtk.shmem_alloc(rtk.shmem_context, size)
		if iova == 0 {
			C.kprintf(c'rtkit[%.*s]: failed to allocate 0x%llx-byte buffer for ep=%llu\n',
				i32(rtk.name.len), rtk.name.str, size, u64(ep))
			return rtk.nonfatal_log_errors
		}
		rtk.system_iovas[ep] = iova
		rtk.system_sizes[ep] = size
	}

	wire_iova := iova & iova_mask
	mut reply := u64(0)
	if ep == ep_oslog {
		if iova & 0xfff != 0 {
			return false
		}
		reply = (u64(buffer_request) << 56) | (size << 36) | (wire_iova >> 12)
	} else {
		reply = (u64(buffer_request) << management_type_shift) | ((size >> 12) << 44) | wire_iova
	}
	// Logging endpoints can retry publication of a retained mapping after a
	// mailbox timeout. Crashlog keeps the buffer for later notifications.
	sent := rtk.send_system_reply(ep, reply, wait)
	if !sent && rtk.nonfatal_log_errors {
		C.kprintf(c'rtkit[%.*s]: buffer reply timed out on endpoint %llu\n',
			i32(rtk.name.len), rtk.name.str, u64(ep))
	}
	return sent || ep != ep_crashlog || rtk.nonfatal_log_errors
}

fn (mut rtk RTKit) acknowledge_log(ep u8, data u64, wait mailbox.SendWait) bool {
	sent := rtk.send_system_reply(ep, data, wait)
	if !sent && rtk.nonfatal_log_errors {
		C.kprintf(c'rtkit[%.*s]: log acknowledgement timed out on endpoint %llu\n',
			i32(rtk.name.len), rtk.name.str, u64(ep))
	}
	return sent || rtk.nonfatal_log_errors
}

fn (rtk &RTKit) dump_syslog_entry(msg u64) {
	message_size := rtk.syslog_msg_size
	iova := rtk.system_iovas[ep_syslog]
	if rtk.shmem_read == unsafe { nil } || iova == 0 || message_size == 0
		|| message_size > syslog_max_message_size {
		return
	}

	index := u64(u8(msg))
	stride := u64(syslog_context_offset + syslog_context_size + message_size)
	if index >= rtk.syslog_entries || index >= rtk.system_sizes[ep_syslog] / stride {
		return
	}
	offset := index * stride + syslog_context_offset
	mut payload := [syslog_context_size + syslog_max_message_size]u8{}
	cpu.dmb_ishld()
	if !rtk.shmem_read(rtk.shmem_context, iova + offset, unsafe { &payload[0] },
		u64(syslog_context_size + message_size)) {
		return
	}

	payload[syslog_context_size - 1] = 0
	mut end := u32(syslog_context_size)
	limit := syslog_context_size + message_size - 1
	for end < limit && payload[end] != 0 { end++ }
	for end > syslog_context_size {
		last := payload[end - 1]
		if last != ` ` && last != `\n` && last != `\r` { break }
		end--
	}
	payload[end] = 0
	C.kprintf(c'rtkit[%.*s]: syslog message: %s: %s\n', i32(rtk.name.len), rtk.name.str,
		unsafe { &char(&payload[0]) }, unsafe { &char(&payload[syslog_context_size]) })
}

fn (mut rtk RTKit) refresh_application_ready() {
	if rtk.firmware_led_boot {
		katomic.store(mut rtk.application_ready, rtk.state == .running
			&& (rtk.iop_power_state & 0xff) == power_state_on
			&& (rtk.ap_power_state & 0xff) == power_state_on)
	}
}

// Handle one RTKit transport message addressed to a system endpoint. This is
// also called after boot so late logs and reports cannot fill the ASC mailbox.
pub fn (mut rtk RTKit) handle_system_message(msg mailbox.MboxMsg) bool {
	return rtk.handle_system_message_wait(msg, mailbox.SendWait{})
}

pub fn (mut rtk RTKit) handle_system_message_wait(msg mailbox.MboxMsg, wait mailbox.SendWait) bool {
	ep := mailbox.msg_endpoint(&msg)
	match ep {
		ep_mgmt {
			kind := management_type(msg.data0)
			match kind {
				msg_iop_power_ack {
					rtk.iop_power_state = u16(msg.data0 & 0xffff)
					rtk.refresh_application_ready()
				}
				msg_ap_power_ack {
					rtk.ap_power_state = u16(msg.data0 & 0xffff)
					rtk.refresh_application_ready()
				}
				else {
					C.kprintf(c'rtkit[%.*s]: ignoring runtime management message 0x%llx\n',
						i32(rtk.name.len), rtk.name.str, u64(kind))
				}
			}
		}
		ep_crashlog {
			if management_type(msg.data0) != crash_notification {
				C.kprintf(c'rtkit[%.*s]: unknown crashlog message 0x%llx\n',
					i32(rtk.name.len), rtk.name.str, msg.data0)
				return true
			}
			if rtk.system_iovas[ep] == 0 {
				return rtk.reply_system_buffer(ep, msg.data0, wait)
			}
			katomic.store(mut rtk.crashed, true)
			C.kprintf(c'rtkit[%.*s]: coprocessor crash notification\n', i32(rtk.name.len),
				rtk.name.str)
			rtk.dump_crashlog()
			rtk.state = .error
			return false
		}
		ep_ioreport {
			kind := management_type(msg.data0)
			if kind == buffer_request {
				return rtk.reply_system_buffer(ep, msg.data0, wait)
			}
			// Unknown IOReport requests 0x8 and 0xc must be acknowledged or
			// some coprocessors stop making progress.
			if kind == 0x8 || kind == 0xc {
				return rtk.acknowledge_log(ep, msg.data0, wait)
			}
		}
		ep_syslog {
			kind := management_type(msg.data0)
			if kind == buffer_request {
				return rtk.reply_system_buffer(ep, msg.data0, wait)
			}
			if kind == syslog_init {
				rtk.syslog_entries = u32(msg.data0 & 0xff)
				rtk.syslog_msg_size = u32((msg.data0 >> 24) & 0xff)
				return true
			}
			// Echo the notification even if the record could not be read.
			if kind == syslog_log {
				rtk.dump_syslog_entry(msg.data0)
				return rtk.acknowledge_log(ep, msg.data0, wait)
			}
		}
		ep_oslog {
			kind := u8(msg.data0 >> 56)
			if kind == buffer_request {
				return rtk.reply_system_buffer(ep, msg.data0, wait)
			}
			if kind == oslog_log && rtk.oslog_ack_enabled {
				if rtk.system_iovas[ep] == 0 || msg.data0 & oslog_log_reserved != 0 {
					C.kprintf(c'rtkit[%.*s]: invalid oslog notification 0x%llx\n',
						i32(rtk.name.len), rtk.name.str, msg.data0)
					return true
				}
				// Channel zero carries a wrapping write counter. Echo it
				// verbatim, including counters larger than the buffer.
				if !rtk.send_system_reply(ep, msg.data0, wait) {
					C.kprintf(c'rtkit[%.*s]: oslog acknowledgement failed\n',
						i32(rtk.name.len), rtk.name.str)
				}
			}
		}
		else {}
	}
	return true
}

// A stopped transport has no reply outstanding. For a guarded wait this
// decision is made under the same lock as the cancellation check.
fn (mut rtk RTKit) send_system_reply(ep u8, data u64, wait mailbox.SendWait) bool {
	return rtk.send_message_wait(ep, data, wait)
		|| (wait.lock != unsafe { nil } && !wait.active(wait.context))
}

fn start_system_endpoints(mut rtk RTKit, start_tracekit bool) bool {
	system_eps := [ep_crashlog, ep_syslog, ep_debug, ep_ioreport, ep_oslog, ep_tracekit]!
	for ep in system_eps {
		if ep == ep_tracekit && !start_tracekit { continue }
		if rtk.endpoints[ep] && !rtk.send_start_endpoint(ep, 0) {
			return false
		}
	}
	return true
}

// Start an application endpoint after RTKit has reached the ON state.
pub fn (mut rtk RTKit) start_endpoint(ep u8) bool {
	return rtk.start_endpoint_irq(ep, 0)
}

// A nonzero IRQ is reserved for the private G13 initializer, which owns the
// transport with interrupts enabled after the handshake.
pub fn (mut rtk RTKit) start_endpoint_irq(ep u8, irq u32) bool {
	if !rtk.endpoints[ep] {
		C.kprintf(c'rtkit[%.*s]: Endpoint %llu not available\n', i32(rtk.name.len),
			rtk.name.str, u64(ep))
		return false
	}
	if ep >= app_endpoint_start {
		ready := if rtk.firmware_led_boot {
			!katomic.load(&rtk.crashed) && katomic.load(&rtk.application_ready)
		} else {
			rtk.state == .running
		}
		if !ready {
			C.kprintf(c'rtkit[%.*s]: Endpoint %llu requested before RTKit is running\n',
				i32(rtk.name.len), rtk.name.str, u64(ep))
			return false
		}
	}
	return rtk.send_start_endpoint(ep, irq)
}

// Send a protocol-defined payload without changing any of its bits.
pub fn (mut rtk RTKit) send_message(ep u8, data u64) bool {
	return rtk.send_message_irq(ep, data, 0)
}

// The private initializer uses its reserved line for application sends.
pub fn (mut rtk RTKit) send_message_irq(ep u8, data u64, irq u32) bool {
	return rtk.send_message_wait(ep, data, mailbox.SendWait{irq: irq})
}

struct TransportSendGuard {
	rtk  &RTKit
	wait mailbox.SendWait
	application bool
}

fn rtkit_send_active(context voidptr) bool {
	guard := unsafe { &TransportSendGuard(context) }
	return (guard.wait.active == unsafe { nil } || guard.wait.active(guard.wait.context))
		&& !katomic.load(&guard.rtk.crashed)
		&& (!guard.application || katomic.load(&guard.rtk.application_ready))
}

pub fn (mut rtk RTKit) send_message_wait(ep u8, data u64, wait mailbox.SendWait) bool {
	message := mailbox.MboxMsg{
		data0: data
		data1: u64(ep)
	}
	return rtk.send_message_result(message, wait, ep >= app_endpoint_start) == .sent
}

// A firmware-led send checks readiness before each FIFO attempt.
fn (mut rtk RTKit) send_message_result(message mailbox.MboxMsg, wait mailbox.SendWait,
	application bool) mailbox.SendResult {
	if rtk.firmware_led_boot {
		boot_irq := if wait.lock == unsafe { nil } { rtk.boot_send_irq } else { u32(0) }
		// The mailbox checks this synchronously, with wait.lock held if supplied.
		guard := TransportSendGuard{rtk: rtk, wait: wait, application: application}
		send_wait := mailbox.SendWait{
			irq: if boot_irq != 0 { boot_irq } else { wait.irq }
			lock: wait.lock
			context: unsafe { voidptr(&guard) }
			active: rtkit_send_active
		}
		if boot_irq != 0 { rtk.lock.release() }
		result := rtk.mbox.send_timed_wait(message, send_wait)
		if boot_irq != 0 { rtk.lock.acquire() }
		return result
	}
	if wait.lock != unsafe { nil } {
		return rtk.mbox.send_timed_wait(message, wait)
	}
	return if rtk.mbox.send(message) { .sent } else { .timed_out }
}

pub fn (mut rtk RTKit) recv_msg() ?mailbox.MboxMsg {
	return rtk.mbox.recv()
}

pub fn (mut rtk RTKit) recv_msg_blocking(timeout int) ?mailbox.MboxMsg {
	return rtk.mbox.recv_blocking(timeout)
}
