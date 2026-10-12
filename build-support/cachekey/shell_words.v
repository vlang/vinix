// SPDX-License-Identifier: GPL-2.0-or-later
module cachekey

// POSIX shlex.split rules for the existing compiler override. This produces
// argv only; substitutions and shell execution are never performed.
pub fn shell_words(text string) ![]string {
	mut words := []string{}
	mut word := ''
	mut quote := u8(0)
	mut escaped := false
	mut started := false
	for ch in text.bytes() {
		if escaped {
			if quote == `"` && ch !in [u8(`"`), `\\`] { word += '\\' }
			word += ch.ascii_str()
			escaped = false
			started = true
			continue
		}
		if quote == `'` {
			if ch == `'` { quote = 0 } else { word += ch.ascii_str() }
			continue
		}
		if ch == `\\` {
			escaped = true
			started = true
			continue
		}
		if quote == `"` {
			if ch == `"` { quote = 0 } else { word += ch.ascii_str() }
			continue
		}
		if ch in [u8(`'`), `"`] {
			quote = ch
			started = true
			continue
		}
		if ch in [u8(` `), `\t`, `\n`, `\r`] {
			if started {
				words << word
				word = ''
				started = false
			}
			continue
		}
		word += ch.ascii_str()
		started = true
	}
	if escaped { return error('No escaped character') }
	if quote != 0 { return error('No closing quotation') }
	if started { words << word }
	return words
}
