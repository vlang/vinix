// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import os
import strconv

fn attribute(line string, key string) !u64 {
	for word in line.all_before('>').split(' ') {
		if word.starts_with(key + '=') { return strconv.parse_uint(word.all_after('=').trim_right('/'), 10, 64)! }
	}
	return error('missing LLVM attribute ' + key)
}
fn code_id(line string) !u64 {
	if line.starts_with('<UnknownCode') { return strconv.parse_uint(line.all_after('<UnknownCode').all_before(' ').trim_right('/>'), 10, 64)! }
	return attribute(line, 'codeid')!
}

// Independent LLVM trace inventory: declaration count, constant record order,
// SETTYPE state and module/function ID ranges. Literal bit semantics are checked
// separately against known inputs assembled by LLVM, not inferred from this dump.
fn inventory(stream airbitcode.Stream, ir airbitcode.IRModule, pools airbitcode.IRConstantPools, oracle string) ! {
	mut stack := []u64{}
	stack.flags |= .noslices
	defer { unsafe { stack.free() } }
	mut default_type := -1
	for i, typ in ir.types { if typ.kind == .integer_t && typ.bits == 32 { default_type = i; break } }
	mut current := default_type
	mut module_values := u32(0)
	mut declarations := 0
	mut next_function := 0
	mut function_scope := -1
	mut scope := -1
	mut ordinal := 0
	mut checked := 0
	mut body_count := 0
	for raw in oracle.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('</') {
			if stack.len == 0 { return error('unbalanced LLVM inventory') }
			id := stack.pop()
			if id == 11 {
				if scope < 0 || ordinal != pools.scopes[scope].count { return error('LLVM pool count differs') }
				scope = -1
			}
			if id == 12 { function_scope = -1 }
			continue
		}
		if line.all_before('>').contains(' BlockID=') || line.starts_with('<UnknownBlock') {
			id := if line.starts_with('<UnknownBlock') { strconv.parse_uint(line.all_after('<UnknownBlock').all_before(' '), 10, 64)! } else { attribute(line, 'BlockID')! }
			if id == 12 {
				for next_function < ir.functions.len && ir.functions[next_function].declaration { next_function++ }
				if next_function >= ir.functions.len { return error('extra LLVM function body') }
				function_scope = next_function + 1; next_function++; body_count++
			}
			if id == 11 {
				if stack.len == 0 { return error('unscoped LLVM constants') }
				scope = if stack.last() == 8 { 0 } else if stack.last() == 12 { function_scope } else { -1 }
				if scope < 0 { return error('LLVM constant scope differs') }
				current = default_type; ordinal = 0
			}
			if !line.contains('/>') { stack << id }
			continue
		}
		if stack.len == 0 || (!line.contains(' codeid=') && !line.starts_with('<UnknownCode')) { continue }
		code := code_id(line)!
		if stack.last() == 8 && code in [u64(7), 8, 9, 14, 18]! { declarations++; module_values++ }
		if stack.last() != 11 { continue }
		if code == 1 { current = int(attribute(line, 'op0')!); continue }
		entry := pools.scopes[scope]
		if ordinal >= entry.count { return error('extra LLVM constant') }
		constant := pools.constants[entry.first + ordinal]
		number := if scope == 0 { module_values } else { module_values + u32(entry.arguments_count + ordinal) }
		if constant.type_index != current || constant.scope != scope || constant.number != number || stream.records[constant.record].code != code { return error('LLVM constant type/order/value-ID differs') }
		if scope == 0 { module_values++ }
		ordinal++; checked++
	}
	mut expected_bodies := 0
	for function in ir.functions { if !function.declaration { expected_bodies++ } }
	if stack.len != 0 || checked != pools.constants.len || declarations != pools.declarations.len || module_values != pools.module_values || expected_bodies != body_count { return error('incomplete LLVM constant inventory') }
	println('LLVM-CONSTANT-INVENTORY: ${checked} typed records, ${declarations} declarations, ${body_count} function scopes and value IDs match; opaque expressions unevaluated')
}

