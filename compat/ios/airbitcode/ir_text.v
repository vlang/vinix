// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct IRPrinter {
	ir IRModule
mut:
	bytes []u8
	visits int
}

fn (mut p IRPrinter) write(text string) ! {
	if text.len > 65536 - p.bytes.len { return error('AIR IR: rendered type byte limit') }
	for i in 0 .. text.len { p.bytes << text[i] }
}
fn (mut p IRPrinter) number(value u64) ! {
	text := value.str()
	defer { unsafe { text.free() } }
	p.write(text)!
}
fn (mut p IRPrinter) name(text string) ! {
	p.write('%"')!
	for i in 0 .. text.len {
		byte := text[i]
		if byte >= 32 && byte <= 126 && byte !in [u8(`"`), `\\`]! {
			if p.bytes.len >= 65536 { return error('AIR IR: rendered type byte limit') }
			p.bytes << byte
		} else {
			hex := '0123456789ABCDEF'
			if p.bytes.len > 65536 - 3 { return error('AIR IR: rendered type byte limit') }
			p.bytes << u8(`\\`)
			p.bytes << hex[int(byte >> 4)]
			p.bytes << hex[int(byte & 15)]
		}
	}
	p.write('"')!
}
fn (mut p IRPrinter) typ(index int, depth int) ! {
	if depth > 64 || p.visits >= 65536 { return error('AIR IR: rendered type work/depth limit') }
	if index < 0 || index >= p.ir.types.len { return error('AIR IR: rendered type index') }
	p.visits++
	typ := p.ir.types[index]
	refs := unsafe { p.ir.references[typ.refs_start..typ.refs_start + typ.refs_count] }
	if typ.name.len != 0 { p.name(typ.name)!; return }
	match typ.kind {
		.integer_t { p.write('i')!; p.number(typ.bits)! }
		.pointer_t {
			p.write('ptr')!
			if typ.address_space != 0 { p.write(' addrspace(')!; p.number(typ.address_space)!; p.write(')')! }
		}
		.array_t, .vector_t {
			p.write(if typ.kind == .array_t { '[' } else { '<' })!
			if typ.scalable { p.write('vscale x ')! }
			p.number(typ.count)!; p.write(' x ')!; p.typ(refs[0], depth + 1)!
			p.write(if typ.kind == .array_t { ']' } else { '>' })!
		}
		.struct_t {
			p.write(if typ.packed { '<{ ' } else { '{ ' })!
			for i, ref in refs { if i != 0 { p.write(', ')! }; p.typ(ref, depth + 1)! }
			p.write(if typ.packed { ' }>' } else { ' }' })!
		}
		.function_t {
			p.typ(refs[0], depth + 1)!; p.write(' (')!
			for i in 1 .. refs.len { if i > 1 { p.write(', ')! }; p.typ(refs[i], depth + 1)! }
			if typ.vararg { if refs.len > 1 { p.write(', ')! }; p.write('...')! }
			p.write(')')!
		}
		else {
			text := match typ.kind {
				.void_t { 'void' } .float_t { 'float' } .double_t { 'double' }
				.half_t { 'half' } .bfloat_t { 'bfloat' } .label_t { 'label' }
				.x86_fp80_t { 'x86_fp80' } .fp128_t { 'fp128' } .ppc_fp128_t { 'ppc_fp128' }
				.metadata_t { 'metadata' } .token_t { 'token' } .x86_mmx_t { 'x86_mmx' }
				.x86_amx_t { 'x86_amx' } else { return error('AIR IR: unnamed opaque type') }
			}
			p.write(text)!
		}
	}
}

// Bounded LLVM text for inspection. Pointers use LLVM's opaque-pointer spelling;
// the underlying type index retains original AIR pointee references separately.
pub fn (ir IRModule) type_text(index int) !string {
	mut p := IRPrinter{ir: ir}
	p.bytes.flags |= .noslices
	defer { unsafe { p.bytes.free() } }
	p.typ(index, 0)!
	return p.bytes.bytestr()
}
