// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import crypto.sha256
import generators
import os

// BSD-licensed smali 2.5.2 and its Maven dependencies. These tools only
// assemble native declarations; the Android implementations are V JNI code.
const framework_tools = [
 'org/smali/smali/2.5.2/smali-2.5.2 136c5c4653d6531bd7b6f10f35f8691cb96432e727d30b4d5579826ee01e9419',
 'org/smali/baksmali/2.5.2/baksmali-2.5.2 1ed236266d7dc4907aade0b19a34f77efac25342b63c8ace52e579039941b389',
 'org/smali/dexlib2/2.5.2/dexlib2-2.5.2 5a5c8982d8bd7d6e3bb1a0713049e3c78b719ec32b20f6b619885cec30a0dd61',
 'org/smali/util/2.5.2/util-2.5.2 4f580a9cff3ebb83cb3fd20bec88e37e4f183796ca652732992611620282daea',
 'org/antlr/antlr/3.5.2/antlr-3.5.2 5ac36c2acfb0a0f3d37dafe20b5b570f2643e2d000c648d44503c2738be643df',
 'org/antlr/antlr-runtime/3.5.2/antlr-runtime-3.5.2 ce3fc8ecb10f39e9a3cddcbb2ce350d272d9cd3d0b1e18e6fe73c3b9389c8734',
 'org/antlr/stringtemplate/3.2.1/stringtemplate-3.2.1 f66ce72e965e5301cb0f020e54d2ba6ad76feb91b3cbfc30dbbf00c06a6df6d7',
 'antlr/antlr/2.7.7/antlr-2.7.7 88fbda4b912596b9f56e8e12e580cc954bacfb51776ecfddd3e18fc1cf56dc4c',
 'com/beust/jcommander/1.64/jcommander-1.64 156be736199c990321d9ff77090b199629cfc9865e2d6c13f7cd291bb1641817',
 'com/google/guava/guava/27.1-android/guava-27.1-android 686404f2d1d4d221911f96bd627ff60dac2226a5dfa6fb8ba517073eb97ec0ef',
 'com/google/guava/failureaccess/1.0.1/failureaccess-1.0.1 a171ee4c734dd2da837e4b16be9df4661afab72a41adaf31eb84dfdaf936ca26',
]

fn framework_digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

pub fn framework_replace_method(source string, name string, declaration string) !string {
 mut text := source
 mut found := false
 for block in source.split('.method ') {
  if !block.all_before('\n').ends_with(' ' + name) { continue }
  if found { return error('duplicate framework method: ' + name) }
  end := block.index('.end method') or { return error('unterminated framework method: ' + name) }
  text = text.replace('.method ' + block[..end + '.end method'.len], declaration)
  found = true
 }
 if !found { text += '\n' + declaration + '\n' }
 return text
}

// Missing packages must stay missing. The upstream GStub fallback advertises
// services that are not installed and starts a separate class loader while
// holding the global package lock. Preserve normal APK loading and lock exits.
pub fn framework_package_presence(source string) !string {
 mut text := source
 for name in ['loadApplication', 'loadPackage'] {
  signature := '.method private static ' + name + '(Ljava/lang/String;)'
  start := text.index(signature) or { return error('missing ATL package loader: ' + name) }
  end := start + (text[start..].index('.end method') or { return error('unterminated ATL package loader') })
  method := text[start..end]
  fallback := '    sget-object v0, Landroid/atl/ATLLoadedApp;->play_services:Ljava/util/HashSet;'
  first := method.index(fallback) or { return error('missing ATL package fallback: ' + name) }
  tail := method[first..]
  condition := tail.index('    if-eqz v0, :') or { return error('missing ATL package absence branch') }
  label := tail[condition..].all_before('\n').all_after(', ')
  mut last := first + (tail.index('\n    ' + label + '\n') or { return error('missing ATL package absence label') })
  // loadApplication has a catch handler before its missing-package exit.
  if handler := tail.index('\n    :catchall_') {
   if first + handler < last { last = first + handler }
  }
  if !method[first..last].contains('->loadGStub(') { return error('unexpected ATL package fallback') }
  replacement := method[..first] + '    goto/16 ' + label + '\n' + method[last..]
  text = text[..start] + replacement + text[end..]
 }
 return text
}

