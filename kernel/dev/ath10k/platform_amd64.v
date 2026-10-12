// SPDX-License-Identifier: ISC
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module ath10k

import acpisync
import devcore
import dma
import errno
import event.eventstruct
import fs
import fwload
import katomic
import klock
import krandom
import memory
import resource
import socket.inet
import stat
import usercopy
import x86.kio

const board_name = 'bus=pci,vendor=168c,device=0042,subsystem-vendor=17aa,subsystem-device=0901'
const firmware_name = 'ath10k/QCA9377/hw1.0/firmware-6.bin'
const board_file = 'ath10k/QCA9377/hw1.0/board-2.bin'

__global (
	card_device   &devcore.Device = unsafe { nil }
	card_regs     u64
	card_pool     dma.Buffer
	card_firmware &fwload.Image = unsafe { nil }
	card_board    &fwload.Image = unsafe { nil }
	card_protocol Protocol
	card_wmi      Wmi
	card_htt      Htt
	card_station  Station
	card_rx_lock  klock.Lock
	card_tx_lock  klock.Lock
	card_gate     voidptr
	card_active   bool
	card_radio    bool
	card_link     bool
	card_stage    u32
	card_error    int
	card_node     WifiDevice
	card_box      &resource.Resource = unsafe { nil }
)

fn bus_read(_ voidptr, offset u32) u32 { return kio.mmin[u32](unsafe { &u32(card_regs + offset) }) }

fn bus_write(_ voidptr, offset u32, value u32) {
	kio.mmout[u32](unsafe { &u32(card_regs + offset) }, value)
}

fn bus_clock(_ voidptr) u64 { return devcore.now_ns() }

fn bus_delay(_ voidptr, us u32) { devcore.stall(u64(us) * 1000) }

fn bus_barrier() {
	asm volatile amd64 { mfence ; ; ; memory }
}

fn card_matches(dev &devcore.Device) bool {
	return dev.bus == .pci && dev.vendor == 0x168c && dev.device == 0x0042 && dev.pci.read[u32](0x2c) == 0x090117aa
}

pub fn initialise() {
	card_gate = acpisync.create(true)
	devcore.register_driver(devcore.Driver{
		name:     'ath10k'
		bus:      .pci
		matches:  card_matches
		probe:    card_probe
		remove:   card_remove
		suspend:  card_suspend
		resume:   card_resume
		reset:    card_resume
		shutdown: card_shutdown
	}) or {}
}

fn log_failure(stage u32) bool {
	card_error = -5
	C.kprintf(c'ath10k: QCA9377 startup failed at stage %u; see /proc/bootlog\n', stage)
	return false
}

fn fence() {
	card_rx_lock.acquire()
	card_active = false
	card_rx_lock.release()
	card_tx_lock.acquire()
	card_station.fail(-100)
	card_tx_lock.release()
	card_link = false
	inet.detach_owned(inet.driver_ath10k)
}

fn stop(mut dev devcore.Device) {
	bus_write(unsafe { nil }, 0x3a008, 0)
	dev.pci.update_command(4, 0)
	_ = dev.pci.read[u16](4)
	bus_barrier()
	bus_write(unsafe { nil }, 0x80008, 1)
	devcore.sleep_ms(20)
	if card_pool.virt != 0 { erase(voidptr(card_pool.virt), card_pool.bytes) }
}

fn release_images() {
	fwload.release(card_firmware)
	fwload.release(card_board)
	card_firmware = unsafe { nil }
	card_board = unsafe { nil }
}

