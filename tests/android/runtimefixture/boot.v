module runtimefixture

import crypto.sha256
import json2
import os

const boot_original_source = '414a3f237e77ecde182445ef6645f5636773e30b309c06ea4cc179cf5c98c4a7'

struct BootContext {
	root      string
	constants map[string]json2.Any
}

fn boot_context() !BootContext {
	row := call({
		'module':     json2.Any('boot')
		'attributes': json2.Any(['INPUTS', 'BOOT_DIRECTORY', 'BOOT_ORIGINAL', 'COMPILER_ARGUMENTS'].map(json2.Any(it)))
	})!
	assert 'result' in row, json2.encode(row)
	return BootContext{temporary()!, map_field(row, 'result').as_map()}
}

fn boot_arg(kind string, value json2.Any) json2.Any {
	return json2.Any([json2.Any(kind), value])
}

fn boot_path(path string) json2.Any { return boot_arg('path', json2.Any(path)) }

fn boot_bytes(bytes []u8) json2.Any { return boot_arg('bytes', json2.Any(bytes.hex())) }

fn boot_response(operation string, arguments []json2.Any, record_run bool) !map[string]json2.Any {
	return call({
		'module':     json2.Any('boot')
		'operation':  json2.Any(operation)
		'arguments':  json2.Any(arguments)
		'record_run': json2.Any(record_run)
	})!
}

fn boot_call(operation string, arguments []json2.Any) !json2.Any {
	row := boot_response(operation, arguments, false)!
	assert 'result' in row, json2.encode(row)
	return map_field(row, 'result')
}

fn boot_reject(operation string, arguments []json2.Any) ! {
	row := boot_response(operation, arguments, false)!
	assert text(row, 'kind') == 'RuntimeError', json2.encode(row)
}

fn boot_zip_write(path string, entries [][]string) ! {
	row := call({
		'module':    json2.Any('zip')
		'operation': json2.Any('write')
		'path':      json2.Any(path)
		'entries':   json2.Any(entries.map(json2.Any(it.map(json2.Any(it)))))
	})!
	assert 'result' in row, json2.encode(row)
}

fn boot_zip_read(path string, names []string) !map[string]json2.Any {
	row := call({
		'module':    json2.Any('zip')
		'operation': json2.Any('read')
		'path':      json2.Any(path)
		'names':     json2.Any(names.map(json2.Any(it)))
	})!
	assert 'result' in row, json2.encode(row)
	return map_field(row, 'result').as_map()
}

fn boot_dex(descriptor string, callsites u32) []u8 {
	mut name := [u8(descriptor.len)]
	name << descriptor.bytes()
	name << u8(0)
	map_offset := 152 + name.len
	mut data := []u8{len: map_offset + 16}
	for i, byte in 'dex\n038\x00'.bytes() { data[i] = byte }
	put32(mut data, 32, u32(data.len))
	put32(mut data, 36, 112)
	put32(mut data, 40, 0x12345678)
	put32(mut data, 52, u32(map_offset))
	for offset, table in {
		56: u32(112)
		64: u32(116)
		96: u32(120)
	} {
		put32(mut data, offset, 1)
		put32(mut data, offset + 4, table)
	}
	put32(mut data, 112, 152)
	for i, byte in name { data[152 + i] = byte }
	put32(mut data, map_offset, 1)
	put16(mut data, map_offset + 4, 7)
	put32(mut data, map_offset + 8, callsites)
	return data
}

fn boot_many_classes(count int, callsites u32) []u8 {
	string_offset := 112
	type_offset := 112 + count * 4
	class_offset := type_offset + count * 4
	mut data := []u8{len: class_offset + count * 32}
	for index in 0 .. count {
		descriptor := 'Ljava/time/Test${index};'
		put32(mut data, string_offset + index * 4, u32(data.len))
		put32(mut data, type_offset + index * 4, u32(index))
		put32(mut data, class_offset + index * 32, u32(index))
		data << u8(descriptor.len)
		data << descriptor.bytes()
		data << u8(0)
	}
	for data.len % 4 != 0 { data << u8(0) }
	map_offset := data.len
	data << []u8{len: 16}
	for i, byte in 'dex\n038\x00'.bytes() { data[i] = byte }
	put32(mut data, 32, u32(data.len))
	put32(mut data, 36, 112)
	put32(mut data, 40, 0x12345678)
	put32(mut data, 52, u32(map_offset))
	for offset, table in {
		56: string_offset
		64: type_offset
		96: class_offset
	} {
		put32(mut data, offset, u32(count))
		put32(mut data, offset + 4, u32(table))
	}
	put32(mut data, map_offset, 1)
	put16(mut data, map_offset + 4, 7)
	put32(mut data, map_offset + 8, callsites)
	return data
}

