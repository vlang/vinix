// SPDX-License-Identifier: GPL-2.0-or-later
module main
import androidtools
import os
fn main() {
 if os.args.len != 3 { panic('usage: build-contact-labels-framework FRAMEWORK FRESH_EXTERNAL_OUTPUT') }
 base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
 if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') { panic('fresh external output required') }
 mut changed := map[string]string{}
 for kind in ['Email', 'Phone'] {
  path := '/android/provider/ContactsContract$CommonDataKinds$' + kind + '.smali'
  original := os.read_file(base + '/smali' + path)!
  changed[path] = androidtools.framework_contact_labels_source(original, kind)!
  for declaration in ['.class public final Landroid/provider/ContactsContract$CommonDataKinds$' + kind + ';',
   '.super Ljava/lang/Object;', '.field public static final CONTENT_URI:Landroid/net/Uri;',
   '.method public constructor <init>()V'] {
   for variant in [original.replace(declaration, ''), original + '\n' + declaration + '\n'] {
    mut rejected := false
    androidtools.framework_contact_labels_source(variant, kind) or { rejected = true }
    assert rejected
   }
  }
  for member in ['.field public static final TYPE_CUSTOM:I', '.method public static getTypeLabel()V', '.method public static getTypeLabelResource()V'] {
   mut rejected := false
   androidtools.framework_contact_labels_source(original + '\n' + member + '\n', kind) or { rejected = true }
   assert rejected
  }
 }
 os.mkdir_all(root)!
 os.cp_all(base + '/smali', root + '/smali', false)!
 for path, source in changed { os.write_file(root + '/smali' + path, source)! }
 os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
 java := '/opt/homebrew/opt/openjdk@25/bin/java'
 cp := os.real_path('build/android-framework/tools') + '/*'
 for args in [[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'],
 ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
 [java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes', 'Landroid/provider/ContactsContract$CommonDataKinds$Email;,Landroid/provider/ContactsContract$CommonDataKinds$Phone;', '--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip']] {
  if os.system_args(args) != 0 { panic('SDK assembly/readback failed') }
 }
 for kind in ['Email', 'Phone'] {
  source := os.read_file(root + '/roundtrip/android/provider/ContactsContract$CommonDataKinds$' + kind + '.smali')!
  assert source.contains('.method public static final getTypeLabelResource(I)I')
  assert source.contains('.method public static getTypeLabel(Landroid/content/res/Resources;ILjava/lang/CharSequence;)Ljava/lang/CharSequence;')
 }
 println('CONTACT-LABELS-SDK-PASS assembly readback twenty-two-input-refusals')
}
