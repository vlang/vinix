// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn calculator_display(element ui2.Element) ?string {
	if element.id == 'display' {
		return element.text
	}
	for child in element.children {
		if text := calculator_display(child) {
			return text
		}
	}
	return none
}

fn main() {
	if options := app_process_options(arguments()[1..]) {
		run_app_process(options)
		return
	}
	desktop_ignore_broken_pipe()
	factory := app_factory_named('vinix-calculator') or { panic('calculator missing') }
	mut desktop := Desktop{}
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	initial := app.build(ui2.rect(0, 0, 284, 364)) or { panic(err) }
	assert calculator_display(initial) or { panic('display missing') } == '0'
	free_tree(initial)
	for key in ['7', '+', '8', '='] {
		app.handle(key) or { panic(err) }
	}
	result := app.build(ui2.rect(0, 0, 284, 364)) or { panic(err) }
	assert calculator_display(result) or { panic('display missing') } == '15'
	free_tree(result)
	if mut app is RemoteApp {
		app.close()
		assert app.closed
	}
	println('APPLICATION CALCULATOR RPC PASS')
}
