@[has_globals]
module virtio_net

import aarch64.cpu
import aarch64.uart
import memory
import socket.inet

const reg_magic = u64(0x000)
const reg_version = u64(0x004)
const reg_device_id = u64(0x008)
const reg_host_features = u64(0x010)
const reg_guest_features = u64(0x020)
const reg_guest_page_size = u64(0x028)
const reg_queue_sel = u64(0x030)
const reg_queue_num_max = u64(0x034)
const reg_queue_num = u64(0x038)
const reg_queue_align = u64(0x03c)
const reg_queue_pfn = u64(0x040)
const reg_queue_notify = u64(0x050)
const reg_interrupt_status = u64(0x060)
const reg_interrupt_ack = u64(0x064)
const reg_status = u64(0x070)
const reg_config = u64(0x100)

const virtio_magic = u32(0x74726976)
const virtio_id_net = u32(1)
const virtio_net_f_mac = u32(1) << 5
const status_acknowledge = u32(1)
const status_driver = u32(2)
const status_driver_ok = u32(4)
const descriptor_write = u16(2)

const mmio_base = u64(0x0a000000)
const mmio_slot_size = u64(0x200)
const mmio_slot_count = u64(32)
const queue_align = u64(4096)
const wanted_queue_size = u16(64)
const buffer_size = u64(2048)
const net_header_size = u64(10)

struct Queue {
mut:
	index          u16
	size           u16
	desc           u64
	avail          u64
	used           u64
	buffers        u64
	buffers_phys   u64
	last_used      u16
	next_available u16
	free           [wanted_queue_size]bool
}

__global (
	device_base = u64(0)
	rx_queue    Queue
	tx_queue    Queue
	mac_address [6]u8
	ready       = false
)

fn mmio_r32(address u64) u32 {
	value := unsafe { *&u32(address) }
	cpu.dmb_ish()
	return value
}

fn mmio_w32(address u64, value u32) {
	cpu.dmb_ish()
	unsafe { *&u32(address) = value }
}

fn align_up(value u64, alignment u64) u64 {
	return (value + alignment - 1) & ~(alignment - 1)
}

fn setup_queue(index u16, hhdm u64, receive bool) ?Queue {
	mmio_w32(device_base + reg_queue_sel, index)
	maximum := mmio_r32(device_base + reg_queue_num_max)
	if maximum == 0 {
		return none
	}
	size := if maximum < wanted_queue_size { u16(maximum) } else { wanted_queue_size }
	mmio_w32(device_base + reg_queue_num, size)
	mmio_w32(device_base + reg_queue_align, u32(queue_align))

	avail_offset := u64(size) * 16
	used_offset := align_up(avail_offset + 4 + 2 * u64(size) + 2, queue_align)
	queue_bytes := used_offset + 4 + 8 * u64(size) + 2
	queue_pages := (queue_bytes + 4095) / 4096
	queue_phys := u64(memory.pmm_alloc(queue_pages))
	if queue_phys == 0 {
		return none
	}
	queue_virt := queue_phys + hhdm
	unsafe { C.memset(voidptr(queue_virt), 0, queue_pages * 4096) }

	buffer_pages := (u64(size) * buffer_size + 4095) / 4096
	buffer_phys := u64(memory.pmm_alloc(buffer_pages))
	if buffer_phys == 0 {
		return none
	}
	buffer_virt := buffer_phys + hhdm
	unsafe { C.memset(voidptr(buffer_virt), 0, buffer_pages * 4096) }

	mut queue := Queue{
		index: index
		size: size
		desc: queue_virt
		avail: queue_virt + avail_offset
		used: queue_virt + used_offset
		buffers: buffer_virt
		buffers_phys: buffer_phys
	}
	for i := u16(0); i < size; i++ {
		descriptor := queue.desc + u64(i) * 16
		unsafe {
			*&u64(descriptor) = buffer_phys + u64(i) * buffer_size
			*&u32(descriptor + 8) = if receive { u32(buffer_size) } else { 0 }
			*&u16(descriptor + 12) = if receive { descriptor_write } else { u16(0) }
			*&u16(descriptor + 14) = 0
		}
		queue.free[i] = !receive
		if receive {
			unsafe { *&u16(queue.avail + 4 + u64(i) * 2) = i }
		}
	}
	if receive {
		queue.next_available = size
		unsafe { *&u16(queue.avail + 2) = size }
	}
	cpu.dmb_ish()
	mmio_w32(device_base + reg_queue_pfn, u32(queue_phys / 4096))
	return queue
}

fn reap_tx() {
	if !ready && device_base == 0 {
		return
	}
	cpu.dmb_ish()
	used_index := unsafe { *&u16(tx_queue.used + 2) }
	for tx_queue.last_used != used_index {
		ring_index := u64(tx_queue.last_used % tx_queue.size)
		descriptor := unsafe { *&u32(tx_queue.used + 4 + ring_index * 8) }
		if descriptor < u32(tx_queue.size) {
			tx_queue.free[descriptor] = true
		}
		tx_queue.last_used++
	}
}

