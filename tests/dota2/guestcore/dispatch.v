// SPDX-License-Identifier: GPL-2.0-or-later
module guestcore

import androidhost as ah
import json2

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	operation := ah.field(ah.field(row, 'arguments').object(), 'public_operation').text()
	match operation {
		'env-digest' { return export(digest('arg0')!) }
		'env-elf_input' { return export(elf('arg0', 'arg1', 'arg2')!) }
		'env-runtime_candidate' { return export(runtime_candidate('arg0', 'arg1', 'arg2')!) }
		'env-runtime_inputs' { return export(runtime_inputs('arg0')!) }
		'env-install_pin' { pin('arg0', 'arg1')! }
		'env-main' { env_main('arg0', 'arg1', 'arg2')! }
		else { return error('unknown native guest workflow operation') }
	}
	return ah.Value(json2.Null{})
}
