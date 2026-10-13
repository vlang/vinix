// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

fn test_command_words_group_quotes_preserve_empty_and_literal_shell_text() {
	mut words := command_words('one "two three" ' + "'four five'" + ' six\\ seven "" ab"cd"e')!
	assert words == ['one', 'two three', 'four five', 'six seven', '', 'abcde']
	free_command_values(mut words)
	assert words.len == 0
	mut literal := command_words('$(literal) $HOME ; | > * ~/a @DATA@\n')!
	assert literal == ['$(literal)', '$HOME', ';', '|', '>', '*', '~/a', '@DATA@']
	free_command_values(mut literal)
	mut single := command_words("'C:\\Program Files\\app' \"a\nb\"")!
	assert single == ['C:\\Program Files\\app', 'a\nb']
	free_command_values(mut single)
	mut blank := command_words(' \t\n\r')!
	assert blank.len == 0
	free_command_values(mut blank)
}

fn test_command_words_refuse_incomplete_quoting_nul_and_bounds_without_truncation() {
	for input in ['a "unfinished', "a 'unfinished", 'a trailing\\', 'nul\x00', 'x'.repeat(4097), 'x '.repeat(257), 'x'.repeat(command_byte_limit + 1)] {
		mut refused := false
		command_words(input) or { refused = true }
		assert refused
	}
	mut edge := command_words('x'.repeat(4096))!
	assert edge.len == 1 && edge[0].len == 4096
	free_command_values(mut edge)
}

fn test_command_vector_owns_every_value_separates_grants_and_preserves_service_options_as_app_arguments() {
	mut vector := command_vector('org.ffmpeg.cli', ['--data-cwd', '--file', '/etc/passwd', '', '$literal'], ['/home/alex/a space'], true, true)!
	assert vector == ['run-terminal-args', 'org.ffmpeg.cli', '--data-cwd', '--file', '/home/alex/a space', '--', '--data-cwd', '--file', '/etc/passwd', '', '$literal']
	free_command_values(mut vector)
	for id in ['', 'root; command', '../app'] {
		mut refused := false
		command_vector(id, [], [], false, false) or { refused = true }
		assert refused
	}
}
