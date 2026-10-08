module boothost

import androidhost as ah
import encoding.hex

// Keep raw integer spelling, non-finite float types, and owned WTF-8 strings.
pub fn unpack(value ah.Value) !ah.Value {
	pair := value.items()
	if pair.len != 2 { return error('invalid boot transport') }
	kind := pair[0].text()
	data := pair[1]
	return match kind {
		'string' { ah.Value(hex.decode(data.text())!.bytestr()) }
		'float' { ah.Value(ah.Number{data.text()}) }
		'list' { ah.Value(data.items().map(unpack(it)!)) }
		'dict' {
			mut row := map[string]ah.Value{}
			for entry in data.items() {
				fields := entry.items()
				if fields.len != 2 { return error('invalid boot dictionary transport') }
				row[unpack(fields[0])!.text()] = unpack(fields[1])!
			}
			ah.Value(row)
		}
		'value' { data }
		else { return error('invalid boot transport kind') }
	}
}

pub fn pack(value ah.Value) ah.Value {
	return match value {
		string { ah.Value([ah.Value('string'), ah.Value(value.bytes().hex())]) }
		ah.Number {
			if value.text in ['nan', 'inf', '-inf'] {
				ah.Value([ah.Value('float'), ah.Value(value.text)])
			} else {
				ah.Value([ah.Value('value'), value])
			}
		}
		[]ah.Value { ah.Value([ah.Value('list'), ah.Value(value.map(pack(it)))]) }
		map[string]ah.Value {
			mut items := []ah.Value{}
			for key, item in value { items << ah.Value([pack(ah.Value(key)), pack(item)]) }
			ah.Value([ah.Value('dict'), ah.Value(items)])
		}
		else { ah.Value([ah.Value('value'), value]) }
	}
}
