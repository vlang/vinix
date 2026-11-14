// SPDX-License-Identifier: GPL-2.0-or-later
// Raw bitmap storage transfer. The synchronized Java wrapper owns the bitmap
// monitor and advances the destination in elements only after a successful copy.
@[translated]
module atlframework

type WsBitmapBufferInstance = fn (voidptr, voidptr, voidptr) u8
type WsBitmapBufferAddress = fn (voidptr, voidptr) voidptr
type WsBitmapBufferCapacity = fn (voidptr, voidptr) i64
type WsBitmapBufferCritical = fn (voidptr, voidptr, voidptr) voidptr
type WsBitmapBufferRelease = fn (voidptr, voidptr, voidptr, i32)

fn C.memmove(voidptr, voidptr, usize) voidptr

fn ws_bitmap_buffer_shift(e voidptr, object voidptr, array bool) i32 {
	unsafe {
		names := if array {
			[&char(c'[B'), &char(c'[S'), &char(c'[I')]!
		} else {
			[&char(c'java/nio/ByteBuffer'), &char(c'java/nio/ShortBuffer'), &char(c'java/nio/IntBuffer')]!
		}
		for index, name in names {
			kind := cls(e, name)
			if kind == nil { return -1 }
			if pending(e) { Drop(slot(e, 23))(e, kind); return -1 }
			matches := WsBitmapBufferInstance(slot(e, 32))(e, object, kind) != 0
			Drop(slot(e, 23))(e, kind)
			if pending(e) { return -1 }
			if matches { return i32(index) }
		}
		throw(e, c'java/lang/RuntimeException', c'Unsupported bitmap buffer storage')
		return -1
	}
}

// Android's heap ByteBufferAs{Short,Int}Buffer has no public array. Its
// immutable bb/offset fields identify the byte storage without changing either
// buffer's position. Validate both the view and the backing array bounds.
fn ws_bitmap_buffer_view(e voidptr, destination voidptr, shift i32, position i32, size i64, offset &i64) voidptr {
	unsafe {
		if shift != 1 && shift != 2 { return nil }
		name := if shift == 1 { &char(c'java/nio/ByteBufferAsShortBuffer') } else { &char(c'java/nio/ByteBufferAsIntBuffer') }
		kind := cls(e, name)
		defer { if kind != nil { Drop(slot(e, 23))(e, kind) } }
		if kind == nil || pending(e) { return nil }
		matches := WsBitmapBufferInstance(slot(e, 32))(e, destination, kind) != 0
		if pending(e) || !matches { return nil }
		base := get_object(e, destination, name, c'bb', c'Ljava/nio/ByteBuffer;')
		defer { if base != nil { Drop(slot(e, 23))(e, base) } }
		if base == nil || pending(e) { return nil }
		view_offset := get_int(e, destination, name, c'offset')
		if pending(e) { return nil }
		base_capacity := integer(e, base, c'java/nio/Buffer', c'capacity', c'()I', nil)
		if pending(e) { return nil }
		start := i64(view_offset) + (i64(position) << shift)
		if view_offset < 0 || base_capacity < 0 || start + size > base_capacity {
			throw(e, c'java/lang/RuntimeException', c'Invalid bitmap buffer view range'); return nil
		}
		array_offset := integer(e, base, c'java/nio/ByteBuffer', c'arrayOffset', c'()I', nil)
		if pending(e) { return nil }
		if array_offset < 0 { throw(e, c'java/lang/RuntimeException', c'Invalid bitmap buffer backing offset'); return nil }
		args := &Value(C.alloca(sizeof(Value)))
		args[0] = Value{l: base}
		array := static_obj(e, c'java/nio/NIOAccess', c'getBaseArray', c'(Ljava/nio/Buffer;)Ljava/lang/Object;', args)
		*offset = i64(array_offset) + start
		return array
	}
}

