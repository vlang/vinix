// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A polled driver for Intel's 8254x gigabit Ethernet family (e1000).
//
// It is the network card every PC hypervisor offers: QEMU's `-nic
// model=e1000` is an 82540EM, and VirtualBox's three Intel adapters are the
// 82540EM, 82543GC and 82545EM, on its x86 and its arm64 machines alike. They
// share one register set, and so does the 82574L (QEMU's e1000e, the q35
// default) as long as it is driven with the legacy descriptors used here.
//
// The driver is the same on both architectures: it finds the card through the
// PCI layer and only maps its registers and orders its memory accesses
// through the per-architecture helpers in e1000_amd64.v and e1000_arm64.v.
// Like the VirtIO network driver it takes no interrupts. The card's are
// masked, and the scheduler's device poll drains the receive ring into the IP
// stack.
//
// Locking: the transmit ring is only touched from send(), which lwIP calls
// with the stack's lock held. The receive ring has a try-lock of its own, so
// a CPU which finds another one draining it goes on with its own work.
@[has_globals]
module e1000

import devcore
import dma
import klock
import socket.inet

// Registers, as offsets into BAR 0.
const reg_ctrl = u64(0x0000)
const reg_status = u64(0x0008)
const reg_eerd = u64(0x0014)
const reg_icr = u64(0x00c0)
const reg_imc = u64(0x00d8)
const reg_rctl = u64(0x0100)
const reg_tctl = u64(0x0400)
const reg_tipg = u64(0x0410)
const reg_rdbal = u64(0x2800)
const reg_rdbah = u64(0x2804)
const reg_rdlen = u64(0x2808)
const reg_rdh = u64(0x2810)
const reg_rdt = u64(0x2818)
const reg_tdbal = u64(0x3800)
const reg_tdbah = u64(0x3804)
const reg_tdlen = u64(0x3808)
const reg_tdh = u64(0x3810)
const reg_tdt = u64(0x3818)
const reg_mta = u64(0x5200)
const reg_ral0 = u64(0x5400)
const reg_rah0 = u64(0x5404)

// The registers the driver uses fit well inside this; a BAR that reports a
// smaller size than the register file is not believed.
const min_register_span = u64(0x20000)

const ctrl_lrst = u32(1) << 3
const ctrl_asde = u32(1) << 5
const ctrl_slu = u32(1) << 6
const ctrl_ilos = u32(1) << 7
const ctrl_rst = u32(1) << 26
const ctrl_vme = u32(1) << 30
const ctrl_phy_rst = u32(1) << 31

const status_lu = u32(1) << 1

// Receive: enabled, broadcasts/multicast accepted, the CRC stripped. IPv6
// discovery and IGMP/MLD need multicast reception; group policy is enforced
// by the native stack and socket memberships until a hardware hash filter
// callback is available. BSIZE is left at
// zero with BSEX clear, which is 2048-byte buffers, and long packets are off,
// so every frame fits one buffer.
const rctl_en = u32(1) << 1
// IPv6 neighbor discovery and router advertisements use multicast MACs.
const rctl_mpe = u32(1) << 4
const rctl_bam = u32(1) << 15
const rctl_secrc = u32(1) << 26

// Transmit: enabled, short frames padded, and the collision parameters the
// manual gives for full duplex.
const tctl_en = u32(1) << 1
const tctl_psp = u32(1) << 3
const tctl_ct = u32(0x0f) << 4
const tctl_cold = u32(0x40) << 12
const tctl_rtlc = u32(1) << 24
const tipg_copper = u32(10) | (u32(8) << 10) | (u32(6) << 20)

const rah_av = u32(1) << 31

// Descriptor bits.
const desc_dd = u32(1)
const rx_eop = u32(1) << 1
// CRC, symbol, sequence, carrier-extension and receive-data errors. The
// checksum error bits are only reported with checksum offload, which is off.
const rx_error_mask = u32(0x97)
const tx_cmd_eop = u32(1)
const tx_cmd_ifcs = u32(1) << 1
const tx_cmd_rs = u32(1) << 3

