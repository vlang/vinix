import os
import json2

fn main() {
 base := 'build/android-maps/'
 for n in ['209','210','211'] {
  reviewed := match n {
   '209' { 'skip.png and search-later.png' }
   '210' { 'initial.png and search-typed.png' }
   else { 'skip-later.png' }
  }
  os.write_file(base+'attempt'+n+'-review.txt', 'FAIL functional review: manually inspected '+reviewed+'; native Vinix WS still shows the real Maps Make it your map onboarding. No map, search, directions or location pass. Diagnostic run only; no app code modified. Framework click trace and listener-map trace do not establish that the inner callback completes. Other captured frames retained without an individual visual review claim.\n')!
 }
 r := os.exec([base+'retain211'])
 assert r.exit_code==0,r.output
 print(r.output)
 mut graph := os.read_file(base+'graph189.v')!
 start := graph.index('  mut root := ws.activity') or {panic('root')}
 end := graph.index('  if root == nil || pending(e)') or {panic('end root')}
 graph=graph[..start]+"  window := obj(e,ws.activity,c'android/app/Activity',c'getWindow',c'()Landroid/view/Window;',nil)\n  decor := obj(e,window,c'android/view/Window',c'getDecorView',c'()Landroid/view/View;',nil)\n  find := [Value{i:26}]!\n  view := obj(e,decor,c'android/view/View',c'findViewById',c'(I)Landroid/view/View;',&find[0])\n  root := get_object(e,view,c'android/view/View',c'on_click_listener',c'Landroid/view/View\u0024OnClickListener;')\n"+graph[end..]
 graph=graph.replace('[4096]','[512]').replace('used < 4096','used < 512').replace('depths[at] < 9','depths[at] < 6').replace('ws_object_samples >= 6','ws_object_samples >= 3')
 graph=graph.replace('   matched := text != nil && !pending(e) && ws_object_selected(text, selected)\n','')
 needle := " || text[0]==`[`\n"
 assert graph.contains(needle)
 graph=graph.replace(needle,needle+'   matched := !excluded\n')
 os.write_file(base+'graph212.v',graph)!
 os.write_file(base+'build-native212.v',os.read_file(base+'build-native209.v')!.replace('209','212').replace('graph189.v','graph212.v'))!
 os.write_file(base+'run212.v',os.read_file(base+'run211.v')!.replace('211','212').replace('libnative209','libnative212'))!
 os.write_file(base+'interact212.v',os.read_file(base+'interact211.v')!.replace('211','212'))!
 os.write_file(base+'stage-aux212.v',os.read_file(base+'stage-aux211.v')!.replace('211','212'))!
 mut cfg:=json2.decode[map[string]json2.Any](os.read_file(base+'attempt211.json')!)!
 cfg['output']=base+'attempt212'
 os.write_file(base+'attempt212.json',json2.encode(cfg,prettify:true)+'\n')!
 // Reuse the exact diagnostic framework211; only the native object probe changes.
 os.mkdir_all(base+'framework212')!
 os.cp(base+'framework211/api-impl.jar',base+'framework212/api-impl.jar')!
}
