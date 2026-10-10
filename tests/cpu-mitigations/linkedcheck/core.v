// SPDX-License-Identifier: GPL-2.0-or-later
module linkedcheck

import fixturehost
import hosttest
import os

const registers = ['rax', 'rbx', 'rcx', 'rdx', 'rsi', 'rdi', 'rbp', 'r8', 'r9', 'r10', 'r11', 'r12',
	'r13', 'r14', 'r15']
const thunk = '<__x86_indirect_thunk_'

struct Branch {
	start   int
	operand int
}

fn space(ch rune) bool {
	return ch in [rune(9), 10, 11, 12, 13, 28, 29, 30, 31, 32, 0x85, 0xa0, 0x1680, 0x2000, 0x2001,
		0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029,
		0x202f, 0x205f, 0x3000]
}

// Keep the original regex's Unicode word boundary and whitespace semantics.
// Positions address runes; slices are converted only for reported failures.
fn branches(runes []rune) []Branch {
	mut values := []Branch{}
	patterns := ['call', 'callq', 'jmp', 'jmpq'].map(it.runes())
	for start in 0 .. runes.len {
		if runes[start] !in [`c`, `j`] { continue }
		if start > 0 && hosttest.module_word_rune(runes[start - 1]) { continue }
		for letters in patterns {
			if start + letters.len >= runes.len { continue }
			if runes[start..start + letters.len] != letters { continue }
			mut cursor := start + letters.len
			if !space(runes[cursor]) { continue }
			for cursor < runes.len && space(runes[cursor]) { cursor++ }
			values << Branch{start, cursor}
			break
		}
	}
	return values
}

fn line_end(runes []rune, start int) int {
	mut end := start
	for end < runes.len && runes[end] != `\n` { end++ }
	return end
}

fn spelling(runes []rune) string { return runes.map(it.str()).join('') }

fn raw_indirect(runes []rune, values []Branch) []string {
	mut raw := []string{}
	mut start := 0
	mut index := 0
	for start < runes.len {
		end := line_end(runes, start)
		mut last := -1
		for index < values.len && values[index].start < end {
			branch := values[index]
			index++
			if branch.start < start { continue }
			if branch.operand < runes.len && runes[branch.operand] == `*` {
				last = branch.operand
			}
		}
		finish := if last >= 0 { line_end(runes, last) } else { end }
		if last >= 0 { raw << spelling(runes[start..finish]) }
		start = finish + 1
	}
	return raw
}

fn thunk_branches(runes []rune, values []Branch) int {
	mut count := 0
	mut consumed := -1
	for branch in values {
		if branch.start < consumed { continue }
		end := line_end(runes, branch.operand)
		tail := spelling(runes[branch.operand..end])
		if at := tail.last_index(thunk) {
			count++
			// The original greedy [^\n]* consumes through the final thunk
			// prefix, so a second mnemonic inside that match is not counted.
			consumed = branch.operand + tail[..at + thunk.len].runes().len
		}
	}
	return count
}

pub fn check(listing string) !int {
	hosttest.module_decode_utf8(listing)!
	if !listing.contains('file format elf64-x86-64') {
		return error('FAIL: expected an x86-64 production ELF')
	}
	runes := listing.runes()
	values := branches(runes)
	raw := raw_indirect(runes, values)
	if raw.len > 0 {
		return error('FAIL: raw indirect branches:\n' + raw[..if raw.len < 20 {
			raw.len
		} else {
			20
		}].join('\n'))
	}
	for register in registers {
		name := thunk + register
		if !listing.contains(name + '>:') && (listing.contains(name + '>') || listing.contains(name + '+')) {
			return error('FAIL: unresolved thunk ' + register)
		}
	}
	if !listing.contains('<vinix_x86_resume_context>:') {
		return error('FAIL: missing final scheduler mitigation stub')
	}
	count := thunk_branches(runes, values)
	if count < 100 { return error('FAIL: compiler mitigation appears absent') }
	return count
}

pub fn command(arguments []string) int {
	parsed := hosttest.parse_arguments(arguments, [hosttest.Option{'--objdump', true, []}], 1,
		'Check the final x86 production ELF', 'Usage: check-linked KERNEL [--objdump TOOL]') or {
		eprintln(err.msg())
		return 2
	}
	tool := parsed.options['--objdump'] or { '/opt/homebrew/opt/llvm/bin/llvm-objdump' }
	arch := $if amd64 { 'amd64' } $else { 'arm64' }
	listing := fixturehost.capture_in_preferred([tool, '-d', '--no-show-raw-insn',
		parsed.positional[0]],
		'', os.environ(), false, '', false, arch) or {
		eprintln(err.msg())
		return 1
	}
	count := check(listing) or {
		eprintln(err.msg())
		return 1
	}
	println('CPU MITIGATION LINKED PASS: ${count} thunk branches, no raw indirect CALL/JMP')
	return 0
}
