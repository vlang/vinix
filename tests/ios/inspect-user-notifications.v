// SPDX-License-Identifier: GPL-2.0-or-later
// Measure the installed Apple runtime; execute inside an .app bundle for center checks.
module main

import os

#flag -framework Foundation
#flag -framework UserNotifications
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlopen(&char, int) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getName(voidptr) &char
fn C.class_copyIvarList(voidptr, &u32) &voidptr
fn C.ivar_getName(voidptr) &char
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.ivar_getOffset(voidptr) isize
fn C.class_copyMethodList(voidptr, &u32) &voidptr
fn C.method_getName(voidptr) voidptr
fn C.sel_getName(voidptr) &char
fn C.method_getTypeEncoding(voidptr) &char

type Send = fn (u64, voidptr, u64) u64
fn msg(object u64, selector &char, argument u64) u64 {
 return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), argument) }
}
fn main() {
 if os.args.len == 3 && os.args[1] == '--bundle' {
  bundle := os.abs_path(os.args[2]) + '/InspectNotifications.app/Contents'
  os.mkdir_all(bundle + '/MacOS') or { panic(err) }
  binary := bundle + '/MacOS/inspect'
  os.cp(os.executable(), binary) or { panic(err) }
  os.write_file(bundle + '/Info.plist', '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.vinix.notification-inspection</string><key>CFBundleExecutable</key><string>inspect</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>') or { panic(err) }
  mut process := os.new_process(binary)
  process.set_args(['UNUserNotificationCenter', 'center'])
  process.set_redirect_stdio_merged(); process.run()
  print(process.stdout_slurp()); process.wait(); code := process.code; process.close()
  exit(code)
 }
 name := if os.args.len > 1 { os.args[1] } else { 'UNUserNotificationCenter' }
 if name == 'CTTelephonyNetworkInfo' {
  assert C.dlopen(c'/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony', 2) != unsafe { nil }
 }
 if name == 'ASIdentifierManager' {
  assert C.dlopen(c'/System/Library/Frameworks/AdSupport.framework/AdSupport', 2) != unsafe { nil }
 }
 cls := C.objc_getClass(name.str)
 assert cls != unsafe { nil }
 println('${name} SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
 mut count := u32(0)
 ivars := C.class_copyIvarList(cls, &count)
 for i in 0 .. int(count) {
  ivar := unsafe { ivars[i] }
  println('IVAR ${unsafe { C.ivar_getName(ivar).vstring() }} ${unsafe { C.ivar_getTypeEncoding(ivar).vstring() }} ${C.ivar_getOffset(ivar)}')
 }
 unsafe { C.free(ivars) }
 for meta in [false, true]! {
  methods := C.class_copyMethodList(if meta { C.object_getClass(cls) } else { cls }, &count)
  for i in 0 .. int(count) {
   method := unsafe { methods[i] }
   println('METHOD ${if meta { "+" } else { "-" }} ${unsafe { C.sel_getName(C.method_getName(method)).vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}')
  }
  unsafe { C.free(methods) }
 }
 if name == 'CTTelephonyNetworkInfo' {
  pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
  object := msg(u64(cls), c'new', 0)
  for selector in [c'delegate', c'dataServiceIdentifier', c'subscriberCellularProvider', c'serviceSubscriberCellularProviders', c'serviceCurrentRadioAccessTechnology', c'currentRadioAccessTechnology', c'serviceSubscriberCellularProvidersDidUpdateNotifier', c'subscriberCellularProviderDidUpdateNotifier']! {
   value := msg(object, selector, 0)
   kind := if value == 0 { 'nil' } else { unsafe { C.class_getName(C.object_getClass(voidptr(value))).vstring() } }
   println('DEFAULT ${unsafe { selector.vstring() }} ${kind}${if value == 0 { '' } else { ' count=' + msg(value, c'count', 0).str() }}')
  }
  msg(object, c'release', 0); msg(pool, c'drain', 0)
 }
 if name == 'ASIdentifierManager' {
  pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
  object := msg(u64(cls), c'sharedManager', 0)
  println('ADSUPPORT: sharedManager nil=' + (object == 0).str())
  println('ADSUPPORT: repeated sharedManager same=' + (object == msg(u64(cls), c'sharedManager', 0)).str())
  identifier := msg(object, c'advertisingIdentifier', 0)
  println('ADSUPPORT: tracking=' + msg(object, c'isAdvertisingTrackingEnabled', 0).str())
  if identifier != 0 { println('ADSUPPORT: identifier=' + unsafe { (&char(msg(msg(identifier, c'UUIDString', 0), c'UTF8String', 0))).vstring() }) }
  allocated := msg(u64(cls), c'new', 0)
  println('ADSUPPORT: new same=' + (allocated == object).str() + ' tracking=' + msg(allocated, c'isAdvertisingTrackingEnabled', 0).str())
  msg(allocated, c'release', 0); msg(pool, c'drain', 0)
 }
 if os.args.len > 2 && os.args[2] == 'center' {
  assert name == 'UNUserNotificationCenter'
  pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
  center := msg(u64(cls), c'currentNotificationCenter', 0)
  assert center != 0 && center == msg(u64(cls), c'currentNotificationCenter', 0)
  assert msg(center, c'delegate', 0) == 0
  delegate := msg(u64(C.objc_getClass(c'NSObject')), c'new', 0)
  msg(center, c'setDelegate:', delegate)
  inner := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
  assert msg(center, c'delegate', 0) == delegate
  msg(inner, c'drain', 0)
  msg(delegate, c'release', 0)
  assert msg(center, c'delegate', 0) == 0
  println('CENTER: singleton and zeroing weak delegate PASS; content extensions ${msg(center, c'supportsContentExtensions', 0)}')
  msg(pool, c'drain', 0)
 }
}
