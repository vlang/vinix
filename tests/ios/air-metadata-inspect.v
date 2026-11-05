// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import os
import strconv

// LLVM's printed metadata IDs differ from bitcode IDs. Compare rooted graphs,
// including inline strings/values, without assuming either numbering scheme.
struct LLVMMetadata {
mut:
	nodes map[int]string
	named map[string]string
}
fn (graph &LLVMMetadata) free() {
	unsafe {
		for _, value in graph.nodes { value.free() }
		for _, value in graph.named { value.free() }
		graph.nodes.free(); graph.named.free()
	}
}
fn llvm_metadata(source string) !LLVMMetadata {
	mut graph := LLVMMetadata{}
	mut keep := false
	defer { if !keep { graph.free() } }
	for line in source.split_into_lines() {
		if !line.starts_with('!') || !line.contains(' = ') { continue }
		name := line[1..].all_before(' = ')
		rhs := line.all_after(' = ')
		if name.len > 0 && name[0] >= `0` && name[0] <= `9` {
			id := strconv.atoi(name)!
			if id in graph.nodes { return error('duplicate LLVM metadata ID') }
			graph.nodes[id] = rhs.clone()
		} else {
			if name in graph.named { return error('duplicate LLVM named metadata') }
			graph.named[name] = rhs.clone()
		}
	}
	keep = true
	return graph
}
fn llvm_string(text string) !string {
	if text.len < 2 || text[0] != `"` || text[text.len - 1] != `"` { return error('expected LLVM quoted bytes') }
	mut bytes := []u8{cap: text.len}
	defer { unsafe { bytes.free() } }
	mut i := 1
	for i < text.len - 1 {
		if text[i] == `\\` {
			if i + 1 < text.len - 1 && text[i + 1] in [u8(`\\`), `"`]! { bytes << text[i + 1]; i += 2; continue }
			if i + 2 >= text.len - 1 { return error('truncated LLVM byte escape') }
			bytes << u8(strconv.parse_uint(text[i + 1..i + 3], 16, 8)!)
			i += 3
		} else { bytes << text[i]; i++ }
	}
	return bytes.bytestr()
}
fn llvm_symbol(text string) !string {
	if !text.contains('@') { return error('expected LLVM symbol') }
	name := text.all_after('@')
	return if name.starts_with('"') { llvm_string(name)! } else { name.clone() }
}
fn (graph LLVMMetadata) resolve(text string) !string {
	if text.len > 1 && text[0] == `!` && text[1] >= `0` && text[1] <= `9` {
		id := strconv.atoi(text[1..])!
		return graph.nodes[id] or { return error('unresolved LLVM metadata') }
	}
	return text
}
fn tuple_fields(text string) ![]string {
	body := if text.starts_with('distinct ') { text[9..] } else { text }
	if !body.starts_with('!{') || !body.ends_with('}') { return error('expected LLVM tuple') }
	mut fields := []string{}
	mut start := 2
	mut depth := 0
	mut quoted := false
	for i in 2 .. body.len - 1 {
		byte := body[i]
		if byte == `"` { quoted = !quoted }
		if quoted { continue }
		if byte in [u8(`{`), `[`, `(`, `<`]! { depth++ }
		if byte in [u8(`}`), `]`, `)`, `>`]! { depth-- }
		if depth < 0 { return error('unbalanced LLVM tuple') }
		if byte == `,` && depth == 0 { fields << body[start..i].trim_space(); start = i + 1 }
	}
	if quoted || depth != 0 { return error('unbalanced LLVM tuple field') }
	if start < body.len - 1 { fields << body[start..body.len - 1].trim_space() }
	return fields
}
fn llvm_integer(text string, bits u32) !u64 {
	prefix := 'i${bits} '
	if !text.starts_with(prefix) || bits == 0 || bits > 64 { return error('LLVM integer type differs') }
	value := text[prefix.len..]
	mut number := u64(0)
	if bits == 1 && value in ['true', 'false'] { number = if value == 'true' { 1 } else { 0 } }
	else if value.starts_with('-') { number = u64(0) - strconv.parse_uint(value[1..], 10, 64)! }
	else { number = strconv.parse_uint(value, 10, 64)! }
	return if bits == 64 { number } else { number & ((u64(1) << bits) - 1) }
}
fn value_symbol(data []u8, stream airbitcode.Stream, ir airbitcode.IRModule, record int) !string {
	for function in ir.functions { if function.record == record { return function.name } }
	raw := stream.records[record]
	if raw.code != 7 || raw.values_count < 2 { return error('unsupported LLVM metadata symbol kind') }
	values := stream.values[raw.values_start..raw.values_start + raw.values_count]
	for entry in stream.records {
		if stream.blocks[entry.block].id != 23 || !entry.has_blob { continue }
		if values[0] > entry.blob.size || values[1] > entry.blob.size - values[0] { return error('global symbol bounds') }
		start := int(entry.blob.offset + values[0])
		return unsafe { tos(&data[start], int(values[1])) }
	}
	return error('metadata symbol has no STRTAB')
}
fn graph_node(data []u8, stream airbitcode.Stream, ir airbitcode.IRModule, pools airbitcode.IRConstantPools,
	md airbitcode.IRMetadata, graph LLVMMetadata, index int, text string, mut visited map[int]int, mut distinct map[int]int, depth int) ! {
	if depth > 64 { return error('LLVM graph comparison depth limit') }
	if index < 0 { if text != 'null' { return error('LLVM null differs') }; return }
	node := md.nodes[index]
	match node.kind {
		.text {
			if !text.starts_with('!"') { return error('LLVM metadata string kind differs') }
			value := llvm_string(text[1..])!
			defer { unsafe { value.free() } }
			if value != node.text { return error('LLVM metadata string bytes differ') }
		}
		.value {
			typ := ir.types[node.type_index]
			if typ.kind == .integer_t {
				if llvm_integer(text, typ.bits)! != md.integer(ir, pools, index)! { return error('LLVM metadata integer differs') }
			} else if typ.kind == .pointer_t {
				prefix := if typ.address_space == 0 { 'ptr @' } else { 'ptr addrspace(${typ.address_space}) @' }
				if !text.starts_with(prefix) { return error('LLVM metadata pointer type differs') }
				value := pools.lookup(0, node.value_number)!
				if value.kind != .declaration { return error('unsupported metadata pointer constant') }
				name := llvm_symbol(text)!
				defer { unsafe { name.free() } }
				if value_symbol(data, stream, ir, value.record)! != name { return error('LLVM metadata symbol differs') }
			} else { return error('unsupported rooted LLVM metadata value') }
		}
		.tuple {
			if text.len < 2 || text[0] != `!` { return error('expected LLVM tuple ID') }
			id := strconv.atoi(text[1..])!
			if previous := visited[index] {
				if previous != id { return error('LLVM tuple reference identity differs') }
				return
			}
			if node.distinct {
				if previous := distinct[id] { if previous != index { return error('LLVM distinct tuple identity differs') } }
				distinct[id] = index
			}
			visited[index] = id
			rhs := graph.resolve(text)!
			if rhs.starts_with('distinct ') != node.distinct { return error('LLVM metadata distinctness differs') }
			fields := tuple_fields(rhs)!
			defer { unsafe { fields.free() } }
			refs := md.tuple(index)!
			if fields.len != refs.len { return error('LLVM metadata tuple arity differs') }
			for i, ref in refs { graph_node(data, stream, ir, pools, md, graph, ref, fields[i], mut visited, mut distinct, depth + 1)! }
		}
		.opaque { return error('opaque debug/legacy metadata in AIR entry graph') }
	}
}
fn compare(data []u8, stream airbitcode.Stream, ir airbitcode.IRModule, pools airbitcode.IRConstantPools,
	md airbitcode.IRMetadata, source string) ! {
	graph := llvm_metadata(source)!
	defer { graph.free() }
	mut visited := map[int]int{}
	mut distinct := map[int]int{}
	defer { unsafe { visited.free(); distinct.free() } }
	mut roots := 0
	mut llvm_roots := 0
	for name, _ in graph.named { if name in ['air.vertex', 'air.fragment', 'air.kernel'] { llvm_roots++ } }
	for named in md.named {
		if named.name !in ['air.vertex', 'air.fragment', 'air.kernel'] { continue }
		rhs := graph.named[named.name] or { return error('LLVM AIR stage root missing') }
		fields := tuple_fields(rhs)!
		defer { unsafe { fields.free() } }
		if fields.len != named.refs_count { return error('LLVM AIR entry count differs') }
		for i in 0 .. fields.len { graph_node(data, stream, ir, pools, md, graph, md.edges[named.refs_start + i], fields[i], mut visited, mut distinct, 0)! }
		roots++
	}
	if roots != llvm_roots { return error('extra LLVM AIR stage roots') }
	println('LLVM-AIR-METADATA: ${roots} stage roots, ${visited.len} rooted tuples match (strings, integers, symbols, nulls and graph shape)')
}

