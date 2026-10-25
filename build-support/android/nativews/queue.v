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

// A native main-loop pass also has to reach frames, rendering and input. A
// Handler can keep the Java queue ready forever by posting its next callback.
// Check before MessageQueue.next removes a message so yielding preserves order.
fn ws_queue_begin_pump() {
	ws.queue_pump_polls = 0
	ws.queue_pump_deadline = ws_millis() + 16
	ws.queue_pump_active = true
}

fn ws_queue_end_pump() {
	ws.queue_pump_active = false
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
		if queue.thread == ws.main_thread {
			if timeout != 0 { return 1 }
			if ws.queue_pump_active {
				// Always admit the first poll, even if startup or host scheduling
				// used the time budget before Java reached nativePollOnce.
				if ws.queue_pump_polls > 0 && (ws.queue_pump_polls >= 64
					|| ws_millis() >= ws.queue_pump_deadline) { return 1 }
				ws.queue_pump_polls++
			}
			return 0
		}
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
