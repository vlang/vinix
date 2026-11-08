// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module ohci

import powerpc.boot
import powerpc.cpu
import powerpc.mmio
import powerpc.pages
import powerpc.pci
import powerpc.pointer
import powerpc.runtime
import powerpc.serial
import powerpc.video

struct Endpoint {
mut:
	address u32
	number u32
	packet u32
	kind u32
	port u32
	low bool
	active bool
	previous [6]u8
}

struct Controller {
mut:
	base u32
	dma u32
	ports u32
	count u32
	next_address u32
	endpoints [8]Endpoint
}

__global controllers [4]Controller
__global controller_count u32
__global frequency u32
__global keys [128]u8
__global key_read u32
__global key_write u32
__global caps_lock bool
__global pointer_state pointer.State

pub fn pointer_snapshot() pointer.Packet {
	poll()
	return pointer_state.take()
}

// Readiness never consumes key bytes or pointer edges. The syscall wait loop
// pumps poll() before testing these predicates.
pub fn key_pending() bool { return key_read != key_write }
pub fn pointer_pending() bool { return pointer_state.changed }

fn delay(ms u32) {
	end := cpu.timebase() + u64(frequency / 1000) * ms
	for cpu.timebase() < end {}
}

fn wait_clear(address u32, mask u32, ms u32) bool {
	end := cpu.timebase() + u64(frequency / 1000) * ms
	for cpu.timebase() < end {
		if mmio.read32(address) & mask == 0 { return true }
	}
	return false
}

fn td(address u32, flags u32, buffer u32, size u32, next u32) {
	mmio.write32(address, flags | 0xf0000000)
	mmio.write32(address + 4, if size == 0 { u32(0) } else { buffer })
	mmio.write32(address + 8, next)
	mmio.write32(address + 12, if size == 0 { u32(0) } else { buffer + size - 1 })
	mmio.publish(address, 32)
}

// One synchronous endpoint-zero transfer. DMA storage is fixed per host.
fn transfer(mut host Controller, address u32, low bool, packet u32, request u32, value u32, index u32, size u32) int {
	if size > 1024 { return -1 }
	base := host.dma
	ed := base + 256
	setup := base + 576
	buffer := base + 1024
	mmio.write32(setup, request | value << 16)
	mmio.write32(setup + 4, index | size << 16)
	mmio.publish(setup, 32)
	runtime.fill(voidptr(buffer), 0, 1024)
	mmio.publish(buffer, 1024)
	input := request & 0x80 != 0
	td(base + 320, 0x02000000, setup, 8, if size == 0 { base + 448 } else { base + 384 })
	if size != 0 { td(base + 384, 0x03040000 | if input { u32(0x100000) } else { u32(0x80000) }, buffer, size, base + 448) }
	td(base + 448, 0x03000000 | if input { u32(0x80000) } else { u32(0x100000) }, 0, 0, base + 512)
	mmio.write32(ed, address | packet << 16 | if low { u32(0x2000) } else { u32(0) })
	mmio.write32(ed + 4, base + 512)
	mmio.write32(ed + 8, base + 320)
	mmio.write32(ed + 12, 0)
	mmio.publish(ed, 32)
	mmio.write32(host.base + 0x20, ed)
	mmio.write32(host.base + 0x08, 2)
	deadline := cpu.timebase() + u64(frequency / 4)
	mut success := false
	for cpu.timebase() < deadline {
		mmio.acquire(ed, 32)
		head := mmio.read32(ed + 8)
		if head & 1 != 0 { break }
		if head & 0xfffffff0 == base + 512 { success = true; break }
	}
	// Stop the list before recycling any descriptor, including on timeout.
	mmio.write32(host.base + 4, mmio.read32(host.base + 4) & ~u32(0x10))
	// Let the host retire its private done head before these TDs are reused.
	mmio.write32(host.base + 0x0c, 2)
	delay(2)
	mmio.write32(host.base + 0x20, 0)
	mmio.write32(host.base + 0x24, 0)
	mmio.write32(host.base + 0x0c, 2)
	mmio.write32(host.base + 4, mmio.read32(host.base + 4) | 0x10)
	if !success { return -1 }
	mmio.acquire(base + 448, 32)
	if mmio.read32(base + 448) >> 28 != 0 { return -1 }
	if size == 0 { return 0 }
	mmio.acquire(base + 384, 32)
	mmio.acquire(buffer, 1024)
	if mmio.read32(base + 384) >> 28 != 0 { return -1 }
	remaining := mmio.read32(base + 388)
	if remaining == 0 { return int(size) }
	if remaining < buffer || remaining > buffer + size { return -1 }
	return int(remaining - buffer)
}

fn arm(mut host Controller, index u32) {
	ep := host.endpoints[index]
	ed := host.dma + 2048 + index * 256
	// Retain the toggle carry from the completed ED.
	carry := mmio.read32(ed + 8) & 2
	td(ed + 64, 0x00140000, ed + 192, ep.packet, ed + 128)
	mmio.write32(ed + 8, ed + 64 | carry)
	mmio.publish(ed, 32)
}

