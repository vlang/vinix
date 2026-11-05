@[has_globals]
module fixture

import x86.kio
import klock

#include <assert.h>
#include <string.h>
fn C.assert(bool)
fn C.memset(voidptr, int, usize) voidptr
fn C._vinit(int, voidptr)

const com1_port = 0x3f8
const com_ports = [com1_port, 0x2f8, 0x3e8, 0x2e8]!

struct Bootlog {}
fn (_ Bootlog) append(_text charptr, len u64) { logged += len }

struct TestRSDPResponse {
mut:
	address voidptr
}
struct TestRSDPRequest {
mut:
	response &TestRSDPResponse = unsafe { nil }
}

__global (
	kprint_lock klock.Lock
	bootlog Bootlog
	logged u64
	terminal_bytes [64]u8
	terminal_len int
	flags u32
	mmio_reads int
	mmio_delay int
	mmio_output [64]u8
	mmio_len int
	acpi_data [1024]u8
	rsdp_response TestRSDPResponse
	fake_higher_half u64
)

fn terminal(text charptr, len u64) {
	C.assert(len <= 64)
	terminal_len = int(len)
	for i := 0; i < int(len); i++ { terminal_bytes[i] = unsafe { u8(text[i]) } }
}

// Fake only the MMIO boundary; uart.v's production polling/formatting runs.
fn read_register(offset u64) u32 {
	C.assert(offset == 0x18)
	mmio_reads++
	return if mmio_reads <= mmio_delay { u32(0x20) } else { flags }
}
fn write_register(offset u64, value u32) {
	C.assert(offset == 0 && mmio_len < 64)
	mmio_output[mmio_len] = u8(value)
	mmio_len++
}
fn tx_relax() {}
fn reset_mmio(status u32, wait int) {
	flags = status
	mmio_delay = wait
	mmio_reads = 0
	mmio_len = 0
	initialise(0x1000)
}

fn test_hhdm_offset() u64 { return fake_higher_half }
fn test_bootloader_hhdm_offset() u64 { return u64(unsafe { &acpi_data[0] }) }
fn store32(offset int, value u32) {
	for i in 0 .. 4 { acpi_data[offset + i] = u8(value >> (i * 8)) }
}
fn store64(offset int, value u64) {
	for i in 0 .. 8 { acpi_data[offset + i] = u8(value >> (i * 8)) }
}
fn text_at(offset int, text string) {
	for i := 0; i < text.len; i++ { acpi_data[offset + i] = text[i] }
}
fn acpi_spcr(kind u8) {
	unsafe { C.memset(&acpi_data[0], 0, 1024) }
	rsdp_response.address = voidptr(0x40)
	firmware_rsdp_req.response = unsafe { &rsdp_response }
	acpi_data[0x40 + 15] = 2
	store64(0x40 + 24, 0x80)
	text_at(0x80, 'XSDT')
	store32(0x80 + 4, 44)
	text_at(0x80 + 10, 'BOCHS')
	store64(0x80 + 36, 0x100)
	text_at(0x100, 'SPCR')
	store32(0x100 + 4, 80)
	acpi_data[0x100 + 36] = kind
	store64(0x100 + 44, 0x09000000)
}

fn check_firmware() {
	fake_higher_half = 0 // Exercise Limine offset before PMM.
	firmware_rsdp_req.response = unsafe { nil }
	C.assert((boot_console_uart(false) or { u64(0) }) == 0)
	C.assert((boot_console_uart(true) or { u64(0) }) == 0x09000000)
	acpi_spcr(3)
	C.assert(is_qemu())
	C.assert((boot_console_uart(false) or { u64(0) }) == 0x09000000)
	acpi_spcr(0xe)
	C.assert((console_uart() or { u64(0) }) == 0x09000000)
	acpi_spcr(0) // 16550 is not PL011.
	C.assert((boot_console_uart(false) or { u64(0) }) == 0)
	acpi_spcr(3)
	acpi_data[0x100 + 40] = 1 // I/O space is not MMIO.
	C.assert((console_uart() or { u64(0) }) == 0)
	acpi_spcr(3)
	store32(0x100 + 4, 51)
	C.assert((console_uart() or { u64(0) }) == 0)
	acpi_spcr(3)
	store64(0x100 + 44, 0)
	C.assert((console_uart() or { u64(0) }) == 0)
	// VirtualBox-style DSDT fallback, with no SPCR.
	store64(0x80 + 36, 0x200)
	text_at(0x200, 'FACP')
	store32(0x200 + 4, 148)
	store64(0x200 + 140, 0x300)
	text_at(0x300, 'DSDT')
	store32(0x300 + 4, 80)
	text_at(0x300 + 36, 'ARMH0011')
	acpi_data[0x300 + 60] = 0x86
	acpi_data[0x300 + 61] = 9
	store32(0x300 + 64, 0x12340000)
	C.assert((boot_console_uart(false) or { u64(0) }) == 0x12340000)
	fake_higher_half = test_bootloader_hhdm_offset()
	C.assert((boot_console_uart(false) or { u64(0) }) == 0x12340000)
}

