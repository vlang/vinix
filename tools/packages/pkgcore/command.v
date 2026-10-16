// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

pub const max_command_arguments = pkgprotocol.command_argument_limit
pub const max_command_bytes = pkgprotocol.command_byte_limit

pub struct CommandLaunch {
pub:
	arguments []string
	documents []string
	data_cwd bool // work in private application data, without adding any grants
}

// Requests returned by command_launch own their vectors and strings. Manually
// assembled inputs can borrow fields and must not retire those borrowed values.
pub fn (mut input CommandLaunch) close() {
	mut owned_arguments := unsafe { input.arguments }
	mut owned_documents := unsafe { input.documents }
	pkgprotocol.free_command_values(mut owned_arguments)
	pkgprotocol.free_command_values(mut owned_documents)
	input = CommandLaunch{}
}

struct LaunchInput {
	documents []string
	arguments []string
	terminal bool
	command bool
	data_cwd bool
	window bool
}

fn validate_command(input CommandLaunch) ! {
	pkgprotocol.validate_command_input(input.arguments, input.documents)!
}

// Only the prefix is parsed as service options. Everything after -- is passed
// literally to the selected application, including empty strings and --file.
pub fn command_launch(arguments []string) !CommandLaunch {
	// Prefix scratch borrows the caller's paths. Clone only after the complete
	// borrowed request has passed syntax, count, string and aggregate limits.
	capacity := if arguments.len / 2 < max_command_arguments { arguments.len / 2 } else { max_command_arguments }
	mut documents := []string{cap: capacity}
	unsafe { documents.flags |= .noslices }
	defer { unsafe { (&array(&documents)).free() } }
	mut position := 0
	mut data_cwd := false
	for position < arguments.len && arguments[position] != '--' {
		if arguments[position] == '--data-cwd' {
			if data_cwd { return error('command launch repeats --data-cwd') }
			data_cwd = true; position++; continue
		}
		if arguments[position] != '--file' || position + 1 >= arguments.len {
			return error('command launch requires [--data-cwd] [--file ABSOLUTE_FILE]... -- [LITERAL_ARGUMENT...]')
		}
		if documents.len == max_command_arguments { return error('command launch exceeds the document count limit') }
		// V's normal string append clones; this temporary vector only borrows.
		unsafe { documents.push_many(&arguments[position + 1], 1) }
		position += 2
	}
	if position >= arguments.len { return error('command launch requires the -- argument separator') }
	if arguments.len - position - 1 > max_command_arguments { return error('command launch exceeds the argument count limit') }
	input := CommandLaunch{ documents: documents, arguments: arguments[position + 1..], data_cwd: data_cwd }
	validate_command(input)!
	return CommandLaunch{ documents: review_strings(input.documents), arguments: review_strings(input.arguments), data_cwd: data_cwd }
}
