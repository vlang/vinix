// SPDX-License-Identifier: GPL-2.0-or-later
module ansreads

import hosttest
import os
import x.json2

fn C.fcntl(int, int, ...int) int

struct Fixture {
	work     string
	source   string
	data     []u8
	manifest Manifest
}

fn fixture() !Fixture {
	work := hosttest.work_dir('', 'vinix-ans-reads-')!
	mut keep := false
	defer { if !keep { hosttest.remove_work_dir(work) or { panic(err) } } }
	source := os.join_path(work, 'image')
	data := []u8{len: 65536, init: u8((index * 17 + 3) & 255)}
	os.write_file_array(source, data)!
	manifest := record(source, [Range{ offset: 0, length: 8192 }, Range{ offset: 12345, length: 8001 },
		Range{ offset: 61440, length: 4096 }], 'synthetic host fixture')!
	keep = true
	return Fixture{work, source, data, manifest}
}

fn test_readonly_chunks_independent_sha256_and_descriptor_identity() {
	f := fixture()!
	defer { hosttest.remove_work_dir(f.work) or { panic(err) } }
	opened := open_source(f.source)!
	assert C.fcntl(opened.fd, C.F_GETFL) & C.O_ACCMODE == C.O_RDONLY
	assert C.fcntl(opened.fd, C.F_GETFD) & C.FD_CLOEXEC != 0
	assert C.write(opened.fd, c'x', 1) == -1 && C.errno == C.EBADF
	assert opened.kind == 'regular-file'
	assert C.close(opened.fd) == 0
	for passes in [1, 2, 10] {
		result := check(f.source, f.manifest.value()!, passes)!
		assert result.result == 'REFERENCE COMPARISON PASS'
		assert result.read_only && !result.physical_hardware_independently_verified
		assert result.source_kind == 'regular-file' && result.passes == passes
		assert result.ranges == 3 && result.chunk_patterns == [513, 4096, 65521]
		assert result.bytes_read == i64(8192 + 8001 + 4096) * 3 * passes
	}
	for range in f.manifest.ranges {
		fragment := os.join_path(f.work, 'fragment')
		os.write_file_array(fragment, f.data[int(range.offset)..int(range.offset + range.length)])!
		oracle := hosttest.capture(['shasum', '-a', '256', fragment], '', 30, os.environ())!
		assert oracle.code == 0 && oracle.stderr == '', oracle.stderr
		assert oracle.stdout.all_before(' ') == range.sha256
	}
	// A pathname replacement cannot redirect an already inspected source handle.
	held := open_source(f.source)!
	defer { C.close(held.fd) }
	os.rename(f.source, os.join_path(f.work, 'original'))!
	os.write_file_array(f.source, []u8{len: f.data.len, init: 0})!
	assert digest(held.fd, f.manifest.ranges[1], 513)! == f.manifest.ranges[1].sha256
	assert os.read_bytes(os.join_path(f.work, 'original'))! == f.data
}

fn check_error(source string, value Value, passes int) string {
	check(source, value, passes) or { return err.msg() }
	return 'unexpected success'
}

fn validation_error(text string) string {
	value := parse_manifest(text) or { return err.msg() }
	validate_manifest(value) or { return err.msg() }
	return 'unexpected success'
}

