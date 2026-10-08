// SPDX-License-Identifier: GPL-2.0-or-later
// Headerless dm-verity-v1 images. Geometry and root authority come from the caller.
module verityimage

import os
import crypto.sha256
import encoding.hex

#include <sys/stat.h>
#include <stdlib.h>

fn C.fstat(i32, &C.stat) i32
fn C.mkdtemp(&char) &char
fn C.link(&char, &char) i32

pub const block_size = 4096
pub const digest_size = 32
pub const hashes_per_block = 128
pub const max_bytes = u64(0x7fffffffffffffff)
pub const format = 'dm-verity-v1-sha256-4096-no-salt-no-superblock'
pub const token_prefix = 'vinix.verity='

pub struct InvalidImage {
pub:
	message string
}

pub fn (e InvalidImage) msg() string { return e.message }

pub fn (e InvalidImage) code() int { return 0 }

fn invalid(message string) IError { return InvalidImage{message} }

pub struct FileError {
pub:
	message    string
	code_value int
	filename   string
	filename2  string
}

pub fn (e FileError) msg() string { return e.message }

pub fn (e FileError) code() int { return e.code_value }

fn file_error(path string, path2 string) IError {
	number := int(C.errno)
	return FileError{os.get_error_msg(number), number, path, path2}
}

fn open_file(path string) !os.File {
	return os.open(path) or { return file_error(path, '') }
}

fn create_file(path string) !os.File {
	return os.create(path) or { return file_error(path, '') }
}

pub struct Level {
pub:
	offset u64
	count  u64
}

pub fn layout(data_blocks u64) ![]Level {
	if data_blocks < 1 || data_blocks > max_bytes / block_size {
		return invalid('data block count must be a positive, bounded integer')
	}
	mut counts := []u64{}
	mut children := data_blocks
	for children > 1 {
		children = (children + hashes_per_block - 1) / hashes_per_block
		counts << children
	}
	mut position := data_blocks
	mut levels := []Level{}
	for count in counts.reverse() {
		levels << Level{position, count}
		position += count
	}
	if position > max_bytes / block_size {
		return invalid('data and hash tree exceed the supported device size')
	}
	return levels.reverse()
}

pub fn root_hash(value string) ![]u8 {
	if value.len != 64 || !value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
		return invalid('root hash must be exactly 64 lowercase hexadecimal digits')
	}
	return hex.decode(value)!
}

pub fn device_name(value string) !string {
	if !value.starts_with('/dev/') || value.len < 6 || value.len > 68 {
		return invalid('device must be an exact /dev block-device path')
	}
	name := value[5..]
	if !name[0].is_alnum() || !name.bytes().all(it.is_alnum() || it in [`_`, `.`, `-`]) {
		return invalid('device must be an exact /dev block-device path')
	}
	return value
}

pub fn command_line(device string, data_blocks u64, digest string) !string {
	layout(data_blocks)!
	root_hash(digest)!
	return '${token_prefix}1,${device_name(device)!},${data_blocks},${digest}'
}

pub struct Policy {
pub:
	device      string
	data_blocks u64
	digest      string
}

pub fn parse_command_line(token string) !Policy {
	parts := token.split(',')
	if parts.len != 4 || parts[0] != token_prefix + '1' || parts[2].len == 0 || (parts[2][0] < `1` || parts[2][0] > `9`) || !parts[2].bytes().all((it >= `0` && it <= `9`)) || parts[3].len != 64 || !parts[3].bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) || !parts[1].starts_with('/dev/') || parts[1].len == 5 || !parts[1][5..].bytes().all(it.is_alnum() || it in [
		`_`,
		`.`,
		`-`,
	]) {
		return invalid('invalid verified-root command-line token')
	}
	mut count := u64(0)
	for digit in parts[2].bytes() {
		if count > (u64(0xffffffffffffffff) - u64(digit - `0`)) / 10 {
			return invalid('data block count must be a positive, bounded integer')
		}
		count = count * 10 + u64(digit - `0`)
	}
	if command_line(parts[1], count, parts[3])! != token {
		return invalid('noncanonical verified-root command-line token')
	}
	return Policy{parts[1], count, parts[3]}
}

