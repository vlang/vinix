// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// A value codec for the runtime's modeled Intent fields. The field order follows
// AOSP android15-release Intent.writeToParcel; Parcel's existing String encoding
// means this is not an Android-native byte interoperability claim. Uri is written
// as StringUri (type 1), ComponentName inline, and Rect using its existing codec.
// ClipData, extended flags, content-user overrides and original intents are not
// modeled; reject them rather than silently losing authentication request data.
const intent_parcel_fields = ['action:Ljava/lang/String;',
	'component:Landroid/content/ComponentName;', 'data:Landroid/net/Uri;',
	'extras:Landroid/os/Bundle;', 'flags:I', 'packageName:Ljava/lang/String;',
	'selector:Landroid/content/Intent;', 'type:Ljava/lang/String;',
	'vinixCategories:Ljava/util/HashSet;', 'vinixIdentifier:Ljava/lang/String;',
	'vinixClipData:Landroid/content/ClipData;', 'vinixSourceBounds:Landroid/graphics/Rect;']

fn intent_parcel_method(signature string, locals int, body string) string {
	return '\n.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

pub fn framework_intent_parcel_source(source string) !string {
	if source.count('.class public Landroid/content/Intent;\n') != 1
		|| source.count('.super Ljava/lang/Object;\n') != 1
		|| source.count('.implements Landroid/os/Parcelable;\n') != 1 {
		return error('expected Parcelable Intent class')
	}
	mut seen := map[string]bool{}
	for raw in source.split_into_lines() {
		line := raw.trim_space()
		if !line.starts_with('.field ') || line.contains(' static ') { continue }
		field := line.all_after_last(' ')
		if field !in intent_parcel_fields || field in seen {
			return error('unmodeled or duplicate Intent instance field: ' + field)
		}
		seen[field] = true
	}
	if seen.len != intent_parcel_fields.len { return error('missing modeled Intent fields') }
	if source.contains(' CREATOR:') || source.contains(' <clinit>()V\n') {
		return error('Intent creator or initializer already exists')
	}
	for signature in ['<init>(Landroid/os/Parcel;)V', 'describeContents()I',
		'writeToParcel(Landroid/os/Parcel;I)V', 'readFromParcel(Landroid/os/Parcel;)V',
		'vinixReadFromParcel(Landroid/os/Parcel;)V'] {
		if source.contains(' ' + signature + '\n') {
			return error('Intent parcel method already exists: ' + signature)
		}
	}
	cls := 'Landroid/content/Intent;'
	creator := 'Landroid/content/VinixIntentCreator;'
	mut out := source + '\n.field public static final CREATOR:Landroid/os/Parcelable\$Creator;\n'
	out += intent_parcel_method('static constructor <clinit>()V', 1,
		'new-instance v0, ${creator}\ninvoke-direct {v0}, ${creator}-><init>()V\n' +
		'sput-object v0, ${cls}->CREATOR:Landroid/os/Parcelable\$Creator;\nreturn-void')
	out += intent_parcel_method('protected constructor <init>(Landroid/os/Parcel;)V', 0,
		'invoke-direct {p0}, ${cls}-><init>()V\ninvoke-direct {p0, p1}, ${cls}->vinixReadFromParcel(Landroid/os/Parcel;)V\nreturn-void')
	out += intent_parcel_method('public describeContents()I', 1,
		'iget-object v0, p0, ${cls}->extras:Landroid/os/Bundle;\nif-eqz v0, :empty\n' +
		'invoke-virtual {v0}, Landroid/os/Bundle;->describeContents()I\nmove-result v0\nreturn v0\n:empty\nconst/4 v0, 0x0\nreturn v0')
	mut write := 'iget-object v0, p0, ${cls}->vinixClipData:Landroid/content/ClipData;\nif-eqz v0, :supported\n' +
		'new-instance v0, Ljava/lang/UnsupportedOperationException;\nconst-string v1, "Intent ClipData parceling is unsupported"\n' +
		'invoke-direct {v0, v1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V\nthrow v0\n:supported\n'
	write += 'iget-object v0, p0, ${cls}->action:Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n' +
		'iget-object v0, p0, ${cls}->data:Landroid/net/Uri;\nif-eqz v0, :null_uri\nconst/4 v1, 0x1\n' +
		'invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V\ninvoke-virtual {v0}, Landroid/net/Uri;->toString()Ljava/lang/String;\nmove-result-object v0\n' +
		'invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\ngoto :uri_done\n:null_uri\nconst/4 v0, 0x0\n' +
		'invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\n:uri_done\n'
	for field in ['type', 'vinixIdentifier'] {
		write += 'iget-object v0, p0, ${cls}->${field}:Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n'
	}
	write += 'iget v0, p0, ${cls}->flags:I\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\n' +
		'const/4 v0, 0x0\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\n' +
		'iget-object v0, p0, ${cls}->packageName:Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n' +
		'iget-object v0, p0, ${cls}->component:Landroid/content/ComponentName;\nif-eqz v0, :null_component\n' +
		'invoke-virtual {v0}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;\nmove-result-object v1\n' +
		'invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n' +
		'invoke-virtual {v0}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;\nmove-result-object v1\n' +
		'invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\ngoto :component_done\n:null_component\nconst/4 v0, 0x0\n' +
		'invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n:component_done\n' +
		'iget-object v0, p0, ${cls}->vinixSourceBounds:Landroid/graphics/Rect;\nif-eqz v0, :null_bounds\nconst/4 v1, 0x1\n' +
		'invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V\ninvoke-virtual {v0, p1, p2}, Landroid/graphics/Rect;->writeToParcel(Landroid/os/Parcel;I)V\ngoto :bounds_done\n' +
		':null_bounds\nconst/4 v0, 0x0\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\n:bounds_done\n' +
		'iget-object v0, p0, ${cls}->vinixCategories:Ljava/util/HashSet;\nif-eqz v0, :null_categories\n' +
		'invoke-virtual {v0}, Ljava/util/HashSet;->size()I\nmove-result v1\ninvoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V\n' +
		'invoke-virtual {v0}, Ljava/util/HashSet;->iterator()Ljava/util/Iterator;\nmove-result-object v0\n:categories_loop\n' +
		'invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z\nmove-result v1\nif-eqz v1, :categories_done\n' +
		'invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;\nmove-result-object v1\ncheck-cast v1, Ljava/lang/String;\n' +
		'invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\ngoto :categories_loop\n:null_categories\nconst/4 v0, 0x0\n' +
		'invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\n:categories_done\n' +
		'iget-object v0, p0, ${cls}->selector:${cls}\nif-eqz v0, :null_selector\nconst/4 v1, 0x1\n' +
		'invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V\ninvoke-virtual {v0, p1, p2}, ${cls}->writeToParcel(Landroid/os/Parcel;I)V\ngoto :selector_done\n' +
		':null_selector\nconst/4 v0, 0x0\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\n:selector_done\n' +
		'const/4 v0, 0x0\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\n' +
		'const/4 v0, -0x2\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\n' +
		'iget-object v0, p0, ${cls}->extras:Landroid/os/Bundle;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeBundle(Landroid/os/Bundle;)V\n' +
		'const/4 v0, 0x0\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\nreturn-void'
	out += intent_parcel_method('public writeToParcel(Landroid/os/Parcel;I)V', 2, write)
	mut read := 'invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\niput-object v0, p0, ${cls}->action:Ljava/lang/String;\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-eqz v0, :uri_done\nconst/4 v1, 0x1\nif-ne v0, v1, :unsupported\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\nif-eqz v0, :malformed\n' +
		'invoke-static {v0}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;\nmove-result-object v0\niput-object v0, p0, ${cls}->data:Landroid/net/Uri;\n:uri_done\n'
	for field in ['type', 'vinixIdentifier'] {
		read += 'invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\niput-object v0, p0, ${cls}->${field}:Ljava/lang/String;\n'
	}
	read += 'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\niput v0, p0, ${cls}->flags:I\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-nez v0, :unsupported\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\niput-object v0, p0, ${cls}->packageName:Ljava/lang/String;\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\nif-eqz v0, :component_done\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v1\nif-eqz v1, :malformed\n' +
		'new-instance v2, Landroid/content/ComponentName;\ninvoke-direct {v2, v0, v1}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V\n' +
		'iput-object v2, p0, ${cls}->component:Landroid/content/ComponentName;\n:component_done\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-eqz v0, :bounds_done\nconst/4 v1, 0x1\nif-ne v0, v1, :malformed\n' +
		'sget-object v0, Landroid/graphics/Rect;->CREATOR:Landroid/os/Parcelable\$Creator;\ninvoke-interface {v0, p1}, Landroid/os/Parcelable\$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\nmove-result-object v0\n' +
		'check-cast v0, Landroid/graphics/Rect;\niput-object v0, p0, ${cls}->vinixSourceBounds:Landroid/graphics/Rect;\n:bounds_done\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-ltz v0, :malformed\nif-eqz v0, :categories_done\n' +
		'new-instance v1, Ljava/util/HashSet;\ninvoke-direct {v1}, Ljava/util/HashSet;-><init>()V\niput-object v1, p0, ${cls}->vinixCategories:Ljava/util/HashSet;\n' +
		':categories_loop\ninvoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v2\nif-eqz v2, :malformed\n' +
		'invoke-virtual {v1, v2}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z\nmove-result v2\nif-eqz v2, :malformed\nadd-int/lit8 v0, v0, -0x1\nif-nez v0, :categories_loop\n:categories_done\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-eqz v0, :selector_done\nconst/4 v1, 0x1\nif-ne v0, v1, :malformed\n' +
		'new-instance v0, ${cls}\ninvoke-direct {v0, p1}, ${cls}-><init>(Landroid/os/Parcel;)V\niput-object v0, p0, ${cls}->selector:${cls}\n:selector_done\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-nez v0, :unsupported\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nconst/4 v1, -0x2\nif-ne v0, v1, :unsupported\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readBundle()Landroid/os/Bundle;\nmove-result-object v0\niput-object v0, p0, ${cls}->extras:Landroid/os/Bundle;\n' +
		'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-nez v0, :unsupported\nreturn-void\n' +
		':unsupported\nnew-instance v0, Landroid/os/BadParcelableException;\nconst-string v1, "Unsupported Intent parcel state"\n' +
		'invoke-direct {v0, v1}, Landroid/os/BadParcelableException;-><init>(Ljava/lang/String;)V\nthrow v0\n' +
		':malformed\nnew-instance v0, Landroid/os/BadParcelableException;\nconst-string v1, "Malformed Intent parcel state"\n' +
		'invoke-direct {v0, v1}, Landroid/os/BadParcelableException;-><init>(Ljava/lang/String;)V\nthrow v0'
	out += intent_parcel_method('private vinixReadFromParcel(Landroid/os/Parcel;)V', 3, read)
	mut replace := 'new-instance v0, ${cls}\ninvoke-direct {v0, p1}, ${cls}-><init>(Landroid/os/Parcel;)V\n'
	for field in intent_parcel_fields {
		op := if field.ends_with(':I') { '' } else { '-object' }
		replace += 'iget${op} v1, v0, ${cls}->${field}\niput${op} v1, p0, ${cls}->${field}\n'
	}
	out += intent_parcel_method('public readFromParcel(Landroid/os/Parcel;)V', 2, replace + 'return-void')
	return out
}

pub fn framework_intent_parcel_creator_source() string {
	cls := 'Landroid/content/Intent;'
	creator := 'Landroid/content/VinixIntentCreator;'
	return '.class public final ${creator}\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable\$Creator;\n' +
		intent_parcel_method('public constructor <init>()V', 0, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		intent_parcel_method('public createFromParcel(Landroid/os/Parcel;)${cls}', 1,
			'new-instance v0, ${cls}\ninvoke-direct {v0, p1}, ${cls}-><init>(Landroid/os/Parcel;)V\nreturn-object v0') +
		intent_parcel_method('public bridge synthetic createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 1,
			'invoke-virtual {p0, p1}, ${creator}->createFromParcel(Landroid/os/Parcel;)${cls}\nmove-result-object v0\nreturn-object v0') +
		intent_parcel_method('public newArray(I)[${cls}', 1, 'new-array v0, p1, [${cls}\nreturn-object v0') +
		intent_parcel_method('public bridge synthetic newArray(I)[Ljava/lang/Object;', 1,
			'invoke-virtual {p0, p1}, ${creator}->newArray(I)[${cls}\nmove-result-object v0\nreturn-object v0')
}

fn framework_intent_parcel(smali string) ! {
	path := smali + '/android/content/Intent.smali'
	creator := smali + '/android/content/VinixIntentCreator.smali'
	if os.exists(creator) { return error('Intent creator already exists') }
	source := framework_intent_parcel_source(os.read_file(path)!)!
	os.write_file(path, source)!
	os.write_file(creator, framework_intent_parcel_creator_source())!
}
