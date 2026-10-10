// SPDX-License-Identifier: GPL-2.0-or-later
module symbolcore

import encoding.utf8
import hosttest
import math.big
import os

const skip = ['memory__Slab__alloc', 'memory__malloc', 'v_malloc', 'malloc', 'malloc_uninit',
	'malloc_noscan', 'vcalloc', 'alloc_array_data', 'array__ensure_cap', 'memdup']
const leaves = ['memcpy', 'memmove', 'memset', 'memcmp', 'strlen', 'strcmp', 'strncmp', 'strcpy']
// Decimal category Nd in the original Python 3.9 / Unicode 13 parser.
const decimal_zeros = [0x30, 0x660, 0x6f0, 0x7c0, 0x966, 0x9e6, 0xa66, 0xae6, 0xb66, 0xbe6, 0xc66,
	0xce6, 0xd66, 0xde6, 0xe50, 0xed0, 0xf20, 0x1040, 0x1090, 0x17e0, 0x1810, 0x1946, 0x19d0, 0x1a80,
	0x1a90, 0x1b50, 0x1bb0, 0x1c40, 0x1c50, 0xa620, 0xa8d0, 0xa900, 0xa9d0, 0xa9f0, 0xaa50, 0xabf0,
	0xff10, 0x104a0, 0x10d30, 0x11066, 0x110f0, 0x11136, 0x111d0, 0x112f0, 0x11450, 0x114d0, 0x11650,
	0x116c0, 0x11730, 0x118e0, 0x11950, 0x11c50, 0x11d50, 0x11da0, 0x16a60, 0x16b50, 0x1d7ce, 0x1d7d8,
	0x1d7e2, 0x1d7ec, 0x1d7f6, 0x1e140, 0x1e2f0, 0x1e950, 0x1fbf0]

fn space(character rune) bool {
	return utf8.is_space(character) || character in [`\x1c`, `\x1d`, `\x1e`, `\x1f`]
}

fn stripped(text string) string {
	runes := text.runes()
	mut start := 0
	mut end := runes.len
	for start < end && space(runes[start]) { start++ }
	for end > start && space(runes[end - 1]) { end-- }
	return runes[start..end].string()
}

fn decimal(character rune) bool { return decimal_zeros.any(character >= it && character < it + 10) }

fn hex(character u8) bool {
	return (character >= `0` && character <= `9`) || (character >= `a` && character <= `f`)
}

pub struct Site {
pub:
	label     string
	count     string
	size      string
	addresses []string
}

pub fn allocation_line(raw string) ?Site {
	line := stripped(raw)
	mut marker := 0
	for {
		found := line.index_after('PERF-SITE ', marker) or { return none }
		start := found + 10
		marker = start
		for separator in start .. line.len {
			if line[separator] != ` ` { continue }
			mut pos := separator + 1
			count_start := pos
			for pos < line.len {
				character := utf8.get_rune(line, pos)
				if !decimal(character) { break }
				pos += character.str().len
			}
			if pos == count_start || pos == line.len || line[pos] != ` ` { continue }
			count := line[count_start..pos]
			pos++
			size_start := pos
			for pos < line.len {
				character := utf8.get_rune(line, pos)
				if !decimal(character) { break }
				pos += character.str().len
			}
			if pos == size_start || pos == line.len || line[pos] != ` ` { continue }
			size := line[size_start..pos]
			pos++
			words := line[pos..].split(' ')
			if words.len == 0 || words.any(it == '' || !it.bytes().all(hex(it))) { continue }
			addresses := words.filter(it != '0')
			return Site{line[start..separator], count, size, if addresses.len > 0 {
				addresses[1..].clone()
			} else {
				[]string{}
			}}
		}
	}
	return none
}

fn subtract(address string, amount int, clamp bool) !string {
	value := big.integer_from_radix(address, 16)!
	result := value - big.integer_from_int(amount)
	encoded := result.hex()
	if encoded.starts_with('-') { return if clamp { '0' } else { '-0x' + encoded[1..] } }
	return if clamp { encoded } else { '0x' + encoded }
}

