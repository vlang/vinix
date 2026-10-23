import os
import json2
fn main() {
 mut cfg:=json2.decode[map[string]json2.Any](os.read_file('build/android-maps/attempt193.json')!)!
 cfg['output']='build/android-maps/attempt195'
 os.write_file('build/android-maps/attempt195.json',json2.encode(cfg,prettify:true))!
 os.write_file('build/android-maps/interact195.v',os.read_file('build/android-maps/interact193.v')!.replace('attempt193','attempt195'))!
}
