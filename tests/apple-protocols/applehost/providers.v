// SPDX-License-Identifier: GPL-2.0-only
module applehost

import crypto.sha256
import fixturehost
import hosttest
import json2
import os

pub struct ProviderError {
pub:
	kind    string
	message string
}

pub fn (e ProviderError) msg() string { return e.message }

pub fn (e ProviderError) code() int { return 0 }

const ans_hardware = ['a_kernel_read32', 'a_kernel_read64', 'a_kernel_write32', 'a_kernel_write64',
	'a_kernel_now', 'a_kernel_delay', 'a_kernel_sync', 'vinix_ans_init']
const spi_hardware = ['kernel_read32', 'kernel_write32', 'kernel_now_us', 'kernel_delay_us',
	'vinix_apple_spi_keyboard_init']
const speaker_hardware = ['kernel_read32', 'kernel_write32', 'kernel_now_us', 'kernel_delay_us',
	'kernel_clean', 'kernel_invalidate', 'kernel_power', 'vinix_apple_speakers_init']

fn source_text(path string) !string {
	raw := fixturehost.read(path)!
	hosttest.module_decode_utf8(raw)!
	return raw.replace('\r\n', '\n').replace('\r', '\n')
}

fn source_lines(text string) []string {
	mut lines := []string{}
	mut current := ''
	mut skip_lf := false
	for ch in text.runes() {
		if skip_lf && ch == `\n` {
			skip_lf = false
			continue
		}
		skip_lf = false
		if ch in [`\n`, `\r`, rune(11), rune(12), rune(28), rune(29), rune(30), rune(133),
			rune(0x2028), rune(0x2029)] {
			lines << current
			current = ''
			skip_lf = ch == `\r`
		} else {
			current += ch.str()
		}
	}
	if current != '' { lines << current }
	return lines
}

fn word_hits(text string, name string) []int {
	mut hits := []int{}
	mut start := 0
	for start < text.len {
		index := start + (text[start..].index(name) or { break })
		end := index + name.len
		left := text[..index].runes()
		right := text[end..].runes()
		if (left.len == 0 || !hosttest.module_word_rune(left.last())) && (right.len == 0 || !hosttest.module_word_rune(right[0])) {
			hits << index
		}
		start = end
	}
	return hits
}

fn line_number(text string, end int) int { return text[..end].count('\n') + 1 }

fn comment_line(text string) bool {
	mut remaining := text
	for ch in text.runes() {
		space := ch in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, rune(0x85), rune(0xa0), rune(0x1680),
			rune(0x2028), rune(0x2029), rune(0x202f), rune(0x205f), rune(0x3000)] || (ch >= 0x1c && ch <= 0x1f) || (ch >= 0x2000 && ch <= 0x200a)
		if !space { break }
		remaining = remaining[ch.str().len..]
	}
	return remaining.starts_with('//')
}

struct Definition {
	first       int
	last        int
	export_name string
}

fn definition(text string, name string, exact bool) !Definition {
	mut start := 0
	for start < text.len {
		index := start + (text[start..].index("@[export: '") or { break })
		start = index + 1
		if index > 0 && text[index - 1] != `\n` { continue }
		after := index + "@[export: '".len
		closing := after + (text[after..].index("']\npub fn " + name + '(') or { continue })
		export_name := text[after..closing]
		if export_name.len == 0 || export_name.contains("'") || exact && export_name != name {
			continue
		}
		match_end := closing + ("']\npub fn " + name + '(').len
		begin := match_end + (text[match_end..].index('{') or { return ProviderError{'ValueError', 'substring not found'} })
		mut depth := 1
		mut end := begin + 1
		for depth > 0 {
			if end >= text.len { return ProviderError{'IndexError', 'string index out of range'} }
			if text[end] == `{` { depth++ }
			if text[end] == `}` { depth-- }
			end++
		}
		if end < text.len && text[end] == `\n` { end++ }
		return Definition{index, end, export_name}
	}
	return ProviderError{'RuntimeError', 'hardware definition changed: ' + name}
}

fn strip_comments(text string) string {
	mut result := ''
	for line in text.split('\n') { result += line.all_before('//') + '\n' }
	return result
}

struct Omission {
	span Definition
	name string
}