pub fn allocation_frames(output string) []string {
	mut frames := []string{}
	for block in stripped(output.replace('\r\n', '\n').replace('\r', '\n')).split('\n\n') {
		lines := block.split('\n')
		for index := 0; index < lines.len - 1; index += 2 {
			name := lines[index]
			if name != '??' && !skip.any(name.starts_with(it)) { frames << name }
		}
	}
	return frames
}

pub fn allocation_tool() !string {
	configured := (os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }) + '/llvm-symbolizer'
	if os.exists(configured) { return configured }
	if found := os.find_abs_path_of_executable('llvm-symbolizer') { return found }
	return error('llvm-symbolizer not found; set LLVM_BIN')
}

pub fn allocation_report(site Site, kernel string, tool string) !string {
	mut argv := [tool, '--obj=${kernel}', '--functions=short', '--inlining=true']
	for address in site.addresses { argv << subtract(address, 4, false)! }
	result := hosttest.capture(argv, '', -1, os.environ())!
	// The original allocation reporter uses stdout even after a nonzero exit.
	return '${site.label}: ${site.count} x ${site.size} bytes\n    ${allocation_frames(result.stdout).join(' <- ')}\n'
}

pub fn allocation_key(site Site) string {
	// Length framing avoids collisions when a label itself contains delimiters.
	return '${site.label.len}:${site.label}${site.size.len}:${site.size}' + site.addresses.map('${it.len}:${it}').join('')
}

pub fn run_allocations(args []string) int {
	if args.len != 1 {
		eprintln('Usage: tests/kernel-allocs/sites KERNEL < run.log')
		return 1
	}
	tool := allocation_tool() or {
		eprintln(err)
		return 1
	}
	mut seen := map[string]bool{}
	for {
		line := os.get_raw_line()
		if line == '' { break }
		site := allocation_line(line) or { continue }
		key := allocation_key(site)
		if key in seen { continue }
		seen[key] = true
		print(allocation_report(site, args[0], tool) or {
			eprintln(err)
			return 1
		})
	}
	return 0
}

pub struct Hit {
pub:
	kind    string
	pc      string
	lr      string
	frames  []string
	process string
}

// The byte-pattern's process name extends greedily to the last ')' on its
// line. Matches may start inside a serial prefix and repeat on later lines.
pub fn access_hits(text string) []Hit {
	mut hits := []Hit{}
	for line in text.split('\n') {
		mut search := 0
		for {
			start := line.index_after('user-access: ', search) or { break }
			search = start + 13
			mut pos := search
			kind := if line[pos..].starts_with('read ') {
				'read'
			} else if line[pos..].starts_with('wrote ') {
				'wrote'
			} else {
				continue
			}
			pos += kind.len
			mut addresses := []string{}
			mut valid := true
			for separator in [' 0x', ' at pc 0x', ' lr 0x', ' < 0x', ' 0x', ' 0x', ' 0x'] {
				if !line[pos..].starts_with(separator) {
					valid = false
					break
				}
				pos += separator.len
				hex_start := pos
				for pos < line.len && hex(line[pos]) { pos++ }
				if pos == hex_start {
					valid = false
					break
				}
				addresses << line[hex_start..pos]
			}
			if !valid || !line[pos..].starts_with(' (') { continue }
			process_start := pos + 2
			end := line.last_index(')') or { continue }
			if end < process_start { continue }
			hits << Hit{kind, addresses[1], addresses[2], addresses[3..].clone(), replacement_utf8(line[process_start..end])}
			break
		}
	}
	return hits
}

// Unicode replacement decoding follows maximal valid prefixes of malformed
// sequences, matching the old process-name decode(errors='replace').
fn replacement_utf8(text string) string {
	mut result := []u8{}
	mut pos := 0
	for pos < text.len {
		first := text[pos]
		if first < 0x80 {
			result << first
			pos++
			continue
		}
		length := if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			0
		}
		mut consumed := 1
		if length != 0 {
			for consumed < length && pos + consumed < text.len {
				byte := text[pos + consumed]
				if byte < 0x80 || byte > 0xbf { break }
				if consumed == 1 && ((first == 0xe0 && byte < 0xa0) || (first == 0xed && byte > 0x9f) || (first == 0xf0 && byte < 0x90) || (first == 0xf4 && byte > 0x8f)) {
					break
				}
				consumed++
			}
		}
		if length != 0 && consumed == length {
			result << text[pos..pos + consumed].bytes()
		} else {
			result << [u8(0xef), 0xbf, 0xbd]
		}
		pos += consumed
	}
	return result.bytestr()
}

