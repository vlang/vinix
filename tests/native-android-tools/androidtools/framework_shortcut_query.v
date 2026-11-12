// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_shortcut_query(smali string) ! {
	path := smali + '/android/content/pm/ShortcutManager.smali'
	// Keep the legacy query consistent with getShortcuts(FLAG_MATCH_DYNAMIC).
	// The current WS shortcut backend has no published entries. This query
	// does not claim shortcut publication or desktop integration.
	mut text := framework_replace_method(os.read_file(path)!, 'getDynamicShortcuts()Ljava/util/List;', r'
.method public getDynamicShortcuts()Ljava/util/List;
.locals 1
const/4 v0, 2
invoke-virtual {p0, v0}, Landroid/content/pm/ShortcutManager;->getShortcuts(I)Ljava/util/List;
move-result-object v0
return-object v0
.end method')!
	// Removing unknown IDs is harmless in the current empty backend. Validate
	// every ID as ShortcutService does; never report publishing an entry.
	text = framework_replace_method(text, 'removeDynamicShortcuts(Ljava/util/List;)V', r'
.method public removeDynamicShortcuts(Ljava/util/List;)V
.locals 2
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-interface {p1}, Ljava/util/List;->iterator()Ljava/util/Iterator;
move-result-object v0
:next
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :done
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Ljava/lang/String;
invoke-static {v1}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z
move-result v1
if-eqz v1, :next
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "shortcut ID must not be empty"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:done
return-void
.end method')!
	os.write_file(path, text)!
}
