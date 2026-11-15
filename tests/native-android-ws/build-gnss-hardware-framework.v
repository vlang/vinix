// SPDX-License-Identifier: GPL-2.0-or-later
module main
import androidtools
import os
fn main() {
 if os.args.len != 3 { panic('usage: build-gnss-hardware-framework FRAMEWORK FRESH_EXTERNAL_OUTPUT') }
 base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
 if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') { panic('fresh external output required') }
 original := os.read_file(base + '/smali/android/location/LocationManager.smali')!
 changed := androidtools.framework_gnss_hardware_source(original)!
 for declaration in ['.class public Landroid/location/LocationManager;', '.method public constructor <init>()V', '.method private native nativeGetLocation()V'] {
  for variant in [original.replace(declaration, ''), original + '\n' + declaration + '\n'] {
   mut rejected := false
   androidtools.framework_gnss_hardware_source(variant) or { rejected = true }
   assert rejected
  }
 }
 for method in ['getGnssHardwareModelName()Ljava/lang/String;', 'getGnssYearOfHardware()I'] {
  mut rejected := false
  androidtools.framework_gnss_hardware_source(original + '\n.method public ' + method + '\n.end method\n') or { rejected = true }
  assert rejected
 }
 os.mkdir_all(root)!
 os.cp_all(base + '/smali', root + '/smali', false)!
 os.write_file(root + '/smali/android/location/LocationManager.smali', changed)!
 os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
 java := '/opt/homebrew/opt/openjdk@25/bin/java'
 cp := os.real_path('build/android-framework/tools') + '/*'
 for args in [[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'],
 ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
 [java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes', 'Landroid/location/LocationManager;', '--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip']] {
  if os.system_args(args) != 0 { panic('SDK assembly/readback failed') }
  if !os.is_file(root + '/classes.dex') { panic('assembly did not produce DEX') }
 }
 roundtrip := os.read_file(root + '/roundtrip/android/location/LocationManager.smali')!
 for method in ['getGnssHardwareModelName()Ljava/lang/String;', 'getGnssYearOfHardware()I'] {
  assert roundtrip.contains('.method public ' + method)
 }
 println('GNSS-HARDWARE-SDK-PASS assembly readback eight-input-refusals')
}
