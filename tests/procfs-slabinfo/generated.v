// SPDX-License-Identifier: GPL-2.0-or-later
// Check the complete new formatter/sampler scope, not just the procfs wrapper.
module main

import crypto.sha256
import json2
import os

const functions = ['fs__slabinfo_read', 'memory__heap_classes_into',
	'memory__class_snapshot', 'memory__heap_big_pages', 'memory__heap_written_after_free',
	'slabreport__writer', 'slabreport__Writer__byte', 'slabreport__Writer__class',
	'slabreport__Writer__count', 'slabreport__Writer__footer', 'slabreport__Writer__header',
	'slabreport__Writer__text', 'slabreport__Writer__unsigned']

fn body(source string, name string) !string {
	mut offset := 0
	mut found := ''
	for line in source.split_into_lines() {
		if line.contains(name + '(') && line.ends_with(' {') && !line.starts_with('\t') {
			if found != '' { return error('duplicate definition: ' + name) }
			start := offset + line.len - 1
			mut depth := 0
			mut end := start
			for i in start .. source.len {
				if source[i] == `{` { depth++ }
				if source[i] == `}` { depth-- }
				if depth == 0 { end = i + 1; break }
			}
			if end == start { return error('incomplete definition: ' + name) }
			found = source[start..end]
		}
		offset += line.len + 1
	}
	if found == '' { return error('missing definition: ' + name) }
	return found
}

fn verify(source string) !map[string]string {
	mut result := map[string]string{}
	for name in functions {
		text := body(source, name)!
		for forbidden in ['malloc(', 'calloc(', 'realloc(', 'memdup', 'new_array',
			'array__', 'string__', 'lib__new_text', '__str('] {
			if text.contains(forbidden) { return error('allocation-like call in ' + name + ': ' + forbidden) }
		}
		result[name] = sha256.sum(text.bytes()).hex()
	}
	text := body(source, 'fs__slabinfo_read')!
	if text.count('vinix_stack_alloc(') != 2 || !text.contains('memory__heap_classes_into(classes, 18)') {
		return error('explicit borrowed class/writer stack storage missing')
	}
	return result
}

fn run() ! {
	if os.args.len != 2 { return error('usage: generated BLOB.c') }
	source := os.read_file(os.args[1])!
	result := verify(source)!
	mut refused := 0
	for name in functions {
		original := body(source, name)!
		mutated := source.replace_once(original, original.replace_once('{', '{\n malloc(48);'))
		verify(mutated) or { refused++; continue }
		return error('missed allocation in ' + name)
	}
	println(json2.encode({'functions': json2.decode[json2.Any](json2.encode(result))!,
		'blob_sha256': sha256.sum(source.bytes()).hex(), 'allocation_refusals': refused}, prettify: true))
}

fn main() { run() or { eprintln(err); exit(1) } }
