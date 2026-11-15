// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Owns only the validated profile. All module/stream/pool/body/program indexes
// and their backing bitcode are borrowed: keep them alive and immutable until
// after the last run, then free this object once before freeing those indexes.
// Each run owns separate execution scratch and borrows only its own bindings.
pub struct IRPreparedMemoryFunction {
	ready    bool
	program  IRTypedProgram
	ir       IRModule
	stream   Stream
	pools    IRConstantPools
	bodies   IRFunctionBodies
	function int
	profile  IRMemoryProfile
}

pub fn (p IRTypedProgram) prepare_memory_function(ir IRModule, stream Stream,
	pools IRConstantPools, bodies IRFunctionBodies, function int) !IRPreparedMemoryFunction {
	profile := p.memory_function_profile(ir, stream, pools, bodies, function)!
	return IRPreparedMemoryFunction{true, p, ir, stream, pools, bodies, function, profile}
}

pub fn (f &IRPreparedMemoryFunction) free() {
	if f.ready { f.profile.free() }
}

pub fn (f &IRPreparedMemoryFunction) steps() int { return f.profile.steps }

pub fn (f &IRPreparedMemoryFunction) argument_count() int { return f.profile.arguments.len }

// Return a copy so callers cannot change the cached binding requirements.
pub fn (f &IRPreparedMemoryFunction) argument(index int) !IRMemoryArgument {
	if !f.ready || index < 0 || index >= f.profile.arguments.len {
		return error('AIR prepared memory: argument index')
	}
	return f.profile.arguments[index]
}

pub fn (f &IRPreparedMemoryFunction) run(mut bindings []IRMemoryBinding, step_limit int) !IRVoidRun {
	if !f.ready { return error('AIR prepared memory: uninitialized function') }
	return f.program.execute_memory_function(f.ir, f.stream, f.pools, f.bodies,
		f.function, f.profile, mut bindings, step_limit)!
}
