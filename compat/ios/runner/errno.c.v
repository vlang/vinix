// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <errno.h>

// __error exposes the calling thread's errno. Translate immediately after a
// failed native libc call, before another libc operation can overwrite it.
fn darwin_native_error(value int) int {
	$if macos { return value }
	return match value {
		C.EAGAIN { 35 }
		C.EINPROGRESS { 36 }
		C.EALREADY { 37 }
		C.ENOTSOCK { 38 }
		C.EDESTADDRREQ { 39 }
		C.EMSGSIZE { 40 }
		C.EPROTOTYPE { 41 }
		C.ENOPROTOOPT { 42 }
		C.EPROTONOSUPPORT { 43 }
		C.ESOCKTNOSUPPORT { 44 }
		C.EOPNOTSUPP { 102 }
		C.EPFNOSUPPORT { 46 }
		C.EAFNOSUPPORT { 47 }
		C.EADDRINUSE { 48 }
		C.EADDRNOTAVAIL { 49 }
		C.ENETDOWN { 50 }
		C.ENETUNREACH { 51 }
		C.ENETRESET { 52 }
		C.ECONNABORTED { 53 }
		C.ECONNRESET { 54 }
		C.ENOBUFS { 55 }
		C.EISCONN { 56 }
		C.ENOTCONN { 57 }
		C.ESHUTDOWN { 58 }
		C.ETOOMANYREFS { 59 }
		C.ETIMEDOUT { 60 }
		C.ECONNREFUSED { 61 }
		C.ELOOP { 62 }
		C.ENAMETOOLONG { 63 }
		C.EHOSTDOWN { 64 }
		C.EHOSTUNREACH { 65 }
		C.ENOTEMPTY { 66 }
		C.EOVERFLOW { 84 }
		C.ECANCELED { 89 }
		C.EPROTO { 100 }
		C.ENOSYS { 78 }
		else { value }
	}
}
