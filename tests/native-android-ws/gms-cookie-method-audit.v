// SPDX-License-Identifier: GPL-2.0-or-later
// Audit every root/nested-archive DEX table, disassembling candidate callers only.
module main

import compress.szip
import crypto.sha256
import json2
import os

const apk_pin = 'a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707'
const wanted = ['Landroid/webkit/CookieManager;->flush()V',
	'Landroid/webkit/CookieSyncManager;->sync()V']

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn save[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn u16_at(data []u8, at int) u16 {
	assert at >= 0 && at <= data.len - 2
	return u16(data[at]) | u16(data[at + 1]) << 8
}

fn u32_at(data []u8, at int) int {
	assert at >= 0 && at <= data.len - 4
	value := u32(u16_at(data, at)) | u32(u16_at(data, at + 2)) << 16
	assert value <= 0x7fffffff
	return int(value)
}

fn uleb(data []u8, mut at &int) int {
	mut value := u32(0)
	for shift in [0, 7, 14, 21, 28] {
		assert *at >= 0 && *at < data.len
		byte := data[*at]
		(*at)++
		assert shift < 28 || byte < 8
		value |= u32(byte & 127) << shift
		if byte & 128 == 0 { return int(value) }
	}
	panic('invalid DEX ULEB')
}

fn dex_string(data []u8, index int) string {
	assert index >= 0 && index < u32_at(data, 56)
	mut at := u32_at(data, u32_at(data, 60) + index * 4)
	uleb(data, mut &at)
	start := at
	for at < data.len && data[at] != 0 { at++ }
	assert at < data.len
	return data[start..at].bytestr()
}

fn dex_type(data []u8, index int) string {
	assert index >= 0 && index < u32_at(data, 64)
	return dex_string(data, u32_at(data, u32_at(data, 68) + index * 4))
}

fn target_ids(data []u8) map[int]string {
	assert data.len >= 112 && data[..4] == 'dex\n'.bytes()
	assert u32_at(data, 32) == data.len && u32_at(data, 36) == 112
	assert u32_at(data, 40) == 0x12345678
	mut found := map[int]string{}
	for i in 0 .. u32_at(data, 88) {
		at := u32_at(data, 92) + i * 8
		owner := dex_type(data, int(u16_at(data, at)))
		if owner !in ['Landroid/webkit/CookieManager;', 'Landroid/webkit/CookieSyncManager;'] { continue }
		name := dex_string(data, u32_at(data, at + 4))
		if name !in ['flush', 'sync'] { continue }
		proto := int(u16_at(data, at + 2))
		assert proto < u32_at(data, 72)
		proto_at := u32_at(data, 76) + proto * 12
		if dex_type(data, u32_at(data, proto_at + 4)) != 'V'
			|| u32_at(data, proto_at + 8) != 0 { continue }
		descriptor := owner + '->' + name + '()V'
		if descriptor in wanted { found[i] = descriptor }
	}
	return found
}

// Scan every code unit as a conservative candidate selector, not an instruction
// decoder. Any real invoke necessarily matches; operand false positives only
// select extra classes. Canonical baksmali invoke lines prove actual callers.
fn candidate_classes(data []u8, ids map[int]string) []string {
	mut found := []string{}
	for index in 0 .. u32_at(data, 96) {
		class_at := u32_at(data, 100) + index * 32
		mut at := u32_at(data, class_at + 24)
		if at == 0 { continue }
		static_fields := uleb(data, mut &at)
		instance_fields := uleb(data, mut &at)
		direct_methods := uleb(data, mut &at)
		virtual_methods := uleb(data, mut &at)
		for _ in 0 .. static_fields + instance_fields {
			uleb(data, mut &at)
			uleb(data, mut &at)
		}
		mut matches := false
		for _ in 0 .. direct_methods + virtual_methods {
			uleb(data, mut &at)
			uleb(data, mut &at)
			code := uleb(data, mut &at)
			if code == 0 { continue }
			units := u32_at(data, code + 12)
			start := code + 16
			assert units <= (data.len - start) / 2
			for i in 0 .. units - 1 {
				op := data[start + i * 2]
				if (op >= 0x6e && op <= 0x72) || (op >= 0x74 && op <= 0x78)
					|| op in [u8(0xfa), u8(0xfb)] {
					if int(u16_at(data, start + (i + 1) * 2)) in ids { matches = true }
				}
			}
		}
		if matches { found << dex_type(data, u32_at(data, class_at)) }
	}
	assert found.len <= 128, 'bounded selected-class disassembly'
	return found
}

fn command(out string, name string, argv []string) !string {
	result := os.exec(argv)
	save(out + '/' + name + '.json', {
		'argv': json2.Any(argv)
		'exit_code': json2.Any(result.exit_code)
		'output': json2.Any(result.output)
	})!
	assert result.exit_code == 0, result.output
	return result.output
}

fn full_method_refs(out string, name string, argv []string) ![]string {
	result := os.exec(argv)
	mut refs := result.output.split_into_lines().filter(it in wanted)
	refs.sort()
	save(out + '/' + name + '.json', {
		'argv': json2.Any(argv)
		'exit_code': json2.Any(result.exit_code)
		'output_sha256': json2.Any(sha256.sum(result.output.bytes()).hex())
		'output_bytes': json2.Any(result.output.len)
		'output_lines': json2.Any(result.output.split_into_lines().len)
		'relevant_descriptors': json2.Any(refs)
	})!
	assert result.exit_code == 0
	return refs
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(path)! }
			else { return error('nonregular audit evidence: ' + path) }
		}
	}
}

