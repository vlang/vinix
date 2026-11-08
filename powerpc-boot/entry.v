// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

// IEEE 1275 PowerPC client interface: every cell is exactly 32 bits.
struct Call {
mut:
	service &char
	nargs   u32
	nret    u32
	cells   [12]u32
}

type Client = fn (&Call) int

__global firmware Client
__global stdout_handle u32

fn find_device(path &char) u32 {
	mut call := Call{ service: c'finddevice', nargs: 1, nret: 1 }
	call.cells[0] = u32(path)
	if firmware(unsafe { &call }) != 0 { return 0xffffffff }
	return call.cells[1]
}

fn get_property(node u32, name &char, buffer voidptr, size u32) int {
	mut call := Call{ service: c'getprop', nargs: 4, nret: 1 }
	call.cells[0] = node
	call.cells[1] = u32(name)
	call.cells[2] = u32(buffer)
	call.cells[3] = size
	if firmware(unsafe { &call }) != 0 { return -1 }
	return int(call.cells[4])
}

fn puts(text &char) {
	mut size := u32(0)
	unsafe { for text[size] != 0 { size++ }
	 }
	mut done := u32(0)
	for done < size {
		mut call := Call{ service: c'write', nargs: 3, nret: 1 }
		call.cells[0] = stdout_handle
		call.cells[1] = u32(text) + done
		call.cells[2] = size - done
		if firmware(unsafe { &call }) != 0 { return }
		written := int(call.cells[3])
		if written <= 0 || u32(written) > size - done { return }
		done += u32(written)
	}
}

// Open Firmware supplies a stack and the client entry in r5. Stay on that
// stack until the loader has claimed its own memory and copied the tree.
@[export: 'vinix_of_entry']
fn entry(_ u32, _ u32, client Client) {
	firmware = client
	chosen := find_device(c'/chosen')
	if chosen == 0xffffffff { return }
	if get_property(chosen, c'stdout', &stdout_handle, 4) != 4 { return }
	puts(c'VINIX-PPC: V Open Firmware entry\r\n')
	if sizeof(voidptr) != 4 || sizeof(Call) != 60 {
		puts(c'VINIX-PPC: FAIL ABI\r\n')
		return
	}
	mut endian := u32(0x01020304)
	if unsafe { *(&u8(&endian)) } != 1 {
		puts(c'VINIX-PPC: FAIL byte order\r\n')
		return
	}
	puts(c'VINIX-PPC: PASS ppc32 big-endian firmware\r\n')
	if !discover() { puts(c'VINIX-PPC: FAIL firmware discovery\r\n') }
}
