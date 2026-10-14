// SPDX-License-Identifier: GPL-2.0-or-later
module display

import encoding.binary
import net.unix

fn read_exact(mut connection unix.StreamConn, size int) ![]u8 {
	mut bytes := []u8{len: size}
	mut offset := 0
	for offset < size {
		count := connection.read(mut bytes[offset..])!
		if count == 0 { return error('X11 connection closed') }
		offset += count
	}
	return bytes
}

fn reply(mut connection unix.StreamConn) ![]u8 {
	for {
		mut packet := read_exact(mut connection, 32)!
		if packet[0] == 0 {
			return error('X11 error ${packet[1]} for request ${packet[10]}/${binary.little_endian_u16(packet[8..10])}')
		}
		if packet[0] != 1 { continue }
		size := int(binary.little_endian_u32(packet[4..8])) * 4
		if size < 0 || size > 1024 * 1024 { return error('invalid X11 reply size') }
		if size > 0 { packet << read_exact(mut connection, size)! }
		return packet
	}
}

fn request(opcode u8, minor u8, size int) []u8 {
	mut bytes := []u8{len: size}
	bytes[0] = opcode
	bytes[1] = minor
	binary.little_endian_put_u16(mut bytes[2..4], u16(size / 4))
	return bytes
}

fn resources(mut connection unix.StreamConn, opcode u8, root u32) ![]u8 {
	mut packet := request(opcode, 25, 8)
	binary.little_endian_put_u32(mut packet[4..8], root)
	connection.write(packet)!
	return reply(mut connection)
}

fn timed_mode(opcode u8, root u32, width u16, height u16) []u8 {
	name := 'vinix-60hz'
	mut packet := request(opcode, 16, 40 + ((name.len + 3) & ~3))
	binary.little_endian_put_u32(mut packet[4..8], root)
	binary.little_endian_put_u16(mut packet[12..14], width)
	binary.little_endian_put_u16(mut packet[14..16], height)
	binary.little_endian_put_u32(mut packet[16..20], u32(width) * u32(height) * 60)
	for offset in [20, 22, 24] {
		binary.little_endian_put_u16(mut packet[offset..offset + 2], width)
	}
	for offset in [28, 30, 32] {
		binary.little_endian_put_u16(mut packet[offset..offset + 2], height)
	}
	binary.little_endian_put_u16(mut packet[34..36], u16(name.len))
	copy(mut packet[40..], name.bytes())
	return packet
}

// Xvfb advertises its fixed geometry with zero dot-clock/totals. Zed 0.138
// divides those values to schedule rendering. Supply a 60 Hz RandR mode with
// the same framebuffer size; the Alpine executable remains unchanged.
pub fn ensure_refresh(display_name string) ! {
	if !display_name.starts_with(':') { return error('Zed requires its private local X11 display') }
	number := display_name[1..].all_before('.')
	if number.len == 0 || !number.bytes().all(it >= `0` && it <= `9`) {
		return error('invalid X11 display')
	}
	mut connection := unix.connect_stream('/tmp/.X11-unix/X${number}')!
	defer { connection.close() or {} }
	mut hello := []u8{len: 12}
	hello[0] = `l`
	binary.little_endian_put_u16(mut hello[2..4], 11)
	connection.write(hello)!
	header := read_exact(mut connection, 8)!
	if header[0] != 1 { return error('X11 refused the Zed display connection') }
	setup := read_exact(mut connection, int(binary.little_endian_u16(header[6..8])) * 4)!
	if setup.len < 32 || setup[20] != 1 {
		return error('Zed expects a single-screen private display')
	}
	root_offset := 32 + ((int(binary.little_endian_u16(setup[16..18])) + 3) & ~3) + int(setup[21]) * 8
	if root_offset + 40 > setup.len { return error('invalid X11 screen setup') }
	root := binary.little_endian_u32(setup[root_offset..root_offset + 4])
	width := binary.little_endian_u16(setup[root_offset + 20..root_offset + 22])
	height := binary.little_endian_u16(setup[root_offset + 22..root_offset + 24])
	mut query := request(98, 0, 16)
	binary.little_endian_put_u16(mut query[4..6], 5)
	copy(mut query[8..], 'RANDR'.bytes())
	connection.write(query)!
	extension := reply(mut connection)!
	if extension[8] != 1 { return error('RandR is required for Zed') }
	opcode := extension[9]
	initial := resources(mut connection, opcode, root)!
	ncrtcs := int(binary.little_endian_u16(initial[16..18]))
	noutputs := int(binary.little_endian_u16(initial[18..20]))
	if ncrtcs != 1 || noutputs != 1 || initial.len < 72 {
		return error('unexpected private RandR screen layout')
	}
	// Already configured displays need no mutation.
	if binary.little_endian_u32(initial[48..52]) != 0
		&& binary.little_endian_u16(initial[56..58]) != 0
		&& binary.little_endian_u16(initial[64..66]) != 0 {
		return
	}
	crtc := binary.little_endian_u32(initial[32..36])
	output := binary.little_endian_u32(initial[36..40])
	connection.write(timed_mode(opcode, root, width, height))!
	created := reply(mut connection)!
	mode := binary.little_endian_u32(created[8..12])
	mut add := request(opcode, 18, 12)
	binary.little_endian_put_u32(mut add[4..8], output)
	binary.little_endian_put_u32(mut add[8..12], mode)
	connection.write(add)!
	current := resources(mut connection, opcode, root)!
	mut configure := request(opcode, 21, 32)
	binary.little_endian_put_u32(mut configure[4..8], crtc)
	binary.little_endian_put_u32(mut configure[12..16], binary.little_endian_u32(current[12..16]))
	binary.little_endian_put_u32(mut configure[20..24], mode)
	binary.little_endian_put_u16(mut configure[24..26], 1)
	binary.little_endian_put_u32(mut configure[28..32], output)
	connection.write(configure)!
	configured := reply(mut connection)!
	if configured[1] != 0 { return error('X11 refused the 60 Hz private display mode') }
}
