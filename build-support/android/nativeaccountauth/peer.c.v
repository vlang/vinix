// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

import net as _

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

fn C.getpeereid(i32, &u32, &u32) i32

// Peer records the kernel's identity for a connected Unix stream. It does not
// accept an APK's Context, package name or caller-supplied UID as authority.
pub struct Peer {
pub:
	pid int
	uid u32
	gid u32
}

struct WirePeer {
	pid i32
	uid u32
	gid u32
}

// peer_credentials must be called on the accepted connection, before parsing
// untrusted account requests. The Linux ABI also works in the Vinix kernel.
pub fn peer_credentials(fd int) !Peer {
	if fd < 0 || fd > 0x7fffffff { return error('invalid account peer descriptor') }
	socket := i32(fd)
	mut kind := i32(0)
	mut length := u32(sizeof(i32))
	if C.getsockopt(socket, C.SOL_SOCKET, C.SO_TYPE, &kind, &length) != 0
		|| length != sizeof(i32) || kind != C.SOCK_STREAM {
		return error('account peer requires a Unix stream')
	}
	mut address := C.sockaddr_un{}
	length = u32(sizeof(C.sockaddr_un))
	if C.getsockname(socket, voidptr(&address), &length) != 0
		|| length < 2 || length > sizeof(C.sockaddr_un) || address.sun_family != C.AF_UNIX {
		return error('account peer requires a Unix socket')
	}
	address = C.sockaddr_un{}
	length = u32(sizeof(C.sockaddr_un))
	if C.getpeername(socket, voidptr(&address), &length) != 0
		|| length < 2 || length > sizeof(C.sockaddr_un) || address.sun_family != C.AF_UNIX {
		return error('account peer requires a connected Unix socket')
	}
	$if linux {
		mut peer := WirePeer{}
		length = u32(sizeof(WirePeer))
		if C.getsockopt(socket, C.SOL_SOCKET, C.SO_PEERCRED, &peer, &length) != 0
			|| length != sizeof(WirePeer) || peer.pid <= 0 {
			return error('cannot obtain account peer credentials')
		}
		return Peer{ pid: int(peer.pid), uid: peer.uid, gid: peer.gid }
	} $else $if macos {
		// This host adapter exercises the same contract without substituting
		// process-global credentials for the remote endpoint's credentials.
		mut uid := u32(0)
		mut gid := u32(0)
		if C.getpeereid(socket, &uid, &gid) != 0 {
			return error('cannot obtain account peer credentials')
		}
		mut pid := i32(0)
		length = u32(sizeof(i32))
		if C.getsockopt(socket, C.SOL_LOCAL, C.LOCAL_PEERPID, &pid, &length) != 0
			|| length != sizeof(i32) || pid <= 0 {
			return error('cannot obtain account peer process')
		}
		return Peer{ pid: int(pid), uid: uid, gid: gid }
	} $else {
		return error('account peer credentials require Linux or macOS')
	}
}
