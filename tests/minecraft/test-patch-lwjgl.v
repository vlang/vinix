// SPDX-License-Identifier: GPL-2.0-or-later
import bundlehost as bh
import compress.szip
import encoding.binary
import lwjglpatch
import os

fn words(values []u32) []u8 {
	mut bytes := []u8{}
	for value in values { bytes << binary.little_endian_get_u32(value) }
	return bytes
}

fn rejected(data []u8, expected string) ! {
	mut found := false
	lwjglpatch.patch_native(data) or {
		assert err.msg().contains(expected)
		found = true
		return
	}
	assert found
}

fn native() ! {
	for sizes in [[u32(0xd2820003), 0xd2820001], [u32(0xd2820023), 0xd2820021]] {
		original := words([sizes[0], 0x52800022, 0xaa0303e1, 0xaa1503e0, 0x97ff4a7d])
		mut input := []u8{len: 8}
		input << original
		input << []u8{len: 8}
		actual, changed := lwjglpatch.patch_native(input)!
		assert changed && actual[..8] == input[..8] && actual[28..] == input[28..]
		assert actual[8..28] == words([sizes[1], 0xaa0403e2, 0x2a0503e3, 0xaa1503e0, 0x97ff4a79])
		repeat, rechanged := lwjglpatch.patch_native(actual)!
		assert !rechanged && repeat == actual
		mut duplicate := original.clone()
		duplicate << original
		rejected(duplicate, 'found 2')!
		mut misaligned := [u8(0)]
		misaligned << original
		rejected(misaligned, 'not found')!
	}
	for size in 0 .. 20 { rejected([]u8{len: size}, 'not found')! }
	println('PASS both libffi buffer sizes, exact five-instruction rewrite, idempotence, ambiguity/alignment and short input')
}

fn archive(path string, name string, native []u8) ! {
	mut zip := szip.open(path, .best_compression, .write)!
	defer { zip.close() }
	for entry in [[name, ''], ['META-INF/fixture.txt', 'unchanged metadata fixture']] {
		zip.open_entry(entry[0])!
		bytes := if entry[0] == name { native } else { entry[1].bytes() }
		zip.write_entry(bytes) or {
			zip.close_entry()
			return err
		}
		zip.close_entry()
	}
}

fn payload(path string, name string) ![]u8 {
	mut zip := szip.open(path, .default_compression, .read_only)!
	defer { zip.close() }
	zip.open_entry(name)!
	defer { zip.close_entry() }
	mut buffer := []u8{len: int(zip.size())}
	assert zip.read_entry_buf(buffer.data, buffer.len)! == buffer.len
	return buffer
}

fn jars(work string) ! {
	original := words([u32(0xd2820003), 0x52800022, 0xaa0303e1, 0xaa1503e0, 0x97ff4a7d])
	name := 'linux/arm64/org/lwjgl/liblwjgl.so'
	path := work + '/native.jar'
	archive(path, name, original)!
	assert lwjglpatch.patch_jar(path)!
	assert payload(path, name)! == words([u32(0xd2820001), 0xaa0403e2, 0x2a0503e3, 0xaa1503e0,
		0x97ff4a79])
	assert payload(path, 'META-INF/fixture.txt')!.bytestr() == 'unchanged metadata fixture'
	first := os.read_bytes(path)!
	assert !lwjglpatch.patch_jar(path)! && os.read_bytes(path)! == first
	archive(work + '/wrong.jar', 'other.so', original)!
	for candidate in ['wrong.jar', 'broken.jar', 'ambiguous.jar'] {
		if candidate == 'broken.jar' { os.write_file(work + '/' + candidate, 'not a ZIP')! }
		if candidate == 'ambiguous.jar' {
			mut repeated := original.clone()
			repeated << original
			archive(work + '/' + candidate, name, repeated)!
		}
		before := os.read_bytes(work + '/' + candidate)!
		mut rejected := false
		lwjglpatch.patch_jar(work + '/' + candidate) or { rejected = true }
		assert rejected && os.read_bytes(work + '/' + candidate)! == before
	}
	for path_name in os.walk_ext(work, '') {
		assert !path_name.contains('.minecraft-patch-')
	}
	println('PASS independently produced/read JAR payloads, other entries, idempotence and atomic rejection')
}

fn main() {
	work := bh.temporary(os.temp_dir(), 'vinix-lwjgl-tests-') or { panic(err) }
	defer { bh.retire(work) }
	native() or { panic(err) }
	jars(work) or { panic(err) }
	println('LWJGL PATCH NATIVE PASS')
}
