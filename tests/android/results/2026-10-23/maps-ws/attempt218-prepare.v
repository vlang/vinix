import os
import json2
fn main() {
 b := 'build/android-maps/'
 native := b+'native218'
 if !os.is_dir(native) { os.cp_all(b+'native',native,false)! }
 os.cp(b+'libnative216.so',native+'/libvinix-android-native.so')!
 os.cp(b+'launcher200',native+'/popular-launcher')!
 mut cfg := json2.decode[map[string]json2.Any](os.read_file(b+'attempt217.json')!)!
 cfg['native_dir'] = native
 cfg['output'] = b+'attempt218'
 mut apps := cfg['applications']!.as_array()
 mut app := apps[0].as_map()
 app['startup_seconds'] = 240
 apps[0] = json2.Any(app)
 cfg['applications'] = json2.Any(apps)
 os.write_file(b+'attempt218.json',json2.encode(cfg,prettify:true)+'\n')!
 os.write_file(b+'interact218.v',os.read_file(b+'interact217.v')!.replace('217','218'))!
}
