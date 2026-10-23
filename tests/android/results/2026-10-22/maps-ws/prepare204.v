import os
import json2
fn main() {
 b := 'build/android-maps/'
 os.write_file(b+'build-native204.v',os.read_file(b+'build-native200.v')!.replace("'ws_attachment.v',", "'fonts.v','ws_attachment.v',").replace('native200','native204').replace('NATIVE200','NATIVE204'))!
 os.write_file(b+'build-framework204.v',os.read_file(b+'build-framework201.v')!.replace('framework201','framework204').replace('FRAMEWORK201','FRAMEWORK204'))!
 for mode in ['baseline','fixed'] {
  mut cfg:=json2.decode[map[string]json2.Any](os.read_file(b+'fixture-order203-fixed.json')!)!
  mut app:=cfg['applications']!.as_array()[0].as_map()
  app['apk']=b+'font204-apk/bootstrap.apk'
  cfg['applications']=[json2.Any(app)]
  cfg['output']=b+'fixture-font204-'+mode
  os.write_file(b+'fixture-font204-'+mode+'.json',json2.encode(cfg,prettify:true)+'\n')!
 }
 os.write_file(b+'run-font204.v',os.read_file(b+'run-order203.v')!.replace("{'198'} else {'201'}","{'201'} else {'204'}").replace('fixture-order203-','fixture-font204-').replace("base+'libnative200.so'", "base+'libnative'+if baseline {'200.so'} else {'204.so'}"))!
 mut cfg:=json2.decode[map[string]json2.Any](os.read_file(b+'attempt203.json')!)!
 mut app:=cfg['applications']!.as_array()[0].as_map()
 app['startup_seconds']=360
 cfg['applications']=[json2.Any(app)]
 cfg['output']=b+'attempt204'
 os.write_file(b+'attempt204.json',json2.encode(cfg,prettify:true)+'\n')!
 os.write_file(b+'run204.v',os.read_file(b+'run203.v')!.replace('libnative200','libnative204').replace('framework201','framework204').replace('attempt203','attempt204'))!
 os.write_file(b+'interact204.v',os.read_file(b+'interact203.v')!.replace('attempt203','attempt204'))!
 os.write_file(b+'stage-aux204.v',os.read_file(b+'stage-aux203.v')!.replace('attempt203','attempt204'))!
}