// Called by the C IP shim's Ethernet output callback.  Return zero when the
// frame was accepted and a negative value when the ring is temporarily full.
@[export: 'vinix_virtio_net_send']
pub fn send(frame voidptr, length u64) int {
	if !ready || frame == unsafe { nil } || length > buffer_size - net_header_size {
		return -1
	}
	reap_tx()
	mut descriptor := -1
	for i := 0; i < int(tx_queue.size); i++ {
		if tx_queue.free[i] {
			descriptor = i
			break
		}
	}
	if descriptor < 0 {
		return -1
	}
	tx_queue.free[descriptor] = false
	buffer := tx_queue.buffers + u64(descriptor) * buffer_size
	unsafe {
		C.memset(voidptr(buffer), 0, net_header_size)
		C.memcpy(voidptr(buffer + net_header_size), frame, length)
		*&u32(tx_queue.desc + u64(descriptor) * 16 + 8) = u32(length + net_header_size)
	}
	ring_position := u64(tx_queue.next_available % tx_queue.size)
	unsafe { *&u16(tx_queue.avail + 4 + ring_position * 2) = u16(descriptor) }
	tx_queue.next_available++
	cpu.dmb_ish()
	unsafe { *&u16(tx_queue.avail + 2) = tx_queue.next_available }
	mmio_w32(device_base + reg_queue_notify, tx_queue.index)
	return 0
}

pub fn initialise(hhdm u64) {
	for slot := u64(0); slot < mmio_slot_count; slot++ {
		base := hhdm + mmio_base + slot * mmio_slot_size
		if mmio_r32(base + reg_magic) != virtio_magic
			|| mmio_r32(base + reg_device_id) != virtio_id_net {
			continue
		}
		device_base = base
		uart.puts(c'virtio-net: found at slot ')
		uart.put_dec(slot)
		uart.puts(c'\n')

		mmio_w32(base + reg_status, 0)
		mmio_w32(base + reg_status, status_acknowledge)
		mmio_w32(base + reg_status, status_acknowledge | status_driver)
		offered := mmio_r32(base + reg_host_features)
		accepted := offered & virtio_net_f_mac
		mmio_w32(base + reg_guest_features, accepted)
		mmio_w32(base + reg_guest_page_size, 4096)
		if accepted & virtio_net_f_mac != 0 {
			for i := u64(0); i < 6; i++ {
				mac_address[i] = unsafe { *&u8(base + reg_config + i) }
			}
		} else {
			mac_address = [u8(0x52), 0x54, 0x00, 0x12, 0x34, 0x56]!
		}

		rx_queue = setup_queue(0, hhdm, true) or {
			uart.puts(c'virtio-net: RX queue unavailable\n')
			return
		}
		tx_queue = setup_queue(1, hhdm, false) or {
			uart.puts(c'virtio-net: TX queue unavailable\n')
			return
		}
		mmio_w32(base + reg_status, status_acknowledge | status_driver | status_driver_ok)
		ready = true
		if !inet.attach(&mac_address, inet.driver_virtio) {
			ready = false
			uart.puts(c'virtio-net: IP stack attach failed\n')
			return
		}
		mmio_w32(base + reg_queue_notify, rx_queue.index)
		uart.puts(c'virtio-net: ready, DHCP requested\n')
		return
	}
	uart.puts(c'virtio-net: no device found\n')
}

pub fn poll() {
	if !ready {
		return
	}
	reap_tx()
	cpu.dmb_ish()
	used_index := unsafe { *&u16(rx_queue.used + 2) }
	mut available_index := unsafe { *&u16(rx_queue.avail + 2) }
	for rx_queue.last_used != used_index {
		ring_index := u64(rx_queue.last_used % rx_queue.size)
		entry := rx_queue.used + 4 + ring_index * 8
		descriptor := unsafe { *&u32(entry) }
		length := unsafe { *&u32(entry + 4) }
		if descriptor < u32(rx_queue.size) && length > net_header_size
			&& length <= buffer_size {
			buffer := rx_queue.buffers + u64(descriptor) * buffer_size + net_header_size
			inet.receive(voidptr(buffer), u64(length) - net_header_size)
		}
		position := u64(available_index % rx_queue.size)
		unsafe { *&u16(rx_queue.avail + 4 + position * 2) = u16(descriptor) }
		available_index++
		rx_queue.last_used++
	}
	if unsafe { *&u16(rx_queue.avail + 2) } != available_index {
		cpu.dmb_ish()
		unsafe { *&u16(rx_queue.avail + 2) = available_index }
		mmio_w32(device_base + reg_queue_notify, rx_queue.index)
	}
	interrupts := mmio_r32(device_base + reg_interrupt_status)
	if interrupts != 0 {
		mmio_w32(device_base + reg_interrupt_ack, interrupts)
	}
}
