// SPDX-License-Identifier: GPL-2.0-or-later
// Levels come from explicit leading markers in the retained plain-text log.
module main

import ui2

enum ConsoleSeverity { unmarked error warning info debug }
enum ConsoleSeverityFilter { all error warning info debug unmarked }

const console_severity_actions = ['console.severity.all', 'console.severity.error',
	'console.severity.warning', 'console.severity.info', 'console.severity.debug',
	'console.severity.unmarked']!
const console_severity_filters = [ConsoleSeverityFilter.all, ConsoleSeverityFilter.error,
	ConsoleSeverityFilter.warning, ConsoleSeverityFilter.info, ConsoleSeverityFilter.debug,
	ConsoleSeverityFilter.unmarked]!

// Compare a borrowed ASCII token without allocating a lowercase string.
fn console_severity_token_is(text string, start int, end int, token string) bool {
	if end - start != token.len { return false }
	for index in 0 .. token.len {
		byte := text[start + index]
		upper := if byte >= `a` && byte <= `z` { byte - 32 } else { byte }
		if upper != token[index] { return false }
	}
	return true
}

fn console_severity_token(text string, first int, last int) ConsoleSeverity {
	mut start := first
	mut end := last
	for start < end && text[start] == ` ` { start++ }
	for end > start && text[end - 1] == ` ` { end-- }
	if console_severity_token_is(text, start, end, 'ERROR')
		|| console_severity_token_is(text, start, end, 'FATAL')
		|| console_severity_token_is(text, start, end, 'CRITICAL') { return .error }
	if console_severity_token_is(text, start, end, 'WARN')
		|| console_severity_token_is(text, start, end, 'WARNING') { return .warning }
	if console_severity_token_is(text, start, end, 'INFO')
		|| console_severity_token_is(text, start, end, 'NOTICE') { return .info }
	if console_severity_token_is(text, start, end, 'DEBUG')
		|| console_severity_token_is(text, start, end, 'TRACE') { return .debug }
	return .unmarked
}

fn console_severity_timestamp(text string, start int, end int) bool {
	mut digit := false
	for at in start .. end {
		byte := text[at]
		if byte >= `0` && byte <= `9` { digit = true; continue }
		if byte != ` ` && byte != `.` && byte != `:` && byte != `/` && byte != `-`
			&& byte != `+` && byte != `T` && byte != `Z` { return false }
	}
	return digit
}

fn console_line_severity(text string, start int, end int) ConsoleSeverity {
	if start < 0 || end > text.len || end <= start { return .unmarked }
	mut at := start
	for at < end && text[at] == ` ` { at++ }
	if at == end { return .unmarked }
	if text[at] == `[` {
		mut close := at + 1
		limit := if end - at > 256 { at + 256 } else { end }
		for close < limit && text[close] != `]` { close++ }
		if close == limit { return .unmarked }
		// A bracketed level or colon-delimited prefix field is explicit metadata.
		mut field := at + 1
		for index in at + 1 .. close + 1 {
			if index == close || text[index] == `:` {
				level := console_severity_token(text, field, index)
				if level != .unmarked { return level }
				field = index + 1
			}
		}
		if !console_severity_timestamp(text, at + 1, close) { return .unmarked }
		at = close + 1
		for at < end && text[at] == ` ` { at++ }
	}
	// Xorg's explicit message marker can follow its bracketed timestamp.
	if end - at >= 4 && text[at] == `(` && text[at + 3] == `)` {
		if text[at + 1] == `E` && text[at + 2] == `E` { return .error }
		if text[at + 1] == `W` && text[at + 2] == `W` { return .warning }
		if text[at + 1] == `I` && text[at + 2] == `I` { return .info }
		if text[at + 1] == `D` && text[at + 2] == `B` { return .debug }
		return .unmarked
	}
	mut token_end := at
	for token_end < end && text[token_end] != ` ` && text[token_end] != `:` { token_end++ }
	return console_severity_token(text, at, token_end)
}

fn console_severity_matches(filter ConsoleSeverityFilter, severity ConsoleSeverity) bool {
	return match filter {
		.all { true }
		.error { severity == .error }
		.warning { severity == .warning }
		.info { severity == .info }
		.debug { severity == .debug }
		.unmarked { severity == .unmarked }
	}
}

fn console_severity_columns(width int) int {
	return if width >= 660 { 6 } else if width >= 340 { 3 } else if width >= 230 { 2 } else { 1 }
}

fn (a &ConsoleApp) severity_log_top(width int) int {
	columns := console_severity_columns(width)
	return 156 + ((console_severity_actions.len + columns - 1) / columns) * 34 + 8
}

fn (a &ConsoleApp) build_severity_controls(mut children []ui2.Element, width int) {
	columns := console_severity_columns(width)
	available := if width > 28 { width - 28 } else { 0 }
	button_width := if available >= (columns - 1) * 6 { (available - (columns - 1) * 6) / columns } else { 0 }
	for index, action in console_severity_actions {
		children << ui2.Element{
			...console_button(action, action, 14 + (index % columns) * (button_width + 6),
				156 + (index / columns) * 34, button_width, a.severity_filter == console_severity_filters[index])
			tooltip: tr('console.severity.help')
		}
	}
}
