import os
import json2
fn main() {
 b := 'build/android-maps/'
 r := os.exec(['tar','-czf',os.abs_path(b+'native212-sources.tar.gz'),'-C',b+'native','atlframework'])
 assert r.exit_code == 0, r.output
 mut g := os.read_file(b+'graph189.v')!
 g = g.replace('  mut root := ws.activity', "  window := obj(e,ws.activity,c'android/app/Activity',c'getWindow',c'()Landroid/view/Window;',nil)\n  decor := obj(e,window,c'android/view/Window',c'getDecorView',c'()Landroid/view/View;',nil)\n  find := [Value{i:26}]!\n  view := obj(e,decor,c'android/view/View',c'findViewById',c'(I)Landroid/view/View;',&find[0])\n  mut root := get_object(e,view,c'android/view/View',c'on_click_listener',c'Landroid/view/View\u0024OnClickListener;')")
 g = g.replace("path := C.getenv(c'VINIX_ANDROID_TRACE_OBJECT_ROOT')", "path := c'a.@afql.a.b.d.b.c'")
 g = g.replace('[4096]','[1024]').replace('used < 4096','used < 1024').replace('depths[at] < 9','depths[at] < 6').replace('ws_object_samples >= 6','ws_object_samples >= 3')
 g = g.replace('   matched := text != nil && !pending(e) && ws_object_selected(text, selected)\n','')
 needle := " || text[0]==`[`\n"
 assert g.contains(needle)
 g = g.replace(needle,needle+'   matched := !excluded\n')
 os.write_file(b+'graph213.v',g)!
 mut build := os.read_file(b+'build-native212.v')!.replace('212','213')
 build = build.replace(" mut sources :=", " os.write_file(out+'/atlframework/ws_views.v',os.read_file(out+'/atlframework/ws_views.v')!.replace('visible=%d\\n','visible=%d alpha=%f\\n').replace(\"c'getVisibility', c'()I', nil))\",\"c'getVisibility', c'()I', nil), f64(ws_view_translation(e,view,c'alpha'))))\"))!\n mut sources :=")
 // ws_debug_tree is the only matching printf; avoid changing any dispatch call.
 os.write_file(b+'build-native213.v',build)!
 for kind in ['run','interact','stage-aux'] {
  os.write_file(b+kind+'213.v',os.read_file(b+kind+'212.v')!.replace('212','213'))!
 }
 mut cfg := json2.decode[map[string]json2.Any](os.read_file(b+'attempt212.json')!)!
 cfg['output']=b+'attempt213'
 os.write_file(b+'attempt213.json',json2.encode(cfg,prettify:true)+'\n')!
 os.mkdir_all(b+'framework213')!
 os.cp(b+'framework211/api-impl.jar',b+'framework213/api-impl.jar')!
}
