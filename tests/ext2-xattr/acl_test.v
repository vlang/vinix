// SPDX-License-Identifier: GPL-2.0-or-later
module posix_acl

fn sample() []u8 {
	mut result := []u8{cap: 60}
	append32(mut result, 2)
	for current in [Entry{user_obj, 7, undefined_id}, Entry{user, 6, 1000},
		Entry{group_obj, 1, undefined_id}, Entry{group, 4, 2000},
		Entry{group, 2, 3000}, Entry{mask, 6, undefined_id}, Entry{other, 7, undefined_id}] {
		append16(mut result, current.tag)
		append16(mut result, current.permissions)
		append32(mut result, current.id)
	}
	return result
}

fn test_disk_wire_roundtrip_uses_distinct_entry_sizes() {
	wire := sample()
	assert valid(wire)
	mut disk := []u8{}
	disk.flags |= .noslices
	assert to_disk(wire, mut disk)
	assert disk.len == 44
	assert le32(disk, 0) == 1
	mut decoded := []u8{}
	decoded.flags |= .noslices
	assert from_disk(disk, mut decoded)
	assert decoded == wire
}

fn test_owner_named_user_and_group_mask_precedence() {
	mut data := sample()
	assert permits(data, 10, 20, 10, 999, []u32{}, 7)
	assert permits(data, 10, 20, 1000, 999, []u32{}, 6)
	put_permissions(mut data, 5, 4)
	assert permits(data, 10, 20, 1000, 999, []u32{}, 4)
	assert !permits(data, 10, 20, 1000, 999, []u32{}, 2)
	assert !permits(data, 10, 20, 999, 20, []u32{}, 4)
	assert permits(data, 10, 20, 999, 999, [u32(2000)], 4)
	assert !permits(data, 10, 20, 999, 999, [u32(3000)], 4)
	assert permits(data, 10, 20, 999, 999, []u32{}, 7)
	put_permissions(mut data, 5, 6)
	assert !permits(data, 10, 20, 999, 999, [u32(2000), 3000], 6)
}

fn test_creation_intersects_original_mode_and_chmod_preserves_named_grants() {
	mut data := sample()
	inherited, extended := inherit(mut data, 0o100660)
	assert extended && inherited == 0o100660
	assert entry(data, 1).permissions == 6
	assert entry(data, 5).permissions == 6
	assert entry(data, 6).permissions == 0
	chmod(mut data, 0o100204)
	assert entry(data, 0).permissions == 2
	assert entry(data, 1).permissions == 6
	assert entry(data, 5).permissions == 0
	assert entry(data, 6).permissions == 4
	derived, _ := mode(data, 0o100000)
	assert derived == 0o100204
	assert !permits(data, 10, 20, 1000, 999, []u32{}, 4)
}

fn test_minimal_acl_is_mode_equivalent() {
	mut data := []u8{}
	append32(mut data, 2)
	for current in [Entry{user_obj, 6, undefined_id}, Entry{group_obj, 4, undefined_id},
		Entry{other, 0, undefined_id}] {
		append16(mut data, current.tag)
		append16(mut data, current.permissions)
		append32(mut data, current.id)
	}
	assert valid(data)
	derived, extended := mode(data, 0o102000)
	assert derived == 0o102640 && !extended
	chmod(mut data, 0o100755)
	assert entry(data, 1).permissions == 5
}

fn test_acl_rejects_bad_versions_lengths_ids_order_and_permissions() {
	assert !valid([u8(2), 0, 0])
	assert valid([u8(2), 0, 0, 0])
	for offset in [0, 4, 6, 8, 12, 20, 44, 52] {
		mut data := sample()
		data[offset] = if offset == 8 { u8(0) } else { u8(255) }
		assert !valid(data)
	}
	mut duplicate := sample()
	duplicate[40] = 0xd0
	duplicate[41] = 7
	assert !valid(duplicate)
	mut disk := []u8{}
	assert to_disk(sample(), mut disk)
	disk.delete_last()
	mut output := []u8{}
	assert !from_disk(disk, mut output)
}
