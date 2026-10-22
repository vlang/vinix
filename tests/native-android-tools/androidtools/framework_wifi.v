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
}
