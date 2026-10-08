module appleadt

import dl
import g17decode as g
import math.big
import json2
import strconv
import traceanalysis as j

type CompressionDecode = fn (voidptr, usize, voidptr, usize, voidptr, i32) usize

pub const max_device_tree_bytes = u64(64 << 20)

pub fn is_compressed(payload []u8) bool {
	return payload.len >= 4 && payload[..4].bytestr() in ['bvx1', 'bvx2']
}

pub fn decompress(payload []u8, initial_capacity u64) ![]u8 {
	if !is_compressed(payload) { return payload }
	$if !macos {
		return error('LZFSE DeviceTree extraction requires macOS libcompression')
	}
	library := dl.open_opt('/usr/lib/libcompression.dylib', dl.rtld_lazy) or { return error('cannot load macOS libcompression: ${err}') }
	defer { dl.close(library) }
	address := dl.sym_opt(library, 'compression_decode_buffer')!
	decode := unsafe { CompressionDecode(address) }
	mut capacity := initial_capacity
	if capacity == 0 {
		capacity = u64(payload.len) * 4
		if capacity < 1 << 20 { capacity = 1 << 20 }
	}
	for capacity <= max_device_tree_bytes {
		buffer := unsafe { C.malloc(usize(capacity)) }
		if buffer == unsafe { nil } { return error('cannot allocate LZFSE DeviceTree buffer') }
		decoded := decode(buffer, usize(capacity), payload.data, usize(payload.len), unsafe { nil }, 0x801)
		if decoded == 0 {
			unsafe { C.free(buffer) }
			return error('macOS libcompression rejected the LZFSE DeviceTree payload')
		}
		if u64(decoded) < capacity {
			result := unsafe { (&u8(buffer)).vbytes(int(decoded)).clone() }
			unsafe { C.free(buffer) }
			return result
		}
		unsafe { C.free(buffer) }
		capacity *= 2
	}
	return error('decompressed DeviceTree exceeds the 64 MiB safety limit')
}

// Capture the optional Python capacity before converting it to size_t. Neither
// a rejected signed value nor a value above the safety bound is narrowed.
pub fn decompress_request(payload []u8, initial j.Value) ![]u8 {
	if !is_compressed(payload) { return payload }
	$if !macos {
		return error('LZFSE DeviceTree extraction requires macOS libcompression')
	}
	mut capacity := big.zero_int
	if initial !is json2.Null { capacity = g.integer(initial)! }
	if capacity < big.integer_from_i64(-9223372036854775807 - 1) {
		return error("OverflowError: cannot fit 'int' into an index-sized integer")
	}
	if capacity.signum < 0 {
		return error('Array length must be >= 0, not ${capacity.str()}')
	}
	if capacity > big.integer_from_u64(max_device_tree_bytes) {
		return error('decompressed DeviceTree exceeds the 64 MiB safety limit')
	}
	return decompress(payload, strconv.parse_uint(capacity.str(), 10, 64)!)
}
