module authproto
import crypto.sha256
fn compat_dispose(mut frame Frame) { frame.wipe(); unsafe { for field in frame.fields { field.free() }; (&array(&frame.fields)).free() } }
fn compat_error(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }
fn test_wire_and_acceptance_compatibility() {
	for code in [u16(0), 1, 2, 3, 4, 5, 65535]! {
		for count in 0 .. max_fields + 1 {
			for kind in 0 .. 3 {
				mut frame := Frame{ code: code, fields: [][]u8{cap: count} }
				unsafe { frame.fields.flags |= .noslices }
				for index in 0 .. count {
					length := if kind == 0 { index % 5 } else if kind == 1 { 256 } else { max_field }
					field := []u8{len: length, init: u8(it % 256)}
					unsafe { frame.fields.push_many(&field, 1) }
				}
				bytes := encode(frame)!
				mut decoded := decode(bytes)!
				assert decoded.code == code && decoded.fields == frame.fields
				println('AUTH COMPAT ' + code.str() + ' fields=' + count.str() + ' kind=' + kind.str() + ' bytes=' + bytes.len.str() + ' sha256=' + sha256.sum(bytes).hex())
				compat_dispose(mut decoded); compat_dispose(mut frame); unsafe { bytes.free() }
			}
		}
	}
	mut source := text_frame(op_verify, 'alex', 'secret', 'tail')
	bytes := encode(source)!
	for cut in 0 .. bytes.len {
		if mut accepted := decode(unsafe { bytes[..cut] }) { compat_dispose(mut accepted); assert false }
		else { compat_error(err) }
		println('AUTH COMPAT truncated=' + cut.str() + ' REFUSE')
	}
	for index in [0, 4, 8, 11, 12, 15, 20, 23, 30, 33]! {
		mut bad := bytes.clone(); bad[index] = 255
		if mut accepted := decode(bad) { compat_dispose(mut accepted); assert false }
		else { compat_error(err) }
		println('AUTH COMPAT malformed=' + index.str() + ' REFUSE')
		unsafe { bad.free() }
	}
	compat_dispose(mut source); unsafe { bytes.free() }
}
