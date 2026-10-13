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

struct LaunchInput {
	documents []string
	arguments []string
	terminal bool
	command bool
	data_cwd bool
}

fn validate_command(input CommandLaunch) ! {
	pkgprotocol.validate_command_input(input.arguments, input.documents)!
}

// Only the prefix is parsed as service options. Everything after -- is passed
// literally to the selected application, including empty strings and --file.
pub fn command_launch(arguments []string) !CommandLaunch {
	mut documents := []string{}
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
		documents << arguments[position + 1]
		position += 2
	}
	if position >= arguments.len { return error('command launch requires the -- argument separator') }
	if arguments.len - position - 1 > max_command_arguments { return error('command launch exceeds the argument count limit') }
	input := CommandLaunch{ documents: documents, arguments: arguments[position + 1..].clone(), data_cwd: data_cwd }
	validate_command(input)!
	return input
}
