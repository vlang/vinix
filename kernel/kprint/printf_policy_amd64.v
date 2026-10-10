module kprint

import dev.serial
import term

fn policy_serial(character u8, panic bool) {
	if panic { serial.panic_out(character) } else { serial.out(character) }
}

fn policy_terminal(text &char, len u64) { term.print(text, len) }

// A panic is to be read: it lights a screen that is dark for a sleep.
fn policy_panic_terminal(text &char, len u64) {
	term.screen_for_panic()
	term.print(text, len)
}
