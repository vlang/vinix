// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

const volume_seal_bytes = 320

struct VolumeSealCrypto {
mut:
	bytes [320]u8
	message [320]u8
	key [64]u8
	tag [32]u8
}

fn volume_seal_geometry(disk &DiskKey, row &Request) bool {
	return key_valid(disk) && (disk.sector == 512 || disk.sector == 4096)
		&& row.version == 1 && row.slot < 64 && row.flags <= 1 && row.length != 0
		&& row.offset <= disk.bytes && row.length <= disk.bytes - row.offset
		&& row.offset % disk.sector == 0 && row.length % disk.sector == 0
}

@[direct_array_access]
fn volume_seal_disk(bytes &u8) DiskKey {
	mut disk := DiskKey{bytes: get_le(bytes, 80, 8), sector: get_le(bytes, 88, 8), kind: u32(get_le(bytes, 96, 4))}
	unsafe { for i in 0 .. 16 { disk.id[i] = bytes[104 + i] } }
	return disk
}

fn volume_seal_row(bytes &u8) Request {
	return Request{version: u32(get_le(bytes, 120, 4)), slot: u32(get_le(bytes, 124, 4)),
		offset: get_le(bytes, 128, 8), length: get_le(bytes, 136, 8), flags: get_le(bytes, 144, 8)}
}

fn volume_seal_header(bytes &u8, size int) bool {
	if size != volume_seal_bytes { return false }
	unsafe { for i in 0 .. 8 { if bytes[i] != u8(c'VINIXVC1'[i]) { return false } } }
	if get_le(bytes, 8, 4) != 1 || get_le(bytes, 12, 4) != 1 || get_le(bytes, 16, 4) != volume_seal_bytes
		|| get_le(bytes, 20, 4) != 64 || get_le(bytes, 24, 8) != sealed_scrypt_n
		|| get_le(bytes, 32, 4) != sealed_scrypt_r || get_le(bytes, 36, 4) != sealed_scrypt_p { return false }
	unsafe {
		for i in 68 .. 80 { if bytes[i] != 0 { return false } }
		for i in 100 .. 104 { if bytes[i] != 0 { return false } }
		for i in 152 .. 192 { if bytes[i] != 0 { return false } }
		for i in 256 .. 288 { if bytes[i] != 0 { return false } }
	}
	disk := volume_seal_disk(bytes); row := volume_seal_row(bytes)
	return volume_seal_geometry(unsafe { &disk }, unsafe { &row })
}

fn volume_seal_tag(wrapping &u8, bytes &u8, output &[32]u8) bool {
	mut work := unsafe { &VolumeSealCrypto(C.alloca(sizeof(VolumeSealCrypto))) }
	unsafe { *work = VolumeSealCrypto{}; C.memcpy(&work.message[0], wrapping, 32); C.memcpy(&work.message[32], bytes, 288) }
	defer { erase_key(work, sizeof(VolumeSealCrypto)) }
	return recovery_hmac(unsafe { wrapping + 32 }, &work.message[0], 320, output)
}

@[direct_array_access]
fn encode_volume_seal(disk &DiskKey, request &EncryptedRequest, wrapping &u8, random &u8, output &u8) bool {
	if !volume_seal_geometry(disk, &request.data) || recovery_equal(&request.key[0], &request.key[32], 32)
		|| recovery_equal(wrapping, unsafe { wrapping + 32 }, 32) || recovery_equal(&request.key[0], wrapping, 64) { return false }
	mut work := unsafe { &VolumeSealCrypto(C.alloca(sizeof(VolumeSealCrypto))) }
	unsafe { *work = VolumeSealCrypto{} }
	defer { erase_key(work, sizeof(VolumeSealCrypto)) }
	unsafe { C.memcpy(&work.bytes[0], c'VINIXVC1', 8) }
	put_le(&work.bytes[0], 8, 4, 1); put_le(&work.bytes[0], 12, 4, 1)
	put_le(&work.bytes[0], 16, 4, volume_seal_bytes); put_le(&work.bytes[0], 20, 4, 64)
	put_le(&work.bytes[0], 24, 8, sealed_scrypt_n); put_le(&work.bytes[0], 32, 4, sealed_scrypt_r); put_le(&work.bytes[0], 36, 4, sealed_scrypt_p)
	put_le(&work.bytes[0], 80, 8, disk.bytes); put_le(&work.bytes[0], 88, 8, disk.sector); put_le(&work.bytes[0], 96, 4, disk.kind)
	put_le(&work.bytes[0], 120, 4, request.data.version); put_le(&work.bytes[0], 124, 4, request.data.slot)
	put_le(&work.bytes[0], 128, 8, request.data.offset); put_le(&work.bytes[0], 136, 8, request.data.length); put_le(&work.bytes[0], 144, 8, request.data.flags)
	unsafe { C.memcpy(&work.bytes[40], random, 28); C.memcpy(&work.bytes[104], &disk.id[0], 16); C.memcpy(&work.bytes[192], &request.key[0], 64) }
	recovery_chacha(wrapping, &work.bytes[56], &work.bytes[192])
	if !volume_seal_tag(wrapping, &work.bytes[0], unsafe { &work.tag }) { return false }
	unsafe { C.memcpy(&work.bytes[288], &work.tag[0], 32); C.memcpy(output, &work.bytes[0], volume_seal_bytes) }
	return true
}

@[direct_array_access]
fn decode_volume_seal(bytes &u8, size int, wrapping &u8, mut disk DiskKey, mut request EncryptedRequest) bool {
	if !volume_seal_header(bytes, size) || recovery_equal(wrapping, unsafe { wrapping + 32 }, 32) { return false }
	mut work := unsafe { &VolumeSealCrypto(C.alloca(sizeof(VolumeSealCrypto))) }
	unsafe { *work = VolumeSealCrypto{} }
	defer { erase_key(work, sizeof(VolumeSealCrypto)) }
	if !volume_seal_tag(wrapping, bytes, unsafe { &work.tag }) || !recovery_equal(&work.tag[0], unsafe { bytes + 288 }, 32) { return false }
	unsafe { C.memcpy(&work.key[0], bytes + 192, 64) }
	recovery_chacha(wrapping, unsafe { bytes + 56 }, &work.key[0])
	if recovery_equal(&work.key[0], &work.key[32], 32) || recovery_equal(&work.key[0], wrapping, 64) { return false }
	disk = volume_seal_disk(bytes); request = EncryptedRequest{data: volume_seal_row(bytes)}
	unsafe { C.memcpy(&request.key[0], &work.key[0], 64) }
	return true
}
