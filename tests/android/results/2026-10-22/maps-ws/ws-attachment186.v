// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

fn ws_attach_children(e voidptr, parent voidptr) {
 ws_trace_view_additions(e, parent)
 token := get_object(e, parent, c'android/view/View', c'vinixWindowToken', c'Landroid/os/IBinder;')
 if token == unsafe { nil } { return }
 args := [Value{l: token}]!
 call(e, parent, c'android/view/View', c'vinixAttachChildren', c'(Landroid/os/IBinder;)V', unsafe { &args[0] })
}

fn ws_attach_window(e voidptr, window voidptr, decor voidptr) {
 unsafe {
  mut token := get_object(e, window, c'android/view/Window', c'vinixWindowToken', c'Landroid/os/IBinder;')
  if token == nil && !pending(e) {
   token = new_object(e, c'android/os/Binder', c'()V', nil)
   put_object(e, window, c'android/view/Window', c'vinixWindowToken', c'Landroid/os/IBinder;', token)
  }
  args := &Value(C.alloca(sizeof(Value)))
  args[0] = Value{l: token}
  if !pending(e) { call(e, decor, c'android/view/View', c'vinixAttachToWindow', c'(Landroid/os/IBinder;)V', args) }
 }
}

fn ws_detach_view(e voidptr, view voidptr) {
 unsafe {
  args := &Value(C.alloca(sizeof(Value)))
  args[0] = Value{l: nil}
  if view != nil && !pending(e) { call(e, view, c'android/view/View', c'vinixAttachToWindow', c'(Landroid/os/IBinder;)V', args) }
 }
}
