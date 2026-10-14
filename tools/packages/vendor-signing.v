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
	}
	if path == 'internal/edwards25519/extra.v' {
		if result.count('check_initialized(...points)') != 2 { return error('unexpected multiscalar source layout') }
		result = result.replace('check_initialized(...points)', 'for point in points { check_initialized(point) }')
	}
	if path == 'internal/edwards25519/element.v' {
		original := '\tv = v.carry_propagate_generic()\n\treturn v'
		if result.count(original) != 2 { return error('unexpected field carry source layout') }
		// The method already updates v. Assigning its result back to v makes
		// the qualified compiler heap-promote this temporary on every field
		// multiply/square. Keep the same carry and return the updated value.
		result = result.replace(original, '\tv.carry_propagate_generic()\n\treturn v')
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
			'per-operation lookup table and digit ownership; point addition/subtraction use updated stack receivers'],
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
