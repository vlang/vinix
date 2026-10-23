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
  'build-framework207.v':'framework207-build.v','framework207/framework-manifest.json':'framework207-manifest.json',
  'prepare207.v':'prepare207.v','run-render207.v':'run-render207.v','advance207.v':'advance207.v','advance207-test.v':'advance207-test.v','run-render207-fixed2.v':'run-render207-fixed2.v','run-render207-final.v':'run-render207-final.v','render207-initial-fixture-source.tar.gz':'render207-initial-fixture-source.tar.gz','render207-intermediate-fixture-source.tar.gz':'render207-intermediate-fixture-source.tar.gz','framework207-initial-manifest.json':'framework207-initial-manifest.json','framework207-initial-render_nodes.v':'framework207-initial-render_nodes.v','render207-final-apk-build.log':'render207-final-apk-build.log','run207.v':'run207.v','stage-aux207.v':'stage-aux207.v',
  'validate207.v':'validate207.v','validate207.log':'validate207.log','retain207.v':'retain207.v',
  'advance207-matrix.v':'advance207-matrix.v','run-render207-fixed4.v':'run-render207-fixed4.v',
  'framework207-null-matrix-manifest.json':'framework207-null-matrix-manifest.json',
  'build-framework207-initial.log':'framework207-initial-build.log',
  'fixture-render207-fixed4-host.log':'fixture-render207-fixed4-harness.log',
  'fixture-render207-fixed5-host.log':'fixture-render207-fixed5-harness.log',
  'fixture-render207-fixed6-host.log':'fixture-render207-fixed6-harness.log','fixture-render207-baseline3-host.log':'fixture-render207-baseline3-harness.log',
  'advance207-nested.v':'advance207-nested.v','run-render207-final2.v':'run-render207-final2.v',
  'render207-final2-apk-build.log':'render207-final2-apk-build.log',
  'advance207-outline.v':'advance207-outline.v','run-render207-fixed5.v':'run-render207-fixed5.v','framework207-clip-stub-manifest.json':'framework207-clip-stub-manifest.json',
  'attempt207/launcher-runtime-sha256.json':'attempt207-launcher-runtime-sha256.json',
  'attempt207-harness.log':'attempt207-harness.log','interact207.log':'attempt207-interaction.log',
  'fixture-render207-baseline-host.log':'fixture-render207-baseline-harness.log','fixture-render207-fixed-host.log':'fixture-render207-fixed-harness.log','fixture-render207-fixed2-host.log':'fixture-render207-fixed2-harness.log','fixture-render207-baseline2-host.log':'fixture-render207-baseline2-harness.log','fixture-render207-fixed3-host.log':'fixture-render207-fixed3-harness.log'
 }{os.cp(base+src,root+name)!;artifacts[name]=hash(root+name)!}
 for kind in ['framework']{
  src:=base+'build-'+kind+'207.log'
  name:=kind+'207-build.log.gz'
  os.write_file_array(root+name,gzip.compress(os.read_bytes(src)!)!)!
  artifacts[name]=hash(root+name)!
 }
 r:=os.exec(['tar','-czf',os.abs_path(root+'render207-fixture-source.tar.gz'),'-C',base+'render207-final2-apk','smali','res'])
 assert r.exit_code==0,r.output
 artifacts['render207-fixture-source.tar.gz']=hash(root+'render207-fixture-source.tar.gz')!
 mut sources:=map[string]json2.Any{}
 for file in ['tests/native-android-tools/androidtools/framework_render_nodes.v','tests/native-android-tools/androidtools/framework_drawing_ids.v','tests/native-android-tools/androidtools/framework_pictures.v','tests/native-android-tools/androidtools/framework_classes.v','tests/native-android-ws/startupfixture/render_nodes.v','tests/native-android-ws/startupfixture/startup.v']{
  s:=os.exec(['git','show','b8165449a:'+file]);assert s.exit_code==0
  sources[file]=sha256.sum(s.output.bytes()).hex()
 }
 receipt:={
  'artifacts_sha256':json2.Any(artifacts),'committed_sources_sha256':json2.Any({'b8165449a':json2.Any(sources)}),
  'framework207_sha256':json2.Any(hash(base+'framework207/api-impl.jar')!),
  'native204_sha256':json2.Any(hash(base+'libnative204.so')!),
  'native_build_receipt':json2.Any('runtime204-build.json'),
  'initial_framework207_sha256':json2.Any(hash(base+'framework207-initial.jar')!),
  'null_matrix_framework207_sha256':json2.Any(hash(base+'framework207-null-matrix.jar')!),
  'clip_stub_framework207_sha256':json2.Any(hash(base+'framework207-clip-stub.jar')!),
  'first_baseline_fixture_apk_sha256':json2.Any('9c7acb735123ee589f7a4971279406a96a45b31f89a8ceee35e3c677f095aa91'),
  'first_fixed_fixture_apk_sha256':json2.Any(hash(base+'render207-initial.apk')!),
  'intermediate_fixture_apk_sha256':json2.Any(hash(base+'render207-final-apk/bootstrap.apk')!),
  'fixture_apk_sha256':json2.Any(hash(base+'render207-final2-apk/bootstrap.apk')!),
  'scope':json2.Any('Native WS RenderNode command display lists, RecordingCanvas, live child references, affine transforms, bounds/rect/rectangular-outline clipping and real group-opacity compositing. Same final signed APK fails framework206 and passes framework207/native204: 13312 pixels, recording state, drawing identity, mutable Paint/clip snapshots, live child changes/list replacement/discard and canvas-state recovery after direct/offscreen cyclic-list failures. All 90 previous pass markers retained. Initial verifier failure, missing Matrix.native_equals test dependency, null Canvas matrix crash and outline clip stub pixel failure and parent-clip test expectation failure retained separately. Native204 and launcher200 unchanged. Rounded/path outline clipping and perspective rotation explicitly unsupported; Z/elevation/shadow metadata retained without rendered node shadows. No RenderEffect implementation; no claim of complete Android HWUI or Maps functionality.'),
  'references':json2.Any([json2.Any('https://developer.android.com/reference/android/graphics/RenderNode'),json2.Any('https://android.googlesource.com/platform/frameworks/base/+/master/graphics/java/android/graphics/RenderNode.java')])
 }
 os.write_file(root+'runtime207-build.json',json2.encode(receipt,prettify:true)+'\n')!
 mut doc:=json2.decode[map[string]json2.Any](os.read_file(root+'results.json')!)!
 mut rows:=doc['applications']!.as_array().clone()
 for run in ['fixture-render207-baseline','fixture-render207-fixed','fixture-render207-fixed2','fixture-render207-baseline2','fixture-render207-fixed3','fixture-render207-fixed4','fixture-render207-fixed5','fixture-render207-baseline3','fixture-render207-fixed6','attempt207']{
  assert !rows.any(it.as_map()['run']!.str()==run),'already retained '+run
  batch:=base+run
  mut row:=json2.decode[[]json2.Any](os.read_file(batch+'/results.json')!)![0].as_map().clone()
  id:=row['id']!.str();state:=batch+'/'+id+'/'
  serial:=gzip.decompress(os.read_bytes(state+'serial.log.gz')!)!
  assert sha256.sum(serial).hex()==row['serial_sha256']!.str(),run
  row['run']=run;row['runtime_sha256']=json2.decode[json2.Any](os.read_file(batch+'/runtime-sha256.json')!)!
  row['kernel_sha256']='f8d86366353da19545fa6814b7b54d53973e59fdbafe2575c96c13594284b352'
  row['kernel_build_receipt']='arp-kernels.json';row['boot_base_receipt']='boot-base161.json';row['build_receipt']='runtime207-build.json'
  row['startup_ui_passed']=false;row['search_passed']=false
  row['harness_binary_sha256']=hash(base+'suite159')!
  row['harness_source_verified']=true
  row['manual_review']=match run{
   'fixture-render207-baseline', 'fixture-render207-baseline2', 'fixture-render207-baseline3' {'EXPECTED FAIL: signed RenderNode fixture stops at missing android.graphics.RenderNode against framework206/native204. The baseline3 run uses the same final signed APK as fixed6; baseline2 uses the intermediate matrix-value test APK.'}
   'fixture-render207-fixed' {'FAIL implementation: initial framework207 has an invalid uninitialized Canvas register in an exception-handler merge; ART rejects RenderNode.vinixDraw before pixel tests. Initial source snapshot, framework hash and manifest retained.'}
   'fixture-render207-fixed2' {'INCOMPLETE regression: corrected framework passes verifier and reaches cycle-error recovery; test stops at an unrelated missing Matrix.native_equals API. Final test compares public matrix values directly. No pixel or full regression pass claimed for this run.'}
   'fixture-render207-fixed3' {'FAIL implementation: offscreen recovery reaches compositing, then Canvas.setMatrix(null) raises NullPointerException. Final RenderNode uses an explicit identity Matrix. No full regression pass claimed.'}
   'fixture-render207-fixed4' {'FAIL implementation: rectangular outline pixels reveal that existing Canvas.clipPath is a stub. Final RenderNode clips rectangular outlines directly and explicitly rejects rounded/path outlines. No full regression pass claimed.'}
   'fixture-render207-fixed5' {'FAIL test expectation: parent bounds correctly clip the replaced child at x=19, while the intermediate fixture expected content to x=23. Corrected expected pixels in the final signed fixture. No full regression pass claimed.'}
   'fixture-render207-fixed6' {'PASS synthetic regression: same final signed APK as baseline3; 13312 pixel comparisons and recording/layer state checks pass, including direct and offscreen cycle recovery. All 90 previous pass markers retained; native WS ready with GTK/X11 absent.'}
   else {os.read_file(base+'attempt207-review.txt')!.trim_space()}
  }
  for file,field in {'serial.log.gz':'serial_log','application.png':'screenshot','initial.png':'initial_screenshot','skip.png':'skip_screenshot','pan.png':'pan_screenshot','zoom.png':'zoom_screenshot','search-typed.png':'typed_screenshot','search.png':'search_screenshot','search-later.png':'later_screenshot','sheet.png':'sheet_screenshot','network.pcap':'network_capture'}{
   if !os.is_file(state+file){continue}
   name:=run+'-'+id+'-'+file;os.cp(state+file,root+name)!;row[field]=name
   if file!='serial.log.gz'{row[field+'_sha256']=hash(root+name)!}
  }
  mut saved:=map[string]json2.Any{}
  mut scripts:={run+'-configuration.json':batch+'.json',run+'-suite.v':base+'suite-low-disk.v',run+'-launcher.v':base+'trace200-launcher.v'}
  if run=='attempt207'{scripts[run+'-interaction.v']=base+'interact207.v'}
  for name,path in scripts{os.cp(path,root+name)!;saved[name]=hash(root+name)!}
  row['harness_artifacts_sha256']=json2.Any(saved);rows<<json2.Any(row)
 }
 doc['applications']=json2.Any(rows)
 os.write_file(root+'results.json',json2.encode(doc,prettify:true)+'\n')!
 println('Retained '+rows.len.str()+' runs')
}
