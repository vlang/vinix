import os
import json2
import crypto.sha256
import compress.gzip
const base='build/android-maps/'
const root='tests/android/results/2026-10-22/maps-ws/'
fn hash(path string)!string{return sha256.sum(os.read_bytes(path)!).hex()}
fn main(){
 mut artifacts:=map[string]json2.Any{}
 for src,name in {
  'build-framework205.v':'framework205-build.v','framework205/framework-manifest.json':'framework205-manifest.json',
  'prepare205.v':'prepare205.v','run-locales205.v':'run-locales205.v','run205.v':'run205.v','stage-aux205.v':'stage-aux205.v',
  'validate205.v':'validate205.v','validate205.log':'validate205.log','retain205.v':'retain205.v',
  'attempt205/launcher-runtime-sha256.json':'attempt205-launcher-runtime-sha256.json',
  'attempt205-harness.log':'attempt205-harness.log','interact205.log':'attempt205-interaction.log',
  'run-locales205-baseline.log':'fixture-locales205-baseline-harness.log','run-locales205-fixed.log':'fixture-locales205-fixed-harness.log'
 }{os.cp(base+src,root+name)!;artifacts[name]=hash(root+name)!}
 for kind in ['framework']{
  src:=base+'build-'+kind+'205.log'
  name:=kind+'205-build.log.gz'
  os.write_file_array(root+name,gzip.compress(os.read_bytes(src)!)!)!
  artifacts[name]=hash(root+name)!
 }
 r:=os.exec(['tar','-czf',os.abs_path(root+'locales205-fixture-source.tar.gz'),'-C',base+'locales205-apk','smali','res'])
 assert r.exit_code==0,r.output
 artifacts['locales205-fixture-source.tar.gz']=hash(root+'locales205-fixture-source.tar.gz')!
 mut sources:=map[string]json2.Any{}
 for file in ['tests/native-android-tools/androidtools/framework_text_locales.v','tests/native-android-tools/androidtools/framework_classes.v','tests/native-android-ws/startupfixture/text_locales.v','tests/native-android-ws/startupfixture/startup.v']{
  s:=os.exec(['git','show','3ee06406d:'+file]);assert s.exit_code==0
  sources[file]=sha256.sum(s.output.bytes()).hex()
 }
 receipt:={
  'artifacts_sha256':json2.Any(artifacts),'committed_sources_sha256':json2.Any({'3ee06406d':json2.Any(sources)}),
  'framework205_sha256':json2.Any(hash(base+'framework205/api-impl.jar')!),
  'native204_sha256':json2.Any(hash(base+'libnative204.so')!),
  'native_build_receipt':json2.Any('runtime204-build.json'),
  'fixture_apk_sha256':json2.Any(hash(base+'locales205-apk/bootstrap.apk')!),
  'scope':json2.Any('Paint and TextView ordered text locale state. Defaults are captured at construction and reset, copy/set preserve state, self-set avoids native Paint recycling, and TextView uses its TextPaint with layout/invalidate notifications. Null and empty inputs are rejected. Same signed APK fails the previous framework204 and passes framework205 with 88 earlier pass markers. Native backend is unchanged native204. Locale-aware shaping and glyph fallback remain unavailable. Maps functionality is reviewed separately.'),
  'references':json2.Any([json2.Any('https://android.googlesource.com/platform/frameworks/base/+/master/graphics/java/android/graphics/Paint.java'),json2.Any('https://android.googlesource.com/platform/frameworks/base/+/24aba4b/core/java/android/widget/TextView.java')])
 }
 os.write_file(root+'runtime205-build.json',json2.encode(receipt,prettify:true)+'\n')!
 mut doc:=json2.decode[map[string]json2.Any](os.read_file(root+'results.json')!)!
 mut rows:=doc['applications']!.as_array().clone()
 for run in ['fixture-locales205-baseline','fixture-locales205-fixed','attempt205']{
  assert !rows.any(it.as_map()['run']!.str()==run),'already retained '+run
  batch:=base+run
  mut row:=json2.decode[[]json2.Any](os.read_file(batch+'/results.json')!)![0].as_map().clone()
  id:=row['id']!.str();state:=batch+'/'+id+'/'
  serial:=gzip.decompress(os.read_bytes(state+'serial.log.gz')!)!
  assert sha256.sum(serial).hex()==row['serial_sha256']!.str(),run
  row['run']=run;row['runtime_sha256']=json2.decode[json2.Any](os.read_file(batch+'/runtime-sha256.json')!)!
  row['kernel_sha256']='f8d86366353da19545fa6814b7b54d53973e59fdbafe2575c96c13594284b352'
  row['kernel_build_receipt']='arp-kernels.json';row['boot_base_receipt']='boot-base161.json';row['build_receipt']='runtime205-build.json'
  row['startup_ui_passed']=false;row['search_passed']=false
  row['harness_binary_sha256']=hash(base+'suite159')!
  row['harness_source_verified']=true
  row['manual_review']=match run{
   'fixture-locales205-baseline'{'EXPECTED FAIL: same signed text locale fixture stops at missing Paint.getTextLocales against framework204/native204.'}
   'fixture-locales205-fixed'{'PASS synthetic regression: same signed fixture checks default snapshots, ordered list, primary locale, copy/set/self-set/reset, TextView Paint propagation, layout/invalidate and invalid inputs; all 88 earlier pass markers remain. Native backend ready with GTK and X11 absent.'}
   else{os.read_file(base+'attempt205-review.txt')!.trim_space()}
  }
  for file,field in {'serial.log.gz':'serial_log','application.png':'screenshot','initial.png':'initial_screenshot','skip.png':'skip_screenshot','pan.png':'pan_screenshot','zoom.png':'zoom_screenshot','search-typed.png':'typed_screenshot','search.png':'search_screenshot','search-later.png':'later_screenshot','sheet.png':'sheet_screenshot','network.pcap':'network_capture'}{
   if !os.is_file(state+file){continue}
   name:=run+'-'+id+'-'+file;os.cp(state+file,root+name)!;row[field]=name
   if file!='serial.log.gz'{row[field+'_sha256']=hash(root+name)!}
  }
  mut saved:=map[string]json2.Any{}
  mut scripts:={run+'-configuration.json':batch+'.json',run+'-suite.v':base+'suite-low-disk.v',run+'-launcher.v':base+'trace200-launcher.v'}
  if run=='attempt205'{scripts[run+'-interaction.v']=base+'interact205.v'}
  for name,path in scripts{os.cp(path,root+name)!;saved[name]=hash(root+name)!}
  row['harness_artifacts_sha256']=json2.Any(saved);rows<<json2.Any(row)
 }
 doc['applications']=json2.Any(rows)
 os.write_file(root+'results.json',json2.encode(doc,prettify:true)+'\n')!
 println('Retained '+rows.len.str()+' runs')
}
