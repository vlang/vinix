// SPDX-License-Identifier: GPL-2.0-or-later
module emulatorhost

import hosttest
import os
import policyhost

fn space(ch rune) bool {
	return ch in [rune(9), 10, 11, 12, 13, 28, 29, 30, 31, 32, 0x85, 0xa0, 0x1680,
		0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000]
}
fn trim(text string) string {
	chars := text.runes()
	mut first := 0
	mut last := chars.len
	for first < last && space(chars[first]) { first++ }
	for last > first && space(chars[last - 1]) { last-- }
	return chars[first..last].string()
}
fn lines(text string) []string {
	mut result := []string{}
	mut start := 0
	chars := text.runes()
	mut i := 0
	for i < chars.len {
		if chars[i] in [rune(10), 11, 12, 13, 28, 29, 30, 0x85, 0x2028, 0x2029] {
			result << chars[start..i].string()
			if chars[i] == 13 && i + 1 < chars.len && chars[i + 1] == 10 { i++ }
			start = i + 1
		}
		i++
	}
	if start < chars.len { result << chars[start..].string() }
	return result
}
fn cue_reference(line string) string {
	chars := line.runes()
	mut i := 0
	for i < chars.len && space(chars[i]) { i++ }
	if i + 4 >= chars.len || chars[i] !in [rune(`F`), `f`] || chars[i + 1] !in [rune(`I`), `i`, 0x130, 0x131]
		|| chars[i + 2] !in [rune(`L`), `l`] || chars[i + 3] !in [rune(`E`), `e`] || !space(chars[i + 4]) { return '' }
	i += 4
	for i < chars.len && space(chars[i]) { i++ }
	start := i
	if i < chars.len && chars[i] == `"` {
		i++
		for i < chars.len && chars[i] != `"` { i++ }
		if i > start + 1 && i + 1 < chars.len && space(chars[i + 1]) { return chars[start + 1..i].string() }
		// The unquoted alternative in the original regex also accepts a
		// leading quote if the quoted alternative cannot match.
		i = start
	}
	for i < chars.len && !space(chars[i]) { i++ }
	return if i > start && i < chars.len { chars[start..i].string() } else { '' }
}

pub fn stage_game(kind string, source_arg string, destination string) ! {
	mut copied := map[string]bool{}
	stage_game_inner(kind, source_arg, destination, mut copied)!
}

fn stage_game_inner(kind string, source_arg string, destination string, mut copied map[string]bool) ! {
	policyhost.command_checkpoint()!
	source := hosttest.module_resolve(source_arg)!
	if !os.exists(source) { return error('Missing game dependency: ' + source) }
	if kind == 'ps1' && source in copied { return }
	copied[source] = true
	mkdir(os.dir(destination))!
	hosttest.module_copy_file_preserving_stat(source, destination)!
	if kind != 'ps1' { return }
	mut references := []string{}
	ext := os.file_ext(source).to_lower()
	if ext in ['.cue', '.m3u'] {
		for line in lines(hosttest.module_read_text(source)!) {
			name := if ext == '.cue' { cue_reference(line) } else { trim(line) }
			if name != '' && (ext != '.m3u' || !name.starts_with('#')) { references << name }
		}
	}
	for name in references {
		relative := name.replace('\\', '/')
		if relative.starts_with('/') || '..' in relative.split('/') {
			return error('disc reference must stay below its directory: ' + name)
		}
		// Unix Path removes empty and '.' components, but treats backslashes
		// literally in all paths except the explicit disc-reference rule.
		part := relative.split('/').filter(it != '' && it != '.').join('/')
		stage_game_inner(kind, os.dir(source) + '/' + part, os.dir(destination) + '/' + part, mut copied)!
	}
}

// Reject malformed demonstration ROMs before indexing. The original swaps
// require complete halfwords/words and the IPL budget mutation requires 4 KiB.
pub fn n64_variants(data []u8) !([]u8, []u8, []u8) {
	if data.len < 0x1000 || data.len % 4 != 0 { return error('N64 demonstration ROM must contain complete words and IPL3') }
	mut half := data.clone()
	mut word := data.clone()
	for i in 0 .. data.len / 2 { half[i * 2] = data[i * 2 + 1]; half[i * 2 + 1] = data[i * 2] }
	for i in 0 .. data.len / 4 { for byte in 0 .. 4 { word[i * 4 + byte] = data[i * 4 + 3 - byte] } }
	mut stalled := data.clone()
	for i in 0x40 .. 0x1000 { stalled[i] = 0 }
	stalled[0x43] = 8 // big-endian jr $zero; nop
	return half, word, stalled
}
