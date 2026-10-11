// SPDX-License-Identifier: GPL-2.0-or-later
import hosttest
import json2
import net.unix
import os
import policyhost
import screenhost
import screenshotcore
import time

#include <fcntl.h>

fn C.fcntl(int, int, ...int) int

fn fd_count() int {
	mut count := 0
	for fd in 0 .. 1024 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn line(mut connection unix.StreamConn) !string {
	mut result := []u8{}
	for {
		mut byte := [1]u8{}
		if connection.read(mut byte)! != 1 { return error('Unexpected EOF') }
		result << byte[0]
		if byte[0] == 10 { return result.bytestr() }
	}
	return error('unreachable')
}

fn qmp_model(mut listener unix.StreamListener, kind string) ! {
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	connection.set_read_timeout(3 * time.second)
	connection.write_string('{"QMP":{}}\n')!
	assert json2.decode[json2.Any](line(mut connection)!)!.as_map()['execute']!.str() == 'qmp_capabilities'
	connection.write_string('{"event":"RESET"}\n{"return":{}}\n')!
	request := json2.decode[json2.Any](line(mut connection)!)!.as_map()
	assert request['execute']!.str() == 'screendump'
	if kind == 'eof' { return }
	if kind == 'error' {
		connection.write_string('{"error":{"class":"GenericError","desc":"display unavailable"}}\n')!
		return
	}
	if kind == 'malformed' {
		connection.write_string('broken json\n')!
		return
	}
	path := request['arguments']!.as_map()['filename']!.str()
	if kind == 'pixels' {
		mut data := 'P6\n# actual QMP fixture\n2 1\n255\n'.bytes()
		data << [u8(0), 10, 32, 255, 127, 1]
		os.write_file_array(path, data)!
	}
	connection.write_string('{"event":"STOP"}\n{"return":{}}\n')!
}

fn checked() ! {
	guard := policyhost.own_commands()
	defer { guard.close() }
	work := hosttest.work_dir('', 'vinix-screen-check-')!
	defer { hosttest.remove_work_dir(work) or {} }
	before := fd_count()
	for kind in ['pixels', 'error', 'eof', 'malformed', 'empty'] {
		mut suffixes := if kind == 'pixels' { ['png', 'ppm', 'PNG'] } else { ['png'] }
		if kind == 'pixels' && os.exists('/opt/homebrew/bin/magick') {
			suffixes << ['bmp', 'gif', 'tiff', 'jpg']
		}
		for suffix in suffixes {
			socket := work + '/qmp.sock'
			mut listener := unix.listen_stream(socket, unix.ListenOptions{})!
			listener.set_accept_timeout(3 * time.second)
			worker := spawn qmp_model(mut listener, kind)
			target := work + '/screen.' + suffix
			mut failure := ''
			screenhost.capture(socket, target) or { failure = err.msg() }
			worker.wait()!
			listener.close()!
			os.rm(socket) or {}
			assert (failure == '') == (kind == 'pixels')
			if kind == 'pixels' {
				mut decoded := target
				if suffix !in ['png', 'ppm', 'PNG'] {
					decoded = work + '/decoded.png'
					policyhost.inherited(['magick', target, '-depth', '8', '-define', 'png:color-type=2',
						'PNG:' + decoded])!
				}
				image := screenshotcore.read(decoded)!
				assert image.width == 2 && image.height == 1 && image.channels == 3
				if suffix != 'jpg' {
					assert image.pixels == [u8(0), 10, 32, 255, 127, 1]
				} else {
					assert os.read_bytes(target)![..2] == [u8(0xff), 0xd8]
				}
				if decoded != target { os.rm(decoded)! }
				os.rm(target)!
			}
		}
	}
	assert fd_count() == before
	println('PASS native screenshots: real QMP exchange, events, exact RGB/PNG/PPM bytes, malformed/error/EOF/missing output and FD retirement')
}

fn main() {
	checked() or {
		eprintln(err)
		exit(1)
	}
}
