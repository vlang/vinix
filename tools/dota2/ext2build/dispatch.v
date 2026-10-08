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
		'identity' { return ah.Value(identity(args[0])!) }
		'same_source' { return ah.Value(same_source(args[0], args[1])!) }
		'export_initialize' { export_initialize(args[0], args[1])! }
		'close' { export_close(args[0])! }
		'read_source' { return ah.Value(read_source(args[0], args[1], args[2], args[3])!) }
		'read' { return ah.Value(disk_read(args[0], args[1], args[2])!) }
		'receive' { return ah.Value(receive(args[0], args[1])!) }
		'option_reply' {
			data := if args.len > 3 {
				args[3]
			} else {
				callback('literal', {
					'value': b('')
				})!.text()
			}
			option_reply(args[0], args[1], args[2], data)!
		}
		'negotiate' { return ah.Value(negotiate(args[0])!) }
		'handle' { handle(args[0])! }
		else { return error('unknown ext2 construction operation') }
	}
	return ah.Value(json2.Null{})
}
