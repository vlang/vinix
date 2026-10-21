// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

#include <pthread.h>

fn C.pthread_self() usize
fn C.pipe(&i32) i32
fn C.fcntl(i32, i32, ...) i32

struct WsQueue {
mut:
	thread   usize
	read_fd  i32
	write_fd i32
	idling   bool
}

fn ws_queue_new() i64 {
	unsafe {
		mut descriptors := [2]i32{}
		if C.pipe(&descriptors[0]) != 0 { return 0 }
		C.fcntl(descriptors[0], 4, 2048)
		C.fcntl(descriptors[1], 4, 2048)
		C.fcntl(descriptors[0], 2, 1)
		C.fcntl(descriptors[1], 2, 1)
		queue := &WsQueue(C.calloc(1, sizeof(WsQueue)))
		*queue = WsQueue{ thread: usize(C.pthread_self()), read_fd: descriptors[0], write_fd: descriptors[1] }
		return i64(queue)
	}
}

fn ws_queue_destroy(pointer i64) {
	unsafe {
		if pointer == 0 { return }
		queue := &WsQueue(pointer)
		C.close(queue.read_fd)
		C.close(queue.write_fd)
		C.free(queue)
	}
}

fn ws_queue_wake(pointer i64) {
	unsafe {
		if pointer == 0 { return }
		byte := u8(1)
		C.write((&WsQueue(pointer)).write_fd, &byte, 1)
	}
}

fn ws_queue_poll(pointer i64, timeout i32) u8 {
	unsafe {
		if pointer == 0 { return 1 }
		queue := &WsQueue(pointer)
		if queue.thread == ws.main_thread { return u8(timeout != 0) }
		mut descriptor := WsPoll{ fd: queue.read_fd, events: 1 }
		queue.idling = timeout != 0
		C.poll(voidptr(&descriptor), 1, timeout)
		queue.idling = false
		mut bytes := [128]u8{}
		for C.read(queue.read_fd, &bytes[0], 128) > 0 {
		}
		return 0
	}
}
