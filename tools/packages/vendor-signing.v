// SPDX-License-Identifier: GPL-2.0-or-later
// Reproduce the package service's MIT-licensed V signing dependency.
module main

import crypto.sha256
import json2
import os

const signing_source_revision = '826e96f56ca12fcb8fd02dfd6edf1551008e62a8'
const signing_source_files = ['LICENSE', 'ed25519.v', 'internal/edwards25519/edwards25519.v',
	'internal/edwards25519/element.v', 'internal/edwards25519/extra.v',
	'internal/edwards25519/point.v', 'internal/edwards25519/scalar.v',
	'internal/edwards25519/scalarmult.v', 'internal/edwards25519/table.v']

struct SigningSource {
	path string
	blob string
	upstream_sha256 string
	result_sha256 string
}

struct SigningProvenance {
	format int = 1
	revision string
	license string = 'MIT'
	adaptations []string
	files []SigningSource
}

fn signing_git(checkout string, arguments []string) !string {
	mut process := os.new_process('git')
	process.set_args(['-C', checkout, ...arguments])
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error(output) }
	return output
}

fn signing_replace(source string, original string, replacement string, count int) !string {
	if source.count(original) != count { return error('unexpected signing ownership source layout') }
	return source.replace(original, replacement)
}

fn signing_adapt(path string, source string) !string {
	mut result := source.replace('import crypto.ed25519.internal.edwards25519',
		'import tools.packages.signing.internal.edwards25519')
	if path == 'ed25519.v' {
		if !result.starts_with('module ed25519\n') { return error('unexpected signing module declaration') }
		result = result.replace_once('module ed25519\n', 'module signing\n')
		helper := 'fn signing_hash512(first []u8, second []u8, third []u8) []u8 {\n\tmut digest := sha512.new()\n\tdefer { unsafe { digest.free(); free(digest) } }\n\tdigest.write(first) or { panic(err) }\n\tdigest.write(second) or { panic(err) }\n\tdigest.write(third) or { panic(err) }\n\tmut out := []u8{len: sha512.size}\n\tdigest.checksum_into(mut out)\n\treturn out\n}\n\n'
		result = signing_replace(result, '// public_key_size is the sizeof public keys in bytes', helper + '// public_key_size is the sizeof public keys in bytes', 1)!
		result = signing_replace(result, 'mut h := sha512.sum512(seed)',
			'mut h := signing_hash512(seed, [], [])\n\tdefer { unsafe { h.free() } }', 2)!
		for name, count in {'s': 2, 'r': 1, 'k': 2, 'ss': 2} {
			result = signing_replace(result, 'mut ${name} := edwards25519.new_scalar()',
				'mut ${name} := edwards25519.new_scalar_owned()\n\tdefer { unsafe { free(${name}) } }', count)!
		}
		msg_start := '\tmut mh := sha512.new()'
		msg_end := '\tmut r := edwards25519.new_scalar_owned()'
		if result.count(msg_start) != 1 || result.count(msg_end) != 1 { return error('unexpected signing nonce hash layout') }
		result = result.all_before(msg_start) + '\tmsg_digest := signing_hash512(prefix, message, [])\n\tdefer { unsafe { msg_digest.free() } }\n\n' + msg_end + result.all_after(msg_end)
		original := '\tmut kh := sha512.new()\n\tkh.write(rr.bytes())!\n\tkh.write(publickey)!\n\tkh.write(message)!\n\n\tmut hram_digest := []u8{cap: sha512.size}\n\thram_digest = kh.sum(hram_digest)'
		result = signing_replace(result, original, '\tencoded_r := rr.bytes()\n\tdefer { unsafe { encoded_r.free() } }\n\thram_digest := signing_hash512(encoded_r, publickey, message)\n\tdefer { unsafe { hram_digest.free() } }', 1)!
		original_verify := '\tmut kh := sha512.new()\n\tkh.write(sig[..32])!\n\tkh.write(publickey)!\n\tkh.write(message)!\n\n\tmut hram_digest := []u8{cap: sha512.size}\n\thram_digest = kh.sum(hram_digest)'
		result = signing_replace(result, original_verify, '\thram_digest := signing_hash512(sig[..32], publickey, message)\n\tdefer { unsafe { hram_digest.free() } }', 1)!
		result = signing_replace(result, 'copy(mut signature[..32], rr.bytes())\n\tcopy(mut signature[32..], ss.bytes())',
			'encoded_s := ss.bytes()\n\tdefer { unsafe { encoded_s.free() } }\n\tcopy(mut signature[..32], encoded_r)\n\tcopy(mut signature[32..], encoded_s)', 1)!
		result = signing_replace(result, 'return subtle.constant_time_compare(sig[..32], rr.bytes()) == 1',
			'encoded_r := rr.bytes()\n\tdefer { unsafe { encoded_r.free() } }\n\treturn subtle.constant_time_compare(sig[..32], encoded_r) == 1', 1)!
		result = signing_replace(result, 'mut publickey := aa.bytes()', 'mut publickey := aa.bytes()\n\tdefer { unsafe { publickey.free() } }', 1)!
		result = signing_replace(result, 'mut seed := rand.bytes(seed_size)!', 'mut seed := rand.bytes(seed_size)!\n\tdefer { unsafe { seed.free() } }', 1)!
		result = signing_replace(result, 'sign_generic(mut signature, privatekey, message)!',
			'sign_generic(mut signature, privatekey, message) or { unsafe { signature.free() }; return err }', 1)!
	}
	if path == 'internal/edwards25519/point.v' {
		original := 'fn check_initialized(points ...Point) {\n\tfor _, p in points {\n\t\tif p.x == fe_zero && p.y == fe_zero {\n\t\t\tpanic(\'edwards25519: use of uninitialized Point\')\n\t\t}\n\t}\n}'
		replacement := 'fn check_initialized(p Point) {\n\tif p.x == fe_zero && p.y == fe_zero {\n\t\tpanic(\'edwards25519: use of uninitialized Point\')\n\t}\n}'
		if result.count(original) != 1 || result.count('check_initialized(p, q)') != 2
			|| result.count('check_initialized(v, u)') != 1 {
			return error('unexpected point-initialization source layout')
		}
		result = result.replace_once(original, replacement)
		result = result.replace('check_initialized(p, q)', 'check_initialized(p)\n\tcheck_initialized(q)')
		result = result.replace_once('check_initialized(v, u)', 'check_initialized(v)\n\tcheck_initialized(u)')
		result = signing_replace(result, 'qcached := pc.from_p3(q)', 'pc.from_p3(q)', 2)!
		result = signing_replace(result, 'result := p1.add(p, qcached)\n\treturn v.from_p1(result)',
			'p1.add(p, pc)\n\treturn v.from_p1(p1)', 1)!
		result = signing_replace(result, 'result := p1.sub(p, qcached)\n\treturn v.from_p1(result)',
			'p1.sub(p, pc)\n\treturn v.from_p1(p1)', 1)!
		result = signing_replace(result, 'mut p := Point{}\n\treturn p.set(id_point)', 'return id_point', 1)!
		result = signing_replace(result, 'mut p := Point{}\n\treturn p.set(gen_point)', 'return gen_point', 1)!
		start := 'pub fn (mut v Point) bytes() []u8 {'
		end := '// Conversions.'
		if result.count(start) != 1 || result.count(end) != 1 { return error('unexpected point encoding layout') }
		encoding := 'pub fn (mut v Point) bytes() []u8 {\n\tcheck_initialized(v)\n\tmut zinv := Element{}\n\tmut x := Element{}\n\tmut y := Element{}\n\tzinv.invert(v.z)\n\tx.multiply(v.x, zinv)\n\ty.multiply(v.y, zinv)\n\tmut out := []u8{len: 32}\n\ty.encode_into(mut out)\n\tout[31] |= u8(x.is_negative() * 128)\n\treturn out\n}\n\n'
		result = result.all_before(start) + encoding + end + result.all_after(end)
	}
	if path == 'internal/edwards25519/extra.v' {
		if result.count('check_initialized(...points)') != 2 { return error('unexpected multiscalar source layout') }
		result = result.replace('check_initialized(...points)', 'for point in points { check_initialized(point) }')
		outlined := '\t// This function is outlined to make the allocations inline in the caller\n\t// rather than happen on the heap.\n\tmut buf := [32]u8{}\n\treturn v.bytes_montgomery_generic(mut buf)\n}\n\nfn (mut v Point) bytes_montgomery_generic(mut buf [32]u8) []u8 {\n'
		result = signing_replace(result, outlined, '', 1)!
		result = signing_replace(result, 'return copy_field_element(mut buf, mut u)',
			'mut out := []u8{len: 32}\n\tu.encode_into(mut out)\n\treturn out', 1)!
	}
	if path == 'internal/edwards25519/element.v' {
		original := '\tv = v.carry_propagate_generic()\n\treturn v'
		if result.count(original) != 2 { return error('unexpected field carry source layout') }
		// The method already updates v. Assigning its result back to v makes
		// the qualified compiler heap-promote this temporary on every field
		// multiply/square. Keep the same carry and return the updated value.
		result = result.replace(original, '\tv.carry_propagate_generic()\n\treturn v')
		result = signing_replace(result, 'return int(v.bytes()[0] & 1)',
			'encoded := v.bytes()\n\tdefer { unsafe { encoded.free() } }\n\treturn int(encoded[0] & 1)', 1)!
		result = signing_replace(result, 'return v.selected(e.negate(uk), uk, uk.is_negative())',
			'e.negate(uk)\n\treturn v.selected(e, uk, uk.is_negative())', 1)!
		result = signing_replace(result, 'mut buf := []u8{len: 8}', 'mut buf := []u8{len: 8}\n\tdefer { unsafe { buf.free() } }', 1)!
		result = signing_replace(result, 'idxs := [v.l0, v.l1, v.l2, v.l3, v.l4]',
			'idxs := [v.l0, v.l1, v.l2, v.l3, v.l4]!', 1)!
		result = signing_replace(result, 'sv := left.bytes()\n\treturn subtle.constant_time_compare(sa, sv)',
			'sv := left.bytes()\n\tdefer { unsafe { sa.free(); sv.free() } }\n\treturn subtle.constant_time_compare(sa, sv)', 1)!
		start := 'fn (mut v Element) bytes_generic() []u8 {'
		end := '// equal returns 1'
		if result.count(start) != 1 || result.count(end) != 1 { return error('unexpected field encoding layout') }
		mut body := result.all_after(start).all_before(end)
		body = signing_replace(body, '\n\tmut out := []u8{len: 32}\n', '', 1)!
		body = signing_replace(body, '\treturn out\n', '', 1)!
		wrapper := start + '\n\tmut out := []u8{len: 32}\n\tv.encode_into(mut out)\n\treturn out\n}\n\n// out is owned by the caller and does not borrow the receiver.\nfn (mut v Element) encode_into(mut out []u8) {'
		result = result.all_before(start) + wrapper + body + end + result.all_after(end)
	}
	if path == 'internal/edwards25519/scalar.v' {
		result = signing_replace(result, 'pub fn new_scalar() Scalar {\n\treturn Scalar{}\n}',
			'pub fn new_scalar() Scalar {\n\treturn Scalar{}\n}\n\n// The package signing entry points own and retire this box.\npub fn new_scalar_owned() &Scalar {\n\treturn &Scalar{}\n}', 1)!
		for declaration in ['mut wide_bytes := []u8{len: 64}', 'mut wide_bytes := []u8{len: 64, cap: 64}'] {
			result = signing_replace(result, declaration, declaration + '\n\tdefer { unsafe { wide_bytes.free() } }', 1)!
		}
		result = signing_replace(result, 'copy(mut ss.s, x)', 'for i in 0 .. 32 { ss.s[i] = x[i] }', 1)!
		result = signing_replace(result, 'copy(mut buf, s.s[..])', 'for i in 0 .. 32 { buf[i] = s.s[i] }', 1)!
		result = signing_replace(result, 'return subtle.constant_time_compare(s.s[..], t.s[..])',
			'mut left := []u8{len: 32}\n\tmut right := []u8{len: 32}\n\tfor i in 0 .. 32 { left[i] = s.s[i]; right[i] = t.s[i] }\n\tdefer { unsafe { left.free(); right.free() } }\n\treturn subtle.constant_time_compare(left, right)', 1)!
		start := 'fn sc_mul_add(mut s [32]u8, a [32]u8, b [32]u8, c [32]u8) {'
		end := '// Input:\n//   s[0]+256*s[1]'
		if result.count(start) != 1 || result.count(end) != 1 { return error('unexpected scalar multiplication layout') }
		mut body := result.all_after(start).all_before(end)
		for name in ['a', 'b', 'c'] { body = body.replace('load3(${name}[', 'load3(${name}_bytes[').replace('load4(${name}[', 'load4(${name}_bytes[') }
		owned := '\n\tmut a_bytes := []u8{len: 32}\n\tmut b_bytes := []u8{len: 32}\n\tmut c_bytes := []u8{len: 32}\n\tfor i in 0 .. 32 { a_bytes[i] = a[i]; b_bytes[i] = b[i]; c_bytes[i] = c[i] }\n\tdefer { unsafe { a_bytes.free(); b_bytes.free(); c_bytes.free() } }'
		result = result.all_before(start) + start + owned + body + end + result.all_after(end)
		result = signing_replace(result, 'mut digits := [5]u64{}', 'mut digits := [5]u64{}\n\tencoded := s.bytes()\n\tdefer { unsafe { encoded.free() } }', 1)!
		result = signing_replace(result, 'binary.little_endian_u64(s.s[i * 8..])', 'binary.little_endian_u64(encoded[i * 8..])', 1)!
	}
	if path == 'internal/edwards25519/scalarmult.v' {
		// Upstream's Once belongs to a new wrapper on every call, so it never
		// shares a table. Retain that construction order with explicit ownership.
		marker := '// scalar_base_mult sets v = x * B'
		if result.count(marker) != 1 || !result.starts_with('module edwards25519\n\nimport sync\n') {
			return error('unexpected signing basepoint source layout')
		}
		prefix := 'module edwards25519\n\n// This table belongs to the scalar multiplication that requested it.\nfn basepoint_table() []AffineLookupTable {\n\tmut table := []AffineLookupTable{len: 32}\n\tmut p := new_generator_point()\n\tfor i := 0; i < 32; i++ {\n\t\ttable[i].from_p3(p)\n\t\tfor j := 0; j < 8; j++ {\n\t\t\tp.add(p, p)\n\t\t}\n\t}\n\treturn table\n}\n\n'
		result = prefix + marker + result.all_after(marker)
		naf_start := 'struct BasepointNaftablePrecomp {'
		naf_end := '// vartime_double_scalar_base_mult sets v = a * A'
		if result.count(naf_start) != 1 || result.count(naf_end) != 1 { return error('unexpected signing NAF source layout') }
		result = result.all_before(naf_start) + 'fn basepoint_naf_table(mut table NafLookupTable8) {\n\ttable.from_p3(new_generator_point())\n}\n\n' + naf_end + result.all_after(naf_end)
		result = signing_replace(result, 'mut bp_naftable := basepoint_naf_table()',
			'mut bp_naftable := &NafLookupTable8{}\n\tdefer { unsafe { free(bp_naftable) } }\n\tbasepoint_naf_table(mut bp_naftable)', 1)!
		result = signing_replace(result, 'mut atable := NafLookupTable5{}',
			'mut atable := &NafLookupTable5{}\n\tdefer { unsafe { free(atable) } }', 1)!
		result = signing_replace(result, 'mut bpt_table := basepoint_table()',
			'mut bpt_table := basepoint_table()\n\tdefer { unsafe { bpt_table.free() } }', 1)!
		result = signing_replace(result, 'digits := x.signed_radix16()',
			'digits := x.signed_radix16()\n\tdefer { unsafe { digits.free() } }', 2)!
		result = signing_replace(result, 'bnaf := b.non_adjacent_form(8)',
			'bnaf := b.non_adjacent_form(8)\n\tdefer { unsafe { anaf.free(); bnaf.free() } }', 1)!
		result = signing_replace(result, 'mut a := xa\n\tmut b := xb',
			'mut a := new_scalar_owned()\n\tmut b := new_scalar_owned()\n\tdefer { unsafe { free(a); free(b) } }\n\ta.set(xa)\n\tb.set(xb)', 1)!
	}
	return result
}

