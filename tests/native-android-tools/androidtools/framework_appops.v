// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_appops(smali string) ! {
 path := smali + '/android/app/AppOpsManager.smali'
 mut text := os.read_file(path)!
 for signature in ['checkOpNoThrow(Ljava/lang/String;ILjava/lang/String;)I', 'checkPackage(ILjava/lang/String;)V',
  'noteProxyOpNoThrow(Ljava/lang/String;Ljava/lang/String;)I'] {
  text = framework_replace_method(text, signature, '.method public native ' + signature + '\n.end method')!
 }
 mut mapping := '.method public static permissionToOp(Ljava/lang/String;)Ljava/lang/String;\n.locals 1\n'
 for index, entry in ['ACCESS_COARSE_LOCATION:coarse_location', 'ACCESS_FINE_LOCATION:fine_location',
  'ACCESS_BACKGROUND_LOCATION:coarse_location', 'READ_EXTERNAL_STORAGE:read_external_storage',
  'WRITE_EXTERNAL_STORAGE:write_external_storage', 'RECORD_AUDIO:record_audio', 'CAMERA:camera',
  'BODY_SENSORS:body_sensors', 'ACTIVITY_RECOGNITION:activity_recognition', 'READ_CONTACTS:read_contacts',
  'WRITE_CONTACTS:write_contacts', 'READ_CALENDAR:read_calendar', 'WRITE_CALENDAR:write_calendar',
  'READ_PHONE_STATE:read_phone_state', 'CALL_PHONE:call_phone', 'READ_SMS:read_sms', 'SEND_SMS:send_sms'] {
  parts := entry.split(':')
  mapping += 'const-string v0, "android.permission.' + parts[0] + '"\n' +
   'invoke-virtual {v0, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\n' +
   'if-eqz v0, :next_' + index.str() + '\nconst-string v0, "android:' + parts[1] + '"\nreturn-object v0\n:next_' + index.str() + '\n'
 }
 mapping += 'const/4 v0, 0\nreturn-object v0\n.end method'
 text = framework_replace_method(text, 'permissionToOp(Ljava/lang/String;)Ljava/lang/String;', mapping)!
 for name, value in {'MODE_ALLOWED': 0, 'MODE_IGNORED': 1, 'MODE_ERRORED': 2, 'MODE_DEFAULT': 3} {
  text += '\n.field public static final ' + name + ':I = ' + value.str() + '\n'
 }
 os.write_file(path, text)!
 process := smali + '/android/os/Process.smali'
 os.write_file(process, framework_replace_method(os.read_file(process)!, 'myUid()I', '.method public static native myUid()I\n.end method')!)!
 mut process_text := os.read_file(process)!
 for signature in ['getThreadPriority(I)I', 'setThreadPriority(I)V', 'setThreadPriority(II)V'] {
  process_text = framework_replace_method(process_text, signature, '.method public static native ' + signature + '\n.end method')!
 }
 os.write_file(process, process_text)!
 // All APK code in this backend executes as the launching Unix user. Keep
 // package metadata consistent with the actual process instead of UID -1.
 pkg := smali + '/android/content/pm/PackageParser$Package.smali'
 original := os.read_file(pkg)!
 marker := 'const/4 v1, -0x1\n\n    iput v1, v0, Landroid/content/pm/ApplicationInfo;->uid:I'
 if !original.contains(marker) { return error('missing package UID initialization') }
 os.write_file(pkg, original.replace(marker, 'invoke-static {}, Landroid/os/Process;->myUid()I\n\n    move-result v1\n\n    iput v1, v0, Landroid/content/pm/ApplicationInfo;->uid:I'))!
}
