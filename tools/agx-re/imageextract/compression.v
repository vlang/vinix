module imageextract

import dl

type CompressionDecode = fn (voidptr, usize, voidptr, usize, voidptr, i32) usize

pub fn decompress_kernel(payload []u8, initial_capacity u64) ![]u8 {
	if payload.len >= 4 && u32_at(payload, 0) == macho_magic_64 { return payload }
	if payload.len < 4 || payload[..4].bytestr() !in ['bvx1', 'bvx2'] {
		return error('unsupported kernel compression magic ${bytes_repr(payload[..if payload.len < 4 {
			payload.len
		} else {
			4
		}])}')
	}
	$if !macos {
		return error('LZFSE kernel extraction currently requires macOS libcompression')
	}
	library := dl.open_opt('/usr/lib/libcompression.dylib', dl.rtld_lazy) or {
		return error('cannot load macOS libcompression: ${err}')
	}
	defer { dl.close(library) }
	address := dl.sym_opt(library, 'compression_decode_buffer')!
	decode := unsafe { CompressionDecode(address) }
	mut capacity := initial_capacity
	if capacity == 0 {
		capacity = u64(payload.len) * 4
		if capacity < 64 << 20 { capacity = 64 << 20 }
	}
	for capacity <= 1 << 30 {
		// Every unsuccessful capacity is explicitly released before growing.
		// The returned image owns a V buffer independent of the decoder scratch.
		buffer := unsafe { C.malloc(usize(capacity)) }
		if buffer == unsafe { nil } { return error('cannot allocate LZFSE kernel buffer') }
		decoded := decode(buffer, usize(capacity), payload.data, usize(payload.len),
			unsafe { nil }, 0x801)
		if decoded == 0 {
			unsafe { C.free(buffer) }
			return error('macOS libcompression rejected the LZFSE kernel payload')
		}
		if u64(decoded) < capacity {
			image := unsafe { (&u8(buffer)).vbytes(int(decoded)).clone() }
			unsafe { C.free(buffer) }
			if image.len < 4 || u32_at(image, 0) != macho_magic_64 {
				return error('decompressed kernel collection is not a Mach-O')
			}
			return image
		}
		unsafe { C.free(buffer) }
		capacity *= 2
	}
	return error('decompressed kernel collection exceeds the 1 GiB safety limit')
}
