module cpu

import msr

pub fn interrupt_state() bool {
	mut f := u64(0)
	asm volatile amd64 {
		pushfq
		pop f
		; =rm (f)
	}
	return f & (1 << 9) != 0
}

pub fn set_gs_base(ptr u64) {
	msr.wrmsr(0xc0000101, ptr)
}

pub fn set_fs_base(ptr u64) {
	msr.wrmsr(0xc0000100, ptr)
}

pub fn get_gs_base() u64 {
	return msr.rdmsr(0xc0000101)
}

pub fn get_fs_base() u64 {
	return msr.rdmsr(0xc0000100)
}

pub fn syscall_set_fs_base(_ voidptr, base voidptr) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: set_fs_base(0x%llx)\n', base)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	set_fs_base(u64(base))
	return 0, 0
}

pub fn syscall_set_gs_base(_ voidptr, base voidptr) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: set_gs_base(0x%llx)\n', base)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	set_gs_base(u64(base))
	return 0, 0
}

pub fn read_cr0() u64 {
	mut ret := u64(0)
	asm volatile amd64 {
		mov ret, cr0
		; =r (ret)
		;
		; memory
	}
	return ret
}

pub fn write_cr0(value u64) {
	asm volatile amd64 {
		mov cr0, value
		;
		; r (value)
		; memory
	}
}

pub fn read_cr2() u64 {
	mut ret := u64(0)
	asm volatile amd64 {
		mov ret, cr2
		; =r (ret)
		;
		; memory
	}
	return ret
}

pub fn write_cr2(value u64) {
	asm volatile amd64 {
		mov cr2, value
		;
		; r (value)
		; memory
	}
}

pub fn read_cr3() u64 {
	mut ret := u64(0)
	asm volatile amd64 {
		mov ret, cr3
		; =r (ret)
		;
		; memory
	}
	return ret
}

pub fn write_cr3(value u64) {
	asm volatile amd64 {
		mov cr3, value
		;
		; r (value)
		; memory
	}
}

pub fn read_cr4() u64 {
	mut ret := u64(0)
	asm volatile amd64 {
		mov ret, cr4
		; =r (ret)
		;
		; memory
	}
	return ret
}

pub fn write_cr4(value u64) {
	asm volatile amd64 {
		mov cr4, value
		;
		; r (value)
		; memory
	}
}

pub fn wrxcr(reg u32, value u64) {
	a := u32(value)
	d := u32(value >> 32)
	asm volatile amd64 {
		xsetbv
		;
		; a (a)
		  d (d)
		  c (reg)
		; memory
	}
}

pub fn rdtsc() u64 {
	mut a := u32(0)
	mut d := u32(0)
	asm volatile amd64 {
		rdtsc
		; =a (a)
		  =d (d)
	}

	return u64(a) | (u64(d) << 32)
}

pub fn rdrand64() u64 {
	mut a := u64(0)
	asm volatile amd64 {
		rdrand rax
		; =a (a)
	}

	return a
}

pub fn rdrand32() u32 {
	mut a := u32(0)
	asm volatile amd64 {
		rdrand eax
		; =a (a)
	}

	return a
}

pub fn rdseed32() u32 {
	mut a := u32(0)
	asm volatile amd64 {
		rdseed eax
		; =a (a)
	}

	return a
}

fn xsave(region voidptr) {
	asm volatile amd64 {
		xsave [region]
		;
		; r (region)
		  a (0xffffffff)
		  d (0xffffffff)
		; memory
	}
}

fn xrstor(region voidptr) {
	asm volatile amd64 {
		xrstor [region]
		;
		; r (region)
		  a (0xffffffff)
		  d (0xffffffff)
		; memory
	}
}

fn fxsave(region voidptr) {
	asm volatile amd64 {
		fxsave [region]
		;
		; r (region)
		; memory
	}
}

fn fxrstor(region voidptr) {
	asm volatile amd64 {
		fxrstor [region]
		;
		; r (region)
		; memory
	}
}

pub const cpuid_xsave = u32(1 << 26)
pub const cpuid_avx = u32(1 << 28)
pub const cpuid_avx512 = u32(1 << 16)

pub fn cpuid(leaf u32, subleaf u32) (bool, u32, u32, u32, u32) {
	mut cpuid_max := u32(0)
	asm volatile amd64 {
		cpuid
		; =a (cpuid_max)
		; a (leaf & 0x80000000)
		; rbx
		  rcx
		  rdx
	}
	if leaf > cpuid_max {
		return false, 0, 0, 0, 0
	}
	mut a := u32(0)
	mut b := u32(0)
	mut c := u32(0)
	mut d := u32(0)
	asm volatile amd64 {
		cpuid
		; =a (a)
		  =b (b)
		  =c (c)
		  =d (d)
		; a (leaf)
		  c (subleaf)
	}
	return true, a, b, c, d
}

__global (
	cpu_get_id fn () u64
	cpu_set_id fn (u64)
	fpu_storage_size u64
	fpu_save         fn (voidptr)
	fpu_restore      fn (voidptr)
)

pub fn set_id_zero(_ u64) {
}

pub fn get_id_zero() u64 {
	return 0
}

pub fn set_id_rdtscp(id u64) {
	msr.wrmsr(0xc0000103, id)
}

pub fn get_id_rdtscp() u64 {
	return msr.rdmsr(0xc0000103)
}