fn boot_reads_real_dex_class_descriptor_and_bootstrap_count(mut c BootContext) ! {
	for callsites in [u32(3), 0] {
		result := boot_call('dex_info', [boot_bytes(boot_dex('Ljava/time/Example;', callsites))])!.as_array()
		assert result[0].as_array().map(it.str()) == ['java/time/Example.class']
		assert result[1].int() == int(callsites)
	}
}

fn boot_rejects_invalid_or_escaping_dex_data(mut c BootContext) ! {
	data := boot_dex('Ljava/time/Example;', 0)
	for bytes in [data[..100], data[..data.len - 1], boot_dex('L../Escape;', 0),
		boot_dex('L/Absolute;', 0)] {
		boot_reject('dex_info', [boot_bytes(bytes)])!
	}
	mut invalid := data.clone()
	put32(mut invalid, 120, 8)
	boot_reject('dex_info', [boot_bytes(invalid)])!
}

fn boot_reconstructs_only_required_classfiles_and_rejects_missing_input(mut c BootContext) ! {
	source := c.root + '/all.jar'
	boot_zip_write(source, [
		['java/time/Example.class', 'class-bytecode'.bytes().hex()],
		['java/time/Other.class', 'other-bytecode'.bytes().hex()],
	])!
	result := c.root + '/subset.jar'
	boot_call('class_subset', [boot_path(source),
		boot_arg('set', json2.Any([json2.Any('java/time/Example.class')])), boot_path(result)])!
	archive := boot_zip_read(result, ['java/time/Example.class'])!
	assert strings(archive, 'names') == ['java/time/Example.class']
	assert text(map_field(archive, 'files').as_map(), 'java/time/Example.class') == 'class-bytecode'.bytes().hex()
	boot_reject('class_subset', [boot_path(source),
		boot_arg('set', json2.Any([json2.Any('java/time/Missing.class')])), boot_path(result)])!
}

fn boot_jar_replacement_preserves_resources_and_is_deterministic(mut c BootContext) ! {
	original := c.root + '/original.jar'
	boot_zip_write(original, [
		['classes.dex', boot_dex('Ljava/time/Example;', 3).hex()],
		['classes2.dex', boot_dex('Ljava/time/Old;', 0).hex()],
		['android/icu/icu-data.dat', 'unchanged ICU binary data'.bytes().hex()],
		['META-INF/LICENSE', 'license'.bytes().hex()],
	])!
	original_bytes := os.read_bytes(original)!
	output := c.root + '/dex'
	os.mkdir(output)!
	os.write_file_array(output + '/classes.dex', boot_dex('Ljava/time/Example;', 0))!
	os.write_file_array(output + '/classes2.dex', boot_dex('Ljava/time/GeneratedLambda;', 0))!
	first := c.root + '/one.jar'
	second := c.root + '/two.jar'
	for path in [first, second] {
		boot_call('package_jar', [boot_path(original), boot_path(output), boot_path(path)])!
	}
	assert os.read_bytes(first)! == os.read_bytes(second)!
	assert os.read_bytes(original)! == original_bytes
	archive := map_field(boot_zip_read(first, ['android/icu/icu-data.dat', 'META-INF/LICENSE'])!, 'files').as_map()
	assert text(archive, 'android/icu/icu-data.dat') == 'unchanged ICU binary data'.bytes().hex()
	assert text(archive, 'META-INF/LICENSE') == 'license'.bytes().hex()
	info := boot_call('jar_info', [boot_path(first)])!.as_array()
	mut classes := info[0].as_array().map(it.str())
	classes.sort()
	assert classes == ['java/time/Example.class', 'java/time/GeneratedLambda.class']
	assert info[1].int() == 0
}

fn boot_rejects_duplicate_classes_across_multidex(mut c BootContext) ! {
	path := c.root + '/bad.jar'
	boot_zip_write(path, [['classes.dex', boot_dex('Ljava/time/Example;', 0).hex()],
		['classes2.dex', boot_dex('Ljava/time/Example;', 0).hex()]])!
	boot_reject('jar_info', [boot_path(path)])!
}