fn ws_bitmap_copy_to_buffer(e voidptr, pointer i64, destination voidptr, format i32, stride i32) {
	unsafe {
		if pending(e) { return }
		if pointer == 0 { throw(e, c'java/lang/IllegalStateException', c'Bitmap has no pixels'); return }
		if destination == nil { throw(e, c'java/lang/NullPointerException', c'Bitmap buffer'); return }
		bitmap := &WsBitmap(pointer)
		channels := if bitmap.alpha_only { i64(1) } else { i64(4) }
		if bitmap.rgba == nil || bitmap.width <= 0 || bitmap.height <= 0
			|| bitmap.width > 16384 || bitmap.height > 16384
			|| i64(bitmap.width) * bitmap.height > 64 * 1024 * 1024
			|| stride != bitmap.row_bytes || stride != ((i64(bitmap.width) * channels + 3) & ~i64(3))
			|| format != (if bitmap.alpha_only { 24 } else { 5 }) {
			throw(e, c'java/lang/IllegalArgumentException', c'Invalid bitmap buffer layout'); return
		}
		size := i64(bitmap.row_bytes) * bitmap.height
		shift := ws_bitmap_buffer_shift(e, destination, false)
		if shift < 0 || pending(e) { return }
		position := integer(e, destination, c'java/nio/Buffer', c'position', c'()I', nil)
		if pending(e) { return }
		remaining := integer(e, destination, c'java/nio/Buffer', c'remaining', c'()I', nil)
		if pending(e) { return }
		capacity := integer(e, destination, c'java/nio/Buffer', c'capacity', c'()I', nil)
		if pending(e) { return }
		if position < 0 || remaining < 0 || capacity < position || remaining > capacity - position
			|| size > (i64(remaining) << shift) {
			throw(e, c'java/lang/RuntimeException', c'Bitmap buffer is too small'); return
		}
		read_only := boolean(e, destination, c'java/nio/Buffer', c'isReadOnly', c'()Z', nil) != 0
		if pending(e) { return }
		if read_only {
			exception := new_object(e, c'java/nio/ReadOnlyBufferException', c'()V', nil)
			if exception != nil {
				if !pending(e) { ExceptionThrow(slot(e, 13))(e, exception) }
				Drop(slot(e, 23))(e, exception)
			}
			return
		}
		direct := WsBitmapBufferAddress(slot(e, 230))(e, destination)
		if pending(e) { return }
		if direct != nil {
			available := WsBitmapBufferCapacity(slot(e, 231))(e, destination)
			if pending(e) { return }
			if available < position || available > 0x7fffffff || size > ((available - position) << shift) {
				throw(e, c'java/lang/RuntimeException', c'Invalid direct bitmap buffer capacity'); return
			}
			C.memmove(&u8(direct) + (i64(position) << shift), bitmap.rgba, usize(size))
			return
		}
		args := [Value{l: destination}]!
		mut array := static_obj(e, c'java/nio/NIOAccess', c'getBaseArray', c'(Ljava/nio/Buffer;)Ljava/lang/Object;', &args[0])
		defer { if array != nil { Drop(slot(e, 23))(e, array) } }
		if pending(e) { return }
		mut offset := i64(0)
		if array == nil {
			array = ws_bitmap_buffer_view(e, destination, shift, position, size, &offset)
		} else {
			nio := cls(e, c'java/nio/NIOAccess')
			defer { if nio != nil { Drop(slot(e, 23))(e, nio) } }
			if nio == nil || pending(e) { return }
			member := Member(slot(e, 113))(e, nio, c'getBaseArrayOffset', c'(Ljava/nio/Buffer;)I')
			if member == nil || pending(e) { return }
			offset = IntCall(slot(e, 131))(e, nio, member, &args[0])
		}
		if pending(e) { return }
		if array == nil { throw(e, c'java/lang/RuntimeException', c'Bitmap buffer has no accessible storage'); return }
		array_shift := ws_bitmap_buffer_shift(e, array, true)
		if array_shift < 0 || pending(e) { return }
		count := ws_array_len(e, array)
		if pending(e) { return }
		if offset < 0 || count < 0 || i64(offset) + size > (i64(count) << array_shift) {
			throw(e, c'java/lang/RuntimeException', c'Invalid bitmap buffer array range'); return
		}
		pinned := WsBitmapBufferCritical(slot(e, 222))(e, array, nil)
		if pinned == nil {
			if !pending(e) { throw(e, c'java/lang/OutOfMemoryError', c'Bitmap buffer storage') }
			return
		}
		// No JNI operation occurs while the primitive storage is pinned.
		C.memmove(&u8(pinned) + offset, bitmap.rgba, usize(size))
		WsBitmapBufferRelease(slot(e, 223))(e, array, pinned, 0)
	}
}