fn canonical(address string) string {
	value := address.trim_left('0')
	return if value == '' { '0' } else { value }
}

pub fn access_addresses(hits []Hit) ![]string {
	mut set := map[string]bool{}
	for hit in hits {
		set[canonical(hit.pc)] = true
		set[subtract(hit.lr, 1, true)!] = true
		for address in hit.frames { set[subtract(address, 1, true)!] = true }
	}
	mut addresses := set.keys().filter(it != '0')
	addresses.sort_with_compare(fn (a &string, b &string) int {
		if a.len < b.len { return -1 }
		if a.len > b.len { return 1 }
		return compare_strings(a, b)
	})
	return addresses
}

pub fn access_names(addresses []string, output string) map[string][]string {
	mut table := map[string][]string{}
	blocks := output.replace('\r\n', '\n').replace('\r', '\n').trim('\n').split('\n\n')
	for index in 0 .. int_min(addresses.len, blocks.len) {
		lines := blocks[index].split('\n')
		mut names := []string{}
		for frame := 0; frame < lines.len; frame += 2 { names << lines[frame] }
		table[addresses[index]] = names
	}
	return table
}

pub fn access_tool() !string {
	for name in ['llvm-symbolizer', '/opt/homebrew/opt/llvm/bin/llvm-symbolizer'] {
		if found := os.find_abs_path_of_executable(name) { return found }
	}
	return error('llvm-symbolizer not found')
}

pub fn access_report(hits []Hit, table map[string][]string, amd64 bool) (string, int) {
	mut seen := map[string]bool{}
	mut output := ''
	for hit in hits {
		mut chain := (table[canonical(hit.pc)] or { ['?'] }).clone()
		mut callers := hit.frames.clone()
		if chain.last() in leaves || amd64 { callers.prepend(hit.lr) }
		for caller in callers {
			if canonical(caller) == '0' { continue }
			address := subtract(caller, 1, true) or { panic(err) }
			for name in table[address] or { ['?'] } {
				if chain.last() != name && name != '??' { chain << name }
			}
		}
		key := '${hit.kind.len}:${hit.kind}' + chain.map('${it.len}:${it}').join('')
		if key in seen { continue }
		seen[key] = true
		output += '${hit.kind:-5} ${chain.join(' < ')}   [${hit.process}]\n'
	}
	output += '${seen.len} paths\n'
	return output, 1
}

pub fn run_access(args []string) int {
	if args.len != 1 {
		eprintln('Usage: tests/user-access/sites KERNEL < serial.log')
		return 1
	}
	hits := access_hits(os.get_raw_stdin().bytestr())
	if hits.len == 0 {
		println('no direct user accesses reported')
		return 0
	}
	addresses := access_addresses(hits) or {
		eprintln(err)
		return 1
	}
	mut table := map[string][]string{}
	tool := access_tool() or {
		eprintln(err)
		return 1
	}
	if addresses.len > 0 {
		mut argv := [tool, '-e', args[0], '--inlines', '--functions=short']
		argv << addresses.map('0x' + it)
		result := hosttest.capture(argv, '', -1, os.environ()) or {
			eprintln(err)
			return 1
		}
		if result.code != 0 {
			eprintln('llvm-symbolizer exited ${result.code}: ${result.stderr.trim_space()}')
			return 1
		}
		table = access_names(addresses, result.stdout)
	}
	mut image := os.open(args[0]) or {
		eprintln(err)
		return 1
	}
	defer { image.close() }
	mut header := []u8{len: 20}
	count := image.read(mut header) or { 0 }
	amd64 := count >= 20 && header[18] == 0x3e && header[19] == 0
	message, code := access_report(hits, table, amd64)
	print(message)
	return code
}