fn boot_rejects_corrupted_pinned_download_without_network(mut c BootContext) ! {
	path := c.root + '/cached.jar'
	os.write_file(path, 'verified tool')!
	record := {
		'filename': json2.Any('cached.jar')
		'url':      json2.Any('https://example.invalid/tool.jar')
		'sha256':   json2.Any(sha256.sum(os.read_bytes(path)!).hex())
	}
	download_arguments := [boot_arg('value', json2.Any(record)), boot_path(c.root)]
	accepted := boot_response('download', download_arguments, true)!
	assert text(accepted, 'result') == path, json2.encode(accepted)
	assert map_field(accepted, 'run_calls').int() == 0
	os.write_file(path, 'corrupted tool')!
	rejected := boot_response('download', download_arguments, true)!
	assert text(rejected, 'kind') == 'RuntimeError', json2.encode(rejected)
	assert map_field(rejected, 'run_calls').int() == 0
}

fn (c BootContext) provenance() !map[string]json2.Any {
	mut records := []json2.Any{}
	for name, value in map_field(c.constants, 'BOOT_ORIGINAL').as_map() {
		original := value.as_map()
		relative := text(c.constants, 'BOOT_DIRECTORY') + '/' + name
		path := c.root + '/' + relative
		os.mkdir_all(os.dir(path))!
		count := map_field(original, 'classes_before').int() + 1
		boot_zip_write(path, [['classes.dex', boot_many_classes(count, 0).hex()]])!
		mut record := record_copy(original)
		record['path'] = json2.Any(relative)
		record['sha256'] = json2.Any(sha256.sum(os.read_bytes(path)!).hex())
		record['size'] = json2.Any(os.stat(path)!.size)
		record['classes_after'] = json2.Any(count)
		record['bootstrap_callsites_after'] = json2.Any(0)
		records << json2.Any(record)
	}
	return {
		'format':             json2.Any(1)
		'inputs':             map_field(c.constants, 'INPUTS')
		'compiler_arguments': map_field(c.constants, 'COMPILER_ARGUMENTS')
		'compiler':           json2.Any('D8 8.3.37 (build official)')
		'input_key':          json2.Any('a'.repeat(64))
		'files':              json2.Any(records)
	}
}

fn boot_validates_real_dex_counts_and_pinned_compiler_receipt(mut c BootContext) ! {
	manifest := c.provenance()!
	mut payloads := []json2.Any{}
	for item in map_field(manifest, 'files').as_array() {
		record := item.as_map()
		payloads << json2.Any({
			'path':   map_field(record, 'path')
			'size':   map_field(record, 'size')
			'sha256': map_field(record, 'sha256')
		})
	}
	boot_call('validate_provenance', [boot_path(c.root), boot_arg('value', json2.Any(manifest)),
		boot_arg('value', json2.Any(payloads))])!
	changes := {
		'inputs':             json2.Any([]json2.Any{})
		'compiler_arguments': json2.Any([json2.Any('--min-api'), json2.Any('35')])
		'compiler':           json2.Any('D8 8.0.0 (build other)')
		'input_key':          json2.Any('bad')
		'files':              json2.Any([]json2.Any{})
	}
	for key, value in changes {
		mut bad := record_copy(manifest)
		bad[key] = value
		boot_reject('validate_provenance', [boot_path(c.root), boot_arg('value', json2.Any(bad)),
			boot_arg('value', json2.Any(payloads))])!
	}
	mut changed := record_copy(payloads[0].as_map())
	changed['sha256'] = json2.Any('b'.repeat(64))
	payloads[0] = json2.Any(changed)
	boot_reject('validate_provenance', [boot_path(c.root), boot_arg('value', json2.Any(manifest)),
		boot_arg('value', json2.Any(payloads))])!
}

fn boot_copy_manifest(manifest map[string]json2.Any) map[string]json2.Any {
	mut copied := record_copy(manifest)
	copied['files'] = json2.Any(map_field(manifest, 'files').as_array().map(json2.Any(record_copy(it.as_map()))))
	return copied
}

struct BootMutation {
	name  string
	value json2.Any
}

