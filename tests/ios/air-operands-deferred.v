// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import os

// Read-only diagnostic of the current partial profile, without invoking LLVM.
fn main() {
	if os.args.len < 2 { panic('usage: air-operands-deferred CORPUS_DIR [...]') }
	mut counts := []u64{len: 67}
	mut modules := 0; mut instructions := 0; mut deferred := 0
	defer { unsafe { counts.free() } }
	for directory in os.args[1..] {
		mut files := os.ls(directory)!; files.sort()
		defer { unsafe { files.free() } }
		for file in files {
			if !file.starts_with('module-') || !file.ends_with('.bc') { continue }
			data := os.read_bytes(directory + '/' + file)!; defer { unsafe { data.free() } }
			stream := airbitcode.parse(data)!; defer { stream.free() }
			ir := stream.ir_module(data)!; defer { ir.free() }
			pools := ir.constant_pools(stream)!; defer { pools.free() }
			bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }
			p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
			modules++; instructions += p.instructions.len
			mut shown := 0
			for i, op in p.instructions {
				if op.status != .deferred { continue }
				deferred++
				inst := bodies.instructions[i]; record := stream.records[inst.record]
				if record.code < u64(counts.len) { counts[int(record.code)]++ }
				if shown < 4 {
					println('DEFERRED ${directory}/${file} function=${ir.functions[inst.scope - 1].name} ordinal=${i - bodies.scopes[inst.scope].instructions_start} next=${inst.next_value} code=${record.code} type=${op.result_type} raw=${stream.values[record.values_start..record.values_start + record.values_count]}')
					shown++
				}
			}
		}
	}
	for code, count in counts { if count != 0 { println('DEFERRED-CODE ${code} ${count}') } }
	if modules == 0 { panic('no AIR modules') }
	println('DEFERRED-INVENTORY: ${modules} modules, ${instructions} instructions, ${deferred} deferred; no execution')
}
