import os
import json2

fn main() {
 base := 'build/android-maps/'
 mut diag := os.read_file(base+'visibility197.v')!
 diag = diag.replace('visibility197_count>=24','visibility197_count>=128')
 diag = diag.replace("C.printf(c'ANDROID-WS-VISIBILITY state=%d sample=%d\\n',visibility,visibility197_count)","C.printf(c'ANDROID-WS-VISIBILITY state=%d sample=%d widget=%llx id=%x\\n',visibility,visibility197_count,get_long(e,view,c'android/view/View',c'widget'),integer(e,view,c'android/view/View',c'getId',c'()I',nil))")
 diag = diag.replace('%llx','%lx')
 diag += '
fn ws_trace_remove200(e voidptr, parent voidptr, widget i64) {
 unsafe {
  if pending(e) || integer(e,parent,c\'android/view/View\',c\'getId\',c\'()I\',nil)!=i32(0x7f0b0460) {return}
  C.printf(c\'ANDROID-WS-REMOVE widget=%lx\\n\',widget)
  worker:=static_obj(e,c\'java/lang/Thread\',c\'currentThread\',c\'()Ljava/lang/Thread;\',nil)
  stack:=obj(e,worker,c\'java/lang/Thread\',c\'getStackTrace\',c\'()[Ljava/lang/StackTraceElement;\',nil)
  length:=if pending(e) {i32(0)} else {ws_array_len(e,stack)}
  for n:=i32(0); n<length && n<32 && !pending(e); n++ {
   push_frame(e)
   frame:=WsArrayGet(slot(e,173))(e,stack,n)
   label:=obj(e,frame,c\'java/lang/StackTraceElement\',c\'toString\',c\'()Ljava/lang/String;\',nil)
   text:=ws_utf(e,label)
   if text!=nil {C.printf(c\'ANDROID-WS-REMOVE-CALLER %.1024s\\n\',text);ws_release(e,label,text)}
   pop_frame(e)
  }
  if pending(e) {ExceptionClear(slot(e,17))(e)}
 }
}
'
 os.write_file(base+'visibility200.v',diag)!
 mut source:=os.read_file(base+'build-native198.v')!.replace('native198','native200').replace('NATIVE198','NATIVE200')
 source=source.replace('mut sources := map[string]string{}',"os.cp('build/android-maps/visibility200.v',out+'/atlframework/visibility197.v')!\n os.write_file(out+'/atlframework/ws_generated.v',os.read_file(out+'/atlframework/ws_generated.v')!.replace('ws_trace_view_additions(e, this, p1); ws_trace_view_additions(e, this, p1);','ws_trace_view_additions(e, this, p1);').replace(\"fn ws_binding_180(e voidptr, this voidptr, p0 i64, p1 i64)  {\\n    unsafe {\\n ws_mark()\",\"fn ws_binding_180(e voidptr, this voidptr, p0 i64, p1 i64)  {\\n    unsafe {\\n ws_trace_remove200(e,this,p1); ws_mark()\"))!\n mut sources := map[string]string{}")
 os.write_file(base+'build-native200.v',source)!
 os.write_file(base+'trace200-launcher.v',os.read_file(base+'trace199-launcher.v')!.replace("'VINIX_ANDROID_TRACE_VISIBILITY', 'com.google.android.apps.gmm.base.views.map.MapViewContainer'","'VINIX_ANDROID_TRACE_VISIBILITY', 'android.widget.LinearLayout'"))!
 os.write_file(base+'interact200.v',os.read_file(base+'interact199.v')!.replace('attempt199','attempt200'))!
 mut cfg:=json2.decode[map[string]json2.Any](os.read_file(base+'attempt199.json')!)!
 cfg['output']=base+'attempt200'
 os.write_file(base+'attempt200.json',json2.encode(cfg,prettify:true)+'\n')!
}
