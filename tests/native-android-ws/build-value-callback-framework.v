// SPDX-License-Identifier: GPL-2.0-or-later
module main
import androidtools
import os
fn main() {
 if os.args.len != 3 { panic('usage: build-value-callback-framework FRAMEWORK FRESH_EXTERNAL_OUTPUT') }
 base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
 if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') { panic('fresh external output required') }
 original := os.read_file(base + '/smali/android/webkit/ValueCallback.smali')!
 changed := androidtools.framework_value_callback_source(original)!
 assert androidtools.framework_value_callback_source(changed)! == changed
 for declaration in ['.class public Landroid/webkit/ValueCallback;', '.super Ljava/lang/Object;',
  '.method public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V'] {
  for variant in [original.replace(declaration, ''), original + '\n' + declaration + '\n'] {
   mut rejected := false
   androidtools.framework_value_callback_source(variant) or { rejected = true }
   assert rejected
  }
 }
 for variant in [changed.replace('onReceiveValue(Ljava/lang/Object;)V', 'onReceiveValue(Ljava/lang/String;)V'),
  changed + '\n.field public extra:I\n', changed.replace('public abstract onReceiveValue', 'public native onReceiveValue'),
  changed + '\n.method public constructor <init>()V\n.end method\n'] {
  mut rejected := false
  androidtools.framework_value_callback_source(variant) or { rejected = true }
  assert rejected
 }
 os.mkdir_all(root)!
 os.cp_all(base + '/smali', root + '/smali', false)!
 os.write_file(root + '/smali/android/webkit/ValueCallback.smali', changed)!
 os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
 java := '/opt/homebrew/opt/openjdk@25/bin/java'
 cp := os.real_path('build/android-framework/tools') + '/*'
 for args in [[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'],
 ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
 [java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes', 'Landroid/webkit/ValueCallback;', '--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip']] {
  if os.system_args(args) != 0 { panic('SDK assembly/readback failed') }
 }
 roundtrip := os.read_file(root + '/roundtrip/android/webkit/ValueCallback.smali')!
 assert roundtrip.contains('.class public interface abstract Landroid/webkit/ValueCallback;')
 assert roundtrip.contains('.method public abstract onReceiveValue(Ljava/lang/Object;)V')
 assert !roundtrip.contains('<init>')
 assert roundtrip.contains('Ldalvik/annotation/Signature;')
 println('VALUE-CALLBACK-SDK-PASS assembly readback idempotent twelve-input-refusals')
}