fn card_probe(mut dev devcore.Device) bool {
	if card_device != unsafe { nil } || card_gate == unsafe { nil } { return false }
	pm := dev.pci.capability(1)
	if pm != 0 {
		control := dev.pci.read[u16](u32(pm) + 4)
		if control & 3 != 0 {
			dev.pci.write[u16](u32(pm) + 4, control & ~u16(0x8103))
			devcore.sleep_ms(10)
		}
	}
	dev.pci.update_command(5, 2 | (u16(1) << 10))
	bar := dev.pci.get_bar(0)
	if !bar.is_mmio || bar.base == 0 || bar.size < 0x8000c || bar.base + bar.size < bar.base {
		return false
	}
	card_regs = bar.base + memory.get_hhdm_offset()
	if bar.base + bar.size > 0x100000000 {
		for page := bar.base & ~u64(4095); page < bar.base + bar.size; page += 4096 {
			kernel_pagemap.map_page(page + memory.get_hhdm_offset(), page,
				memory.pte_present | memory.pte_writable | memory.pte_noexec | u64(0x18)) or { return false }
		}
	}
	pcie := dev.pci.capability(0x10)
	if pcie != 0 {
		link := dev.pci.read[u16](u32(pcie) + 0x10)
		dev.pci.write[u16](u32(pcie) + 0x10, link & ~u16(0x103))
	}
	dma.set_address_bits(mut dev, 32)
	card_pool = dma.alloc_buffer(mut dev, 4 * 1024 * 1024) or { return false }
	card_device = unsafe { dev }
	card_radio = true
	if card_box == unsafe { nil } {
		card_node.stat.mode = stat.ifchr | 0o600
		card_node.stat.rdev = resource.create_dev_id()
		card_node.stat.blksize = 1518
		card_box = &resource.Resource(unsafe { &card_node })
	}
	fs.devtmpfs_add_device(card_box, 'wlan0')
	C.kprintf(c'ath10k: PCI %llx:%llx.%llx QCA9377 168c:0042 Lenovo 17aa:0901\n',
		u64(dev.pci.bus), u64(dev.pci.slot), u64(dev.pci.function))
	acpisync.acquire(card_gate, 0xffff)
	if !start(mut dev) { stop(mut dev) }
	acpisync.signal(card_gate)
	// Retain the binding and diagnostic node when firmware is missing. A
	// later retry uses the same DMA allocation, without requiring a reboot.
	return true
}

fn start(mut dev devcore.Device) bool {
	fence()
	card_error = 0
	card_stage = 1
	stop(mut dev)
	dev.pci.update_command(5, 2 | (u16(1) << 10))
	if card_firmware == unsafe { nil } {
		card_firmware = fwload.request(firmware_name) or {
			card_error = -2
			print('ath10k: missing ath10k/QCA9377/hw1.0/firmware-6.bin; install firmware, then wifi-ctl boot\n')
			return false
		}
	}
	if card_board == unsafe { nil } {
		card_board = fwload.request(board_file) or {
			card_error = -2
			print('ath10k: missing ath10k/QCA9377/hw1.0/board-2.bin\n')
			return false
		}
	}
	firmware := parse_firmware(Blob{ data: card_firmware.data, len: u32(card_firmware.size) }) or { return log_failure(card_stage) }
	board := select_board(Blob{ data: card_board.data, len: u32(card_board.size) }, board_name) or { return log_failure(card_stage) }
	card_protocol = Protocol{
		context:   unsafe { nil }
		event:     protocol_event
		transport: Transport{
			hardware: Hardware{ read: bus_read, write: bus_write, clock: bus_clock, delay: bus_delay, barrier: bus_barrier }
			pool:     Blob{ data: unsafe { &u8(card_pool.virt) }, len: u32(card_pool.bytes) }
			bus:      u32(card_pool.bus)
		}
	}
	card_wmi = Wmi{ management: management_input }
	card_htt = Htt{ input: ethernet_input }
	card_station = Station{}
	card_stage = 2
	if !card_protocol.transport.layout() || !card_protocol.transport.reset_rom() {
		return log_failure(card_stage)
	}
	dev.pci.update_command(0, 4)
	_ = dev.pci.read[u16](4)
	card_stage = 3
	if !card_protocol.transport.configure_pcie_target() { return log_failure(card_stage) }
	card_stage = 4
	version := card_protocol.transport.boot(firmware, board) or { return log_failure(card_stage) }
	C.kprintf(c'ath10k: target %08llx, firmware and Lenovo board loaded\n', u64(version))
	card_stage = 5
	if !card_protocol.wait_ready() { return log_failure(card_stage) }
	card_protocol.connect(0x100) or { return log_failure(card_stage) }
	card_protocol.connect(0x300) or { return log_failure(card_stage) }
	if !card_protocol.finish_setup() { return log_failure(card_stage) }
	card_stage = 6
	limit := devcore.deadline(5 * devcore.second)
	for !card_wmi.ready && !card_protocol.transport.fault {
		card_protocol.poll()
		if card_wmi.service_ready && !card_wmi.init_sent {
			_ = card_wmi.initialise(mut card_protocol)
		}
		if limit.expired() { return log_failure(card_stage) }
		devcore.sleep_ms(1)
	}
	if !card_wmi.ready { return log_failure(card_stage) }
	card_stage = 7
	if !card_htt.request_version(mut card_protocol) { return log_failure(card_stage) }
	htt_limit := devcore.deadline(3 * devcore.second)
	for !card_htt.version && !card_protocol.transport.fault {
		card_protocol.poll()
		if htt_limit.expired() { return log_failure(card_stage) }
		devcore.sleep_ms(1)
	}
	if !card_htt.configure(mut card_protocol, card_wmi.full_reorder) {
		return log_failure(card_stage)
	}
	// These commands share WMI's FIFO; scan is issued after them.
	setup_limit := devcore.deadline(3 * devcore.second)
	mut table_sent := false
	for !card_wmi.vdev || !table_sent {
		card_protocol.poll()
		if !card_wmi.vdev { _ = card_wmi.create_vdev(mut card_protocol) }
		if card_wmi.vdev && !table_sent { table_sent = card_wmi.channel_table(mut card_protocol) }
		if card_protocol.transport.fault || setup_limit.expired() { return log_failure(card_stage) }
		devcore.sleep_ms(1)
	}
	card_stage = 8
	card_rx_lock.acquire()
	card_active = true
	card_rx_lock.release()
	print('ath10k: radio ready; passive scan and WPA2-PSK/CCMP on channels 1-11 available via /dev/wlan0\n')
	return true
}

