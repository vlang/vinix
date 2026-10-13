// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn scrub_view_fixture(mask int) string {
	zero := '0'.repeat(64); mut changed := 0; for i in 0 .. 3 { if mask & (1 << i) != 0 { changed++ } }
	mut text := 'format=VINIXSR1 operation=scrubbed-data disks=2 mappings=3 matched=${3 - changed} changed=${changed} algorithm=sha256 reference_sha256=${zero}\n'
	for i in 0 .. 3 {
		different := mask & (1 << i) != 0
		text += 'disk=${if i == 2 { 1 } else { 0 }} slot=${63 - i} offset=${i * 4096} bytes=512 readonly=${i & 1} result=${if different { 'changed' } else { 'match' }} expected_sha256=${zero} actual_sha256=${if different { 'f'.repeat(64) } else { zero }}\n'
	}
	return text
}

fn test_scrub_view_all_change_masks_truncations_embedded_nuls_and_trailing_bytes() {
	for mask in 0 .. 8 {
		text := scrub_view_fixture(mask)
		assert scrub_report_valid(text.str, text.len)
		for size in 0 .. text.len { assert !scrub_report_valid(text.str, size) }
		for at in 0 .. text.len { mut broken := text.bytes(); broken[at] = 0; assert !scrub_report_valid(broken.data, broken.len) }
		for suffix in ['\n', ' ', 'disk=1\n', '\x00', '\r\n'] { broken := text + suffix; assert !scrub_report_valid(broken.str, broken.len) }
	}
}

fn test_scrub_view_rejects_noncanonical_or_inconsistent_headers_and_later_rows() {
	text := scrub_view_fixture(5)
	for pair in [
		['VINIXSR1', 'VINIXSR2'], ['scrubbed-data', 'scrubbed-ciphertext'], ['disks=2', 'disks=0'], ['disks=2', 'disks=65'],
		['disks=2', 'disks=02'], ['disks=2', 'disks=+2'], ['disks=2', 'disks=18446744073709551616'],
		['mappings=3', 'mappings=2'], ['mappings=3', 'mappings=4'], ['mappings=3', 'mappings=65'],
		['matched=1', 'matched=2'], ['changed=2', 'changed=1'], ['algorithm=sha256', 'algorithm=sha512'],
		['disk=1 slot=61', 'disk=2 slot=61'],
		['slot=61', 'slot=62'], ['slot=61', 'slot=64'], ['offset=8192', 'offset=1'],
		['offset=8192', 'offset=9223372036854775808'], ['offset=8192', 'offset=9223372036854775296'],
		['bytes=512 readonly=0 result=changed', 'bytes=0 readonly=0 result=changed'],
		['bytes=512 readonly=0 result=changed', 'bytes=513 readonly=0 result=changed'],
		['bytes=512 readonly=0 result=changed', 'bytes=2305843009213693952 readonly=0 result=changed'],
		['readonly=1', 'readonly=2'], ['result=changed', 'result=match'], ['result=match', 'result=changed'],
		['actual_sha256=' + 'f'.repeat(64), 'actual_sha256=' + 'F'.repeat(64)],
		['reference_sha256=' + '0'.repeat(64), 'reference_sha256=' + '0'.repeat(63)],
		['reference_sha256=' + '0'.repeat(64), 'reference_sha256=' + 'g'.repeat(64)],
		['disk=1', 'disk=01'], ['offset=8192', 'offset=-8192'], [' bytes=', '  bytes='], ['\n', '\r\n']
	] { broken := text.replace(pair[0], pair[1]); assert broken != text && !scrub_report_valid(broken.str, broken.len), pair.str() }
	// Disk order is canonical; saved slots and offsets need not be ascending.
	ordered := text.replace('disk=0 slot=62', 'disk=1 slot=62').replace('disk=1 slot=61', 'disk=0 slot=61')
	assert !scrub_report_valid(ordered.str, ordered.len)
	overlap := text.replace('disk=1 slot=61 offset=8192', 'disk=0 slot=61 offset=4096')
	assert !scrub_report_valid(overlap.str, overlap.len)
}

fn test_scrub_view_maximum_and_empty_saved_sets_and_producer_compatibility() {
	zero := '0'.repeat(64)
	for disks in 1 .. 65 {
		empty := 'format=VINIXSR1 operation=scrubbed-data disks=${disks} mappings=0 matched=0 changed=0 algorithm=sha256 reference_sha256=${zero}\n'
		assert scrub_report_valid(empty.str, empty.len)
	}
	mut text := 'format=VINIXSR1 operation=scrubbed-data disks=64 mappings=64 matched=0 changed=64 algorithm=sha256 reference_sha256=${zero}\n'
	for disk in 0 .. 64 { text += 'disk=${disk} slot=${63 - disk} offset=9223372036854774784 bytes=512 readonly=${disk & 1} result=changed expected_sha256=${zero} actual_sha256=' + 'f'.repeat(64) + '\n' }
	assert text.len > 12000 && scrub_report_valid(text.str, text.len)
	assert !scrub_report_valid(text.str, 32768) && !scrub_report_valid(text.str, -1)
	mut manifest := DataManifest{}; mut plan := Plan{count: 12, key: DiskKey{bytes: 1048576, sector: 512, kind: 1}}; plan.key.id[0] = 0x37
	for i in 0 .. 12 { plan.rows[i] = Request{slot: u32(63 - i), offset: u64(i * 4096), length: 512, flags: u64(i & 1)}; manifest.digests.slots[i] = u32(63 - i) }
	assert append_plan(mut manifest.set, &plan); manifest.digests.count = 12
	for mask in 0 .. 4096 {
		mut observed := manifest.digests; for i in 0 .. 12 { if mask & (1 << i) != 0 { observed.values[i][i] ^= 1 } }
		mut bytes := [32768]char{}; size := encode_scrub_report(&manifest, &observed, &bytes[0])
		assert size > 0 && scrub_report_valid(unsafe { &u8(&bytes[0]) }, size)
	}
}

fn test_scrub_view_cli_exact_arity_and_empty_path() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'show-data-scrub'), &char(c'/missing'), &char(c'extra'), &char(nil)]!
		for count in [2, 4, 5] { assert run(count, &args[0]) == 2 }
		args[2] = &char(c''); assert run(3, &args[0]) == 2
		args[2] = &char(c'/missing'); assert run(3, &args[0]) == 1
	}
}
