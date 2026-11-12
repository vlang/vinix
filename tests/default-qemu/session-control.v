// SPDX-License-Identifier: GPL-2.0-or-later
// Input for the disposable session diagnostic image.
import os
import time
import json2

fn qmp(request string) {
	helper := os.getenv_opt('VINIX_QMP_HELPER') or { '/tmp/vinix-qmp' }
	result := os.exec([helper, 'qmp', os.args[1], request])
	if result.exit_code != 0 { panic('QMP failed: ' + result.output) }
}

fn move(x int, y int) {
	qmp('{"execute":"input-send-event","arguments":{"events":[{"type":"rel","data":{"axis":"x","value":${x}}},{"type":"rel","data":{"axis":"y","value":${y}}}]}}')
	time.sleep(500 * time.millisecond)
}

fn main() {
	if os.args.len < 3 { panic('SOCKET hover | click X Y | shot PATH | keys KEY...') }
	match os.args[2] {
		'hover' {
			move(-2000, -2000)
			time.sleep(2 * time.second)
			move(60, 125)
			for _ in 0 .. 20 { move(0, 80); move(0, -80) }
		}
		'click' {
			move(-2000, -2000)
			move(os.args[3].int(), os.args[4].int())
			qmp('{"execute":"input-send-event","arguments":{"events":[{"type":"btn","data":{"button":"left","down":true}}]}}')
			time.sleep(time.second)
			qmp('{"execute":"input-send-event","arguments":{"events":[{"type":"btn","data":{"button":"left","down":false}}]}}')
		}
		'shot' {
			qmp('{"execute":"screendump","arguments":{"filename":${json2.encode(os.args[3])}}}')
		}
		'keys' {
			for key in os.args[3..] {
				qmp('{"execute":"human-monitor-command","arguments":{"command-line":${json2.encode('sendkey ' + key)}}}')
				time.sleep(150 * time.millisecond)
			}
		}
		else { panic('hover | click X Y | shot PATH | keys KEY...') }
	}
}
