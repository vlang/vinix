// SPDX-License-Identifier: GPL-2.0-only
module nativepolicy

import hosttest

fn replace_word(text string, old string, replacement string) string {
	runes := text.runes()
	mut result := ''
	mut index := 0
	for index < runes.len {
		if !hosttest.module_word_rune(runes[index]) { result += runes[index].str(); index++; continue }
		start := index
		for index < runes.len && hosttest.module_word_rune(runes[index]) { index++ }
		word := runes[start..index].string()
		result += if word == old { replacement } else { word }
	}
	return result
}

// Adapt only the original register boundaries. The C control algorithms are
// copied verbatim, with the same first closing-line rule as the original regex.
pub fn reference_init(source string, kind string) !string {
	mut text := ''
	mut wrappers := ''
	mut index := 0
	prefix := 'static inline i64 syscall'
	for index < source.len {
		position := index + (source[index..].index(prefix) or { text += source[index..]; break })
		text += source[index..position]
		count_at := position + prefix.len
		mut matched := false
		if count_at + 2 < source.len && source[count_at] >= `1` && source[count_at] <= `5`
			&& source[count_at + 1] == `(` {
			line_end := count_at + (source[count_at..].index('\n') or { source.len - count_at })
			if header_end := source[count_at + 2..line_end].last_index(') {') {
				if header_end > 0 {
					body := count_at + 2 + header_end + ') {'.len
					if closing := source[body..].index('\n}') {
						count := int(source[count_at] - `0`)
						mut args := ['u64 nr']
						mut values := ['nr']
						for i in 0 .. 5 {
							if i < count { args << 'u64 a' + i.str() }
							values << if i < count { 'a' + i.str() } else { '0' }
						}
						wrappers += 'static inline i64 syscall' + count.str() + '(' + args.join(',') +
							') { return vinit_syscall(' + values.join(',') + '); }\n'
						index = body + closing + 2
						matched = true
					}
				}
			}
		}
		if !matched { text += prefix; index = count_at }
	}
	naked := '__attribute__((naked)) static void signal_restorer(void) {'
	mut start := 0
	for {
		position := start + (text[start..].index(naked) or { break })
		body := position + naked.len
		end := body + (text[body..].index('\n}') or { break }) + 2
		text = text[..position] + 'static void signal_restorer(void) {}' + text[end..]
		start = position + 'static void signal_restorer(void) {}'.len
	}
	text = text.replace('void _start(void)', 'void vinix_init_' + kind + '(void)')
	if kind == 'desktop' {
		text = text.replace('static volatile int requested_power_signal', 'volatile int vinit_power')
			.replace('static volatile int requested_desktop_reload', 'volatile int vinit_reload')
		text = replace_word(text, 'requested_power_signal', 'vinit_power')
		text = replace_word(text, 'requested_desktop_reload', 'vinit_reload')
		text = text.replace('static void power_signal_handler', 'void vinix_init_power_signal')
			.replace('static void child_signal_handler', 'void vinix_init_child_signal')
			.replace('power_signal_handler', 'vinix_init_power_signal')
			.replace('child_signal_handler', 'vinix_init_child_signal')
	}
	end := (text.index('typedef long i64;') or { return error('Missing original i64 declaration') }) +
		'typedef long i64;'.len
	text = text[..end] + '\nextern i64 vinit_syscall(u64,u64,u64,u64,u64,u64);\n' + wrappers + text[end..]
	if kind == 'desktop' {
		text += '\n#include <stdbool.h>\nvoid initcore__prepare_desktop_boot(void) { prepare_desktop_boot(); }\nvoid initcore__prepare_hosted_x11_storage(void) { prepare_hosted_x11_storage(); }\nvoid initcore__install_power_signals(void) { install_power_signals(); install_child_signal(); }\nvoid initcore__apply_power_request(void) { apply_power_request(); }\nvoid initcore__pause_for(struct kernel_timespec delay) { pause_for(delay); }\nvoid initcore__wait_for_child(i64 child,int *status) { wait_for_child(child,status); }\nvoid initcore__stop_desktop_group(i64 child) { stop_desktop_group(child); }\ni64 initcore__spawn_program(char **args,char **fallback,bool group,int *status,char **env,bool trace) { return spawn_program(args,fallback,group,status,env,trace); }\n'
	}
	return text
}