fn boot_rejects_library_receipt_that_lies_about_original_or_output_dex(mut c BootContext) ! {
	manifest := c.provenance()!
	changes := [BootMutation{'original_sha256', json2.Any('b'.repeat(64))},
		BootMutation{'classes_before', json2.Any(1)}, BootMutation{'classes_after', json2.Any(99999)},
		BootMutation{'bootstrap_callsites_after', json2.Any('__fixture_float_zero__')},
		BootMutation{'bootstrap_callsites_before', json2.Any(0)},
		BootMutation{'sha256', json2.Any('b'.repeat(64))},
		BootMutation{'path', json2.Any('usr/lib/java/dex/art/../escape.jar')},
		BootMutation{'path', json2.Any([]json2.Any{})}]
	for change in changes {
		mut bad := boot_copy_manifest(manifest)
		mut files := map_field(bad, 'files').as_array().clone()
		mut record := record_copy(files[0].as_map())
		record[change.name] = change.value
		files[0] = json2.Any(record)
		bad['files'] = json2.Any(files)
		if change.name == 'bootstrap_callsites_after' {
			// json2.Any renders 0.0 as 0. Preserve this original strict-type
			// mutation through the standard JSON-number transport.
			encoded := json2.encode(bad).replace('"__fixture_float_zero__"', '0.0')
			boot_reject('validate_provenance', [boot_path(c.root),
				boot_arg('json', json2.Any(encoded))])!
		} else {
			boot_reject('validate_provenance', [boot_path(c.root), boot_arg('value', json2.Any(bad))])!
		}
	}
	mut bad := boot_copy_manifest(manifest)
	mut files := map_field(bad, 'files').as_array().clone()
	files[1] = json2.Any(record_copy(files[0].as_map()))
	bad['files'] = json2.Any(files)
	boot_reject('validate_provenance', [boot_path(c.root), boot_arg('value', json2.Any(bad))])!
}

fn boot_rejects_checksum_consistent_dex_with_bootstrap_calls(mut c BootContext) ! {
	mut manifest := c.provenance()!
	mut files := map_field(manifest, 'files').as_array().clone()
	mut record := record_copy(files[0].as_map())
	path := c.root + '/' + text(record, 'path')
	boot_zip_write(path, [['classes.dex',
		boot_many_classes(map_field(record, 'classes_after').int(), 1).hex()]])!
	record['sha256'] = json2.Any(sha256.sum(os.read_bytes(path)!).hex())
	record['size'] = json2.Any(os.stat(path)!.size)
	files[0] = json2.Any(record)
	manifest['files'] = json2.Any(files)
	boot_reject('validate_provenance', [boot_path(c.root), boot_arg('value', json2.Any(manifest))])!
}

pub fn boot_source_identity() string { return boot_original_source }

pub fn run_boot_guarded(selection string) ! { guarded(selection, '--child-boot')! }

pub fn run_boot(selection string) ! {
	gold := json2.decode[map[string]json2.Any](os.read_file(os.dir(@FILE) + '/boot-builders.json')!)!
	assert text(gold, 'original_source_sha256') == boot_original_source
	for item in map_field(gold, 'dex').as_array() {
		row := item.as_map()
		assert boot_dex(text(row, 'descriptor'), u32(map_field(row, 'callsites').int())).hex() == text(row, 'hex')
	}
	for item in map_field(gold, 'many_classes').as_array() {
		row := item.as_map()
		data := boot_many_classes(map_field(row, 'count').int(), u32(map_field(row, 'callsites').int()))
		assert data.len == map_field(row, 'size').int()
		assert sha256.sum(data).hex() == text(row, 'sha256')
	}
	cases := map[string]fn (mut BootContext) !{
		'BootclasspathTests.test_reads_real_dex_class_descriptor_and_bootstrap_count':             boot_reads_real_dex_class_descriptor_and_bootstrap_count
		'BootclasspathTests.test_rejects_invalid_or_escaping_dex_data':                            boot_rejects_invalid_or_escaping_dex_data
		'BootclasspathTests.test_reconstructs_only_required_classfiles_and_rejects_missing_input': boot_reconstructs_only_required_classfiles_and_rejects_missing_input
		'BootclasspathTests.test_jar_replacement_preserves_resources_and_is_deterministic':        boot_jar_replacement_preserves_resources_and_is_deterministic
		'BootclasspathTests.test_rejects_duplicate_classes_across_multidex':                       boot_rejects_duplicate_classes_across_multidex
		'BootclasspathTests.test_rejects_corrupted_pinned_download_without_network':               boot_rejects_corrupted_pinned_download_without_network
		'BootclasspathTests.test_validates_real_dex_counts_and_pinned_compiler_receipt':           boot_validates_real_dex_counts_and_pinned_compiler_receipt
		'BootclasspathTests.test_rejects_library_receipt_that_lies_about_original_or_output_dex':  boot_rejects_library_receipt_that_lies_about_original_or_output_dex
		'BootclasspathTests.test_rejects_checksum_consistent_dex_with_bootstrap_calls':            boot_rejects_checksum_consistent_dex_with_bootstrap_calls
	}
	assert selection == '' || selection in cases, 'Unknown native fixture ' + selection
	for name, test in cases {
		if selection != '' && selection != name { continue }
		boot_run_case(test)!
		println('PASS ' + name)
	}
}

fn boot_run_case(test fn (mut BootContext) !) ! {
	mut c := boot_context()!
	defer { os.rmdir_all(c.root) or { panic(err) } }
	test(mut c)!
}
