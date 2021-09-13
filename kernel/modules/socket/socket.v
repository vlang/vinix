module socket

import resource
import file
import errno

import socket.public as sock_pub

import socket.unix as sock_unix

fn socket_create(domain int, @type int, protocol int) ?&resource.Resource {
	match domain {
		sock_pub.af_unix {
			ret := sock_unix.create(@type) ?
			return ret
		}
		else {
			C.printf(c'socket: Unknown domain: %d\n', domain)
			errno.set(errno.einval)
			return error('')
		}
	}
}

pub fn syscall_socket(_ voidptr, domain int, @type int, protocol int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: socket(%d, 0x%x, %d)\n', domain, @type, protocol)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	socket := socket_create(domain, @type, protocol) or {
		return -1, errno.get()
	}

	mut flags := int(0)
	if @type & sock_pub.sock_cloexec != 0 {
		flags |= resource.o_cloexec
	}

	ret := file.fdnum_create_from_resource(voidptr(0), socket, flags, 0, false) or {
		return -1, errno.get()
	}

	return u64(ret), 0
}
