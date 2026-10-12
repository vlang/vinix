// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import crypto.sha256
import json2
import os
import strconv

// Keep each occurrence: ar p selects the first member with a repeated name.
pub fn archive_members(data []u8) !map[string][][]u8 {
	if data.len < 8 || data[..8].bytestr() != '!<arch>\n' { return error('invalid ar archive magic') }
	mut result := map[string][][]u8{}
	mut position := 8
	for position < data.len {
		if data.len - position < 60 { return error('truncated ar header') }
		header := data[position..position + 60]
		if header[58..60].bytestr() != '`\n' { return error('invalid ar header trailer') }
		name := header[..16].bytestr().trim_space().trim_right('/')
		length := strconv.parse_uint(header[48..58].bytestr().trim_space(), 10, 64)!
		if length > u64(data.len - position - 60) { return error('truncated ar member') }
		size := int(length)
		body := data[position + 60..position + 60 + size].clone()
		mut members := result[name] or { [][]u8{} }
		members << body
		result[name] = members
		position += 60 + size + (size & 1)
	}
	if position != data.len { return error('missing ar padding') }
	return result
}

pub fn assembly_function(assembly string, name string) !string {
	marker := '<' + name + '>:'
	start := assembly.index(marker) or { return error('assembly function missing: ' + name) }
	remaining := assembly[start..]
	end := remaining.index('\n\n') or { remaining.len }
	return remaining[..end]
}

fn relative_to_root(path string, root string) !string {
	if !path.starts_with(root.trim_right('/') + '/') { return error('evidence path is outside the repository: ' + path) }
	return path[root.trim_right('/').len + 1..]
}

fn word_character(c u8) bool { return c.is_alnum() || c == `_` }

pub fn instruction_position(line string, names []string) int {
	for index in 0 .. line.len {
		if index > 0 && word_character(line[index - 1]) { continue }
		for name in names {
			end := index + name.len
			if end < line.len && line[index..end] == name && line[end].is_space() { return index }
		}
	}
	return -1
}

fn selected_lines(body string, names []string, suffix string) []json2.Any {
	mut result := []json2.Any{}
	for line in body.split_into_lines() {
		position := instruction_position(line, names)
		if position >= 0 && (suffix == '' || line[position..].contains(suffix)) {
			result << json2.Any(line.trim_space())
		}
	}
	return result
}

