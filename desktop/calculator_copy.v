// SPDX-License-Identifier: GPL-2.0-or-later
// Copy snapshots the displayed number; arithmetic and history stay independent.
module main

import ui2

fn (app &CalculatorApp) copy_value() string {
	if app.programmer {
		return if app.integer.has_error { '' } else { app.integer.text(app.integer.base) }
	}
	value := app.calculator.display
	return if !app.calculator.has_error
		&& (calculator_valid_number(value) || calculator_valid_scientific_number(value)) {
		value
	} else { '' }
}

fn (mut app CalculatorApp) copy_result() {
	// Empty input also invalidates a superseded copy's acknowledgement, without
	// placing an arithmetic error or a non-finite display onto the clipboard.
	app.copy_client.queue(app.copy_value())
}

fn (mut app CalculatorApp) take_clipboard_copy_request() []u8 {
	return app.copy_client.take_request()
}

fn (mut app CalculatorApp) receive_clipboard_copy_reply(payload string) {
	app.copy_client.receive_reply(payload)
}

// Text and tooltips borrow translated strings or the model's fixed status key.
fn (app &CalculatorApp) copy_controls(mut children []ui2.Element, button ui2.Rect, status ui2.Rect) {
	key := app.copy_client.status_key()
	button_feedback := key.len > 0 && status.width <= 0
	label := tr(if button_feedback { key } else { 'calculator.copy' })
	children << ui2.Element{
		...ui2.button('calculator.copy', label, button,
			ui2.BoxStyle{ bg: settings_choice_bg, radius: 5 },
			ui2.TextStyle{ color: body_text, size: if button.width < 116 { 9 } else { 11 }, align: .center })
		id: if button_feedback { 'calculator.copy.status' } else { 'calculator.copy' }
		action_id: 'calculator.copy'
		tooltip: tr(if key.len > 0 { key } else { 'calculator.copy' })
	}
	if key.len > 0 && status.width > 0 {
		children << ui2.Element{
			...ui2.label('calculator.copy.status', tr(key), status,
				ui2.TextStyle{ size: 11, color: if key == 'clipboard.copy.copied' { app_accent }
					else { body_muted } })
			tooltip: tr(key)
		}
	}
}
