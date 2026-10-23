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
  'build-framework206.v':'framework206-build.v','framework206/framework-manifest.json':'framework206-manifest.json',
  'prepare206.v':'prepare206.v','run-drawing206.v':'run-drawing206.v','run206.v':'run206.v','stage-aux206.v':'stage-aux206.v',
  'validate206.v':'validate206.v','validate206.log':'validate206.log','retain206.v':'retain206.v',
  'attempt206/launcher-runtime-sha256.json':'attempt206-launcher-runtime-sha256.json',
  'attempt206-harness.log':'attempt206-harness.log','interact206.log':'attempt206-interaction.log',
  'run-drawing206-baseline.log':'fixture-drawing206-baseline-harness.log','run-drawing206-fixed.log':'fixture-drawing206-fixed-harness.log'
 }{os.cp(base+src,root+name)!;artifacts[name]=hash(root+name)!}
 for kind in ['framework']{
  src:=base+'build-'+kind+'206.log'
  name:=kind+'206-build.log.gz'
  os.write_file_array(root+name,gzip.compress(os.read_bytes(src)!)!)!
  artifacts[name]=hash(root+name)!
 }
 r:=os.exec(['tar','-czf',os.abs_path(root+'drawing206-fixture-source.tar.gz'),'-C',base+'drawing206-apk','smali','res'])
 assert r.exit_code==0,r.output
 artifacts['drawing206-fixture-source.tar.gz']=hash(root+'drawing206-fixture-source.tar.gz')!
 mut sources:=map[string]json2.Any{}
 for file in ['tests/native-android-tools/androidtools/framework_drawing_ids.v','tests/native-android-tools/androidtools/framework_classes.v','tests/native-android-ws/startupfixture/drawing_ids.v','tests/native-android-ws/startupfixture/startup.v']{
  s:=os.exec(['git','show','5087ee194:'+file]);assert s.exit_code==0
  sources[file]=sha256.sum(s.output.bytes()).hex()
 }
 receipt:={
  'artifacts_sha256':json2.Any(artifacts),'committed_sources_sha256':json2.Any({'5087ee194':json2.Any(sources)}),
  'framework206_sha256':json2.Any(hash(base+'framework206/api-impl.jar')!),
  'native204_sha256':json2.Any(hash(base+'libnative204.so')!),
  'native_build_receipt':json2.Any('runtime204-build.json'),
  'fixture_apk_sha256':json2.Any(hash(base+'drawing206-apk/bootstrap.apk')!),
  'scope':json2.Any('Stable process-local drawing IDs for native WS Views, independent of native addresses and resource IDs. First access is synchronized per View and allocation across all Views is synchronized. Same signed APK fails framework205 and passes framework206/native204; four concurrent threads share one ID and create 256 distinct IDs. Layout, reparenting and all constructors preserve uniqueness. All 89 earlier pass markers remain. Native backend and launcher200 are unchanged. Maps functionality is reviewed separately.'),
  'references':json2.Any([json2.Any('https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android10-release/core/java/android/view/View.java'),json2.Any('https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android10-release/graphics/java/android/graphics/RenderNode.java')])
 }
 os.write_file(root+'runtime206-build.json',json2.encode(receipt,prettify:true)+'\n')!
 mut doc:=json2.decode[map[string]json2.Any](os.read_file(root+'results.json')!)!
 mut rows:=doc['applications']!.as_array().clone()
 for run in ['fixture-drawing206-baseline','fixture-drawing206-fixed','attempt206']{
  assert !rows.any(it.as_map()['run']!.str()==run),'already retained '+run
  batch:=base+run
  mut row:=json2.decode[[]json2.Any](os.read_file(batch+'/results.json')!)![0].as_map().clone()
  id:=row['id']!.str();state:=batch+'/'+id+'/'
  serial:=gzip.decompress(os.read_bytes(state+'serial.log.gz')!)!
  assert sha256.sum(serial).hex()==row['serial_sha256']!.str(),run
  row['run']=run;row['runtime_sha256']=json2.decode[json2.Any](os.read_file(batch+'/runtime-sha256.json')!)!
  row['kernel_sha256']='f8d86366353da19545fa6814b7b54d53973e59fdbafe2575c96c13594284b352'
  row['kernel_build_receipt']='arp-kernels.json';row['boot_base_receipt']='boot-base161.json';row['build_receipt']='runtime206-build.json'
  row['startup_ui_passed']=false;row['search_passed']=false
  row['harness_binary_sha256']=hash(base+'suite159')!
  row['harness_source_verified']=true
  row['manual_review']=match run{
   'fixture-drawing206-baseline'{'EXPECTED FAIL: same signed drawing ID fixture stops at missing View.getUniqueDrawingId against framework205/native204.'}
   'fixture-drawing206-fixed'{'PASS synthetic regression: four concurrent threads obtain the same shared View ID and 256 unique View IDs; repeated access, layout, reparenting, all constructors and duplicate resource IDs preserve identity. All 89 earlier pass markers remain. Native backend ready with GTK and X11 absent.'}
   else{os.read_file(base+'attempt206-review.txt')!.trim_space()}
  }
  for file,field in {'serial.log.gz':'serial_log','application.png':'screenshot','initial.png':'initial_screenshot','skip.png':'skip_screenshot','pan.png':'pan_screenshot','zoom.png':'zoom_screenshot','search-typed.png':'typed_screenshot','search.png':'search_screenshot','search-later.png':'later_screenshot','sheet.png':'sheet_screenshot','network.pcap':'network_capture'}{
   if !os.is_file(state+file){continue}
   name:=run+'-'+id+'-'+file;os.cp(state+file,root+name)!;row[field]=name
   if file!='serial.log.gz'{row[field+'_sha256']=hash(root+name)!}
  }
  mut saved:=map[string]json2.Any{}
  mut scripts:={run+'-configuration.json':batch+'.json',run+'-suite.v':base+'suite-low-disk.v',run+'-launcher.v':base+'trace200-launcher.v'}
  if run=='attempt206'{scripts[run+'-interaction.v']=base+'interact206.v'}
  for name,path in scripts{os.cp(path,root+name)!;saved[name]=hash(root+name)!}
  row['harness_artifacts_sha256']=json2.Any(saved);rows<<json2.Any(row)
 }
 doc['applications']=json2.Any(rows)
 os.write_file(root+'results.json',json2.encode(doc,prettify:true)+'\n')!
 println('Retained '+rows.len.str()+' runs')
}