struct Extracted {
mut:
	dex []string
	archives []string
	bytes u64
	root_dex int
	keys map[string]bool
}

fn extract_archive(path string, out string, prefix string, depth int, mut extracted Extracted) ! {
	assert depth <= 4
	mut archive := szip.open(path, .no_compression, .read_only)!
	defer { archive.close() }
	assert archive.total()! <= 65536
	mut seen := map[string]bool{}
	for i in 0 .. archive.total()! {
		archive.open_entry_by_index(i)!
		name := archive.name()
		nested := name.ends_with('.apk') || name.ends_with('.jar') || name.ends_with('.zip')
		if !name.ends_with('.dex') && !nested {
			archive.close_entry()
			continue
		}
		assert !name.starts_with('/') && !name.contains('\\') && !name.contains('!')
		assert !name.split('/').any(it == '' || it == '.' || it == '..')
		assert name !in seen
		seen[name] = true
		key := prefix + name
		assert key !in extracted.keys
		extracted.keys[key] = true
		assert archive.size() >= 8 && archive.size() <= 256 * 1024 * 1024
		extracted.bytes += archive.size()
		assert extracted.bytes <= u64(1024 * 1024 * 1024)
		mut data := []u8{len: int(archive.size())}
		assert archive.read_entry_buf(data.data, data.len)! == data.len
		archive.close_entry()
		target := out + (if nested { '/archives/' } else { '/dex/' }) + key
		os.mkdir_all(os.dir(target))!
		os.write_file_array(target, data)!
		if nested {
			extracted.archives << key
			assert extracted.archives.len <= 64
			extract_archive(target, out, key + '!/', depth + 1, mut extracted)!
		} else {
			extracted.dex << key
			assert extracted.dex.len <= 256
			if depth == 0 { extracted.root_dex++ }
		}
	}
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 3, 'FRESH_OUTPUT APK'
	out := os.abs_path(os.args[1])
	apk := os.abs_path(os.args[2])
	assert !os.exists(out) && !os.is_link(out)
	assert hash(apk)! == apk_pin
	os.mkdir_all(out + '/dex')!
	os.mkdir_all(out + '/tools')!
	os.cp('tests/native-android-ws/gms-cookie-method-audit.v', out + '/author.v')!
	os.cp(os.executable(), out + '/author')!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	mut inputs := {apk: apk_pin, java: hash(java)!}
	for name in ['baksmali-2.5.2.jar', 'dexlib2-2.5.2.jar', 'util-2.5.2.jar',
		'guava-27.1-android.jar', 'failureaccess-1.0.1.jar', 'jcommander-1.64.jar'] {
		path := os.abs_path('build/android-framework/tools/' + name)
		inputs[path] = hash(path)!
		os.cp(path, out + '/tools/' + name)!
	}
	save(out + '/inputs-before.json', inputs)!
	mut extracted := Extracted{}
	extract_archive(apk, out, '', 0, mut extracted)!
	assert extracted.root_dex == 15
	mut dex_names := extracted.dex.clone()
	dex_names.sort()
	save(out + '/nested-archive-members.json', extracted.archives)!
	save(out + '/dex-members.json', dex_names)!
	mut all_refs := []string{}
	mut callers := []string{}
	for name in dex_names {
		path := out + '/dex/' + name
		data := os.read_bytes(path)!
		ids := target_ids(data)
		mut refs := ids.values()
		refs.sort()
		assert full_method_refs(out, name + '-method-table', [java, '-cp', out + '/tools/*',
			'org.jf.baksmali.Main', 'list', 'methods', path])! == refs
		for ref in refs { all_refs << name + ':' + ref }
		save(out + '/' + name + '-refs.json', refs)!
		if ids.len == 0 { continue }
		classes := candidate_classes(data, ids)
		save(out + '/' + name + '-candidates.json', classes)!
		if classes.len == 0 { continue }
		selected := out + '/smali/' + name
		command(out, name + '-disassemble', [java, '-cp', out + '/tools/*',
			'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', '--classes', classes.join(','),
			'-o', selected, path])!
		for class in classes {
			relative := class[1..class.len - 1] + '.smali'
			mut method := ''
			for line_index, line in os.read_lines(selected + '/' + relative)! {
				if line.starts_with('.method ') { method = line }
				if line.trim_space().starts_with('invoke-') {
					for ref in wanted {
						if line.ends_with(', ' + ref) {
							callers << name + ':' + relative + ':' + (line_index + 1).str()
								+ ':' + method + ':' + line.trim_space()
						}
					}
				}
			}
		}
	}
	save(out + '/references.json', all_refs)!
	save(out + '/callers.json', callers)!
	for path, pin in inputs { assert hash(path)! == pin, path }
	save(out + '/inputs-after.json', inputs)!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	save(out + '/sha256.json', pins)!
	println('GMS-COOKIE-AUDIT-PASS dex=' + dex_names.len.str() + ' refs=' + all_refs.len.str()
		+ ' calls=' + callers.len.str() + ' nested_archives=' + extracted.archives.len.str()
		+ ' seal=' + hash(out + '/sha256.json')!)
	for caller in callers { println(caller) }
}
