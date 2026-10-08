// SPDX-License-Identifier: GPL-2.0-or-later
module vkcore

import androidhost as ah
import json2

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	operation := ah.field(row, 'operation').text()
	if operation == 'prepare' { return export(prepare('arg0', 'arg1')!) }
	match operation {
		'copy_layer' { copy_layer('arg0', 'arg1')! }
		'complete_native_closure' { closure('arg0')! }
		'install_native_translator' { install_translator('arg0', 'arg1')! }
		'retain_software_gl' { retain_gl('arg0', 'arg1')! }
		'boot' { main_policy('arg0')! }
		else { return error('unknown Vulkan guest controller operation') }
	}
	return ah.Value(json2.Null{})
}
