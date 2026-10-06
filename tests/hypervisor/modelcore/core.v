// Differential host model of the public ABI; never part of the guest kernel.
@[has_globals]
module modelcore

#include <hypervisor-guest-native-abi.h>
#include <stdlib.h>
struct C.vinix_hv_create { memory_size u64 }
struct C.vinix_hv_registers { rax u64 rdx u64 }
struct C.vinix_hv_entry { rip u64 rsp u64 rflags u64 }
struct C.vinix_hv_exit { reason u32 instruction_length u32 qualification u64 }
fn C.getenv(&char) &char
fn C.atoi(&char) i32
fn C.strcmp(&char, &char) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.__errno_location() &i32
fn C.abort()
fn C.exit(i32)
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32

__global (
	hv_case i32
	hv_opens i32
	hv_closes i32
	hv_phase i32
	hv_initialized bool
	hv_proc_read bool
	hv_proc_closed bool
	hv_registers C.vinix_hv_registers
)

fn require(condition bool) {
	if !condition {
		unsafe { C.printf(c'Host model invariant: phase=%d opens=%d closes=%d\n', hv_phase, hv_opens, hv_closes) }
		C.fflush(nil)
		C.abort()
	}
}

@[export: 'hv_model_open']
pub fn open(path &char, flags i32) i32 {
	unsafe {
		err := C.__errno_location()
		if !hv_initialized {
			hv_initialized = true
			option := C.getenv(c'HV_MODEL_CASE')
			hv_case = if option == nil { i32(0) } else { C.atoi(option) }
			*err = 99
		}
		if C.strcmp(path, c'/proc/meminfo') == 0 {
			require(flags == C.O_RDONLY && (hv_case < 0 || hv_closes == 5))
			return 90
		}
		require(C.strcmp(path, c'/dev/hypervisor') == 0 && flags == C.O_RDWR)
		if hv_case < 0 {
			*err = if hv_case == -1 { C.ENOENT } else if hv_case == -2 { C.ENODEV } else { C.EACCES }
			return -1
		}
		if hv_case == 5 && hv_opens == 1 { return -1 }
		require(hv_phase == 0 && hv_opens == hv_closes)
		hv_opens++
		return 10 + hv_opens
	}
}

@[export: 'hv_model_pwrite']
pub fn pwrite(fd i32, data voidptr, count usize, offset isize) isize {
	unsafe {
		expected := [u8(0xba), 0xe9, 0, 0xb0, 0x56, 0xee, 0xf4]!
		require(fd == 10 + hv_opens && hv_phase == 2 && count == 7 && offset == 0x1000)
		require(C.memcmp(data, &expected[0], 7) == 0)
		hv_phase = 3
		return if hv_case == 1 { isize(6) } else { isize(7) }
	}
}

@[export: 'hv_model_ioctl_backend']
pub fn ioctl(fd i32, request usize, data voidptr) i32 {
	unsafe {
		require(fd == 10 + hv_opens)
		match request {
			usize(C.VINIX_HV_GET_API_VERSION) {
				require(hv_phase == 0 && data == nil)
				hv_phase = 1
				return if hv_case == 4 { i32(0) } else { i32(C.VINIX_HV_API_VERSION) }
			}
			usize(C.VINIX_HV_CREATE_VM) {
				require(hv_phase == 1 && (&C.vinix_hv_create(data)).memory_size == 0x10000)
				hv_phase = 2
				return if hv_case == 11 { i32(-1) } else { i32(0) }
			}
			usize(C.VINIX_HV_SET_REGISTERS) {
				require(hv_phase == 3)
				mut seed := [15]u64{}
				for i in 0 .. 15 { seed[i] = u64(0x1234567800000000) | u64(i + hv_opens - 1) }
				require(C.memcmp(data, &seed[0], sizeof(C.vinix_hv_registers)) == 0)
				C.memcpy(&hv_registers, data, sizeof(C.vinix_hv_registers))
				hv_phase = 4
				return if hv_case == 12 { i32(-1) } else { i32(0) }
			}
			usize(C.VINIX_HV_SET_ENTRY) {
				entry := &C.vinix_hv_entry(data)
				require(hv_phase == 4 && entry.rip == 0x1000 && entry.rsp == 0x8000 && entry.rflags == 2)
				hv_phase = 5
				return if hv_case == 10 { i32(-1) } else { i32(0) }
			}
			usize(C.VINIX_HV_RUN) {
				mut exit := &C.vinix_hv_exit(data)
				if hv_phase == 5 {
					exit.reason = if hv_case == 3 { u32(C.VINIX_HV_EXIT_HLT) } else { u32(C.VINIX_HV_EXIT_IO) }
					exit.instruction_length = 1
					exit.qualification = u64(if hv_case == 9 { 0xea } else { 0xe9 }) << 16
					hv_registers.rax = (hv_registers.rax & ~u64(0xff)) | 0x56
					hv_registers.rdx = (hv_registers.rdx & ~u64(0xffff)) | 0xe9
					hv_phase = 6
					return if hv_case == 14 { i32(-1) } else { i32(0) }
				}
				require(hv_phase == 8)
				exit.reason = u32(C.VINIX_HV_EXIT_HLT)
				hv_phase = 9
				return if hv_case == 15 { i32(-1) } else { i32(0) }
			}
			usize(C.VINIX_HV_GET_REGISTERS) {
				require(hv_phase == 6)
				if hv_case == 2 { hv_registers.rax ^= 0x100 }
				C.memcpy(data, &hv_registers, sizeof(C.vinix_hv_registers))
				hv_phase = 7
				return if hv_case == 13 { i32(-1) } else { i32(0) }
			}
			usize(C.VINIX_HV_ADVANCE_RIP) {
				require(hv_phase == 7 && *&u32(data) == 1)
				hv_phase = 8
				return if hv_case == 8 { i32(-1) } else { i32(0) }
			}
			else { C.abort(); return -1 }
		}
	}
}

@[export: 'hv_model_read']
pub fn read(fd i32, data voidptr, count usize) isize {
	unsafe {
		require(fd == 90 && count == 128 && !hv_proc_read)
		hv_proc_read = true
		*&u8(data) = `M`
		return if hv_case == 7 { isize(0) } else { isize(1) }
	}
}

@[export: 'hv_model_close']
pub fn close(fd i32) i32 {
	unsafe {
		if fd == 90 {
			require(hv_proc_read && !hv_proc_closed)
			hv_proc_closed = true
			return 0
		}
		require(fd == 10 + hv_opens && hv_phase == 9)
		hv_closes++
		hv_phase = 0
		return if hv_case == 6 { i32(-1) } else { i32(0) }
	}
}

@[export: 'hv_model_pause']
pub fn pause() i32 {
	unsafe {
		require(hv_proc_read && hv_proc_closed && (hv_case < 0 || hv_opens == 5 && hv_closes == 5))
		C.exit(0)
		return 0
	}
}
