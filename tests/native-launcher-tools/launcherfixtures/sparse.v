// SPDX-License-Identifier: GPL-2.0-or-later
module launcherfixtures

import os
import steamshim
import tarcore
import tarstream

fn C.mkdtemp(&char) &char

fn pax(key string, value string) string {
	mut length := key.len + value.len + 4
	for {
		row := length.str() + ' ' + key + '=' + value + '\n'
		if row.len == length { return row }
		length = row.len
	}
	return ''
}

fn octal(mut bytes []u8, start int, length int, value i64) {
	digits := '${value:o}'
	text := '0'.repeat(length - 1 - digits.len) + digits + '\x00'
	for i, ch in text.bytes() { bytes[start + i] = ch }
}

fn checksum(mut bytes []u8) {
	for i in 148 .. 156 { bytes[i] = 32 }
	mut total := i64(0)
	for byte in bytes { total += byte }
	digits := '${total:o}'
	text := '0'.repeat(6 - digits.len) + digits + '\x00 '
	for i, ch in text.bytes() { bytes[148 + i] = ch }
}

pub fn sparse_cases(work string, options steamshim.TarOptions) ! {
	os.mkdir_all(work)!
	payload := 'ABCD'.bytes()
	expected := 'A' + '\x00'.repeat(4095) + 'BCD' + '\x00'.repeat(4093)
	for kind in ['old-gnu', 'old-gnu-extended', 'pax-00', 'pax-01', 'pax-10'] {
		path := work + '/' + kind + '.tar'
		mut writer := tarcore.create(path)!
		if kind.starts_with('old-gnu') {
			mut header := tarcore.header(tarcore.Member{ name: 'sparse', size: 4, kind: `S` })!
			if kind == 'old-gnu' {
				octal(mut header, 386, 12, 0)
				octal(mut header, 398, 12, 1)
				octal(mut header, 410, 12, 4096)
				octal(mut header, 422, 12, 3)
			} else {
				header[482] = 1
			}
			octal(mut header, 483, 12, 8192)
			checksum(mut header)
			writer.write(header)!
			if kind == 'old-gnu-extended' {
				mut block := []u8{len: 512}
				octal(mut block, 0, 12, 0)
				octal(mut block, 12, 12, 1)
				octal(mut block, 24, 12, 4096)
				octal(mut block, 36, 12, 3)
				writer.write(block)!
			}
			writer.write(payload)!
			writer.padding(4)!
		} else {
			mut records := pax('GNU.sparse.name', 'sparse')
			mut data := payload.clone()
			if kind == 'pax-00' {
				records += pax('GNU.sparse.size', '8192') + pax('GNU.sparse.offset', '0') + pax('GNU.sparse.numbytes', '1') + pax('GNU.sparse.offset', '4096') + pax('GNU.sparse.numbytes', '3')
			} else if kind == 'pax-01' {
				records += pax('GNU.sparse.size', '8192') + pax('GNU.sparse.map', '0,1,4096,3')
			} else {
				records += pax('GNU.sparse.major', '1') + pax('GNU.sparse.minor', '0') + pax('GNU.sparse.realsize', '8192')
				mut prefix := '2\n0\n1\n4096\n3\n'.bytes()
				prefix << []u8{len: 512 - prefix.len}
				prefix << payload
				data = prefix.clone()
			}
			writer.add(tarcore.Member{ name: 'pax', kind: `x`, size: records.len }, records.bytes())!
			writer.add(tarcore.Member{ name: 'unused', size: data.len }, data)!
		}
		writer.add(tarcore.Member{ name: 'after', size: 5 }, 'after'.bytes())!
		writer.finish()!
		writer.close()
		destination := work + '/' + kind
		steamshim.extract(path, destination, options)!
		assert os.read_file(destination + '/sparse')! == expected, kind
		assert os.read_file(destination + '/after')! == 'after', kind
	}
	path := work + '/fractional.tar'
	mut writer := tarcore.create(path)!
	records := pax('mtime', '123.25')
	writer.add(tarcore.Member{ name: 'pax', kind: `x`, size: records.len }, records.bytes())!
	writer.add(tarcore.Member{ name: 'file', size: 4 }, payload)!
	writer.add(tarcore.Member{ name: 'hard', kind: `1`, linkname: './file' }, []u8{})!
	writer.finish()!
	writer.close()
	mut check := tarstream.open_plain(path)!
	assert check.next()!.name == 'file'
	assert check.modification_time() == '123.25', check.modification_time()
	check.close()
	// HFS+ RAM volumes store integral times. Verify the fractional SDK operation
	// on the host's normal cache filesystem, with an exclusive owned directory.
	mut pattern := (os.getenv('HOME') + '/.cache/vinix-pax-time.XXXXXX\x00').bytes()
	assert C.mkdtemp(pattern.data) != unsafe { nil }
	destination := pattern.bytestr().all_before('\x00')
	defer { os.rmdir_all(destination) or {} }
	os.write_file(destination + '/hard', 'existing target')!
	steamshim.extract(path, destination, options)!
	assert os.read_file(destination + '/hard')! == 'ABCD'
	result := os.exec(['/usr/bin/stat', '-f', '%Fm', destination + '/hard'])
	assert result.exit_code == 0 && result.output.trim_space() == '123.250000000', result.output
	println('PASS normalized archive hard-link fallback and fractional PAX modification time')
	println('PASS original GNU and PAX 0.0/0.1/1.0 sparse bytes, holes, size and following-member boundaries')
}
