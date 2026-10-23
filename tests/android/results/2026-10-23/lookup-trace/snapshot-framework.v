import os
import json2
import crypto.sha256
import compress.gzip
fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
 b:='build/android-maps/framework237-lookup/'
 raw:=json2.decode[map[string]json2.Any](os.read_file(b+'framework-manifest.json')!)!
 assert hash(b+'api-impl.jar')! == raw['output_sha256']!.str()
 mut source:=map[string]string{}
 mut hashes:=map[string]string{}
 for path in os.walk_ext(b+'sources/androidtools','.v') {
  name:='tests/native-android-tools/androidtools/'+os.base(path)
  source[name]=os.read_file(path)!
  hashes[name]=hash(path)!
 }
 for name,digest in raw['sources']!.as_map() {
  if !name.starts_with('build-support/android/atlframework/') {continue}
  assert hash(name)! == digest.str()
  source[name]=os.read_file(name)!
  hashes[name]=hash(name)!
 }
 os.write_file_array(b+'frozen-sources.json.gz',gzip.compress(json2.encode(source).bytes())!)!
 os.write_file(b+'frozen-source-sha256.json',json2.encode(hashes,prettify:true)+'\n')!
 // Exact immutable236 module plus own two changes: no concurrent Insets hook.
 for path in os.walk_ext('build/android-maps/framework236-texture/sources/androidtools','.v') {
  name:=os.base(path)
  if name=='framework_startup.v' {continue}
  assert hash(path)! == hash(b+'sources/androidtools/'+name)!,name
 }
 startup:=os.read_file(b+'sources/androidtools/framework_startup.v')!
 assert startup.replace_once(' framework_lookup_trace(smali)!\n','')==os.read_file('build/android-maps/framework236-texture/sources/androidtools/framework_startup.v')!
 assert !startup.contains('framework_window_insets')
 println('LOOKUP237 FROZEN SOURCE PASS '+source.len.str()+' exact inputs; raw checkout manifest retained separately')
 r:=os.exec(['/opt/homebrew/opt/openjdk@25/bin/java','-cp','build/android-framework/tools/*','org.jf.baksmali.Main','disassemble',b+'api-impl.jar','--classes','Landroid/view/ViewGroup;,Landroid/atl/VinixViewLookupTrace;','-o',b+'actual-dex'])
 assert r.exit_code==0,r.output
 dex:=os.read_file(b+'actual-dex/android/view/ViewGroup.smali')!
 assert dex.count('Landroid/atl/VinixViewLookupTrace;->enabled:Z')==2
 assert os.read_file(b+'actual-dex/android/atl/VinixViewLookupTrace.smali')!.contains('VINIX_ANDROID_TRACE_VIEW_LOOKUP')
 println('LOOKUP237 ACTUAL DEX PASS both gates and opt-in class present')
}
