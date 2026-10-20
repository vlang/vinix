// SPDX-License-Identifier: GPL-2.0-or-later
// JNI's stable C ABI. No Java objects are retained outside GC-owned fields.
@[translated]
module atlframework

#include <dlfcn.h>
#include <stdio.h>

fn C.dlsym(voidptr, &char) voidptr
fn C.fputs(&char, voidptr) i32
fn C.puts(&char) i32

union Value {
mut:
    l voidptr
    i i32
    j i64
    f f32
    d f64
}

struct NativeMethod {
    name &char
    signature &char
    function voidptr
}

type Lookup = fn (voidptr, &char) voidptr
type Member = fn (voidptr, voidptr, &char, &char) voidptr
type ObjectCall = fn (voidptr, voidptr, voidptr, &Value) voidptr
type VoidCall = fn (voidptr, voidptr, voidptr, &Value)
type IntCall = fn (voidptr, voidptr, voidptr, &Value) i32
type BoolCall = fn (voidptr, voidptr, voidptr, &Value) u8
type ObjectField = fn (voidptr, voidptr, voidptr) voidptr
type PutObject = fn (voidptr, voidptr, voidptr, voidptr)
type IntField = fn (voidptr, voidptr, voidptr) i32
type LongField = fn (voidptr, voidptr, voidptr) i64
type PutInt = fn (voidptr, voidptr, voidptr, i32)
type Check = fn (voidptr) u8
type Drop = fn (voidptr, voidptr)
type Same = fn (voidptr, voidptr, voidptr) u8
type Register = fn (voidptr, voidptr, &NativeMethod, i32) i32
type CreateVM = fn (voidptr, &voidptr, voidptr) i32

fn slot(e voidptr, index i32) voidptr {
    unsafe { return (&voidptr(*(&voidptr(e))))[index] }
}

fn pending(e voidptr) bool { unsafe { return Check(slot(e, 228))(e) != 0 } }
fn cls(e voidptr, name &char) voidptr {
    if pending(e) { return unsafe { nil } }
    unsafe { return Lookup(slot(e, 6))(e, name) }
}
fn method(e voidptr, class_name &char, name &char, signature &char) voidptr {
    c := cls(e, class_name)
    if c == unsafe { nil } { return unsafe { nil } }
    unsafe {
        result := Member(slot(e, 33))(e, c, name, signature)
        Drop(slot(e, 23))(e, c)
        return result
    }
}
fn field(e voidptr, class_name &char, name &char, signature &char) voidptr {
    c := cls(e, class_name)
    if c == unsafe { nil } { return unsafe { nil } }
    unsafe {
        result := Member(slot(e, 94))(e, c, name, signature)
        Drop(slot(e, 23))(e, c)
        return result
    }
}
fn obj(e voidptr, receiver voidptr, class_name &char, name &char, signature &char, args &Value) voidptr {
    m := method(e, class_name, name, signature)
    if m == unsafe { nil } { return unsafe { nil } }
    unsafe { return ObjectCall(slot(e, 36))(e, receiver, m, args) }
}
fn call(e voidptr, receiver voidptr, class_name &char, name &char, signature &char, args &Value) {
    m := method(e, class_name, name, signature)
    if m != unsafe { nil } { unsafe { VoidCall(slot(e, 63))(e, receiver, m, args) } }
}
fn integer(e voidptr, receiver voidptr, class_name &char, name &char, signature &char, args &Value) i32 {
    m := method(e, class_name, name, signature)
    if m == unsafe { nil } { return 0 }
    unsafe { return IntCall(slot(e, 51))(e, receiver, m, args) }
}
fn boolean(e voidptr, receiver voidptr, class_name &char, name &char, signature &char, args &Value) u8 {
    m := method(e, class_name, name, signature)
    if m == unsafe { nil } { return 0 }
    unsafe { return BoolCall(slot(e, 39))(e, receiver, m, args) }
}
fn new_object(e voidptr, class_name &char, signature &char, args &Value) voidptr {
    m := method(e, class_name, c'<init>', signature)
    c := cls(e, class_name)
    if m == unsafe { nil } || c == unsafe { nil } { return unsafe { nil } }
    unsafe { return ObjectCall(slot(e, 30))(e, c, m, args) }
}
fn get_object(e voidptr, receiver voidptr, class_name &char, name &char, signature &char) voidptr {
    f := field(e, class_name, name, signature)
    if f == unsafe { nil } { return unsafe { nil } }
    unsafe { return ObjectField(slot(e, 95))(e, receiver, f) }
}
fn put_object(e voidptr, receiver voidptr, class_name &char, name &char, signature &char, value voidptr) {
    f := field(e, class_name, name, signature)
    if f != unsafe { nil } { unsafe { PutObject(slot(e, 104))(e, receiver, f, value) } }
}
fn get_int(e voidptr, receiver voidptr, class_name &char, name &char) i32 {
    f := field(e, class_name, name, c'I')
    if f == unsafe { nil } { return 0 }
    unsafe { return IntField(slot(e, 100))(e, receiver, f) }
}
fn put_int(e voidptr, receiver voidptr, class_name &char, name &char, value i32) {
    f := field(e, class_name, name, c'I')
    if f != unsafe { nil } { unsafe { PutInt(slot(e, 109))(e, receiver, f, value) } }
}
fn get_long(e voidptr, receiver voidptr, class_name &char, name &char) i64 {
    f := field(e, class_name, name, c'J')
    if f == unsafe { nil } { return 0 }
    unsafe { return LongField(slot(e, 101))(e, receiver, f) }
}

fn register(e voidptr, name &char, methods &NativeMethod, count i32) i32 {
    c := cls(e, name)
    if c == unsafe { nil } { return -1 }
    unsafe {
        result := Register(slot(e, 215))(e, c, methods, count)
        Drop(slot(e, 23))(e, c)
        return result
    }
}

@[export: 'JNI_CreateJavaVM']
pub fn create_vm(vm voidptr, env &voidptr, args voidptr) i32 {
    unsafe {
        next := CreateVM(C.dlsym(voidptr(usize(-1)), c'JNI_CreateJavaVM'))
        if voidptr(next) == nil { return -1 }
        result := next(vm, env, args)
        if result != 0 { return result }
        if register_activity(*env) != 0 || register_action_bar(*env) != 0 || register_simple_cursor(*env) != 0 || register_search(*env) != 0 || register_search_callbacks(*env) != 0 || register_dialog(*env) != 0 || register_dialog_builder(*env) != 0 || register_dialog_click(*env) != 0 || register_menu(*env) != 0 || register_menu_item(*env) != 0 || register_menu_click(*env) != 0 || register_charsets(*env) != 0 || register_theme(*env) != 0 || register_recreate(*env) != 0 || register_view(*env) != 0 || register_list_click(*env) != 0 || register_dialog_native(*env) != 0 { return -1 }
        if register_scroll(*env) != 0 { return -1 }
        C.puts(c'VINIX-ANDROID-FRAMEWORK ready')
        return 0
    }
}
