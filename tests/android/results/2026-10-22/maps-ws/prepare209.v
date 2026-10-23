import os
fn main(){
 b:='build/android-maps/'
 path:=b+'native/atlframework/ws_views.v'
 mut s:=os.read_file(path)!
 assert !s.contains('WS-DIAG209')
 s=s.replace('fn ws_render(e voidptr) {','__global ws_diag209_at i64\nfn ws_render(e voidptr) {')
 s=s.replace('ws_trace_tree(e, decor)','ws_trace_tree(e, decor)\n\t\tdiagnostic := ws_millis() - ws_diag209_at > 30000\n\t\tif diagnostic { ws_diag209_at = ws_millis(); C.printf(c\'WS-DIAG209 draw begin sequence=%u\\n\',surface.sequence) }')
 s=s.replace('surface.sequence++','surface.sequence++\n\t\tif diagnostic { C.printf(c\'WS-DIAG209 draw end sequence=%u\\n\',surface.sequence) }')
 s=s.replace('if target == nil { return }','if target == nil { return }\n\t\tif event.kind == 2 { ws_diag209_object(e, target, c\'pointer target\'); listener := get_object(e,target,c\'android/view/View\',c\'on_click_listener\',c\'Landroid/view/View$OnClickListener;\'); ws_diag209_object(e,listener,c\'click listener\') }')
 s=s.replace("return boolean(e, target, c'android/view/View', c'dispatchTouchEvent', c'(Landroid/view/MotionEvent;)Z', args)","accepted := boolean(e, target, c'android/view/View', c'dispatchTouchEvent', c'(Landroid/view/MotionEvent;)Z', args)\n\t\tif action != 2 { C.printf(c'WS-DIAG209 motion action=%d x=%d y=%d accepted=%d\\n', action,x,y,i32(accepted)) }\n\t\treturn accepted")
 s += '\nfn ws_diag209_object(e voidptr, object voidptr, label &char) { unsafe {\nif object == nil || pending(e) { return }\ncls:=WsObjectClass(slot(e,31))(e,object)\nname:=obj(e,cls,c\'java/lang/Class\',c\'getName\',c\'()Ljava/lang/String;\',nil)\nchars:=ws_utf(e,name)\nC.printf(c\'WS-DIAG209 %s class=%s\\n\',label,chars)\nws_release(e,name,chars)\n} }\n'
 os.write_file(path,s)!
 os.write_file(b+'build-native209.v',os.read_file(b+'build-native204.v')!.replace('native204','native209').replace('NATIVE204','NATIVE209'))!
 os.write_file(b+'attempt209.json',os.read_file(b+'attempt208.json')!.replace('attempt208','attempt209').replace('360','180'))!
 os.write_file(b+'run209.v',os.read_file(b+'run208.v')!.replace('libnative204','libnative209').replace('attempt208','attempt209'))!
 os.write_file(b+'interact209.v',os.read_file(b+'interact208.v')!.replace('attempt208','attempt209'))!
 os.write_file(b+'stage-aux209.v',os.read_file(b+'stage-aux208.v')!.replace('attempt208','attempt209'))!
}
