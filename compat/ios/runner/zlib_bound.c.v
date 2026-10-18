// SPDX-License-Identifier: GPL-2.0-or-later
module main

// LP64 z_stream and the deflate-state prefix shared by Darwin zlib and the
// supplied musl zlib 1.3.2 backend. These are not inflate-state offsets. Native
// initialized-stream tests on both systems verify this private ABI dependency.
// No state is created here: streaming entry points still belong to the backend.
fn zlib_deflate_bound(stream voidptr, count u64) u64 {
	// Preserve Darwin unsigned-long overflow, including rounding additions.
	conservative := count + ((count + 7) >> 3) + ((count + 63) >> 6) + 5
	if stream == unsafe { nil } { return conservative + 6 }
	address := u64(stream)
	if read64(address + 64) == 0 || read64(address + 72) == 0 { return conservative + 6 }
	state := read64(address + 56)
	if state == 0 || read64(state) != address { return conservative + 6 }
	if read32(state + 8) !in [u32(42), 57, 69, 73, 91, 103, 113, 666]! { return conservative + 6 }
	mut wrapper := u64(6)
	match i32(read32(state + 48)) {
		0 { wrapper = 0 }
		1 { wrapper = if read32(state + 172) == 0 { u64(6) } else { u64(10) } }
		2 {
			wrapper = 18
			header := read64(state + 56)
			if header != 0 {
				if read64(header + 24) != 0 { wrapper += u32(read32(header + 32) + 2) }
				for offset in [u64(40), 56]! {
					text := read64(header + offset)
					if text != 0 { wrapper += u64(darwin_strlen(unsafe { &char(text) })) + 1 }
				}
				if read32(header + 68) != 0 { wrapper += 2 }
			}
		}
		else {}
	}
	if read32(state + 84) == 15 && read32(state + 136) == 15 {
		tight := zlib_compress_bound(count) - 6 + wrapper
		// Darwin 1.2.12 underestimates streams with a preset dictionary
		// (e.g. level 1, Z_FIXED, 64K random input). A bound may be larger:
		// retain the conservative estimate for this case so Z_FINISH fits.
		if read32(state + 48) in [u32(0), 1]! && read32(state + 172) != 0 && conservative + wrapper > tight {
			return conservative + wrapper
		}
		return tight
	}
	return conservative + wrapper
}

fn zlib_bound_symbol(symbol string) ?u64 {
	if symbol == '_deflateBound' { return u64(unsafe { voidptr(zlib_deflate_bound) }) }
	return none
}
