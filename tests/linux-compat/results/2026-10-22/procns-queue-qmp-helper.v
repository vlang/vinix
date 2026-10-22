import crypto.sha256
import json2
import os
import qmpclient
import strconv
import time

fn read_words(mut monitor qmpclient.Monitor, address u64, count int) !([]u64, string) {
	command := 'x /' + count.str() + 'gx 0x' + address.hex()
	raw := monitor.request('human-monitor-command', {'command-line': json2.Any(command), 'cpu-index': json2.Any(0)})!.str()
	mut words := []u64{}
	for item in raw.fields() {
		field := item.trim_space()
		if field.starts_with('0x') && !field.ends_with(':') { words << strconv.parse_uint(field[2..], 16, 64)! }
	}
	if words.len != count { return error('Unexpected memory response: ' + raw) }
	return words, raw
}

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	for tag in os.args[1..] {
		before := tag.contains('-before-')
		link := area + '/q-' + sha256.sum(tag.bytes()).hex()[..12] + '.sock'
		if !os.exists(link) { os.symlink(area + '/states/' + tag + '/qmp.sock', link)! }
		mut monitor := qmpclient.connect_bounded(link, u64(time.sys_mono_now()) + u64(10_000_000_000), unsafe { nil })!
		queue := if before { u64(0xffffffff803a64b8) } else { u64(0xffffffff803a74b8) }
		big := if before { u64(0xffffffff80daaee8) } else { u64(0xffffffff80dabee8) }
		last := if before { u64(0xffffffff80daad68) } else { u64(0xffffffff80dabd68) }
		header, raw := read_words(mut monitor, queue, 6)!
		pages, raw_pages := read_words(mut monitor, big, 1)!
		reaped, raw_reaped := read_words(mut monitor, last, 1)!
		bytes := header[3] * header[5]
		mut result := {'utc': time.utc().str(), 'tag': tag, 'queue_address': '0x' + queue.hex(), 'queue_data': '0x' + header[0].hex(), 'queue_offset': header[1].str(), 'queue_len': header[2].str(), 'queue_cap': header[3].str(), 'queue_flags': header[4].str(), 'queue_element_size': header[5].str(), 'queue_capacity_bytes': bytes.str(), 'queue_expected_request_bytes': (bytes + 31).str(), 'queue_big_pages_if_big': ((bytes + 31 + 4095) / 4096 + 1).str(), 'heap_big_pages': pages[0].str(), 'last_reap_ns': reaped[0].str(), 'raw_array': raw, 'raw_pages': raw_pages, 'raw_last_reap': raw_reaped, 'method': 'Read-only QMP virtual memory; exact blob.c Array layout and 16-byte managed header; allocation request includes header+15 alignment padding. MallocMetadata six u64 fields pinned from big_metadata.v; snapshot not atomic.'}
		if header[0] != 0 && header[4] & 16 != 0 && bytes > 4096 {
			managed, raw_managed := read_words(mut monitor, header[0] - header[1] - 16, 2)!
			allocation := managed[0]
			metadata, raw_metadata := read_words(mut monitor, allocation - 4096, 6)!
			result['managed_header_address'] = '0x' + (header[0] - header[1] - 16).hex()
			result['allocation_address'] = '0x' + allocation.hex()
			result['metadata_address'] = '0x' + (allocation - 4096).hex()
			result['metadata_magic'] = '0x' + metadata[0].hex()
			result['metadata_pages'] = metadata[1].str()
			result['metadata_size'] = metadata[2].str()
			result['metadata_total_pages'] = (metadata[1] + 1).str()
			result['metadata_geometry_valid'] = (metadata[0] == u64(0x56494e4958424947) && metadata[3] == ~metadata[1] && metadata[4] == ~metadata[2] && (metadata[2] + 4095) / 4096 == metadata[1]).str()
			result['raw_managed_header'] = raw_managed
			result['raw_metadata'] = raw_metadata
		}
		monitor.close()
		path := area + '/qmp-queue-' + tag + '-' + time.now().unix().str() + '.json'
		os.write_file(path, json2.encode(result, prettify: true))!
		println(json2.encode(result, prettify: true))
		println(path)
	}
}
