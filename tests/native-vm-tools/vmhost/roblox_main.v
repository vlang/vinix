// SPDX-License-Identifier: MIT
module vmhost

import gamehost
import os
import strconv

pub struct RobloxVerdict {
pub:
	status int
	lines  []string
}

pub fn roblox_verdict(work string, uploads string, version string, bytes []u8, drawn bool, strace bool) !RobloxVerdict {
	transcript := bytes.bytestr()
	for marker, message in {
		'KERNEL PANIC':        'The kernel panicked'
		'ROBLOX-WINDOWS-FAIL': 'Wine did not run in the guest, so the client was never started'
	} {
		if transcript.contains(marker) {
			return error(message + '; inspect ' + work + '/vinix.log')
		}
	}
	if !transcript.contains('ROBLOX-WINDOWS-DONE') {
		return error('The guest never finished its observation; inspect ' + work + '/vinix.log')
	}
	report := uploads + '/wine.log'
	mut lines := []string{}
	if os.exists(report) { lines = roblox_lines(gamehost.decode_utf8(os.read_bytes(report)!)) }
	mut output := []string{}
	if strace {
		if lines.any(!it.contains(' ')) { return error('malformed system-call trace line') }
		numbers := lines.map(it.all_after_last(' '))
		output << 'The client made ' + numbers.len.str() + ' system calls of its own that Linux does not have' + if numbers.len > 0 {
			', first ' + numbers[..if numbers.len < 4 { numbers.len } else { 4 }].join(', ')
		} else {
			''
		}
	} else {
		output << lines[if lines.len > 12 { lines.len - 12 } else { 0 }..].map('  ' + it)
	}
	alive := transcript.all_after_last('ROBLOX-WINDOWS-TICK').contains('ROBLOX-WINDOWS-ALIVE')
	output << 'Deployment ' + version + ': client ' + if alive { 'still running' } else { 'gone' } + ' at the end of the observation, ' + if drawn {
		'a drawn'
	} else {
		'an empty'
	} + ' display. Transcript: ' + work + '/vinix.log, uploads: ' + uploads
	return RobloxVerdict{if alive && drawn { 0 } else { 1 }, output}
}

fn roblox_lines(text string) []string {
	mut lines := []string{}
	mut line := ''
	mut after_cr := false
	for ch in text.runes() {
		if ch == `\n` && after_cr {
			after_cr = false
			continue
		}
		after_cr = ch == `\r`
		if ch in [`\n`, `\r`, `\v`, `\f`, 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029] {
			lines << line
			line = ''
		} else {
			line += ch.str()
		}
	}
	if line != '' { lines << line }
	return lines
}

pub fn roblox_cli(root string, argv []string) !int {
	options := roblox_options(root, argv)!
	if options.version_set && options.version == '' {
		return error('Not a Roblox deployment name: ')
	}
	gamehost.mkdir(options.work)!
	deployment := roblox_fetch(gamehost.Tools{ root: root }, options.work, options.version)!
	client := options.work + '/client/' + deployment.version
	roblox_stage(deployment.downloads, client)!
	guest_root := roblox_prepare(root, options, client, deployment.version)!
	uploads := options.work + '/uploads'
	gamehost.remove(uploads)!
	mut server := roblox_uploads(os.executable(), uploads, options.port)!
	defer { server.close() or {} }
	seconds := strconv.atof64(options.timeout, allow_overflow: true)!
	bytes := roblox_guest(options, guest_root, seconds)!
	server.close()!
	if options.shell { return 0 }
	mut frames := os.ls(uploads)!.filter(it.ends_with('.xwd'))
	frames.sort()
	mut drawn := false
	for frame in frames {
		candidate := roblox_xwd(uploads + '/' + frame, uploads + '/' + frame[..frame.len - 4] + '.png')!
		drawn = candidate || drawn
	}
	verdict := roblox_verdict(options.work, uploads, deployment.version, bytes, drawn, options.strace)!
	for line in verdict.lines { println(line) }
	return verdict.status
}
