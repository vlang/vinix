// SPDX-License-Identifier: GPL-2.0-or-later
module lavacore

import androidhost as ah
import json2

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	id := match ah.field(row, 'operation').text() {
		'digest' { digest('arg0')! }
		'elf_input' { elf('arg0', 'arg1', 'arg2')! }
		'install_pin' { pin('arg0', 'arg1')!; return ah.Value(json2.Null{}) }
		'needed' { needed('arg0', 'arg1')! }
		'runtime_closure' { closure('arg0', 'arg1', 'arg2')! }
		'verdict' { verdict('arg0', 'arg1', 'arg2')! }
		'main' { main_policy('arg0', 'arg1')!; return ah.Value(json2.Null{}) }
		else { return error('unknown Lavapipe controller operation') }
	}
	return export(id)
}
