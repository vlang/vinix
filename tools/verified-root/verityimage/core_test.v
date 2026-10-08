// SPDX-License-Identifier: GPL-2.0-or-later
module verityimage

import os

fn fixture(path string, blocks int) ! {
	mut output := os.create(path)!
	defer { output.close() }
	mut block := []u8{len: block_size}
	for index in 0 .. blocks {
		for byte_index in 0 .. block.len {
			block[byte_index] = u8(u64(index) >> ((byte_index % 8) * 8))
		}
		write_all(mut output, block)!
	}
}

fn expect_invalid(operation fn () !) {
	mut failed := false
	operation() or {
		assert err is InvalidImage
		failed = true
	}
	assert failed
}

fn test_known_tree_geometry_and_one_block_root() {
	assert layout(1)! == []Level{}
	assert layout(2)! == [Level{2, 1}]
	assert layout(128)! == [Level{128, 1}]
	assert layout(129)! == [Level{130, 2}, Level{129, 1}]
	assert layout(16384)! == [Level{16385, 128}, Level{16384, 1}]
	assert layout(16385)! == [Level{16388, 129}, Level{16386, 2}, Level{16385, 1}]
	work := private_dir(os.temp_dir())!
	defer { os.rmdir_all(work) or { panic(err) } }
	data := os.join_path(work, 'data')
	image := os.join_path(work, 'image')
	os.write_file_array(data, []u8{len: block_size, init: `x`})!
	metadata := build(data, image, false)!
	assert metadata.root_hash == hash_block(os.read_bytes(data)!).hex()
	assert os.read_bytes(image)! == os.read_bytes(data)!
}

fn test_deterministic_root_first_tree_and_boundaries() {
	work := private_dir(os.temp_dir())!
	defer { os.rmdir_all(work) or { panic(err) } }
	for blocks in [2, 128, 129, 16384, 16385] {
		data := os.join_path(work, 'data-${blocks}')
		image := os.join_path(work, 'image-${blocks}')
		replica := os.join_path(work, 'replica-${blocks}')
		fixture(data, blocks)!
		metadata := build(data, image, false)!
		verify(image, u64(blocks), metadata.root_hash)!
		assert build(data, replica, false)! == metadata
		assert os.read_bytes(image)! == os.read_bytes(replica)!
		mut stream := os.open(image)!
		mut block := []u8{len: block_size}
		read_block(mut stream, u64(blocks), mut block) or {
			stream.close()
			panic(err)
		}
		stream.close()
		assert hash_block(block).hex() == metadata.root_hash
		token := command_line('/dev/vda', u64(blocks), metadata.root_hash)!
		assert parse_command_line(token)! == Policy{'/dev/vda', u64(blocks), metadata.root_hash}
		// Each independent boundary is complete; retire its private fixtures.
		os.rm(data)!
		os.rm(image)!
		os.rm(replica)!
	}
}

fn test_tamper_every_level_data_padding_size_and_root() {
	work := private_dir(os.temp_dir())!
	defer { os.rmdir_all(work) or { panic(err) } }
	data := os.join_path(work, 'data')
	valid := os.join_path(work, 'valid')
	image := os.join_path(work, 'bad')
	fixture(data, 16385)!
	metadata := build(data, valid, false)!
	mut offsets := [u64(0), 128 * block_size, 16384 * block_size]
	for level in layout(16385)! { offsets << level.offset * block_size }
	offsets << (16388 + 128) * block_size + 32
	for offset in offsets {
		os.cp(valid, image)!
		mut stream := os.open_file(image, 'r+b')!
		stream.seek(i64(offset), .start)!
		mut byte := []u8{len: 1}
		assert stream.read(mut byte)! == 1
		byte[0] ^= 1
		stream.seek(i64(offset), .start)!
		write_all(mut stream, byte)!
		stream.close()
		expect_invalid(fn [image, metadata] () ! { verify(image, 16385, metadata.root_hash)! })
	}
	for size in [u64(0), 4095, metadata.image_bytes - 1, metadata.image_bytes - block_size,
		metadata.image_bytes + 1, metadata.image_bytes + block_size] {
		os.cp(valid, image)!
		mut stream := os.open_file(image, 'r+b')!
		assert C.ftruncate(i32(stream.fd), i64(size)) == 0
		stream.close()
		expect_invalid(fn [image, metadata] () ! { verify(image, 16385, metadata.root_hash)! })
	}
	expect_invalid(fn [valid] () ! { verify(valid, 16385, '0'.repeat(64))! })
	expect_invalid(fn [valid, metadata] () ! { verify(valid, 16384, metadata.root_hash)! })
	mut stream := os.open_file(data, 'r+b')!
	write_all(mut stream, [`!`])!
	stream.close()
	attacker_path := os.join_path(work, 'attacker')
	attacker := build(data, attacker_path, false)!
	assert attacker.root_hash != metadata.root_hash
	expect_invalid(fn [attacker_path, metadata] () ! {
		verify(attacker_path, 16385, metadata.root_hash)!
	})
}

fn test_input_and_policy_validation() {
	for blocks in [u64(0), max_bytes / block_size, (max_bytes + 1) / block_size] {
		expect_invalid(fn [blocks] () ! { layout(blocks)! })
	}
	for request in ['0', '-1', 'true', '"1"', '9223372036854775808', '18446744073709551616'] {
		expect_invalid(fn [request] () ! {
			query('{"operation":"layout","data_blocks":' + request + '}')!
		})
	}
	for digest in ['', 'A'.repeat(64), 'z'.repeat(64), '0'.repeat(63), '0'.repeat(65)] {
		expect_invalid(fn [digest] () ! { root_hash(digest)! })
	}
	for device in ['/dev/../vda', '/dev/vda/child', '/dev/vda,2', 'vda', '/dev/-vda', '/dev/.vda'] {
		expect_invalid(fn [device] () ! { command_line(device, 2, '0'.repeat(64))! })
	}
	assert device_name('/dev/' + 'a'.repeat(63))! == '/dev/' + 'a'.repeat(63)
	expect_invalid(fn () ! { device_name('/dev/' + 'a'.repeat(64))! })
	for token in ['vinix.verity=2,/dev/vda,2,' + '0'.repeat(64),
		'vinix.verity=1,/dev/vda,02,' + '0'.repeat(64), 'vinix.verity=1,/dev/vda,2,' + 'A'.repeat(64),
		'x=vinix.verity=1,/dev/vda,2,' + '0'.repeat(64)] {
		expect_invalid(fn [token] () ! { parse_command_line(token)! })
	}
	work := private_dir(os.temp_dir())!
	defer { os.rmdir_all(work) or { panic(err) } }
	data := os.join_path(work, 'data')
	image := os.join_path(work, 'image')
	for value in ['', 'x'] {
		os.write_file(data, value)!
		expect_invalid(fn [data, image] () ! { build(data, image, false)! })
	}
	metadata := build(data, image, true)!
	assert metadata.data_blocks == 1
	mut padded := []u8{len: 4096}
	padded[0] = `x`
	assert os.read_bytes(image)! == padded
	expect_invalid(fn [data, image] () ! { build(data, image, true)! })
	link := os.join_path(work, 'link')
	os.symlink(image, link)!
	expect_invalid(fn [link, metadata] () ! { verify(link, 1, metadata.root_hash)! })
}
