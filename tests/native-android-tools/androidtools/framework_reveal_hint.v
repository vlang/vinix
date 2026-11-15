// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

// An opt-out bit gives every View constructor the Android default of true.
// This is an ancestor hint; changing it does not request focus or scrolling.
pub fn framework_reveal_hint_source(original string) !string {
 for declaration in ['.class public Landroid/view/View;', '.super Ljava/lang/Object;',
  '.method public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V'] {
  if original.count(declaration + '\n') != 1 { return error('canonical View reveal-hint input required') }
 }
 for member in ['vinixRevealOnFocusDisabled:', 'getRevealOnFocusHint(', 'setRevealOnFocusHint('] {
  if original.contains(member) { return error('View reveal hint already exists') }
 }
 return original + r'
.field private vinixRevealOnFocusDisabled:Z
.method public final setRevealOnFocusHint(Z)V
.locals 1
const/4 v0, 1
if-eqz p1, :store
const/4 v0, 0
:store
iput-boolean v0, p0, Landroid/view/View;->vinixRevealOnFocusDisabled:Z
return-void
.end method
.method public final getRevealOnFocusHint()Z
.locals 1
iget-boolean v0, p0, Landroid/view/View;->vinixRevealOnFocusDisabled:Z
xor-int/lit8 v0, v0, 1
return v0
.end method
'
}

pub fn framework_reveal_hint(smali string) ! {
 path := smali + '/android/view/View.smali'
 os.write_file(path, framework_reveal_hint_source(os.read_file(path)!)!)!
}
