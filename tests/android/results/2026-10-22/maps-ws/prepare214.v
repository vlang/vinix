import os
import json2
fn main() {
 b := 'build/android-maps/'
 r := os.exec(['tar','-czf',os.abs_path(b+'native213-sources.tar.gz'),'-C',b+'native','atlframework'])
 assert r.exit_code == 0, r.output
 mut g := os.read_file(b+'graph213.v')!
 start := g.index("  window := obj(e,ws.activity") or { panic('root start') }
 end := g.index('  mut cursor := 0') or { panic('root end') }
 g = g[..start]+"  mut root := ws.activity\n  path := &char(c'bY.a')\n"+g[end..]
 g = g.replace("   if instance_of(e,value,c'java/util/Map') && depths[at] < 6 {\n    contents := obj(e,value,c'java/util/Map',c'values',c'()Ljava/util/Collection;',nil)","   if (instance_of(e,value,c'java/util/Map') || instance_of(e,value,c'java/util/Collection')) && depths[at] < 6 {\n    contents := if instance_of(e,value,c'java/util/Map') { obj(e,value,c'java/util/Map',c'values',c'()Ljava/util/Collection;',nil) } else { value }")
 os.write_file(b+'graph214.v',g)!
 os.write_file(b+'build-native214.v',os.read_file(b+'build-native213.v')!.replace('213','214'))!
 for kind in ['run','interact','stage-aux'] {
  os.write_file(b+kind+'214.v',os.read_file(b+kind+'213.v')!.replace('213','214'))!
 }
 mut cfg := json2.decode[map[string]json2.Any](os.read_file(b+'attempt213.json')!)!
 cfg['output']=b+'attempt214'
 os.write_file(b+'attempt214.json',json2.encode(cfg,prettify:true)+'\n')!
 os.mkdir_all(b+'framework214')!
 os.cp(b+'framework211/api-impl.jar',b+'framework214/api-impl.jar')!
}
