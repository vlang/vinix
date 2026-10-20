// SPDX-License-Identifier: GPL-2.0-or-later
import json2
import os
import qmpclient
import time

fn main() {
 if os.args.len < 3 { panic('usage: qmp-keys SOCKET QCODE [QCODE...]') }
 mut monitor := qmpclient.connect(os.args[1])!
 defer { monitor.close() }
 mut keys := []json2.Any{}
 for key in os.args[2..] { keys << json2.Any({'type': json2.Any('qcode'), 'data': json2.Any(key)}) }
 monitor.command('send-key', {'keys': json2.Any(keys), 'hold-time': json2.Any(80)})!
 time.sleep(250 * time.millisecond)
}
