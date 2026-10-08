// SPDX-License-Identifier: GPL-2.0-or-later
module packagestore

import androidhost as ah

fn option(options string, name string) !string { return attribute(options, name)! }

fn parser_error(parser string, message string) ! {
	method(parser, 'error', [v(ah.Value(message))], {})!
}

fn main_policy(options string, parser string) ! {
	source_arg := option(options, 'source_root')!
	ui_arg := option(options, 'ui2_source')!
	source := if truth(source_arg)! { method(source_arg, 'resolve', [], {})! } else { null()! }
	extras := call('builtins.tuple', o(option(options, 'source_extra')!))!
	mut ui2 := if truth(ui_arg)! { method(ui_arg, 'resolve', [], {})! } else { null()! }
	if !compare('is_', ui2, null()!)! && compare('is_', source, null()!)! {
		parser_error(parser, '--ui2-source requires --source-root')!
	}
	if !compare('is_', source, null()!)! {
		if !truth(method(source, 'is_dir', [], {})!)! {
			parser_error(parser, 'source root is not a directory: ' + text(source)!)!
		}
		iter := iterator(extras)!
		for {
			row := next(iter)!
			if row.done { break }
			extra := row.value
			if truth(method(extra, 'is_absolute', [], {})!)! || truth(call('operator.contains', o(attribute(extra, 'parts')!), v(ah.Value('..')))!)! {
				parser_error(parser, 'source extra must stay below source root: ' + text(extra)!)!
			}
			method(method(call('operator.truediv', o(source), o(extra))!, 'resolve', [], {})!, 'relative_to', [o(source)], {}) or {
				if kind(err, 'value_error') {
					activate(err)!
					parser_error(parser, 'source extra resolves outside source root: ' + text(extra)!)!
					activate(none)!
				} else {
					return err
				}
				''
			}
		}
		if compare('is_', ui2, null()!)! { ui2 = join(source, 'third_party/ui2')! }
		if !truth(method(join(ui2, 'v.mod')!, 'is_file', [], {})!)! {
			parser_error(parser, 'ui2 source is not a checkout: ' + text(ui2)!)!
		}
	}
	address := collection('tuple', [literal(ah.Value('127.0.0.1'))!, option(options, 'port')!])!
	destination := method(option(options, 'store')!, 'resolve', [], {})!
	server := call('OverlayServer', o(address), o(destination), o(option(options, 'max_bytes')!), o(source), o(extras), o(ui2), o(option(options, 'clipboard')!))!
	port := call('operator.getitem', o(attribute(server, 'server_address')!), v(ah.Value(1)))!
	ready := option(options, 'ready_file')!
	if truth(ready)! {
		method(ready, 'write_text', [v(ah.Value(text(port)! + '\n'))], {
			'encoding': v(ah.Value('ascii'))
		})!
	}
	log('qemu-package-store: listening on 127.0.0.1:' + text(port)! + ', storing ' + text(attribute(server, 'destination')!)! + (if !compare('is_', source, null()!)! {
		', sharing ' + text(source)!
	} else {
		''
	}))!
	own(server, 'server_close')!
	method(server, 'serve_forever', [], {}) or {
		failure := err
		if kind(failure, 'interrupt') {
			close(server, none)!
			return
		}
		close(server, failure)!
		return failure
	}
	close(server, none)!
}

fn log_message(format_string string, args string) ! {
	message := call('operator.mod', o(format_string), o(args))!
	log('qemu-package-store: ' + text(message)!)!
}
