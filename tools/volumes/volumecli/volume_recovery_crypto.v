// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// A recovery configuration preserves the VC1 metadata layout, but has its own
// format domain and no KDF fields. A private independent 64-byte recovery key
// supplies the stream and authentication halves directly.
fn volume_recovery_header(bytes &u8, size int) bool {
	if size != volume_seal_bytes { return false }
	unsafe { for i in 0 .. 8 { if bytes[i] != u8(c'VINIXVR1'[i]) { return false } } }
	if get_le(bytes, 8, 4) != 1 || get_le(bytes, 12, 4) != 1
		|| get_le(bytes, 16, 4) != volume_seal_bytes || get_le(bytes, 20, 4) != 64 { return false }
	unsafe {
		for i in 24 .. 56 { if bytes[i] != 0 { return false } }
		for i in 68 .. 80 { if bytes[i] != 0 { return false } }
		for i in 100 .. 104 { if bytes[i] != 0 { return false } }
		for i in 152 .. 192 { if bytes[i] != 0 { return false } }
		for i in 256 .. 288 { if bytes[i] != 0 { return false } }
	}
	disk := volume_seal_disk(bytes); row := volume_seal_row(bytes)
	return volume_seal_geometry(unsafe { &disk }, unsafe { &row })
}

@[direct_array_access]
fn encode_volume_recovery(disk &DiskKey, request &EncryptedRequest, recovery &u8, nonce &u8, output &u8) bool {
	if !volume_seal_geometry(disk, &request.data) || recovery_equal(&request.key[0], &request.key[32], 32)
		|| recovery_equal(recovery, unsafe { recovery + 32 }, 32) || recovery_equal(&request.key[0], recovery, 64) { return false }
	mut work := unsafe { &VolumeSealCrypto(C.alloca(sizeof(VolumeSealCrypto))) }
	unsafe { *work = VolumeSealCrypto{} }
	defer { erase_key(work, sizeof(VolumeSealCrypto)) }
	unsafe { C.memcpy(&work.bytes[0], c'VINIXVR1', 8) }
	put_le(&work.bytes[0], 8, 4, 1); put_le(&work.bytes[0], 12, 4, 1)
	put_le(&work.bytes[0], 16, 4, volume_seal_bytes); put_le(&work.bytes[0], 20, 4, 64)
	put_le(&work.bytes[0], 80, 8, disk.bytes); put_le(&work.bytes[0], 88, 8, disk.sector); put_le(&work.bytes[0], 96, 4, disk.kind)
	put_le(&work.bytes[0], 120, 4, request.data.version); put_le(&work.bytes[0], 124, 4, request.data.slot)
	put_le(&work.bytes[0], 128, 8, request.data.offset); put_le(&work.bytes[0], 136, 8, request.data.length); put_le(&work.bytes[0], 144, 8, request.data.flags)
	unsafe { C.memcpy(&work.bytes[56], nonce, 12); C.memcpy(&work.bytes[104], &disk.id[0], 16); C.memcpy(&work.bytes[192], &request.key[0], 64) }
	recovery_chacha(recovery, &work.bytes[56], &work.bytes[192])
	if !volume_seal_tag(recovery, &work.bytes[0], unsafe { &work.tag }) { return false }
	unsafe { C.memcpy(&work.bytes[288], &work.tag[0], 32); C.memcpy(output, &work.bytes[0], volume_seal_bytes) }
	return true
}

// Neither metadata nor plaintext escapes on rejection, including tag failures.
@[direct_array_access]
fn decode_volume_recovery(bytes &u8, size int, recovery &u8, mut disk DiskKey, mut request EncryptedRequest) bool {
	if !volume_recovery_header(bytes, size) || recovery_equal(recovery, unsafe { recovery + 32 }, 32) { return false }
	mut work := unsafe { &VolumeSealCrypto(C.alloca(sizeof(VolumeSealCrypto))) }
	unsafe { *work = VolumeSealCrypto{} }
	defer { erase_key(work, sizeof(VolumeSealCrypto)) }
	if !volume_seal_tag(recovery, bytes, unsafe { &work.tag }) || !recovery_equal(&work.tag[0], unsafe { bytes + 288 }, 32) { return false }
	unsafe { C.memcpy(&work.key[0], bytes + 192, 64) }
	recovery_chacha(recovery, unsafe { bytes + 56 }, &work.key[0])
	if recovery_equal(&work.key[0], &work.key[32], 32) || recovery_equal(&work.key[0], recovery, 64) { return false }
	disk = volume_seal_disk(bytes); request = EncryptedRequest{data: volume_seal_row(bytes)}
	unsafe { C.memcpy(&request.key[0], &work.key[0], 64) }
	return true
}
