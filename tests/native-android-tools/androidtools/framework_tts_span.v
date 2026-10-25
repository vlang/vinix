// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn tts_span_method(signature string, locals int, body string) string {
	return '.method public ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn tts_span_builder_class(name string, parent string) string {
	return '.class public Landroid/text/style/TtsSpan\$${name};\n.super Landroid/text/style/TtsSpan\$${parent};\n.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/text/style/TtsSpan;\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x9\nname = "${name}"\n.end annotation\n'
}

// TtsSpan is metadata, not a drawing span. Keep the supplied argument bundle
// and each builder's bundle by reference, as Android does. Parceling uses this
// framework's existing Bundle map codec; it does not add a nested-bundle codec.
fn framework_tts_span(smali string) ! {
	style := smali + '/android/text/style/'
	for name in ['TtsSpan', 'TtsSpan$Builder', 'TtsSpan$SemioticClassBuilder', 'TtsSpan$TextBuilder',
		'TtsSpan$VerbatimBuilder'] {
		if os.exists(style + name + '.smali') { return error('${name} already present') }
	}
	owner := 'Landroid/text/style/TtsSpan;'
	mut text := '.class public ${owner}\n.super Ljava/lang/Object;\n.implements Landroid/text/ParcelableSpan;\n.implements Landroid/os/Parcelable;\n.field private final mType:Ljava/lang/String;\n.field private final mArgs:Landroid/os/PersistableBundle;\n.annotation system Ldalvik/annotation/MemberClasses;\nvalue = {Landroid/text/style/TtsSpan\$Builder;, Landroid/text/style/TtsSpan\$SemioticClassBuilder;, Landroid/text/style/TtsSpan\$TextBuilder;, Landroid/text/style/TtsSpan\$VerbatimBuilder;}\n.end annotation\n'
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
		text += '.field public static final ${name}:Ljava/lang/String; = "${value}"\n'
	}
	text += tts_span_method('constructor <init>(Ljava/lang/String;Landroid/os/PersistableBundle;)V', 0,
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${owner}->mType:Ljava/lang/String;\niput-object p2, p0, ${owner}->mArgs:Landroid/os/PersistableBundle;\nreturn-void')
	text += tts_span_method('constructor <init>(Landroid/os/Parcel;)V', 1,
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\niput-object v0, p0, ${owner}->mType:Ljava/lang/String;\ninvoke-virtual {p1}, Landroid/os/Parcel;->readPersistableBundle()Landroid/os/PersistableBundle;\nmove-result-object v0\niput-object v0, p0, ${owner}->mArgs:Landroid/os/PersistableBundle;\nreturn-void')
	text += tts_span_method('getType()Ljava/lang/String;', 1,
		'iget-object v0, p0, ${owner}->mType:Ljava/lang/String;\nreturn-object v0')
	text += tts_span_method('getArgs()Landroid/os/PersistableBundle;', 1,
		'iget-object v0, p0, ${owner}->mArgs:Landroid/os/PersistableBundle;\nreturn-object v0')
	text += tts_span_method('describeContents()I', 1, 'const/4 v0, 0\nreturn v0')
	text += tts_span_method('getSpanTypeIdInternal()I', 1, 'const/16 v0, 24\nreturn v0')
	text += tts_span_method('getSpanTypeId()I', 1,
		'invoke-virtual {p0}, ${owner}->getSpanTypeIdInternal()I\nmove-result v0\nreturn v0')
	text += tts_span_method('writeToParcel(Landroid/os/Parcel;I)V', 0,
		'invoke-virtual {p0, p1, p2}, ${owner}->writeToParcelInternal(Landroid/os/Parcel;I)V\nreturn-void')
	text += tts_span_method('writeToParcelInternal(Landroid/os/Parcel;I)V', 1,
		'iget-object v0, p0, ${owner}->mType:Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\niget-object v0, p0, ${owner}->mArgs:Landroid/os/PersistableBundle;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writePersistableBundle(Landroid/os/PersistableBundle;)V\nreturn-void')
	os.write_file(style + 'TtsSpan.smali', text)!

	builder := 'Landroid/text/style/TtsSpan$Builder;'
	mut build := tts_span_builder_class('Builder', 'Builder')
	build = build.replace('.super ${builder}', '.super Ljava/lang/Object;')
	build += '.field private final mType:Ljava/lang/String;\n.field private final mArgs:Landroid/os/PersistableBundle;\n'
	build += tts_span_method('constructor <init>(Ljava/lang/String;)V', 1,
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${builder}->mType:Ljava/lang/String;\nnew-instance v0, Landroid/os/PersistableBundle;\ninvoke-direct {v0}, Landroid/os/PersistableBundle;-><init>()V\niput-object v0, p0, ${builder}->mArgs:Landroid/os/PersistableBundle;\nreturn-void')
	build += tts_span_method('build()${owner}', 3,
		'new-instance v0, ${owner}\niget-object v1, p0, ${builder}->mType:Ljava/lang/String;\niget-object v2, p0, ${builder}->mArgs:Landroid/os/PersistableBundle;\ninvoke-direct {v0, v1, v2}, ${owner}-><init>(Ljava/lang/String;Landroid/os/PersistableBundle;)V\nreturn-object v0')
	for kind, descriptor in {
		'String': 'Ljava/lang/String;'
		'Int':    'I'
		'Long':   'J'
	} {
		args := if kind == 'Long' { 'v0, p1, p2, p3' } else { 'v0, p1, p2' }
		build += tts_span_method('set${kind}Argument(Ljava/lang/String;${descriptor})${builder}', 1,
			'iget-object v0, p0, ${builder}->mArgs:Landroid/os/PersistableBundle;\ninvoke-virtual {${args}}, Landroid/os/PersistableBundle;->put${kind}(Ljava/lang/String;${descriptor})V\nreturn-object p0')
	}
	os.write_file(style + 'TtsSpan$Builder.smali', build)!

	semiotic := 'Landroid/text/style/TtsSpan$SemioticClassBuilder;'
	mut semi := tts_span_builder_class('SemioticClassBuilder', 'Builder')
	semi += tts_span_method('constructor <init>(Ljava/lang/String;)V', 0,
		'invoke-direct {p0, p1}, ${builder}-><init>(Ljava/lang/String;)V\nreturn-void')
	for name, key in {
		'Gender':       'gender'
		'Animacy':      'animacy'
		'Multiplicity': 'multiplicity'
		'Case':         'case'
	} {
		semi += tts_span_method('set${name}(Ljava/lang/String;)${semiotic}', 1,
			'const-string v0, "android.arg.${key}"\ninvoke-virtual {p0, v0, p1}, ${builder}->setStringArgument(Ljava/lang/String;Ljava/lang/String;)${builder}\nreturn-object p0')
	}
	os.write_file(style + 'TtsSpan$SemioticClassBuilder.smali', semi)!

	for name, key in {
		'TextBuilder':     'text'
		'VerbatimBuilder': 'verbatim'
	} {
		child := 'Landroid/text/style/TtsSpan$${name};'
		setter := if key == 'text' { 'Text' } else { 'Verbatim' }
		mut body := tts_span_builder_class(name, 'SemioticClassBuilder')
		body += tts_span_method('constructor <init>()V', 1,
			'const-string v0, "android.type.${key}"\ninvoke-direct {p0, v0}, ${semiotic}-><init>(Ljava/lang/String;)V\nreturn-void')
		body += tts_span_method('constructor <init>(Ljava/lang/String;)V', 0,
			'invoke-direct {p0}, ${child}-><init>()V\ninvoke-virtual {p0, p1}, ${child}->set${setter}(Ljava/lang/String;)${child}\nreturn-void')
		body += tts_span_method('set${setter}(Ljava/lang/String;)${child}', 1,
			'const-string v0, "android.arg.${key}"\ninvoke-virtual {p0, v0, p1}, ${builder}->setStringArgument(Ljava/lang/String;Ljava/lang/String;)${builder}\nreturn-object p0')
		os.write_file(style + 'TtsSpan$${name}.smali', body)!
	}

	persist_path := smali + '/android/os/PersistableBundle.smali'
	mut persist := os.read_file(persist_path)!
	if persist.contains('<init>(I)V') {
		return error('PersistableBundle capacity constructor already present')
	}
	persist += tts_span_method('constructor <init>(I)V', 1,
		'invoke-direct {p0}, Landroid/os/BaseBundle;-><init>()V\nif-gtz p1, :capacity\nconst/4 p1, 0\n:capacity\nnew-instance v0, Landroid/util/ArrayMap;\ninvoke-direct {v0, p1}, Landroid/util/ArrayMap;-><init>(I)V\niput-object v0, p0, Landroid/os/BaseBundle;->mMap:Landroid/util/ArrayMap;\nreturn-void')
	os.write_file(persist_path, persist)!

	parcel_path := smali + '/android/os/Parcel.smali'
	mut parcel := os.read_file(parcel_path)!
	if parcel.contains('PersistableBundle(') {
		return error('Parcel persistable bundle methods already present')
	}
	parcel += tts_span_method('writePersistableBundle(Landroid/os/PersistableBundle;)V', 1,
		'const/4 v0, 0\nif-eqz p1, :write\niget-object v0, p1, Landroid/os/BaseBundle;->mMap:Landroid/util/ArrayMap;\n:write\ninvoke-virtual {p0, v0}, Landroid/os/Parcel;->writeMap(Ljava/util/Map;)V\nreturn-void')
	parcel += tts_span_method('readPersistableBundle()Landroid/os/PersistableBundle;', 1,
		'const/4 v0, 0\ninvoke-virtual {p0, v0}, Landroid/os/Parcel;->readPersistableBundle(Ljava/lang/ClassLoader;)Landroid/os/PersistableBundle;\nmove-result-object v0\nreturn-object v0')
	parcel += tts_span_method('readPersistableBundle(Ljava/lang/ClassLoader;)Landroid/os/PersistableBundle;', 3,
		'invoke-virtual {p0, p1}, Landroid/os/Parcel;->readHashMap(Ljava/lang/ClassLoader;)Ljava/util/HashMap;\nmove-result-object v0\nif-nez v0, :copy\nconst/4 v0, 0\nreturn-object v0\n:copy\nnew-instance v1, Landroid/os/PersistableBundle;\ninvoke-direct {v1}, Landroid/os/PersistableBundle;-><init>()V\niget-object v2, v1, Landroid/os/BaseBundle;->mMap:Landroid/util/ArrayMap;\ninvoke-virtual {v2, v0}, Landroid/util/ArrayMap;->putAll(Ljava/util/Map;)V\nreturn-object v1')
	os.write_file(parcel_path, parcel)!
}
