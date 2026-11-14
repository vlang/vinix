// SPDX-License-Identifier: GPL-2.0-or-later
// Extend the latest qualified SDK with the production bitmap buffer adapter.
module main
import androidtools
import os
fn main() {
 if os.args.len != 3 { panic('usage: build-bitmap-buffer-framework FRAMEWORK FRESH_EXTERNAL_OUTPUT') }
 base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
 if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') { panic('fresh external output required') }
 original := os.read_file(base + '/smali/android/graphics/Bitmap.smali')!
 changed := androidtools.framework_bitmap_buffers_source(original)!
 for declaration in ['.method public copyPixelsToBuffer(Ljava/nio/Buffer;)V', '.method public recycle()V', '.method private static native native_copy_to_buffer(JLjava/nio/Buffer;II)V'] {
  for variant in [original.replace(declaration, ''), original + '\n' + declaration + '\n'] {
   mut rejected := false
   androidtools.framework_bitmap_buffers_source(variant) or { rejected = true }
   assert rejected, 'changed or duplicate Bitmap declaration accepted'
  }
 }
 assert changed.contains('.method public declared-synchronized copyPixelsToBuffer(')
 assert changed.contains('.method public declared-synchronized recycle()V')
 assert changed.count('monitor-enter p0') >= 2 && changed.count('monitor-exit p0') >= 4
 os.mkdir_all(root)!
 os.cp_all(base + '/smali', root + '/smali', false)!
 os.write_file(root + '/smali/android/graphics/Bitmap.smali', changed)!
 os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
 java := '/opt/homebrew/opt/openjdk@25/bin/java'
 cp := os.real_path('build/android-framework/tools') + '/*'
 for args in [[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'],
 ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
 [java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes', 'Landroid/graphics/Bitmap;', '--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip']] {
  if os.system_args(args) != 0 { panic('SDK assembly/readback failed') }
  if !os.is_file(root + '/classes.dex') { panic('assembly did not produce DEX') }
 }
 roundtrip := os.read_file(root + '/roundtrip/android/graphics/Bitmap.smali')!
 assert roundtrip.contains('.method public declared-synchronized') || roundtrip.contains('.method public synchronized copyPixelsToBuffer(')
 assert roundtrip.contains('->native_copy_to_buffer(JLjava/nio/Buffer;II)V')
 println('BITMAP-BUFFER-SDK-PASS assembly readback six-declaration-refusals')
}
