import os
import androidtools
import crypto.sha256
import json2

fn main() {
	input := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
	assert sha256.sum(os.read_bytes(input)!).hex() == '4acb4a9356b7c0ed53498923e46fbe55acfabfe362f899a0a0a45bfd58f12357'
	output := os.abs_path('build/android-maps/framework240-date-ranges')
	os.mkdir_all(output + '/sources/androidtools')!
	androidtools.extend_framework(input, output + '/api-impl.jar', output, os.abs_path('build/android-framework/tools'), '/opt/homebrew/opt/openjdk@25/bin/java')!
 // extend_framework scans the live checkout. Preserve its raw receipt, then
 // describe the module actually compiled into this frozen build executable.
 os.cp(output + "/framework-manifest.json", output + "/framework-manifest-live-checkout.json")!
 mut manifest := json2.decode[map[string]json2.Any](os.read_file(output + "/framework-manifest.json")!)!
 mut sources := manifest["sources"]!.as_map()
 for key in sources.keys() {
  if key.starts_with("tests/native-android-tools/androidtools/") { sources.delete(key) }
 }
 for file in os.ls(output + "/sources/androidtools")! {
  if file.starts_with("framework") && file.ends_with(".v") {
   sources["tests/native-android-tools/androidtools/" + file] = sha256.sum(os.read_bytes(output + "/sources/androidtools/" + file)!).hex()
  }
 }
 manifest["sources"] = sources
 manifest["source_scope"] = "frozen compiled androidtools framework generators plus live checked ATL source inputs; raw live-checkout manifest retained separately"
 os.write_file(output + "/framework-manifest.json", json2.encode(manifest, prettify: true))!
 
	println('FRAMEWORK240-INSETS ' + sha256.sum(os.read_bytes(output + '/api-impl.jar')!).hex())
}
