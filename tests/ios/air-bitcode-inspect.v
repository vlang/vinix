// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import metallib
import os
import strconv

fn attribute(line string, key string) !u64 {
	for word in line.split(' ') {
		if word.starts_with(key + '=') { return strconv.parse_uint(word.all_after('=').trim_right('/>'), 10, 64)! }
	}
	return error('missing LLVM dump attribute: ' + key)
}

fn compare(stream airbitcode.Stream, data []u8, text string) ! {
	mut stack := [0]
	defer { unsafe { stack.free() } }
	stack.flags |= .noslices
	mut names := []string{}
	names.flags |= .noslices
	defer { unsafe { names.free() } }
	mut block_index := 1
	mut record_index := 0
	mut strings := []airbitcode.Blob{}
	defer { unsafe { strings.free() } }
	mut string_index := 0
	mut table_count := 0
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if string_index < strings.len {
			if !line.starts_with("'") || !line.ends_with("'") { return error('missing LLVM metadata string') }
			range := strings[string_index]
			compare_bytes(line[1..line.len - 1], data, range)!
			string_index++
			continue
		}
		if line.starts_with('</') {
			if stack.len <= 1 || line != '</' + names.last() + '>' { return error('unbalanced LLVM block dump') }
			stack.pop()
			names.pop()
			continue
		}
		if line.contains(' BlockID=') || line.starts_with('<UnknownBlock') {
			if block_index >= stream.blocks.len { return error('extra LLVM block') }
			block := stream.blocks[block_index]
			id := if line.starts_with('<UnknownBlock') { strconv.parse_uint(line.all_after('<UnknownBlock').all_before(' '), 10, 64)! } else { attribute(line, 'BlockID')! }
			if block.id != id || block.parent != stack.last()
				|| u64(block.width) != attribute(line, 'BlockCodeSize')!
				|| (block.end_bit - block.start_bit) / 32 != attribute(line, 'NumWords')! { return error('LLVM block differs') }
			if !line.contains('/>') {
				stack << block_index
				names << line.all_before(' ').all_after('<')
			}
			block_index++
		} else if line.contains(' codeid=') || line.starts_with('<UnknownCode') {
			if record_index >= stream.records.len { return error('extra LLVM record') }
			record := stream.records[record_index]
			code := if line.starts_with('<UnknownCode') { strconv.parse_uint(line.all_after('<UnknownCode').all_before(' ').trim_right('/>'), 10, 64)! } else { attribute(line, 'codeid')! }
			if record.block != stack.last() || record.code != code { return error('LLVM record code or scope differs') }
			mut count := 0
			for word in line.all_before('>').split(' ') {
				if !word.starts_with('op') { continue }
				if !word.starts_with('op' + count.str() + '=') || count >= record.values_count { return error('unexpected LLVM operand') }
				value := strconv.parse_uint(word.all_after('=').trim_right('/'), 10, 64)!
				if value != stream.values[record.values_start + count] { return error('LLVM operand differs') }
				count++
			}
			if count != record.values_count { return error('LLVM operand count differs') }
			marker := "blob data = '"
			if line.contains(' num-strings = ') {
				next := stream.metadata_strings(data, record_index)!
				// Transfer ownership only after successful decoding.
				unsafe { strings.free(); strings = next }
				if strconv.parse_uint(line.all_after(' num-strings = ').all_before(' '), 10, 64)! != u64(strings.len) { return error('LLVM metadata string count differs') }
				string_index = 0
				table_count++
			} else if line.contains(marker) != record.has_blob { return error('LLVM blob presence differs') }
			if line.contains(marker) {
				encoded := line.all_after(marker).all_before_last("'")
				compare_bytes(encoded, data, record.blob)!
			}
			record_index++
		}
	}
	if stack.len != 1 || block_index != stream.blocks.len || record_index != stream.records.len || string_index != strings.len { return error('incomplete LLVM comparison') }
	println('LLVM-COMPARE: blocks=${block_index - 1} records=${record_index} operands=${stream.values.len}; scopes/codes/operands and ordinary blob bytes match, ${table_count} metadata string tables match decoded strings; AIR execution unverified')
}