const rx_descriptors = u32(128)
const tx_descriptors = u32(64)
const descriptor_bytes = u64(16)
const frame_buffer_bytes = u64(2048)

// How long to wait on a register before deciding the card is not going to
// answer. A reset or an EEPROM read is done in well under a millisecond.
const register_timeout_ns = 200 * devcore.millisecond
// How long a full transmit ring may stay full. The card drains 63 frames in
// microseconds when it is working.
const tx_full_timeout_ns = 100 * devcore.millisecond

// The cards this drives, all Intel's. The 82574L reports EEPROM reads with the
// later layout of EERD.
const intel_vendor = u16(0x8086)
const id_82540em = u16(0x100e)
const id_82543gc = u16(0x1004)
const id_82544gc = u16(0x100c)
const id_82545em = u16(0x100f)
const id_82574l = u16(0x10d3)
const supported_ids = [id_82540em, id_82545em, id_82543gc, id_82544gc, id_82574l]!

__global (
	e1000_ready        bool
	e1000_regs         u64
	e1000_new_eerd     bool
	e1000_mac          [6]u8
	e1000_rx_ring      u64
	e1000_rx_buffers   u64
	e1000_rx_next      u32
	e1000_rx_discard   bool
	e1000_rx_lock      klock.Lock
	e1000_tx_ring      u64
	e1000_tx_buffers   u64
	e1000_tx_next      u32
	e1000_tx_clean     u32
	e1000_tx_in_flight u32
	e1000_tx_lock      klock.Lock
	// Where the card finds the rings and buffers, kept so that a resume or a
	// reset can tell it again, and the memory itself, to give back on removal.
	e1000_rx_ring_dma    dma.Buffer
	e1000_rx_buffers_dma dma.Buffer
	e1000_tx_ring_dma    dma.Buffer
	e1000_tx_buffers_dma dma.Buffer
	// The card this driver has. It drives one: the IP stack has one interface.
	e1000_device &devcore.Device
)

fn model_name(device_id u16) string {
	return match device_id {
		id_82540em { '82540EM' }
		id_82543gc { '82543GC' }
		id_82544gc { '82544GC' }
		id_82545em { '82545EM' }
		id_82574l { '82574L' }
		else { 'unknown' }
	}
}

fn eeprom_done(context voidptr) bool {
	done := if e1000_new_eerd { u32(1) << 1 } else { u32(1) << 4 }
	return reg_read(reg_eerd) & done != 0
}

// Read one 16-bit word of the EEPROM through EERD.
fn eeprom_read(word u32) ?u16 {
	start := if e1000_new_eerd { (word << 2) | 1 } else { (word << 8) | 1 }
	reg_write(reg_eerd, start)
	if !devcore.spin_until(eeprom_done, unsafe { nil }, register_timeout_ns) {
		return none
	}
	return u16(reg_read(reg_eerd) >> 16)
}

// The station address. QEMU and VirtualBox both load receive address 0 from
// the EEPROM, the way real hardware does, so it is normally already there;
// failing that, the EEPROM itself is asked.
fn read_mac() bool {
	ral := reg_read(reg_ral0)
	rah := reg_read(reg_rah0)
	if ral != 0 || rah & 0xffff != 0 {
		for i := 0; i < 4; i++ {
			e1000_mac[i] = u8(ral >> (8 * i))
		}
		e1000_mac[4] = u8(rah)
		e1000_mac[5] = u8(rah >> 8)
		return true
	}
	for i := u32(0); i < 3; i++ {
		word := eeprom_read(i) or { return false }
		e1000_mac[i * 2] = u8(word)
		e1000_mac[i * 2 + 1] = u8(word >> 8)
	}
	return true
}

// A card that has left the bus reads as all ones, reset bit included, so this
// is also how a pulled card is told from one that is merely slow.
fn reset_done(context voidptr) bool {
	ctrl := reg_read(reg_ctrl)
	return ctrl != 0xffffffff && ctrl & ctrl_rst == 0
}

fn card_matches(dev &devcore.Device) bool {
	if dev.bus != .pci || dev.vendor != intel_vendor {
		return false
	}
	for id in supported_ids {
		if dev.device == id {
			return true
		}
	}
	return false
}

