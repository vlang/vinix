import os
import json2
fn main(){
 b:='build/android-maps/'
 os.write_file(b+'build-framework205.v',os.read_file(b+'build-framework204.v')!.replace('204','205'))!
 for mode in ['baseline','fixed']{
  mut cfg:=json2.decode[map[string]json2.Any](os.read_file(b+'fixture-font204-fixed.json')!)!
  mut app:=cfg['applications']!.as_array()[0].as_map()
  app['apk']=b+'locales205-apk/bootstrap.apk'
  cfg['applications']=[json2.Any(app)]
  cfg['output']=b+'fixture-locales205-'+mode
  os.write_file(b+'fixture-locales205-'+mode+'.json',json2.encode(cfg,prettify:true)+'\n')!
 }
 os.write_file(b+'run-locales205.v',os.read_file(b+'run-font204.v')!.replace("{'201'} else {'204'}", "{'204'} else {'205'}").replace('fixture-font204-','fixture-locales205-').replace("base+'libnative'+if baseline {'200.so'} else {'204.so'}", "base+'libnative204.so'"))!
 os.write_file(b+'attempt205.json',os.read_file(b+'attempt204.json')!.replace('attempt204','attempt205'))!
 os.write_file(b+'run205.v',os.read_file(b+'run204.v')!.replace('framework204','framework205').replace('attempt204','attempt205'))!
 os.write_file(b+'interact205.v',os.read_file(b+'interact204.v')!.replace('attempt204','attempt205'))!
 os.write_file(b+'stage-aux205.v',os.read_file(b+'stage-aux204.v')!.replace('attempt204','attempt205'))!
}
