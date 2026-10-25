// SPDX-License-Identifier: GPL-2.0-or-later
// V-generated APK for Maps' TtsSpan descriptors and public span contracts.
module main

import crypto.sha256
import json2
import os
import time

const probe = 'Lorg/vinix/bootstrap/TtsSpanProbe;'
const span = 'Landroid/text/style/TtsSpan;'
const bundle = 'Landroid/os/PersistableBundle;'
const parcel = 'Landroid/os/Parcel;'

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(value string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
		'const-string v1, "BOOTSTRAP-TTS-SPAN-${value}"\n' +
		'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn equal(actual string, expected string, label string) string {
	return 'const-string v9, "${label}"\ninvoke-static {${actual}, ${expected}, v9}, ${probe}->equal(IILjava/lang/String;)V\n'
}

fn same(actual string, expected string, label string) string {
	return 'const-string v9, "${label}"\ninvoke-static {${actual}, ${expected}, v9}, ${probe}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
}

fn text(actual string, expected string, label string) string {
	return 'const-string v9, "${label}"\ninvoke-static {${actual}, ${expected}, v9}, ${probe}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V\n'
}

fn helpers() string {
	mut s := method('private static fail(Ljava/lang/String;)V', '
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0', 1)
	s += method('private static equal(IILjava/lang/String;)V', '
if-eq p0, p1, :ok
invoke-static {p2}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 0)
	s += method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', '
if-eq p0, p1, :ok
invoke-static {p2}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 0)
	s += method('private static text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V', '
invoke-virtual {p1, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :ok
invoke-static {p2}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 1)
	s += method('private static traceAbsent()V', '
invoke-static {}, Ljava/lang/System;->getenv()Ljava/util/Map;
move-result-object v0
invoke-interface {v0}, Ljava/util/Map;->keySet()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v2
:next
invoke-interface {v2}, Ljava/util/Iterator;->hasNext()Z
move-result v0
if-eqz v0, :good
invoke-interface {v2}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/String;
const-string v1, "VINIX_ANDROID_TRACE_"
invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :next
const-string v0, "trace variables must be absent"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:good
' + marker('TRACE-ENV-ABSENT-PASS') + 'return-void', 3)
	return s
}

fn maps_probe() string {
	// agdh.f allocates TtsSpan before its capacity-sized argument bundle.
	mut b := marker('CALL') + '
new-instance v5, ${span}
new-instance v6, ${bundle}
const/4 v1, 1
invoke-direct {v6, v1}, ${bundle}-><init>(I)V
const-string v1, "android.arg.text"
const-string v2, "Turn left in 500 meters"
invoke-virtual {v6, v1, v2}, ${bundle}->putString(Ljava/lang/String;Ljava/lang/String;)V
const-string v1, "android.type.text"
invoke-direct {v5, v1, v6}, ${span}-><init>(Ljava/lang/String;${bundle})V
invoke-virtual {v5}, ${span}->getType()Ljava/lang/String;
move-result-object v2
' + text('v2', 'v1', 'Maps text type') + '
invoke-virtual {v5}, ${span}->getArgs()${bundle}
move-result-object v2
' + same('v2', 'v6', 'constructor retains argument bundle') + '
const-string v1, "android.arg.text"
invoke-virtual {v2, v1}, ${bundle}->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v2
const-string v1, "Turn left in 500 meters"
' + text('v2', 'v1', 'Maps spoken text') + '
const-string v1, "500 m"
invoke-static {v1}, Landroid/text/SpannableString;->valueOf(Ljava/lang/CharSequence;)Landroid/text/SpannableString;
move-result-object v7
const/4 v1, 0
const/4 v2, 5
const/16 v3, 33
invoke-interface {v7, v5, v1, v2, v3}, Landroid/text/Spannable;->setSpan(Ljava/lang/Object;III)V
invoke-interface {v7, v5}, Landroid/text/Spanned;->getSpanStart(Ljava/lang/Object;)I
move-result v2
' + equal('v2', 'v1', 'Maps full span start') + '
invoke-interface {v7, v5}, Landroid/text/Spanned;->getSpanEnd(Ljava/lang/Object;)I
move-result v1
const/4 v2, 5
' + equal('v1', 'v2', 'Maps full span end') + marker('MAPS-PASS') + 'return-void'
	return method('private static maps()V', b, 10)
}

fn make_args() string {
	mut b := '
new-instance v5, ${bundle}
const/4 v0, 0
invoke-direct {v5, v0}, ${bundle}-><init>(I)V
const-string v0, "string"
const-string v1, "fifty three"
invoke-virtual {v5, v0, v1}, ${bundle}->putString(Ljava/lang/String;Ljava/lang/String;)V
const-string v0, "integer"
const/16 v1, -53
invoke-virtual {v5, v0, v1}, ${bundle}->putInt(Ljava/lang/String;I)V
const-string v0, "long"
const-wide v1, 0x123456789abcdefL
invoke-virtual {v5, v0, v1, v2}, ${bundle}->putLong(Ljava/lang/String;J)V
const-string v0, "boolean"
const/4 v1, 1
invoke-virtual {v5, v0, v1}, ${bundle}->putBoolean(Ljava/lang/String;Z)V
const/4 v0, 2
new-array v1, v0, [I
const/4 v0, 0
const/16 v2, -7
aput v2, v1, v0
const/4 v0, 1
const/16 v2, 4096
aput v2, v1, v0
const-string v0, "integers"
invoke-virtual {v5, v0, v1}, ${bundle}->putIntArray(Ljava/lang/String;[I)V
const/4 v0, 2
new-array v1, v0, [J
const/4 v0, 0
const-wide v2, 0x123456789abcdefL
aput-wide v2, v1, v0
const/4 v0, 1
const-wide v2, -53
aput-wide v2, v1, v0
const-string v0, "longs"
invoke-virtual {v5, v0, v1}, ${bundle}->putLongArray(Ljava/lang/String;[J)V
const/4 v0, 2
new-array v1, v0, [Ljava/lang/String;
const/4 v0, 0
const-string v2, "north"
aput-object v2, v1, v0
const/4 v0, 1
const/4 v2, 0
aput-object v2, v1, v0
const-string v0, "strings"
invoke-virtual {v5, v0, v1}, ${bundle}->putStringArray(Ljava/lang/String;[Ljava/lang/String;)V
return-object v5'
	return method('private static args()${bundle}', b, 6)
}

fn check_args() string {
	mut b := '
const-string v0, "string"
invoke-virtual {p0, v0}, ${bundle}->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
const-string v2, "fifty three"
' + text('v1', 'v2', 'argument string') + '
const-string v0, "integer"
invoke-virtual {p0, v0}, ${bundle}->getInt(Ljava/lang/String;)I
move-result v1
const/16 v2, -53
' + equal('v1', 'v2', 'argument integer') + '
const-string v0, "long"
invoke-virtual {p0, v0}, ${bundle}->getLong(Ljava/lang/String;)J
move-result-wide v1
const-wide v3, 0x123456789abcdefL
cmp-long v1, v1, v3
const/4 v2, 0
' + equal('v1', 'v2', 'argument long') + '
const-string v0, "boolean"
invoke-virtual {p0, v0}, ${bundle}->getBoolean(Ljava/lang/String;)Z
move-result v1
const/4 v2, 1
' + equal('v1', 'v2', 'argument boolean') + '
const-string v0, "integers"
invoke-virtual {p0, v0}, ${bundle}->getIntArray(Ljava/lang/String;)[I
move-result-object v5
array-length v1, v5
const/4 v2, 2
' + equal('v1', 'v2', 'argument int array length') + '
const/4 v0, 0
aget v1, v5, v0
const/16 v2, -7
' + equal('v1', 'v2', 'argument int array first') + '
const/4 v0, 1
aget v1, v5, v0
const/16 v2, 4096
' + equal('v1', 'v2', 'argument int array last') + '
const-string v0, "longs"
invoke-virtual {p0, v0}, ${bundle}->getLongArray(Ljava/lang/String;)[J
move-result-object v5
array-length v1, v5
const/4 v2, 2
' + equal('v1', 'v2', 'argument long array length') + '
const/4 v0, 0
aget-wide v1, v5, v0
const-wide v3, 0x123456789abcdefL
cmp-long v1, v1, v3
const/4 v2, 0
' + equal('v1', 'v2', 'argument long array first') + '
const/4 v0, 1
aget-wide v1, v5, v0
const-wide v3, -53
cmp-long v1, v1, v3
const/4 v2, 0
' + equal('v1', 'v2', 'argument long array last') + '
const-string v0, "strings"
invoke-virtual {p0, v0}, ${bundle}->getStringArray(Ljava/lang/String;)[Ljava/lang/String;
move-result-object v5
array-length v1, v5
const/4 v2, 2
' + equal('v1', 'v2', 'argument string array length') + '
const/4 v0, 0
aget-object v1, v5, v0
const-string v2, "north"
' + text('v1', 'v2', 'argument string array first') + '
const/4 v0, 1
aget-object v1, v5, v0
const/4 v2, 0
' + same('v1', 'v2', 'argument string array null element') + 'return-void'
	return method('private static checkArgs(${bundle})V', b, 10)
}

fn core_probe() string {
	mut b := '
invoke-static {}, ${probe}->args()${bundle}
move-result-object v6
new-instance v5, ${span}
const-string v1, "example.custom.type"
invoke-direct {v5, v1, v6}, ${span}-><init>(Ljava/lang/String;${bundle})V
invoke-virtual {v5}, ${span}->getType()Ljava/lang/String;
move-result-object v2
' + text('v2', 'v1', 'custom type is retained') + '
invoke-virtual {v5}, ${span}->getArgs()${bundle}
move-result-object v1
' + same('v1', 'v6', 'arguments retain identity') + '
invoke-static {v1}, ${probe}->checkArgs(${bundle})V
const-string v1, "after-construction"
const-string v2, "live data"
invoke-virtual {v6, v1, v2}, ${bundle}->putString(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v5}, ${span}->getArgs()${bundle}
move-result-object v3
invoke-virtual {v3, v1}, ${bundle}->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v3
' + text('v3', 'v2', 'argument mutations remain observable') + '
invoke-virtual {v5}, ${span}->describeContents()I
move-result v1
const/4 v2, 0
' + equal('v1', 'v2', 'span describes no special parcel contents') + '
invoke-virtual {v5}, ${span}->getSpanTypeId()I
move-result v1
const/16 v2, 24
' + equal('v1', 'v2', 'public TTS span type id') + '
invoke-virtual {v5}, ${span}->getSpanTypeIdInternal()I
move-result v1
' + equal('v1', 'v2', 'internal parcel span type id agrees') + '
instance-of v1, v5, Landroid/text/ParcelableSpan;
const/4 v2, 1
' + equal('v1', 'v2', 'span implements ParcelableSpan') + '
new-instance v5, ${span}
const/4 v1, 0
invoke-direct {v5, v1, v1}, ${span}-><init>(Ljava/lang/String;${bundle})V
invoke-virtual {v5}, ${span}->getType()Ljava/lang/String;
move-result-object v2
' + same('v2', 'v1', 'null type is retained') + '
invoke-virtual {v5}, ${span}->getArgs()${bundle}
move-result-object v2
' + same('v2', 'v1', 'null arguments are retained') + '
new-instance v5, ${bundle}
const/4 v1, -1
invoke-direct {v5, v1}, ${bundle}-><init>(I)V
invoke-virtual {v5}, ${bundle}->size()I
move-result v1
const/4 v2, 0
' + equal('v1', 'v2', 'negative capacity creates empty arguments') + '
const-string v1, "negative-capacity"
const-string v2, "mutable data"
invoke-virtual {v5, v1, v2}, ${bundle}->putString(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v5, v1}, ${bundle}->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v3
' + text('v3', 'v2', 'negative capacity arguments remain mutable')
	for name, value in {
		'TYPE_TEXT':        'android.type.text'
		'TYPE_VERBATIM':    'android.type.verbatim'
		'ARG_TEXT':         'android.arg.text'
		'ARG_VERBATIM':     'android.arg.verbatim'
		'ARG_GENDER':       'android.arg.gender'
		'ARG_ANIMACY':      'android.arg.animacy'
		'ARG_MULTIPLICITY': 'android.arg.multiplicity'
		'ARG_CASE':         'android.arg.case'
	} {
		b += '\nsget-object v1, ${span}->${name}:Ljava/lang/String;\nconst-string v2, "${value}"\n' + text('v1', 'v2', '${name} public literal')
	}
	b += marker('CORE-PASS') + 'return-void'
	return method('private static core()V', b, 10)
}

fn parcel_probe() string {
	mut b := '
invoke-static {}, ${probe}->args()${bundle}
move-result-object v6
new-instance v5, ${span}
const-string v1, "example.parcel.type"
invoke-direct {v5, v1, v6}, ${span}-><init>(Ljava/lang/String;${bundle})V
invoke-static {}, ${parcel}->obtain()${parcel}
move-result-object v7
const/4 v1, 0
invoke-virtual {v5, v7, v1}, ${span}->writeToParcel(${parcel}I)V
const v2, 0x1234abcd
invoke-virtual {v7, v2}, ${parcel}->writeInt(I)V
invoke-virtual {v7, v1}, ${parcel}->setDataPosition(I)V
invoke-virtual {v7}, ${parcel}->readString()Ljava/lang/String;
move-result-object v1
const-string v2, "example.parcel.type"
' + text('v1', 'v2', 'parcel writes type first') + '
invoke-virtual {v7}, ${parcel}->readPersistableBundle()${bundle}
move-result-object v1
invoke-static {v1}, ${probe}->checkArgs(${bundle})V
invoke-virtual {v7}, ${parcel}->readInt()I
move-result v1
const v2, 0x1234abcd
' + equal('v1', 'v2', 'parcel output preserves trailing value') + '
invoke-virtual {v7}, ${parcel}->dataAvail()I
move-result v1
const/4 v2, 0
' + equal('v1', 'v2', 'parcel output consumes exactly its data') + '
invoke-virtual {v7}, ${parcel}->recycle()V
' + marker('PARCEL-WRITE-PASS') + '
invoke-static {}, ${parcel}->obtain()${parcel}
move-result-object v7
const-string v1, "independent.wire.type"
invoke-virtual {v7, v1}, ${parcel}->writeString(Ljava/lang/String;)V
invoke-virtual {v7, v6}, ${parcel}->writePersistableBundle(${bundle})V
const v1, 0x1234abcd
invoke-virtual {v7, v1}, ${parcel}->writeInt(I)V
invoke-virtual {v7}, ${parcel}->marshall()[B
move-result-object v8
invoke-virtual {v7}, ${parcel}->recycle()V
invoke-static {}, ${parcel}->obtain()${parcel}
move-result-object v7
const/4 v1, 0
array-length v2, v8
invoke-virtual {v7, v8, v1, v2}, ${parcel}->unmarshall([BII)V
invoke-virtual {v7, v1}, ${parcel}->setDataPosition(I)V
new-instance v5, ${span}
invoke-direct {v5, v7}, ${span}-><init>(${parcel})V
invoke-virtual {v5}, ${span}->getType()Ljava/lang/String;
move-result-object v1
const-string v2, "independent.wire.type"
' + text('v1', 'v2', 'parcel constructor reads independent type') + '
invoke-virtual {v5}, ${span}->getArgs()${bundle}
move-result-object v1
invoke-static {v1}, ${probe}->checkArgs(${bundle})V
invoke-virtual {v7}, ${parcel}->readInt()I
move-result v1
const v2, 0x1234abcd
' + equal('v1', 'v2', 'parcel constructor preserves trailing value') + '
invoke-virtual {v7}, ${parcel}->dataAvail()I
move-result v1
const/4 v2, 0
' + equal('v1', 'v2', 'parcel constructor consumes exactly its data') + '
invoke-virtual {v7}, ${parcel}->recycle()V
const-string v1, "string"
const-string v2, "source changed after transport"
invoke-virtual {v6, v1, v2}, ${bundle}->putString(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v5}, ${span}->getArgs()${bundle}
move-result-object v1
invoke-static {v1}, ${probe}->checkArgs(${bundle})V
' + marker('PARCEL-READ-PASS')
	// Internal write has the same wire and accepts absent arguments.
	b += '
new-instance v5, ${span}
const/4 v1, 0
invoke-direct {v5, v1, v1}, ${span}-><init>(Ljava/lang/String;${bundle})V
invoke-static {}, ${parcel}->obtain()${parcel}
move-result-object v7
invoke-virtual {v5, v7, v1}, ${span}->writeToParcelInternal(${parcel}I)V
invoke-virtual {v7, v1}, ${parcel}->setDataPosition(I)V
new-instance v5, ${span}
invoke-direct {v5, v7}, ${span}-><init>(${parcel})V
invoke-virtual {v5}, ${span}->getType()Ljava/lang/String;
move-result-object v2
const/4 v1, 0
' + same('v2', 'v1', 'null type survives internal parcel') + '
invoke-virtual {v5}, ${span}->getArgs()${bundle}
move-result-object v2
' + same('v2', 'v1', 'null arguments survive internal parcel') + '
invoke-virtual {v7}, ${parcel}->dataAvail()I
move-result v2
' + equal('v2', 'v1', 'null parcel ends exactly') + '
invoke-virtual {v7}, ${parcel}->recycle()V
' + marker('PARCEL-NULL-PASS') + '
invoke-static {}, ${parcel}->obtain()${parcel}
move-result-object v7
new-instance v6, ${bundle}
const/4 v1, 0
invoke-direct {v6, v1}, ${bundle}-><init>(I)V
invoke-virtual {v6}, ${bundle}->size()I
move-result v2
' + equal('v2', 'v1', 'zero capacity creates empty arguments') + '
invoke-virtual {v7, v6}, ${parcel}->writePersistableBundle(${bundle})V
const v2, 0x1234abcd
invoke-virtual {v7, v2}, ${parcel}->writeInt(I)V
invoke-virtual {v7, v1}, ${parcel}->setDataPosition(I)V
invoke-virtual {v7, v1}, ${parcel}->readPersistableBundle(Ljava/lang/ClassLoader;)${bundle}
move-result-object v6
instance-of v1, v6, ${bundle}
const/4 v2, 1
' + equal('v1', 'v2', 'empty arguments stay nonnull in parcel') + '
invoke-virtual {v6}, ${bundle}->size()I
move-result v1
const/4 v2, 0
' + equal('v1', 'v2', 'empty arguments retain zero entries') + '
invoke-virtual {v7}, ${parcel}->readInt()I
move-result v1
const v2, 0x1234abcd
' + equal('v1', 'v2', 'empty arguments preserve parcel suffix') + '
invoke-virtual {v7}, ${parcel}->dataAvail()I
move-result v1
const/4 v2, 0
' + equal('v1', 'v2', 'empty arguments consume exact stream') + '
invoke-virtual {v7}, ${parcel}->recycle()V
' + marker('PARCEL-EMPTY-PASS') + 'return-void'
	return method('private static parcels()V', b, 10)
}

fn spans_probe() string {
	mut b := '
new-instance v5, ${span}
new-instance v6, ${bundle}
invoke-direct {v6}, ${bundle}-><init>()V
const-string v1, "android.type.text"
invoke-direct {v5, v1, v6}, ${span}-><init>(Ljava/lang/String;${bundle})V
new-instance v6, Landroid/text/SpannableString;
const-string v1, "one two three"
invoke-direct {v6, v1}, Landroid/text/SpannableString;-><init>(Ljava/lang/CharSequence;)V
const/4 v1, 4
const/4 v2, 7
const/16 v3, 33
invoke-virtual {v6, v5, v1, v2, v3}, Landroid/text/SpannableString;->setSpan(Ljava/lang/Object;III)V
new-instance v7, Landroid/text/style/ForegroundColorSpan;
const v1, 0xff2471c4
invoke-direct {v7, v1}, Landroid/text/style/ForegroundColorSpan;-><init>(I)V
const/4 v1, 0
const/4 v2, 3
invoke-virtual {v6, v7, v1, v2, v3}, Landroid/text/SpannableString;->setSpan(Ljava/lang/Object;III)V
const/4 v1, 4
const/4 v2, 7
const-class v3, ${span}
invoke-virtual {v6, v1, v2, v3}, Landroid/text/SpannableString;->getSpans(IILjava/lang/Class;)[Ljava/lang/Object;
move-result-object v8
array-length v1, v8
const/4 v2, 1
' + equal('v1', 'v2', 'typed span query finds only TtsSpan') + '
const/4 v1, 0
aget-object v2, v8, v1
' + same('v2', 'v5', 'typed span query retains identity') + '
invoke-virtual {v6, v5}, Landroid/text/SpannableString;->getSpanFlags(Ljava/lang/Object;)I
move-result v1
const/16 v2, 33
' + equal('v1', 'v2', 'span flags retained') + '
new-instance v8, Landroid/text/SpannedString;
invoke-direct {v8, v6}, Landroid/text/SpannedString;-><init>(Ljava/lang/CharSequence;)V
const/16 v1, 8
const/16 v2, 13
const/16 v3, 18
invoke-virtual {v6, v5, v1, v2, v3}, Landroid/text/SpannableString;->setSpan(Ljava/lang/Object;III)V
invoke-virtual {v6, v5}, Landroid/text/SpannableString;->getSpanStart(Ljava/lang/Object;)I
move-result v2
' + equal('v2', 'v1', 'reapplying span moves its range') + '
invoke-virtual {v8, v5}, Landroid/text/SpannedString;->getSpanStart(Ljava/lang/Object;)I
move-result v1
const/4 v2, 4
' + equal('v1', 'v2', 'immutable snapshot retains original range') + '
invoke-virtual {v8, v5}, Landroid/text/SpannedString;->getSpanEnd(Ljava/lang/Object;)I
move-result v1
const/4 v2, 7
' + equal('v1', 'v2', 'immutable snapshot retains original end') + '
invoke-virtual {v6, v5}, Landroid/text/SpannableString;->removeSpan(Ljava/lang/Object;)V
invoke-virtual {v6, v5}, Landroid/text/SpannableString;->getSpanStart(Ljava/lang/Object;)I
move-result v1
const/4 v2, -1
' + equal('v1', 'v2', 'removed span is absent') + '
invoke-virtual {v6, v7}, Landroid/text/SpannableString;->getSpanStart(Ljava/lang/Object;)I
move-result v1
const/4 v2, 0
' + equal('v1', 'v2', 'removing TtsSpan preserves other span classes') + '
invoke-virtual {v8, v5}, Landroid/text/SpannedString;->getSpanStart(Ljava/lang/Object;)I
move-result v1
const/4 v2, 4
' + equal('v1', 'v2', 'removal preserves snapshot span') + marker('SPANS-PASS') + 'return-void'
	return method('private static spans()V', b, 10)
}

fn builders_probe() string {
	builder := 'Landroid/text/style/TtsSpan\$Builder;'
	semiotic := 'Landroid/text/style/TtsSpan\$SemioticClassBuilder;'
	mut b := '
new-instance v5, ${builder}
const-string v1, "example.builder.type"
invoke-direct {v5, v1}, ${builder}-><init>(Ljava/lang/String;)V
const-string v1, "word"
const-string v2, "first"
invoke-virtual {v5, v1, v2}, ${builder}->setStringArgument(Ljava/lang/String;Ljava/lang/String;)${builder}
move-result-object v1
' + same('v1', 'v5', 'string setter returns builder for chaining') + '
const-string v1, "count"
const/16 v2, -53
invoke-virtual {v5, v1, v2}, ${builder}->setIntArgument(Ljava/lang/String;I)${builder}
move-result-object v1
' + same('v1', 'v5', 'integer setter returns builder for chaining') + '
const-string v1, "distance"
const-wide v2, 0x123456789abcdefL
invoke-virtual {v5, v1, v2, v3}, ${builder}->setLongArgument(Ljava/lang/String;J)${builder}
move-result-object v1
' + same('v1', 'v5', 'wide setter returns builder for chaining') + '
invoke-virtual {v5}, ${builder}->build()${span}
move-result-object v6
invoke-virtual {v6}, ${span}->getType()Ljava/lang/String;
move-result-object v1
const-string v2, "example.builder.type"
' + text('v1', 'v2', 'builder preserves chosen type') + '
invoke-virtual {v6}, ${span}->getArgs()${bundle}
move-result-object v7
const-string v1, "count"
invoke-virtual {v7, v1}, ${bundle}->getInt(Ljava/lang/String;)I
move-result v1
const/16 v2, -53
' + equal('v1', 'v2', 'builder stores signed integer') + '
const-string v1, "distance"
invoke-virtual {v7, v1}, ${bundle}->getLong(Ljava/lang/String;)J
move-result-wide v1
const-wide v3, 0x123456789abcdefL
cmp-long v1, v1, v3
const/4 v2, 0
' + equal('v1', 'v2', 'builder stores all long bits') + '
const-string v1, "word"
const-string v2, "second"
invoke-virtual {v5, v1, v2}, ${builder}->setStringArgument(Ljava/lang/String;Ljava/lang/String;)${builder}
invoke-virtual {v7, v1}, ${bundle}->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
' + text('v1', 'v2', 'built span observes subsequent builder writes') + '
invoke-virtual {v5}, ${builder}->build()${span}
move-result-object v6
invoke-virtual {v6}, ${span}->getArgs()${bundle}
move-result-object v1
' + same('v1', 'v7', 'successive builds share builder arguments')
	for name, value in {
		'Gender':       'female'
		'Animacy':      'animate'
		'Multiplicity': 'plural'
		'Case':         'genitive'
	} {
		b += '\nnew-instance v5, ${semiotic}\nconst-string v1, "example.semiotic.type"\ninvoke-direct {v5, v1}, ${semiotic}-><init>(Ljava/lang/String;)V\nconst-string v2, "${value}"\ninvoke-virtual {v5, v2}, ${semiotic}->set${name}(Ljava/lang/String;)${semiotic}\nmove-result-object v1\n' + same('v1', 'v5', '${name} setter returns semiotic builder') +
			'invoke-virtual {v5}, ${semiotic}->build()${span}\nmove-result-object v6\ninvoke-virtual {v6}, ${span}->getArgs()${bundle}\nmove-result-object v7\nconst-string v1, "android.arg.${name.to_lower()}"\ninvoke-virtual {v7, v1}, ${bundle}->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v1\n' + text('v1', 'v2', '${name} setter stores public argument key')
	}
	for name, key in {
		'TextBuilder':     'text'
		'VerbatimBuilder': 'verbatim'
	} {
		child := 'Landroid/text/style/TtsSpan\$${name};'
		setter := if key == 'text' { 'Text' } else { 'Verbatim' }
		b += '\nnew-instance v5, ${child}\nconst-string v1, "initial pronunciation"\ninvoke-direct {v5, v1}, ${child}-><init>(Ljava/lang/String;)V\ninvoke-virtual {v5}, ${child}->build()${span}\nmove-result-object v6\ninvoke-virtual {v6}, ${span}->getType()Ljava/lang/String;\nmove-result-object v1\nconst-string v2, "android.type.${key}"\n' + text('v1', 'v2', '${name} fixed public type') +
			'invoke-virtual {v6}, ${span}->getArgs()${bundle}\nmove-result-object v7\nconst-string v1, "android.arg.${key}"\ninvoke-virtual {v7, v1}, ${bundle}->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v1\nconst-string v2, "initial pronunciation"\n' + text('v1', 'v2', '${name} constructor value') +
			'const-string v2, "updated pronunciation"\ninvoke-virtual {v5, v2}, ${child}->set${setter}(Ljava/lang/String;)${child}\nmove-result-object v1\n' + same('v1', 'v5', '${name} setter returns concrete builder') +
			'const-string v1, "android.arg.${key}"\ninvoke-virtual {v7, v1}, ${bundle}->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v1\n' + text('v1', 'v2', '${name} setter updates already built span') +
			'new-instance v5, ${child}\ninvoke-direct {v5}, ${child}-><init>()V\ninvoke-virtual {v5}, ${child}->build()${span}\nmove-result-object v6\ninvoke-virtual {v6}, ${span}->getArgs()${bundle}\nmove-result-object v7\nconst-string v1, "android.arg.${key}"\ninvoke-virtual {v7, v1}, ${bundle}->containsKey(Ljava/lang/String;)Z\nmove-result v1\nconst/4 v2, 0\n' + equal('v1', 'v2', '${name} empty constructor leaves argument absent')
	}
	b += marker('BUILDERS-PASS') + 'return-void'
	return method('private static builders()V', b, 10)
}

fn probe_class() string {
	return '.class public ${probe}\n.super Ljava/lang/Object;\n' + helpers() + make_args() +
		check_args() + maps_probe() + core_probe() + builders_probe() + parcel_probe() + spans_probe() +
		method('public static run()V', 'invoke-static {}, ${probe}->traceAbsent()V\n' +
			'invoke-static {}, ${probe}->maps()V\ninvoke-static {}, ${probe}->core()V\n' +
			'invoke-static {}, ${probe}->builders()V\ninvoke-static {}, ${probe}->parcels()V\ninvoke-static {}, ${probe}->spans()V\n' +
			marker('PASS') + 'return-void', 2)
}

fn activity() string {
	return '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) +
		method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\ninvoke-static {}, ${probe}->run()V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nconst-string v1, "TtsSpan fixture passed"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-READY"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void', 2)
}

fn file_hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn checked(out string, name string, args []string, pins map[string]string) ! {
	for path, pin in pins {
		assert file_hash(path)! == pin, path
	}
	started := time.utc().str()
	r := os.exec(args)
	os.write_file(out + '/' + name + '.log', r.output)!
	os.write_file(out + '/' + name + '-receipt.json', json2.encode({
		'argv':             json2.Any(args)
		'started_utc':      json2.Any(started)
		'completed_utc':    json2.Any(time.utc().str())
		'exit_code':        json2.Any(r.exit_code)
		'input_sha256':     json2.decode[json2.Any](json2.encode(pins))!
		'generator_sha256': json2.Any(file_hash(os.executable())!)
	},
		prettify: true
	) + '\n')!
	for path, pin in pins {
		assert file_hash(path)! == pin, path
	}
	assert r.exit_code == 0, name + ': ' + r.output
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out), 'fresh output required'
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.mkdir_all(out + '/res/values')!
	os.write_file(out + '/res/values/values.xml', '<resources><string name="app_name">TtsSpan fixture</string></resources>')!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="TtsSpan fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/TtsSpanProbe.smali', probe_class())!
	tools := os.getenv('TTS_SPAN_FIXTURE_TOOLS_ROOT')
	aapt := if tools == '' {
		os.abs_path('build/android-native-ws/aapt2')
	} else {
		tools + '/aapt2'
	}
	signer := if tools == '' {
		os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar')
	} else {
		tools + '/apksigner.jar'
	}
	framework := if tools == '' {
		'/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	} else {
		tools + '/framework-res.apk'
	}
	smali := if tools == '' {
		os.abs_path('build/android-framework/tools')
	} else {
		tools + '/smali'
	}
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	keytool := '/opt/homebrew/opt/openjdk@25/bin/keytool'
	zip := '/usr/bin/zip'
	mut pins := map[string]string{}
	for path in [aapt, signer, framework, java, keytool, zip] { pins[path] = file_hash(path)! }
	for name in os.ls(smali)! {
		if name.ends_with('.jar') { pins[smali + '/' + name] = file_hash(smali + '/' + name)! }
	}
	assert pins.len > 6
	os.write_file(out + '/tool-inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	checked(out, 'resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'], pins)!
	checked(out, 'aapt2', [aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml',
		'-o', out + '/unsigned.apk', out + '/resources.zip'], pins)!
	checked(out, 'smali', [java, '-cp', smali + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali',
		'-o', out + '/classes.dex'], pins)!
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'], pins)!
	key := out + '/fixture.p12'
	checked(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname',
		'CN=Vinix TtsSpan fixture', '-storepass', 'android', '-keypass', 'android'], pins)!
	checked(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture',
		'--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk',
		out + '/unsigned.apk'], pins)!
	checked(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'], pins)!
	os.write_file(out + '/tool-inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	println('TTS-SPAN-APK ' + file_hash(out + '/probe.apk')!)
}