fn enumerate(mut host Controller, port u32, mut pool pages.Pool) {
	status := host.base + 0x54 + port * 4
	if mmio.read32(status) & 1 == 0 { return }
	mmio.write32(status, 0x10)
	if !wait_clear(status, 0x10, 100) { return }
	delay(10)
	flags := mmio.read32(status)
	if flags & 3 != 3 { return }
	low := flags & 0x200 != 0
	if !enumerate_device(mut host, port, low, 0, mut pool) {
		mmio.write32(status, 1) // isolate a device which may still answer at address zero
	}
}

fn enumerate_device(mut host Controller, port u32, low bool, depth u32, mut pool pages.Pool) bool {
	if host.next_address > 32 { return false }
	buffer := unsafe { &u8(host.dma + 1024) }
	if transfer(mut host, 0, low, 8, 0x0680, 0x0100, 0, 8) < 8 { return false }
	class := unsafe { u32(buffer[4]) }
	packet := unsafe { u32(buffer[7]) }
	if (packet != 8 && packet != 16 && packet != 32 && packet != 64) || (low && packet != 8) { return false }
	address := host.next_address
	if transfer(mut host, 0, low, packet, 0x0500, address, 0, 0) < 0 { return false }
	host.next_address++
	delay(2)
	configure_device(mut host, address, packet, class, port, low, depth, mut pool)
	return true
}

fn configure_device(mut host Controller, address u32, packet u32, class u32, port u32, low bool, depth u32, mut pool pages.Pool) {
	buffer := unsafe { &u8(host.dma + 1024) }
	if transfer(mut host, address, low, packet, 0x0680, 0x0200, 0, 9) < 9 { return }
	length := unsafe { u32(buffer[2]) | u32(buffer[3]) << 8 }
	if length < 9 || length > 1024 || transfer(mut host, address, low, packet, 0x0680, 0x0200, 0, length) != int(length) { return }
	configuration := unsafe { u32(buffer[5]) }
	if !low && class == 9 {
		enumerate_hub(mut host, address, packet, configuration, port, depth, mut pool)
		return
	}
	if !low && discover_audio(mut host, address, packet, port, length, mut pool) { return }
	mut kind := u32(0)
	mut interface_number := u32(0)
	mut endpoint := u32(0)
	mut maximum := u32(0)
	unsafe {
		for at := u32(9); at + 2 <= length; {
			size := u32(buffer[at])
			if size < 2 || size > length - at { return }
			if buffer[at + 1] == 4 && size >= 9 {
				kind = if buffer[at + 5] == 3 && buffer[at + 6] == 1 && buffer[at + 4] > 0 { u32(buffer[at + 7]) } else { u32(0) }
				interface_number = buffer[at + 2]
			}
			if buffer[at + 1] == 5 && size >= 7 && (kind == 1 || kind == 2)
				&& buffer[at + 2] & 0x80 != 0 && buffer[at + 3] & 3 == 3 {
				endpoint = buffer[at + 2] & 15
				maximum = u32(buffer[at + 4]) | u32(buffer[at + 5]) << 8
				break
			}
			at += size
		}
	}
	if endpoint == 0 || maximum < 3 || maximum > 64 || (kind == 1 && maximum < 8) || host.count == 8 { return }
	if transfer(mut host, address, low, packet, 0x0900, configuration, 0, 0) < 0 { return }
	if transfer(mut host, address, low, packet, 0x0b21, 0, interface_number, 0) < 0 { return } // boot protocol
	transfer(mut host, address, low, packet, 0x0a21, 0, interface_number, 0) // SET_IDLE, optional
	index := host.count
	host.endpoints[index] = Endpoint{address: address, number: endpoint, packet: if kind == 1 { u32(8) } else { u32(3) }, kind: kind, port: port, low: low, active: true}
	ed := host.dma + 2048 + index * 256
	mmio.write32(ed, address | endpoint << 7 | 0x1000 | maximum << 16 | if low { u32(0x2000) } else { u32(0) })
	mmio.write32(ed + 4, ed + 128)
	mmio.write32(ed + 12, if index == 0 { u32(0) } else { ed - 256 })
	arm(mut host, index)
	host.count++
	if kind == 2 {
		screen := video.info()
		pointer_state.attach(screen.width, screen.height)
	}
	serial.text(if kind == 1 { c'VINIX-PPC: USB keyboard ready\n' } else { c'VINIX-PPC: USB mouse ready\n' })
}

