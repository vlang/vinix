// SPDX-License-Identifier: GPL-2.0-or-later
// Compose the pinned Maps370 generator with the independently qualified371 repair.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const work = state + 'maps372-generator-composition-b-2026-10-26'
const original = repo + '/tests/native-android-ws/maps370-generate.v'
const original_pin = 'b3b7cc8a7f669c0b302c1b7d842c88915c655df7173b805339ab8301a8599633'
const original_commit = 'fb3b07283836c48919e1d8d3e667e56799240a69'
const peer = repo + '/tests/native-android-ws/intent-uri371-framework-peer-check.v'
const peer_pin = '2b5ad54bb7ec4ba4de41ee400cf3a5555f2db2cb7f5a02afc1dca29951790f7f'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const framework = state + 'intent-uri371-framework-build-2026-10-26'
const manifest = '71e311764ece295185656854294a514a9c641419c567d5f96ac66f52f4b89750'
const jar = '3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21'
const output = work + '/maps372-generate.v'
const recorded = repo + '/build/android-maps/maps372-generate-recorded'
const build_root = state + 'maps372-generator-build-2026-10-26'

fn hash(path string) !string {
 assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular, path
 return sha256.sum(os.read_bytes(path)!).hex()
}
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn replace_once(text string, before string, after string) !string {
 if text.count(before) != 1 { return error('unique replacement required: ' + before) }
 return text.replace(before, after)
}
fn contract(text string, version string) string {
 begin := '\n// BEGIN SHARED FRAMEWORK' + version + ' CONTRACT\n'
 end := '\n// END SHARED FRAMEWORK' + version + ' CONTRACT\n'
 assert text.count(begin) == 1 && text.count(end) == 1
 return text.all_after(begin).all_before(end)
}

fn getter_contract() string {
 return r'
fn getter371_body(text string) ![]string {
 header := ".method public getDataString()Ljava/lang/String;"
 if text.split_into_lines().filter(it == header).len != 1 { return error("unique getDataString required") }
 return text.all_after(header + "\n").all_before(".end method").split_into_lines().map(it.trim_space()).filter(it.len > 0)
}
fn getter371_expected(dex bool, target string) []string {
 return [if dex { ".registers 2" } else { ".locals 1" },
  "iget-object v0, p0, Landroid/content/Intent;->data:Landroid/net/Uri;",
  "if-nez v0, " + target, if dex { "const/4 v0, 0x0" } else { "const/4 v0, 0" },
  "return-object v0", target,
  "invoke-virtual {v0}, Landroid/net/Uri;->toString()Ljava/lang/String;",
  "move-result-object v0", "return-object v0"]
}
fn getter371_check(text string, dex bool) ! {
 body := getter371_body(text)!
 if body.len != 9 || !body[2].starts_with("if-nez v0, :") { return error("null-data getter branch differs") }
 target := if dex { body[2].all_after("if-nez v0, ") } else { ":has_data" }
 if body != getter371_expected(dex, target) { return error("exact null-data getter required") }
}
fn qualify_getter371(root string) ! {
 path := root + "/framework/smali/android/content/Intent.smali"
 if hash(path)! != "cf947375973e5e03b7df25c8288d9c899955e86ff0a20c5a299356e2e34a303d" {
  return error("qualified371 Intent source differs")
 }
 getter371_check(os.read_file(path)!, false)!
 getter371_check(os.read_file(root + "/framework/new-dex/android/content/Intent.smali")!, true)!
}
'
}

fn getter_self_test() string {
 return r'
fn getter371_self_test() ! {
 header := ".method public getDataString()Ljava/lang/String;\n"
 source := header + getter371_expected(false, ":has_data").join("\n") + "\n.end method\n"
 dex := header + getter371_expected(true, ":cond_6").join("\n") + "\n.end method\n"
 getter371_check(source, false)!
 getter371_check(dex, true)!
 mut rejected := 0
 for bad in [source.replace("const/4 v0, 0", "const-string v0, " + u8(34).ascii_str() + u8(34).ascii_str()),
  source.replace(".locals 1", ".locals 2"), source.replace("if-nez v0", "if-eqz v0"),
  source.replace("Uri;->toString()", "Uri;->getScheme()"), source + source,
  dex.replace("const/4 v0, 0x0", "const/4 v0, 0x1"), dex.replace("\n:cond_6\n", "\n:cond_7\n")] {
  getter371_check(bad, bad.contains(".registers")) or { rejected++; continue }
  return error("invalid null getter accepted")
 }
 assert rejected == 7
}
'
}

fn derive(before string) !string {
 mut text := before
 for label in ['maps370', 'Maps370', 'MAPS370', 'attempt370', 'suite370', 'validate_styled370', 'fresh370', "'370'"] {
  text = text.replace(label, label.replace('370', '372'))
 }
 text = text.replace('Intent-uri369 framework', 'Intent-uri371 framework').replace('intent-uri369 framework', 'intent-uri371 framework')
 text = replace_once(text, '// BEGIN SHARED FRAMEWORK369 CONTRACT\n', '// BEGIN SHARED FRAMEWORK369 CONTRACT\n' + getter_contract().trim_left('\n'))!
 text = replace_once(text,
  "fn qualify_framework369(root string, manifest_pin string, jar_pin string) !int {\n\tcount := qualify_build(root, manifest_pin, 'framework/api-impl.jar', jar_pin)!",
  "fn qualify_framework369(root string, manifest_pin string, jar_pin string) !int {\n\tcount := qualify_build(root, manifest_pin, 'framework/api-impl.jar', jar_pin)!\n\tqualify_getter371(root)!")!
 text = replace_once(text, '\nfn self_test(output string) ! {', getter_self_test() + '\nfn self_test(output string) ! {\n\tgetter371_self_test()!')!
 text = replace_once(text,
  'fn generate(framework_root string, manifest_pin string, jar_pin string) ! {',
  'fn generate(framework_root string, manifest_pin string, jar_pin string) ! {\n\tassert framework_root == ' + "'" + framework + "' && manifest_pin == '" + manifest + "' && jar_pin == '" + jar + "'")!
 for version in ['359', '361', '365', '367'] { assert contract(text, version) == contract(before, version) }
 assert contract(text, '369').contains('qualify_getter371(root)!')
 assert text.contains("settings['applications']!.as_array()[0].as_map()['startup_seconds']!.int() != 600")
 assert text.contains("'unchanged_runtime_entries': '106'") && text.contains('if classifier(suite_text)! != classifier(original)!')
 assert text.contains("['vinix', 'initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar']")
 return text
}