// Register with the device core, which hands over a supported card if the
// machine has one. Returns whether the driver ended up with a working card.
pub fn initialise() bool {
	devcore.register_driver(devcore.Driver{
		name:     'e1000'
		bus:      .pci
		matches:  card_matches
		probe:    card_probe
		remove:   card_remove
		suspend:  card_suspend
		resume:   card_resume
		shutdown: card_shutdown
		reset:    card_reset
	}) or { return e1000_ready }
	return e1000_ready
}

// Whether a card is up and attached to the IP stack.
pub fn ready() bool {
	return e1000_ready
}

// Take a card and bring it up. False if another driver already owns the IP
// stack's one interface, or the card cannot be made to work.
fn card_probe(mut dev devcore.Device) bool {
	if e1000_device != unsafe { nil } {
		// One interface: a second card stays unbound rather than half driven.
		return false
	}
	mut card := dev.pci
	name := model_name(card.device_id)

	mut other_mac := [6]u8{}
	mut other_mtu := u32(0)
	if inet.link_info(unsafe { &other_mac }, unsafe { &other_mtu }) {
		C.kprintf(c'e1000: %.*s left alone: another network interface is attached\n',
			i32(name.len), name.str)
		return false
	}

	// Size the BAR with decoding off, so that the all-ones probe never lands
	// on top of something else, then turn on memory decoding and bus
	// mastering. The legacy interrupt stays off: this driver polls.
	command := card.read[u16](0x4)
	card.write[u16](0x4, command & ~u16(0x7))
	bar := card.get_bar(0)
	card.write[u16](0x4, (command & ~u16(1)) | 0x6 | (u16(1) << 10))
	if !bar.is_mmio || bar.base == 0 {
		C.kprintf(c'e1000: %.*s has no memory BAR\n', i32(name.len), name.str)
		return false
	}
	span := if bar.size >= min_register_span { bar.size } else { min_register_span }
	e1000_regs = map_registers(bar.base, span)
	if e1000_regs == 0 {
		C.kprintf(c'e1000: could not map registers at 0x%llx\n', u64(bar.base))
		return false
	}
	e1000_new_eerd = card.device_id == id_82574l

	if !allocate_rings(mut dev) {
		print('e1000: out of memory for descriptor rings\n')
		free_rings(mut dev)
		return false
	}
	if !hardware_start(true) {
		C.kprintf(c'e1000: %.*s did not come out of reset\n', i32(name.len), name.str)
		free_rings(mut dev)
		return false
	}

	link := if reg_read(reg_status) & status_lu != 0 { 'up' } else { 'down' }
	C.kprintf(c'e1000: %.*s at %llx:%llx.%llx, MAC %02llx:%02llx:%02llx:%02llx:%02llx:%02llx, link %.*s\n',
		i32(name.len), name.str, u64(card.bus), u64(card.slot), u64(card.function),
		u64(e1000_mac[0]), u64(e1000_mac[1]), u64(e1000_mac[2]), u64(e1000_mac[3]),
		u64(e1000_mac[4]), u64(e1000_mac[5]), i32(link.len), link.str)

	// Transmit has to work before attaching: DHCP sends its discover from
	// inside attach().
	e1000_device = unsafe { dev }
	e1000_ready = true
	if !inet.attach(&e1000_mac, inet.driver_e1000) {
		hardware_stop()
		free_rings(mut dev)
		e1000_device = unsafe { nil }
		print('e1000: IP stack attach failed\n')
		return false
	}
	// A frame arriving is what ends a sleep for a machine waiting on the
	// network; whether it may is the administrator's choice, off by default.
	dev.wakeup_capable = true
	print('e1000: ready, DHCP requested\n')
	return true
}

