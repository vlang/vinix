module random

import resource
import fs
import stat
import klock
import event.eventstruct
import memory
import x86.cpu

__global (
	ur_initialized = false
	ur_rdrand = false
	ur_rdseed = false
)

struct URandom {
mut:
	stat       stat.Stat
	refcount   int
	l          klock.Lock
	event      eventstruct.Event
	status     int
	can_mmap   bool
	rng_lock   klock.Lock
	buffer     [16]u32
	key        [16]u32
	reseed_ctr u64
}

[inline]
fn rotl32(a u32, shift u32) u32 {
	return ((a) << (shift)) | ((a) >> (32 - (shift)))
}

[inline]
fn qr(a &u32, b &u32, c &u32, d &u32) {
	unsafe {
		*b = *b ^ rotl32(*a + *d, 7)
		*c = *c ^ rotl32(*b + *a, 9)
		*d = *d ^ rotl32(*c + *b, 13)
		*a = *a ^ rotl32(*d + *c, 18)
	}
}

// not threadsafe!
fn (mut this URandom) do_salsa20_block(mut out [16]u32) {
	mut x := [16]u32{}
	for i := 0; i < 16; i++ {
		x[i] = this.buffer[i]
	}

	for i := 0; i < 10; i++ {
		qr(&x[0], &x[4], &x[8], &x[12])
		qr(&x[5], &x[9], &x[13], &x[1])
		qr(&x[10], &x[14], &x[2], &x[6])
		qr(&x[15], &x[3], &x[7], &x[11])

		qr(&x[0], &x[1], &x[2], &x[3])
		qr(&x[5], &x[6], &x[7], &x[4])
		qr(&x[10], &x[11], &x[8], &x[9])
		qr(&x[15], &x[12], &x[13], &x[14])
	}

	for i := 0; i < 16; i++ {
		out[i] = x[i] + this.key[i]
	}

	for i := 0; i < 16; i++ {
		this.buffer[i] = x[i]
	}
}

fn (mut this URandom) mmap(page u64, flags int) voidptr {
	return memory.pmm_alloc(1)
}

fn (mut this URandom) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if count == 0 {
		return i64(0)
	}

	this.rng_lock.acquire()
	
	mut cnt := count
	mut out := [16]u32{}
	mut cbuf := buf

	this.reseed_ctr += cnt
	if this.reseed_ctr >= 2048 {
		this.reseed_ctr = 0
		this.reseed()
	}

	for {
		unsafe {
			if cnt > 64 {
				this.do_salsa20_block(mut out)
				C.memcpy(cbuf, voidptr(&out[0]), 64)
				cbuf = voidptr(u64(cbuf) + u64(64))
				cnt -= 64
			} else {
				this.do_salsa20_block(mut out)
				C.memcpy(cbuf, voidptr(&out[0]), cnt)
				break
			}
		}
	}

	this.rng_lock.release()

	return i64(count)
}

fn (mut this URandom) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return i64(count)
}

fn (mut this URandom) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this URandom) unref(handle voidptr) ? {
	this.refcount--
}

fn (mut this URandom) grow(handle voidptr, new_size u64) ? {
}

fn (mut this URandom) reseed() {
	if ur_rdseed {
		for i in 0..this.key.len {
			this.key[i] ^= cpu.rdseed32()
		}
	} else if ur_rdrand {
		for i in 0..this.key.len {
			this.key[i] ^= cpu.rdrand32()
		}
	}
}

fn init_urandom() {
	mut success, _, mut b, mut c, _ := cpu.cpuid(1, 0)
	if success && (c & (1 << 30)) != 0 {
		println('urandom: rdrand available')
		ur_rdrand = true
	}

	success, _, b, _, _ = cpu.cpuid(0, 7)
	if success && (b & (1 << 18)) != 0 {
		println('urandom: rdseed available')
		ur_rdseed = true
	}

	// todo improve entropy via interrupts and other random events
	mut rng := &URandom{}

	rng.stat.size = 0
	rng.stat.blocks = 0
	rng.stat.blksize = 4096
	rng.stat.rdev = resource.create_dev_id()
	rng.stat.mode = 0o666 | stat.ifchr

	rng.can_mmap = true

	mut seed := cpu.rdtsc()
	rng.key[0] = u32(seed)
	rng.key[2] = u32(seed >> 32)
	seed = cpu.rdtsc()
	rng.buffer[0] = u32(seed)
	rng.buffer[2] = u32(seed >> 32)

	rng.reseed()

	fs.devtmpfs_add_device(rng, 'urandom')
}

pub fn initialise() {
	init_urandom()
}