pub fn regular(path string) !string {
	if os.is_link(path) || !os.is_file(path) {
		return invalid('input must be a regular file, without a leaf symlink: ${path}')
	}
	return path
}

pub fn hash_block(data []u8) []u8 { return sha256.sum(data) }

pub fn total_blocks(data_blocks u64) !u64 {
	mut total := data_blocks
	for level in layout(data_blocks)! { total += level.count }
	return total
}

fn file_size(file os.File) !u64 {
	mut state := C.stat{}
	if C.fstat(i32(file.fd), &state) != 0 {
		return file_error('', '')
	}
	return u64(state.st_size)
}

fn read_block(mut file os.File, offset u64, mut buffer []u8) ! {
	file.seek(i64(offset * block_size), .start) or { return file_error('', '') }
	mut used := 0
	for used < buffer.len {
		count := file.read(mut buffer[used..]) or { if err is os.Eof {
			return invalid('short read at image block ${offset}')
		} else {
			return file_error('', '')
		} }
		if count == 0 { return invalid('short read at image block ${offset}') }
		used += count
	}
}

fn write_all(mut file os.File, data []u8) ! {
	unsafe { file.write_full_buffer(data.data, usize(data.len)) or { return file_error('', '') } }
}

pub fn verify(path string, data_blocks u64, digest string) ! {
	expected := root_hash(digest)!
	levels := layout(data_blocks)!
	regular(path)!
	expected_size := total_blocks(data_blocks)! * block_size
	mut stream := open_file(path)!
	defer { stream.close() }
	if file_size(stream)! != expected_size {
		return invalid('image size differs from its trusted data/tree geometry')
	}
	mut stored := []u8{len: block_size}
	mut child_data := []u8{len: block_size}
	if levels.len == 0 {
		read_block(mut stream, 0, mut child_data)!
		if hash_block(child_data) != expected {
			return invalid('data block 0 differs from the trusted root hash')
		}
		if file_size(stream)! != expected_size {
			return invalid('image size changed during verification')
		}
		return
	}
	mut children_offset := u64(0)
	mut children_count := data_blocks
	for level in levels {
		for index := u64(0); index < level.count; index++ {
			read_block(mut stream, level.offset + index, mut stored)!
			used := int(if children_count - index * hashes_per_block < hashes_per_block {
				children_count - index * hashes_per_block
			} else {
				u64(hashes_per_block)
			})
			for slot in 0 .. used {
				child := children_offset + index * hashes_per_block + u64(slot)
				read_block(mut stream, child, mut child_data)!
				if hash_block(child_data) != stored[slot * digest_size..(slot + 1) * digest_size] {
					return invalid('hash mismatch for image block ${child}')
				}
			}
			if stored[used * digest_size..].any(it != 0) {
				return invalid('nonzero unused hash slots in image block ${level.offset + index}')
			}
		}
		children_offset, children_count = level.offset, level.count
	}
	read_block(mut stream, levels.last().offset, mut child_data)!
	if hash_block(child_data) != expected {
		return invalid('hash tree differs from the trusted root hash')
	}
	if file_size(stream)! != expected_size {
		return invalid('image size changed during verification')
	}
}

pub struct Metadata {
pub:
	format       string
	data_blocks  u64
	root_hash    string
	block_size   u64
	tree_blocks  u64
	image_bytes  u64
	source_bytes u64
}

fn copy_file(mut incoming os.File, mut outgoing os.File) !u64 {
	mut buffer := []u8{len: 1024 * 1024}
	mut copied := u64(0)
	for {
		count := incoming.read(mut buffer) or { if err is os.Eof {
			break
		} else {
			return file_error('', '')
		} }
		if count == 0 { break }
		write_all(mut outgoing, buffer[..count])!
		copied += u64(count)
	}
	return copied
}

