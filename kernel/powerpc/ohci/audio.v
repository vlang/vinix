// SPDX-License-Identifier: GPL-2.0-or-later
module ohci

import powerpc.cpu
import powerpc.mmio
import powerpc.pages
import powerpc.runtime
import powerpc.serial

__global audio_dma u32
__global audio_host u32
__global audio_port u32
__global audio_flags u32
__global audio_ready bool

// UAC1, fixed 48 kHz stereo signed 16-bit PCM, synchronous full-speed OUT.
// All descriptors are checked before configuration changes invalidate them.
fn discover_audio(mut host Controller, address u32, packet u32, port u32, length u32, mut pool pages.Pool) bool {
	if audio_ready { return false }
	data := unsafe { &u8(host.dma + 1024) }
	mut stream := false
	mut format := false
	mut pcm := false
	mut iface := u32(0)
	mut alternate := u32(0)
	mut endpoint := u32(0)
	mut maximum := u32(0)
	mut ac_interface := u32(0)
	mut control_interface := false
	mut mute_unit := u32(0)
	unsafe {
		for at := u32(9); at + 2 <= length; {
			size := u32(data[at])
			if size < 2 || size > length - at { return false }
			if data[at + 1] == 4 && size >= 9 {
				stream = data[at + 5] == 1 && data[at + 6] == 2 && data[at + 7] == 0 && data[at + 3] != 0
				control_interface = data[at + 5] == 1 && data[at + 6] == 1 && data[at + 7] == 0
				if control_interface { ac_interface = data[at + 2] }
				iface = data[at + 2]; alternate = data[at + 3]
				format = false; pcm = false
			}
			if control_interface && data[at + 1] == 0x24 && size >= 8 && data[at + 2] == 6
				&& data[at + 5] > 0 && data[at + 6] & 1 != 0 { mute_unit = data[at + 3] }
			if stream && data[at + 1] == 0x24 && size >= 7 && data[at + 2] == 1 {
				pcm = data[at + 5] == 1 && data[at + 6] == 0
			}
			if stream && data[at + 1] == 0x24 && size >= 11 && data[at + 2] == 2 {
				format = data[at + 3] == 1 && data[at + 4] == 2 && data[at + 5] == 2
					&& data[at + 6] == 16 && data[at + 7] == 1 && data[at + 8] == 0x80
					&& data[at + 9] == 0xbb && data[at + 10] == 0
			}
			if stream && format && pcm && data[at + 1] == 5 && size >= 9
				&& data[at + 2] & 0x80 == 0 && data[at + 3] & 15 == 13 && data[at + 6] == 1 {
				endpoint = data[at + 2] & 15
				maximum = u32(data[at + 4]) | u32(data[at + 5]) << 8
				break
			}
			at += size
		}
	}
	if endpoint == 0 || maximum != 192 { return false }
	serial.text(c'VINIX-PPC: USB audio profile found\n')
	configuration := unsafe { u32(data[5]) }
	if transfer(mut host, address, false, packet, 0x0900, configuration, 0, 0) < 0 { serial.text(c'USB audio: configuration failed\n'); return false }
	if mute_unit != 0 && transfer(mut host, address, false, packet, 0x0121, 0x0100, mute_unit << 8 | ac_interface, 1) < 0 { serial.text(c'USB audio: unmute failed\n'); return false }
	if transfer(mut host, address, false, packet, 0x0b01, alternate, iface, 0) < 0 { serial.text(c'USB audio: interface failed\n'); return false }
	audio_dma = pool.take(48, 1)
	if audio_dma == 0 { return false }
	runtime.fill(voidptr(audio_dma), 0, 48 * 4096)
	audio_flags = address | endpoint << 7 | 0x8800 | maximum << 16
	mmio.write32(audio_dma, audio_flags | 0x4000)
	mmio.write32(audio_dma + 4, audio_dma + 4032)
	mmio.write32(audio_dma + 8, audio_dma + 4032)
	mmio.publish(audio_dma, 48 * 4096)
	audio_host = controller_count
	audio_port = port
	audio_ready = true
	serial.text(c'VINIX-PPC: USB audio ready (48000 Hz stereo S16LE)\n')
	return true
}

pub fn sound_present() bool { return audio_ready }

// Caller validates/copies the complete user buffer before handing it to DMA.
pub fn sound_buffer() u32 { return if audio_ready { audio_dma + 4096 } else { u32(0) } }

pub fn sound_play(size u32) int {
	if !audio_ready { return -19 }
	if size == 0 || size > 192000 || size % 192 != 0 { return -22 }
	mut host := unsafe { &controllers[audio_host] }
	if mmio.read32(host.base + 0x54 + audio_port * 4) & 1 == 0 { audio_ready = false; return -19 }
	frames := size / 192
	count := (frames + 7) / 8
	first_frame := (mmio.read32(host.base + 0x3c) + 10) & 0xffff
	tail := audio_dma + 4032
	for i := u32(0); i < count; i++ {
		td_address := audio_dma + 32 + i * 32
		buffer := audio_dma + 4096 + i * 1536
		packets := if frames - i * 8 > 8 { u32(8) } else { frames - i * 8 }
		mmio.write32(td_address, 0xf0000000 | (packets - 1) << 24 | ((first_frame + i * 8) & 0xffff))
		mmio.write32(td_address + 4, buffer & ~u32(4095))
		mmio.write32(td_address + 8, if i + 1 == count { tail } else { td_address + 32 })
		mmio.write32(td_address + 12, buffer + packets * 192 - 1)
		for pair := u32(0); pair < 4; pair++ {
			low := 0xe000 | ((buffer & 4095) + pair * 384)
			high := 0xe000 | ((buffer & 4095) + pair * 384 + 192)
			mmio.write32(td_address + 16 + pair * 4, low | high << 16)
		}
	}
	mmio.publish(audio_dma + 32, count * 32)
	mmio.publish(audio_dma + 4096, size)
	mmio.write32(audio_dma + 4, tail)
	mmio.write32(audio_dma + 8, audio_dma + 32)
	mmio.write32(audio_dma, audio_flags)
	mmio.publish(audio_dma, 32)
	mmio.write32(host.base + 4, mmio.read32(host.base + 4) | 0x0c)
	deadline := cpu.timebase() + u64(frequency) * 2
	mut complete := false
	for cpu.timebase() < deadline {
		poll() // keep HID responsive while the fixed isochronous list plays
		mmio.acquire(audio_dma, 32)
		if mmio.read32(audio_dma + 8) & 0xfffffff0 == tail { complete = true; break }
	}
	// Quiesce isochronous traversal before modifying the ED or reusing PCM.
	mmio.write32(host.base + 4, mmio.read32(host.base + 4) & ~u32(8))
	delay(2)
	mmio.acquire(audio_dma, 32)
	mmio.write32(audio_dma, audio_flags | 0x4000)
	mmio.publish(audio_dma, 32)
	if !complete { audio_ready = false; return -110 }
	mmio.acquire(audio_dma + 32, count * 32)
	for i := u32(0); i < count; i++ {
		td_address := audio_dma + 32 + i * 32
		if mmio.read32(td_address) >> 28 != 0 { return -5 }
		packets := if frames - i * 8 > 8 { u32(8) } else { frames - i * 8 }
		for j := u32(0); j < packets; j++ {
			status := mmio.read32(td_address + 16 + (j / 2) * 4) >> ((j & 1) * 16)
			if status & 0xf000 != 0 { return -5 }
		}
	}
	return int(size)
}