// Reset the card and program it from what the driver keeps: the station
// address, and the rings where they already are. `first` reads the address
// out of the card instead. Used to start it, to resume it and to reset it.
fn hardware_start(first bool) bool {
	// Quiet the card and reset it. Firmware may have left it running: a
	// network boot ROM, for one, does. The mask is written again after the
	// reset, as Linux does, and reading ICR drops anything already latched.
	reg_write(reg_imc, 0xffffffff)
	reg_write(reg_rctl, 0)
	reg_write(reg_tctl, 0)
	reg_write(reg_ctrl, reg_read(reg_ctrl) | ctrl_rst)
	if !devcore.spin_until(reset_done, unsafe { nil }, register_timeout_ns) {
		return false
	}
	reg_write(reg_imc, 0xffffffff)
	_ := reg_read(reg_icr)

	mut ctrl := reg_read(reg_ctrl)
	ctrl |= ctrl_slu | ctrl_asde
	ctrl &= ~(ctrl_lrst | ctrl_ilos | ctrl_phy_rst | ctrl_vme)
	reg_write(reg_ctrl, ctrl)

	if first && !read_mac() {
		// Locally administered, so it cannot clash with a real card.
		e1000_mac = [u8(0x52), 0x54, 0x00, 0x12, 0x34, 0x57]!
		print('e1000: no station address in the card or its EEPROM; using a made-up one\n')
	}
	reg_write(reg_ral0, u32(e1000_mac[0]) | (u32(e1000_mac[1]) << 8) | (u32(e1000_mac[2]) << 16) | (u32(e1000_mac[3]) << 24))
	reg_write(reg_rah0, u32(e1000_mac[4]) | (u32(e1000_mac[5]) << 8) | rah_av)
	for i := u64(0); i < 128; i++ {
		reg_write(reg_mta + i * 4, 0)
	}
	start_rx()
	start_tx()
	return true
}

// Stop the card touching memory: nothing received, nothing sent, no
// interrupt. Callers have already made sure no CPU is inside poll() or
// send().
fn hardware_stop() {
	reg_write(reg_imc, 0xffffffff)
	reg_write(reg_rctl, 0)
	reg_write(reg_tctl, 0)
	_ := reg_read(reg_icr)
}

// Keep poll() and send() out, and wait for a CPU already inside either.
fn fence() {
	e1000_ready = false
	e1000_rx_lock.acquire()
	e1000_rx_lock.release()
	e1000_tx_lock.acquire()
	e1000_tx_lock.release()
}

fn allocate_rings(mut dev devcore.Device) bool {
	e1000_rx_ring_dma = dma.alloc_buffer(mut dev, u64(rx_descriptors) * descriptor_bytes) or { return false }
	e1000_rx_buffers_dma = dma.alloc_buffer(mut dev, u64(rx_descriptors) * frame_buffer_bytes) or {
		return false
	}
	e1000_tx_ring_dma = dma.alloc_buffer(mut dev, u64(tx_descriptors) * descriptor_bytes) or { return false }
	e1000_tx_buffers_dma = dma.alloc_buffer(mut dev, u64(tx_descriptors) * frame_buffer_bytes) or {
		return false
	}
	e1000_rx_ring = e1000_rx_ring_dma.virt
	e1000_rx_buffers = e1000_rx_buffers_dma.virt
	e1000_tx_ring = e1000_tx_ring_dma.virt
	e1000_tx_buffers = e1000_tx_buffers_dma.virt
	return true
}

fn free_rings(mut dev devcore.Device) {
	dma.free_buffer(mut dev, e1000_rx_ring_dma)
	dma.free_buffer(mut dev, e1000_rx_buffers_dma)
	dma.free_buffer(mut dev, e1000_tx_ring_dma)
	dma.free_buffer(mut dev, e1000_tx_buffers_dma)
	e1000_rx_ring_dma = dma.Buffer{}
	e1000_rx_buffers_dma = dma.Buffer{}
	e1000_tx_ring_dma = dma.Buffer{}
	e1000_tx_buffers_dma = dma.Buffer{}
	e1000_rx_ring = 0
	e1000_rx_buffers = 0
	e1000_tx_ring = 0
	e1000_tx_buffers = 0
}