fn signing_check_tree(directory string, prefix string) ! {
	if os.is_link(directory) || !os.is_dir(directory) { return error('signing source must be an ordinary directory') }
	for name in os.ls(directory)! {
		path := directory + '/' + name
		relative := if prefix == '' { name } else { prefix + '/' + name }
		if os.is_link(path) { return error('signing source contains a symlink: ${relative}') }
		if os.is_dir(path) { signing_check_tree(path, relative)!; continue }
		if !os.is_file(path) { return error('signing source contains a special file: ${relative}') }
		upstream := if relative == 'signing.v' { 'ed25519.v' } else { relative }
		if relative.ends_with('.v') && !relative.ends_with('_test.v') && upstream !in signing_source_files {
			return error('unrecorded signing implementation source: ${relative}')
		}
	}
}

fn synchronize_signing() ! {
	if os.args.len != 3 || os.args[1] !in ['--write', '--check'] {
		return error('usage: vendor-signing --write|--check V_GIT_CHECKOUT')
	}
	checkout := os.abs_path(os.args[2])
	if signing_git(checkout, ['rev-parse', signing_source_revision + '^{commit}'])!.trim_space() != signing_source_revision {
		return error('the pinned V standard-library commit is unavailable')
	}
	repository := os.dir(os.dir(os.dir(@FILE)))
	destination := repository + '/tools/packages/signing'
	if os.exists(destination) { signing_check_tree(destination, '')! }
	mut records := []SigningSource{}
	for path in signing_source_files {
		input := 'vlib/crypto/ed25519/' + path
		object := signing_source_revision + ':' + input
		original := signing_git(checkout, ['show', object])!
		adapted := signing_adapt(path, original)!
		output := if path == 'ed25519.v' { 'signing.v' } else { path }
		target := destination + '/' + output
		if os.args[1] == '--write' {
			os.mkdir_all(os.dir(target))!
			os.write_file(target, adapted)!
		} else if os.read_file(target)! != adapted {
			return error('vendored signing source differs from its pinned adaptation: ${output}')
		}
		records << SigningSource{ path: output, blob: signing_git(checkout, ['rev-parse', object])!.trim_space(),
			upstream_sha256: sha256.sum(original.bytes()).hex(), result_sha256: sha256.sum(adapted.bytes()).hex() }
	}
	provenance := json2.encode(SigningProvenance{ revision: signing_source_revision,
		adaptations: ['package-local module namespace', 'non-variadic point-initialization checks; arithmetic and encoding retained',
			'field multiplication/squaring discard redundant carry-result assignment; receiver mutation and returned limbs retained',
			'per-operation lookup table and digit ownership; point addition/subtraction use updated stack receivers',
			'owned SHA-512 state/output, scalar boxes/conversions and point encodings; hash inputs, arithmetic and signature bytes retained'],
		files: records }) + '\n'
	if os.args[1] == '--write' {
		os.write_file(destination + '/provenance.json', provenance)!
	} else if os.read_file(destination + '/provenance.json')! != provenance {
		return error('vendored signing provenance differs from the pinned source')
	}
	println('Package signing source ' + os.args[1] + ' passed')
}

fn main() {
	synchronize_signing() or { eprintln(err); exit(1) }
}
