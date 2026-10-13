// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

pub const max_command_arguments = 256
pub const max_command_bytes = 64 * 1024

pub struct CommandLaunch {
pub:
	arguments []string
	documents []string
}

struct LaunchInput {
	documents []string
	arguments []string
	terminal bool
	command bool
}

fn validate_command(input CommandLaunch) ! {
	if input.arguments.len > max_command_arguments || input.documents.len > max_command_arguments {
		return error('command launch exceeds the argument/document count limit')
	}
	mut bytes := 0
	for argument in input.arguments {
		if argument.contains('\x00') || argument.len > 4096 {
			return error('command argument contains NUL or exceeds 4096 bytes')
		}
		bytes += argument.len + 1
	}
	for document in input.documents {
		if !document.starts_with('/') || !printable(document, 4096) {
			return error('command document must be an absolute printable path')
		}
		bytes += document.len + 1
	}
	if bytes > max_command_bytes { return error('command launch exceeds the 64 KiB input limit') }
}

// Only the prefix is parsed as service options. Everything after -- is passed
// literally to the selected application, including empty strings and --file.
pub fn command_launch(arguments []string) !CommandLaunch {
	mut documents := []string{}
	mut position := 0
	for position < arguments.len && arguments[position] != '--' {
		if arguments[position] != '--file' || position + 1 >= arguments.len {
			return error('command launch requires [--file ABSOLUTE_FILE]... -- [LITERAL_ARGUMENT...]')
		}
		documents << arguments[position + 1]
		position += 2
	}
	if position >= arguments.len { return error('command launch requires the -- argument separator') }
	input := CommandLaunch{ documents: documents, arguments: arguments[position + 1..].clone() }
	validate_command(input)!
	return input
}