// Point every receive descriptor at its buffer, hand all but one to the card
// and turn reception on. Anything a previous run left in the ring is dropped.
fn start_rx() {
	ring := e1000_rx_ring_dma
	buffers := e1000_rx_buffers_dma
	for i := u64(0); i < u64(rx_descriptors); i++ {
		unsafe {
			*&u64(ring.virt + i * descriptor_bytes) = buffers.bus + i * frame_buffer_bytes
			*&u64(ring.virt + i * descriptor_bytes + 8) = 0
		}
	}
	e1000_rx_next = 0
	e1000_rx_discard = false
	dma_barrier()
	reg_write(reg_rdbal, u32(ring.bus))
	reg_write(reg_rdbah, u32(ring.bus >> 32))
	reg_write(reg_rdlen, rx_descriptors * u32(descriptor_bytes))
	reg_write(reg_rdh, 0)
	// Every descriptor but one belongs to the card. The one at the tail is
	// ours; head reaching it means the ring is full, not empty.
	reg_write(reg_rdt, rx_descriptors - 1)
	reg_write(reg_rctl, rctl_en | rctl_mpe | rctl_bam | rctl_secrc)
}

fn start_tx() {
	ring := e1000_tx_ring_dma
	buffers := e1000_tx_buffers_dma
	for i := u64(0); i < u64(tx_descriptors); i++ {
		unsafe {
			*&u64(ring.virt + i * descriptor_bytes) = buffers.bus + i * frame_buffer_bytes
			*&u64(ring.virt + i * descriptor_bytes + 8) = 0
		}
	}
	e1000_tx_next = 0
	e1000_tx_clean = 0
	e1000_tx_in_flight = 0
	dma_barrier()
	reg_write(reg_tdbal, u32(ring.bus))
	reg_write(reg_tdbah, u32(ring.bus >> 32))
	reg_write(reg_tdlen, tx_descriptors * u32(descriptor_bytes))
	reg_write(reg_tdh, 0)
	reg_write(reg_tdt, 0)
	reg_write(reg_tipg, tipg_copper)
	reg_write(reg_tctl, tctl_en | tctl_psp | tctl_ct | tctl_cold | tctl_rtlc)
}

// ── What the device core asks for ───────────────────────────────────────────

// Give the card back: the IP stack loses its interface, the card is stopped
// and may no longer master the bus, and its memory is returned.
fn card_remove(mut dev devcore.Device) {
	fence()
	inet.detach()
	hardware_stop()
	dev.pci.update_command(1 << 2, 0)
	free_rings(mut dev)
	e1000_device = unsafe { nil }
	dev.wakeup_capable = false
	print('e1000: removed\n')
}

// Before power off or reset: stop DMA, and leave the card as quiet as
// firmware expects to find it.
fn card_shutdown(mut dev devcore.Device) {
	fence()
	hardware_stop()
	dev.pci.update_command(1 << 2, 0)
}

// For system sleep the card is stopped and everything else is kept: the
// stack stays attached, and frames sent meanwhile are refused as a full ring
// would refuse them.
fn card_suspend(mut dev devcore.Device) bool {
	fence()
	hardware_stop()
	return true
}

// Firmware may have reset the card while the machine slept, or cut its
// power: nothing in it is assumed to have survived.
fn card_resume(mut dev devcore.Device) bool {
	command := dev.pci.read[u16](0x4)
	dev.pci.write[u16](0x4, (command & ~u16(1)) | 0x6 | (u16(1) << 10))
	if !hardware_start(false) {
		return false
	}
	e1000_ready = true
	return true
}

// A card that stopped answering is reset in place. The stack keeps its
// interface and its address; what was in the rings is lost, which TCP
// recovers from.
fn card_reset(mut dev devcore.Device) bool {
	fence()
	if !hardware_start(false) {
		return false
	}
	e1000_ready = true
	return true
}

// Take back the descriptors the card has finished sending.
fn reclaim_tx() {
	for e1000_tx_in_flight > 0 {
		descriptor := e1000_tx_ring + u64(e1000_tx_clean) * descriptor_bytes
		if u32(unsafe { *&u8(descriptor + 12) }) & desc_dd == 0 {
			return
		}
		e1000_tx_clean = (e1000_tx_clean + 1) % tx_descriptors
		e1000_tx_in_flight--
	}
}

