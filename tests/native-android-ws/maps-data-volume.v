// SPDX-License-Identifier: GPL-2.0-or-later
// Verify a fresh test data volume before the account broker provisions apps.
module main

import json2
import os

#include <unistd.h>

fn C.fsync(int) int
fn C.pread(int, voidptr, uint, i64) i64

const data_mount = '/var/lib/vinix/apps'

struct Volume {
	mountpoint  string
	uuid_hex    string
	image_bytes u64
}

fn volume_uuid(path string, size u64) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut block := []u8{len: 512}
	defer { unsafe { block.free() } }
	// Raw Vinix block reads require sector alignment. Stdio may split an
	// otherwise aligned fread into unaligned readv buffers, so bypass it here.
	read := unsafe { C.pread(file.fd, block.data, uint(block.len), 1024) }
	if read < 0 { return error('aligned superblock read: ' + os.error_posix().msg()) }
	if read != 512 || block[56] != 0x53 || block[57] != 0xef
		|| block[24..28] != [u8(2), 0, 0, 0] {
		return error('expected 4096-byte ext2 blocks')
	}
	blocks := u64(block[4]) | (u64(block[5]) << 8) | (u64(block[6]) << 16) | (u64(block[7]) << 24)
	if blocks * 4096 != size { return error('ext2 volume size differs') }
	return block[104..120].hex()
}

fn locate(volume Volume) !string {
	mut found := ''
	// QEMU can enumerate its firmware disk and explicit data disk in either order.
	for path in ['/dev/vda', '/dev/vdb', '/dev/vdc', '/dev/vdd'] {
		if !os.exists(path) { continue }
		uuid := volume_uuid(path, volume.image_bytes) or {
			eprintln('MAPS-DATA-VOLUME-CANDIDATE ${path}: ' + err.msg())
			continue
		}
		if uuid != volume.uuid_hex { continue }
		if found != '' { return error('duplicate selected filesystem UUID') }
		found = path
	}
	if found == '' { return error('selected data volume not found') }
	return found
}

fn mount_rows() ![][]string {
	return os.read_file('/proc/self/mounts')!.split_into_lines().map(it.fields())
}

fn check(volume Volume, mount_new bool) ! {
	if os.geteuid() != 0 { return error('root test operator required') }
	if volume.mountpoint != data_mount || volume.image_bytes != u64(8) << 30
		|| volume.uuid_hex.len != 32
		|| !volume.uuid_hex.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
		return error('invalid selected volume metadata')
	}
	device := locate(volume)!
	if mount_new {
		for row in mount_rows()! {
			if row.len >= 2 && (row[0] == device || row[1] == volume.mountpoint || row[1].starts_with(volume.mountpoint + '/')) {
				return error('refusing to hide an existing mount')
			}
		}
		os.mkdir_all(volume.mountpoint)!
		if os.is_link(volume.mountpoint) || os.ls(volume.mountpoint)!.len != 0 {
			return error('fresh empty data mountpoint required')
		}
		if os.system_args(['/bin/mount', '-t', 'ext2', '-o', 'rw,nosuid,nodev,strictatime,wxallowed',
			device, volume.mountpoint]) != 0 {
			return error('data volume mount failed')
		}
	}
	mut matches := 0
	for row in mount_rows()! {
		if row.len < 4 || row[1] != volume.mountpoint { continue }
		if row[0] != device || row[2] != 'ext2' { return error('mounted filesystem differs') }
		options := row[3].split(',')
		if 'ro' in options || 'noexec' in options || 'nosuid' !in options
			|| 'nodev' !in options || 'wxallowed' !in options {
			return error('data mount flags differ')
		}
		matches++
	}
	if matches != 1 { return error('one selected data mount required') }
	metadata := os.lstat(volume.mountpoint)!
	if metadata.uid != 0 || metadata.mode & 0o7777 != 0o755 || metadata.get_filetype() != .directory {
		return error('protected root-owned volume root required')
	}
	space := os.disk_usage(data_mount)!
	if space.total < u64(7) << 30 || space.available < u64(6) << 30 {
		return error('fresh volume capacity missing')
	}
	first, second := volume.mountpoint + '/.vinix-volume-probe', volume.mountpoint + '/.vinix-volume-renamed'
	if os.exists(first) || os.exists(second) { return error('fresh probe names required') }
	mut bytes := []u8{len: 1024 * 1024}
	defer { unsafe { bytes.free() } }
	for i in 0 .. bytes.len { bytes[i] = u8(i * 31 + 7) }
	mut output := os.open_file(first, 'wx', 0o600)!
	defer { output.close() }
	if output.write(bytes)! != bytes.len { return error('volume write failed') }
	output.flush()
	if C.fsync(output.fd) != 0 { return error('volume sync failed') }
	os.rename(first, second)!
	mut input := os.open(second)!
	defer { input.close() }
	mut readback := []u8{len: bytes.len}
	defer { unsafe { readback.free() } }
	mut offset := 0
	for _ in 0 .. 1024 {
		if offset == readback.len { break }
		n := unsafe { C.pread(input.fd, &u8(readback.data) + offset, uint(readback.len - offset), i64(offset)) }
		if n <= 0 || n > readback.len - offset { return error('volume readback failed') }
		offset += int(n)
	}
	if offset != bytes.len || readback != bytes { return error('volume readback differs') }
	os.rm(second)!
	println('MAPS-DATA-VOLUME-PASS device=${device} mount=${volume.mountpoint} uuid=${volume.uuid_hex} total_bytes=${space.total} available_bytes=${space.available} write_sync_rename_readback=1')
}

fn main() {
	if os.args.len == 4 && os.args[1] == '--inspect' {
		volume := json2.decode[Volume](os.read_file(os.args[3])!)!
		if volume_uuid(os.args[2], volume.image_bytes)! != volume.uuid_hex {
			panic('volume UUID differs from selected metadata')
		}
		println('MAPS-DATA-VOLUME-INSPECT-PASS uuid=' + volume.uuid_hex)
		return
	}
	if os.args.len != 2 || os.args[1] !in ['--mount', '--check'] {
		eprintln('usage: maps-data-volume --mount|--check | --inspect IMAGE METADATA')
		exit(2)
	}
	volume := json2.decode[Volume](os.read_file('/opt/current-api/data-image.json') or {
		eprintln(err)
		exit(1)
	}) or {
		eprintln(err)
		exit(1)
	}
	check(volume, os.args[1] == '--mount') or {
		eprintln('MAPS-DATA-VOLUME-FAILED ' + err.msg())
		exit(1)
	}
}
