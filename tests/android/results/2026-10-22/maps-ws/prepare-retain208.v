import os
fn main(){
 b:='build/android-maps/'
 mut s:=os.read_file(b+'retain206.v')!.replace('206','208').replace('drawing208','layout208').replace('5087ee194','a68ef53f9')
 s=s.replace("'run-layout208-baseline.log'", "'fixture-layout208-baseline-host.log'").replace("'run-layout208-fixed.log'", "'fixture-layout208-fixed-host.log'")
 s=s.replace("base+'build-'+kind+'208.log'", "base+kind+'208-build.log'")
 s=s.replace('framework_drawing_ids.v','framework_layout_canvas.v').replace('startupfixture/drawing_ids.v','startupfixture/layout_canvas.v')
 a:=s.index("  'scope':json2.Any(") or {panic('scope')};z:=s.index("\n }\n os.write_file(root+'runtime208") or {panic('receipt')}
 s=s[..a]+"  'scope':json2.Any('Draw native WS text layouts through the supplied Canvas virtual drawText method. Picture and RenderNode record text and Paint snapshots; replay honors the destination bitmap, transform and clip. Same signed APK fails framework207 and passes framework208/native204: UTF16 supplementary character, multiline, wrap, empty text/lines, independent baselines and 12288 pixel comparisons. All 91 prior pass markers retained. Uses existing WS line metrics; shaping, styled runs, paragraph alignment and selection/highlight rendering remain outside this change. Native204 and launcher200 unchanged. Actual Maps reviewed separately.'),\n  'references':json2.Any([json2.Any('https://developer.android.com/reference/android/text/Layout'),json2.Any('https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/text/Layout.java')])"+s[z..]
 a2:=s.index("   'fixture-layout208-baseline'") or {panic('baseline')};z2:=s.index("   else{os.read_file") or {panic('review')}
 s=s[..a2]+"   'fixture-layout208-baseline'{'EXPECTED FAIL: same signed fixture stops at missing Layout.native_draw_custom_canvas on framework207/native204 after the RenderNode checks pass.'}\n   'fixture-layout208-fixed'{'PASS synthetic regression: virtual Canvas dispatch, UTF16 supplementary character, multiline, wrapping, empty text/lines and independent baselines; 12288 pixels for Picture/RenderNode recording, Paint snapshots and translated/clipped bitmap targets. All 91 earlier pass markers retained. Native WS ready, GTK/X11 absent.'}\n"+s[z2..]
 s=s.replace("'prepare208.v':'prepare208.v',", "'prepare208.v':'prepare208.v','prepare-retain208.v':'prepare-retain208.v','layout208-apk-build.log':'layout208-apk-build.log',")
 os.write_file(b+'retain208.v',s)!
 os.write_file(b+'audit-build208.v',os.read_file(b+'audit-build207.v')!.replace('207','208'))!
 os.write_file(b+'commit208-evidence.v',os.read_file(b+'commit207-evidence.v')!.replace('207','208').replace('paths.len>60 && paths.len<160','paths.len>30 && paths.len<75').replace('RenderNode regression','Canvas text regression'))!
}
