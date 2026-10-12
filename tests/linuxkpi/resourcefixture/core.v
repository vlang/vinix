// SPDX-License-Identifier: GPL-2.0-or-later
// Public Linux resource records, parsed without compatibility kernel overlays.
@[translated]
module resourcefixture

#include "resource_v_contract.h"

struct C.rlimit {
mut:
	rlim_cur usize
	rlim_max usize
}

struct C.rlimit64 {
mut:
	rlim_cur u64
	rlim_max u64
}

fn C.assert(bool)
fn C.puts(&char) i32

@[c_extern]
__global C.RLIM_INFINITY usize

@[c_extern]
__global C.RLIM_NLIMITS u32

@[c_extern]
__global C.RLIMIT_CPU u32

@[c_extern]
__global C.RLIMIT_FSIZE u32

@[c_extern]
__global C.RLIMIT_DATA u32

@[c_extern]
__global C.RLIMIT_STACK u32

@[c_extern]
__global C.RLIMIT_CORE u32

@[c_extern]
__global C.RLIMIT_RSS u32

@[c_extern]
__global C.RLIMIT_NPROC u32

@[c_extern]
__global C.RLIMIT_NOFILE u32

@[c_extern]
__global C.RLIMIT_MEMLOCK u32

@[c_extern]
__global C.RLIMIT_AS u32

@[c_extern]
__global C.RLIMIT_LOCKS u32

@[c_extern]
__global C.RLIMIT_SIGPENDING u32

@[c_extern]
__global C.RLIMIT_MSGQUEUE u32

@[c_extern]
__global C.RLIMIT_NICE u32

@[c_extern]
__global C.RLIMIT_RTPRIO u32

@[c_extern]
__global C.RLIMIT_RTTIME u32

@[export: 'main']
@[direct_array_access]
pub fn run() i32 {
	unsafe {
		ids := [C.RLIMIT_CPU, C.RLIMIT_FSIZE, C.RLIMIT_DATA, C.RLIMIT_STACK, C.RLIMIT_CORE,
			C.RLIMIT_RSS, C.RLIMIT_NPROC, C.RLIMIT_NOFILE, C.RLIMIT_MEMLOCK, C.RLIMIT_AS,
			C.RLIMIT_LOCKS, C.RLIMIT_SIGPENDING, C.RLIMIT_MSGQUEUE, C.RLIMIT_NICE, C.RLIMIT_RTPRIO,
			C.RLIMIT_RTTIME]!
		for index in 0 .. 16 { C.assert(ids[index] == u32(index)) }
		C.assert(C.RLIM_NLIMITS == 16 && C.RLIM_INFINITY == ~usize(0))
		ordinary := C.rlimit{ rlim_cur: 0, rlim_max: C.RLIM_INFINITY }
		wide := C.rlimit64{ rlim_cur: 0, rlim_max: ~u64(0) }
		C.assert(ordinary.rlim_cur == 0 && ordinary.rlim_max == ~usize(0))
		C.assert(wide.rlim_cur == 0 && wide.rlim_max == ~u64(0))
		C.puts(c'PASS: original UAPI resource IDs, infinity width and record layout')
		return 0
	}
}
