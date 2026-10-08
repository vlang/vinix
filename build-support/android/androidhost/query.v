module androidhost

import json2
import encoding.hex

fn text(row map[string]Value, name string) !string {
	value := field(row, name)
	if value is string { return value }
	return error('TypeError: expected string query field ' + name)
}

pub fn query(request string) !string {
	row := json2.decode[Value](request, strict: true)!.object()
	operation := text(row, 'operation')!
	result := match operation {
		'digest' { Value(digest(text(row, 'path')!)!) }
		'relative' { Value(relative(field(row, 'name'))!) }
		'elf' {
			required := field(row, 'required')
			check_elf(text(row, 'path')!, required is bool && required as bool)!
			Value(json2.null)
		}
		'dex_info' {
			info := dex_info(hex.decode(text(row, 'data')!)!)!
			Value([Value(info.classes.map(Value(it))), Value(info.callsites)])
		}
		else { return error('unknown Android host operation ' + operation) }
	}
	return encode(result)
}

pub fn error_json(err IError) string {
	if err is FileError {
		return encode(Value(map[string]Value{
			'kind':     Value('OSError')
			'error':    Value(err.msg())
			'errno':    Value(err.code())
			'filename': Value(err.filename)
		}))
	}
	if err is AsciiError {
		return encode(Value(map[string]Value{
			'kind':     Value('UnicodeDecodeError')
			'encoding': Value('ascii')
			'object':   Value(err.bytes.hex())
			'start':    Value(err.start)
			'end':      Value(err.start + 1)
			'reason':   Value(err.msg())
		}))
	}
	if err.msg().starts_with('struct.error: ') {
		return encode(Value(map[string]Value{
			'kind':  Value('struct.error')
			'error': Value(err.msg()[14..])
		}))
	}
	if err.msg().starts_with('ValueError: ') {
		return encode(Value(map[string]Value{
			'kind':  Value('ValueError')
			'error': Value(err.msg()[12..])
		}))
	}
	if err.msg().starts_with('TypeError: ') {
		return encode(Value(map[string]Value{
			'kind':  Value('TypeError')
			'error': Value(err.msg()[11..])
		}))
	}
	return encode(Value(map[string]Value{
		'kind':  Value('RuntimeError')
		'error': Value(err.msg())
	}))
}