fn private_dir(parent string) !string {
	mut pattern := (os.join_path(parent, '.vinix-verity-XXXXXX') + '\x00').bytes()
	path := C.mkdtemp(&char(pattern.data))
	if path == unsafe { nil } {
		return file_error(os.join_path(parent, '.vinix-verity-XXXXXX'), '')
	}
	return unsafe { path.vstring().clone() }
}

pub fn build(source string, output_path string, pad bool) !Metadata {
	regular(source)!
	output := os.abs_path(output_path)
	if os.exists(output) || os.is_link(output) {
		return invalid('output already exists; choose a new image path')
	}
	os.mkdir_all(os.dir(output)) or { return file_error(os.dir(output), '') }
	size := (os.stat(source) or { return file_error(source, '') }).size
	if size == 0 || (size % block_size != 0 && !pad) {
		return invalid('data must be nonempty and 4096-byte aligned (or use --pad explicitly)')
	}
	// A filesystem size is a signed offset. Check before rounding up.
	if size > max_bytes { return invalid('data block count must be a positive, bounded integer') }
	data_blocks := (size + block_size - 1) / block_size
	levels := layout(data_blocks)!
	work := private_dir(os.dir(output))!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	image := os.join_path(work, 'image')
	{
		mut incoming := open_file(source)!
		defer { incoming.close() }
		mut outgoing := create_file(image)!
		defer { outgoing.close() }
		if copy_file(mut incoming, mut outgoing)! != size {
			return invalid('input size changed while copying')
		}
		padding := []u8{len: int(data_blocks * block_size - size)}
		write_all(mut outgoing, padding)!
	}
	mut digest := ''
	mut buffer := []u8{len: block_size}
	if levels.len == 0 {
		mut stream := open_file(image)!
		defer { stream.close() }
		read_block(mut stream, 0, mut buffer)!
		digest = hash_block(buffer).hex()
	} else {
		mut previous := image
		mut children := data_blocks
		mut files := []string{}
		for level_index, level in levels {
			current := os.join_path(work, 'level-${level_index}')
			{
				mut incoming := open_file(previous)!
				defer { incoming.close() }
				mut outgoing := create_file(current)!
				defer { outgoing.close() }
				mut hashes := []u8{len: block_size}
				for index := u64(0); index < level.count; index++ {
					for byte_index in 0 .. hashes.len { hashes[byte_index] = 0 }
					used := int(if children - index * hashes_per_block < hashes_per_block {
						children - index * hashes_per_block
					} else {
						u64(hashes_per_block)
					})
					for slot in 0 .. used {
						read_block(mut incoming, index * hashes_per_block + u64(slot), mut buffer) or { return invalid('short read while constructing hash tree') }
						hash := hash_block(buffer)
						for byte_index, byte in hash {
							hashes[slot * digest_size + byte_index] = byte
						}
					}
					write_all(mut outgoing, hashes)!
				}
			}
			files << current
			previous, children = current, level.count
		}
		{
			mut stream := open_file(previous)!
			defer { stream.close() }
			read_block(mut stream, 0, mut buffer)!
			digest = hash_block(buffer).hex()
		}
		{
			mut outgoing := os.open_file(image, 'ab') or { return file_error(image, '') }
			defer { outgoing.close() }
			for path in files.reverse() {
				mut incoming := open_file(path)!
				copy_file(mut incoming, mut outgoing) or {
					incoming.close()
					return err
				}
				incoming.close()
			}
		}
	}
	verify(image, data_blocks, digest)!
	// The private directory shares the output filesystem. link(2) atomically
	// publishes the completed bytes and refuses a concurrently created leaf.
	if C.link(&char(image.str), &char(output.str)) != 0 { return file_error(image, output) }
	total := total_blocks(data_blocks)!
	return Metadata{format, data_blocks, digest, block_size, total - data_blocks, total * block_size, size}
}