fn protocol_event(_ voidptr, endpoint u8, packet Blob) {
	if endpoint == card_protocol.wmi {
		card_wmi.receive(mut card_protocol, packet)
	} else if endpoint == card_protocol.htt {
		card_tx_lock.acquire()
		card_htt.receive(mut card_protocol, packet)
		card_tx_lock.release()
	}
}

fn management_input(_ voidptr, frame Blob) { card_station.management(frame) }

fn ethernet_input(_ voidptr, frame Blob) {
	// HTT invokes this under TX. Never hold TX while entering lwIP: its
	// synchronous reply invokes send(), which takes TX again.
	if be16(frame, 12) == 0x888e {
		card_station.input(frame, devcore.now_ns())
		return
	}
	if card_station.state != .connected { return }
	card_tx_lock.release()
	_ = inet.receive_owned(inet.driver_ath10k, voidptr(frame.data), frame.len)
	card_tx_lock.acquire()
}

pub fn poll() {
	if card_gate == unsafe { nil } || !card_rx_lock.test_and_acquire() { return }
	defer { card_rx_lock.release() }
	if !card_active { return }
	card_protocol.poll()
	card_tx_lock.acquire()
	card_station.tick(mut card_protocol, mut card_wmi, mut card_htt)
	connected := card_station.state == .connected && card_htt.peer_mapped && !card_protocol.transport.fault
	card_htt.secure = card_station.network.secure
	card_tx_lock.release()
	if card_wmi.scanning && devcore.now_ns() >= card_wmi.scan_deadline {
		card_wmi.scanning = false
		card_wmi.scan_error = -110
		// A missing completion leaves the target's scan state unknown. Fence
		// the transport; a subsequent boot is required before another scan.
		card_protocol.transport.fault = true
	}
	if connected != card_link {
		card_link = connected
		if connected {
			if inet.attach(unsafe { &card_wmi.mac }, inet.driver_ath10k) {
				inet.set_link(inet.driver_ath10k, true)
				print('ath10k: station authorized; DHCP requested\n')
			} else {
				card_station.fail(-12)
				card_link = false
			}
		} else {
			inet.detach_owned(inet.driver_ath10k)
			C.kprintf(c'ath10k: station disconnected, error %d\n', card_station.error)
		}
	}
	if card_protocol.transport.fault {
		card_active = false
		card_error = -5
		print('ath10k: transport fault; DMA buffers retained until reset, see /proc/bootlog\n')
	}
}