// Called by the C IP shim's Ethernet output callback, with the stack's lock
// held. Returns zero when the frame was queued and a negative value when it
// was not; lwIP treats that as a lost frame, which TCP recovers from.
@[export: 'vinix_e1000_send']
pub fn send(frame voidptr, length u64) int {
	if !e1000_ready || frame == unsafe { nil } || length == 0 || length > frame_buffer_bytes {
		return -1
	}
	// One descriptor always stays empty: a tail that caught up with the head
	// would tell the card the ring is empty. QEMU sends a frame before the
	// tail write returns, so the ring only fills where the send is
	// asynchronous; give such a card a moment to catch up.
	e1000_tx_lock.acquire()
	defer {
		e1000_tx_lock.release()
	}
	if !e1000_ready {
		return -1
	}
	reclaim_tx()
	if e1000_tx_in_flight >= tx_descriptors - 1 {
		full := devcore.deadline(tx_full_timeout_ns)
		for e1000_tx_in_flight >= tx_descriptors - 1 {
			if full.expired() {
				// The card has stopped taking frames: that is a failure to
				// report, not just a frame to drop.
				mut dev := e1000_device
				if dev != unsafe { nil } {
					devcore.report_timeout(mut dev, 'transmit ring full')
				}
				return -1
			}
			reclaim_tx()
		}
	}
	index := e1000_tx_next
	buffer := e1000_tx_buffers + u64(index) * frame_buffer_bytes
	descriptor := e1000_tx_ring + u64(index) * descriptor_bytes
	unsafe {
		C.memcpy(voidptr(buffer), frame, length)
		// Length, no checksum offload, and "end of packet, insert the FCS,
		// report status".
		*&u32(descriptor + 8) = u32(length) | ((tx_cmd_eop | tx_cmd_ifcs | tx_cmd_rs) << 24)
		*&u32(descriptor + 12) = 0
	}
	e1000_tx_in_flight++
	e1000_tx_next = (index + 1) % tx_descriptors
	dma_barrier()
	reg_write(reg_tdt, e1000_tx_next)
	return 0
}

fn rx_status(index u32) u32 {
	return u32(unsafe { *&u8(e1000_rx_ring + u64(index) * descriptor_bytes + 12) })
}

// Hand every frame the card has received to the IP stack and give the buffers
// back. Called from the scheduler's device poll, on any CPU.
pub fn poll() {
	if !e1000_ready {
		return
	}
	// The usual answer, and it costs one read of ordinary memory. It is only
	// a hint: the card may be on its way out on another CPU, so the ring is
	// read through a copy of its address, and nothing is believed until the
	// lock is held and the card is still there.
	ring := e1000_rx_ring
	if ring == 0 || u32(unsafe { *&u8(ring + u64(e1000_rx_next) * descriptor_bytes + 12) }) & desc_dd == 0 {
		return
	}
	if !e1000_rx_lock.test_and_acquire() {
		return
	}
	if !e1000_ready {
		e1000_rx_lock.release()
		return
	}
	mut last := u32(0)
	mut consumed := false
	for n := u32(0); n < rx_descriptors; n++ {
		index := e1000_rx_next
		descriptor := e1000_rx_ring + u64(index) * descriptor_bytes
		status := rx_status(index)
		if status & desc_dd == 0 {
			break
		}
		// Only now is the rest of the descriptor, and the frame, the card's
		// finished work.
		dma_barrier()
		length := u64(unsafe { *&u16(descriptor + 8) })
		errors := u32(unsafe { *&u8(descriptor + 13) })
		if status & rx_eop == 0 {
			// Part of a frame longer than a buffer. Long packets are off, so
			// this should not happen; drop the pieces if it does.
			e1000_rx_discard = true
		} else {
			if !e1000_rx_discard && errors & rx_error_mask == 0 && length >= 14 {
				inet.receive(voidptr(e1000_rx_buffers + u64(index) * frame_buffer_bytes),
					length)
			}
			e1000_rx_discard = false
		}
		unsafe {
			*&u32(descriptor + 12) = 0
		}
		last = index
		consumed = true
		e1000_rx_next = (index + 1) % rx_descriptors
	}
	if consumed {
		dma_barrier()
		reg_write(reg_rdt, last)
	}
	e1000_rx_lock.release()
}