fn remove_hardware(original string, names []string, family string) !(string, []json2.Any, []string) {
	mut spans := []Omission{}
	mut omitted := []json2.Any{}
	lines := source_lines(original)
	for name in names {
		span := definition(original, name, family == 'ans')!
		spans << Omission{span, name}
		mut row := map[string]json2.Any{}
		row['name'] = name
		if family != 'ans' { row['export'] = span.export_name }
		row['first_line'] = line_number(original, span.first)
		row['last_line'] = original[..span.last].count('\n')
		row['sha256'] = sha256.hexhash(original[span.first..span.last])
		if family == 'ans' {
			row['reason'] = 'injected fixture installs its own callbacks and invokes a_start directly'
		} else {
			mut references := []json2.Any{}
			for hit in word_hits(original, name) {
				if hit >= span.first && hit < span.last { continue }
				line := original[..hit].count('\n')
				if line >= lines.len {
					return ProviderError{'IndexError', 'list index out of range'}
				}
				references << json2.Any({
					'line': json2.Any(line + 1)
					'text': json2.Any(lines[line])
					'kind': json2.Any(if comment_line(lines[line]) {
						'comment'
					} else {
						'code'
					})
				})
			}
			row['original_references'] = references
			row['reason'] = if family == 'spi' {
				'fixture installs exported injected callbacks and invokes vinix_spi_core_start_keyboard directly'
			} else {
				'fixture installs exported injected callbacks and invokes vinix_spk_core_c_init directly'
			}
		}
		omitted << json2.Any(row)
	}
	spans.sort(a.span.first < b.span.first)
	mut parts := []string{}
	mut cursor := 0
	for item in spans {
		parts << if cursor < item.span.first { original[cursor..item.span.first] } else { '' }
		cursor = item.span.last
	}
	parts << original[cursor..]
	copied := parts.join('')
	checked := if family == 'ans' { copied } else { strip_comments(copied) }
	for name in names {
		if word_hits(checked, name).len > 0 {
			return ProviderError{'RuntimeError', 'retained reference to omitted hardware function: ' + name}
		}
	}
	return copied, omitted, parts
}

fn mkdir(path string, allow bool) ! {
	if path.contains('\x00') { return ProviderError{'ValueError', 'embedded null byte'} }
	os.mkdir(path) or {
		if allow && os.is_dir(path) { return }
		if err.code() == C.ENOENT {
			parent := path.trim_right('/').all_before_last('/')
			if parent != '' && parent != path {
				mkdir(parent, true)!
				os.mkdir(path) or { return fixturehost.FileError{path, err.code(), os.get_error_msg(err.code())} }
				return
			}
		}
		return fixturehost.FileError{path, err.code(), os.get_error_msg(err.code())}
	}
}

fn append_path(parent string, name string) string {
	return if parent == '.' { name } else { parent.trim_right('/') + '/' + name }
}

pub fn copy_provider(root string, destination string, family string, ans bool, hardware bool) !map[string]json2.Any {
	mkdir(destination, false)!
	if family == 'ans' {
		ext2_path := append_path(root, 'kernel/apple/ans/ext2core/core.v')
		mut ext2 := fixturehost.read(ext2_path)!
		mut receipt := {
			'ext2_source':        json2.Any('kernel/apple/ans/ext2core/core.v')
			'ext2_sha256':        json2.Any(sha256.hexhash(ext2))
			'ans':                json2.Any(ans)
			'hardware':           json2.Any(hardware)
			'excluded_functions': json2.Any([]json2.Any{})
		}
		if ans {
			path := append_path(root, 'kernel/apple/ans/anscore/core.v')
			original := source_text(path)!
			copied, excluded, parts := if hardware {
				original, []json2.Any{}, [original]
			} else {
				remove_hardware(original, ans_hardware, family)!
			}
			mkdir(append_path(destination, 'anscore'), false)!
			fixturehost.write(append_path(destination, 'anscore/core.v'), copied)!
			receipt['excluded_functions'] = excluded
			receipt['ans_source'] = 'kernel/apple/ans/anscore/core.v'
			receipt['ans_source_sha256'] = sha256.hexhash(original)
			receipt['ans_copied_sha256'] = sha256.hexhash(copied)
			receipt['retained_chunks_sha256'] = parts.map(json2.Any(sha256.hexhash(it)))
			receipt['transform'] = 'remove only listed whole definitions; all retained text is byte-identical'
			ext2 = ext2.replace_once('module ext2core', 'module ext2core\nimport ext2core.anscore as _')
		}
		fixturehost.write(append_path(destination, 'core.v'), ext2)!
		return receipt
	}
	path := if family == 'spi' {
		'kernel/apple/spi_keyboard/spicore/core.v'
	} else {
		'kernel/apple/speakers/spkcore/core.v'
	}
	original := source_text(append_path(root, path))!
	copied, omitted, parts := if hardware {
		original, []json2.Any{}, [original]
	} else {
		remove_hardware(original, if family == 'spi' { spi_hardware } else { speaker_hardware }, family)!
	}
	fixturehost.write(append_path(destination, 'core.v'), copied)!
	return {
		'source':                 json2.Any(path)
		'source_sha256':          json2.Any(sha256.hexhash(original))
		'copied_sha256':          json2.Any(sha256.hexhash(copied))
		'hardware':               json2.Any(hardware)
		'excluded_functions':     json2.Any(omitted)
		'retained_chunks_sha256': json2.Any(parts.map(json2.Any(sha256.hexhash(it))))
		'transform':              json2.Any('remove only listed whole definitions; every retained byte is unchanged')
	}
}