@[export: 'main']
pub fn run() i32 {
	// Deliberately run before _vinit, exactly as the kernel does.
	kio.setup(0, 0)
	early_initialise()
	C.assert(com1_present && kio.ier() == 0 && kio.scratch() == 0x19)
	panic_out(`E`)
	reset_mmio(0, 0)
	putc(`E`)
	flags = 0x20
	putc(`X`)
	C.assert(uart_tx_failed)
	check_firmware()
	C._vinit(0, unsafe { nil })
	C.assert(com1_present && get_base() == 0x1000 && uart_tx_failed)
	panic_out(`\n`)
	C.assert(kio.size() == 3 && kio.byte_at(0) == `E`
		&& kio.byte_at(1) == `\r` && kio.byte_at(2) == `\n`)
	flags = 0
	initialise(0x1000)
	putc(`R`)
	C.assert(mmio_len == 2 && mmio_output[1] == `R`)
	check_firmware()

	kio.setup(0, 3)
	early_initialise()
	kwrite(charptr(c'A\n'), 2)
	C.assert(kio.reads() == 6 && kio.size() == 3)
	C.assert(kio.byte_at(0) == `A` && kio.byte_at(1) == `\r` && kio.byte_at(2) == `\n`)
	C.assert(terminal_len == 2 && terminal_bytes[0] == `A` && terminal_bytes[1] == `\n` && logged == 2)
	for fixture_mode in 1 .. 4 {
		kio.setup(fixture_mode, 0)
		early_initialise()
		out(`X`)
		panic_out(`\n`)
		C.assert(kio.size() == 0 && (!com1_present || com1_tx_failed))
		C.assert(com1_present == (fixture_mode != 1))
		C.assert(kio.reads() == if fixture_mode == 1 { 0 } else if fixture_mode == 2 { 65536 } else { 1 })
		// Framebuffer and bootlog must still receive output after TX failed.
		kwrite(charptr(c'F'), 1)
		C.assert(terminal_len == 1 && terminal_bytes[0] == `F`)
		if fixture_mode == 2 {
			enable_port_interrupts(0x3f8)
			C.assert(kio.ier() == 1 && com1_tx_failed)
		}
	}
	kio.setup(0, 0)
	early_initialise()
	C.assert(kio.ier() == 0)
	enable_port_interrupts(0x3f8)
	C.assert(kio.ier() == 1)
	kio.setup(2, 0)
	out(`X`)
	C.assert(com1_tx_failed)
	kio.setup(0, 0)
	C.assert(resume() == 1 && kio.ier() == 1 && com1_present && !com1_tx_failed)
	panic_out(`R`)
	C.assert(kio.size() == 1 && kio.byte_at(0) == `R`)

	initialise(0)
	mmio_reads = 0
	putc(`X`)
	C.assert(mmio_reads == 0)
	reset_mmio(0, 3)
	write(charptr(c'A\n'), 2)
	C.assert(mmio_reads == 6 && mmio_len == 3 && mmio_output[0] == `A`
		&& mmio_output[1] == `\r` && mmio_output[2] == `\n`)
	reset_mmio(0x20, 0)
	putc(`X`)
	write(charptr(c'ignored\n'), 8)
	C.assert(mmio_reads == 65536 && mmio_len == 0)
	reset_mmio(0xffffffff, 0)
	putc(`X`)
	putc(`Y`)
	C.assert(mmio_reads == 1 && mmio_len == 0)
	reset_mmio(0, 0)
	putc(`R`)
	C.assert(mmio_len == 1 && mmio_output[0] == `R`)
	return 0
}