fn compare_bytes(encoded string, data []u8, range airbitcode.Blob) ! {
	actual := unescape(encoded)!
	defer { unsafe { actual.free() } }
	if actual != data[int(range.offset)..int(range.offset + range.size)] { return error('LLVM blob/string bytes differ') }
}

fn unescape(encoded string) ![]u8 {
	mut actual := []u8{}
	actual.flags |= .noslices
	mut keep := false
	defer { if !keep { unsafe { actual.free() } } }
	mut i := 0
	for i < encoded.len {
		if encoded[i] == `\\` {
			if i + 1 < encoded.len && encoded[i + 1] == `\\` { actual << u8(`\\`); i += 2; continue }
			if i + 1 < encoded.len && encoded[i + 1] in [u8(`n`), `r`, `t`, `a`, `b`, `f`, `v`, `"`, `'`]! {
				actual << match encoded[i + 1] { `n` { u8(10) } `r` { u8(13) } `t` { u8(9) } `a` { u8(7) } `b` { u8(8) } `f` { u8(12) } `v` { u8(11) } else { encoded[i + 1] } }
				i += 2
				continue
			}
			if i + 3 >= encoded.len || encoded[i + 1] != `x` { return error('unsupported LLVM dump escape') }
			actual << u8(strconv.parse_uint(encoded[i + 2..i + 4], 16, 8)!)
			i += 4
		} else { actual << encoded[i]; i++ }
	}
	keep = true
	return actual
}

fn compare_module(bytes []u8, llvm string, base string) !(int, int) {
	stream := airbitcode.parse(bytes)!
	defer { stream.free() }
	os.write_file_array(base + '.bc', bytes)!
	result := os.exec([llvm, '--dump', '--dump-blockinfo', '--non-symbolic', '--show-binary-blobs', base + '.bc'])
	defer { unsafe { result.output.free() } }
	os.write_file(base + '.llvm.log', result.output)!
	os.write_file(base + '.llvm.status', result.exit_code.str() + '\n')!
	if result.exit_code != 0 { return error('LLVM rejects ' + base) }
	compare(stream, bytes, result.output)!
	return stream.records.len, stream.values.len
}

fn corpus(path string, llvm string, out string) ! {
	if os.exists(out) || os.is_link(out) || out == os.getwd() || out.starts_with(os.getwd() + '/') { return error('requires fresh external output') }
	if os.file_size(path) > metallib.max_library_size { return error('library size limit') }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	library := metallib.parse(data)!
	defer { library.free() }
	os.mkdir_all(out)!
	os.cp(path, out + '/input.metallib')!
	mut total_records := 0
	mut total_values := 0
	for i, module in library.modules {
		range := module.bitcode
		bytes := data[int(range.offset)..int(range.offset + range.size)]
		base := out + '/module-' + i.str()
		records, values := compare_module(bytes, llvm, base)!
		total_records += records
		total_values += values
		if i % 50 == 0 { println('CORPUS-PROGRESS: module=${i}') }
	}
	println('CORPUS: ${library.modules.len} modules, ${total_records} records, ${total_values} operands match LLVM; shader execution unverified')
}

fn changed_attribute(text string, key string) !string {
	start := (text.index(key + '=') or { return error('control requires attribute ' + key) }) + key.len + 1
	mut end := start
	for end < text.len && text[end] >= `0` && text[end] <= `9` { end++ }
	if start == end { return error('control requires numeric attribute') }
	value := strconv.parse_uint(text[start..end], 10, 64)!
	return text[..start] + (if value == ~u64(0) { u64(0) } else { value + 1 }).str() + text[end..]
}

fn rejected(stream airbitcode.Stream, data []u8, oracle string, name string) ! {
	compare(stream, data, oracle) or {
		println('LLVM-NEGATIVE: ${name} rejected')
		return
	}
	return error('comparison accepted corrupt LLVM dump: ' + name)
}

