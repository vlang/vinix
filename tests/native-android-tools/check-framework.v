// SPDX-License-Identifier: GPL-2.0-or-later
// Guard the DEX transformation that installs the V framework implementation.
module main

import androidtools
import os

fn main() {
 activity := '.class public Landroid/app/Activity;\n.super Ljava/lang/Object;\n' +
  '.method private static createMainActivity(Ljava/lang/String;JLjava/lang/String;)Landroid/app/Activity;\n.locals 1\nconst/4 v0, 0\nreturn-object v0\n.end method\n' +
  ['Start', 'Stop', 'Destroy'].map('.method protected on' + it + '()V\n.locals 0\n# original ' + it + '\nreturn-void\n.end method\n').join('') +
  '.method public unrelated()V\n.locals 0\nreturn-void\n.end method\n'
 bar := '.class public Landroid/app/ActionBar;\n.super Ljava/lang/Object;\n'
 cursor_v := os.read_file('build-support/android/atlframework/cursors.v')!
 bar_v := os.read_file('build-support/android/atlframework/actionbar.v')!
 patched, _ := androidtools.framework_patch(activity, bar, cursor_v, bar_v)!
 assert patched.contains('.method public unrelated()V\n.locals 0\nreturn-void\n.end method')
 for name in ['Start', 'Stop', 'Destroy'] {
  assert patched.contains('vinixOriginalOn' + name + '()V\n.locals 0\n# original ' + name)
 }
 assert patched.contains('.method public static native createMainActivity(')
 mut rejected := false
 androidtools.framework_patch(patched, bar, cursor_v, bar_v) or { rejected = true }
 assert rejected
 rejected = false
 androidtools.framework_patch(activity.replace('protected onStop', 'public onStop'), bar, cursor_v, bar_v) or { rejected = true }
 assert rejected
 launcher := androidtools.framework_launcher(os.read_file('build-support/android/run-android')!)!
 assert launcher.contains('$runtime/usr/lib/art/libvinix-android-framework.so')
 assert launcher.contains('extra_preload=\${VINIX_ANDROID_TEST_PRELOAD:-}')
 rejected = false
 androidtools.framework_launcher(launcher) or { rejected = true }
 assert rejected
 classes := androidtools.framework_extra_classes(os.read_file('build-support/android/atlframework/widgets.v')!)
 assert classes['android/content/ContentProvider$PipeDataWriter']!.contains('writeDataToPipe(Landroid/os/ParcelFileDescriptor;Landroid/net/Uri;Ljava/lang/String;Landroid/os/Bundle;Ljava/lang/Object;)V')
 assert classes['android/widget/SearchView$OnQueryTextListener']!.contains('.method public abstract onQueryTextSubmit(Ljava/lang/String;)Z')
 assert classes['android/widget/SimpleCursorAdapter']!.contains('Landroid/widget/CursorAdapter;-><init>(Landroid/content/Context;Landroid/database/Cursor;I)V')
 println('Android framework: lifecycle preservation, static JNI factory, declaration guards, cursor constructors and launcher path: PASS')
}
