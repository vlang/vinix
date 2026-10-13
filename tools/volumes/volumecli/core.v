// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

#include <volume.h>

fn C.open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.ioctl(i32, u64, ...voidptr) i32
fn C.printf(&char, ...voidptr) i32
fn C.perror(&char)
fn C.strcmp(&char, &char) i32

struct Request {
mut:
	version u32 = 1
	slot    u32
	offset  u64
	length  u64
	flags   u64
}

struct Status {
mut:
	version     u64
	bytes       u64
	sector      u64
	flags       u64
	reads       u64
	writes      u64
	read_bytes  u64
	write_bytes u64
	flushes     u64
	errors      u64
	last_error  u64
	disk_id     u64
	start       u64
	slot        u64
	generation  u64
	reserved    u64
}

fn decimal(text &char) ?u64 {
	mut value := u64(0)
	mut length := 0
	unsafe {
		for text[length] != 0 {
			if text[length] < `0` || text[length] > `9` { return none }
			digit := u64(u8(text[length]) - u8(`0`))
			if value > (u64(-1) - digit) / 10 { return none }
			value = value * 10 + digit
			length++
		}
	}
	if length == 0 { return none }
	return value
}

fn usage() i32 {
	C.printf(c'       vinix-volume rewrap-volume CONFIG OLD_PASSPHRASE_FILE NEW_PASSPHRASE_FILE NEW_CONFIG\n')
	C.printf(c'       vinix-volume seal-volume DEVICE SLOT OFFSET_BYTES LENGTH_BYTES KEYFILE PASSPHRASE_FILE CONFIG [ro]\n       vinix-volume open-volume DEVICE CONFIG PASSPHRASE_FILE [ro]\n       vinix-volume unseal-volume-key CONFIG PASSPHRASE_FILE KEYFILE\n')
	C.printf(c'       vinix-volume rewrap-key ENVELOPE OLD_PASSPHRASE_FILE NEW_PASSPHRASE_FILE NEW_ENVELOPE\n')
	C.printf(c'       vinix-volume seal-key KEYFILE PASSPHRASE_FILE ENVELOPE\n       vinix-volume unseal-key ENVELOPE PASSPHRASE_FILE KEYFILE\n       vinix-volume open-sealed DEVICE SLOT OFFSET_BYTES LENGTH_BYTES ENVELOPE PASSPHRASE_FILE [ro]\n')
	C.printf(c'       vinix-volume backup-key KEYFILE RECOVERY_KEYFILE ENVELOPE\n       vinix-volume recover-key ENVELOPE RECOVERY_KEYFILE KEYFILE\n')
	C.printf(c'       vinix-volume open-crypt DEVICE SLOT OFFSET_BYTES LENGTH_BYTES KEYFILE [ro]\n')
	C.printf(c'usage: vinix-volume status DEVICE\n       vinix-volume health DEVICE\n       vinix-volume monitor DEVICE INTERVAL_SECONDS [SAMPLES]\n       vinix-volume create DEVICE SLOT OFFSET_BYTES LENGTH_BYTES [ro]\n       vinix-volume grow DEVICE LENGTH_BYTES\n       vinix-volume remove DEVICE\n       vinix-volume discard DEVICE OFFSET_BYTES LENGTH_BYTES\n       vinix-volume save DEVICE PLAN\n       vinix-volume restore DEVICE PLAN\n       vinix-volume discover PLAN\n       vinix-volume restore-auto PLAN\n       vinix-volume restore-set DIRECTORY\n       vinix-volume boot-restore\n')
	C.printf(c'       vinix-volume save-set BUNDLE DEVICE [DEVICE ...]\n       vinix-volume plan-grow BUNDLE SLOT LENGTH_BYTES\n       vinix-volume restore-bundle BUNDLE [grow]\n')
	C.printf(c'       vinix-volume show-bundle BUNDLE\n       vinix-volume check-bundle BUNDLE [grow]\n')
	C.printf(c'       vinix-volume hash-bundle BUNDLE MANIFEST DISK_INDEX DEVICE [...]\n       vinix-volume verify-data MANIFEST DISK_INDEX DEVICE [...]\n       vinix-volume show-data MANIFEST\n')
	C.printf(c'       vinix-volume scrub-data MANIFEST REPORT DISK_INDEX DEVICE [...]\n')
	C.printf(c'       vinix-volume plan-add BUNDLE DISK_INDEX SLOT OFFSET_BYTES LENGTH_BYTES [ro]\n       vinix-volume plan-remove BUNDLE SLOT\n')
	C.printf(c'       vinix-volume plan-add-batch BUNDLE IDENTITY SLOT OFFSET_BYTES LENGTH_BYTES MODE [...]\n       vinix-volume plan-preview-add-batch BUNDLE IDENTITY SLOT OFFSET_BYTES LENGTH_BYTES MODE [...]\n       MODE is rw or ro; batches contain 1..64 requests\n')
	C.printf(c'       vinix-volume plan-grow-batch BUNDLE IDENTITY SLOT LENGTH_BYTES [...]\n       vinix-volume plan-preview-grow-batch BUNDLE IDENTITY SLOT LENGTH_BYTES [...]\n')
	C.printf(c'       vinix-volume pool-contract-batch BUNDLE POOL IDENTITY END_BYTES [...]\n       vinix-volume pool-preview-contract-batch BUNDLE POOL IDENTITY END_BYTES [...]\n')
	C.printf(c'       vinix-volume pool-resize-batch BUNDLE IDENTITY POOL START_BYTES END_BYTES [...]\n       vinix-volume pool-preview-resize-batch BUNDLE IDENTITY POOL START_BYTES END_BYTES [...]\n')
	C.printf(c'       vinix-volume plan-contract-capacity-batch BUNDLE IDENTITY DEVICE EXPECTED_BYTES [...]\n       vinix-volume plan-preview-contract-capacity-batch BUNDLE IDENTITY DEVICE EXPECTED_BYTES [...]\n')
	C.printf(c'       vinix-volume pool-allocate-set-batch BUNDLE POOL SLOT LENGTH_BYTES MODE [...]\n       vinix-volume pool-preview-set-batch BUNDLE POOL SLOT LENGTH_BYTES MODE [...]\n')
	C.printf(c'       vinix-volume pool-grow-set-batch BUNDLE POOL SLOT LENGTH_BYTES [...]\n       vinix-volume pool-preview-grow-set-batch BUNDLE POOL SLOT LENGTH_BYTES [...]\n')
	C.printf(c'       vinix-volume plan-remove-batch BUNDLE SLOT [...]\n       vinix-volume plan-preview-remove-batch BUNDLE SLOT [...]\n')
	C.printf(c'       vinix-volume plan-enroll BUNDLE PLAN\n       vinix-volume plan-forget BUNDLE DISK_INDEX\n')
	C.printf(c'       vinix-volume plan-enroll-batch BUNDLE PLAN [...]\n       vinix-volume plan-preview-enroll-batch BUNDLE PLAN [...]\n')
	C.printf(c'       vinix-volume plan-forget-batch BUNDLE IDENTITY [...]\n       vinix-volume plan-preview-forget-batch BUNDLE IDENTITY [...]\n')
	C.printf(c'       vinix-volume plan-space BUNDLE DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES\n       vinix-volume plan-allocate BUNDLE DISK_INDEX SLOT LENGTH_BYTES START_BYTES END_BYTES ALIGNMENT_BYTES [ro]\n')
	C.printf(c'       vinix-volume plan-capacity BUNDLE DISK_INDEX DEVICE EXPECTED_BYTES\n')
	C.printf(c'       vinix-volume plan-capacity-batch BUNDLE DISK_INDEX DEVICE EXPECTED_BYTES [DISK_INDEX DEVICE EXPECTED_BYTES ...]\n       vinix-volume plan-preview-capacity-batch BUNDLE DISK_INDEX DEVICE EXPECTED_BYTES [DISK_INDEX DEVICE EXPECTED_BYTES ...]\n')
	C.printf(c'       vinix-volume pool-add BUNDLE POOL_ID DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES\n       vinix-volume pool-remove BUNDLE POOL_ID DISK_INDEX\n       vinix-volume pool-space BUNDLE POOL_ID\n       vinix-volume pool-allocate BUNDLE POOL_ID SLOT LENGTH_BYTES [ro]\n')
	C.printf(c'       vinix-volume pool-add-batch BUNDLE POOL_ID DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES [...]\n       vinix-volume pool-preview-add-batch BUNDLE POOL_ID DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES [...]\n       vinix-volume pool-remove-batch BUNDLE POOL_ID DISK_INDEX [...]\n       vinix-volume pool-preview-remove-batch BUNDLE POOL_ID DISK_INDEX [...]\n')
	C.printf(c'       vinix-volume pool-order BUNDLE POOL_ID DISK_INDEX [...]\n       vinix-volume pool-preview-order BUNDLE POOL_ID DISK_INDEX [...]\n')
	C.printf(c'       vinix-volume pool-expand BUNDLE POOL_ID DISK_INDEX END_BYTES\n       vinix-volume pool-grow BUNDLE POOL_ID SLOT LENGTH_BYTES\n')
	C.printf(c'       vinix-volume pool-allocate-batch BUNDLE POOL_ID SLOT LENGTH_BYTES MODE [SLOT LENGTH_BYTES MODE ...]\n       vinix-volume pool-preview-batch BUNDLE POOL_ID SLOT LENGTH_BYTES MODE [SLOT LENGTH_BYTES MODE ...]\n       MODE is rw or ro; batches contain 1..64 requests\n')
	C.printf(c'       vinix-volume pool-grow-batch BUNDLE POOL_ID SLOT LENGTH_BYTES [SLOT LENGTH_BYTES ...]\n       vinix-volume pool-preview-grow-batch BUNDLE POOL_ID SLOT LENGTH_BYTES [SLOT LENGTH_BYTES ...]\n')
	C.printf(c'       vinix-volume pool-expand-batch BUNDLE POOL_ID DISK_INDEX END_BYTES [DISK_INDEX END_BYTES ...]\n       vinix-volume pool-preview-expand-batch BUNDLE POOL_ID DISK_INDEX END_BYTES [DISK_INDEX END_BYTES ...]\n')
	return 2
}

pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc >= 2 && C.strcmp(argv[1], c'rewrap-volume') == 0 {
			if argc != 6 || argv[2][0] == 0 || argv[3][0] == 0 || argv[4][0] == 0 || argv[5][0] == 0 { return usage() }
			return rewrap_volume_seal(argv[2], argv[3], argv[4], argv[5])
		}
		if argc >= 2 && C.strcmp(argv[1], c'seal-volume') == 0 {
			if argc != 9 && argc != 10 { return usage() }
			slot := decimal(argv[3]) or { return usage() }; offset := decimal(argv[4]) or { return usage() }; length := decimal(argv[5]) or { return usage() }
			if slot >= 64 || length == 0 || argv[2][0] == 0 || argv[6][0] == 0 || argv[7][0] == 0 || argv[8][0] == 0
				|| (argc == 10 && C.strcmp(argv[9], c'ro') != 0) { return usage() }
			data := Request{slot: u32(slot), offset: offset, length: length, flags: if argc == 10 { u64(1) } else { u64(0) }}
			return seal_volume_file(argv[2], argv[6], argv[7], argv[8], &data)
		}
		if argc >= 2 && C.strcmp(argv[1], c'open-volume') == 0 {
			if (argc != 5 && argc != 6) || argv[2][0] == 0 || argv[3][0] == 0 || argv[4][0] == 0 || (argc == 6 && C.strcmp(argv[5], c'ro') != 0) { return usage() }
			return open_volume_seal(argv[2], argv[3], argv[4], argc == 6)
		}
		if argc >= 2 && C.strcmp(argv[1], c'unseal-volume-key') == 0 {
			if argc != 5 || argv[2][0] == 0 || argv[3][0] == 0 || argv[4][0] == 0 { return usage() }
			return unseal_volume_key(argv[2], argv[3], argv[4])
		}
		if argc >= 2 && C.strcmp(argv[1], c'rewrap-key') == 0 {
			if argc != 6 || argv[2][0] == 0 || argv[3][0] == 0 || argv[4][0] == 0 || argv[5][0] == 0 { return usage() }
			return rewrap_sealed_key(argv[2], argv[3], argv[4], argv[5])
		}
		if argc >= 2 && (C.strcmp(argv[1], c'seal-key') == 0 || C.strcmp(argv[1], c'unseal-key') == 0) {
			if argc != 5 || argv[2][0] == 0 || argv[3][0] == 0 || argv[4][0] == 0 { return usage() }
			return sealed_key_file(argv[2], argv[3], argv[4], C.strcmp(argv[1], c'seal-key') == 0)
		}
		if argc >= 2 && C.strcmp(argv[1], c'open-sealed') == 0 {
			if argc != 8 && argc != 9 { return usage() }
			slot := decimal(argv[3]) or { return usage() }; offset := decimal(argv[4]) or { return usage() }; length := decimal(argv[5]) or { return usage() }
			if slot >= 64 || length == 0 || argv[2][0] == 0 || argv[6][0] == 0 || argv[7][0] == 0 || (argc == 9 && C.strcmp(argv[8], c'ro') != 0) { return usage() }
			data := Request{slot: u32(slot), offset: offset, length: length, flags: if argc == 9 { u64(1) } else { u64(0) }}
			return open_sealed_volume(argv[2], argv[6], argv[7], &data)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'backup-key') == 0 || C.strcmp(argv[1], c'recover-key') == 0) {
			if argc != 5 || argv[2][0] == 0 || argv[3][0] == 0 || argv[4][0] == 0 { return usage() }
			return recovery_key_file(argv[2], argv[3], argv[4], C.strcmp(argv[1], c'backup-key') == 0)
		}
		if argc >= 2 && C.strcmp(argv[1], c'open-crypt') == 0 {
			if argc != 7 && argc != 8 { return usage() }
			slot := decimal(argv[3]) or { return usage() }; offset := decimal(argv[4]) or { return usage() }; length := decimal(argv[5]) or { return usage() }
			if slot >= 64 || length == 0 || (argc == 8 && C.strcmp(argv[7], c'ro') != 0) { return usage() }
			data := Request{slot: u32(slot), offset: offset, length: length, flags: if argc == 8 { u64(1) } else { u64(0) }}
			return open_encrypted_volume(argv[2], argv[6], &data)
		}
		if argc >= 2 && C.strcmp(argv[1], c'show-data') == 0 {
			if argc != 3 { return usage() }; return verify_manifest_data(argv[2], nil, true)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'hash-bundle') == 0 || C.strcmp(argv[1], c'verify-data') == 0 || C.strcmp(argv[1], c'scrub-data') == 0) {
			create := C.strcmp(argv[1], c'hash-bundle') == 0; scrub := C.strcmp(argv[1], c'scrub-data') == 0; start := if create || scrub { i32(4) } else { i32(3) }
			if argc < start + 2 || argc > start + 128 || (argc - start) % 2 != 0 { return usage() }
			mut devices := &DataDevices(C.alloca(sizeof(DataDevices))); *devices = DataDevices{count: (argc - start) / 2}
			for i in 0 .. devices.count {
				at := start + i * 2; disk := decimal(argv[at]) or { return usage() }
				if disk >= 64 || argv[at + 1][0] == 0 { return usage() }; devices.disks[i] = u32(disk); devices.paths[i] = argv[at + 1]
			}
			if create { return hash_bundle_data(argv[2], argv[3], devices) }
			if scrub { return scrub_manifest_data(argv[2], argv[3], devices) }
			return verify_manifest_data(argv[2], devices, false)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'pool-grow-set-batch') == 0 || C.strcmp(argv[1], c'pool-preview-grow-set-batch') == 0) {
			if argc < 6 || argc > 195 || (argc - 3) % 3 != 0 { return usage() }
			mut batch := &MultiPoolGrowthBatch(C.alloca(sizeof(MultiPoolGrowthBatch)))
			*batch = MultiPoolGrowthBatch{count: (argc - 3) / 3}
			for i in 0 .. batch.count {
				at := 3 + i * 3
				pool := decimal(argv[at]) or { return usage() }; slot := decimal(argv[at + 1]) or { return usage() }
				length := decimal(argv[at + 2]) or { return usage() }
				if pool >= 64 || slot >= 64 || length == 0 { return usage() }
				batch.pools[i] = u32(pool); batch.slots[i] = u32(slot); batch.lengths[i] = length
			}
			return grow_multi_pool_batch_plan(argv[2], batch, C.strcmp(argv[1], c'pool-preview-grow-set-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'pool-allocate-set-batch') == 0 || C.strcmp(argv[1], c'pool-preview-set-batch') == 0) {
			if argc < 7 || argc > 259 || (argc - 3) % 4 != 0 { return usage() }
			mut batch := &MultiPoolBatch(C.alloca(sizeof(MultiPoolBatch)))
			*batch = MultiPoolBatch{count: (argc - 3) / 4}
			for i in 0 .. batch.count {
				at := 3 + i * 4
				pool := decimal(argv[at]) or { return usage() }; slot := decimal(argv[at + 1]) or { return usage() }
				length := decimal(argv[at + 2]) or { return usage() }
				if pool >= 64 || slot >= 64 || length == 0 || (C.strcmp(argv[at + 3], c'rw') != 0 && C.strcmp(argv[at + 3], c'ro') != 0) { return usage() }
				batch.pools[i] = u32(pool); batch.rows[i] = Request{slot: u32(slot), length: length,
					flags: if C.strcmp(argv[at + 3], c'ro') == 0 { u64(1) } else { u64(0) }}
			}
			return multi_pool_batch_plan(argv[2], batch, C.strcmp(argv[1], c'pool-preview-set-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'plan-contract-capacity-batch') == 0 || C.strcmp(argv[1], c'plan-preview-contract-capacity-batch') == 0) {
			if argc < 6 || argc > 195 || (argc - 3) % 3 != 0 { return usage() }
			mut batch := &CapacityContractBatch(C.alloca(sizeof(CapacityContractBatch)))
			*batch = CapacityContractBatch{count: (argc - 3) / 3}
			for i in 0 .. batch.count {
				at := 3 + i * 3
				if !parse_disk_identity(argv[at], mut batch.keys[i]) || argv[at + 1][0] == 0 { return usage() }
				end := decimal(argv[at + 2]) or { return usage() }; if end == 0 { return usage() }
				batch.devices[i] = argv[at + 1]; batch.expected[i] = end
			}
			return contract_capacity_batch_plan(argv[2], batch, C.strcmp(argv[1], c'plan-preview-contract-capacity-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'pool-resize-batch') == 0 || C.strcmp(argv[1], c'pool-preview-resize-batch') == 0) {
			if argc < 7 || argc > 259 || (argc - 3) % 4 != 0 { return usage() }
			mut batch := &PoolResizeBatch(C.alloca(sizeof(PoolResizeBatch)))
			*batch = PoolResizeBatch{count: (argc - 3) / 4}
			for i in 0 .. batch.count {
				at := 3 + i * 4
				if !parse_disk_identity(argv[at], mut batch.rows[i].key) { return usage() }
				pool := decimal(argv[at + 1]) or { return usage() }
				start := decimal(argv[at + 2]) or { return usage() }
				end := decimal(argv[at + 3]) or { return usage() }
				if pool >= 64 || start >= end { return usage() }
				batch.rows[i].pool = u32(pool); batch.rows[i].start = start; batch.rows[i].end = end
			}
			return resize_batch_pool_plan(argv[2], batch, C.strcmp(argv[1], c'pool-preview-resize-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'pool-contract-batch') == 0 || C.strcmp(argv[1], c'pool-preview-contract-batch') == 0) {
			if argc < 6 || argc > 132 || (argc - 4) % 2 != 0 { return usage() }
			pool := decimal(argv[3]) or { return usage() }; if pool >= 64 { return usage() }
			mut batch := &PoolContractionBatch(C.alloca(sizeof(PoolContractionBatch)))
			*batch = PoolContractionBatch{count: (argc - 4) / 2}
			for i in 0 .. batch.count {
				at := 4 + i * 2
				if !parse_disk_identity(argv[at], mut batch.keys[i]) { return usage() }
				end := decimal(argv[at + 1]) or { return usage() }; if end == 0 { return usage() }; batch.ends[i] = end
			}
			return contract_batch_pool_plan(argv[2], u32(pool), batch, C.strcmp(argv[1], c'pool-preview-contract-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'plan-grow-batch') == 0 || C.strcmp(argv[1], c'plan-preview-grow-batch') == 0) {
			if argc < 6 || argc > 195 || (argc - 3) % 3 != 0 { return usage() }
			mut batch := &MappingGrowthBatch(C.alloca(sizeof(MappingGrowthBatch)))
			*batch = MappingGrowthBatch{count: (argc - 3) / 3}
			for i in 0 .. batch.count {
				at := 3 + i * 3
				if !parse_disk_identity(argv[at], mut batch.keys[i]) { return usage() }
				slot := decimal(argv[at + 1]) or { return usage() }
				length := decimal(argv[at + 2]) or { return usage() }
				if slot >= 64 || length == 0 { return usage() }
				batch.slots[i] = u32(slot); batch.lengths[i] = length
			}
			return grow_batch_bundle_plan(argv[2], batch, C.strcmp(argv[1], c'plan-preview-grow-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'plan-add-batch') == 0 || C.strcmp(argv[1], c'plan-preview-add-batch') == 0) {
			if argc < 8 || argc > 323 || (argc - 3) % 5 != 0 { return usage() }
			mut batch := &MappingAdditionBatch(C.alloca(sizeof(MappingAdditionBatch)))
			*batch = MappingAdditionBatch{count: (argc - 3) / 5}
			for i in 0 .. batch.count {
				at := 3 + i * 5
				if !parse_disk_identity(argv[at], mut batch.keys[i]) { return usage() }
				slot := decimal(argv[at + 1]) or { return usage() }
				offset := decimal(argv[at + 2]) or { return usage() }
				length := decimal(argv[at + 3]) or { return usage() }
				if slot >= 64 || length == 0 || (C.strcmp(argv[at + 4], c'rw') != 0 && C.strcmp(argv[at + 4], c'ro') != 0) { return usage() }
				batch.rows[i] = Request{slot: u32(slot), offset: offset, length: length,
					flags: if C.strcmp(argv[at + 4], c'ro') == 0 { u64(1) } else { u64(0) }}
			}
			return add_batch_bundle_plan(argv[2], batch, C.strcmp(argv[1], c'plan-preview-add-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'plan-forget-batch') == 0 || C.strcmp(argv[1], c'plan-preview-forget-batch') == 0) {
			if argc < 4 || argc > 67 { return usage() }
			mut batch := &DiskForgetBatch(C.alloca(sizeof(DiskForgetBatch)))
			*batch = DiskForgetBatch{count: argc - 3}
			for i in 0 .. batch.count { if !parse_disk_identity(argv[3 + i], mut batch.keys[i]) { return usage() } }
			return forget_batch_bundle_plan(argv[2], batch, C.strcmp(argv[1], c'plan-preview-forget-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'plan-enroll-batch') == 0 || C.strcmp(argv[1], c'plan-preview-enroll-batch') == 0) {
			if argc < 4 || argc > 67 { return usage() }
			for i in 3 .. argc { if argv[i][0] == 0 { return usage() } }
			return enroll_batch_bundle_plan(argv[2], argc - 3, &argv[3], C.strcmp(argv[1], c'plan-preview-enroll-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'plan-remove-batch') == 0 || C.strcmp(argv[1], c'plan-preview-remove-batch') == 0) {
			if argc < 4 || argc > 67 { return usage() }
			mut batch := &MappingRemovalBatch(C.alloca(sizeof(MappingRemovalBatch)))
			*batch = MappingRemovalBatch{count: argc - 3}
			for i in 0 .. batch.count {
				slot := decimal(argv[3 + i]) or { return usage() }
				if slot >= 64 { return usage() }
				batch.slots[i] = u32(slot)
			}
			return remove_batch_bundle_plan(argv[2], batch, C.strcmp(argv[1], c'plan-preview-remove-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'pool-order') == 0 || C.strcmp(argv[1], c'pool-preview-order') == 0) {
			if argc < 5 || argc > 68 { return usage() }
			pool := decimal(argv[3]) or { return usage() }
			if pool >= 64 { return usage() }
			mut order := &PoolOrder(C.alloca(sizeof(PoolOrder)))
			*order = PoolOrder{count: argc - 4}
			for i in 0 .. order.count {
				disk := decimal(argv[4 + i]) or { return usage() }
				if disk >= 64 { return usage() }
				order.disks[i] = u32(disk)
			}
			return order_pool_plan(argv[2], u32(pool), order, C.strcmp(argv[1], c'pool-preview-order') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'pool-add-batch') == 0
			|| C.strcmp(argv[1], c'pool-preview-add-batch') == 0
			|| C.strcmp(argv[1], c'pool-remove-batch') == 0
			|| C.strcmp(argv[1], c'pool-preview-remove-batch') == 0) {
			remove := C.strcmp(argv[1], c'pool-remove-batch') == 0 || C.strcmp(argv[1], c'pool-preview-remove-batch') == 0
			width := if remove { 1 } else { 4 }
			if argc < 4 + width || argc > 4 + width * 64 || (argc - 4) % width != 0 { return usage() }
			pool := decimal(argv[3]) or { return usage() }
			if pool >= 64 { return usage() }
			mut batch := &PoolMembersBatch(C.alloca(sizeof(PoolMembersBatch)))
			*batch = PoolMembersBatch{count: (argc - 4) / width}
			for i in 0 .. batch.count {
				at := 4 + width * i
				disk := decimal(argv[at]) or { return usage() }
				if disk >= 64 { return usage() }
				batch.rows[i] = PoolRegion{pool: u32(pool), disk: u32(disk)}
				if !remove {
					window := SpaceWindow{start: decimal(argv[at + 1]) or { return usage() },
						end: decimal(argv[at + 2]) or { return usage() }, alignment: decimal(argv[at + 3]) or { return usage() }}
					if !space_window_valid(window) { return usage() }
					batch.rows[i].window = window
				}
			}
			preview := C.strcmp(argv[1], c'pool-preview-add-batch') == 0 || C.strcmp(argv[1], c'pool-preview-remove-batch') == 0
			return members_batch_pool_plan(argv[2], u32(pool), batch, remove, preview)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'plan-capacity-batch') == 0 || C.strcmp(argv[1], c'plan-preview-capacity-batch') == 0) {
			if argc < 6 || argc > 195 || (argc - 3) % 3 != 0 { return usage() }
			mut batch := &CapacityBatch(C.alloca(sizeof(CapacityBatch)))
			*batch = CapacityBatch{count: (argc - 3) / 3}
			for i in 0 .. batch.count {
				at := 3 + i * 3
				disk := decimal(argv[at]) or { return usage() }
				expected := decimal(argv[at + 2]) or { return usage() }
				if disk >= 64 || expected == 0 || argv[at + 1][0] == 0 { return usage() }
				batch.disks[i] = u32(disk); batch.devices[i] = argv[at + 1]; batch.expected[i] = expected
			}
			return capacity_batch_bundle_plan(argv[2], batch, C.strcmp(argv[1], c'plan-preview-capacity-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'pool-expand-batch') == 0 || C.strcmp(argv[1], c'pool-preview-expand-batch') == 0) {
			if argc < 6 || argc > 132 || (argc - 4) % 2 != 0 { return usage() }
			pool := decimal(argv[3]) or { return usage() }
			if pool >= 64 { return usage() }
			mut batch := &PoolExpansionBatch(C.alloca(sizeof(PoolExpansionBatch)))
			*batch = PoolExpansionBatch{count: (argc - 4) / 2}
			for i in 0 .. batch.count {
				disk := decimal(argv[4 + i * 2]) or { return usage() }
				end := decimal(argv[5 + i * 2]) or { return usage() }
				if disk >= 64 || end == 0 { return usage() }
				batch.disks[i] = u32(disk); batch.ends[i] = end
			}
			return expand_batch_pool_plan(argv[2], u32(pool), batch, C.strcmp(argv[1], c'pool-preview-expand-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'pool-grow-batch') == 0 || C.strcmp(argv[1], c'pool-preview-grow-batch') == 0) {
			if argc < 6 || argc > 132 || (argc - 4) % 2 != 0 { return usage() }
			pool := decimal(argv[3]) or { return usage() }
			if pool >= 64 { return usage() }
			mut batch := &PoolGrowthBatch(C.alloca(sizeof(PoolGrowthBatch)))
			*batch = PoolGrowthBatch{count: (argc - 4) / 2}
			for i in 0 .. batch.count {
				slot := decimal(argv[4 + i * 2]) or { return usage() }
				length := decimal(argv[5 + i * 2]) or { return usage() }
				if slot >= 64 || length == 0 { return usage() }
				batch.slots[i] = u32(slot)
				batch.lengths[i] = length
			}
			return grow_batch_pool_plan(argv[2], u32(pool), batch, C.strcmp(argv[1], c'pool-preview-grow-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'pool-allocate-batch') == 0 || C.strcmp(argv[1], c'pool-preview-batch') == 0) {
			if argc < 7 || argc > 196 || (argc - 4) % 3 != 0 { return usage() }
			pool := decimal(argv[3]) or { return usage() }
			if pool >= 64 { return usage() }
			mut batch := &PoolBatch(C.alloca(sizeof(PoolBatch)))
			*batch = PoolBatch{count: (argc - 4) / 3}
			for i in 0 .. batch.count {
				at := 4 + i * 3
				slot := decimal(argv[at]) or { return usage() }
				length := decimal(argv[at + 1]) or { return usage() }
				if slot >= 64 || length == 0 || (C.strcmp(argv[at + 2], c'rw') != 0
					&& C.strcmp(argv[at + 2], c'ro') != 0) { return usage() }
				batch.rows[i] = Request{slot: u32(slot), length: length,
					flags: if C.strcmp(argv[at + 2], c'ro') == 0 { u64(1) } else { u64(0) }}
			}
			return batch_pool_plan(argv[2], u32(pool), batch, C.strcmp(argv[1], c'pool-preview-batch') == 0)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'pool-expand') == 0 || C.strcmp(argv[1], c'pool-grow') == 0) {
			if argc != 6 { return usage() }
			pool := decimal(argv[3]) or { return usage() }
			index := decimal(argv[4]) or { return usage() }
			size := decimal(argv[5]) or { return usage() }
			if pool >= 64 || index >= 64 || size == 0 { return usage() }
			return grow_pool_plan(argv[2], u32(pool), u32(index), size, C.strcmp(argv[1], c'pool-expand') == 0)
		}
		if argc >= 2 && C.strcmp(argv[1], c'pool-add') == 0 {
			if argc != 8 { return usage() }
			pool := decimal(argv[3]) or { return usage() }
			disk := decimal(argv[4]) or { return usage() }
			window := SpaceWindow{start: decimal(argv[5]) or { return usage() },
				end: decimal(argv[6]) or { return usage() }, alignment: decimal(argv[7]) or { return usage() }}
			if pool >= 64 || disk >= 64 || !space_window_valid(window) { return usage() }
			region := PoolRegion{pool: u32(pool), disk: u32(disk), window: window}
			return edit_pool_plan(argv[2], &region, false)
		}
		if argc >= 2 && C.strcmp(argv[1], c'pool-remove') == 0 {
			if argc != 5 { return usage() }
			pool := decimal(argv[3]) or { return usage() }
			disk := decimal(argv[4]) or { return usage() }
			if pool >= 64 || disk >= 64 { return usage() }
			region := PoolRegion{pool: u32(pool), disk: u32(disk)}
			return edit_pool_plan(argv[2], &region, true)
		}
		if argc >= 2 && C.strcmp(argv[1], c'pool-space') == 0 {
			if argc != 4 { return usage() }
			pool := decimal(argv[3]) or { return usage() }
			if pool >= 64 { return usage() }
			return space_pool_plan(argv[2], u32(pool))
		}
		if argc >= 2 && C.strcmp(argv[1], c'pool-allocate') == 0 {
			if argc != 6 && argc != 7 { return usage() }
			pool := decimal(argv[3]) or { return usage() }
			slot := decimal(argv[4]) or { return usage() }
			length := decimal(argv[5]) or { return usage() }
			if pool >= 64 || slot >= 64 || length == 0 { return usage() }
			mut row := Request{slot: u32(slot), length: length}
			if argc == 7 {
				if C.strcmp(argv[6], c'ro') != 0 { return usage() }
				row.flags = 1
			}
			return allocate_pool_plan(argv[2], u32(pool), &row)
		}
		if argc >= 2 && C.strcmp(argv[1], c'plan-capacity') == 0 {
			if argc != 6 { return usage() }
			disk := decimal(argv[3]) or { return usage() }
			expected := decimal(argv[5]) or { return usage() }
			if disk >= 64 || expected == 0 { return usage() }
			return capacity_bundle_plan(argv[2], int(disk), argv[4], expected)
		}
		if argc >= 2 && (C.strcmp(argv[1], c'plan-space') == 0
			|| C.strcmp(argv[1], c'plan-allocate') == 0) {
			allocate := C.strcmp(argv[1], c'plan-allocate') == 0
			if (!allocate && argc != 7) || (allocate && argc != 9 && argc != 10) { return usage() }
			disk := decimal(argv[3]) or { return usage() }
			if disk >= 64 { return usage() }
			mut row := Request{}
			if allocate {
				slot := decimal(argv[4]) or { return usage() }
				row.length = decimal(argv[5]) or { return usage() }
				if slot >= 64 || row.length == 0 { return usage() }
				row.slot = u32(slot)
				if argc == 10 {
					if C.strcmp(argv[9], c'ro') != 0 { return usage() }
					row.flags = 1
				}
			}
			at := if allocate { 6 } else { 4 }
			window := SpaceWindow{start: decimal(argv[at]) or { return usage() },
				end: decimal(argv[at + 1]) or { return usage() },
				alignment: decimal(argv[at + 2]) or { return usage() }}
			if !space_window_valid(window) { return usage() }
			return space_bundle_plan(argv[2], int(disk), window, &row, allocate)
		}
		if argc >= 2 && C.strcmp(argv[1], c'plan-enroll') == 0 {
			if argc != 4 { return usage() }
			return enroll_bundle_disk(argv[2], argv[3])
		}
		if argc >= 2 && C.strcmp(argv[1], c'plan-forget') == 0 {
			if argc != 4 { return usage() }
			disk := decimal(argv[3]) or { return usage() }
			if disk >= 64 { return usage() }
			return forget_bundle_disk(argv[2], int(disk))
		}
		if argc >= 2 && C.strcmp(argv[1], c'plan-add') == 0 {
			if argc != 7 && argc != 8 { return usage() }
			disk := decimal(argv[3]) or { return usage() }
			slot := decimal(argv[4]) or { return usage() }
			offset := decimal(argv[5]) or { return usage() }
			length := decimal(argv[6]) or { return usage() }
			if disk >= 64 || slot >= 64 || length == 0 { return usage() }
			mut row := Request{slot: u32(slot), offset: offset, length: length}
			if argc == 8 {
				if C.strcmp(argv[7], c'ro') != 0 { return usage() }
				row.flags = 1
			}
			return edit_bundle_plan(argv[2], int(disk), &row, false)
		}
		if argc >= 2 && C.strcmp(argv[1], c'plan-remove') == 0 {
			if argc != 4 { return usage() }
			slot := decimal(argv[3]) or { return usage() }
			if slot >= 64 { return usage() }
			row := Request{slot: u32(slot)}
			return edit_bundle_plan(argv[2], 0, &row, true)
		}
		if argc >= 2 && C.strcmp(argv[1], c'show-bundle') == 0 {
			if argc != 3 { return usage() }
			return inspect_bundle(argv[2], false, false)
		}
		if argc >= 2 && C.strcmp(argv[1], c'check-bundle') == 0 {
			if argc != 3 && argc != 4 { return usage() }
			if argc == 4 && C.strcmp(argv[3], c'grow') != 0 { return usage() }
			return inspect_bundle(argv[2], true, argc == 4)
		}
		if argc >= 2 && C.strcmp(argv[1], c'save-set') == 0 {
			if argc < 4 || argc > 67 { return usage() }
			return save_bundle(argv[2], int(argc - 3), argv + 3)
		}
		if argc >= 2 && C.strcmp(argv[1], c'plan-grow') == 0 {
			if argc != 5 { return usage() }
			slot := decimal(argv[3]) or { return usage() }
			length := decimal(argv[4]) or { return usage() }
			if slot >= 64 || length == 0 { return usage() }
			return grow_bundle_plan(argv[2], u32(slot), length)
		}
		if argc >= 2 && C.strcmp(argv[1], c'restore-bundle') == 0 {
			if argc != 3 && argc != 4 { return usage() }
			if argc == 4 && C.strcmp(argv[3], c'grow') != 0 { return usage() }
			return restore_bundle(argv[2], argc == 4)
		}
		if argc >= 2 && C.strcmp(argv[1], c'monitor') == 0 {
			if argc != 4 && argc != 5 { return usage() }
			interval := decimal(argv[3]) or { return usage() }
			if interval == 0 || interval > 86400 { return usage() }
			mut samples := u64(0)
			if argc == 5 {
				samples = decimal(argv[4]) or { return usage() }
				if samples == 0 { return usage() }
			}
			return monitor_device(argv[2], u32(interval), samples)
		}
		if argc == 3 && C.strcmp(argv[1], c'health') == 0 { return query_health(argv[2]) }
		if argc == 2 && C.strcmp(argv[1], c'boot-restore') == 0 { return boot_restore() }
		if argc == 3 && C.strcmp(argv[1], c'discover') == 0 { return automatic_plan(argv[2], false) }
		if argc == 3 && C.strcmp(argv[1], c'restore-auto') == 0 { return automatic_plan(argv[2], true) }
		if argc == 3 && C.strcmp(argv[1], c'restore-set') == 0 { return restore_set_directory(argv[2]) }
	}
	if argc < 3 { return usage() }
	unsafe {
		if C.strcmp(argv[1], c'save') == 0 && argc == 4 { return save_plan(argv[2], argv[3]) }
		if C.strcmp(argv[1], c'restore') == 0 && argc == 4 { return restore_plan(argv[2], argv[3]) }
	}
	mut request := u64(0)
	mut data := Request{}
	mut range := [2]u64{}
	unsafe {
		if C.strcmp(argv[1], c'status') == 0 && argc == 3 {
			request = 0x56560004
		} else if C.strcmp(argv[1], c'remove') == 0 && argc == 3 {
			request = 0x56560003
		} else if C.strcmp(argv[1], c'grow') == 0 && argc == 4 {
			request = 0x56560002
			data.length = decimal(argv[3]) or { return usage() }
		} else if C.strcmp(argv[1], c'discard') == 0 && argc == 5 {
			request = 0x1277
			range[0] = decimal(argv[3]) or { return usage() }
			range[1] = decimal(argv[4]) or { return usage() }
		} else if C.strcmp(argv[1], c'create') == 0 && (argc == 6 || argc == 7) {
			request = 0x56560001
			slot := decimal(argv[3]) or { return usage() }
			if slot >= 64 { return usage() }
			data.slot = u32(slot)
			data.offset = decimal(argv[4]) or { return usage() }
			data.length = decimal(argv[5]) or { return usage() }
			if argc == 7 {
				if C.strcmp(argv[6], c'ro') != 0 { return usage() }
				data.flags = 1
			}
		} else {
			return usage()
		}
	}
	flags := i32(if request == 0x1277 || (request == 0x56560001 && data.flags == 0) { C.O_RDWR } else { C.O_RDONLY }) | i32(C.O_CLOEXEC)
	fd := unsafe { C.open(argv[2], flags) }
	if fd < 0 {
		C.perror(c'vinix-volume: open')
		return 1
	}
	defer { C.close(fd) }
	if request == 0x56560004 {
		mut result := Status{}
		if C.ioctl(fd, request, &result) != 0 {
			C.perror(c'vinix-volume: status')
			return 1
		}
		if result.version != 1 || result.reserved != 0 {
			C.printf(c'vinix-volume: unsupported status version\n')
			return 1
		}
		C.printf(c'bytes=%lu sector=%lu readonly=%lu offline=%lu flush=%lu discard=%lu encrypted=%lu\nreads=%lu writes=%lu read_bytes=%lu write_bytes=%lu flushes=%lu\nerrors=%lu last_error=%lu disk=%lu offset=%lu slot=%lu generation=%lu\n',
			result.bytes, result.sector, result.flags & 1, (result.flags >> 1) & 1, (result.flags >> 2) & 1,
			(result.flags >> 5) & 1, (result.flags >> 6) & 1,
			result.reads, result.writes, result.read_bytes, result.write_bytes, result.flushes,
			result.errors, result.last_error, result.disk_id, result.start, result.slot, result.generation)
	} else if request == 0x1277 {
		if C.ioctl(fd, request, &range[0]) != 0 {
			C.perror(c'vinix-volume: discard')
			return 1
		}
	} else {
		if C.ioctl(fd, request, &data) != 0 {
			C.perror(c'vinix-volume: change')
			return 1
		}
		if request == 0x56560001 { C.printf(c'/dev/mapper/vinix%u\n', data.slot) }
	}
	return 0
}

$if !volume_library ? {
	@[export: 'main']
	pub fn entry(argc i32, argv &&char) i32 { return run(argc, argv) }
}