// A complete LLVM dump with ordinary blobs and METADATA_STRINGS is required.
// Exercise the oracle too, so a vacuous comparison cannot qualify the corpus.
fn negative_controls(stream airbitcode.Stream, data []u8, oracle string) ! {
	compare(stream, data, oracle)!
	for key in ['BlockID', 'NumWords', 'BlockCodeSize', 'codeid', 'op0'] {
		changed := changed_attribute(oracle, key)!
		rejected(stream, data, changed, key)!
		unsafe { changed.free() }
	}
	changed_count := oracle.replace_once('num-strings = ', 'num-strings = 999')
	if changed_count == oracle { return error('control requires metadata strings') }
	rejected(stream, data, changed_count, 'metadata count')!
	unsafe { changed_count.free() }
	for marker in ["blob data = '", 'num-strings = '] {
		found := oracle.index(marker) or { return error('control requires ' + marker) }
		mut start := found + marker.len
		if marker == 'num-strings = ' {
			quote := oracle[start..].index("'") or { return error('missing quoted string') }
			start += quote + 1
		}
		if start >= oracle.len { return error('empty control input') }
		changed := oracle[..start] + (if oracle[start] == `x` { 'y' } else { 'x' }) + oracle[start + 1..]
		rejected(stream, data, changed, marker)!
		unsafe { changed.free() }
	}
	for raw in oracle.split_into_lines() {
		if raw.trim_space().starts_with('</') {
			changed := oracle.replace_once(raw, '</CORRUPT>')
			rejected(stream, data, changed, 'closing block')!
			unsafe { changed.free() }
			break
		}
	}
	for raw in oracle.split_into_lines() {
		if raw.contains(' codeid=') {
			missing := oracle.replace_once(raw + '\n', '')
			extra := oracle.replace_once(raw, raw + '\n' + raw)
			rejected(stream, data, missing, 'missing record')!
			rejected(stream, data, extra, 'extra record')!
			unsafe { missing.free(); extra.free() }
			break
		}
	}
	rejected(stream, data, oracle[..oracle.len / 2], 'truncation')!
	println('LLVM-NEGATIVE: all 12 corruption controls rejected')
}

fn main() {
	if os.args.len == 5 && os.args[1] == 'library' { corpus(os.args[2], os.args[3], os.abs_path(os.args[4]))!; return }
	if os.args.len < 3 || os.args[1] !in ['inspect', 'compare', 'negative-controls']
		|| (os.args[1] == 'inspect' && os.args.len != 3)
		|| (os.args[1] != 'inspect' && os.args.len != 4) {
		panic('usage: air-bitcode-inspect inspect FILE | compare FILE LLVM_DUMP | negative-controls FILE LLVM_DUMP | library MTLB LLVM_BCANALYZER FRESH_EXTERNAL_DIR')
	}
	if os.file_size(os.args[2]) > airbitcode.max_input_size { panic('input size limit') }
	data := os.read_bytes(os.args[2])!
	defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!
	defer { stream.free() }
	println('AIR-BITSTREAM: blocks=${stream.blocks.len - 1} records=${stream.records.len} operands=${stream.values.len}; encoding only, IR semantics and shader execution unverified')
	if os.args[1] in ['compare', 'negative-controls'] {
		oracle := os.read_file(os.args[3])!
		defer { unsafe { oracle.free() } }
		if os.args[1] == 'compare' {
			compare(stream, data, oracle)!
		} else {
			negative_controls(stream, data, oracle)!
		}
		return
	}
	for record in stream.records {
		block := stream.blocks[record.block]
		if block.id == 8 && record.code in [u64(2), 3, 16]! {
			mut bytes := []u8{cap: record.values_count}
			for value in stream.values[record.values_start..record.values_start + record.values_count] {
				if value > 255 { panic('non-byte module header value') }
				bytes << u8(value)
			}
			println('MODULE-HEADER: code=${record.code} text=' + bytes.bytestr())
			unsafe { bytes.free() }
		}
	}
}
