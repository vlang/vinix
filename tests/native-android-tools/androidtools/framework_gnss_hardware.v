// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

// No native WS GNSS provider supplies hardware metadata. These Android API 28
// queries report its absence without starting a provider or granting location.
pub fn framework_gnss_hardware_source(original string) !string {
 for declaration in ['.class public Landroid/location/LocationManager;',
  '.method public constructor <init>()V', '.method private native nativeGetLocation()V'] {
  if original.split_into_lines().filter(it == declaration).len != 1 { return error('canonical LocationManager declaration required: ' + declaration) }
 }
 for method in ['getGnssHardwareModelName', 'getGnssYearOfHardware'] {
  if original.contains(' ' + method + '(') { return error('GNSS hardware query already present: ' + method) }
 }
 return original + r'
.method public getGnssHardwareModelName()Ljava/lang/String;
.locals 1
const/4 v0, 0
return-object v0
.end method
.method public getGnssYearOfHardware()I
.locals 1
const/4 v0, 0
return v0
.end method
'
}

pub fn framework_gnss_hardware(smali string) ! {
 path := smali + '/android/location/LocationManager.smali'
 os.write_file(path, framework_gnss_hardware_source(os.read_file(path)!)!)!
}
