// SPDX-License-Identifier: GPL-2.0-or-later
module atlframework

type IcuCount = fn () i32
type IcuName = fn (i32) &char
type FramePush = fn (voidptr, i32) i32
type FramePop = fn (voidptr, voidptr) voidptr
type ExceptionGet = fn (voidptr) voidptr
type ExceptionClear = fn (voidptr)
type ExceptionThrow = fn (voidptr, voidptr) i32
type ObjectArrayNew = fn (voidptr, i32, voidptr, voidptr) voidptr

// ICU 78 exposes converter variants such as x-UTF-16,version=1. The older
// ART/libcore provider cannot construct Java Charset objects for all of them.
// Enumerate only converters that the actual provider successfully constructs;
// otherwise Charset.availableCharsets() fails before returning any encodings.
fn available_charsets(e voidptr, _class voidptr) voidptr {
    unsafe {
        count_fn := IcuCount(C.dlsym(nil, c'ucnv_countAvailable_78'))
        name_fn := IcuName(C.dlsym(nil, c'ucnv_getAvailableName_78'))
        if voidptr(count_fn) == nil || voidptr(name_fn) == nil {
            throw(e, c'java/lang/IllegalStateException', c'pinned ICU 78 converter API is unavailable')
            return nil
        }
        invalid := cls(e, c'java/nio/charset/IllegalCharsetNameException')
        names := new_object(e, c'java/util/ArrayList', c'()V', nil)
        count := count_fn()
        mut args := &Value(C.alloca(sizeof(Value)))
        for index := i32(0); index < count && !pending(e); index++ {
            if FramePush(slot(e, 19))(e, 32) != 0 { return nil }
            args[0] = Value{l: string_value(e, name_fn(index))}
            charset := static_obj(e, c'libcore/icu/NativeConverter', c'charsetForName', c'(Ljava/lang/String;)Ljava/nio/charset/Charset;', args)
            if pending(e) {
                exception := ExceptionGet(slot(e, 15))(e)
                ExceptionClear(slot(e, 17))(e)
                // Only this known provider incompatibility is recoverable.
                recoverable := InstanceOf(slot(e, 32))(e, exception, invalid)
                if recoverable == 0 { ExceptionThrow(slot(e, 13))(e, exception) }
                FramePop(slot(e, 20))(e, nil)
                if recoverable == 0 { return nil }
                continue
            }
            if charset != nil {
                name := obj(e, charset, c'java/nio/charset/Charset', c'name', c'()Ljava/lang/String;', nil)
                args[0] = Value{l: name}
                boolean(e, names, c'java/util/ArrayList', c'add', c'(Ljava/lang/Object;)Z', args)
            }
            FramePop(slot(e, 20))(e, nil)
        }
        if pending(e) { return nil }
        strings := ObjectArrayNew(slot(e, 172))(e, 0, cls(e, c'java/lang/String'), nil)
        args[0] = Value{l: strings}
        return obj(e, names, c'java/util/ArrayList', c'toArray', c'([Ljava/lang/Object;)[Ljava/lang/Object;', args)
    }
}

fn register_charsets(e voidptr) i32 {
    methods := [NativeMethod{c'getAvailableCharsetNames', c'()[Ljava/lang/String;', voidptr(available_charsets)}]!
    return register(e, c'libcore/icu/NativeConverter', unsafe { &methods[0] }, 1)
}
