module runtimefixture

import crypto.sha256
import fixturehost
import json2
import os

#include <stdlib.h>
#include <unistd.h>

fn C.mkdtemp(&char) &char
fn C.link(&char, &char) i32
fn C.symlink(&char, &char) i32

const original_source_sha256 = 'b19cfd6223d7cf5d5ef7a888473cb1564d892821ccd4e6c81c49ef2c43dd58de'

fn repository() string {
	return os.real_path(os.join_path(os.dir(@FILE), '../../..'))
}

fn call(row map[string]json2.Any) !map[string]json2.Any {
	python := if os.getenv('VINIX_RUNTIME_FIXTURE_PYTHON') != '' {
		os.getenv('VINIX_RUNTIME_FIXTURE_PYTHON')
	} else {
		'python3'
	}
	output := fixturehost.capture_preferred([python,
		repository() + '/tests/android/runtime-binding.py', json2.encode(row)], '', os.environ(), false, os.uname().machine)!
	return json2.decode[map[string]json2.Any](output)!
}

fn map_field(row map[string]json2.Any, name string) json2.Any {
	return row[name] or { json2.Any(json2.Null{}) }
}

fn text(row map[string]json2.Any, name string) string { return map_field(row, name).str() }

fn strings(row map[string]json2.Any, name string) []string {
	return map_field(row, name).as_array().map(it.str())
}

fn native_call(operation string, paths []string, values []json2.Any) !json2.Any {
	row := call({
		'operation': json2.Any(operation)
		'paths':     json2.Any(paths.map(json2.Any(it)))
		'values':    json2.Any(values)
	})!
	assert 'result' in row, json2.encode(row)
	return map_field(row, 'result')
}

fn failure(operation string, paths []string, values []json2.Any, kinds []string, contains string) ! {
	row := call({
		'operation': json2.Any(operation)
		'paths':     json2.Any(paths.map(json2.Any(it)))
		'values':    json2.Any(values)
	})!
	assert text(row, 'kind') in kinds, json2.encode(row)
	assert text(row, 'message').contains(contains), json2.encode(row)
}

fn temporary() !string {
	parent := if os.getenv('VINIX_RUNTIME_FIXTURE_WORK') != '' {
		os.getenv('VINIX_RUNTIME_FIXTURE_WORK')
	} else {
		os.temp_dir()
	}
	mut buffer := (parent + '/vinix-runtime-fixture-XXXXXX\x00').bytes()
	if isnil(C.mkdtemp(&char(buffer.data))) { return error('runtime fixture mkdtemp failed') }
	return buffer[..buffer.len - 1].bytestr()
}

struct Context {
	root      string
	overlay   string
	runtime   string
	constants map[string]json2.Any
	bionic    bool
mut:
	manifest map[string]json2.Any
}

fn context(bionic bool) !Context {
	attributes := ['MANIFEST', 'SOURCE_COMMIT', 'SOURCE_SHA256', 'SOURCE_SHA512', 'PATCH', 'LIBART',
		'ART_ELFS', 'ART_HEADERS', 'ANDROIDFW_HEADER', 'BIONIC_MANIFEST', 'BIONIC_SOURCE_COMMIT',
		'BIONIC_SOURCE_SHA256', 'BIONIC_SOURCE_SHA512', 'BIONIC_PATCH', 'BIONIC_LIBRARIES']
	constants := map_field(call({
		'attributes': json2.Any(attributes.map(json2.Any(it)))
	})!, 'result').as_map()
	root := temporary()!
	mut transferred := false
	defer { if !transferred { os.rmdir_all(root) or { panic(err) } } }
	overlay := root + '/overlay'
	os.mkdir(overlay)!
	prefix := if bionic { 'BIONIC_' } else { '' }
	manifest := map[string]json2.Any{
		'format':        json2.Any(1)
		'architecture':  json2.Any('aarch64')
		'page_size':     json2.Any(16384)
		'source_commit': map_field(constants, prefix + 'SOURCE_COMMIT')
		'source_sha512': map_field(constants, prefix + 'SOURCE_SHA512')
		'source_sha256': map_field(constants, prefix + 'SOURCE_SHA256')
		'patch_sha256':  json2.Any(sha256.sum(os.read_bytes(text(constants, prefix + 'PATCH'))!).hex())
		'build_flags':   json2.Any([json2.Any(if bionic {
			'-DBIONIC_PAGE_SIZE=16384'
		} else {
			'-DART_PAGE_SIZE=16384'
		})])
		'files':         json2.Any([]json2.Any{})
	}
	mut c := Context{root, overlay, root + '/runtime', constants, bionic, manifest}
	if bionic {
		for name in strings(constants, 'BIONIC_LIBRARIES') { c.payload(name, elf(183, 0), 0o755)! }
	} else {
		c.manifest['androidfw_configuration_api'] = json2.Any(1)
		libart := text(constants, 'LIBART')
		c.payload(libart, elf(183, 0), 0o755)!
		for name in strings(constants, 'ART_ELFS') {
			if name != libart { c.payload(name, elf(183, 0), 0o755)! }
		}
		c.payload(text(constants, 'ANDROIDFW_HEADER'), '/* pinned androidfw C API */\n'.bytes(), 0o644)!
	}
	transferred = true
	return c
}

fn (mut c Context) write_manifest() ! {
	name := text(c.constants, if c.bionic { 'BIONIC_MANIFEST' } else { 'MANIFEST' })
	os.write_file(c.overlay + '/' + name, json2.encode(c.manifest))!
}

