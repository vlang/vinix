@[has_globals]
module serial

import x86.kio
import klock
import fs
import stat
import event
import event.eventstruct
import katomic
import resource
import file
import x86.idt
import x86.apic

// This are the IO ports where the serial COMs usually appear, this is not
// guaranteed tho, especially beyond the first 2, so we gotta check them all.
const com1_port = 0x3f8

const com_ports = [com1_port, 0x2f8, 0x3e8, 0x2e8]

// Serial devices share IRQs in pairs, COM1/3 use IRQ 4, COM2/4 use IRQ3
const com1_3_irq = 4

const com2_4_irq = 3

__global (
	com1_lock klock.Lock // Lock for COM1 kernel debug reporting.
)

// Fast initialization of COM1 for early kernel reporting.
pub fn early_initialise() {
	initialise_port(com1_port)
}

// Initialize the rest of ports apart of COM1.
pub fn initialise() {
	// Route the COM IRQs to vectors.
	com1_3_vector := idt.allocate_vector()
	com2_4_vector := idt.allocate_vector()
	apic.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, com1_3_vector, com1_3_irq, true)
	apic.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, com2_4_vector, com2_4_irq, true)

	// Add the hardcoded port 1.
	mut com1_res := &COMPort{}
	com1_res.stat.size = 0
	com1_res.stat.blocks = 0
	com1_res.stat.blksize = 512
	com1_res.stat.rdev = resource.create_dev_id()
	com1_res.stat.mode = 0o644 | stat.ifchr
	com1_res.status |= file.pollout
	com1_res.port = com1_port
	com1_res.port_vector = com1_3_vector
	fs.devtmpfs_add_device(com1_res, 'com1')

	// Add the rest of ports.
	for i in 1 .. com_ports.len {
		port := u16(com_ports[i])
		success := initialise_port(port)
		if success {
			// Construct and add device.
			mut com_res := &COMPort{}
			com_res.stat.size = 0
			com_res.stat.blocks = 0
			com_res.stat.blksize = 512
			com_res.stat.rdev = resource.create_dev_id()
			com_res.stat.mode = 0o644 | stat.ifchr
			com_res.status |= file.pollout
			com_res.port = port
			com_res.port_vector = if i % 2 == 0 { com1_3_vector } else { com2_4_vector }
			fs.devtmpfs_add_device(com_res, 'com${i + 1}')
		}
	}
}

// Initialize a port.
fn initialise_port(port u16) bool {
	// Check if the port exists by writing a value and checking it back.
	kio.port_out[u8](port + 7, 0x55)
	if kio.port_in[u8](port + 7) != 0x55 {
		return false
	}

	// Enable data available interrupts and enable DLAB.
	kio.port_out[u8](port + 1, 0x01)
	kio.port_out[u8](port + 3, 0x80)

	// Set divisor to low 1 hi 0 (115200 baud)
	kio.port_out[u8](port + 0, 0x01)
	kio.port_out[u8](port + 1, 0x00)

	// Enable FIFO and interrupts
	kio.port_out[u8](port + 3, 0x03)
	kio.port_out[u8](port + 2, 0xc7)
	kio.port_out[u8](port + 4, 0x0b)
	return true
}

// Kernel reporting to COM1.
pub fn out(value u8) {
	com1_lock.acquire()
	if value == `\n` {
		for !is_transmiter_empty(com1_port) {}
		kio.port_out[u8](com1_port, `\r`)
	}
	for !is_transmiter_empty(com1_port) {}
	kio.port_out[u8](com1_port, value)
	com1_lock.release()
}

// Unlocked COM1 reporting.
@[markused]
pub fn panic_out(value u8) {
	if value == `\n` {
		for !is_transmiter_empty(com1_port) {}
		kio.port_out[u8](com1_port, `\r`)
	}
	for !is_transmiter_empty(com1_port) {}
	kio.port_out[u8](com1_port, value)
}

fn is_transmiter_empty(port u16) bool {
	return kio.port_in[u8](port + 5) & 0b01000000 != 0
}

fn is_data_received(port u16) bool {
	return kio.port_in[u8](port + 5) & 0b00000001 != 0
}

// Resource functions for serial COMPort s
struct COMPort {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	port        u16
	port_vector int
}

fn (mut this COMPort) mmap(page u64, flags int) voidptr {
	return 0
}

fn (mut this COMPort) read(handle voidptr, void_buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}

	// Wait on the event of the port's IRQ.
	mut data := &u8(void_buf)
	mut events := [&int_events[this.port_vector]]
	defer {
		unsafe { events.free() }
	}
	for i := u64(0); i < count; {
		if is_data_received(this.port) {
			val := kio.port_in[u8](this.port)
			unsafe {
				data[i] = val
			}
			i++
		} else {
			event.await(mut events, true) or {}
		}
	}

	return i64(count)
}

fn (mut this COMPort) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}
	mut data := &u8(buf)
	for i in 0 .. count {
		for !is_transmiter_empty(this.port) {}
		kio.port_out[u8](this.port, unsafe { data[i] })
	}
	return i64(count)
}

fn (mut this COMPort) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this COMPort) unref(handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this COMPort) link(handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this COMPort) unlink(handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this COMPort) grow(handle voidptr, new_size u64) ? {
	return none
}
