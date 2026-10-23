import os
import json2
fn main() {
 b := 'build/android-maps/'
 os.cp(b+'libnative219.so',b+'libnative220.so')!
 os.cp(b+'native219-sources.json',b+'native220-sources.json')!
 os.cp(b+'queue219.v',b+'queue220.v')!
 mut cfg := json2.decode[map[string]json2.Any](os.read_file(b+'attempt219.json')!)!
 cfg['output']=b+'attempt220'
 mut apps:=cfg['applications']!.as_array()
 mut app:=apps[0].as_map()
 app['startup_seconds']=150
 apps[0]=json2.Any(app)
 cfg['applications']=json2.Any(apps)
 os.write_file(b+'attempt220.json',json2.encode(cfg,prettify:true)+'\n')!
 os.write_file(b+'interact220.v',os.read_file(b+'interact219.v')!.replace('219','220'))!
 os.write_file(b+'run220.v',os.read_file(b+'run219.v')!.replace('libnative219','libnative220').replace('attempt219','attempt220').replace('interact219','interact220'))!
}
