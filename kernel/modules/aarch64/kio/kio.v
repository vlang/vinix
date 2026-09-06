module kio

import aarch64.cpu

// ARM has no port I/O -- only MMIO.
//
// Accesses go through width-exact routines in asm/aarch64/kio.S. V's inline
// assembler cannot ask for a 32-bit register view (`%w[x]`), so an inline
// `ldr ret, [addr]` with a u32 result became an 8-byte load. On Apple Silicon
// that faulted on the very first AIC register read (misaligned Device-memory
// access, DFSC 0x21); on QEMU it silently over-read. See kio.S.

fn C.vinix_mmio_read8(addr voidptr) u8
fn C.vinix_mmio_read16(addr voidptr) u16
fn C.vinix_mmio_read32(addr voidptr) u32
fn C.vinix_mmio_read64(addr voidptr) u64
fn C.vinix_mmio_write8(addr voidptr, value u8)
fn C.vinix_mmio_write16(addr voidptr, value u16)
fn C.vinix_mmio_write32(addr voidptr, value u32)
fn C.vinix_mmio_write64(addr voidptr, value u64)

pub fn mmin[T](addr &T) T {
	mut ret := T(0)
	$if T is u8 || T is i8 {
		ret = T(C.vinix_mmio_read8(voidptr(addr)))
	} $else $if T is u16 || T is i16 {
		ret = T(C.vinix_mmio_read16(voidptr(addr)))
	} $else $if T is u32 || T is i32 || T is int {
		ret = T(C.vinix_mmio_read32(voidptr(addr)))
	} $else {
		ret = T(C.vinix_mmio_read64(voidptr(addr)))
	}
	cpu.dmb_ish()
	return ret
}

pub fn mmout[T](addr &T, value T) {
	cpu.dmb_ish()
	$if T is u8 || T is i8 {
		C.vinix_mmio_write8(voidptr(addr), u8(value))
	} $else $if T is u16 || T is i16 {
		C.vinix_mmio_write16(voidptr(addr), u16(value))
	} $else $if T is u32 || T is i32 || T is int {
		C.vinix_mmio_write32(voidptr(addr), u32(value))
	} $else {
		C.vinix_mmio_write64(voidptr(addr), u64(value))
	}
}

pub fn mmin32(addr &u32) u32 {
	ret := C.vinix_mmio_read32(voidptr(addr))
	cpu.dmb_ish()
	return ret
}

pub fn mmout32(addr &u32, value u32) {
	cpu.dmb_ish()
	C.vinix_mmio_write32(voidptr(addr), value)
}

pub fn mmin64(addr &u64) u64 {
	ret := C.vinix_mmio_read64(voidptr(addr))
	cpu.dmb_ish()
	return ret
}

pub fn mmout64(addr &u64, value u64) {
	cpu.dmb_ish()
	C.vinix_mmio_write64(voidptr(addr), value)
}
