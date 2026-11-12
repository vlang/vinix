// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2006 The Android Open Source Project
// Intent URI serialization adapted from API 28 Intent.java, android-9.0.0_r1.
module androidtools
import os

pub fn framework_intent_to_uri(smali string) ! {
	path := smali + '/android/content/Intent.smali'
	mut text := os.read_file(path)!
	if text.contains(' toUri(I)') || !text.contains(' parseUri(') { return error('Intent parser without serializer required') }
	mut method := r'
.method public toUri(I)Ljava/lang/String;
.locals 10
new-instance v0, Ljava/lang/StringBuilder;
invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
new-instance v1, Ljava/lang/StringBuilder;
invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V
const/4 v2, 0
const/4 v4, 0
const-string v3, "android.intent.action.VIEW"
invoke-virtual {p0}, Landroid/content/Intent;->getData()Landroid/net/Uri;
move-result-object v5
and-int/lit8 v7, p1, 2
if-eqz v7, :ordinary
invoke-virtual {p0}, Landroid/content/Intent;->getPackage()Ljava/lang/String;
move-result-object v4
if-nez v4, :app
new-instance v7, Ljava/lang/IllegalArgumentException;
const-string v8, "android-app URI requires an explicit package"
invoke-direct {v7, v8}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v7
:app
const-string v6, "android-app://"
invoke-virtual {v0, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v3, "android.intent.action.MAIN"
if-eqz v5, :body
invoke-virtual {v5}, Landroid/net/Uri;->getScheme()Ljava/lang/String;
move-result-object v6
if-eqz v6, :body
const-string v3, "android.intent.action.VIEW"
const/16 v7, 0x2f
invoke-virtual {v0, v7}, Ljava/lang/StringBuilder;->append(C)Ljava/lang/StringBuilder;
invoke-virtual {v0, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v5}, Landroid/net/Uri;->getEncodedAuthority()Ljava/lang/String;
move-result-object v6
if-eqz v6, :body
invoke-virtual {v0, v7}, Ljava/lang/StringBuilder;->append(C)Ljava/lang/StringBuilder;
invoke-virtual {v0, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
'
	for getter in ['getEncodedPath', 'getEncodedQuery', 'getEncodedFragment'] {
		separator := if getter == 'getEncodedQuery' { 63 } else if getter == 'getEncodedFragment' { 35 } else { 0 }
		method += 'invoke-virtual {v5}, Landroid/net/Uri;->' + getter + '()Ljava/lang/String;\nmove-result-object v6\nif-eqz v6, :' + getter + '_done\n'
		if separator != 0 { method += 'const/16 v7, ${separator}\ninvoke-virtual {v0, v7}, Ljava/lang/StringBuilder;->append(C)Ljava/lang/StringBuilder;\n' }
		method += 'invoke-virtual {v0, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n:' + getter + '_done\n'
	}
	method += r'goto :body
:ordinary
if-eqz v5, :no_data
invoke-virtual {v5}, Landroid/net/Uri;->toString()Ljava/lang/String;
move-result-object v6
and-int/lit8 v7, p1, 1
if-eqz v7, :append_data
invoke-virtual {v5}, Landroid/net/Uri;->getScheme()Ljava/lang/String;
move-result-object v2
if-eqz v2, :append_data
const-string v8, "[a-zA-Z0-9.+-]+"
invoke-virtual {v2, v8}, Ljava/lang/String;->matches(Ljava/lang/String;)Z
move-result v7
if-nez v7, :intent_scheme
const/4 v2, 0
goto :append_data
:intent_scheme
const-string v7, "intent:"
invoke-virtual {v0, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v2}, Ljava/lang/String;->length()I
move-result v7
add-int/lit8 v7, v7, 1
invoke-virtual {v6, v7}, Ljava/lang/String;->substring(I)Ljava/lang/String;
move-result-object v6
:append_data
invoke-virtual {v0, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
goto :body
:no_data
and-int/lit8 v7, p1, 1
if-eqz v7, :body
const-string v7, "intent:"
invoke-virtual {v0, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
:body
invoke-direct {p0, v1, v2, v3, v4}, Landroid/content/Intent;->vinixUriFields(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {p0}, Landroid/content/Intent;->getSelector()Landroid/content/Intent;
move-result-object v9
if-eqz v9, :fragment
const-string v6, "SEL;"
invoke-virtual {v1, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const/4 v2, 0
const/4 v3, 0
const/4 v4, 0
invoke-virtual {v9}, Landroid/content/Intent;->getData()Landroid/net/Uri;
move-result-object v7
if-eqz v7, :selector
invoke-virtual {v7}, Landroid/net/Uri;->getScheme()Ljava/lang/String;
move-result-object v2
:selector
invoke-direct {v9, v1, v2, v3, v4}, Landroid/content/Intent;->vinixUriFields(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
:fragment
invoke-virtual {v1}, Ljava/lang/StringBuilder;->length()I
move-result v7
if-eqz v7, :result
const-string v6, "#Intent;"
invoke-virtual {v0, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v6
invoke-virtual {v0, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v6, "end"
invoke-virtual {v0, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
:result
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v0
return-object v0
.end method
.method private static vinixUriPart(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
.locals 1
if-eqz p2, :done
invoke-virtual {p0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-static {p2, p3}, Landroid/net/Uri;->encode(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
invoke-virtual {p0, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const/16 v0, 0x3b
invoke-virtual {p0, v0}, Ljava/lang/StringBuilder;->append(C)Ljava/lang/StringBuilder;
:done
return-void
.end method
.method private vinixUriFields(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
.locals 6
const-string v1, "scheme="
const-string v3, "+.-"
invoke-static {p1, v1, p2, v3}, Landroid/content/Intent;->vinixUriPart(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {p0}, Landroid/content/Intent;->getAction()Ljava/lang/String;
move-result-object v2
if-eqz v2, :categories
invoke-virtual {v2, p3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :categories
const-string v1, "action="
const/4 v3, 0
invoke-static {p1, v1, v2, v3}, Landroid/content/Intent;->vinixUriPart(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
:categories
invoke-virtual {p0}, Landroid/content/Intent;->getCategories()Ljava/util/Set;
move-result-object v0
if-eqz v0, :type
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v0
:category
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v2
if-eqz v2, :type
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v2
check-cast v2, Ljava/lang/String;
const-string v1, "category="
const/4 v3, 0
invoke-static {p1, v1, v2, v3}, Landroid/content/Intent;->vinixUriPart(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
goto :category
:type
invoke-virtual {p0}, Landroid/content/Intent;->getType()Ljava/lang/String;
move-result-object v2
const-string v1, "type="
const-string v3, "/"
invoke-static {p1, v1, v2, v3}, Landroid/content/Intent;->vinixUriPart(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {p0}, Landroid/content/Intent;->getFlags()I
move-result v0
if-eqz v0, :package
const-string v1, "launchFlags=0x"
invoke-virtual {p1, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-static {v0}, Ljava/lang/Integer;->toHexString(I)Ljava/lang/String;
move-result-object v2
invoke-virtual {p1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const/16 v0, 0x3b
invoke-virtual {p1, v0}, Ljava/lang/StringBuilder;->append(C)Ljava/lang/StringBuilder;
:package
invoke-virtual {p0}, Landroid/content/Intent;->getPackage()Ljava/lang/String;
move-result-object v2
if-eqz v2, :component
invoke-virtual {v2, p4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :component
const-string v1, "package="
const/4 v3, 0
invoke-static {p1, v1, v2, v3}, Landroid/content/Intent;->vinixUriPart(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
:component
invoke-virtual {p0}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v0
if-eqz v0, :bounds
invoke-virtual {v0}, Landroid/content/ComponentName;->flattenToShortString()Ljava/lang/String;
move-result-object v2
const-string v1, "component="
const-string v3, "/"
invoke-static {p1, v1, v2, v3}, Landroid/content/Intent;->vinixUriPart(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
:bounds
invoke-virtual {p0}, Landroid/content/Intent;->getSourceBounds()Landroid/graphics/Rect;
move-result-object v0
if-eqz v0, :extras
invoke-virtual {v0}, Landroid/graphics/Rect;->flattenToString()Ljava/lang/String;
move-result-object v2
const-string v1, "sourceBounds="
const/4 v3, 0
invoke-static {p1, v1, v2, v3}, Landroid/content/Intent;->vinixUriPart(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
:extras
invoke-virtual {p0}, Landroid/content/Intent;->getExtras()Landroid/os/Bundle;
move-result-object v4
if-eqz v4, :done
invoke-virtual {v4}, Landroid/os/Bundle;->keySet()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v0
:extra
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v3
if-eqz v3, :done
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Ljava/lang/String;
invoke-virtual {v4, v1}, Landroid/os/Bundle;->get(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v2
'
	for kind, tag in {'String': 'S', 'Boolean': 'B', 'Byte': 'b', 'Character': 'c', 'Double': 'd', 'Float': 'f', 'Integer': 'i', 'Long': 'l', 'Short': 's'} {
		method += 'instance-of v3, v2, Ljava/lang/' + kind + ';\nif-eqz v3, :not_' + kind + '\nconst-string v3, "' + tag + '."\ngoto :encode\n:not_' + kind + '\n'
	}
	method += r'goto :extra
:encode
invoke-virtual {p1, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-static {v1}, Landroid/net/Uri;->encode(Ljava/lang/String;)Ljava/lang/String;
move-result-object v5
invoke-virtual {p1, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const/16 v3, 0x3d
invoke-virtual {p1, v3}, Ljava/lang/StringBuilder;->append(C)Ljava/lang/StringBuilder;
invoke-virtual {v2}, Ljava/lang/Object;->toString()Ljava/lang/String;
move-result-object v5
invoke-static {v5}, Landroid/net/Uri;->encode(Ljava/lang/String;)Ljava/lang/String;
move-result-object v5
invoke-virtual {p1, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const/16 v3, 0x3b
invoke-virtual {p1, v3}, Ljava/lang/StringBuilder;->append(C)Ljava/lang/StringBuilder;
goto :extra
:done
return-void
.end method
'
	text += method
	text = framework_replace_method(text, 'toURI()Ljava/lang/String;', '.method public toURI()Ljava/lang/String;\n.locals 1\nconst/4 v0, 0\ninvoke-virtual {p0, v0}, Landroid/content/Intent;->toUri(I)Ljava/lang/String;\nmove-result-object v0\nreturn-object v0\n.end method')!
	os.write_file(path, text)!
}