fn totals(pools airbitcode.IRConstantPools) (int, int, int) {
	mut opaque := 0
	for constant in pools.constants { if constant.kind == .opaque { opaque++ } }
	println('AIR-CONSTANTS: ${pools.constants.len} constants, ${pools.words.len} words, ${opaque} opaque; ${pools.module_values} module IDs; no execution')
	return pools.constants.len, pools.words.len, opaque
}
fn inspect(path string) ! {
	if os.file_size(path) > airbitcode.max_input_size { return error('input size limit') }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!
	defer { stream.free() }
	ir := stream.ir_module(data)!
	defer { ir.free() }
	pools := ir.constant_pools(stream)!
	defer { pools.free() }
	totals(pools)
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
fn check_file(path string, dis string, analyzer string, base string) !(int, int, int) {
	if os.file_size(path) > airbitcode.max_input_size { return error('input size limit') }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!
	defer { stream.free() }
	ir := stream.ir_module(data)!
	defer { ir.free() }
	pools := ir.constant_pools(stream)!
	defer { pools.free() }
	os.cp(path, base + '.bc')!
	run_saved([dis, base + '.bc', '-o', base + '.ll'], base + '.dis')!
	run_saved([analyzer, '--dump', '--dump-blockinfo', '--non-symbolic', base + '.bc'], base + '.analyzer')!
	oracle := os.read_file(base + '.analyzer.log')!
	defer { unsafe { oracle.free() } }
	inventory(stream, ir, pools, oracle)!
	return totals(pools)
}
fn corpus(input string, dis string, analyzer string, output string) ! {
	fresh(output)!
	mut files := os.ls(input)!
	defer { unsafe { files.free() } }
	files.sort()
	mut modules := 0
	mut constants := 0
	mut words := 0
	mut opaque := 0
	for file in files {
		if !file.starts_with('module-') || !file.ends_with('.bc') { continue }
		c, w, o := check_file(input + '/' + file, dis, analyzer, output + '/' + file.all_before_last('.bc'))!
		modules++; constants += c; words += w; opaque += o
	}
	if modules == 0 { return error('no raw module inputs') }
	println('AIR-CONSTANT-CORPUS: ${modules} modules, ${constants} constants, ${words} decoded words, ${opaque} opaque expressions; LLVM inventories match, shader execution unverified')
}

fn initializer(data []u8, stream airbitcode.Stream, pools airbitcode.IRConstantPools, name string) !int {
	mut table := airbitcode.Blob{}
	for record in stream.records { if stream.blocks[record.block].id == 23 && record.has_blob { table = record.blob } }
	for index in pools.declarations {
		record := stream.records[index]
		if record.code != 7 { continue }
		values := stream.values[record.values_start..record.values_start + record.values_count]
		if values.len < 8 || values[0] > table.size || values[1] > table.size - values[0] { return error('fixture global declaration') }
		start := int(table.offset + values[0])
		if data[start..start + int(values[1])].bytestr() == name {
			if values[4] == 0 { return error('fixture has no initializer') }
			value := pools.lookup(0, values[4] - 1)!
			if value.kind != .constant { return error('fixture initializer is not constant-pool entry') }
			return value.constant_index
		}
	}
	return error('fixture global missing: ' + name)
}

fn rejected_inventory(stream airbitcode.Stream, ir airbitcode.IRModule, pools airbitcode.IRConstantPools, oracle string, name string) ! {
	inventory(stream, ir, pools, oracle) or {
		println('LLVM-CONSTANT-NEGATIVE: ${name} rejected')
		return
	}
	return error('accepted corrupt constant inventory: ' + name)
}

fn negative_controls(stream airbitcode.Stream, ir airbitcode.IRModule, pools airbitcode.IRConstantPools, oracle string) ! {
	for pair in [['<SETTYPE ', 'op0=', 'op0=99999'], ['<GLOBALVAR ', 'codeid=7', 'codeid=99'], ['<INTEGER ', 'codeid=4', 'codeid=5'], ['<FUNCTION_BLOCK ', 'BlockID=12', 'BlockID=99']] {
		mut tested := false
		for raw in oracle.split_into_lines() {
			if !raw.trim_space().starts_with(pair[0]) || !raw.contains(pair[1]) { continue }
			header := raw.replace_once(pair[1], pair[2])
			if header == raw { return error('missing inventory control attribute') }
			changed := oracle.replace_once(raw, header)
			rejected_inventory(stream, ir, pools, changed, pair[0])!
			unsafe { changed.free(); header.free() }
			tested = true; break
		}
		if !tested { return error('missing inventory control input') }
	}
	for mode in ['number', 'type', 'record'] {
		mut constants := pools.constants.clone()
		defer { unsafe { constants.free() } }
		constant := constants[0]
		constants[0] = match mode {
			'number' { airbitcode.IRConstant{...constant, number: constant.number + 1} }
			'type' { airbitcode.IRConstant{...constant, type_index: constant.type_index + 1} }
			else { airbitcode.IRConstant{...constant, record: 0} }
		}
		changed := airbitcode.IRConstantPools{...pools, constants: constants}
		rejected_inventory(stream, ir, changed, oracle, mode)!
	}
	changed := airbitcode.IRConstantPools{...pools, module_values: pools.module_values + 1}
	rejected_inventory(stream, ir, changed, oracle, 'module value count')!
	println('LLVM-CONSTANT-NEGATIVE: all eight inventory corruption controls rejected')
}

fn self_test(assembler string, analyzer string, output string) ! {
	fresh(output)!
	// LLVM IR is fixture data, generated here by maintained V tooling.
	source := 'target triple = "x86_64-unknown-linux-gnu"
@s8 = constant i8 -1
@s1 = constant i1 true
@s64 = constant i64 -9223372036854775808
@s65 = constant i65 18446744073709551616
@s128 = constant i128 -170141183460469231731687303715884105728
@s130 = constant i130 -1
@half_nan = constant half 0xH7E01
@bfloat_nan = constant bfloat 0xR7FC1
@float_negzero = constant float -0.0
@float_value = constant float 1.5
@double_nan = constant double 0x7FF8000000001234
@extended = constant x86_fp80 0xK3FFF8000000000000000
@quad = constant fp128 0xL00000000000000003FFF000000000000
@string = constant [4 x i8] c"A\\00Z\\00"
@data = constant [2 x i32] [i32 -1, i32 -2147483648]
@zero = constant [1000000000 x i32] zeroinitializer
@undefined = constant i32 undef
@poisoned = constant i32 poison
@address = constant ptr getelementptr (i8, ptr @string, i64 1)
@aggregate = constant { i32, ptr } { i32 7, ptr @string }
define i32 @sample(i32 %a) {
  %b = add i32 %a, 123
  ret i32 %b
}
define i32 @other(i32 %a) {
  %b = add i32 %a, -7
  ret i32 %b
}
declare void @external()
'
	os.write_file(output + '/fixture.ll', source)!
	run_saved([assembler, output + '/fixture.ll', '-o', output + '/fixture.bc'], output + '/assemble')!
	run_saved([analyzer, '--dump', '--dump-blockinfo', '--non-symbolic', output + '/fixture.bc'], output + '/analyzer')!
	data := os.read_bytes(output + '/fixture.bc')!
	defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!
	defer { stream.free() }
	ir := stream.ir_module(data)!
	defer { ir.free() }
	pools := ir.constant_pools(stream)!
	defer { pools.free() }
	expected := {
		's8': [u64(255)], 's1': [u64(1)], 's64': [u64(1) << 63], 's65': [u64(0), 1],
		's128': [u64(0), u64(1) << 63], 's130': [~u64(0), ~u64(0), 3],
		'half_nan': [u64(0x7e01)], 'bfloat_nan': [u64(0x7fc1)],
		'float_negzero': [u64(0x80000000)], 'float_value': [u64(0x3fc00000)],
		'double_nan': [u64(0x7ff8000000001234)], 'extended': [u64(0x8000000000000000), 0x3fff],
		'quad': [u64(0), 0x3fff000000000000], 'string': [u64(65), 0, 90, 0],
		'data': [u64(0xffffffff), 0x80000000]
	}
	for name, words in expected {
		index := initializer(data, stream, pools, name)!
		constant := pools.constants[index]
		if pools.words[constant.words_start..constant.words_start + constant.words_count] != words { return error('LLVM fixture bits differ: ' + name) }
	}
	for name, kind in {'zero': airbitcode.IRConstantKind.zero, 'undefined': .undef, 'poisoned': .poison, 'address': .opaque, 'aggregate': .aggregate} {
		index := initializer(data, stream, pools, name)!
		if pools.constants[index].kind != kind { return error('LLVM fixture kind differs: ' + name) }
		if _ := pools.scalar_bits(index) { return error('materialized non-scalar fixture: ' + name) }
	}
	if ir.functions.len != 3 || pools.scopes[1].count != 1 || pools.scopes[2].count != 1 { return error('LLVM fixture scope count') }
	first := pools.lookup(1, pools.module_values + 1)!.constant_index
	second := pools.lookup(2, pools.module_values + 1)!.constant_index
	if pools.scalar_bits(first)! != 123 || pools.scalar_bits(second)! != u64(0xfffffff9) || first == second { return error('LLVM function-local scope alias') }
	if pools.lookup(1, pools.module_values)!.kind != .argument { return error('LLVM fixture argument') }
	if _ := pools.lookup(0, pools.module_values + 1) { return error('local value leaked into module') }
	if _ := pools.lookup(3, 0) { return error('declaration has function scope') }
	oracle := os.read_file(output + '/analyzer.log')!
	defer { unsafe { oracle.free() } }
	inventory(stream, ir, pools, oracle)!
	negative_controls(stream, ir, pools, oracle)!
	println('LLVM-CONSTANT-FIXTURE: 15 exact literal bit patterns, five tagged non-scalars, module/local ID scopes and inventory PASS; no execution')
}
fn main() {
	if os.args.len == 3 && os.args[1] == 'inspect' { inspect(os.args[2])!; return }
	if os.args.len == 6 && os.args[1] == 'corpus' { corpus(os.args[2], os.args[3], os.args[4], os.args[5])!; return }
	if os.args.len == 5 && os.args[1] == 'self-test' { self_test(os.args[2], os.args[3], os.args[4])!; return }
	panic('usage: air-constants-inspect inspect FILE.bc | corpus INPUT_DIR LLVM_DIS LLVM_BCANALYZER FRESH_EXTERNAL_DIR | self-test LLVM_AS LLVM_BCANALYZER FRESH_EXTERNAL_DIR')
}