fn test_full_megabyte_streaming_with_all_chunk_boundaries() {
	work := hosttest.work_dir('', 'vinix-ans-large-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	source := os.join_path(work, 'image')
	data := []u8{len: max_range, init: u8((index * 17 + 3) & 255)}
	os.write_file_array(source, data)!
	manifest := record(source, [Range{ offset: 0, length: max_range }], 'large streaming fixture')!
	oracle := hosttest.capture(['shasum', '-a', '256', source], '', 30, os.environ())!
	assert oracle.code == 0 && oracle.stdout.all_before(' ') == manifest.ranges[0].sha256
	assert check(source, manifest.value()!, 2)!.bytes_read == i64(max_range) * 6
	assert os.read_bytes(source)! == data
}

fn one_range(offset string, length string, hash string) string {
	return '{"schema":"${schema}","ranges":[{"offset":${offset},"length":${length},"sha256":${json2.encode(hash)}}]}'
}

fn test_mismatch_eof_order_and_validation_precede_source_open() {
	f := fixture()!
	defer { hosttest.remove_work_dir(f.work) or { panic(err) } }
	mut changed := f.data.clone()
	changed[0] = `x`
	os.write_file_array(f.source, changed)!
	message := check_error(f.source, f.manifest.value()!, 1)
	assert message.starts_with('MISMATCH pass=1 chunk=513 offset=0 length=8192 expected=')
	assert message.contains(' actual=')
	assert os.read_bytes(f.source)! == changed
	os.write_file_array(f.source, f.data[..16384])!
	assert check_error(f.source, f.manifest.value()!, 1) == 'short read at byte 16384'
	assert os.read_bytes(f.source)! == f.data[..16384]
	os.write_file_array(f.source, f.data)!
	unsorted := Manifest{
		ranges: [Range{ offset: 61440, length: 4096, sha256: '0'.repeat(64) },
			Range{ offset: 0, length: 8192, sha256: '0'.repeat(64) }]
	}
	assert check_error(f.source, unsorted.value()!, 1).starts_with('MISMATCH pass=1 chunk=513 offset=61440 ')
	assert check_error('/absent/ans-source', f.manifest.value()!, 0) == 'passes must be 1..10'
	assert check_error('/absent/ans-source', parse_manifest('{}')!, 1) == 'unrecognized manifest schema'
	for source in ['/dev/null', f.work] {
		assert check_error(source, f.manifest.value()!, 1) == 'source must be a block device or a regular test image'
	}
	for label in ['', 'x'.repeat(257)] {
		record('/absent/ans-source', f.manifest.ranges, label) or {
			assert err.msg() == 'supply a reference label and 1..64 explicit ranges'
			continue
		}
		assert false
	}
	assert record(f.source, [Range{ offset: 0, length: 1 }], '界'.repeat(256))!.reference_label.runes().len == 256
	record(f.source, [Range{ offset: 0, length: 3 }, Range{ offset: 2, length: 1 }], 'overlap') or {
		assert err.msg() == 'overlapping or duplicate sample ranges'
		assert os.read_bytes(f.source)! == f.data
		return
	}
	assert false
}

fn test_exact_manifest_integer_types_limits_hashes_and_overlap() {
	hash := '0'.repeat(64)
	for offset in ['true', 'false', 'null', '"0"', '0.0', '0e0', '[]', '{}'] {
		assert validation_error(one_range(offset, '1', hash)) == 'range offset and length must be integers'
	}
	for offset in ['-1', '9223372036854775808', '18446744073709551616', '9'.repeat(200)] {
		assert validation_error(one_range(offset, '1', hash)) == 'range requires nonnegative offset and 1..1048576 bytes'
	}
	for length in ['0', '-1', '1048577', '9223372036854775808'] {
		assert validation_error(one_range('0', length, hash)) == 'range requires nonnegative offset and 1..1048576 bytes'
	}
	for length in ['true', '"1"', '1.0', '1e0'] {
		assert validation_error(one_range('0', length, hash)) == 'range offset and length must be integers'
	}
	assert validate_manifest(parse_manifest(one_range('9007199254740993', '1', hash))!)![0].offset == i64(9007199254740993)
	assert validate_manifest(parse_manifest(one_range('9223372036854775806', '1', hash))!)![0].offset == max_offset - 1
	assert validation_error(one_range('9223372036854775807', '1', hash)) == 'range overflows a signed 64-bit file offset'
	assert validation_error(one_range('9223372036854775806', '2', hash)) == 'range overflows a signed 64-bit file offset'
	for bad in ['', 'bad', 'A'.repeat(64), 'g'.repeat(64), '0'.repeat(63), '0'.repeat(65)] {
		assert validation_error(one_range('0', '1', bad)) == 'invalid SHA-256 digest'
	}
	for text in ['[]', 'true', '{"schema":true}', '{"schema":"unknown"}'] {
		assert validation_error(text) == 'unrecognized manifest schema'
	}
	for entries in ['[]', 'null', '{}', '[null]'] {
		assert validation_error('{"schema":"${schema}","ranges":${entries}}') != 'unexpected success'
	}
	row := '{"offset":0,"length":1,"sha256":"${hash}"}'
	for entries in [[row, row], []string{len: 65, init: row}] {
		assert validation_error('{"schema":"${schema}","ranges":[${entries.join(',')}]}') != 'unexpected success'
	}
	adjacent := Manifest{ ranges: [Range{3, 2, hash}, Range{0, 3, hash}] }
	assert validate_manifest(adjacent.value()!)![0].offset == 3
	metadata := one_range('0', '1', hash).trim_right('}') + ',"ignored":99999999999999999999999999999999999999999999}'
	assert validate_manifest(parse_manifest(metadata)!)!.len == 1
	// JSON object duplicate keys retain their last value, as the original loader.
	duplicate := one_range('0', '1', hash).replace('"offset":0', '"offset":2,"offset":0')
	assert validate_manifest(parse_manifest(duplicate)!)![0].offset == 0
}

fn save_error(path string, manifest Manifest) string {
	save_new_manifest(path, manifest) or { return err.msg() }
	return 'unexpected success'
}

fn load_error(path string) string {
	load_manifest(path) or { return err.msg() }
	return 'unexpected success'
}

fn test_manifest_exclusive_publication_permissions_roundtrip_and_bounded_load() {
	f := fixture()!
	defer { hosttest.remove_work_dir(f.work) or { panic(err) } }
	assert save_error(f.source, f.manifest) != 'unexpected success'
	alias := os.join_path(f.work, 'alias')
	os.symlink(f.source, alias)!
	assert save_error(alias, f.manifest) != 'unexpected success'
	dangling := os.join_path(f.work, 'dangling')
	missing := os.join_path(f.work, 'absent-target')
	os.symlink(missing, dangling)!
	assert save_error(dangling, f.manifest) != 'unexpected success'
	assert !os.exists(missing) && os.is_link(dangling)
	assert save_error('/dev/null', f.manifest) != 'unexpected success'
	assert save_error(f.work, f.manifest) != 'unexpected success'
	assert os.read_bytes(f.source)! == f.data
	path := os.join_path(f.work, 'reference.json')
	save_new_manifest(path, f.manifest)!
	assert os.stat(path)!.mode & 0o777 == 0o600
	assert os.read_file(path)! == f.manifest.json_text()
	assert json2.decode[Manifest](os.read_file(path)!, strict: true)! == f.manifest
	assert validate_manifest(load_manifest(path)!)! == f.manifest.ranges
	assert check(f.source, load_manifest(path)!, 1)!.bytes_read == 60867
	assert save_error(path, f.manifest) != 'unexpected success'
	for source in ['/dev/null', f.work] {
		assert load_error(source) == 'manifest must be a regular file'
	}
	for text in ['{', '[] trailing', '\xff', '{"schema":NaN}'] {
		os.write_file(path, text)!
		assert load_error(path) != 'unexpected success'
	}
	for size in [max_range, max_range + 1] {
		text := f.manifest.json_text()
		os.write_file(path, text + ' '.repeat(size - text.len))!
		if size > max_range {
			assert load_error(path) == 'manifest is too large'
		} else {
			assert validate_manifest(load_manifest(path)!)! == f.manifest.ranges
		}
	}
}

fn encoded(text string, width int, little bool, bom bool) []u8 {
	mut result := []u8{}
	if bom {
		if width == 2 {
			result << if little { [u8(0xff), 0xfe] } else { [u8(0xfe), 0xff] }
		} else {
			result << if little { [u8(0xff), 0xfe, 0, 0] } else { [u8(0), 0, 0xfe, 0xff] }
		}
	}
	for ch in text.runes() {
		units := if width == 2 && ch > 0xffff {
			[u32(0xd800 + (ch - 0x10000) / 1024), u32(0xdc00 + (ch - 0x10000) % 1024)]
		} else {
			[u32(ch)]
		}
		for unit in units {
			for index in 0 .. width {
				shift := if little { index * 8 } else { (width - 1 - index) * 8 }
				result << u8(unit >> shift)
			}
		}
	}
	return result
}

fn test_manifest_unicode_encodings_boms_and_bad_code_units() {
	text := one_range('0', '1', '0'.repeat(64)).trim_right('}') + ',"label":"界😀"}'
	assert manifest_text([u8(0xef), 0xbb, 0xbf, ...text.bytes()])! == text
	for width in [2, 4] {
		for little in [false, true] {
			for bom in [false, true] {
				data := encoded(text, width, little, bom)
				assert manifest_text(data)! == text
				assert validate_manifest(parse_manifest(manifest_text(data)!)!)!.len == 1
			}
		}
	}
	for bad in [[u8(0xff), 0xfe, 0], [u8(0xfe), 0xff, 0xd8, 0], [u8(0xfe), 0xff, 0xdc, 0],
		[u8(0), 0, 0xfe, 0xff, 0, 0x11, 0, 0]] {
		manifest_text(bad) or { continue }
		assert false
	}
}

fn test_base_zero_integer_cli_grammar_unicode_bounds_and_repeated_ranges() {
	for text in ['0:1', '+0:+1', '0x0:0x_10', '0b00:0b1_0', '0o0:0o10', '00_0:1', '\u00a0٠:١\u3000',
		'０:１０', ' -0 : 1 '] {
		assert parse_range(text)!.offset == 0
	}
	for text in ['01:1', '0_1:1', '1:0', '-1:1', '0:-1', '0:1:2', '0:', '0x:1', '0:1__0', '0:_1',
		'0:1_', '0:0b2', '0:1.0', '0:²', '9223372036854775807:1', '9223372036854775808:1', '0:1048577',
		'0:0x__1', '0:\x1c1'] {
		parse_range(text) or { continue }
		assert false, text
	}
	assert parse_range('0x20000000000001:1')!.offset == i64(9007199254740993)
	parsed := arguments(['record', 'image', '--range=0:1', 'manifest', '--ra', '2:1', '--label',
		'first', '--la=last'])!
	assert parsed.label == 'last' && parsed.ranges.map(it.offset) == [i64(0), 2]
	assert arguments(['check', '--passes', '1_0', 'image', 'manifest'])!.passes == 10
	assert arguments(['check', 'image', 'manifest', '--pa=9'.replace('9', '9'.repeat(200))])!.passes == 11
	assert arguments(['check', '--', '-source', '-manifest'])!.source == '-source'
	assert arguments(['record', '--help'])!.help
	for args in [[]string{}, ['bad'], ['record', 'a', 'b'], ['check', 'a'],
		['check', 'a', 'b', '--range', '0:1'], ['record', 'a', 'b', '--range', '--label'],
		['check', 'a', 'b', '--passes', 'x'], ['record', '--', '--help']] {
		arguments(args) or { continue }
		assert false, args.str()
	}
}

fn descriptors() []int {
	mut result := []int{}
	for fd in 0 .. 512 { if C.fcntl(fd, C.F_GETFD) >= 0 { result << fd } }
	return result
}

fn test_descriptor_retirement_on_repeated_success_and_every_opened_error_path() {
	f := fixture()!
	defer { hosttest.remove_work_dir(f.work) or { panic(err) } }
	before := descriptors()
	tiny := record(f.source, [Range{ offset: 0, length: 1 }], 'tiny')!
	value := tiny.value()!
	bad := Manifest{ ranges: [Range{0, 1, '0'.repeat(64)}] }.value()!
	for iteration in 0 .. 100 {
		assert check(f.source, value, 1)!.bytes_read == 3
		assert check_error(f.source, bad, 1).starts_with('MISMATCH')
		assert check_error('/dev/null', value, 1).contains('source must be')
		assert load_error('/dev/null') == 'manifest must be a regular file'
		path := os.join_path(f.work, 'manifest-${iteration}')
		save_new_manifest(path, tiny)!
		assert validate_manifest(load_manifest(path)!)!.len == 1
		os.write_file(path, '{')!
		assert load_error(path) != 'unexpected success'
		assert save_error(path, tiny) != 'unexpected success'
		record(f.source, [Range{ offset: 65536, length: 1 }], 'eof') or {
			assert err.msg() == 'short read at byte 65536'
			assert descriptors() == before
			continue
		}
		assert false
	}
	assert descriptors() == before
	assert os.read_bytes(f.source)! == f.data
}

fn test_real_cli_readonly_manifest_reports_failure_status_and_foreign_cwd() {
	tool := os.getenv('VINIX_ANS_READS_TOOL')
	if tool == '' { return }
	f := fixture()!
	defer { hosttest.remove_work_dir(f.work) or { panic(err) } }
	path := os.join_path(f.work, 'cli.json')
	mut env := os.environ()
	result := hosttest.capture_in([tool, 'record', f.source, path, '--range', '0:8192',
		'--range=12345:8001', '--range', '61440:4096', '--label', 'CLI 界😀'], '', 30, env, f.work)!
	assert result.code == 0 && result.stderr == '', result.stderr
	assert result.stdout == 'Reference saved; no writes were made to the source.\n'
	assert validate_manifest(load_manifest(path)!)! == f.manifest.ranges
	checked := hosttest.capture_in([tool, 'check', f.source, path], '', 30, env, f.work)!
	assert checked.code == 0 && checked.stderr == '', checked.stderr
	report := json2.decode[Report](checked.stdout, strict: true)!
	assert report.passes == 2 && report.bytes_read == 121734
	assert report.read_only && !report.physical_hardware_independently_verified
	for args in [['record', f.source, f.source, '--range=0:1', '--label=x'],
		['check', f.source, path, '--passes=0'],
		['check', f.source, path, '--passes=' + '9'.repeat(200)], ['check', '/dev/null', path]] {
		failed := hosttest.capture([tool, ...args], '', 30, env)!
		assert failed.code == 1 && failed.stderr.starts_with('FAIL: ') && failed.stdout == '', failed.stderr
	}
	for args in [[]string{}, ['unknown'], ['record', 'a', 'b'], ['check', 'a', 'b', '--passes=x']] {
		failed := hosttest.capture([tool, ...args], '', 30, env)!
		assert failed.code == 2 && failed.stdout == '' && failed.stderr.starts_with('Usage:')
	}
	for args in [['--help'], ['record', '--help'], ['check', '-h']] {
		help := hosttest.capture([tool, ...args], '', 30, env)!
		assert help.code == 0 && help.stderr == '' && help.stdout.contains('power-loss persistence')
	}
	assert os.read_bytes(f.source)! == f.data
}