fn fresh(path string) ! {
	out := os.abs_path(path)
	if os.exists(out) || os.is_link(out) || out == os.getwd() || out.starts_with(os.getwd() + '/') { return error('requires fresh external output') }
	os.mkdir_all(out)!
}
fn run_saved(args []string, base string) ! {
	result := os.exec(args)
	defer { unsafe { result.output.free() } }
	os.write_file(base + '.log', result.output)!
	os.write_file(base + '.status', result.exit_code.str() + '\n')!
	if result.exit_code != 0 { return error('LLVM command failed: ' + args[0]) }
}

fn inspect(path string, oracle string) !(int, int, int) {
	if os.file_size(path) > airbitcode.max_input_size { return error('input size limit') }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!
	defer { stream.free() }
	ir := stream.ir_module(data)!
	defer { ir.free() }
	pools := ir.constant_pools(stream)!
	defer { pools.free() }
	md := ir.module_metadata(data, stream, pools)!
	defer { md.free() }
	entries := md.air_entries(ir, pools)!
	defer { entries.free() }
	if oracle != '' {
		source := os.read_file(oracle)!
		defer { unsafe { source.free() } }
		compare(data, stream, ir, pools, md, source)!
	}
	println('AIR-METADATA: ${md.nodes.len} nodes, ${md.named.len} names, ${entries.entries.len} classic entries, ${entries.arguments.len} arguments')
	for entry in entries.entries {
		println('ENTRY: ${entry.stage} ' + ir.functions[entry.function].name)
		for arg in entries.arguments[entry.arguments_start..entry.arguments_start + entry.arguments_count] {
			println('ARG: ${arg.index} ${arg.kind} ${arg.name} location=${arg.has_location}/${arg.location}/${arg.location_count} opaque=${arg.opaque_attributes}')
		}
	}
	return md.nodes.len, entries.entries.len, entries.arguments.len
}
fn corpus(input string, dis string, output string) ! {
	fresh(output)!
	mut files := os.ls(input)!
	files.sort()
	mut count := 0
	mut nodes := 0
	mut entries := 0
	mut arguments_count := 0
	for file in files {
		if !file.ends_with('.bc') { continue }
		println('MODULE: ' + file)
		base := output + '/' + file.all_before_last('.bc')
		os.cp(input + '/' + file, base + '.bc')!
		run_saved([dis, base + '.bc', '-o', base + '.ll'], base + '.dis')!
		n, e, a := inspect(base + '.bc', base + '.ll')!
		count++; nodes += n; entries += e; arguments_count += a
	}
	if count == 0 { return error('no raw modules') }
	println('CORPUS: ${count} modules, ${nodes} metadata nodes, ${entries} classic entries, ${arguments_count} arguments; LLVM rooted graphs match; no execution')
}
fn self_test(assembler string, dis string, output string) ! {
	fresh(output)!
	// Portable LLVM fixture data, not an executable iOS application.
	source := 'target triple = "x86_64-unknown-linux-gnu"
@predicate = addrspace(2) constant i1 true
define void @kernel_main(ptr addrspace(1) %buffer, <3 x i32> %gid) { ret void }
define <4 x float> @vertex_main(i32 %id) { ret <4 x float> zeroinitializer }
define <4 x float> @fragment_main(<4 x float> %color) { ret <4 x float> %color }
!air.kernel = !{!0}
!air.vertex = !{!10}
!air.fragment = !{!20}
!air.mesh = !{!31}
!0 = !{ptr @kernel_main, !1, !2, !30}
!1 = distinct !{}
!2 = !{!3, !4}
!3 = !{i32 0, !"air.function_constant", !5, !"air.buffer", !"air.location_index", i32 7, i32 2, !"air.address_space", i32 1, !"air.arg_type_size", i32 16, !"air.arg_type_align_size", i32 16, !"air.buffer_size", i32 32, !"air.read", !"air.arg_name", !"buf\\00\\22\\5C,end", !"air.arg_type_name", !"float4"}
!4 = !{i32 1, !"air.thread_position_in_grid", !"air.arg_name", !"gid"}
!5 = !{ptr addrspace(2) @predicate, !"bool", !"predicate"}
!10 = !{ptr @vertex_main, !11, !12}
!11 = !{!13}
!12 = !{!14}
!13 = !{!"air.position", !"air.arg_type_name", !"float4"}
!14 = !{i32 0, !"air.vertex_id", !"air.arg_name", !"vertexID"}
!20 = !{ptr @fragment_main, !21, !22}
!21 = !{!23}
!22 = !{!24}
!23 = !{!"air.render_target", i32 0, !"air.arg_type_name", !"float4"}
!24 = !{i32 0, !"air.fragment_input", !"user(color)", !"air.flat", !"air.arg_name", !"color"}
!30 = distinct !{null, i64 -9223372036854775808, !30}
!31 = !{!"future-stage"}
'
	os.write_file(output + '/fixture-input.ll', source)!
	run_saved([assembler, output + '/fixture-input.ll', '-o', output + '/fixture.bc'], output + '/assemble')!
	run_saved([dis, output + '/fixture.bc', '-o', output + '/fixture.ll'], output + '/disassemble')!
	data := os.read_bytes(output + '/fixture.bc')!
	defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!
	defer { stream.free() }
	ir := stream.ir_module(data)!
	defer { ir.free() }
	pools := ir.constant_pools(stream)!
	defer { pools.free() }
	md := ir.module_metadata(data, stream, pools)!
	defer { md.free() }
	entries := md.air_entries(ir, pools)!
	defer { entries.free() }
	if entries.entries.len != 3 || entries.arguments.len != 4 { return error('fixture stage/argument counts differ') }
	mut stages := [false, false, false]!
	for entry in entries.entries {
		stages[int(entry.stage)] = true
		name := ir.functions[entry.function].name
		args := entries.arguments[entry.arguments_start..entry.arguments_start + entry.arguments_count]
		match entry.stage {
			.kernel {
				if name != 'kernel_main' || args.len != 2 || !entry.opaque_attributes { return error('fixture kernel reflection') }
				arg := args[0]
				if arg.index != 0 || arg.kind != 'air.buffer' || arg.name != 'buf\x00"\\,end' || arg.type_name != 'float4'
					|| !arg.has_location || arg.location != 7 || arg.location_count != 2 || !arg.has_address_space || arg.address_space != 1
					|| !arg.has_size || arg.size != 16 || !arg.has_alignment || arg.alignment != 16 || !arg.has_buffer_size || arg.buffer_size != 32
					|| arg.access != .read || arg.condition < 0 || !arg.opaque_attributes { return error('fixture exact conditional binding fields') }
				if args[1].index != 1 || args[1].kind != 'air.thread_position_in_grid' || args[1].name != 'gid' { return error('fixture builtin input') }
			}
			.vertex {
				if name != 'vertex_main' || args.len != 1 || args[0].name != 'vertexID' || args[0].kind != 'air.vertex_id' { return error('fixture vertex reflection') }
			}
			.fragment {
				if name != 'fragment_main' || args.len != 1 || args[0].name != 'color' || args[0].kind != 'air.fragment_input' || !args[0].opaque_attributes { return error('fixture fragment reflection') }
			}
		}
	}
	if !stages[0] || !stages[1] || !stages[2] { return error('fixture missing shader stage') }
	oracle := os.read_file(output + '/fixture.ll')!
	defer { unsafe { oracle.free() } }
	compare(data, stream, ir, pools, md, oracle)!
	mut controls := 0
	for pair in [['!air.kernel = ', '!air.other = '], ['@kernel_main', '@wrong_kernel'], ['!"air.arg_name"', '!"air.bad_name"'],
		['i32 16', 'i32 48'], ['ptr addrspace(2) @predicate', 'ptr @predicate'], ['null', '!999999'],
		['i64 -9223372036854775808', 'i64 -9223372036854775807'], ['distinct !{}', '!{}'], ['!"user(color)"', '!"user(other)"']] {
		if !oracle.contains(pair[0]) { return error('missing graph control input') }
		// Replace all occurrences for the function name, including its definition.
		changed := oracle.replace(pair[0], pair[1])
		defer { unsafe { changed.free() } }
		compare(data, stream, ir, pools, md, changed) or { controls++; continue }
		return error('accepted corrupted LLVM graph: ' + pair[0])
	}
	graph := llvm_metadata(oracle)!
	defer { graph.free() }
	root := graph.named['air.vertex']
	changed := oracle.replace('!air.vertex = ' + root, '!air.vertex = !{}')
	defer { unsafe { changed.free() } }
	mut removed_rejected := false
	compare(data, stream, ir, pools, md, changed) or { removed_rejected = true; controls++ }
	if !removed_rejected { return error('accepted removed LLVM entry') }
	for id, rhs in graph.nodes {
		if !rhs.starts_with('distinct !{null,') { continue }
		// Preserve labels/values but split one self-cycle into two distinct nodes.
		tail := rhs.replace('!${id}', '!999998')
		duplicated := oracle.replace('!${id} = ' + rhs, '!${id} = ' + tail) + '\n!999998 = ' + tail + '\n'
		defer { unsafe { tail.free(); duplicated.free() } }
		compare(data, stream, ir, pools, md, duplicated) or {
			controls++
			println('LLVM-AIR-SELFTEST: three stages, four typed inputs, exact binding fields, escaped/NUL strings, conditional global, null/cycle identities and ${controls} rejected evidence corruptions PASS')
			return
		}
		return error('accepted split distinct cycle')
	}
	return error('missing distinct cycle control input')
}
fn main() {
	if os.args.len == 5 && os.args[1] == 'self-test' { self_test(os.args[2], os.args[3], os.args[4])!; return }
	if os.args.len == 5 && os.args[1] == 'corpus' { corpus(os.args[2], os.args[3], os.args[4])!; return }
	if os.args.len == 4 && os.args[1] == 'compare' { inspect(os.args[2], os.args[3])!; return }
	if os.args.len == 3 && os.args[1] == 'inspect' { inspect(os.args[2], '')!; return }
	panic('usage: air-metadata-inspect inspect FILE.bc | compare FILE.bc LLVM.ll | corpus INPUT_DIR LLVM_DIS FRESH_EXTERNAL_DIR | self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR')
}
