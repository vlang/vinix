// SPDX-License-Identifier: GPL-2.0-or-later
module ext2build

import androidhost as ah
import json2

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'rounded' { return ah.Value(rounded(args[0], args[1])!) }
		'pointer_count' { return ah.Value(pointer_count(args[0])!) }
		'backup_group' { return ah.Value(backup_group(args[0])!) }
		'scan' { return ah.Value(scan(args[0], if args.len > 1 { args[1] } else { null()! })!) }
		'flatten' { return ah.Value(flatten(args[0])!) }
		'directory_data' { return ah.Value(directory_data(args[0])!) }
		'initialize' { initialize(args[0], args[1], args[2])! }
		'allocate' { return ah.Value(allocate(args[0], args[1])!) }
		'write' { write(args[0], args[1], args[2])! }
		'address_tree' { return ah.Value(address_tree(args[0], args[1])!) }
		'add_node' { add_node(args[0], args[1])! }
		'finish' { return ah.Value(finish(args[0])!) }
		'build' { return ah.Value(build(args[0], args[1], args[2])!) }
		else { return error('unknown ext2 construction operation') }
	}
	return ah.Value(json2.Null{})
}