@[export: 'vinix_ath10k_send']
pub fn send(frame voidptr, length u64) i32 {
	card_tx_lock.acquire()
	defer { card_tx_lock.release() }
	if !card_active || card_station.state != .connected || card_protocol.transport.fault {
		return -100
	}
	if length < 14 || length > 1518 { return -22 }
	card_htt.transmit(mut card_protocol, Blob{ data: unsafe { &u8(frame) }, len: u32(length) }, false,
		card_station.network.secure) or { return -11 }
	return 0
}

fn card_shutdown(mut dev devcore.Device) {
	acpisync.acquire(card_gate, 0xffff)
	fence()
	stop(mut dev)
	acpisync.signal(card_gate)
}

fn card_suspend(mut dev devcore.Device) bool {
	card_shutdown(mut dev)
	return true
}

fn card_resume(mut dev devcore.Device) bool {
	acpisync.acquire(card_gate, 0xffff)
	defer { acpisync.signal(card_gate) }
	if !card_radio { return true }
	if !start(mut dev) {
		stop(mut dev)
		return false
	}
	return true
}

fn card_remove(mut dev devcore.Device) {
	acpisync.acquire(card_gate, 0xffff)
	defer { acpisync.signal(card_gate) }
	fence()
	stop(mut dev)
	_ = fs.devtmpfs_remove_device('wlan0', card_box)
	dma.free_buffer(mut dev, card_pool)
	card_pool = dma.Buffer{}
	release_images()
	card_device = unsafe { nil }
	card_error = -19
}

struct WifiDevice {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut d WifiDevice) read(_ voidptr, _ voidptr, _ u64, _ u64) ?i64 {
	errno.set(errno.enotsup)
	return none
}

fn (mut d WifiDevice) write(_ voidptr, _ voidptr, _ u64, _ u64) ?i64 {
	errno.set(errno.enotsup)
	return none
}

fn (mut d WifiDevice) grow(_ voidptr, _ u64) ? {
	errno.set(errno.eperm)
	return none
}

fn (mut d WifiDevice) mmap(_ voidptr, _ u64, _ int) voidptr { return unsafe { nil } }

fn (mut d WifiDevice) unref(_ voidptr) ? { katomic.dec(mut &d.refcount) }

fn (mut d WifiDevice) link(_ voidptr) ? { katomic.inc(mut &d.stat.nlink) }

fn (mut d WifiDevice) unlink(_ voidptr) ? { katomic.dec(mut &d.stat.nlink) }

fn (mut d WifiDevice) ioctl(handle voidptr, request u64, arg voidptr) ?int {
	acpisync.acquire(card_gate, 0xffff)
	defer { acpisync.signal(card_gate) }
	if card_device == unsafe { nil } {
		errno.set(errno.enodev)
		return none
	}
	mut result := 0
	match request {
		0x5700 {
			mut data := [256]u8{}
			card_rx_lock.acquire()
			put32(unsafe { &data[0] }, 0, status_state(card_active, card_radio, card_stage, card_error, card_station.state))
			put32(unsafe { &data[0] }, 4, u32(if card_error != 0 { card_error } else if card_active { card_station.error } else { 0 }))
			put32(unsafe { &data[0] }, 8, 0x9377)
			put32(unsafe { &data[0] }, 12, card_stage)
			for i in 0 .. 6 { data[32 + i] = card_wmi.mac[i] }
			put32(unsafe { &data[0] }, 160, if card_radio { u32(1) } else { u32(0) })
			put32(unsafe { &data[0] }, 164, if card_wmi.scanning { u32(1) } else { u32(0) })
			put32(unsafe { &data[0] }, 168, u32(card_wmi.network_count))
			put32(unsafe { &data[0] }, 172, u32(card_wmi.scan_error))
			put32(unsafe { &data[0] }, 176, u32(card_station.state))
			put32(unsafe { &data[0] }, 180, if card_link { u32(1) } else { u32(0) })
			put32(unsafe { &data[0] }, 184, u32(card_htt.tx_queued))
			put32(unsafe { &data[0] }, 188, u32(card_htt.tx_completed))
			put32(unsafe { &data[0] }, 192, u32(card_htt.rx_packets))
			put32(unsafe { &data[0] }, 196, u32(card_htt.rx_dropped))
			put32(unsafe { &data[0] }, 200, u32(card_station.error))
			card_rx_lock.release()
			if !usercopy.copy_to_user(u64(arg), unsafe { &data[0] }, 256) { result = -14 }
		}
		0x5702 {
			card_radio = true
			mut dev := card_device
			if !start(mut dev) {
				stop(mut dev)
				result = card_error
			}
		}
		0x5703 { result = join(arg) }
		0x5704 {
			fence()
			mut dev := card_device
			stop(mut dev)
			card_radio = false
		}
		0x5705 {
			mut data := [4]u8{}
			if !usercopy.copy_from_user(unsafe { &data[0] }, u64(arg), 4) {
				result = -14
			} else if fixture_radio(Blob{ data: unsafe { &data[0] }, len: 4 }) == none {
				result = -22
			} else {
				card_radio = data[0] == 1
				mut dev := card_device
				if card_radio {
					if !card_active && !start(mut dev) {
						stop(mut dev)
						result = card_error
					}
				} else {
					fence()
					stop(mut dev)
				}
			}
		}
		0x5706 {
			card_rx_lock.acquire()
			card_tx_lock.acquire()
			if !card_active || !card_radio || card_protocol.transport.fault {
				result = -100
			} else if card_station.state != .idle && card_station.state != .failed {
				result = -16
			} else if !card_wmi.scan(mut card_protocol) {
				result = -11
			}
			card_tx_lock.release()
			card_rx_lock.release()
		}
		0x5707 {
			mut data := [1552]u8{}
			card_rx_lock.acquire()
			card_wmi.pack_networks(unsafe { &data[0] })
			card_rx_lock.release()
			if !usercopy.copy_to_user(u64(arg), unsafe { &data[0] }, 1552) { result = -14 }
		}
		else { return resource.default_ioctl(handle, request, arg) }
	}
	if result < 0 {
		errno.set(u64(-result))
		return none
	}
	return 0
}