fn (mut c Context) payload(name string, contents []u8, mode u32) !string {
	path := c.overlay + '/' + name
	os.mkdir_all(os.dir(path))!
	os.write_file_array(path, contents)!
	os.chmod(path, int(mode))!
	mut records := map_field(c.manifest, 'files').as_array().filter(text(it.as_map(), 'path') != name)
	records << json2.Any(map[string]json2.Any{
		'path':   json2.Any(name)
		'size':   json2.Any(contents.len)
		'sha256': json2.Any(sha256.sum(contents).hex())
	})
	c.manifest['files'] = json2.Any(records)
	c.write_manifest()!
	return path
}

fn (c Context) read() !json2.Any {
	return native_call(if c.bionic { 'read_bionic_manifest' } else { 'read_manifest' }, [c.overlay], []json2.Any{})!
}

fn (c Context) apply(manifest json2.Any) !json2.Any {
	return native_call(if c.bionic { 'apply_bionic' } else { 'apply' }, [c.overlay, c.runtime], [manifest])!
}

fn (mut c Context) reject() ! {
	c.write_manifest()!
	failure(if c.bionic { 'read_bionic_manifest' } else { 'read_manifest' }, [c.overlay], []json2.Any{}, if c.bionic {
		['RuntimeError']
	} else {
		['RuntimeError', 'FileNotFoundError']
	}, '')!
}

fn (c Context) reject_apply(manifest json2.Any, contains string) ! {
	failure(if c.bionic { 'apply_bionic' } else { 'apply' }, [c.overlay, c.runtime], [manifest], ['RuntimeError'], contains)!
}

fn put16(mut bytes []u8, at int, value u16) {
	for index in 0 .. 2 { bytes[at + index] = u8(value >> u32(8 * index)) }
}

fn put32(mut bytes []u8, at int, value u32) {
	for index in 0 .. 4 { bytes[at + index] = u8(value >> u32(8 * index)) }
}

fn put64(mut bytes []u8, at int, value u64) {
	for index in 0 .. 8 { bytes[at + index] = u8(value >> u32(8 * index)) }
}

fn elf(machine u16, offset int) []u8 {
	size := if offset + 128 > 256 { offset + 128 } else { 256 }
	mut data := []u8{len: size}
	for i, b in [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] { data[i] = b }
	put16(mut data, 16, 3)
	put16(mut data, 18, machine)
	put32(mut data, 20, 1)
	put64(mut data, 24, 0x400080)
	put64(mut data, 32, 64)
	put16(mut data, 52, 64)
	put16(mut data, 54, 56)
	put16(mut data, 56, 1)
	put32(mut data, 64, 1)
	put32(mut data, 68, 5)
	put64(mut data, 72, u64(offset))
	put64(mut data, 80, 0x400000)
	put64(mut data, 96, u64(size - offset))
	put64(mut data, 104, u64(size - offset))
	put64(mut data, 112, 16384)
	return data
}

fn link(source string, target string) ! {
	assert C.link(source.str, target.str) == 0
}

fn symlink(source string, target string) ! {
	assert C.symlink(source.str, target.str) == 0
}

fn record_copy(value map[string]json2.Any) map[string]json2.Any {
	mut result := map[string]json2.Any{}
	for key, item in value { result[key] = item }
	return result
}

pub fn source_identity() string { return original_source_sha256 }

// The child may terminate on an assertion. Its waiting parent owns every
// descendant scratch directory and retires them after status propagation.
fn guarded(selection string, child_mode string) ! {
	root := temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	mut environment := os.environ()
	environment['VINIX_RUNTIME_FIXTURE_WORK'] = root
	output := fixturehost.capture_preferred([os.executable(), child_mode, selection], '', environment, false, os.uname().machine)!
	print(output)
}

pub fn run_guarded(selection string) ! {
	guarded(selection, '--child-runtime')!
}

fn verify_original_builders() ! {
	gold := json2.decode[map[string]json2.Any](os.read_file(os.dir(@FILE) + '/elf.json')!)!
	assert text(gold, 'original_source_sha256') == original_source_sha256
	images := map_field(gold, 'elf').as_map()
	assert elf(183, 0).hex() == text(images, 'native')
	assert elf(62, 0).hex() == text(images, 'foreign')
	assert elf(183, 4096).hex() == text(images, 'incongruent')
	assert equivalent(json2.Any({
		'a': json2.Any(1)
		'b': json2.Any('text')
	}),
		json2.Any({
			'b': json2.Any('text')
			'a': json2.Any(1)
		}))
}

// The corpus compares JSON objects without depending on their key order.
fn equivalent(left json2.Any, right json2.Any) bool {
	if left is map[string]json2.Any {
		if right !is map[string]json2.Any { return false }
		if left.len != right.len { return false }
		for key, item in left {
			other := right[key] or { return false }
			if !equivalent(item, other) { return false }
		}
		return true
	}
	if left is []json2.Any {
		if right !is []json2.Any { return false }
		if left.len != right.len { return false }
		for index, item in left { if !equivalent(item, right[index]) { return false } }
		return true
	}
	return json2.encode(left) == json2.encode(right)
}

fn no_temporaries(path string) bool {
	for name in os.ls(path) or { return true } {
		if name.starts_with('.vinix-art-') { return false }
		child := path + '/' + name
		if os.is_dir(child) && !os.is_link(child) && !no_temporaries(child) { return false }
	}
	return true
}

fn stale_elf() []u8 {
	mut bytes := elf(183, 0)
	bytes << 'stale alias'.bytes()
	return bytes
}
