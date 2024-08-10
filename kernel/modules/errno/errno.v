// errno.v: Errno values for all the kernel errors.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module errno

import proc

pub const err = u64(-1)

pub const eperm = 1
pub const enoent = 2
pub const esrch = 3
pub const eintr = 4
pub const eio = 5
pub const enxio = 6
pub const e2big = 7
pub const enoexec = 8
pub const ebadf = 9
pub const echild = 10
pub const eagain = 11
pub const enomem = 12
pub const eacces = 13
pub const efault = 14
pub const enotblk = 15
pub const ebusy = 16
pub const eexist = 17
pub const exdev = 18
pub const enodev = 19
pub const enotdir = 20
pub const eisdir = 21
pub const einval = 22
pub const enfile = 23
pub const emfile = 24
pub const enotty = 25
pub const etxtbsy = 26
pub const efbig = 27
pub const enospc = 28
pub const espipe = 29
pub const erofs = 30
pub const emlink = 31
pub const epipe = 32
pub const edom = 33
pub const erange = 34
pub const edeadlk = 35
pub const enametoolong = 36
pub const enolck = 37
pub const enosys = 38
pub const enotempty = 39
pub const eloop = 40
pub const ewouldblock = eagain
pub const enomsg = 42
pub const eidrm = 43
pub const echrng = 44
pub const el2nsync = 45
pub const el3hlt = 46
pub const el3rst = 47
pub const elnrng = 48
pub const eunatch = 49
pub const enocsi = 50
pub const el2hlt = 51
pub const ebade = 52
pub const ebadr = 53
pub const exfull = 54
pub const enoano = 55
pub const ebadrqc = 56
pub const ebadslt = 57
pub const edeadlock = edeadlk
pub const ebfont = 59
pub const enostr = 60
pub const enodata = 61
pub const etime = 62
pub const enosr = 63
pub const enonet = 64
pub const enopkg = 65
pub const eremote = 66
pub const enolink = 67
pub const eadv = 68
pub const esrmnt = 69
pub const ecomm = 70
pub const eproto = 71
pub const emultihop = 72
pub const edotdot = 73
pub const ebadmsg = 74
pub const eoverflow = 75
pub const enotuniq = 76
pub const ebadfd = 77
pub const eremchg = 78
pub const elibacc = 79
pub const elibbad = 80
pub const elibscn = 81
pub const elibmax = 82
pub const elibexec = 83
pub const eilseq = 84
pub const erestart = 85
pub const estrpipe = 86
pub const eusers = 87
pub const enotsock = 88
pub const edestaddrreq = 89
pub const emsgsize = 90
pub const eprototype = 91
pub const enoprotoopt = 92
pub const eprotonosupport = 93
pub const esocktnosupport = 94
pub const eopnotsupp = 95
pub const enotsup = eopnotsupp
pub const epfnosupport = 96
pub const eafnosupport = 97
pub const eaddrinuse = 98
pub const eaddrnotavail = 99
pub const enetdown = 100
pub const enetunreach = 101
pub const enetreset = 102
pub const econnaborted = 103
pub const econnreset = 104
pub const enobufs = 105
pub const eisconn = 106
pub const enotconn = 107
pub const eshutdown = 108
pub const etoomanyrefs = 109
pub const etimedout = 110
pub const econnrefused = 111
pub const ehostdown = 112
pub const ehostunreach = 113
pub const ealready = 114
pub const einprogress = 115
pub const estale = 116
pub const euclean = 117
pub const enotnam = 118
pub const enavail = 119
pub const eisnam = 120
pub const eremoteio = 121
pub const edquot = 122
pub const enomedium = 123
pub const emediumtype = 124
pub const ecanceled = 125
pub const enokey = 126
pub const ekeyexpired = 127
pub const ekeyrevoked = 128
pub const ekeyrejected = 129
pub const eownerdead = 130
pub const enotrecoverable = 131
pub const erfkill = 132
pub const ehwpoison = 133

pub fn get() u64 {
	return proc.current_thread().errno
}

pub fn set(err_no u64) {
	proc.current_thread().errno = err_no
}
