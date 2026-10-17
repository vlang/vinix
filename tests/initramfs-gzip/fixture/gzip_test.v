// SPDX-License-Identifier: GPL-2.0-or-later
module initramfs

import os
import rand
import time

fn gzip_test_dir() string {
	dir := os.join_path(os.temp_dir(), 'vinix-gzip-cases-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

fn gzip_test_compress(path string, level string, keep_name bool) []u8 {
	mut args := ['gzip', '-c', level]
	if !keep_name {
		args << '-n'
	}
	args << path
	out := os.exec(args)
	assert out.exit_code == 0, out.output
	return out.output.bytes()
}

// Inflate `compressed` and return the result, or none if the decoder refuses it.
fn gzip_test_inflate(compressed []u8) ?[]u8 {
	member := gzip_member(compressed.data, u64(compressed.len)) or { return none }
	mut output := []u8{len: int(member.size)}
	mut d := &Inflater{}
	if !d.gunzip(compressed.data, u64(compressed.len), member, output.data) {
		return none
	}
	return output
}

fn gzip_test_round_trip(name string, data []u8) {
	dir := gzip_test_dir()
	path := os.join_path(dir, name)
	os.write_file_array(path, data) or { panic(err) }
	for level in ['-1', '-6', '-9'] {
		for keep_name in [false, true] {
			compressed := gzip_test_compress(path, level, keep_name)
			inflated := gzip_test_inflate(compressed) or {
				assert false, '${name} ${level} name=${keep_name}: refused'
				return
			}
			assert inflated == data, '${name} ${level} name=${keep_name}: differs'
		}
	}
}

fn test_text_and_repeats() {
	mut text := []u8{}
	for i in 0 .. 20000 {
		text << 'line ${i}: the quick brown fox jumps over the lazy dog\n'.bytes()
	}
	gzip_test_round_trip('text', text)
	gzip_test_round_trip('zeros', []u8{len: 3 * 1024 * 1024})
	gzip_test_round_trip('one-byte', [u8(65)])
	gzip_test_round_trip('empty', []u8{})
	mut runs := []u8{}
	for i in 0 .. 400000 {
		runs << u8((i / 7) % 3)
	}
	gzip_test_round_trip('runs', runs)
}

fn test_incompressible_data_uses_stored_blocks() {
	mut random := []u8{len: 2 * 1024 * 1024 + 123}
	for i in 0 .. random.len {
		random[i] = u8(rand.intn(256) or { 0 })
	}
	gzip_test_round_trip('random', random)
	mut mixed := []u8{}
	for i in 0 .. 64 {
		mixed << random[i * 1000..i * 1000 + 700]
		mixed << []u8{len: 3000, init: u8(i)}
	}
	gzip_test_round_trip('mixed', mixed)
}

fn test_real_tar_archive() {
	dir := gzip_test_dir()
	tar := os.join_path(dir, 'tree.tar')
	out := os.exec(['tar', '-cf', tar, '-C', os.dir(@FILE), '.'])
	assert out.exit_code == 0, out.output
	data := os.read_bytes(tar) or { panic(err) }
	gzip_test_round_trip('tree.tar', data)
}

fn test_comment_field_is_read_without_inflating() {
	dir := gzip_test_dir()
	path := os.join_path(dir, 'commented')
	os.write_file(path, 'payload '.repeat(1000)) or { panic(err) }
	plain := gzip_test_compress(path, '-9', false)
	// Set FCOMMENT and insert the comment after the fixed ten-byte header, as
	// the ISO scripts do.
	mut commented := plain[0..10].clone()
	commented[3] = 0x10
	commented << 'vinix-image-id=0123456789abcdef'.bytes()
	commented << u8(0)
	commented << plain[10..]
	member := gzip_member(commented.data, u64(commented.len)) or {
		assert false, 'commented header refused'
		return
	}
	comment := commented[int(member.comment_offset)..int(member.comment_offset + member.comment_length)].bytestr()
	assert comment == 'vinix-image-id=0123456789abcdef'
	inflated := gzip_test_inflate(commented) or {
		assert false, 'commented member refused'
		return
	}
	assert inflated.bytestr() == 'payload '.repeat(1000)
}

fn test_corruption_is_refused() {
	dir := gzip_test_dir()
	path := os.join_path(dir, 'victim')
	mut text := []u8{}
	for i in 0 .. 5000 {
		text << 'entry ${i} '.bytes()
	}
	os.write_file_array(path, text) or { panic(err) }
	good := gzip_test_compress(path, '-6', false)
	assert gzip_test_inflate(good) != none
	// A wrong CRC.
	mut bad_crc := good.clone()
	bad_crc[bad_crc.len - 8] ^= 0xff
	assert gzip_test_inflate(bad_crc) == none
	// A wrong recorded size.
	mut bad_size := good.clone()
	bad_size[bad_size.len - 4] ^= 0x01
	assert gzip_test_inflate(bad_size) == none
	// Truncated data.
	mut truncated := good[0..good.len / 2].clone()
	truncated << good[good.len - 8..]
	assert gzip_test_inflate(truncated) == none
	// Flipped bits inside the deflate stream: never a crash, and never the
	// original bytes claimed with a damaged stream.
	for i in 0 .. 200 {
		mut flipped := good.clone()
		at := 10 + (i * 37) % (good.len - 18)
		flipped[at] ^= u8(1 << (i % 8))
		if result := gzip_test_inflate(flipped) {
			assert result == text
		}
	}
	// Not gzip at all.
	assert gzip_member('hello world, not gzip'.bytes().data, 21) == none
}

fn test_sample_speed() {
	sample := os.getenv('VINIX_GZIP_SAMPLE')
	if sample == '' {
		return
	}
	data := os.read_bytes(sample) or { panic(err) }
	compressed := gzip_test_compress(sample, '-9', false)
	start := time.now()
	inflated := gzip_test_inflate(compressed) or {
		assert false, 'sample refused'
		return
	}
	elapsed := time.since(start)
	assert inflated == data
	println('inflated ${data.len / 1048576} MiB from ${compressed.len / 1048576} MiB in ${elapsed.milliseconds()} ms (${f64(data.len) / 1048576.0 / elapsed.seconds():.0f} MiB/s)')
}
