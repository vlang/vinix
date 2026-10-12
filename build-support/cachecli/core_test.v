// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module cachecli

import cachekey
import os
import sourcecommand

#include <fcntl.h>

fn C.fcntl(i32, i32, ...int) i32

fn descriptors() int {
	mut count := 0
	for fd in 0 .. 1024 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn test_repeated_options_and_literal_compiler_words() {
	args := arguments(['--source=one', '--source', 'two', '--value=', 'record', '--state=x',
		'--staging=y'], ['--state', '--staging'], ['--source', '--value'], []string{}, 1, 1, '')!
	assert args.options['--source'] == ['one', 'two']
	assert args.options['--value'] == ['']
	assert args.positional == ['record']
	assert cachekey.shell_words('cc --flag "a b" \'\' "\\$literal"')! == ['cc', '--flag', 'a b',
		'', '\\$literal']
	assert cachekey.shell_words('cc a\\ b')! == ['cc', 'a b']
	for text in ['cc "open', 'cc \\'] {
		if _ := cachekey.shell_words(text) {
			assert false
		}
	}
	if _ := arguments(['--so', 'path'], ['--source', '--sort'], []string{}, []string{}, 0, 0, '') {
		assert false
	}
}

fn test_atomic_state_and_combined_stream_lifetimes() {
	work := sourcecommand.temporary('vinix-cache-state')!
	defer { os.rmdir_all(work) or { panic(err) } }
	before := descriptors()
	for _ in 0 .. 100 {
		publish(work + '/key', 'known key\n')!
		assert os.read_file(work + '/key')! == 'known key\n'
	}
	os.mkdir(work + '/destination')!
	if _ := publish(work + '/destination', 'failure') {
		assert false
	}
	assert os.is_dir(work + '/destination')
	assert os.ls(work)!.sorted() == ['destination', 'key']
	assert descriptors() == before
	guard := own_commands()
	defer { guard.close() }
	out := sourcecommand.capture_combined(['/bin/sh', '-c', 'printf one; printf two >&2; printf three'], os.environ(), 5, 1024, cancelled)!
	assert out.status == 0 && out.stdout == 'onetwothree' && out.stderr == ''
	assert descriptors() == before
}
