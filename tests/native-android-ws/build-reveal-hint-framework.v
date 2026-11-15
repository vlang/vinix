// SPDX-License-Identifier: GPL-2.0-or-later
module main
import androidtools
import os
fn main() {
 if os.args.len != 3 { panic('usage: build-reveal-hint-framework FRAMEWORK FRESH_EXTERNAL_OUTPUT') }
 base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
 if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') { panic('fresh external output required') }
 original := os.read_file(base + '/smali/android/view/View.smali')!
 changed := androidtools.framework_reveal_hint_source(original)!
 for declaration in ['.class public Landroid/view/View;', '.super Ljava/lang/Object;',
  '.method public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V'] {
  for variant in [original.replace(declaration, ''), original + '\n' + declaration + '\n'] {
   mut rejected := false
   androidtools.framework_reveal_hint_source(variant) or { rejected = true }
   assert rejected
  }
 }
 for member in ['.field private vinixRevealOnFocusDisabled:Z',
  '.method public final getRevealOnFocusHint()Z', '.method public final setRevealOnFocusHint(Z)V'] {
  mut rejected := false
  androidtools.framework_reveal_hint_source(original + '\n' + member + '\n') or { rejected = true }
  assert rejected
 }
 os.mkdir_all(root)!
 os.cp_all(base + '/smali', root + '/smali', false)!
 os.write_file(root + '/smali/android/view/View.smali', changed)!
 os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
 java := '/opt/homebrew/opt/openjdk@25/bin/java'
 cp := os.real_path('build/android-framework/tools') + '/*'
 for args in [[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'],
 ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
 [java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes', 'Landroid/view/View;', '--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip']] {
  if os.system_args(args) != 0 { panic('SDK assembly/readback failed') }
 }
 roundtrip := os.read_file(root + '/roundtrip/android/view/View.smali')!
 for member in ['.method public final getRevealOnFocusHint()Z', '.method public final setRevealOnFocusHint(Z)V'] {
  assert roundtrip.count(member) == 1
 }
 println('REVEAL-HINT-SDK-PASS assembly readback nine-input-refusals')
}
