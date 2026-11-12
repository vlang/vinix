// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

pub fn framework_voice_capability(smali string) ! {
	path := smali + '/android/telephony/TelephonyManager.smali'
	os.write_file(path, framework_replace_method(os.read_file(path)!, 'isVoiceCapable()Z',
		'.method public isVoiceCapable()Z\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method')!)!
}

pub fn framework_intent_mime(smali string) ! {
	path := smali + '/android/content/IntentFilter.smali'
	mut text := os.read_file(path)!
	if text.contains('addDataType(') { return error('MIME filter support already present') }
	text += r'
.field private vinixMimeTypes:Ljava/util/ArrayList;
.method public final addDataType(Ljava/lang/String;)V
.locals 3
const/16 v0, 0x2f
invoke-virtual {p1, v0}, Ljava/lang/String;->indexOf(I)I
move-result v0
if-lez v0, :bad
add-int/lit8 v0, v0, 1
invoke-virtual {p1}, Ljava/lang/String;->length()I
move-result v1
if-lt v0, v1, :valid
:bad
new-instance v0, Landroid/content/IntentFilter$MalformedMimeTypeException;
invoke-direct {v0, p1}, Landroid/content/IntentFilter$MalformedMimeTypeException;-><init>(Ljava/lang/String;)V
throw v0
:valid
iget-object v0, p0, Landroid/content/IntentFilter;->vinixMimeTypes:Ljava/util/ArrayList;
if-nez v0, :list
new-instance v0, Ljava/util/ArrayList;
invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V
iput-object v0, p0, Landroid/content/IntentFilter;->vinixMimeTypes:Ljava/util/ArrayList;
:list
invoke-virtual {v0, p1}, Ljava/util/ArrayList;->contains(Ljava/lang/Object;)Z
move-result v1
if-nez v1, :done
invoke-virtual {v0, p1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
:done
return-void
.end method
.method public final countDataTypes()I
.locals 1
iget-object v0, p0, Landroid/content/IntentFilter;->vinixMimeTypes:Ljava/util/ArrayList;
if-eqz v0, :empty
invoke-virtual {v0}, Ljava/util/ArrayList;->size()I
move-result v0
return v0
:empty
const/4 v0, 0
return v0
.end method
.method public final getDataType(I)Ljava/lang/String;
.locals 1
iget-object v0, p0, Landroid/content/IntentFilter;->vinixMimeTypes:Ljava/util/ArrayList;
invoke-virtual {v0, p1}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/String;
return-object v0
.end method
.method public final typesIterator()Ljava/util/Iterator;
.locals 1
iget-object v0, p0, Landroid/content/IntentFilter;->vinixMimeTypes:Ljava/util/ArrayList;
if-eqz v0, :done
invoke-virtual {v0}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;
move-result-object v0
:done
return-object v0
.end method
.method public final hasDataType(Ljava/lang/String;)Z
.locals 4
if-eqz p1, :no
iget-object v0, p0, Landroid/content/IntentFilter;->vinixMimeTypes:Ljava/util/ArrayList;
if-eqz v0, :no
invoke-virtual {v0}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;
move-result-object v0
:next
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :no
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Ljava/lang/String;
invoke-virtual {v1, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-nez v2, :yes
const-string v2, "*/*"
invoke-virtual {v2, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-nez v3, :yes
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-nez v3, :yes
const-string v2, "/*"
invoke-virtual {v1, v2}, Ljava/lang/String;->endsWith(Ljava/lang/String;)Z
move-result v3
if-eqz v3, :incoming_wildcard
invoke-virtual {v1}, Ljava/lang/String;->length()I
move-result v3
add-int/lit8 v3, v3, -1
const/4 v2, 0
invoke-virtual {v1, v2, v3}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v2
invoke-virtual {p1, v2}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v3
if-nez v3, :yes
:incoming_wildcard
const-string v2, "/*"
invoke-virtual {p1, v2}, Ljava/lang/String;->endsWith(Ljava/lang/String;)Z
move-result v3
if-eqz v3, :next
invoke-virtual {p1}, Ljava/lang/String;->length()I
move-result v3
add-int/lit8 v3, v3, -1
const/4 v2, 0
invoke-virtual {p1, v2, v3}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v2
invoke-virtual {v1, v2}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v3
if-eqz v3, :next
:yes
const/4 v0, 1
return v0
:no
const/4 v0, 0
return v0
.end method
.method public final matchData(Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;)I
.locals 3
invoke-virtual {p0}, Landroid/content/IntentFilter;->countDataTypes()I
move-result v0
invoke-virtual {p0}, Landroid/content/IntentFilter;->countDataSchemes()I
move-result v1
if-nez v0, :constraints
if-nez v1, :constraints
if-nez p1, :bad_data
if-nez p3, :bad_data
const v2, 0x108000
return v2
:constraints
if-eqz v1, :no_scheme
if-nez p2, :check_scheme
const-string p2, ""
:check_scheme
invoke-virtual {p0, p2}, Landroid/content/IntentFilter;->hasDataScheme(Ljava/lang/String;)Z
move-result v1
if-eqz v1, :bad_data
const v2, 0x208000
goto :matched
:no_scheme
if-nez v0, :mime_scheme
if-nez p3, :bad_data
const v2, 0x108000
goto :matched
:mime_scheme
if-eqz p2, :default_scheme
invoke-virtual {p2}, Ljava/lang/String;->isEmpty()Z
move-result v1
if-nez v1, :default_scheme
const-string v1, "content"
invoke-virtual {v1, p2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-nez v1, :default_scheme
const-string v1, "file"
invoke-virtual {v1, p2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad_data
:default_scheme
const v2, 0x108000
:matched
if-eqz v0, :untyped
invoke-virtual {p0, p1}, Landroid/content/IntentFilter;->hasDataType(Ljava/lang/String;)Z
move-result v1
if-eqz v1, :bad_type
const v2, 0x608000
goto :result
:untyped
if-nez p1, :bad_type
:result
return v2
:bad_type
const/4 v0, -1
return v0
:bad_data
const/4 v0, -2
return v0
.end method
'
	text = framework_replace_method(text, 'match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I', r'.method public match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I
.locals 3
if-eqz p1, :data
invoke-virtual {p0, p1}, Landroid/content/IntentFilter;->hasAction(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :bad_action
:data
invoke-virtual {p0, p2, p3, p4}, Landroid/content/IntentFilter;->matchData(Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;)I
move-result v0
if-ltz v0, :result
if-eqz p5, :result
invoke-interface {p5}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v1
:category
invoke-interface {v1}, Ljava/util/Iterator;->hasNext()Z
move-result v2
if-eqz v2, :result
invoke-interface {v1}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v2
check-cast v2, Ljava/lang/String;
invoke-virtual {p0, v2}, Landroid/content/IntentFilter;->hasCategory(Ljava/lang/String;)Z
move-result v2
if-nez v2, :category
const/4 v0, -4
return v0
:bad_action
const/4 v0, -3
:result
return v0
.end method')!
	os.write_file(path, text)!
	os.write_file(smali + r'/android/content/IntentFilter$MalformedMimeTypeException.smali', r'.class public Landroid/content/IntentFilter$MalformedMimeTypeException;
.super Landroid/util/AndroidException;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/util/AndroidException;-><init>()V
return-void
.end method
.method public constructor <init>(Ljava/lang/String;)V
.locals 0
invoke-direct {p0, p1}, Landroid/util/AndroidException;-><init>(Ljava/lang/String;)V
return-void
.end method
')!
}