pub fn framework_patch(activity_source string, bar_source string, cursor_v string, bar_v string) !(string, string) {
 if activity_source.contains('vinixActionBar:') { return error('framework is already extended; use the original ATL input') }
 mut activity := activity_source
 main := '.method private static createMainActivity(Ljava/lang/String;JLjava/lang/String;)Landroid/app/Activity;'
 if activity.count(main) != 1 { return error('unexpected ATL main activity factory') }
 activity = activity.replace(main, main.replace('private static createMainActivity', 'public static vinixOriginalCreateMainActivity'))
 for name in ['Start', 'Stop', 'Destroy'] {
  old := '.method protected on${name}()V'
  if activity.count(old) != 1 { return error('unexpected ATL lifecycle declaration: ' + old) }
  activity = activity.replace(old, '.method public vinixOriginalOn${name}()V')
 }
 activity += '\n.field private vinixCursors:Ljava/util/ArrayList;\n.field private vinixCursorsStopped:I\n.field private vinixActionBar:Landroid/app/ActionBar;\n.field private vinixMenu:Landroid/view/VinixMenu;\n'
 activity += '.field private vinixSavedState:Landroid/os/Bundle;\n.field private vinixSavedViews:Landroid/util/SparseArray;\n.field private vinixPostCreatePending:I\n'
 mut bar := bar_source
 for declaration in [
  'vinixOwner:Landroid/app/Activity;', 'vinixHeader:Landroid/view/ViewGroup;',
  'vinixRoot:Landroid/view/ViewGroup;', 'vinixTitleView:Landroid/widget/TextView;',
  'vinixSubtitleView:Landroid/widget/TextView;', 'vinixTitle:Ljava/lang/CharSequence;',
  'vinixSubtitle:Ljava/lang/CharSequence;', 'vinixCustom:Landroid/view/View;',
  'vinixDisplayOptions:I', 'vinixShowing:I',
  'vinixMenuPanel:Landroid/view/ViewGroup;', 'vinixMenuScroll:Landroid/view/View;',
  'vinixBack:Landroid/view/View;',
 ] { bar += '\n.field private ' + declaration + '\n' }
 for index, source in [cursor_v, bar_v] {
  mut count := 0
  for entry in source.split('NativeMethod{')[1..] {
   parts := entry.split("c'")
   if parts.len < 3 { return error('malformed V native registration') }
   name := parts[1].all_before("'") + parts[2].all_before("'")
   declaration := '.method public ' + if name.starts_with('createMainActivity(') { 'static ' } else { '' } + 'native ' + name + '\n.end method'
   if index == 0 { activity = framework_replace_method(activity, name, declaration)! }
   else { bar = framework_replace_method(bar, name, declaration)! }
   count++
  }
  if count == 0 { return error('no V native registrations found') }
 }
 return activity, bar
}

