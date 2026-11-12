// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_shortcut_query(smali string) ! {
	path := smali + '/android/content/pm/ShortcutManager.smali'
	// Keep the legacy query consistent with getShortcuts(FLAG_MATCH_DYNAMIC).
	// The current WS shortcut backend has no published entries. This query
	// does not claim shortcut publication or desktop integration.
	os.write_file(path, framework_replace_method(os.read_file(path)!, 'getDynamicShortcuts()Ljava/util/List;', r'
.method public getDynamicShortcuts()Ljava/util/List;
.locals 1
const/4 v0, 2
invoke-virtual {p0, v0}, Landroid/content/pm/ShortcutManager;->getShortcuts(I)Ljava/util/List;
move-result-object v0
return-object v0
.end method')!)!
}