pub fn collect_objects(context Context) !int {
	output := if context.state == os.dir(context.origin) { context.root + '/build/useralloc-review-v6' } else { context.state }
	mkdirs(output)!
	patch := digest(context.root + '/build-support/musl/malloc-retain.patch')!
	mut records := map[string]json2.Any{}
	mut checks := []bool{}
	mut object_count := 0
	for stage in ['optimized-v6-final', 'disabled-v6-final', 'optimized-arm126-v6-final',
		'disabled-arm126-v6-final'] {
		base := context.root + '/third_party/useralloc-libc/build/useralloc/' + stage
		manifest_path := base + '/usr/share/vinix/musl-build.json'
		manifest := read_json(manifest_path)!
		source := os.dir(manifest['configure_argv']!.as_array()[0].str())
		cache := os.dir(source)
		cached := read_json(cache + '/build.json')!
		toolbase := os.dir(manifest['cc']!.as_array()[0].str())
		prefix := manifest['compiler_target']!.str() + '-'
		objdump := toolbase + '/' + prefix + 'objdump'
		readelf := toolbase + '/' + prefix + 'readelf'
		loader := base + '/lib/ld-musl-' + manifest['arch']!.str() + '.so.1'
		archive := base + '/usr/lib/libc.a'
		loader_sha := digest(loader)!
		archive_sha := digest(archive)!
		mut record := map[string]json2.Any{
			'manifest': json2.Any(manifest)
			'manifest_sha256': json2.Any(digest(manifest_path)!)
			'stage_manifest_matches_cache': json2.Any(manifest == cached)
			'patch_sha256_matches_candidate': json2.Any(manifest['patches']!.as_array().last().as_map()['sha256']!.str() == patch)
			'cached_patch_sha256_matches_candidate': json2.Any(digest(cache + '/patches/malloc-retain.patch')! == patch)
			'loader_sha256': json2.Any(loader_sha)
			'archive_sha256': json2.Any(archive_sha)
			'loader_matches_manifest_and_cache': json2.Any(loader_sha == manifest['libc_so_sha256']!.str() && loader_sha == digest(cache + '/objects/lib/libc.so')!)
			'archive_matches_manifest_and_cache': json2.Any(archive_sha == manifest['libc_a_sha256']!.str() && archive_sha == digest(cache + '/objects/lib/libc.a')!)
		}
		for key in ['stage_manifest_matches_cache', 'patch_sha256_matches_candidate',
			'cached_patch_sha256_matches_candidate', 'loader_matches_manifest_and_cache',
			'archive_matches_manifest_and_cache'] { checks << record[key]!.bool() }
		mut sources := map[string]json2.Any{}
		for name in ['malloc.c', 'meta.h', 'free.c', 'glue.h', 'realloc.c', 'aligned_alloc.c'] {
			sources[name] = digest(source + '/src/malloc/mallocng/' + name)!
		}
		record['source_sha256'] = sources
		members := archive_members(os.read_bytes(archive)!)!
		mut objects := map[string]json2.Any{}
		for name in ['malloc', 'free', 'realloc'] {
			for extension in ['o', 'lo'] {
				object := cache + '/objects/obj/src/malloc/mallocng/' + name + '.' + extension
				assembly := captured([objdump, '-dr', object])!
				assembly_path := output + '/' + stage + '-' + name + '-' + extension + '.asm'
				os.write_file(assembly_path, assembly)!
				symbol := {'malloc': '__libc_malloc_impl', 'free': '__libc_free', 'realloc': '__libc_realloc'}[name]!
				body := assembly_function(assembly, symbol)!
				mut item := map[string]json2.Any{
					'object_sha256': json2.Any(digest(object)!)
					'object_path': json2.Any(relative_to_root(object, context.root)!)
					'assembly_sha256': json2.Any(digest(assembly_path)!)
					'assembly_path': json2.Any(relative_to_root(assembly_path, context.root)!)
					'function_has_stack_canary_reference': json2.Any(body.contains('__stack_chk_fail'))
					'object_has_stack_canary_reference': json2.Any(assembly.contains('__stack_chk_fail'))
					'trap_instruction_present': json2.Any(assembly.contains(if manifest['arch']!.str() == 'x86_64' { 'ud2' } else { 'brk' }))
					'function_calls': json2.Any(selected_lines(body, ['call', 'bl'], ''))
				}
				if manifest['arch']!.str() == 'x86_64' {
					item['function_pushes'] = selected_lines(body, ['push'], '')
					item['function_stack_arithmetic'] = selected_lines(body, ['sub', 'add'], '%rsp')
					if name == 'malloc' {
						item['malloc_slow_tail_jump_relocations'] = body.split_into_lines().filter(it.contains('.text.malloc_slow')).map(json2.Any(it.trim_space()))
						checks << item['function_pushes']!.as_array().len == 2 && item['function_stack_arithmetic']!.as_array().len == 0 && item['function_calls']!.as_array().len == 0 && item['malloc_slow_tail_jump_relocations']!.as_array().len > 0
					}
				}
				if extension == 'o' {
					data := members[name + '.o']!
					bytes := os.read_bytes(object)!
					matches := data.filter(it == bytes).len
					item['archive_member_count'] = u64(data.len)
					item['archive_member_sha256s'] = data.map(json2.Any(sha256.sum(it).hex()))
					item['archive_byte_identical_member_count'] = u64(matches)
					item['archive_member_byte_identical'] = matches == 1
					checks << matches == 1
				}
				if name == 'free' { checks << !assembly.contains('__stack_chk_fail') }
				objects[name + '.' + extension] = item.clone()
				object_count++
			}
		}
		record['objects'] = objects
		symbol_path := output + '/' + stage + '-symbols.txt'
		os.write_file(symbol_path, captured([readelf, '-Ws', loader])!)!
		record['loader_symbols_sha256'] = digest(symbol_path)!
		records[stage] = record.clone()
	}
	result := map[string]json2.Any{
		'candidate_patch_sha256': json2.Any(patch)
		'all_machine_checks_pass': json2.Any(checks.all(it))
		'object_count': json2.Any(u64(object_count))
		'stages': json2.Any(records)
	}
	write_json(output + '/object-proof.json', result)!
	mut stages := map[string]json2.Any{}
	for name, value in records {
		row := value.as_map()
		mut item := map[string]json2.Any{}
		for key in ['arch', 'retention'] { item[key] = row['manifest']!.as_map()[key]! }
		for key in ['loader_sha256', 'archive_sha256'] { item[key] = row[key]! }
		stages[name] = item
	}
	println(json2.encode({
		'all_machine_checks_pass': result['all_machine_checks_pass']!
		'object_count': result['object_count']!
		'stages': json2.Any(stages)
	}, prettify: true))
	return 0
}