pub fn extend_framework(input string, output string, work string, tools string, java string) !ah.Value {
 os.mkdir_all(work)!
 os.mkdir_all(tools)!
 mut tool_hashes := map[string]ah.Value{}
 for record in framework_tools {
  parts := record.split(' ')
  name := parts[0].all_after_last('/') + '.jar'
  path := tools + '/' + name
  if !os.exists(path) {
   checked(['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '3', '--output', path + '.part', 'https://repo.maven.apache.org/maven2/' + parts[0] + '.jar'])!
   if framework_digest(path + '.part')! != parts[1] { os.rm(path + '.part')!; return error('framework tool checksum mismatch: ' + name) }
   os.mv(path + '.part', path)!
  }
  if framework_digest(path)! != parts[1] { return error('framework tool checksum mismatch: ' + name) }
  tool_hashes[name] = ah.Value(parts[1])
 }
 input_hash := framework_digest(input)!
 smali := work + '/smali'
 if os.exists(smali) { os.rmdir_all(smali)! }
 checked([java, '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', input, '-o', smali])!
 for name, hash in framework_signature_dependency(smali, work, tools, java)! { tool_hashes[name] = ah.Value(hash) }
 cursor_v := os.read_file(root() + '/build-support/android/atlframework/cursors.v')!
 bar_v := os.read_file(root() + '/build-support/android/atlframework/actionbar.v')!
 activity, bar := framework_patch(os.read_file(smali + '/android/app/Activity.smali')!, os.read_file(smali + '/android/app/ActionBar.smali')!, cursor_v, bar_v)!
 os.write_file(smali + '/android/app/Activity.smali', activity)!
 os.write_file(smali + '/android/app/ActionBar.smali', bar)!
 packages := smali + '/android/atl/ATLLoadedAppManager.smali'
 os.write_file(packages, framework_package_presence(os.read_file(packages)!)!)!
 write_framework_classes(smali)!
 framework_application_startup(smali)!
 framework_companion_contexts(smali)!
 framework_package_storage(smali)!
 framework_application_info(smali)!
 framework_local_binder(smali)!
 framework_package_signatures(smali)!
 checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', smali, '-o', work + '/classes.dex'])!
 next := work + '/api-impl.jar'
 os.cp(input, next)!
 checked(['zip', '-q', '-j', next, work + '/classes.dex'])!
 framework_signature_notice(next, work, tools)!
 mut sources := map[string]ah.Value{}
 for file in ['jni.v', 'cursors.v', 'actionbar.v', 'widgets.v', 'dialogs.v', 'menus.v', 'charsets.v', 'themes.v', 'recreate.v', 'views.v'] { sources['build-support/android/atlframework/' + file] = ah.Value(framework_digest(root() + '/build-support/android/atlframework/' + file)!) }
 sources['tests/native-android-tools/androidtools/framework_classes.v'] = ah.Value(framework_digest(root() + '/tests/native-android-tools/androidtools/framework_classes.v')!)
 sources['tests/native-android-tools/androidtools/framework_content.v'] = ah.Value(framework_digest(root() + '/tests/native-android-tools/androidtools/framework_content.v')!)
 sources['tests/native-android-tools/androidtools/framework.v'] = ah.Value(framework_digest(root() + '/tests/native-android-tools/androidtools/framework.v')!)
 sources['tests/native-android-tools/androidtools/framework_signatures.v'] = ah.Value(framework_digest(root() + '/tests/native-android-tools/androidtools/framework_signatures.v')!)
 sources['tests/native-android-tools/androidtools/framework_application.v'] = ah.Value(framework_digest(root() + '/tests/native-android-tools/androidtools/framework_application.v')!)
 sources['tests/native-android-tools/androidtools/framework_services.v'] = ah.Value(framework_digest(root() + '/tests/native-android-tools/androidtools/framework_services.v')!)
 sources['tests/native-android-tools/androidtools/framework_package_storage.v'] = ah.Value(framework_digest(root() + '/tests/native-android-tools/androidtools/framework_package_storage.v')!)
 sources['tests/native-android-tools/androidtools/framework_package_info.v'] = ah.Value(framework_digest(root() + '/tests/native-android-tools/androidtools/framework_package_info.v')!)
 sources['tests/native-android-tools/androidtools/framework_binder.v'] = ah.Value(framework_digest(root() + '/tests/native-android-tools/androidtools/framework_binder.v')!)
 receipt := ah.Value({
  'schema': ah.Value(1)
  'input_sha256': ah.Value(input_hash)
  'output_sha256': ah.Value(framework_digest(next)!)
  'sources': ah.Value(sources)
  'tools': ah.Value(tool_hashes)
  'java_version': ah.Value(checked([java, '-version'])!.stderr.trim_space())
 })
 os.mkdir_all(os.dir(output))!
 os.cp(next, output + '.next')!
 os.mv(output + '.next', output)!
 os.write_file(work + '/framework-manifest.json', ah.encode(receipt) + '\n')!
 return receipt
}

pub fn framework_cli(argv []string) !int {
 args := parse_arguments(argv, ['--work', '--tools', '--java'], []string{}, []string{}, 2, 2, 'extend-framework INPUT.jar OUTPUT.jar [--work DIR --tools DIR --java JAVA]')!
 work := os.abs_path(args.value('--work', root() + '/build/android-framework-extension'))
 extend_framework(os.abs_path(args.positional[0]), os.abs_path(args.positional[1]), work, os.abs_path(args.value('--tools', work + '/tools')), args.value('--java', 'java'))!
 return 0
}

pub fn build_framework_library(output string, compiler string, generated string, arch string) ! {
 os.mkdir_all(generated)!
 os.mkdir_all(os.dir(output))!
 source := generated + '/android-framework.c'
 generators.generate_module(root() + '/build-support/android/atlframework', source, arch, []string{})!
 checked([compiler, '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-Wl,-z,max-page-size=65536', source, '-ldl', '-o', output])!
}

pub fn framework_launcher(source string) !string {
 old := 'guest_preload="$runtime/usr/lib/libvinix-android-compat.so"'
 if source.count(old) != 1 { return error('unexpected Android launcher preload declaration') }
 // ATL locates its DEX directory relative to JNI_CreateJavaVM's library.
 // Keep this JNI provider beside libart in the private ART directory.
 return source.replace(old, 'guest_preload="$runtime/usr/lib/libvinix-android-compat.so:$runtime/usr/lib/art/libvinix-android-framework.so"')
}
