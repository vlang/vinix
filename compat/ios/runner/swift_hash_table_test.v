// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type HpPrevious = fn (u64, u64, u64) u64
type HpProbe = fn (u64, u64, u64, u64, u64, &u64)

const hp_export = '_$ss10_HashTableV12previousHole6beforeAB6BucketVAF_tF'

fn hp_call(entry u64, code u64, before u64, words u64, mask u64) u64 {
	mut output := [4]u64{}
	unsafe { HpProbe(voidptr(code))(before, words, mask, 0, entry, &output[0]) }
	assert output[2] == 0x5020 && output[3] == 0x5121
	return output[0]
}

// Independent per-bucket oracle: it does not share the runtime's word scan
// or leading-zero operation. Inputs here always contain a real hole.
fn hp_expected(before u64, words u64, mask u64) u64 {
	mut bucket := before
	for _ in u64(0) .. mask + 1 {
		bucket = (bucket - u64(1)) & mask
		if read64(words + (bucket >> 6) * 8) & (u64(1) << u32(bucket & 63)) == 0 { return bucket }
	}
	panic('test bitmap has no hole')
}

fn hp_exhaustive(entry u64, code u64) {
	call := unsafe { HpPrevious(voidptr(entry)) }
	mut word := u64(0)
	address := u64(unsafe { &word })
	for count in [u64(1), 2, 4, 8, 16]! {
		valid := (u64(1) << u32(count)) - 1
		for pattern in u64(0) .. valid {
			word = pattern | ~valid
			for before in u64(0) .. count {
				expected := hp_expected(before, address, count - 1)
				assert call(before, address, count - 1) == expected
				if pattern & 255 == 0 {
					assert hp_call(entry, code, before, address, count - 1) == expected
				}
			}
			assert word == pattern | ~valid
		}
	}
}

fn hp_guarded(entry u64, code u64) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page * 3) == 0 }
	for scale in u32(0) .. 16 {
		count := u64(1) << scale
		word_count := ((count - 1) >> 6) + 1
		bytes := word_count * 8
		assert bytes <= u64(page)
		for at_end in [false, true]! {
			words := span + u64(page) + if at_end { u64(page) - bytes } else { u64(0) }
			for hole in [u64(0), count / 2, count - 1]! {
				assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
				C.memset(voidptr(words), 0xff, usize(bytes))
				unsafe { *(&u64(words + (hole >> 6) * 8)) &= ~(u64(1) << u32(hole & 63)) }
				assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
				for before in [u64(0), count / 2, count - 1, hole]! {
					assert hp_call(entry, code, before, words, count - 1) == hole
				}
				for word in u64(0) .. word_count {
					for bit in [u64(0), 1, 63]! {
						before := word * 64 + bit
						if before < count {
							assert hp_call(entry, code, before, words, count - 1) == hole
						}
					}
				}
			}
			// Random bitmaps exercise many simultaneous holes and occupied runs
			// straddling word boundaries. Force valid padding and one real hole.
			mut random := u64(0x91e10da5c79e7b1d) ^ count
			for _ in 0 .. 16 {
				assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
				for word in u64(0) .. word_count {
					random ^= random << 13
					random ^= random >> 7
					random ^= random << 17
					unsafe { *(&u64(words + word * 8)) = random }
				}
				if count < 64 { unsafe { *(&u64(words)) |= ~((u64(1) << u32(count)) - 1) } }
				hole := random & (count - 1)
				unsafe { *(&u64(words + (hole >> 6) * 8)) &= ~(u64(1) << u32(hole & 63)) }
				assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
				for word in u64(0) .. word_count {
					before := (word * 64 + (random & 63)) & (count - 1)
					assert hp_call(entry, code, before, words, count - 1) == hp_expected(before, words, count - 1)
				}
			}
		}
	}
}

fn hp_bad() {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page) == 0 }
	for args in [[u64(0), 0, 63]!, [u64(0), span + 1, 63]!, [u64(64), span, 63]!, [u64(0), span,
		2]!, [u64(0), span, ~u64(0)]!, [u64(0), span, 0x7fffffffffffffff]!, [u64(0), ~u64(0) - 7,
		63]!, [~u64(0), span, 63]!]! {
		if _ := swift_hash_table_previous_checked(args[0], args[1], args[2]) {
			assert false
		}
	}
	assert C.mprotect(voidptr(span), page, C.PROT_READ | C.PROT_WRITE) == 0
	C.memset(voidptr(span), 0xff, page)
	assert C.mprotect(voidptr(span), page, C.PROT_READ) == 0
	for count in [u64(1), 2, 8, 16, 64, 128, u64(page) * 8]! {
		if _ := swift_hash_table_previous_checked(0, span, count - 1) {
			assert false
		}
	}
	assert C.mprotect(voidptr(span), page, C.PROT_READ | C.PROT_WRITE) == 0
	unsafe { *(&u64(span)) = 0 } // Invalid zero padding outside two buckets.
	assert C.mprotect(voidptr(span), page, C.PROT_READ) == 0
	if _ := swift_hash_table_previous_checked(1, span, 1) {
		assert false
	}
}

fn hp_worker(entry u64, code u64, words u64) u64 {
	for before in u64(0) .. 1024 {
		assert hp_call(entry, code, before & 63, words, 63) == 63
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', hp_export) or { panic(err) } == entry
	}
	return entry
}

fn test_swift_hash_table_previous_hole() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	defer { assert C.munmap(voidptr(code), page) == 0 }
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0x910003fd, 0xaa0503f3,
		u32(0xd2800000 | (0x5020 << 5) | 20), u32(0xd2800000 | (0x5121 << 5) | 21), 0xaa0403f0,
		0xd63f0200, 0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 60))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		assert core != unsafe { nil }
		entry := u64(C.dlsym(core, hp_export[1..].str))
		assert entry != 0
		hp_exhaustive(entry, code)
		hp_guarded(entry, code)
		println('NATIVE-HASH-PREVIOUS-HOLE: exhaustive one/two/four/eight/sixteen-bucket bitmaps, exclusive backward search and full-circle self holes, guarded readonly bitmaps through 32768 buckets, multiword/wrap/random cases and x20/x21')
	}
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', hp_export) == none
	for _ in 0 .. 2 {
		objc_start()
		entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', hp_export) or { panic(err) }
		assert entry == u64(unsafe { voidptr(swift_hash_table_previous) })
		hp_exhaustive(entry, code)
		hp_guarded(entry, code)
		hp_bad()
		mut word := u64(0x7fffffffffffffff)
		words := u64(unsafe { &word })
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn hp_worker(entry, code, words) }
		values := workers.wait()
		for value in values {
			assert value == entry
		}
		unsafe {
			values.free()
			workers.free()
		}
		assert word == 0x7fffffffffffffff
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', hp_export[1..]) == none
		assert runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', hp_export) == none
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', hp_export) == none
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss10_HashTableV8nextHole9atOrAfterAB6BucketVAF_tF') == none
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		ios_runtime.swift_concurrency_retired = true
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', hp_export) == none
		ios_runtime.swift_concurrency_retired = false
		objc_stop()
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', hp_export) == none
		// The direct intrinsic owns no runtime allocation; its existing code
		// pointer still operates on a valid caller-owned bitmap after teardown.
		assert hp_call(entry, code, 0, words, 63) == 63
	}
	println('IOS-HASH-PREVIOUS-HOLE: native backward-hole bitmap semantics and ARM64 ABI, exhaustive small tables, guarded readonly multiword scans, finite full/malformed rejection, allocation-free direct entry, eight concurrent readers and two empty teardowns')
}
