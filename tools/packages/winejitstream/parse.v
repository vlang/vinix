// SPDX-License-Identifier: GPL-2.0-or-later
module winejitstream

pub const log_limit = 262144

pub struct Capture {
pub:
	role            string
	pid             int
	instructions    map[u64][]string
	arithmetic_pass bool
}

pub struct Comparison {
pub:
	parent_pid            int
	child_pid             int
	overlapping_addresses int
	differing_addresses   int
	examples              []Difference
}

pub struct Difference {
pub:
	address      u64
	parent_words []string
	child_words  []string
}

fn hex_digit(value u8) int {
	if value >= `0` && value <= `9` {
		return int(value - `0`)
	}
	if value >= `a` && value <= `f` {
		return int(value - `a`) + 10
	}
	if value >= `A` && value <= `F` {
		return int(value - `A`) + 10
	}
	return -1
}

fn marker_pid(line string, prefix string) !int {
	if !line.starts_with(prefix) {
		return error('unexpected JITSTREAM marker')
	}
	digits := line[prefix.len..]
	if digits.len == 0 || digits[0] == `0` {
		return error('JITSTREAM PID must be canonical and positive')
	}
	mut pid := 0
	for digit in digits {
		if digit < `0` || digit > `9` {
			return error('JITSTREAM PID must be canonical and positive')
		}
		value := int(digit - `0`)
		if pid > (2147483647 - value) / 10 {
			return error('JITSTREAM PID exceeds the supported int range')
		}
		pid = pid * 10 + value
	}
	return pid
}

// QEMU's AArch64 out_asm rows contain one 32-bit instruction word. Keep the
// word rather than its disassembly, which can vary with disassembler versions.
fn instruction(line string) !(u64, string) {
	colon := line.index(':') or { return error('instruction row has no address separator') }
	if !line.starts_with('0x') || colon < 3 || colon > 18 {
		return error('instruction address must contain 1 to 16 hexadecimal digits')
	}
	mut address := u64(0)
	for digit in line[2..colon] {
		value := hex_digit(digit)
		if value < 0 {
			return error('instruction address is not hexadecimal')
		}
		address = (address << 4) | u64(value)
	}
	rest := line[colon + 1..]
	if rest.len < 12 || !rest.starts_with('  ') {
		return error('instruction row must have two spaces before its word')
	}
	word := rest[2..10]
	for digit in word {
		if hex_digit(digit) < 0 {
			return error('instruction word must contain exactly eight hexadecimal digits')
		}
	}
	if (rest[10] != ` ` && rest[10] != `\t`) || rest[11..].trim_space().len == 0 {
		return error('instruction word must be followed by disassembly')
	}
	return address, word.to_lower()
}

// Only rows after this role's exact READY marker belong to its capture. Both
// processes can emit to inherited stderr before their descriptor redirection.
pub fn parse(text string, role string) !Capture {
	if role != 'parent' && role != 'child' {
		return error('JITSTREAM role must be parent or child')
	}
	if text.len > log_limit {
		return error('JITSTREAM log exceeds the byte limit')
	}
	mut ready := false
	mut pid := 0
	mut arithmetic_pass := false
	mut instructions := map[u64][]string{}
	for line_index, line in text.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('JITSTREAM READY') {
			if ready {
				return error('duplicate JITSTREAM READY marker')
			}
			pid = marker_pid(line, 'JITSTREAM READY ${role} pid=')!
			ready = true
			continue
		}
		if trimmed.starts_with('JITSTREAM ARITHMETIC') {
			if !ready || arithmetic_pass {
				return error('JITSTREAM ARITHMETIC marker requires one preceding READY')
			}
			pass_pid := marker_pid(line, 'JITSTREAM ARITHMETIC ${role} PASS pid=')!
			if pass_pid != pid {
				return error('JITSTREAM ARITHMETIC PID differs from READY')
			}
			arithmetic_pass = true
			continue
		}
		if !ready || (!trimmed.starts_with('0x') && !trimmed.starts_with('0X')) {
			continue
		}
		address, word := instruction(line) or {
			return error('invalid AArch64 instruction row at line ${line_index + 1}: ${err}')
		}
		mut words := instructions[address]
		if word !in words {
			words << word
			instructions[address] = words
		}
	}
	if !ready {
		return error('missing JITSTREAM READY marker')
	}
	if instructions.len == 0 {
		return error('JITSTREAM capture has no instructions after READY')
	}
	for address, captured in instructions {
		mut words := captured.clone()
		words.sort()
		instructions[address] = words
	}
	return Capture{
		role:            role
		pid:             pid
		instructions:    instructions
		arithmetic_pass: arithmetic_pass
	}
}

// Address overlap is an observation about virtual addresses. It establishes
// neither shared backing nor the cause of a translation or execution failure.
pub fn compare(parent Capture, child Capture) !Comparison {
	if parent.role != 'parent' || child.role != 'child' {
		return error('JITSTREAM comparison requires parent and child captures')
	}
	if parent.pid <= 0 || child.pid <= 0 || parent.pid == child.pid {
		return error('JITSTREAM comparison requires distinct positive PIDs')
	}
	if parent.instructions.len == 0 || child.instructions.len == 0 {
		return error('JITSTREAM comparison requires instructions in both captures')
	}
	mut addresses := parent.instructions.keys()
	addresses.sort()
	mut overlapping := 0
	mut differing := 0
	mut examples := []Difference{}
	for address in addresses {
		if address !in child.instructions {
			continue
		}
		parent_words := parent.instructions[address]
		child_words := child.instructions[address]
		if parent_words.len == 0 || child_words.len == 0 {
			return error('JITSTREAM instruction address has no words')
		}
		overlapping++
		mut different := false
		// Testing every word against one opposite word is sufficient to find
		// any differing pair without a quadratic cross product.
		for parent_word in parent_words {
			if parent_word != child_words[0] {
				different = true
				break
			}
		}
		if !different {
			for child_word in child_words {
				if child_word != parent_words[0] {
					different = true
					break
				}
			}
		}
		if different {
			differing++
			if examples.len < 8 {
				examples << Difference{
					address:      address
					parent_words: parent_words.clone()
					child_words:  child_words.clone()
				}
			}
		}
	}
	return Comparison{
		parent_pid:            parent.pid
		child_pid:             child.pid
		overlapping_addresses: overlapping
		differing_addresses:   differing
		examples:              examples
	}
}
