// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A native TLS key outlives individual Mach-O images. Its destructor is libc's
// resident free(), so thread exit never calls through an unloaded app image.
__global error_buffer_key = u64(0)
__global error_buffer_key_ready = false

fn error_buffer() &char {
	C.ios_objc_initialize_lock()
	if !error_buffer_key_ready {
		result := C.ios_key_create(unsafe { &error_buffer_key }, unsafe { voidptr(C.free) })
		if result != 0 {
			C.ios_objc_initialize_unlock()
			darwin_set_errno(darwin_native_error(result))
			return unsafe { nil }
		}
		error_buffer_key_ready = true
	}
	key := usize(error_buffer_key)
	C.ios_objc_initialize_unlock()
	mut buffer := C.pthread_getspecific(key)
	if buffer == unsafe { nil } {
		buffer = C.malloc(128)
		if buffer == unsafe { nil } {
			darwin_set_errno(12)
			return unsafe { nil }
		}
		result := C.pthread_setspecific(key, buffer)
		if result != 0 {
			C.free(buffer)
			darwin_set_errno(darwin_native_error(result))
			return unsafe { nil }
		}
	}
	return unsafe { &char(buffer) }
}

fn error_message(number i32, scratch &u8) &char {
	if number >= 0 && number < darwin_error_messages.len {
		return darwin_error_messages[number]
	}
	// The complete signed 32-bit unknown-error message fits in 27 bytes.
	// Convert through i64 so INT_MIN can be negated without overflow.
	C.memcpy(scratch, c'Unknown error: ', 15)
	mut offset := 15
	mut magnitude := u64(if number < 0 { -i64(number) } else { i64(number) })
	if number < 0 {
		unsafe { scratch[offset] = `-` }
		offset++
	}
	mut digits := [10]u8{}
	mut count := 0
	for {
		digits[count] = u8(magnitude % 10) + `0`
		count++
		magnitude /= 10
		if magnitude == 0 { break }
	}
	for count > 0 {
		count--
		unsafe { scratch[offset] = digits[count] }
		offset++
	}
	unsafe { scratch[offset] = 0 }
	return unsafe { &char(scratch) }
}

fn darwin_strerror_r(number i32, buffer &char, capacity usize) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	// A nonzero length with no destination is not a valid string buffer.
	if buffer == unsafe { nil } && capacity != 0 { return 22 }
	scratch := unsafe { &u8(C.__builtin_alloca(32)) }
	message := error_message(number, scratch)
	length := darwin_strlen(message)
	if capacity != 0 {
		copied := if length < capacity { length } else { capacity - 1 }
		C.memcpy(buffer, message, copied)
		unsafe { buffer[copied] = 0 }
	}
	// Invalid error numbers take precedence over truncation, as on Darwin.
	if number < 0 || number >= darwin_error_messages.len { return 22 }
	return if capacity <= length { i32(34) } else { i32(0) }
}

fn darwin_strerror(number i32) &char {
	previous := unsafe { *C.ios_errno_address() }
	buffer := error_buffer()
	if buffer == unsafe { nil } { return buffer }
	result := darwin_strerror_r(number, buffer, 128)
	darwin_set_errno(if result == 0 { previous } else { int(result) })
	return buffer
}

fn errors_symbol(symbol string) ?u64 {
	return match symbol {
		'_strerror' { u64(unsafe { voidptr(darwin_strerror) }) }
		'_strerror_r' { u64(unsafe { voidptr(darwin_strerror_r) }) }
		else { return none }
	}
}
