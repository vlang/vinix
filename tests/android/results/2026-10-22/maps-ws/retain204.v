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
  'build-framework204.v':'framework204-build.v','framework204/framework-manifest.json':'framework204-manifest.json',
  'build-native204.v':'native204-build.v','native204-sources.json':'native204-sources.json',
  'prepare204.v':'prepare204.v','run-font204.v':'run-font204.v','run204.v':'run204.v','stage-aux204.v':'stage-aux204.v',
  'validate204.v':'validate204.v','validate204.log':'validate204.log','retain204.v':'retain204.v',
  'attempt204/launcher-runtime-sha256.json':'attempt204-launcher-runtime-sha256.json',
  'attempt204-harness.log':'attempt204-harness.log','interact204.log':'attempt204-interaction.log',
  'run-font204-baseline.log':'fixture-font204-baseline-harness.log','run-font204-fixed.log':'fixture-font204-fixed-harness.log'
 }{os.cp(base+src,root+name)!;artifacts[name]=hash(root+name)!}
 for kind in ['framework','native']{
  src:=base+'build-'+kind+'204.log'
  name:=kind+'204-build.log.gz'
  os.write_file_array(root+name,gzip.compress(os.read_bytes(src)!)!)!
  artifacts[name]=hash(root+name)!
 }
 artifacts['native204-source-snapshot.tar.gz']=hash(root+'native204-source-snapshot.tar.gz')!
 r:=os.exec(['tar','-czf',os.abs_path(root+'font204-fixture-source.tar.gz'),'-C',base+'font204-apk','smali','res'])
 assert r.exit_code==0,r.output
 artifacts['font204-fixture-source.tar.gz']=hash(root+'font204-fixture-source.tar.gz')!
 mut sources:=map[string]json2.Any{}
 for file in ['build-support/android/nativews/fonts.v','tests/native-android-tools/androidtools/framework_font_builders.v','tests/native-android-tools/androidtools/framework_classes.v','tests/native-android-ws/startupfixture/font_builders.v','tests/native-android-ws/startupfixture/startup.v']{
  s:=os.exec(['git','show','05f4df052:'+file]);assert s.exit_code==0
  sources[file]=sha256.sum(s.output.bytes()).hex()
 }
 receipt:={
  'artifacts_sha256':json2.Any(artifacts),'committed_sources_sha256':json2.Any({'05f4df052':json2.Any(sources)}),
  'framework204_sha256':json2.Any(hash(base+'framework204/api-impl.jar')!),
  'native204_sha256':json2.Any(hash(base+'libnative204.so')!),
  'fixture_apk_sha256':json2.Any(hash(base+'font204-apk/bootstrap.apk')!),
  'scope':json2.Any('Resource Font.Builder, FontStyle, immutable FontFamily and nearest primary-family CustomFallbackBuilder selection. Static font metadata reads bounded OS/2 table values. Same signed APK fails framework201/native200 on missing Font$Builder and passes framework204/native204, including all 8192 pixels for each selection and 87 earlier pass markers. Font collections, variations, file/descriptor constructors and multi-family glyph fallback remain unavailable. Maps functional status is recorded separately from the fixture.'),
  'references':json2.Any([
   json2.Any('https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android10-release/graphics/java/android/graphics/fonts/Font.java'),
   json2.Any('https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android10-release/graphics/java/android/graphics/fonts/FontStyle.java'),
   json2.Any('https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android10-release/graphics/java/android/graphics/fonts/FontFamily.java'),
   json2.Any('https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android10-release/graphics/java/android/graphics/Typeface.java')])
 }
 os.write_file(root+'runtime204-build.json',json2.encode(receipt,prettify:true)+'\n')!
 mut doc:=json2.decode[map[string]json2.Any](os.read_file(root+'results.json')!)!
 mut rows:=doc['applications']!.as_array().clone()
 for run in ['fixture-font204-baseline','fixture-font204-fixed','attempt204']{
  assert !rows.any(it.as_map()['run']!.str()==run),'already retained '+run
  batch:=base+run
  mut row:=json2.decode[[]json2.Any](os.read_file(batch+'/results.json')!)![0].as_map().clone()
  id:=row['id']!.str();state:=batch+'/'+id+'/'
  serial:=gzip.decompress(os.read_bytes(state+'serial.log.gz')!)!
  assert sha256.sum(serial).hex()==row['serial_sha256']!.str(),run
  row['run']=run;row['runtime_sha256']=json2.decode[json2.Any](os.read_file(batch+'/runtime-sha256.json')!)!
  row['kernel_sha256']='f8d86366353da19545fa6814b7b54d53973e59fdbafe2575c96c13594284b352'
  row['kernel_build_receipt']='arp-kernels.json';row['boot_base_receipt']='boot-base161.json';row['build_receipt']='runtime204-build.json'
  row['startup_ui_passed']=false;row['search_passed']=false
  row['harness_binary_sha256']=hash(base+'suite159')!
  row['harness_source_verified']=true
  row['manual_review']=match run{
   'fixture-font204-baseline'{'EXPECTED FAIL: same signed final font fixture stops at missing Font$Builder against framework201/native200.'}
   'fixture-font204-fixed'{'PASS synthetic regression: same signed fixture checks metadata, builder reuse, immutable family snapshots, duplicate style rejection, nearest style selection, 8192-pixel comparisons, XML/range/unsupported rejection; all 87 earlier pass markers remain. Native backend ready with GTK and X11 absent.'}
   else{os.read_file(base+'attempt204-review.txt')!.trim_space()}
  }
  for file,field in {'serial.log.gz':'serial_log','application.png':'screenshot','initial.png':'initial_screenshot','skip.png':'skip_screenshot','pan.png':'pan_screenshot','zoom.png':'zoom_screenshot','search-typed.png':'typed_screenshot','search.png':'search_screenshot','search-later.png':'later_screenshot','sheet.png':'sheet_screenshot','network.pcap':'network_capture'}{
   if !os.is_file(state+file){continue}
   name:=run+'-'+id+'-'+file;os.cp(state+file,root+name)!;row[field]=name
   if file!='serial.log.gz'{row[field+'_sha256']=hash(root+name)!}
  }
  mut saved:=map[string]json2.Any{}
  mut scripts:={run+'-configuration.json':batch+'.json',run+'-suite.v':base+'suite-low-disk.v',run+'-launcher.v':base+'trace200-launcher.v'}
  if run=='attempt204'{scripts[run+'-interaction.v']=base+'interact204.v'}
  for name,path in scripts{os.cp(path,root+name)!;saved[name]=hash(root+name)!}
  row['harness_artifacts_sha256']=json2.Any(saved);rows<<json2.Any(row)
 }
 doc['applications']=json2.Any(rows)
 os.write_file(root+'results.json',json2.encode(doc,prettify:true)+'\n')!
 println('Retained '+rows.len.str()+' runs')
}
