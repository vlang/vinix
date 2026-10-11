// SPDX-License-Identifier: GPL-2.0-or-later
module ext2host

import net
import sync.stdatomic
import time

pub struct Server {
pub:
	port                int
	name                string
	flags               u16
	negotiation_timeout i64
mut:
	export        &Export
	listener      &net.TcpListener
	stopped       i64
	accept_thread thread
	workers       []&Worker
	closed        bool
}

struct Worker {
mut:
	task thread
	done i64
}

pub fn serve(state string, port int, name string, flags u16, negotiation_timeout i64) !&Server {
	mut export := open_export(state)!
	listener := net.listen_tcp(.ip, '127.0.0.1:' + port.str()) or {
		export.close()
		return err
	}
	listener.set_accept_timeout(100 * time.millisecond)
	address := listener.addr() or {
		listener.close() or {}
		export.close()
		return err
	}
	actual_port := address.port() or {
		listener.close() or {}
		export.close()
		return err
	}
	mut server := &Server{
		port:                int(actual_port)
		name:                name
		flags:               flags
		export:              export
		listener:            listener
		negotiation_timeout: negotiation_timeout
	}
	server.accept_thread = spawn accept_loop(mut server)
	return server
}

fn (s &Server) stopping() bool { return stdatomic.load_i64(&s.stopped) != 0 }

pub fn (mut s Server) close() {
	if s.closed { return }
	s.closed = true
	stdatomic.store_i64(&s.stopped, 1)
	s.accept_thread.wait()
	for worker in s.workers { worker.task.wait() }
	s.listener.close() or {}
	s.export.close()
}

fn accept_loop(mut s Server) {
	for !s.stopping() {
		for index := s.workers.len - 1; index >= 0; index-- {
			if stdatomic.load_i64(&s.workers[index].done) == 0 { continue }
			s.workers[index].task.wait()
			s.workers.delete(index)
		}
		mut connection := s.listener.accept() or {
			if s.stopping() { break }
			continue
		}
		connection.set_read_timeout(100 * time.millisecond)
		connection.set_write_timeout(100 * time.millisecond)
		// accept() already enables TCP_NODELAY and suppresses SIGPIPE.
		mut worker := &Worker{}
		worker.task = spawn handle(mut s, mut connection, mut worker)
		s.workers << worker
	}
}

fn receive(mut connection net.TcpConn, count int, s &Server, deadline i64) ![]u8 {
	mut data := []u8{len: count}
	mut at := 0
	mut limit := if deadline == 0 { i64(0) } else { time.ticks() + s.negotiation_timeout }
	for at < count {
		if s.stopping() || (limit != 0 && time.ticks() >= limit) {
			return error('NBD connection stopped')
		}
		n := connection.read(mut data[at..]) or {
			if err == net.err_timed_out { continue }
			return err
		}
		if n == 0 { return error('NBD connection reached EOF') }
		at += n
		// The original recv deadline restarts when a fragment arrives. Once the
		// export is negotiated, reads may remain idle without a protocol deadline.
		if limit != 0 { limit = time.ticks() + s.negotiation_timeout }
	}
	return data
}

fn send(mut connection net.TcpConn, data []u8, s &Server, deadline i64) ! {
	mut at := 0
	limit := if deadline == 0 { i64(0) } else { time.ticks() + s.negotiation_timeout }
	for at < data.len {
		if s.stopping() || (limit != 0 && time.ticks() >= limit) {
			return error('NBD connection stopped')
		}
		n := connection.write(data[at..]) or {
			if err == net.err_timed_out { continue }
			return err
		}
		if n <= 0 { return error('NBD connection write failed') }
		at += n
	}
}

fn option_reply(mut connection net.TcpConn, s &Server, option u32, kind u32, data []u8, deadline i64) ! {
	mut packet := []u8{len: 20}
	put_be(mut packet, 0, reply_magic, 8)
	put_be(mut packet, 8, option, 4)
	put_be(mut packet, 12, kind, 4)
	put_be(mut packet, 16, u64(data.len), 4)
	packet << data
	send(mut connection, packet, s, deadline)!
}

