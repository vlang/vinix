// SPDX-License-Identifier: GPL-2.0-or-later
// A pinned declaration boundary, preserving the original scheduler/MM header.
module hosttest

import os
import json2

pub const sched_mm_input_sha256 = 'cc7ea1f53e66d3b62611affc0590464cbb791a30e95e3d6210cd942437c28ea1'

const sched_mm_prefix = '/* V-generated pinned Linux6.6.157 native declaration boundary; unsupported MM runtime stays unresolved. */\n#include <linux/resource.h>\n'
const sched_mm_signatures = {
	'current_gfp_context':        'extern gfp_t current_gfp_context(gfp_t flags);'
	'in_vfork':                   'extern bool in_vfork(struct task_struct *tsk);'
	'memalloc_nofs_restore':      'extern void memalloc_nofs_restore(unsigned int flags);'
	'memalloc_nofs_save':         'extern unsigned int memalloc_nofs_save(void);'
	'memalloc_noio_restore':      'extern void memalloc_noio_restore(unsigned int flags);'
	'memalloc_noio_save':         'extern unsigned int memalloc_noio_save(void);'
	'memalloc_noreclaim_restore': 'extern void memalloc_noreclaim_restore(unsigned int flags);'
	'memalloc_noreclaim_save':    'extern unsigned int memalloc_noreclaim_save(void);'
	'memalloc_pin_restore':       'extern void memalloc_pin_restore(unsigned int flags);'
	'memalloc_pin_save':          'extern unsigned int memalloc_pin_save(void);'
}

pub struct SchedMmDeclarations {
pub:
	header                     string
	signatures                 map[string]string
	original_definition_sha256 map[string]string
	unchanged_segment_sha256   []string
}

struct SchedMmRange {
	start  int
	finish int
	name   string
}

fn sched_mm_body_end(raw string, begin int) !int {
	if begin >= raw.len || raw[begin] != `{` { return error('Expected original inline body') }
	mut depth := 0
	mut quoted := u8(0)
	mut line_comment := false
	mut block_comment := false
	mut index := begin
	for index < raw.len {
		ch := raw[index]
		next := if index + 1 < raw.len { raw[index + 1] } else { u8(0) }
		if line_comment {
			if ch == `\n` { line_comment = false }
			index++
			continue
		}
		if block_comment {
			if ch == `*` && next == `/` {
				block_comment = false
				index += 2
			} else {
				index++
			}
			continue
		}
		if quoted != 0 {
			if ch == `\\` {
				index += 2
				continue
			}
			if ch == quoted { quoted = 0 }
			index++
			continue
		}
		if ch == `/` && next == `/` {
			line_comment = true
			index += 2
			continue
		}
		if ch == `/` && next == `*` {
			block_comment = true
			index += 2
			continue
		}
		if ch == `"` || ch == `'` {
			quoted = ch
			index++
			continue
		}
		if ch == `{` { depth++ }
		if ch == `}` {
			depth--
			if depth == 0 { return index + 1 }
		}
		index++
	}
	return error('Unterminated original inline body')
}

// This pure operation accepts only the pinned upstream bytes. Every byte outside
// the ten selected definitions, including all conditional directives and other
// inline definitions, is copied directly from that input.
pub fn sched_mm_declarations(original string) !SchedMmDeclarations {
	if text_sha(original) != sched_mm_input_sha256 {
		return error('Unsupported upstream sched/mm.h: original source SHA256 mismatch')
	}
	mut ranges := []SchedMmRange{}
	for name, declaration in sched_mm_signatures {
		original_signature := declaration.trim_right(';').replace('extern ', 'static inline ')
		needle := '\n' + original_signature + '\n{'
		if original.count(needle) != 1 {
			return error('Changed or duplicate original signature ' + name)
		}
		start := original.index(needle) or { return error('Missing original signature ' + name) }
		body := start + needle.len - 1
		finish := sched_mm_body_end(original, body)!
		ranges << SchedMmRange{ start: start + 1, finish: finish, name: name }
	}
	ranges.sort(a.start < b.start)
	mut header := sched_mm_prefix
	mut definitions := map[string]string{}
	mut untouched := []string{}
	mut cursor := 0
	for part in ranges {
		if part.start < cursor { return error('Overlapping original inline definitions') }
		segment := original[cursor..part.start]
		header += segment + sched_mm_signatures[part.name]
		untouched << text_sha(segment)
		definitions[part.name] = text_sha(original[part.start..part.finish])
		cursor = part.finish
	}
	header += original[cursor..]
	untouched << text_sha(original[cursor..])
	return SchedMmDeclarations{
		header:                     header
		signatures:                 sched_mm_signatures.clone()
		original_definition_sha256: definitions
		unchanged_segment_sha256:   untouched
	}
}

// Returns provenance and publishes only after all validation has succeeded.
// CONFIG_BASE_FULL=1 and CONFIG_BASE_SMALL=0 are the supported native profile;
// neither configuration changes nor MM implementations are emitted here.
pub fn generate_sched_mm(original_arg string, output_arg string) !map[string]json2.Any {
	original_path := resolve_path(original_arg)!
	output := resolve_path(output_arg)!
	protected := [original_path, resolve_path(@FILE)!,
		resolve_path(os.join_path(root(), 'tests/linuxkpi/generate_sched_mm.v'))!]
	if output in protected { return error('sched/mm.h output overlaps a generator input') }
	mut import_roots := [resolve_path(upstream_default())!]
	if original_path.ends_with('/include/linux/sched/mm.h') {
		import_roots << original_path.trim_string_right('/include/linux/sched/mm.h')
	}
	if import_roots.any(inside_import(output, it)) {
		return error('sched/mm.h output must be outside the original import')
	}
	if os.is_dir(output) { return error('sched/mm.h output is a directory') }
	before := bounds_file_state(original_path)!
	if os.exists(output) {
		destination := bounds_file_state(output)!
		if before['st_dev']! == destination['st_dev']! && before['st_ino']! == destination['st_ino']! {
			return error('sched/mm.h output aliases the original input')
		}
	}
	original := os.read_file(original_path)!
	generated := sched_mm_declarations(original)!
	mut tool_hashes := map[string]string{}
	for path in protected[1..] { if os.exists(path) { tool_hashes[path] = sha(path)! } }
	provenance := {
		'scope':                      json2.Any('Pinned Linux6.6.157 exact10 declaration boundary; original records and every other byte/directive preserved; unsupported MM services remain unresolved')
		'original_path':              original_path
		'original_sha256':            sched_mm_input_sha256
		'output_path':                output
		'output_sha256':              text_sha(generated.header)
		'replaced_signatures':        string_map(generated.signatures)
		'original_definition_sha256': string_map(generated.original_definition_sha256)
		'unchanged_segment_sha256':   strings(generated.unchanged_segment_sha256)
		'generator_sha256':           string_map(tool_hashes)
		'required_configuration':     json2.Any({
			'CONFIG_BASE_FULL':  json2.Any(1)
			'CONFIG_BASE_SMALL': 0
		})
	}
	if bounds_file_state(original_path)! != before || sha(original_path)! != sched_mm_input_sha256 {
		return error('Original sched/mm.h changed during generation')
	}
	bounds_publish(output, generated.header.bytes())!
	return provenance
}
