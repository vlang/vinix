// SPDX-License-Identifier: GPL-2.0-or-later
module main
import androidtools
import os
fn main() {
 if os.args.len != 3 { panic('usage: build-webview-loader-framework FRAMEWORK FRESH_EXTERNAL_OUTPUT') }
 base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
 if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') { panic('fresh external output required') }
 original := os.read_file(base + '/smali/android/webkit/WebView.smali')!
 changed := androidtools.framework_webview_loader_source(original)!
 for declaration in ['.class public Landroid/webkit/WebView;', '.super Landroid/view/ViewGroup;',
  '.method public static getCurrentWebViewPackage()Landroid/content/pm/PackageInfo;',
  '.method private native native_loadUrl(JLjava/lang/String;)V'] {
  for variant in [original.replace(declaration, ''), original + '\n' + declaration + '\n'] {
   mut rejected := false
   androidtools.framework_webview_loader_source(variant) or { rejected = true }
   assert rejected
  }
 }
 mut rejected := false
 androidtools.framework_webview_loader_source(changed) or { rejected = true }
 assert rejected
 os.mkdir_all(root)!
 os.cp_all(base + '/smali', root + '/smali', false)!
 os.write_file(root + '/smali/android/webkit/WebView.smali', changed)!
 os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
 java := '/opt/homebrew/opt/openjdk@25/bin/java'
 cp := os.real_path('build/android-framework/tools') + '/*'
 for args in [[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'],
 ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
 [java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes', 'Landroid/webkit/WebView;', '--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip']] {
  if os.system_args(args) != 0 { panic('SDK assembly/readback failed') }
 }
 roundtrip := os.read_file(root + '/roundtrip/android/webkit/WebView.smali')!
 assert roundtrip.count('.method public static getWebViewClassLoader()Ljava/lang/ClassLoader;') == 1
 assert roundtrip.contains('Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;')
 println('WEBVIEW-LOADER-SDK-PASS assembly readback nine-input-refusals')
}
