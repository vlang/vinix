// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Native WS has no Android Wi-Fi scanning service. Ethernet connectivity must
// not be advertised as a Wi-Fi radio or a successfully initiated scan.
fn framework_wifi(smali string) ! {
 path := smali + '/android/net/wifi/WifiManager.smali'
 mut text := os.read_file(path)!
 for signature in ['isScanAlwaysAvailable()Z', 'startScan()Z'] {
  text = framework_replace_method(text, signature, '.method public ' + signature + '\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method')!
 }
 text = framework_replace_method(text, 'getScanResults()Ljava/util/List;',
  '.method public getScanResults()Ljava/util/List;\n.locals 1\nnew-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\nreturn-object v0\n.end method')!
 os.write_file(path, text)!
 // API types still resolve when the device lacks the corresponding service:
 // ART resolves check-cast even when the value being cast is null. Keep both
 // RTT service lookups absent and never advertise a ranging capability.
 os.mkdir_all(smali + '/android/net/wifi/rtt')!
 os.write_file(smali + '/android/net/wifi/rtt/WifiRttManager.smali',
  '.class public final Landroid/net/wifi/rtt/WifiRttManager;\n.super Ljava/lang/Object;\n' +
  '.field public static final ACTION_WIFI_RTT_STATE_CHANGED:Ljava/lang/String; = "android.net.wifi.rtt.action.WIFI_RTT_STATE_CHANGED"\n' +
  '.method private constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
  '.method public isAvailable()Z\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method\n')!
 context := smali + '/android/content/Context.smali'
 mut base := os.read_file(context)!
 if !base.contains(' WIFI_RTT_RANGING_SERVICE:') {
  base += '\n.field public static final WIFI_RTT_RANGING_SERVICE:Ljava/lang/String; = "wifirtt"\n'
 }
 os.write_file(context, base)!
 // Upstream's class lookup constructs unknown manager types reflectively.
 // An absent RTT service must return null before reaching that fallback.
 implementation := smali + '/android/app/ContextImpl.smali'
 mut impl := os.read_file(implementation)!
 old := '.method public getSystemService(Ljava/lang/Class;)'
 if impl.count(old) != 1 { return error('unexpected RTT class service lookup') }
 impl = impl.replace(old, '.method private vinixRttFallbackClass(Ljava/lang/Class;)')
 impl += '\n.method public getSystemService(Ljava/lang/Class;)Ljava/lang/Object;\n.locals 1\n' +
  'const-class v0, Landroid/net/wifi/rtt/WifiRttManager;\nif-ne p1, v0, :other\n' +
  'const/4 v0, 0\nreturn-object v0\n:other\n' +
  'invoke-direct {p0, p1}, Landroid/app/ContextImpl;->vinixRttFallbackClass(Ljava/lang/Class;)Ljava/lang/Object;\n' +
  'move-result-object v0\nreturn-object v0\n.end method\n'
 os.write_file(implementation, impl)!
}
