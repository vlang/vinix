// SPDX-License-Identifier: GPL-2.0-or-later
module timesync

import desktop.sessioncore
import desktop.sessionipc
import net
import time
import os

fn C.clock_settime(int, &C.timespec) int

__global volatile stopped bool

fn stop(_ os.Signal) {
	unsafe { stopped = true }
}

fn session_sync_time(server string) ! {
	if server.len == 0 || server.len > 253 || server.contains_any('\t\n\r /') {
		return error('invalid time server')
	}
	address := '${server}:123'
	defer { unsafe { address.free() } }
	mut connection := net.dial_udp(address)!
	defer {
		connection.close() or {}
		unsafe { free(connection) }
	}
	connection.set_read_timeout(2 * time.second)
	connection.set_write_timeout(time.second)
	mut request := [48]u8{}
	request[0] = 0x23
	mut token := [8]u8{}
	mut random := os.open('/dev/urandom')!
	mut bytes := []u8{len: 8}
	n := random.read(mut bytes) or {
		random.close()
		unsafe { bytes.free() }
		return err
	}
	random.close()
	if n != 8 {
		unsafe { bytes.free() }
		return error('random clock token unavailable')
	}
	for i in 0 .. 8 {
		token[i] = bytes[i]
		request[40 + i] = bytes[i]
	}
	unsafe { bytes.free() }
	started := sessionipc.monotonic_millis()
	if connection.write_ptr(&request[0], 48)! != 48 { return error('short clock request') }
	mut reply := []u8{len: 49}
	defer { unsafe { reply.free() } }
	length, _ := connection.read(mut reply)!
	view := unsafe { reply[..length] }
	epoch_ms := sessioncore.ntp_time(view, token, sessionipc.monotonic_millis() - started)!
	stamp := C.timespec{ tv_sec: epoch_ms / 1000, tv_nsec: (epoch_ms % 1000) * 1000000 }
	if C.clock_settime(C.CLOCK_REALTIME, &stamp) != 0 {
		return error('clock change not permitted by the kernel')
	}
}

pub fn run(server string) {
	os.signal_opt(.term, stop) or {}
	os.signal_opt(.int, stop) or {}
	mut next := i64(0)
	for !unsafe { stopped } {
		now := sessionipc.monotonic_millis()
		if now >= next {
			session_sync_time(server) or {
				eprintln('time synchronization: ${err}')
				next = now + 60000
				time.sleep(100 * time.millisecond)
				continue
			}
			epoch, _ := sessionipc.desktop_realtime()
			println('time synchronized: ${epoch}')
			next = now + 15 * 60000
		}
		time.sleep(100 * time.millisecond)
	}
}
