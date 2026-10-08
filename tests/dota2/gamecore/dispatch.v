// SPDX-License-Identifier: GPL-2.0-or-later
module gamecore

import androidhost as ah
import json2

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	operation := ah.field(ah.field(row, 'arguments').object(), 'public_operation').text()
	match operation {
		'module' { return export(module_load('arg0', 'arg1')!) }
		'game_start_observed' { return ah.Value(started('arg0')!) }
		'screenshot' { return ah.Value(screenshot('arg0', 'arg1')!) }
		'stop_vm' { stop_vm('arg0', 'arg1')! }
		'reads_init' { reads_init('arg0', 'arg1')! }
		'reads_observe' { return export(reads_observe('arg0', 'arg1', 'arg2')!) }
		'reads_report' { return export(reads_report('arg0')!) }
		'boot' { main_policy('arg0')! }
		else { return error('unknown Dota guest controller operation') }
	}
	return ah.Value(json2.Null{})
}
