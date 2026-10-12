@[has_globals]
module devcore

pub const microsecond = u64(1000)
pub const millisecond = u64(1000000)
pub const second = u64(1000000000)

__global (
	clock            u64
	bound            Driver
	pub last_command u16
)

pub enum Bus {
	pci
}

pub struct Bar {
pub:
	base    u64  = 0x1000
	size    u64  = 256
	is_mmio bool = true
}

pub struct PCI {
pub:
	bus      u8
	slot     u8
	function u8
pub mut:
	command u16 = 7 // firmware left decoding and bus mastering enabled
}

pub fn (p &PCI) capability(kind u8) u16 { return 0 }

pub fn (p &PCI) read[T](offset u32) T { return T(p.command) }

pub fn (mut p PCI) write[T](offset u32, value T) {
	p.command = u16(value)
	last_command = p.command
}

pub fn (mut p PCI) update_command(clear u16, set u16) {
	p.command = (p.command & ~clear) | set
	last_command = p.command
}

pub fn (p &PCI) get_bar(index u8) Bar { return Bar{} }

pub struct Device {
pub mut:
	bus    Bus = .pci
	vendor u16 = 0x10ec
	device u16 = 0x8168
	pci    PCI
}

pub struct Driver {
pub:
	name     string
	bus      Bus
	matches  fn (&Device) bool    = unsafe { nil }
	probe    fn (mut Device) bool = unsafe { nil }
	remove   fn (mut Device)      = unsafe { nil }
	suspend  fn (mut Device) bool = unsafe { nil }
	resume   fn (mut Device) bool = unsafe { nil }
	shutdown fn (mut Device)      = unsafe { nil }
	reset    fn (mut Device) bool = unsafe { nil }
}

pub fn register_driver(d Driver) ! { bound = d }

pub struct Deadline {
	start u64
	limit u64
}

pub fn deadline(ns u64) Deadline { return Deadline{now_ns(), ns} }

pub fn (d Deadline) expired() bool { return now_ns() - d.start >= d.limit }

pub fn now_ns() u64 {
	clock += millisecond
	return clock
}

pub fn stall(ns u64) { clock += ns }

pub fn sleep_ms(ms u64) { clock += ms * millisecond }
