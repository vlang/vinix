// errno.v: Errno values for all the kernel errors.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module errno

import proc

pub const edom = 1

pub const eilseq = 2

pub const erange = 3

pub const e2big = 1001

pub const eacces = 1002

pub const eaddrinuse = 1003

pub const eaddrnotavail = 1004

pub const eafnosupport = 1005

pub const eagain = 1006

pub const ealready = 1007

pub const ebadf = 1008

pub const ebadmsg = 1009

pub const ebusy = 1010

pub const ecanceled = 1011

pub const echild = 1012

pub const econnaborted = 1013

pub const econnrefused = 1014

pub const econnreset = 1015

pub const edeadlk = 1016

pub const edestaddrreq = 1017

pub const edquot = 1018

pub const eexist = 1019

pub const efault = 1020

pub const efbig = 1021

pub const ehostunreach = 1022

pub const eidrm = 1023

pub const einprogress = 1024

pub const eintr = 1025

pub const einval = 1026

pub const eio = 1027

pub const eisconn = 1028

pub const eisdir = 1029

pub const eloop = 1030

pub const emfile = 1031

pub const emlink = 1032

pub const emsgsize = 1034

pub const emultihop = 1035

pub const enametoolong = 1036

pub const enetdown = 1037

pub const enetreset = 1038

pub const enetunreach = 1039

pub const enfile = 1040

pub const enobufs = 1041

pub const enodev = 1042

pub const enoent = 1043

pub const enoexec = 1044

pub const enolck = 1045

pub const enolink = 1046

pub const enomem = 1047

pub const enomsg = 1048

pub const enoprotoopt = 1049

pub const enospc = 1050

pub const enosys = 1051

pub const enotconn = 1052

pub const enotdir = 1053

pub const enotempty = 1054

pub const enotrecoverable = 1055

pub const enotsock = 1056

pub const enotsup = 1057

pub const enotty = 1058

pub const enxio = 1059

pub const eopnotsupp = 1060

pub const eoverflow = 1061

pub const eownerdead = 1062

pub const eperm = 1063

pub const epipe = 1064

pub const eproto = 1065

pub const eprotonosupport = 1066

pub const eprototype = 1067

pub const erofs = 1068

pub const espipe = 1069

pub const esrch = 1070

pub const estale = 1071

pub const etimedout = 1072

pub const etxtbsy = 1073

pub const ewouldblock = eagain

pub const exdev = 1075

pub const enodata = 1076

pub const etime = 1077

pub const enokey = 1078

pub const eshutdown = 1079

pub const ehostdown = 1080

pub const ebadfd = 1081

pub fn get() u64 {
	return proc.current_thread().errno
}

pub fn set(errno u64) {
	proc.current_thread().errno = errno
}
