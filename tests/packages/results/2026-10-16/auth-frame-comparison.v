module authproto
#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>
#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.shutdown(i32, i32) i32
fn dispose(mut frame Frame) { frame.wipe(); unsafe { for field in frame.fields { field.free() }; (&array(&frame.fields)).free() }; frame = Frame{} }
fn discard(err IError) { text := err.msg(); unsafe { text.free(); err.free() } }
fn test_measure_framing_storage() {
	mut original := text_frame(op_run, 'packages-launch', '', '', 'a'.repeat(32), 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'z'.repeat(1024))
	defer { dispose(mut original) }
	encoded := encode(original)!
	defer { unsafe { encoded.free() } }
	labels := ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve']
	defer { unsafe { labels.free() } }
	for mode in 0 .. 7 {
		C.vinix_heap_begin()
		for _ in 0 .. 5 {
			if mode == 0 { output := encode(original)!; unsafe { output.free() } }
			if mode == 1 { mut decoded := decode(encoded)!; dispose(mut decoded) }
			if mode == 2 {
				if mut decoded := decode(unsafe { encoded[..encoded.len - 1] }) { dispose(mut decoded); assert false }
				else { discard(err) }
			}
			if mode in [3, 4, 5] {
				mut pair := [2]i32{}
				assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
				if mode == 3 {
					write_frame(int(pair[0]), original)!
					mut drain := []u8{len: encoded.len}
					assert C.read(pair[1], drain.data, usize(drain.len)) == drain.len
					unsafe { drain.free() }
				} else {
					count := if mode == 4 { encoded.len } else { encoded.len - 1 }
					assert C.write(pair[0], encoded.data, usize(count)) == count
					assert C.shutdown(pair[0], C.SHUT_WR) == 0
					if mode == 4 { mut decoded := read_frame(int(pair[1]))!; dispose(mut decoded) }
					else { if mut decoded := read_frame(int(pair[1])) { dispose(mut decoded); assert false } else { discard(err) } }
				}
				C.close(pair[0]); C.close(pair[1])
			}
			if mode == 6 { mut frame := text_frame(op_verify, ...labels); dispose(mut frame) }
		}
		kept := C.vinix_heap_end()
		println('AUTH FRAME probe ' + mode.str() + ' five cycles retained ' + kept.str() + ' bytes')
	}
}
