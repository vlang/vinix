// SPDX-License-Identifier: GPL-2.0-or-later
// Isolated production-provider guards and exact Service-only DEX roundtrip.
module main
import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn command(work string, label string, argv []string) ! {
	result := os.exec(argv)
	os.write_file(work + '/' + label + '.json', json2.encode({
		'argv': json2.Any(argv), 'exit_code': json2.Any(result.exit_code), 'output': json2.Any(result.output)
	}, prettify: true) + '\n')!
	assert result.exit_code == 0, label + ': ' + result.output
	assert result.output.trim_space() == '', label + ': unexpected diagnostics'
}
fn main() {
	$if prod { panic('live assertions required') }
	assert os.args.len == 7, 'usage: service-lifecycle-source-check V REPO FRESH_OUTPUT BASELINE_SMALI JAVA SMALI_TOOLS'
	compiler, repo := os.real_path(os.args[1]), os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	baseline, java, tools := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	assert !os.exists(work) && !os.is_link(work) && work != repo && !work.starts_with(repo + '/')
	os.mkdir_all(work + '/androidtools')!
	for name in ['app', 'content', 'os'] { os.mkdir_all(work + '/proof/android/' + name)! }
	mut pins := map[string]string{}
	provider := repo + '/tests/native-android-tools/androidtools/framework_service_lifecycle.v'
	integration := repo + '/tests/native-android-tools/androidtools/framework.v'
	for path in [compiler, java, @FILE, provider, integration] { pins[path] = digest(path)! }
	assert os.read_file(integration)!.contains(' framework_service_bindings(smali)!\n framework_service_lifecycle(smali)!')
	os.cp(provider, work + '/androidtools/provider.v')!
	assert digest(work + '/androidtools/provider.v')! == pins[provider]!
	mut classes := ['android/app/Service', 'android/content/Context', 'android/content/ContextWrapper']
	for name in os.ls(baseline + '/android/os')! {
		if name.starts_with('StrictMode') && name.ends_with('.smali') { classes << 'android/os/' + name.all_before_last('.') }
	}
	assert 'android/os/StrictMode' in classes && classes.len > 4, 'StrictMode preservation inputs required'
	for name in classes {
		path := baseline + '/' + name + '.smali'
		pins[path] = digest(path)!
		os.cp(path, work + '/proof/' + name + '.smali')!
		assert digest(work + '/proof/' + name + '.smali')! == pins[path]!
	}
	for name in os.ls(tools)! { if name.ends_with('.jar') { pins[tools + '/' + name] = digest(tools + '/' + name)! } }
	os.write_file(work + '/check.v', checker)!
	command(work, 'compile', [compiler, '-nocache', '-path', '@vlib|' + work, '-cc', 'cc', '-o', work + '/check', work + '/check.v'])!
	command(work, 'source', [work + '/check', work])!
	for kind in ['baseline', 'patched'] {
		directory := work + '/' + kind + '-smali'
		os.mkdir_all(directory + '/android/app')!
		input := if kind == 'baseline' { baseline + '/android/app/Service.smali' } else { work + '/proof/android/app/Service.smali' }
		os.cp(input, directory + '/android/app/Service.smali')!
		dex := work + '/' + kind + '.dex'
		assert !os.exists(dex)
		command(work, kind + '-assemble', [java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', directory, '-o', dex])!
		assert os.is_file(dex) && os.file_size(dex) > 112, 'fresh DEX required'
		command(work, kind + '-disassemble', [java, '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2', dex, '-o', work + '/' + kind + '-roundtrip'])!
	}
	command(work, 'roundtrip', [work + '/check', work, '--roundtrip'])!
	for name in classes {
		if name != 'android/app/Service' { assert digest(work + '/proof/' + name + '.smali')! == pins[baseline + '/' + name + '.smali']!, 'unrelated framework class changed' }
	}
	for path, pin in pins { assert digest(path)! == pin, 'input changed: ' + path }
	for path in ['check.v', 'androidtools/provider.v', 'check', 'baseline.dex', 'patched.dex', 'proof/android/app/Service.smali'] {
		pins[work + '/' + path] = digest(work + '/' + path)!
	}
	os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
	println('SERVICE-LIFECYCLE-SOURCE-PASS three-method-only supercall constructors-context-strictmode-preserved guards=11 API28-DEX-roundtrip')
}

const checker = '
module main
import androidtools
import os
fn method(source string, signature string) string {
 mut found := ""
 for block in source.split(".method ")[1..] {
  if !block.all_before("\\n").ends_with(" " + signature) { continue }
  assert found == ""
  found = ".method " + block.all_before(".end method") + ".end method"
 }
 assert found != ""
 return found
}
fn unchanged_except_callbacks(old string, patched string) {
 mut old_rest := old
 mut patched_rest := patched
 for signature in ["attachBaseContext(Landroid/content/Context;)V", "onCreate()V", "onDestroy()V"] {
  before := method(old,signature)
  after := method(patched,signature)
  assert before != after
  old_rest = old_rest.replace(before,"CALLBACK:" + signature)
  patched_rest = patched_rest.replace(after,"CALLBACK:" + signature)
  expected := if signature.starts_with("attachBaseContext(") {
   ".method public " + signature + "\\n.registers 2\\ninvoke-super {p0, p1}, Landroid/content/ContextWrapper;->attachBaseContext(Landroid/content/Context;)V\\nreturn-void\\n.end method"
  } else { ".method public " + signature + "\\n.registers 1\\nreturn-void\\n.end method" }
  assert after.split_into_lines().map(it.trim_space()).filter(it != "").join("\\n") == expected
 }
 assert old_rest == patched_rest, "bytes outside three callback methods changed"
 assert method(old,"<init>()V") == method(patched,"<init>()V")
}
fn main() {
 assert os.args.len in [2,3]
 work := os.args[1]
 if os.args.len == 3 {
  assert os.args[2] == "--roundtrip"
  old := os.read_file(work + "/baseline-roundtrip/android/app/Service.smali")!
  patched := os.read_file(work + "/patched-roundtrip/android/app/Service.smali")!
  unchanged_except_callbacks(old,patched)
  return
 }
 path := work + "/proof/android/app/Service.smali"
 old := os.read_file(path)!
 patched := androidtools.framework_service_lifecycle_source(old)!
 unchanged_except_callbacks(old,patched)
 for invalid in [old.replace("onCreate()V", "missingCreate()V"),
  old + method(old,"onCreate()V"), old.replace("Landroid/app/Service;", "Lwrong/Service;"),
  old.replace(".super Landroid/content/ContextWrapper;", ".super Ljava/lang/Object;"),
  old.replace(".method public onDestroy()V", ".method private onDestroy()V"),
  old.replace("Service.onCreate() called", "different diagnostic"),
  old.replace("invoke-super {p0, p1}", "invoke-super {p0, p0}"),
  old.replace(".method public attachBaseContext", ".method public final attachBaseContext"),
  old.replace("    .registers 3\\n", "    .registers 3\\n    iput v0, p0, Landroid/app/Service;->notification_id:I\\n"),
  old.replace(".method public onCreate()V", ".method public native onCreate()V"), patched] {
  assert invalid != old, "negative mutation did not match baseline"
  os.write_file(path,invalid)!
  mut rejected := false
  androidtools.framework_service_lifecycle(work + "/proof") or { rejected = true }
  assert rejected && os.read_file(path)! == invalid, "invalid provider application mutated input"
 }
 os.write_file(path,old)!
 androidtools.framework_service_lifecycle(work + "/proof")!
 assert os.read_file(path)! == patched, "filesystem integration differs"
}
'