fn fixture_radio(data Blob) ?bool {
	value := data.word(0)
	if value > 1 { return none }
	return value == 1
}

fn join(arg voidptr) int {
	mut data := [104]u8{}
	mut pmk := [32]u8{}
	mut nonce := [32]u8{}
	defer {
		erase(unsafe { &data[0] }, 104)
		erase(unsafe { &pmk }, 32)
		erase(unsafe { &nonce }, 32)
	}
	if !usercopy.copy_from_user(unsafe { &data[0] }, u64(arg), 104) { return -14 }
	b := Blob{ data: unsafe { &data[0] }, len: 104 }
	ssid_len := b.word(0)
	pass_len := b.word(4)
	if ssid_len == 0 || ssid_len > 32 || pass_len > 63 || (pass_len != 0 && pass_len < 8) {
		return -22
	}
	card_rx_lock.acquire()
	mut network := Network{}
	mut found := false
	if card_active && card_radio && !card_wmi.scanning {
		for i in 0 .. card_wmi.network_count {
			n := card_wmi.networks[i]
			if n.ssid_len == ssid_len && equal_bytes(unsafe { &n.ssid[0] }, unsafe { &data[8] }, ssid_len)
				&& card_wmi.channel_allowed(n.channel) && (!found || n.rssi > network.rssi) {
				network = n
				found = true
			}
		}
	}
	card_rx_lock.release()
	if !found { return -2 }
	if network.secure != (pass_len != 0) { return -22 }
	if network.secure {
		if !rsn_supported(Blob{ data: unsafe { &network.rsn[0] }, len: network.rsn_len }) {
			return -95
		}
		pmk = derive_pmk(b.view(40, pass_len), b.view(8, ssid_len)) or { return -22 }
		if !krandom.fill(unsafe { &nonce[0] }, 32, false) { return -11 }
	}
	// A clean target restart removes previous peers/keys and outstanding DMA
	// before reusing their slots. Credentials are not retained across resets.
	mut dev := card_device
	if !start(mut dev) {
		stop(mut dev)
		return card_error
	}
	card_rx_lock.acquire()
	card_tx_lock.acquire()
	card_htt.secure = network.secure
	started := card_station.begin(mut card_protocol, mut card_wmi, unsafe { &network }, unsafe { &pmk }, unsafe { &nonce })
	card_tx_lock.release()
	card_rx_lock.release()
	return if started { 0 } else { -5 }
}
