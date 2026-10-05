module kprint

import aarch64.uart
import term

fn policy_serial(character u8, _ bool) { uart.putc(character) }

fn policy_terminal(text &char, len u64) { term.print(text, len) }
