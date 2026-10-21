// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

fn ws_appops_owns(e voidptr, uid i32, package voidptr) bool {
 unsafe {
  if package == nil || uid < 0 || u32(uid) != C.getuid() { return false }
  loaded := static_obj(e, c'android/atl/ATLLoadedApp', c'getPrimaryApplication', c'()Landroid/atl/ATLLoadedApp;', nil)
  if loaded == nil || pending(e) { return false }
  pkg := get_object(e, loaded, c'android/atl/ATLLoadedApp', c'pkg', c'Landroid/content/pm/PackageParser$Package;')
  name := get_object(e, pkg, c'android/content/pm/PackageParser$Package', c'packageName', c'Ljava/lang/String;')
  args := [Value{l: package}]!
  return boolean(e, name, c'java/lang/String', c'equals', c'(Ljava/lang/Object;)Z', &args[0]) != 0
 }
}

fn ws_appops_check(e voidptr, op voidptr, uid i32, package voidptr) i32 {
 unsafe {
  if op == nil { throw(e, c'java/lang/NullPointerException', c'op'); return 2 }
  if !ws_appops_owns(e, uid, package) { return 2 }
  name := ws_utf(e, op)
  defer { ws_release(e, op, name) }
  // The existing backend permits its ordinary external-storage directory.
  if C.strcmp(name, c'android:read_external_storage') == 0 || C.strcmp(name, c'android:write_external_storage') == 0 { return 0 }
  // There are no phone, location, camera, microphone, calendar, contacts or
  // motion-provider services behind these operations in native WS.
  if C.strcmp(name, c'android:coarse_location') == 0 || C.strcmp(name, c'android:fine_location') == 0 ||
   C.strcmp(name, c'android:record_audio') == 0 || C.strcmp(name, c'android:camera') == 0 ||
   C.strcmp(name, c'android:body_sensors') == 0 || C.strcmp(name, c'android:activity_recognition') == 0 ||
   C.strcmp(name, c'android:read_contacts') == 0 || C.strcmp(name, c'android:write_contacts') == 0 ||
   C.strcmp(name, c'android:read_calendar') == 0 || C.strcmp(name, c'android:write_calendar') == 0 ||
   C.strcmp(name, c'android:read_phone_state') == 0 || C.strcmp(name, c'android:call_phone') == 0 ||
   C.strcmp(name, c'android:read_sms') == 0 || C.strcmp(name, c'android:send_sms') == 0 { return 1 }
  // Operations without a backend policy require the caller's permission check.
  return 3
 }
}

fn ws_appops_package(e voidptr, uid i32, package voidptr) {
 if !ws_appops_owns(e, uid, package) && !pending(e) {
  throw(e, c'java/lang/SecurityException', c'package does not belong to the supplied UID')
 }
}
