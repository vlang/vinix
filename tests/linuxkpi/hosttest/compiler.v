// SPDX-License-Identifier: GPL-2.0-or-later
module hosttest

import os

pub fn shell_split(text string) ![]string {
	mut result := []string{}
	mut token := ''
	mut quote := u8(0)
	mut started := false
	mut index := 0
	for index < text.len {
		ch := text[index]
		if quote == `'` {
			if ch == quote { quote = 0 } else { token += ch.ascii_str() }
		} else if ch == `\\` {
			index++
			if index >= text.len { return error('No escaped character') }
			next := text[index]
			// Python's POSIX shlex treats only quotes/backslashes as escapes
			// inside double quotes; dollar signs and backticks stay literal.
			if quote == `"` && next !in [`"`, `\\`] { token += '\\' }
			token += next.ascii_str()
			started = true
		} else if quote != 0 {
			if ch == quote { quote = 0 } else { token += ch.ascii_str() }
		} else if ch in [`'`, `"`] {
			quote = ch
			started = true
		} else if ch in [` `, `\t`, `\r`, `\n`] {
			if started { result << token; token = ''; started = false }
		} else {
			token += ch.ascii_str()
			started = true
		}
		index++
	}
	if quote != 0 { return error('No closing quotation') }
	if started { result << token }
	return result
}

pub fn shell_quote(text string) string {
	if text != '' && text.bytes().all(it.is_alnum() || it in [`_`, `@`, `%`, `+`, `=`, `:`, `,`, `.`, `/`, `-`]) {
		return text
	}
	return "'" + text.replace("'", "'\"'\"'") + "'"
}

pub fn shell_join(args []string) string {
	return args.map(shell_quote(it)).join(' ')
}

pub fn v_function(source string, name string) !string {
	mut start := 0
	for line in source.split_into_lines() {
		if (line.starts_with('fn ${name}(') || line.starts_with('pub fn ${name}(')) &&
			line.contains(')') && line.contains('{') {
			mut begin := start
			if start > 0 {
				previous := source[..start - 1].all_after_last('\n')
				if previous.starts_with('@[export:') { begin -= previous.len + 1 }
			}
			mut end := start + (line.index('{') or { return error('Missing function brace') }) + 1
			mut depth := 1
			for depth > 0 && end < source.len {
				if source[end] == `{` { depth++ }
				if source[end] == `}` { depth-- }
				end++
			}
			if depth != 0 { return error('Unterminated genuine V function ${name}') }
			return source[begin..end] + '\n'
		}
		start += line.len + 1
	}
	return error('Missing genuine V function ${name}')
}

pub fn extract_body(raw string, name string) !string {
	bodies := c_bodies(raw).filter(named_body(it, name))
	if bodies.len != 1 { return error('Missing unique actual generated body ${name}') }
	return bodies[0]
}

fn identifier(text string) bool {
	return text.len > 0 && (text[0].is_letter() || text[0] == `_`) && text.bytes().all(word_char(it))
}

fn foreign_scalar_declarations(raw string, name string) int {
	mut remaining := raw
	mut count := 0
	marker := '@[typedef]'
	for remaining.contains(marker) {
		remaining = remaining.all_after(marker).trim_left(' \t\r\n\v\f')
		declaration := 'struct C.' + name
		if !remaining.starts_with(declaration) { continue }
		mut tail := remaining[declaration.len..].trim_left(' \t\r\n\v\f')
		if !tail.starts_with('{') { continue }
		tail = tail[1..].trim_left(' \t\r\n\v\f')
		if tail.starts_with('}') { count++ }
	}
	return count
}

// This is the original producer's bounded native scalar metadata contract.
// It emits only a readonly native typedef and a width assertion, never a body.
pub fn scalar_metadata(source string, text string) !string {
	mut paths := os.glob(os.join_path(source, '*.v'))!
	paths.sort()
	mut aliases := map[string]string{}
	for path in paths {
		raw := os.read_file(path)!
		for line in raw.split_into_lines() {
			if !line.starts_with('// ABI native-scalar:') { continue }
			parts := line.fields()
			if parts.len != 5 || parts[..3] != ['//', 'ABI', 'native-scalar:'] ||
				!identifier(parts[3]) || parts[4] != 'const_unsigned_long_64' {
				return error('Invalid native scalar metadata in ${path}: ${line}')
			}
			name := parts[3]
			if line != '// ABI native-scalar: ${name} ${parts[4]}' {
				return error('Invalid native scalar metadata in ${path}: ${line}')
			}
			if name in aliases { return error('Duplicate native scalar alias: ${name}') }
			if foreign_scalar_declarations(raw, name) != 1 {
				return error('Native scalar metadata lacks one foreign V declaration: ${name}')
			}
			for statement in text.split(';') {
				if has_word(statement, 'typedef') && statement.trim_space().ends_with(name) &&
					has_word(statement, name) {
					return error('Native scalar alias conflicts with compiler declaration: ${name}')
				}
			}
			aliases[name] = 'const unsigned long'
		}
	}
	mut declarations := []string{}
	for name, scalar in aliases {
		declarations << 'typedef ${scalar} ${name};'
		declarations << '_Static_assert(sizeof(${name}) == 8, "native 64-bit readonly scalar");'
	}
	return declarations.join('\n') + (if declarations.len > 0 { '\n' } else { '' }) + text
}

pub fn c_declarations(raw string, selected []string) !string {
	mut sorted := selected.clone()
	sorted.sort()
	mut result := []string{}
	for name in sorted {
		found := raw.split_into_lines().filter(it.ends_with(');') &&
			!it.contains('{') && !it.contains('}') && named_body(it, name))
		if found.len == 0 { return error('Missing actual generated declaration ${name}') }
		result << found[0]
	}
	return result.join('\n') + '\n'
}