fn negotiate(mut connection net.TcpConn, s &Server) !bool {
	deadline := time.ticks() + s.negotiation_timeout
	mut greeting := []u8{len: 18}
	put_be(mut greeting, 0, nbd_magic, 8)
	put_be(mut greeting, 8, option_magic, 8)
	put_be(mut greeting, 16, 3, 2)
	send(mut connection, greeting, s, deadline)!
	flags := get_be(receive(mut connection, 4, s, deadline)!, 0, 4)
	if flags & 1 == 0 || flags & ~u64(3) != 0 { return false }
	for _ in 0 .. 64 {
		header := receive(mut connection, 16, s, deadline)!
		option := u32(get_be(header, 8, 4))
		length := get_be(header, 12, 4)
		if get_be(header, 0, 8) != option_magic || length > 65536 { return false }
		data := receive(mut connection, int(length), s, deadline)!
		match option {
			2 {
				option_reply(mut connection, s, option, 1, [], deadline)!
				return false
			}
			1 {
				if data != s.name.bytes() { return false }
				mut response := []u8{len: 10}
				put_be(mut response, 0, u64(s.export.size), 8)
				put_be(mut response, 8, s.flags, 2)
				if flags & 2 == 0 { response << []u8{len: 124} }
				send(mut connection, response, s, deadline)!
				return true
			}
			3 {
				mut name := []u8{len: 4}
				put_be(mut name, 0, u64(s.name.len), 4)
				name << s.name.bytes()
				option_reply(mut connection, s, option, 2, name, deadline)!
				option_reply(mut connection, s, option, 1, [], deadline)!
			}
			6, 7 {
				if data.len < 6 {
					option_reply(mut connection, s, option, 0x80000003, [], deadline)!
					continue
				}
				name_length := get_be(data, 0, 4)
				if name_length > u64(data.len - 6) {
					option_reply(mut connection, s, option, 0x80000003, [], deadline)!
					continue
				}
				at := 4 + int(name_length)
				infos := int(get_be(data, at, 2))
				if data.len != at + 2 + infos * 2 {
					option_reply(mut connection, s, option, 0x80000003, [], deadline)!
					continue
				}
				if data[4..at] != s.name.bytes() {
					option_reply(mut connection, s, option, 0x80000006, [], deadline)!
					continue
				}
				mut info := []u8{len: 12}
				put_be(mut info, 2, u64(s.export.size), 8)
				put_be(mut info, 10, s.flags, 2)
				option_reply(mut connection, s, option, 3, info, deadline)!
				for index in 0 .. infos {
					if get_be(data, at + 2 + index * 2, 2) != 3 { continue }
					mut sizes := []u8{len: 14}
					put_be(mut sizes, 0, 3, 2)
					put_be(mut sizes, 2, 1, 4)
					put_be(mut sizes, 6, block, 4)
					put_be(mut sizes, 10, max_request, 4)
					option_reply(mut connection, s, option, 3, sizes, deadline)!
					break
				}
				option_reply(mut connection, s, option, 1, [], deadline)!
				if option == 7 { return true }
			}
			else { option_reply(mut connection, s, option, 0x80000001, [], deadline)! }
		}
	}
	return false
}

fn handle(mut s Server, mut connection net.TcpConn, mut worker Worker) {
	defer {
		connection.close() or {}
		stdatomic.store_i64(&worker.done, 1)
	}
	handle_session(mut s, mut connection) or {}
}

fn handle_session(mut s Server, mut connection net.TcpConn) ! {
	if !negotiate(mut connection, s)! { return }
	for !s.stopping() {
		header := receive(mut connection, 28, s, 0)!
		length := get_be(header, 24, 4)
		if get_be(header, 0, 4) != request_magic || length > max_request { return }
		command := get_be(header, 6, 2)
		if command == 2 { return }
		mut code := u32(0)
		mut data := []u8{}
		if command == 1 {
			receive(mut connection, int(length), s, 0)!
			code = u32(C.EROFS)
		} else if get_be(header, 4, 2) != 0 {
			code = u32(C.EINVAL)
		} else if command == 0 {
			offset := get_be(header, 16, 8)
			if offset > u64(0x7fffffffffffffff) {
				code = u32(C.EINVAL)
			} else {
				data = s.export.read(i64(offset), int(length)) or {
					code = u32(if err.code() > 0 { err.code() } else { int(C.EIO) })
					[]u8{}
				}
			}
		} else if command != 3 {
			code = if command in [u64(4), 6] { u32(C.EROFS) } else { u32(C.EINVAL) }
		}
		mut reply := []u8{len: 16}
		put_be(mut reply, 0, 0x67446698, 4)
		put_be(mut reply, 4, code, 4)
		for index in 0 .. 8 { reply[8 + index] = header[8 + index] }
		reply << data
		send(mut connection, reply, s, 0)!
	}
}
