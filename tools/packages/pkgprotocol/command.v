// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

pub const command_argument_limit = 256
pub const command_byte_limit = 64 * 1024

pub fn validate_command_input(arguments []string, documents []string) ! {
	if arguments.len > command_argument_limit || documents.len > command_argument_limit {
		return error('command launch exceeds the argument/document count limit')
	}
	mut bytes := 0
	for argument in arguments {
		if argument.contains('\x00') || argument.len > 4096 {
			return error('command argument contains NUL or exceeds 4096 bytes')
		}
		bytes += argument.len + 1
	}
	for document in documents {
		if !document.starts_with('/') || !printable(document, 4096) {
			return error('command document must be an absolute printable path')
		}
		bytes += document.len + 1
	}
	if bytes > command_byte_limit { return error('command launch exceeds the 64 KiB input limit') }
}

// Own every string and the array storage. Also use this for command_vector.
pub fn free_command_values(mut values []string) {
	for value in values { unsafe { value.free() } }
	unsafe { (&array(&values)).free() }
	values = []string{}
}

// A small quoting grammar, not a shell: quotes group bytes, backslash escapes
// the next byte outside single quotes, and unquoted ASCII whitespace separates
// arguments. There is no substitution, expansion, redirection or execution.
pub fn command_words(text string) ![]string {
	if text.len > command_byte_limit || text.contains('\x00') {
		return error('Arguments contain NUL or exceed 64 KiB.')
	}
	mut words := []string{}
	mut word := []u8{cap: 256}
	unsafe { words.flags |= .noslices; word.flags |= .noslices }
	mut complete := false
	defer {
		unsafe { word.free() }
		if !complete { free_command_values(mut words) }
	}
	mut quote := u8(0)
	mut escaped := false
	mut started := false
	for byte in text {
		if escaped {
			escaped = false
		} else if byte == `\\` && quote != `'` {
			escaped = true; started = true; continue
		} else if quote != 0 {
			if byte == quote { quote = 0; continue }
		} else if byte in [`'`, `"`] {
			quote = byte; started = true; continue
		} else if byte in [` `, `\t`, `\n`, `\r`] {
			if started {
				if words.len == command_argument_limit { return error('Arguments exceed 256 values.') }
				words << unsafe { tos(word.data, word.len).clone() }
				word.clear(); started = false
			}
			continue
		}
		if word.len == 4096 { return error('An argument exceeds 4096 bytes.') }
		word << byte
		started = true
	}
	if quote != 0 { return error('Finish the quoted argument before launching.') }
	if escaped { return error('A trailing backslash must escape a character.') }
	if started {
		if words.len == command_argument_limit { return error('Arguments exceed 256 values.') }
		words << unsafe { tos(word.data, word.len).clone() }
	}
	validate_command_input(words, [])!
	complete = true
	return words
}

// Returns owned service arguments. The executable is chosen by the caller,
// while the package service still admits trust, policy, identity and files.
pub fn command_vector(id string, arguments []string, documents []string, data_cwd bool, terminal bool) ![]string {
	if !identifier(id) { return error('invalid package launch request') }
	validate_command_input(arguments, documents)!
	mut vector := []string{cap: 4 + arguments.len + documents.len * 2}
	unsafe { vector.flags |= .noslices }
	vector << if terminal { 'run-terminal-args'.clone() } else { 'run-args'.clone() }
	vector << id.clone()
	if data_cwd { vector << '--data-cwd'.clone() }
	for document in documents { vector << '--file'.clone(); vector << document.clone() }
	vector << '--'.clone()
	for argument in arguments { vector << argument.clone() }
	return vector
}
