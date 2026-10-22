// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn method(signature string, body string) string {
 return '.method ' + signature + '\n.locals 10\n' + body + '\n.end method\n'
}

pub fn install(output string, resources string) ! {
 dir := output + '/smali/org/vinix/bootstrap'
 install_io_probe(dir)!
 install_power_probe(dir)!
 install_battery_probe(dir)!
 install_geometry_probe(dir)!
 install_attachment_probe(dir)!
 install_drawable_probe(dir)!
 install_media_probe(dir)!
 os.mkdir_all(output + '/res/font')!
 runtime := resources.all_before('/usr/lib/java/dex/')
 os.cp(runtime + '/usr/share/fonts/dejavu/DejaVuSansMono.ttf', output + '/res/font/fixture_font.ttf')!
 os.write_file(output + '/res/font/fixture_family.xml', '<font-family xmlns:android="http://schemas.android.com/apk/res/android"><font android:font="@font/fixture_font" android:fontWeight="400"/></font-family>')!
 os.write_file(output + '/res/font/fixture_fallback.xml', '<font-family xmlns:android="http://schemas.android.com/apk/res/android" android:fontProviderAuthority="absent.fonts" android:fontProviderPackage="absent.fonts" android:fontProviderQuery="Absent" android:fontProviderSystemFontFamily="sans-serif"/>')!
 os.write_file(dir + '/BroadcastProbe.smali', '.class public Lorg/vinix/bootstrap/BroadcastProbe;\n.super Landroid/content/BroadcastReceiver;\n.field private static count:I\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V\nreturn-void') +
  method('public onReceive(Landroid/content/Context;Landroid/content/Intent;)V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-ne v0, v1, :bad
invoke-virtual {p1, p0}, Landroid/content/Context;->unregisterReceiver(Landroid/content/BroadcastReceiver;)V
sget v0, Lorg/vinix/bootstrap/BroadcastProbe;->count:I
add-int/lit8 v0, v0, 1
sput v0, Lorg/vinix/bootstrap/BroadcastProbe;->count:I
const/4 v1, 2
if-gt v0, v1, :bad
if-ne v0, v1, :done
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-BROADCASTS-PASS overloads queued-main-handler filtering unregister"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
:done
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "broadcast handler or delivery count"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
 os.write_file(dir + '/StartupProbe.smali', '.class public Lorg/vinix/bootstrap/StartupProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check(Landroid/content/Context;)V', '
invoke-static {p0}, Lorg/vinix/bootstrap/StartupProbe;->accessibility(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/StartupProbe;->appops(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/StartupProbe;->uriPermissions(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/IoProbe;->check(Landroid/content/Context;)V
invoke-static {}, Lorg/vinix/bootstrap/StartupProbe;->altitude()V
invoke-static {p0}, Lorg/vinix/bootstrap/PowerProbe;->check(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/BatteryProbe;->check(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/GeometryProbe;->check(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/AttachmentProbe;->check(Landroid/content/Context;)V
invoke-static {}, Lorg/vinix/bootstrap/DrawableProbe;->check()V
invoke-static {p0}, Lorg/vinix/bootstrap/StartupProbe;->haptics(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/MediaProbe;->check(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/StartupProbe;->fonts(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/StartupProbe;->broadcasts(Landroid/content/Context;)V
new-instance v0, Landroid/hardware/SensorManager;
invoke-direct {v0}, Landroid/hardware/SensorManager;-><init>()V
const/4 v1, -1
invoke-virtual {v0, v1}, Landroid/hardware/SensorManager;->getSensorList(I)Ljava/util/List;
move-result-object v1
invoke-interface {v1}, Ljava/util/List;->isEmpty()Z
move-result v1
if-eqz v1, :bad
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/hardware/SensorManager;->getDefaultSensor(I)Landroid/hardware/Sensor;
move-result-object v1
if-nez v1, :bad
const/4 v2, 0
invoke-virtual {v0, v1, v1, v2}, Landroid/hardware/SensorManager;->registerListener(Landroid/hardware/SensorEventListener;Landroid/hardware/Sensor;I)Z
move-result v1
if-nez v1, :bad
const-class v0, Landroid/hardware/SensorEventListener2;
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-SENSORS-PASS empty-list absent-device registration-fails listener2"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "sensor availability"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static accessibility(Landroid/content/Context;)V', '
const-string v0, "accessibility"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/view/accessibility/AccessibilityManager;
if-eqz v0, :bad
invoke-virtual {v0}, Landroid/view/accessibility/AccessibilityManager;->isEnabled()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/view/accessibility/AccessibilityManager;->isTouchExplorationEnabled()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/view/accessibility/AccessibilityManager;->getInstalledAccessibilityServiceList()Ljava/util/List;
move-result-object v1
invoke-static {v1}, Lorg/vinix/bootstrap/StartupProbe;->emptyServices(Ljava/util/List;)V
const/4 v1, -1
invoke-virtual {v0, v1}, Landroid/view/accessibility/AccessibilityManager;->getEnabledAccessibilityServiceList(I)Ljava/util/List;
move-result-object v1
invoke-static {v1}, Lorg/vinix/bootstrap/StartupProbe;->emptyServices(Ljava/util/List;)V
invoke-virtual {v0}, Landroid/view/accessibility/AccessibilityManager;->getAccessibilityServiceList()Ljava/util/List;
move-result-object v1
invoke-static {v1}, Lorg/vinix/bootstrap/StartupProbe;->emptyServices(Ljava/util/List;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-ACCESSIBILITY-PASS disabled empty-installed empty-enabled immutable-lists"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "absent accessibility services"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static emptyServices(Ljava/util/List;)V', '
invoke-interface {p0}, Ljava/util/List;->isEmpty()Z
move-result v0
if-eqz v0, :bad
const/4 v0, 0
:try_start
invoke-interface {p0, v0}, Ljava/util/List;->add(Ljava/lang/Object;)Z
:try_end
.catch Ljava/lang/UnsupportedOperationException; {:try_start .. :try_end} :immutable
goto :bad
:immutable
move-exception v0
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "accessibility service list must be empty and immutable"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static haptics(Landroid/content/Context;)V', '
const-string v0, "vibrator"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/os/Vibrator;
if-eqz v0, :bad
invoke-virtual {v0}, Landroid/os/Vibrator;->hasVibrator()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/Vibrator;->hasAmplitudeControl()Z
move-result v1
if-nez v1, :bad
const-wide/16 v1, 10
invoke-virtual {v0, v1, v2}, Landroid/os/Vibrator;->vibrate(J)V
const/4 v3, -1
invoke-static {v1, v2, v3}, Landroid/os/VibrationEffect;->createOneShot(JI)Landroid/os/VibrationEffect;
move-result-object v1
invoke-virtual {v0, v1}, Landroid/os/Vibrator;->vibrate(Landroid/os/VibrationEffect;)V
const/4 v2, 0
invoke-virtual {v0, v1, v2}, Landroid/os/Vibrator;->vibrate(Landroid/os/VibrationEffect;Landroid/media/AudioAttributes;)V
const/4 v1, 2
new-array v1, v1, [J
const/4 v2, 1
const-wide/16 v3, 10
aput-wide v3, v1, v2
const/4 v2, 0
invoke-virtual {v0, v1, v2}, Landroid/os/Vibrator;->vibrate([JI)V
const/4 v3, 0
invoke-virtual {v0, v1, v2, v3}, Landroid/os/Vibrator;->vibrate([JILandroid/media/AudioAttributes;)V
invoke-virtual {v0}, Landroid/os/Vibrator;->cancel()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-HAPTICS-PASS absent-device effects patterns cancel no-native-motor"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "haptic hardware availability"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static altitude()V', '
const v0, 0x447d5000
invoke-static {v0, v0}, Landroid/hardware/SensorManager;->getAltitude(FF)F
move-result v1
const/4 v2, 0
cmpl-float v1, v1, v2
if-nez v1, :bad
const v1, 0x4460b0a4
invoke-static {v0, v1}, Landroid/hardware/SensorManager;->getAltitude(FF)F
move-result v1
const v2, 0x447a0000
sub-float v1, v1, v2
invoke-static {v1}, Ljava/lang/Math;->abs(F)F
move-result v1
const/high16 v2, 0x3f800000
cmpg-float v1, v1, v2
if-gtz v1, :bad
const v1, 0x44834000
invoke-static {v0, v1}, Landroid/hardware/SensorManager;->getAltitude(FF)F
move-result v1
const/4 v2, 0
cmpg-float v1, v1, v2
if-gez v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-ALTITUDE-PASS sea-level 1000m below-sea-level"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "barometric altitude"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static uriPermissions(Landroid/content/Context;)V', '
const-string v0, "content://not.installed/private"
invoke-static {v0}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v1
invoke-static {}, Landroid/os/Process;->myPid()I
move-result v2
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v3
const/4 v4, 3
const/4 v5, -1
invoke-virtual {p0, v1, v2, v3, v4}, Landroid/content/Context;->checkUriPermission(Landroid/net/Uri;III)I
move-result v0
if-ne v0, v5, :bad
const/16 v3, 12345
invoke-virtual {p0, v1, v2, v3, v4}, Landroid/content/Context;->checkUriPermission(Landroid/net/Uri;III)I
move-result v0
if-ne v0, v5, :bad
invoke-virtual {p0, v1, v4}, Landroid/content/Context;->checkCallingOrSelfUriPermission(Landroid/net/Uri;I)I
move-result v0
if-ne v0, v5, :bad
invoke-virtual {p0, v1, v4}, Landroid/content/Context;->checkCallingUriPermission(Landroid/net/Uri;I)I
move-result v0
if-ne v0, v5, :bad
const/4 v1, 0
:null_uri
invoke-virtual {p0, v1, v2, v3, v4}, Landroid/content/Context;->checkUriPermission(Landroid/net/Uri;III)I
:null_end
.catch Ljava/lang/NullPointerException; {:null_uri .. :null_end} :null_ok
goto :bad
:null_ok
move-exception v0
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-URI-PERMISSIONS-PASS absent-grants foreign-uid calling self null-uri"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "URI delegation permissions"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static appops(Landroid/content/Context;)V', '
new-instance v0, Landroid/app/AppOpsManager;
invoke-direct {v0}, Landroid/app/AppOpsManager;-><init>()V
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v2
if-ltz v2, :bad
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v3
invoke-virtual {v0, v2, v3}, Landroid/app/AppOpsManager;->checkPackage(ILjava/lang/String;)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v4
iget v4, v4, Landroid/content/pm/ApplicationInfo;->uid:I
if-ne v2, v4, :bad
const-string v1, "android:coarse_location"
invoke-virtual {v0, v1, v2, v3}, Landroid/app/AppOpsManager;->checkOpNoThrow(Ljava/lang/String;ILjava/lang/String;)I
move-result v4
const/4 v5, 1
if-ne v4, v5, :bad
const-string v1, "android:read_external_storage"
invoke-virtual {v0, v1, v2, v3}, Landroid/app/AppOpsManager;->checkOpNoThrow(Ljava/lang/String;ILjava/lang/String;)I
move-result v4
if-nez v4, :bad
const-string v3, "not.installed"
invoke-virtual {v0, v1, v2, v3}, Landroid/app/AppOpsManager;->checkOpNoThrow(Ljava/lang/String;ILjava/lang/String;)I
move-result v4
const/4 v5, 2
if-ne v4, v5, :bad
:package
invoke-virtual {v0, v2, v3}, Landroid/app/AppOpsManager;->checkPackage(ILjava/lang/String;)V
:package_end
.catch Ljava/lang/SecurityException; {:package .. :package_end} :package_ok
goto :bad
:package_ok
move-exception v4
const-string v1, "android.permission.ACCESS_FINE_LOCATION"
invoke-static {v1}, Landroid/app/AppOpsManager;->permissionToOp(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
const-string v4, "android:fine_location"
invoke-virtual {v4, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :bad
const-string v1, "android.permission.INTERNET"
invoke-static {v1}, Landroid/app/AppOpsManager;->permissionToOp(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
if-nez v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-APPOPS-PASS uid package-validation allowed-storage absent-location permission-mapping"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "AppOps policy or UID ownership"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static fonts(Landroid/content/Context;)V', '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
const-string v1, "fixture_font"
const-string v2, "font"
const-string v3, "org.vinix.bootstrap"
invoke-virtual {v0, v1, v2, v3}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getFont(I)Landroid/graphics/Typeface;
move-result-object v4
if-eqz v4, :bad
iget-wide v5, v4, Landroid/graphics/Typeface;->native_instance:J
const-wide/16 v7, 0
cmp-long v5, v5, v7
if-eqz v5, :bad
new-instance v5, Landroid/graphics/Paint;
invoke-direct {v5}, Landroid/graphics/Paint;-><init>()V
invoke-virtual {v5, v4}, Landroid/graphics/Paint;->setTypeface(Landroid/graphics/Typeface;)Landroid/graphics/Typeface;
invoke-virtual {v5}, Landroid/graphics/Paint;->getTypeface()Landroid/graphics/Typeface;
move-result-object v6
if-ne v4, v6, :bad
const-string v6, "iii"
invoke-virtual {v5, v6}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v6
const-string v7, "WWW"
invoke-virtual {v5, v7}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v7
cmpl-float v8, v6, v7
if-nez v8, :bad
new-instance v8, Landroid/graphics/Paint;
invoke-direct {v8, v5}, Landroid/graphics/Paint;-><init>(Landroid/graphics/Paint;)V
invoke-virtual {v8}, Landroid/graphics/Paint;->getTypeface()Landroid/graphics/Typeface;
move-result-object v9
if-ne v4, v9, :bad
const-string v1, "fixture_family"
invoke-virtual {v0, v1, v2, v3}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getFont(I)Landroid/graphics/Typeface;
move-result-object v1
if-eqz v1, :bad
const-string v1, "fixture_fallback"
invoke-virtual {v0, v1, v2, v3}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getFont(I)Landroid/graphics/Typeface;
move-result-object v1
if-eqz v1, :bad
new-instance v1, Landroid/widget/TextView;
invoke-direct {v1, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
invoke-virtual {v1, v4}, Landroid/widget/TextView;->setTypeface(Landroid/graphics/Typeface;)V
invoke-virtual {v1}, Landroid/widget/TextView;->getTypeface()Landroid/graphics/Typeface;
move-result-object v1
if-ne v1, v4, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-FONTS-PASS ttf family-xml system-fallback mono-metrics paint-copy textview"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "resource font or monospace metrics"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static broadcasts(Landroid/content/Context;)V', '
move-object v0, p0
new-instance v1, Lorg/vinix/bootstrap/BroadcastProbe;
invoke-direct {v1}, Lorg/vinix/bootstrap/BroadcastProbe;-><init>()V
new-instance v2, Landroid/content/IntentFilter;
const-string v3, "vinix.fixture.BROADCAST"
invoke-direct {v2, v3}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V
const/4 v3, 4
invoke-virtual {v0, v1, v2, v3}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;I)Landroid/content/Intent;
move-result-object v3
if-nez v3, :bad
new-instance v1, Lorg/vinix/bootstrap/BroadcastProbe;
invoke-direct {v1}, Lorg/vinix/bootstrap/BroadcastProbe;-><init>()V
const/4 v3, 0
new-instance v4, Landroid/os/Handler;
invoke-direct {v4}, Landroid/os/Handler;-><init>()V
const/4 v5, 4
invoke-virtual/range {v0 .. v5}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;Ljava/lang/String;Landroid/os/Handler;I)Landroid/content/Intent;
const/4 v5, 6
:conflict
invoke-virtual/range {v0 .. v5}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;Ljava/lang/String;Landroid/os/Handler;I)Landroid/content/Intent;
:conflict_end
.catch Ljava/lang/IllegalArgumentException; {:conflict .. :conflict_end} :conflict_ok
goto :bad
:conflict_ok
move-exception v6
new-instance v6, Landroid/content/Intent;
const-string v7, "vinix.fixture.UNRELATED"
invoke-direct {v6, v7}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
invoke-virtual {p0, v6}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;)V
new-instance v6, Landroid/content/Intent;
const-string v7, "vinix.fixture.BROADCAST"
invoke-direct {v6, v7}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
const-string v7, "another.package"
invoke-virtual {v6, v7}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;
invoke-virtual {p0, v6}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;)V
const/4 v7, 0
invoke-virtual {v6, v7}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;
invoke-virtual {p0, v6}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "broadcast registration flags or sticky state"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
