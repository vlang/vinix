// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import ext2host
import hosttest
import policyhost
import strconv
import time

fn ext2_export(args []string) !int {
	if args.len == 0 || args[0] in ['--help', '-h'] {
		println('Usage: ext2-export build SOURCE --state DIR [--overlay DIR ...]\n       ext2-export serve --state DIR [--port 10809] [--export-name NAME]')
		return if args.len == 0 { 2 } else { 0 }
	}
	kind := args[0]
	if kind !in ['build', 'serve'] { return argument('Unknown export command') }
	if kind == 'build' && args.len < 2 { return argument('build requires a source directory') }
	tail := args[if kind == 'build' { 2 } else { 1 }..]
	options := parse(tail, [hosttest.Option{ name: '--state', value: true },
		hosttest.Option{ name: '--overlay', value: true },
		hosttest.Option{ name: '--port', value: true },
		hosttest.Option{ name: '--export-name', value: true }], ['--overlay'], 'Usage: ext2-export build SOURCE --state DIR | serve --state DIR')!
	required(options, ['--state'])!
	state := resolve(options.value('--state', ''))!
	if kind == 'build' {
		manifest := ext2host.build(args[1], state, options.values['--overlay'] or { []string{} })!
		info := ext2host.inspect(state + '/metadata.ext2')!
		println('Exported ' + manifest.files.len.str() + ' files; disk size ' + manifest.size.str() + ' bytes; metadata storage ' + (info.blocks * 512).str() + ' bytes')
	} else {
		port := strconv.atoi(options.value('--port', '10809')) or { return argument('Invalid port') }
		if port < 0 || port > 65535 { return argument('Invalid port') }
		name := options.value('--export-name', '')
		mut server := ext2host.serve(state, port, name, 3, 120000)!
		defer { server.close() }
		println('Read-only ext2: nbd://127.0.0.1:' + server.port.str() + '/' + name)
		for !policyhost.command_interrupted() { time.sleep(100 * time.millisecond) }
	}
	return 0
}
