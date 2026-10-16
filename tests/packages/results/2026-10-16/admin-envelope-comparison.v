module pkgadmin

#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn probe_error(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }
fn test_admin_protocol_comparison() {
	request := Request{ nonce: '0123456789abcdef0123456789abcdef', arguments: ['apply', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'install', 'example.app'] }
	text := request.encode()!
	mut warm := decode(text)!; warm.close()
	receipt := request.receipt(37)
	partial := text.replace('"example.app"', '17')
	invalid := receipt + 'x'
	for mode in 0 .. 6 {
		C.vinix_heap_begin()
		for _ in 0 .. 5 {
			match mode {
				0 { encoded := request.encode()!; unsafe { encoded.free() } }
				1 { mut decoded := decode(text)!; decoded.close() }
				2 { if mut decoded := decode(partial) { decoded.close(); assert false } else { probe_error(err) } }
				3 { value := request.receipt(37); unsafe { value.free() } }
				4 { assert request.result(receipt)! == 37 }
				else { if _ := request.result(invalid) { assert false } else { probe_error(err) } }
			}
		}
		kept := C.vinix_heap_end()
		label := match mode { 0 { 'encode' } 1 { 'decode' } 2 { 'partial refusal' } 3 { 'receipt' } 4 { 'result' } else { 'result refusal' } }
		println('ADMIN PROTOCOL ' + label + ' retained ' + kept.str() + ' bytes')
	}
}
