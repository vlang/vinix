// SPDX-License-Identifier: GPL-2.0-or-later
module deviceconfigprobe

import os

pub fn install(root string) ! {
 mut body := r'.class public Lorg/vinix/bootstrap/DeviceConfigProbe;
.super Ljava/lang/Object;
.method public static check()V
.locals 5
const-string v0, "vinix_test_namespace"
const-string v1, "value"
const-string v2, "attempted-update"
const/4 v4, 0
invoke-static {v0, v1}, Landroid/provider/DeviceConfig;->getProperty(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
move-result-object v3
if-nez v3, :bad
'
 for flag in [0, 1] {
  for value in ['v2', 'v4'] {
   body += 'const/4 v3, ${flag}\ninvoke-static {v0, v1, ${value}, v3}, Landroid/provider/DeviceConfig;->setProperty(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Z)Z\nmove-result v3\nif-nez v3, :bad\ninvoke-static {v0, v1}, Landroid/provider/DeviceConfig;->getProperty(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v3\nif-nez v3, :bad\n'
  }
 }
 for i, args in ['v4, v1', 'v0, v4'] {
  for j, call in ['getProperty(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;', 'setProperty(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Z)Z'] {
   registers := if j == 0 { args } else { args + ', v2, v4' }
   label := '${i}_${j}'
   body += ':start_${label}\ninvoke-static {${registers}}, Landroid/provider/DeviceConfig;->${call}\n:end_${label}\ngoto :bad\n.catch Ljava/lang/NullPointerException; {:start_${label} .. :end_${label}} :caught_${label}\n:caught_${label}\nmove-exception v3\n'
  }
 }
 body += r'
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "DEVICE-CONFIG-PASS absent-properties failed-writes null-deletion make-default null-rejection"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "absent DeviceConfig datastore"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
'
 os.write_file(root + '/smali/DeviceConfigProbe.smali', body)!
}