fn self_test() ! {
 assert hash(original)! == original_pin && hash(peer)! == peer_pin
 before := os.read_file(original)!
 derived := derive(before)!
 assert derived == derive(before)! && !derived.contains('maps370') && !derived.contains('MAPS370')
 assert derived.contains("config.replace('372', '350')")
 assert derived.contains("text = text.replace(prefix + '368', prefix + '372')")
 assert derived.contains("normalized = normalized.replace(prefix + '372', prefix + '368')")
 assert derived.contains('fn qualify_getter371(root string) !')
 assert derived.contains('getter371_self_test()!')
 replace_once('missing', 'needle', 'replacement') or {
  replace_once('needle needle', 'needle', 'replacement') or {
   println('MAPS372-COMPOSITION-SELF-TEST-PASS inherited=359,361,365,367 labels=372 exact371=true')
   return
  }
  return error('duplicate patch anchor accepted')
 }
 return error('missing patch anchor accepted')
}

fn command(label string, argv []string) ! {
 started := time.utc().str()
 executable_pin := hash(argv[0])!
 result := os.exec(argv)
 os.write_file(work + '/' + label + '.log', result.output)!
 write_json(work + '/' + label + '.json', {
  'argv': json2.Any(argv), 'cwd': json2.Any(os.getwd()), 'started_utc': json2.Any(started),
  'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(result.exit_code),
  'executable_sha256_before': json2.Any(executable_pin), 'executable_sha256_after': json2.Any(hash(argv[0])!),
  'stdout_stderr_sha256': json2.Any(hash(work + '/' + label + '.log')!),
  'VROOT': json2.Any(os.getenv('VROOT')), 'VTMP': json2.Any(os.getenv('VTMP')),
 })!
 assert result.exit_code == 0 && hash(argv[0])! == executable_pin, result.output
 print(result.output)
}
fn inventory(root string, prefix string, mut files map[string]string) ! {
 for name in os.ls(root + '/' + prefix)! {
  relative := if prefix == '' { name } else { prefix + '/' + name }
  path := root + '/' + relative
  assert !os.is_link(path)
  match os.lstat(path)!.get_filetype() {
   .directory { inventory(root, relative, mut files)! }
   .regular { files[relative] = hash(path)! }
   else { return error('nonregular composition artifact: ' + path) }
  }
 }
}
fn compose() ! {
 self_test()!
 for path in [work, build_root, recorded] { assert !os.exists(path) && !os.is_link(path), path }
 assert hash(compiler)! == compiler_pin
 assert hash(framework + '/sha256.json')! == manifest && hash(framework + '/framework/api-impl.jar')! == jar
 os.mkdir(work)!
 os.cp(@FILE, work + '/composer.v')!
 os.cp(os.executable(), work + '/composer')!
 os.cp(original, work + '/maps370-generator-reference.v')!
 os.cp(peer, work + '/intent371-peer-reference.v')!
 os.write_file(output, derive(os.read_file(original)!)!)!
 write_json(work + '/derivation.json', {
  'original_path': original, 'original_commit': original_commit, 'original_sha256': original_pin,
  'peer_reference_sha256': peer_pin, 'composer_sha256': hash(@FILE)!, 'derived_source_sha256': hash(output)!,
  'framework_root': framework, 'framework_manifest_sha256': manifest, 'framework_sha256': jar,
  'scope': 'Only fresh372 replay labels, exact qualified371 integration and additive null getter source/DEX checks. All historical contracts and inherited replay self-tests retained.',
 })!
 os.mkdir(work + '/generated-c')!
 os.setenv('VROOT', '/Users/alex/code/v', true)
 os.setenv('VTMP', work + '/generated-c', true)
 command('compile-generator', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-o', work + '/bootstrap', output])!
 command('generator-self-test', [work + '/bootstrap', '--self-test'])!
 command('recorded-generator-build', [work + '/bootstrap', 'rebuild', build_root, 'build/android-maps/maps372-generate-recorded'])!
 assert hash(original)! == original_pin && hash(peer)! == peer_pin
 assert hash(work + '/composer.v')! == hash(@FILE)! && hash(work + '/maps370-generator-reference.v')! == original_pin
 mut files := map[string]string{}
 inventory(work, '', mut files)!
 write_json(work + '/sha256.json', files)!
 println('MAPS372-COMPOSITION-PASS source=' + hash(output)! + ' generator=' + hash(recorded)! + ' manifest=' + hash(work + '/sha256.json')!)
}
fn main() {
 $if prod { panic('assertions required') }
 assert os.getwd() == repo
 assert os.args.len == 2, 'usage: maps372-generate compose | --self-test'
 if os.args[1] == '--self-test' { self_test() or { panic(err) }; return }
 assert os.args[1] == 'compose'
 compose() or { panic(err) }
}
