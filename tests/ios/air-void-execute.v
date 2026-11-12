// SPDX-License-Identifier: GPL-2.0-or-later
module main
import airbitcode
import os

fn index_of(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic('missing fixture') }
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/')
	os.mkdir_all(out)!
	os.write_file(out + '/input.ll', 'define void @empty() { ret void }
define void @branch(i1 %c, i64 %a) {
  %v = add i64 %a, 1
  br i1 %c, label %slow, label %fast
slow:
  %x = add i64 %v, 3
  %y = mul i64 %x, 7
  ret void
fast:
  ret void
}
define void @loop(i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %next, %body ]
  %done = icmp eq i64 %i, 0
  br i1 %done, label %exit, label %body
body:
  %next = sub i64 %i, 1
  br label %loop
exit:
  ret void
}
define void @floats(half %h, float %f) {
  %x = fadd half %h, %h
  %y = fmul float %f, %f
  ret void
}
define void @guard_unreachable() { unreachable }
define void @guard_loop() { br label %again
again:
  br label %again
}
define void @guard_undef() { br i1 undef, label %yes, label %no
yes:
  ret void
no:
  ret void
}
define i32 @scalar() { ret i32 7 }
')!
	mut process := os.new_process(os.args[1]); process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio_merged(); process.run(); log := process.stdout_slurp(); process.wait(); code := process.code; process.close()
	os.write_file(out + '/assemble.log', log)!; assert code == 0
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	mut checks := 0
	for name in ['empty', 'branch', 'loop', 'floats'] {
		function := index_of(ir, name)
		for sample in 0 .. if name == 'empty' { 1 } else if name == 'loop' { 128 } else { 256 } {
			args := match name { 'empty' { []u64{} } 'branch' { [u64(sample % 2), ~u64(sample)] } 'loop' { [u64(sample)] } else { [u64(sample * 257), u64(sample) * 0x01010101] } }
			expected := match name { 'empty' { 1 } 'branch' { if sample % 2 == 0 { 3 } else { 5 } } 'loop' { sample * 5 + 5 } else { 3 } }
			run := p.run_void_function(ir, stream, pools, bodies, function, args, expected)!; assert run.steps == expected
			if expected > 1 { if _ := p.run_void_function(ir, stream, pools, bodies, function, args, expected - 1) { panic('lost step limit') } }
			if _ := p.run_scalar_function(ir, stream, pools, bodies, function, args, 4096) { panic('scalar API accepted void') }
			if _ := p.run_integer_function(ir, stream, pools, bodies, function, args, 4096) { panic('integer API accepted void') }
			unsafe { args.free() }; checks++
		}
	}
	for name in ['guard_unreachable', 'guard_loop', 'guard_undef', 'scalar'] { if _ := p.run_void_function(ir, stream, pools, bodies, index_of(ir, name), [], 64) { panic('accepted guarded fixture') } }
	os.write_file(out + '/result.txt', 'AIR-VOID-EXECUTION: ${checks} serialized LLVM bitcode cases, exact steps and exhausted budgets, branches/PHI loops/half/float arithmetic, scalar API separation and four guarded failures PASS\n')!
	print(os.read_file(out + '/result.txt')!)
}
