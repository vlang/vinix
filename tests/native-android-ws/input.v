// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import qmpclient
import time

fn main() {
	if os.args.len != 4 { panic('usage: input QMP_SOCKET QCODE_OR_WHEEL_BUTTON COUNT') }
	count := os.args[3].int()
	if count < 1 || count > 1000 { panic('invalid tap count') }
	mut monitor := qmpclient.connect(os.args[1])!
	defer { monitor.close() }
	for _ in 0 .. count {
		mut events := []json2.Any{}
		for down in [true, false] {
			if os.args[2] in ['wheel-up', 'wheel-down'] {
				events << json2.Any({'type': json2.Any('btn'), 'data': json2.Any({
					'down': json2.Any(down), 'button': json2.Any(os.args[2])
				})})
			} else { events << json2.Any({
				'type': json2.Any('key')
				'data': json2.Any({
					'down': json2.Any(down)
					'key':  json2.Any({
						'type': json2.Any('qcode')
						'data': json2.Any(os.args[2])
					})
				})
			}) }
		}
		monitor.command('input-send-event', {
			'events': json2.Any(events)
		})!
		time.sleep(35 * time.millisecond)
	}
	time.sleep(time.second)
}
