import os
import json2

fn main() {
 base := 'build/android-maps/'
 mut views := os.read_file('build-support/android/nativews/ws_views.v')!
 views = views.replace('\t\t\tws_dump_surface_fields(e, view)\n', '')
 needle := '\t\tws_release(e, name, chars)\n\t\tif instance_of(e, view, c\'android/view/ViewGroup\') {'
 assert views.count(needle) == 1
 views = views.replace(needle, '\t\tif C.strcmp(chars, c\'nvv\') == 0 {\n\t\t\tC.printf(c\'ANDROID-WS-ANIMATION-STATE millis=%ld\\n\', ws_millis())\n\t\t\tws_surface_fields_count = 0\n\t\t\tws_dump_surface_fields(e, view)\n\t\t}\n' + needle)
 os.write_file(base+'diagnostic179-ws_views.v',views)!
 mut builder := os.read_file(base+'build-native171.v')!.replace('171','179')
 builder=builder.replace("'build-support/android/nativews/ws_views.v'", "'build/android-maps/diagnostic179-ws_views.v'")
 os.write_file(base+'build-native179.v',builder)!
 mut launcher := os.read_file(base+'fields159-launcher.v')!
 start := launcher.index("'b.b.b.0.e.t.j,") or { panic('field paths') }
 end := launcher.index_after("', true)",start) or { panic('field paths end') }
 launcher = launcher[..start] + "'g,g.d,g.a,g.b,g.c,g.a.0.mStarted,g.a.0.mRunning,g.a.0.mOverallFraction,g.a.0.mStartTime,g.a.0.mLastFrameTime,g.b.0.animator.mStarted,g.b.0.animator.mRunning,g.b.0.animator.mOverallFraction,g.b.0.listener,g.b.0.start_pending,c" + launcher[end..]
 os.write_file(base+'fields179-launcher.v',launcher)!
 mut config := json2.decode[map[string]json2.Any](os.read_file(base+'attempt178.json')!)!
 config['output']=base+'attempt179'
 mut apps := config['applications']!.as_array()
 mut app := apps[0].as_map()
 app['startup_seconds']=300
 apps[0]=app
 config['applications']=apps
 os.write_file(base+'attempt179.json', json2.encode(config,prettify:true)+'\n')!
 mut interact := os.read_file(base+'interact178.v')!.replace('attempt178','attempt179')
 a:=interact.index(" input(path,['drag','430'") or { panic('drag') }
 b:=interact.index(" input(path,['click','300'") or { panic('click') }
 interact=interact[..a]+interact[b..]
 interact=interact.replace('time.sleep(30*time.second)','time.sleep(60*time.second)')
 os.write_file(base+'interact179.v',interact)!
}
