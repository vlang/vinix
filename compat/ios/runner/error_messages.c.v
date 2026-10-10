// SPDX-License-Identifier: GPL-2.0-or-later
module main

// C-locale Darwin error text measured through installed Mac libSystem.
// Fixed C-string pointers have process lifetime and need no registry.
const darwin_error_messages = [
	c'Undefined error: 0', // 0
	c'Operation not permitted', // 1
	c'No such file or directory', // 2
	c'No such process', // 3
	c'Interrupted system call', // 4
	c'Input/output error', // 5
	c'Device not configured', // 6
	c'Argument list too long', // 7
	c'Exec format error', // 8
	c'Bad file descriptor', // 9
	c'No child processes', // 10
	c'Resource deadlock avoided', // 11
	c'Cannot allocate memory', // 12
	c'Permission denied', // 13
	c'Bad address', // 14
	c'Block device required', // 15
	c'Resource busy', // 16
	c'File exists', // 17
	c'Cross-device link', // 18
	c'Operation not supported by device', // 19
	c'Not a directory', // 20
	c'Is a directory', // 21
	c'Invalid argument', // 22
	c'Too many open files in system', // 23
	c'Too many open files', // 24
	c'Inappropriate ioctl for device', // 25
	c'Text file busy', // 26
	c'File too large', // 27
	c'No space left on device', // 28
	c'Illegal seek', // 29
	c'Read-only file system', // 30
	c'Too many links', // 31
	c'Broken pipe', // 32
	c'Numerical argument out of domain', // 33
	c'Result too large', // 34
	c'Resource temporarily unavailable', // 35
	c'Operation now in progress', // 36
	c'Operation already in progress', // 37
	c'Socket operation on non-socket', // 38
	c'Destination address required', // 39
	c'Message too long', // 40
	c'Protocol wrong type for socket', // 41
	c'Protocol not available', // 42
	c'Protocol not supported', // 43
	c'Socket type not supported', // 44
	c'Operation not supported', // 45
	c'Protocol family not supported', // 46
	c'Address family not supported by protocol family', // 47
	c'Address already in use', // 48
	c"Can't assign requested address", // 49
	c'Network is down', // 50
	c'Network is unreachable', // 51
	c'Network dropped connection on reset', // 52
	c'Software caused connection abort', // 53
	c'Connection reset by peer', // 54
	c'No buffer space available', // 55
	c'Socket is already connected', // 56
	c'Socket is not connected', // 57
	c"Can't send after socket shutdown", // 58
	c"Too many references: can't splice", // 59
	c'Operation timed out', // 60
	c'Connection refused', // 61
	c'Too many levels of symbolic links', // 62
	c'File name too long', // 63
	c'Host is down', // 64
	c'No route to host', // 65
	c'Directory not empty', // 66
	c'Too many processes', // 67
	c'Too many users', // 68
	c'Disc quota exceeded', // 69
	c'Stale NFS file handle', // 70
	c'Too many levels of remote in path', // 71
	c'RPC struct is bad', // 72
	c'RPC version wrong', // 73
	c'RPC prog. not avail', // 74
	c'Program version wrong', // 75
	c'Bad procedure for program', // 76
	c'No locks available', // 77
	c'Function not implemented', // 78
	c'Inappropriate file type or format', // 79
	c'Authentication error', // 80
	c'Need authenticator', // 81
	c'Device power is off', // 82
	c'Device error', // 83
	c'Value too large to be stored in data type', // 84
	c'Bad executable (or shared library)', // 85
	c'Bad CPU type in executable', // 86
	c'Shared library version mismatch', // 87
	c'Malformed Mach-o file', // 88
	c'Operation canceled', // 89
	c'Identifier removed', // 90
	c'No message of desired type', // 91
	c'Illegal byte sequence', // 92
	c'Attribute not found', // 93
	c'Bad message', // 94
	c'EMULTIHOP (Reserved)', // 95
	c'No message available on STREAM', // 96
	c'ENOLINK (Reserved)', // 97
	c'No STREAM resources', // 98
	c'Not a STREAM', // 99
	c'Protocol error', // 100
	c'STREAM ioctl timeout', // 101
	c'Operation not supported on socket', // 102
	c'Policy not found', // 103
	c'State not recoverable', // 104
	c'Previous owner died', // 105
	c'Interface output queue is full', // 106
	c'Capabilities insufficient', // 107
]!
