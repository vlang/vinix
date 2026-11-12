// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Backport API29 resource delegation to the selected ART boot library. Class
// lookup remains the original boot → local DEX → parent implementation.
// Contract: https://developer.android.com/reference/dalvik/system/DelegateLastClassLoader
pub fn boot_delegate_last(smali string) ! {
	path := smali + '/dalvik/system/DelegateLastClassLoader.smali'
	mut text := os.read_file(path)!
	owner := 'Ldalvik/system/DelegateLastClassLoader;'
	if !text.contains('.class public final ' + owner) || text.contains('delegateResourceLoading:Z') {
		return error('unmodified DelegateLastClassLoader required')
	}
	text += '\n.field private final delegateResourceLoading:Z\n'
	text = framework_replace_method(text, '<init>(Ljava/lang/String;Ljava/lang/ClassLoader;)V',
		'.method public constructor <init>(Ljava/lang/String;Ljava/lang/ClassLoader;)V\n.locals 2\nconst/4 v0, 0\nconst/4 v1, 1\ninvoke-direct {p0, p1, v0, p2, v1}, ' + owner + '-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;Z)V\nreturn-void\n.end method')!
	text = framework_replace_method(text, '<init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V',
		'.method public constructor <init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V\n.locals 1\nconst/4 v0, 1\ninvoke-direct {p0, p1, p2, p3, v0}, ' + owner + '-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;Z)V\nreturn-void\n.end method')!
	text += '.method public constructor <init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;Z)V\n.locals 0\ninvoke-direct {p0, p1, p2, p3}, Ldalvik/system/PathClassLoader;-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V\niput-boolean p4, p0, ' + owner + '->delegateResourceLoading:Z\nreturn-void\n.end method\n'
	text = framework_replace_method(text, 'getResource(Ljava/lang/String;)Ljava/net/URL;', r'
.method public getResource(Ljava/lang/String;)Ljava/net/URL;
.locals 1
const-class v0, Ljava/lang/Object;
invoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v0
invoke-virtual {v0, p1}, Ljava/lang/ClassLoader;->getResource(Ljava/lang/String;)Ljava/net/URL;
move-result-object v0
if-nez v0, :done
invoke-virtual {p0, p1}, Ldalvik/system/DelegateLastClassLoader;->findResource(Ljava/lang/String;)Ljava/net/URL;
move-result-object v0
if-nez v0, :done
iget-boolean v0, p0, Ldalvik/system/DelegateLastClassLoader;->delegateResourceLoading:Z
if-eqz v0, :absent
invoke-virtual {p0}, Ldalvik/system/DelegateLastClassLoader;->getParent()Ljava/lang/ClassLoader;
move-result-object v0
if-eqz v0, :absent
invoke-virtual {v0, p1}, Ljava/lang/ClassLoader;->getResource(Ljava/lang/String;)Ljava/net/URL;
move-result-object v0
return-object v0
:absent
const/4 v0, 0
:done
return-object v0
.end method')!
	text = framework_replace_method(text, 'getResources(Ljava/lang/String;)Ljava/util/Enumeration;', r'
.method public getResources(Ljava/lang/String;)Ljava/util/Enumeration;
.locals 4
const/4 v0, 3
new-array v0, v0, [Ljava/util/Enumeration;
const-class v1, Ljava/lang/Object;
invoke-virtual {v1}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v1
invoke-virtual {v1, p1}, Ljava/lang/ClassLoader;->getResources(Ljava/lang/String;)Ljava/util/Enumeration;
move-result-object v1
const/4 v2, 0
aput-object v1, v0, v2
invoke-virtual {p0, p1}, Ldalvik/system/DelegateLastClassLoader;->findResources(Ljava/lang/String;)Ljava/util/Enumeration;
move-result-object v1
const/4 v2, 1
aput-object v1, v0, v2
const/4 v3, 0
iget-boolean v1, p0, Ldalvik/system/DelegateLastClassLoader;->delegateResourceLoading:Z
if-eqz v1, :combine
invoke-virtual {p0}, Ldalvik/system/DelegateLastClassLoader;->getParent()Ljava/lang/ClassLoader;
move-result-object v1
if-eqz v1, :combine
invoke-virtual {v1, p1}, Ljava/lang/ClassLoader;->getResources(Ljava/lang/String;)Ljava/util/Enumeration;
move-result-object v3
:combine
const/4 v2, 2
aput-object v3, v0, v2
new-instance v1, Lsun/misc/CompoundEnumeration;
invoke-direct {v1, v0}, Lsun/misc/CompoundEnumeration;-><init>([Ljava/util/Enumeration;)V
return-object v1
.end method')!
	os.write_file(path, text)!
}
