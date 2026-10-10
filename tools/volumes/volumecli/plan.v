// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

const plan_header_bytes = 64
const plan_max_bytes = 2112

struct DiskKey {
mut:
	bytes u64
	sector u64
	kind u32 // 1: MBR disk signature; 2: GPT disk GUID.
	id [16]u8
}

struct Plan {
mut:
	key DiskKey
	count u32
	rows [64]Request
}

fn get_le(data &u8, at int, count int) u64 {
	mut result := u64(0)
	unsafe { for i := 0; i < count; i++ { result |= u64(data[at + i]) << (8 * i) } }
	return result
}

fn put_le(data &u8, at int, count int, value u64) {
	unsafe { for i := 0; i < count; i++ { data[at + i] = u8(value >> (8 * i)) } }
}

fn crc32(data &u8, size int, zero_at int) u32 {
	mut crc := u32(-1)
	unsafe {
		for i := 0; i < size; i++ {
			crc ^= if i >= zero_at && i < zero_at + 4 { u32(0) } else { u32(data[i]) }
			for _ in 0 .. 8 { crc = (crc >> 1) ^ if crc & 1 != 0 { u32(0xedb88320) } else { u32(0) } }
		}
	}
	return ~crc
}

@[direct_array_access]
fn key_valid(key &DiskKey) bool {
	if key.bytes < key.sector * 2 || key.sector < 512 || key.sector > 4096
		|| key.sector & (key.sector - 1) != 0 || key.bytes % key.sector != 0 { return false }
	mut nonzero := false
	for i := 0; i < 16; i++ {
		if key.id[i] != 0 { nonzero = true }
		if key.kind == 1 && i >= 4 && key.id[i] != 0 { return false }
	}
	return nonzero && (key.kind == 1 || key.kind == 2)
}

@[direct_array_access]
fn key_matches(a &DiskKey, b &DiskKey) bool {
	if a.bytes != b.bytes || a.sector != b.sector || a.kind != b.kind { return false }
	for i := 0; i < 16; i++ { if a.id[i] != b.id[i] { return false } }
	return true
}

@[direct_array_access]
fn plan_valid(plan &Plan) bool {
	if plan.count > 64 || !key_valid(&plan.key) { return false }
	for i := u32(0); i < plan.count; i++ {
		row := plan.rows[i]
		if row.version != 1 || row.slot >= 64 || row.flags > 1 || row.length == 0
			|| row.offset > plan.key.bytes || row.length > plan.key.bytes - row.offset
			|| row.offset % plan.key.sector != 0 || row.length % plan.key.sector != 0 { return false }
		for j := u32(0); j < i; j++ {
			other := plan.rows[j]
			if other.slot == row.slot || (row.offset < other.offset + other.length
				&& other.offset < row.offset + row.length) { return false }
		}
	}
	return true
}

@[direct_array_access]
fn encode_plan(plan &Plan, out &u8) int {
	if !plan_valid(plan) { return 0 }
	size := plan_header_bytes + int(plan.count) * 32
	unsafe { for i := 0; i < size; i++ { out[i] = 0 } }
	put_le(out, 0, 8, 0x314d5658494e4956) // VINIXVM1
	put_le(out, 8, 4, 1)
	put_le(out, 12, 4, plan.count)
	put_le(out, 16, 8, plan.key.bytes)
	put_le(out, 24, 8, plan.key.sector)
	put_le(out, 32, 4, plan.key.kind)
	unsafe { for i := 0; i < 16; i++ { out[40 + i] = plan.key.id[i] } }
	for i := u32(0); i < plan.count; i++ {
		row := plan.rows[i]
		at := plan_header_bytes + int(i) * 32
		put_le(out, at, 4, row.version)
		put_le(out, at + 4, 4, row.slot)
		put_le(out, at + 8, 8, row.offset)
		put_le(out, at + 16, 8, row.length)
		put_le(out, at + 24, 8, row.flags)
	}
	put_le(out, 36, 4, crc32(out, size, 36))
	return size
}

@[direct_array_access]
fn decode_plan(data &u8, size int, mut plan Plan) bool {
	if size < plan_header_bytes || size > plan_max_bytes
		|| get_le(data, 0, 8) != 0x314d5658494e4956 || get_le(data, 8, 4) != 1 { return false }
	count := u32(get_le(data, 12, 4))
	if count > 64 || size != plan_header_bytes + int(count) * 32
		|| get_le(data, 56, 8) != 0 || get_le(data, 36, 4) != crc32(data, size, 36) { return false }
	plan = Plan{count: count}
	plan.key.bytes = get_le(data, 16, 8)
	plan.key.sector = get_le(data, 24, 8)
	plan.key.kind = u32(get_le(data, 32, 4))
	unsafe { for i := 0; i < 16; i++ { plan.key.id[i] = data[40 + i] } }
	for i := u32(0); i < count; i++ {
		at := plan_header_bytes + int(i) * 32
		plan.rows[i] = Request{version: u32(get_le(data, at, 4)), slot: u32(get_le(data, at + 4, 4)),
			offset: get_le(data, at + 8, 8), length: get_le(data, at + 16, 8), flags: get_le(data, at + 24, 8)}
	}
	return plan_valid(&plan)
}

// Read only partition-table identity. Never stamp or alter the target disk.
@[direct_array_access]
fn identify_disk(data &u8, size int, bytes u64, sector u64, mut key DiskKey) bool {
	if sector < 512 || sector > 4096 || sector & (sector - 1) != 0
		|| bytes < sector * 2 || bytes % sector != 0 || size != int(sector * 2) { return false }
	key = DiskKey{bytes: bytes, sector: sector}
	if get_le(data, int(sector), 8) == 0x5452415020494645 {
		header := unsafe { &data[int(sector)] }
		length := get_le(header, 12, 4)
		if get_le(header, 8, 4) != 0x10000 || length < 92 || length > sector
			|| get_le(header, 20, 4) != 0 || get_le(header, 24, 8) != 1
			|| get_le(header, 16, 4) != crc32(header, int(length), 16) { return false }
		key.kind = 2
		unsafe { for i := 0; i < 16; i++ { key.id[i] = header[56 + i] } }
	} else {
		if get_le(data, 510, 2) != 0xaa55 { return false }
		// A protective MBR with an unreadable GPT must not fall back to its ID.
		unsafe { for i := 0; i < 4; i++ { if data[446 + i * 16 + 4] == 0xee { return false } } }
		key.kind = 1
		unsafe { for i := 0; i < 4; i++ { key.id[i] = data[440 + i] } }
	}
	return key_valid(&key)
}