pub fn init(info &boot.Info, mut pool pages.Pool) {
	frequency = info.timebase_hz
	for i := u32(0); i < info.pci_count && i < 8; i++ {
		device := info.pci[i]
		if device.class != 0x0c0310 || device.size < 0x60 || controller_count == 4 || !pci.enable(unsafe { &device }) { continue }
		mut host := unsafe { &controllers[controller_count] }
		host.base = device.base
		host.next_address = 1
		if mmio.read32(host.base) & 255 != 0x10 { continue }
		mmio.write32(host.base + 0x14, 0xffffffff)
		mmio.write32(host.base + 4, 0)
		delay(50)
		mmio.write32(host.base + 8, 1)
		if !wait_clear(host.base + 8, 1, 100) { continue }
		host.dma = pool.take(1, 1)
		if host.dma == 0 { continue }
		runtime.fill(voidptr(host.dma), 0, 4096)
		mmio.publish(host.dma, 4096)
		host.ports = mmio.read32(host.base + 0x48) & 255
		if host.ports > 8 { host.ports = 8 }
		mmio.write32(host.base + 0x18, host.dma)
		mmio.write32(host.base + 0x34, 0x27782edf)
		mmio.write32(host.base + 0x40, 0x2a2f)
		mmio.write32(host.base + 0x44, 0x628)
		mmio.write32(host.base + 4, 0x90)
		mmio.write32(host.base + 0x50, 0x10000)
		for port := u32(0); port < host.ports; port++ { mmio.write32(host.base + 0x54 + port * 4, 0x100) }
		delay(200)
		for port := u32(0); port < host.ports; port++ { enumerate(mut host, port, mut pool) }
		if host.count > 0 || (audio_ready && audio_host == controller_count) {
			mut head := if host.count == 0 { u32(0) } else { host.dma + 2048 + (host.count - 1) * 256 }
			if audio_ready && audio_host == controller_count {
				mmio.write32(audio_dma + 12, head)
				mmio.publish(audio_dma, 32)
				head = audio_dma
			}
			for slot := u32(0); slot < 32; slot++ { mmio.write32(host.dma + slot * 4, head) }
			mmio.publish(host.dma, 128)
			mmio.write32(host.base + 4, 0x94)
		}
		controller_count++
	}
}

fn enqueue(byte u8) {
	if byte == 0 || key_write - key_read == 128 { return }
	keys[key_write & 127] = byte
	key_write++
}

fn keycode(code u8, modifiers u8) u8 {
	shift := modifiers & 0x22 != 0
	if code >= 4 && code <= 29 {
		letter := u8(`a`) + code - 4
		if modifiers & 0x11 != 0 { return letter - `a` + 1 }
		return if shift != caps_lock { letter - 32 } else { letter }
	}
	if code >= 30 && code <= 39 {
		plain := c'1234567890'
		upper := c'!@#$%^&*()'
		return unsafe { u8(if shift { upper[code - 30] } else { plain[code - 30] }) }
	}
	return match code {
		40 { u8(10) }
		42 { u8(8) }
		43 { u8(9) }
		44 { u8(32) }
		45 { u8(if shift { `_` } else { `-` }) }
		46 { u8(if shift { `+` } else { `=` }) }
		47 { u8(if shift { `{` } else { `[` }) }
		48 { u8(if shift { `}` } else { `]` }) }
		49 { u8(if shift { `|` } else { `\\` }) }
		51 { u8(if shift { `:` } else { `;` }) }
		52 { u8(if shift { `"` } else { `'` }) }
		53 { u8(if shift { 126 } else { 96 }) }
		54 { u8(if shift { `<` } else { `,` }) }
		55 { u8(if shift { `>` } else { `.` }) }
		56 { u8(if shift { `?` } else { `/` }) }
		else { u8(0) }
	}
}

pub fn poll() {
	for c := u32(0); c < controller_count; c++ {
		mut host := unsafe { &controllers[c] }
		for index := u32(0); index < host.count; index++ {
			mut ep := unsafe { &host.endpoints[index] }
			if !ep.active { continue }
			ed := host.dma + 2048 + index * 256
			mmio.acquire(ed, 32)
			head := mmio.read32(ed + 8)
			if head & 1 != 0 || mmio.read32(host.base + 0x54 + ep.port * 4) & 1 == 0 {
				ep.active = false
				mmio.write32(ed, mmio.read32(ed) | 0x4000)
				mmio.publish(ed, 32)
				continue
			}
			if head & 0xfffffff0 != ed + 128 { continue }
			mmio.acquire(ed + 64, 32)
			mmio.acquire(ed + 192, 64)
			// Rounding permits short USB transfers to complete without halting
			// the endpoint. Only a full boot report may consume the DMA bytes;
			// otherwise stale bytes could look like new keys or mouse motion.
			if mmio.read32(ed + 64) >> 28 == 0 && mmio.read32(ed + 68) == 0 {
				data := unsafe { &u8(ed + 192) }
				unsafe {
					if ep.kind == 1 {
						for j := u32(0); j < 6; j++ {
							code := data[j + 2]
							mut present := false
							for k := u32(0); k < 6; k++ { if ep.previous[k] == code { present = true } }
							if !present && code > 3 {
								if code == 57 { caps_lock = !caps_lock } else { enqueue(keycode(code, data[0])) }
							}
						}
						for j := u32(0); j < 6; j++ { ep.previous[j] = data[j + 2] }
					} else {
						pointer_state.move(i32(i8(data[1])), i32(i8(data[2])), data[0])
						video.pointer(int(i8(data[1])), int(i8(data[2])), data[0])
					}
				}
			}
			arm(mut host, index)
		}
		mmio.write32(host.base + 0x0c, 2)
	}
}

pub fn get() int {
	poll()
	if key_read == key_write { return -1 }
	byte := keys[key_read & 127]
	key_read++
	return int(byte)
}
