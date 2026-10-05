module kprint

import dev.serial
import term

fn policy_serial(character u8, panic bool) {
	if panic { serial.panic_out(character) } else { serial.out(character) }
}

fn policy_terminal(text &char, len u64) { term.print(text, len) }
