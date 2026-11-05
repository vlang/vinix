// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

pub enum IRScalarKind { integer binary32 }
pub struct IRScalarRun {
pub:
	kind IRScalarKind
	bits u32
	value u64 // Raw bits. Ignored when poison is true.
	poison bool
	steps int
}
fn (p IRTypedProgram) execution_bits(index int, binary32 bool) !u32 {
	if binary32 && index >= 0 && index < p.types.len && p.types[index].kind == .float_t { return 32 }
	return p.integer_bits(index)!
}
// The mixed profile admits i1..i64 and binary32 bit patterns. It shares the
// integer interpreter's ownership, control-flow, validity and work constraints.
pub fn (p IRTypedProgram) run_scalar_function(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, function int, arguments []u64, step_limit int) !IRScalarRun {
	run := p.run_scalar_bits(ir, stream, pools, bodies, function, arguments, step_limit, true)!
	typ := ir.types[ir.references[ir.types[ir.functions[function].signature].refs_start]]
	return IRScalarRun{if typ.kind == .float_t { .binary32 } else { .integer }, run.bits, run.value, run.poison, run.steps}
}
