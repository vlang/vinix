// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

__global ws_surface_fields_count i32

// Read explicitly selected field paths on a surface, including inherited and
// private fields. Reflection boxes primitives. This diagnostic never writes
// fields, installs hooks, or runs application lifecycle callbacks.
// Paths are comma separated, with dots between fields. Bounds keep malformed
// requests and object descriptions from flooding the serial port.
fn ws_dump_surface_fields(e voidptr, view voidptr) {
	unsafe {
		paths := C.getenv(c'VINIX_ANDROID_TRACE_SURFACE_FIELDS')
		if paths == nil || ws_surface_fields_count >= 3 || pending(e) { return }
		ws_surface_fields_count++
		mut cursor := usize(0)
		for _ in 0 .. 16 {
			if paths[cursor] == 0 || cursor >= 4096 { break }
			mut path := [256]char{}
			mut size := usize(0)
			for paths[cursor] != 0 && paths[cursor] != `,` && cursor < 4096 {
				if size < 255 { path[size] = paths[cursor] }
				size++
				cursor++
			}
			if paths[cursor] == `,` { cursor++ }
			if size == 0 || size > 255 { continue }
			push_frame(e)
			mut value := view
			mut start := usize(0)
			mut valid := true
			for hop in 0 .. 16 {
				if value == nil {
					valid = false
					break
				}
				mut name := [256]char{}
				mut length := usize(0)
				for start < size && path[start] != `.` {
					name[length] = path[start]
					length++
					start++
				}
				if length == 0 {
					valid = false
					break
				}
				// Numeric components select a List or array element. Array.get
				// also boxes primitive array elements, like Field.get does.
				mut indexed := true
				mut index := i32(0)
				for n := usize(0); n < length; n++ {
					if name[n] < `0` || name[n] > `9` || index > 6553 {
						indexed = false
						break
					}
					index = index * 10 + i32(name[n] - `0`)
				}
				if indexed {
					if instance_of(e, value, c'java/util/List') {
						args := [Value{ i: index }]!
						value = obj(e, value, c'java/util/List', c'get', c'(I)Ljava/lang/Object;', &args[0])
					} else {
						args := [Value{ l: value }, Value{ i: index }]!
						value = static_obj(e, c'java/lang/reflect/Array', c'get', c'(Ljava/lang/Object;I)Ljava/lang/Object;', &args[0])
					}
				} else {
					name_args := [Value{ l: ws_string(e, &name[0]) }]!
					mut cls := WsObjectClass(slot(e, 31))(e, value)
					mut member := voidptr(nil)
					for _ in 0 .. 16 {
						if cls == nil { break }
						member = obj(e, cls, c'java/lang/Class', c'getDeclaredField', c'(Ljava/lang/String;)Ljava/lang/reflect/Field;', &name_args[0])
						if !pending(e) { break }
						ExceptionClear(slot(e, 17))(e)
						cls = obj(e, cls, c'java/lang/Class', c'getSuperclass', c'()Ljava/lang/Class;', nil)
					}
					if member == nil || pending(e) {
						valid = false
						break
					}
					access := [Value{ i: 1 }]!
					call(e, member, c'java/lang/reflect/Field', c'setAccessible', c'(Z)V', &access[0])
					if pending(e) {
						valid = false
						break
					}
					owner := [Value{ l: value }]!
					value = obj(e, member, c'java/lang/reflect/Field', c'get', c'(Ljava/lang/Object;)Ljava/lang/Object;', &owner[0])
				}
				if pending(e) {
					valid = false
					break
				}
				if start == size { break }
				start++
				if hop == 15 { valid = false }
			}
			if valid && !pending(e) {
				args := [Value{ l: value }]!
				text := static_obj(e, c'java/lang/String', c'valueOf', c'(Ljava/lang/Object;)Ljava/lang/String;', &args[0])
				if !pending(e) {
					chars := ws_utf(e, text)
					if !pending(e) {
						C.printf(c'ANDROID-WS-SURFACE-FIELD path=%s value=%.1024s\n', &path[0], chars)
						ws_release(e, text, chars)
					}
				}
			}
			if !valid || pending(e) {
				C.printf(c'ANDROID-WS-SURFACE-FIELD path=%s unavailable\n', &path[0])
			}
			if pending(e) { ExceptionClear(slot(e, 17))(e) }
			pop_frame(e)
		}
	}
}
