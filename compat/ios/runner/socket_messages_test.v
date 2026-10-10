// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_darwin_message_macho_unload() {
	path := os.getenv('VINIX_IOS_MESSAGE_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
		assert system_data == unsafe { nil }
	}
}

fn test_darwin_message_linux_timestamp_layout() {
	// Independent native Linux cmsghdr/timeval bytes, including deliberately
	// unaligned input/output. The live Mac fixture covers Darwin native data.
	mut native := [33]u8{}
	base := usize(unsafe { &native[1] })
	message_store64(base, 32)
	message_store32(base + 8, 1)
	message_store32(base + 12, 29)
	message_store64(base + 16, 1700000000)
	message_store64(base + 24, 234567)
	for capacity in [usize(1), 11, 12, 13, 27, 28, 64] {
		mut output := [66]u8{}
		unsafe { C.memset(&output[0], 0x5a, sizeof(output)) }
		address := usize(unsafe { &output[1] })
		used, flags := message_control_receive(base, 32, address, capacity, true)
		expected := if capacity < 28 { capacity } else { usize(28) }
		assert used == expected
		assert flags == if capacity < 28 { i32(0x20) } else { i32(0) }
		assert output[0] == 0x5a
		for i in int(used) + 1 .. output.len { assert output[i] == 0x5a }
		if used >= 12 {
			assert message_load32(address) == 28
			assert message_load32(address + 4) == 0xffff
			assert message_load32(address + 8) == 2
		}
		if used == 28 {
			assert message_load64(address + 12) == 1700000000
			assert message_load32(address + 20) == 234567
			assert message_load32(address + 24) == 0
		}
	}
}

fn test_darwin_message_partial_descriptor_ownership() {
	mut pair := [2]i32{}
	mut pipe := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_DGRAM, 0, unsafe { &pair[0] }) == 0
	assert C.pipe(unsafe { &pipe[0] }) == 0
	defer { C.close(pair[0]); C.close(pair[1]); C.close(pipe[0]); C.close(pipe[1]) }
	baseline := C.open(c'/dev/null', C.O_RDONLY)
	assert baseline >= 0
	assert C.close(baseline) == 0
	mut record := [21]u8{}
	base := usize(unsafe { &record[1] })
	message_store32(base, 20)
	message_store32(base + 4, 0xffff)
	message_store32(base + 8, 1)
	message_store32(base + 12, u32(pipe[0]))
	message_store32(base + 16, u32(pipe[1]))
	mut byte := [1]u8{init: 0x51}
	mut vector := C.iovec{ iov_base: unsafe { &byte[0] }, iov_len: 1 }
	mut sent := DarwinMessage{ vectors: unsafe { &vector }, vector_count: 1,
		control: voidptr(base), control_length: 20 }
	for _ in 0 .. 32 {
		for capacity in [u32(0), 1, 12, 13, 16, 17, 19, 20] {
			darwin_set_errno(177)
			assert darwin_sendmsg(pair[0], unsafe { &sent }, 0) == 1
			assert unsafe { *C.ios_errno_address() } == 177
			mut output := [65]u8{}
			unsafe { C.memset(&output[0], 0x5a, sizeof(output)) }
			mut got := DarwinMessage{ vectors: unsafe { &vector }, vector_count: 1,
				control: unsafe { &output[1] }, control_length: capacity }
			assert darwin_recvmsg(pair[1], unsafe { &got }, 0) == 1
			assert unsafe { *C.ios_errno_address() } == 177
			assert byte[0] == 0x51
			assert got.control_length == capacity
			assert got.flags == if capacity != 0 && capacity < 20 { i32(0x20) } else { i32(0) }
			assert output[0] == 0x5a
			for i in int(capacity) + 1 .. output.len { assert output[i] == 0x5a }
			if capacity >= 16 {
				received := i32(message_load32(usize(unsafe { &output[13] })))
				assert C.write(pipe[1], unsafe { &byte[0] }, 1) == 1
				assert C.read(received, unsafe { &byte[0] }, 1) == 1
				assert C.close(received) == 0
			}
			if capacity >= 20 {
				received := i32(message_load32(usize(unsafe { &output[17] })))
				assert C.write(received, unsafe { &byte[0] }, 1) == 1
				assert C.read(pipe[0], unsafe { &byte[0] }, 1) == 1
				assert C.close(received) == 0
			}
			// The lowest free native descriptor must be unchanged even when
			// both rights were installed but neither fit in the Darwin output.
			probe := C.open(c'/dev/null', C.O_RDONLY)
			assert probe == baseline
			assert C.close(probe) == 0
		}
		assert darwin_sendmsg(pair[0], unsafe { &sent }, 0) == 1
		mut discarded := DarwinMessage{ vectors: unsafe { &vector }, vector_count: 1,
			control: unsafe { nil }, control_length: 64 }
		assert darwin_recvmsg(pair[1], unsafe { &discarded }, 0) == 1
		assert discarded.control_length == 64 && discarded.flags == 0
		probe := C.open(c'/dev/null', C.O_RDONLY)
		assert probe == baseline
		assert C.close(probe) == 0
	}
}

fn test_darwin_message_rejection_before_io() {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_DGRAM, 0, unsafe { &pair[0] }) == 0
	defer { C.close(pair[0]); C.close(pair[1]) }
	mut bytes := [2]u8{init: 0x5a}
	mut vector := C.iovec{ iov_base: unsafe { &bytes[0] }, iov_len: 1 }
	mut message := DarwinMessage{ vectors: unsafe { &vector }, vector_count: 1, flags: 123 }
	assert C.send(pair[0], c'Q', 1, 0) == 1
	assert darwin_recvmsg(pair[1], unsafe { &message }, 0x100000) == -1
	assert unsafe { *C.ios_errno_address() } == 45
	assert message.flags == 123 && bytes[0] == 0x5a && bytes[1] == 0x5a
	assert darwin_recvmsg(pair[1], unsafe { &message }, 0) == 1
	assert bytes[0] == 0x51 && bytes[1] == 0x5a
	mut record := [12]u8{}
	base := usize(unsafe { &record[0] })
	message_store32(base, 12)
	message_store32(base + 4, 0xffff)
	message_store32(base + 8, 2)
	message.control = unsafe { &record[0] }
	message.control_length = 12
	assert darwin_sendmsg(pair[0], unsafe { &message }, 0) == -1
	assert unsafe { *C.ios_errno_address() } == 45
	message.control = unsafe { nil }
	message.control_length = 0
	assert darwin_recvmsg(pair[1], unsafe { &message }, 0x80) == -1
	assert unsafe { *C.ios_errno_address() } == 35
	vector.iov_len = usize(0x8000000000000000)
	assert darwin_recvmsg(pair[1], unsafe { &message }, 0) == -1
	assert unsafe { *C.ios_errno_address() } == 22
}
