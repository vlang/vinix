module main

// Verify the generated USTAR records independently of the guest parser.
fn test_tar_record_checksums_padding_and_size() {
	mut data := []u8{}
	tar_entry(mut data, 'etc/motd', 'hello'.bytes(), false)
	assert data.len == 1024
	assert data[512..517].bytestr() == 'hello'
	assert data[124..135].bytestr() == '00000000005'
	mut checksum := u32(0)
	for i in 0 .. 512 { checksum += if i >= 148 && i < 156 { u8(32) } else { data[i] } }
	mut recorded := u32(0)
	for i in 148 .. 155 { recorded = recorded * 8 + u32(data[i] - `0`) }
	assert checksum == recorded
}

fn test_tar_hardlink_keeps_single_payload_and_valid_checksum() {
	mut data := []u8{}
	tar_link(mut data, 'usr/bin/vinix-calculator', 'bin/init')
	assert data.len == 512
	assert data[156] == `1`
	assert data[157..165].bytestr() == 'bin/init'
	assert data[124..135].bytestr() == '00000000000'
	mut checksum := u32(0)
	for i in 0 .. 512 { checksum += if i >= 148 && i < 156 { u8(32) } else { data[i] } }
	mut recorded := u32(0)
	for i in 148 .. 155 { recorded = recorded * 8 + u32(data[i] - `0`) }
	assert checksum == recorded
}
