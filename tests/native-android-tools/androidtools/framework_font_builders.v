// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// API 29's resource font path shares the native resource Typeface and its owned
// font data. Font/FontFamily are immutable snapshots; builders may be reused.
// Variable fonts, collections and multi-family glyph fallback are not supported
// by the current stb renderer and must not silently produce the wrong face.
fn framework_font_builders(smali string) ! {
	os.mkdir_all(smali + '/android/graphics/fonts')!
	style := 'Landroid/graphics/fonts/FontStyle;'
	font := 'Landroid/graphics/fonts/Font;'
	builder := 'Landroid/graphics/fonts/Font$Builder;'
	family := 'Landroid/graphics/fonts/FontFamily;'
	fb := 'Landroid/graphics/fonts/FontFamily$Builder;'
	cb := 'Landroid/graphics/Typeface$CustomFallbackBuilder;'
	face := 'Landroid/graphics/Typeface;'
	invalid := '
:invalid
new-instance v0, Ljava/lang/IllegalArgumentException;
invoke-direct {v0}, Ljava/lang/IllegalArgumentException;-><init>()V
throw v0'
	mut text := '.class public final ${style}\n.super Ljava/lang/Object;\n.field private weight:I\n.field private slant:I\n'
	text += touch_method('public constructor <init>()V', 'const/16 v0, 400\nconst/4 v1, 0\ninvoke-direct {p0, v0, v1}, ${style}-><init>(II)V\nreturn-void')
	text += touch_method('public constructor <init>(II)V', '
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
if-lez p1, :invalid
const/16 v0, 1000
if-gt p1, v0, :invalid
if-ltz p2, :invalid
const/4 v0, 1
if-gt p2, v0, :invalid
iput p1, p0, ${style}->weight:I
iput p2, p0, ${style}->slant:I
return-void' + invalid)
	for field, name in {'weight': 'Weight', 'slant': 'Slant'} {
		text += touch_method('public get${name}()I', 'iget v0, p0, ${style}->${field}:I\nreturn v0')
	}
	text += touch_method('public equals(Ljava/lang/Object;)Z', '
instance-of v0, p1, ${style}
if-eqz v0, :no
check-cast p1, ${style}
iget v0, p0, ${style}->weight:I
iget v1, p1, ${style}->weight:I
if-ne v0, v1, :no
iget v0, p0, ${style}->slant:I
iget v1, p1, ${style}->slant:I
if-ne v0, v1, :no
const/4 v0, 1
return v0
:no
const/4 v0, 0
return v0')
	text += touch_method('public hashCode()I', 'iget v0, p0, ${style}->weight:I\nmul-int/lit8 v0, v0, 31\niget v1, p0, ${style}->slant:I\nadd-int/2addr v0, v1\nreturn v0')
	os.write_file(smali + '/android/graphics/fonts/FontStyle.smali', text)!
	text = '.class public final ${font}\n.super Ljava/lang/Object;\n.field private face:${face}\n.field private style:${style}\n'
	text += touch_method('public constructor <init>(${face}${style})V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${font}->face:${face}\niput-object p2, p0, ${font}->style:${style}\nreturn-void')
	text += touch_method('public getStyle()${style}', 'iget-object v0, p0, ${font}->style:${style}\nreturn-object v0')
	text += touch_method('public vinixTypeface()${face}', 'iget-object v0, p0, ${font}->face:${face}\nreturn-object v0')
	text += touch_method('public getTtcIndex()I', 'const/4 v0, 0\nreturn v0')
	os.write_file(smali + '/android/graphics/fonts/Font.smali', text)!
	text = '.class public final ${builder}\n.super Ljava/lang/Object;\n.field private resources:Landroid/content/res/Resources;\n.field private id:I\n.field private weight:I\n.field private slant:I\n.field private index:I\n.field private variation:Ljava/lang/String;\n.field private failure:Ljava/io/IOException;\n'
	text += touch_method('public constructor <init>(Landroid/content/res/Resources;I)V', '
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
iput-object p1, p0, ${builder}->resources:Landroid/content/res/Resources;
iput p2, p0, ${builder}->id:I
const/4 v0, -1
iput v0, p0, ${builder}->weight:I
iput v0, p0, ${builder}->slant:I
new-instance v0, Landroid/util/TypedValue;
invoke-direct {v0}, Landroid/util/TypedValue;-><init>()V
const/4 v1, 1
invoke-virtual {p1, p2, v0, v1}, Landroid/content/res/Resources;->getValue(ILandroid/util/TypedValue;Z)V
iget-object v0, v0, Landroid/util/TypedValue;->string:Ljava/lang/CharSequence;
if-eqz v0, :missing
invoke-interface {v0}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;
move-result-object v0
sget-object v1, Ljava/util/Locale;->ROOT:Ljava/util/Locale;
invoke-virtual {v0, v1}, Ljava/lang/String;->toLowerCase(Ljava/util/Locale;)Ljava/lang/String;
move-result-object v0
const-string v1, ".xml"
invoke-virtual {v0, v1}, Ljava/lang/String;->endsWith(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :done
:missing
new-instance v0, Ljava/io/FileNotFoundException;
const-string v1, "Font.Builder requires a font file resource"
invoke-direct {v0, v1}, Ljava/io/FileNotFoundException;-><init>(Ljava/lang/String;)V
iput-object v0, p0, ${builder}->failure:Ljava/io/IOException;
:done
return-void')
	text += touch_method('public setWeight(I)${builder}', 'if-lez p1, :invalid\nconst/16 v0, 1000\nif-gt p1, v0, :invalid\niput p1, p0, ${builder}->weight:I\nreturn-object p0' + invalid)
	text += touch_method('public setSlant(I)${builder}', 'if-eqz p1, :set\nconst/4 p1, 1\n:set\niput p1, p0, ${builder}->slant:I\nreturn-object p0')
	text += touch_method('public setTtcIndex(I)${builder}', 'iput p1, p0, ${builder}->index:I\nreturn-object p0')
	text += touch_method('public setFontVariationSettings(Ljava/lang/String;)${builder}', 'iput-object p1, p0, ${builder}->variation:Ljava/lang/String;\nreturn-object p0')
	text += touch_method('public build()${font}', '
iget-object v0, p0, ${builder}->failure:Ljava/io/IOException;
if-eqz v0, :source
throw v0
:source
iget v0, p0, ${builder}->index:I
if-nez v0, :unsupported
iget-object v0, p0, ${builder}->variation:Ljava/lang/String;
if-eqz v0, :load
invoke-virtual {v0}, Ljava/lang/String;->isEmpty()Z
move-result v0
if-eqz v0, :unsupported
:load
iget-object v0, p0, ${builder}->resources:Landroid/content/res/Resources;
iget v1, p0, ${builder}->id:I
invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getFont(I)${face}
move-result-object v0
iget v1, p0, ${builder}->weight:I
if-gez v1, :weight
invoke-virtual {v0}, ${face}->getWeight()I
move-result v1
:weight
iget v2, p0, ${builder}->slant:I
if-gez v2, :slant
invoke-virtual {v0}, ${face}->isItalic()Z
move-result v2
:slant
new-instance v3, ${style}
invoke-direct {v3, v1, v2}, ${style}-><init>(II)V
invoke-static {v0, v1, v2}, ${face}->create(${face}IZ)${face}
move-result-object v0
new-instance v1, ${font}
invoke-direct {v1, v0, v3}, ${font}-><init>(${face}${style})V
return-object v1
:unsupported
new-instance v0, Ljava/lang/UnsupportedOperationException;
const-string v1, "native WS font collections and variations are unavailable"
invoke-direct {v0, v1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V
throw v0')
	os.write_file(smali + '/android/graphics/fonts/Font$Builder.smali', text)!
	text = '.class public final ${family}\n.super Ljava/lang/Object;\n.field private fonts:Ljava/util/ArrayList;\n'
	text += touch_method('public constructor <init>(Ljava/util/ArrayList;)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0, p1}, Ljava/util/ArrayList;-><init>(Ljava/util/Collection;)V\niput-object v0, p0, ${family}->fonts:Ljava/util/ArrayList;\nreturn-void')
	text += touch_method('public getSize()I', 'iget-object v0, p0, ${family}->fonts:Ljava/util/ArrayList;\ninvoke-virtual {v0}, Ljava/util/ArrayList;->size()I\nmove-result v0\nreturn v0')
	text += touch_method('public getFont(I)${font}', 'iget-object v0, p0, ${family}->fonts:Ljava/util/ArrayList;\ninvoke-virtual {v0, p1}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ${font}\nreturn-object v0')
	os.write_file(smali + '/android/graphics/fonts/FontFamily.smali', text)!
	text = '.class public final ${fb}\n.super Ljava/lang/Object;\n.field private fonts:Ljava/util/ArrayList;\n'
	text += touch_method('public constructor <init>(${font})V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\niput-object v0, p0, ${fb}->fonts:Ljava/util/ArrayList;\ninvoke-virtual {p0, p1}, ${fb}->addFont(${font})${fb}\nreturn-void')
	text += touch_method('public addFont(${font})${fb}', '
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-virtual {p1}, ${font}->getStyle()${style}
move-result-object v0
iget-object v1, p0, ${fb}->fonts:Ljava/util/ArrayList;
invoke-virtual {v1}, Ljava/util/ArrayList;->size()I
move-result v2
const/4 v3, 0
:loop
if-ge v3, v2, :add
invoke-virtual {v1, v3}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v4
check-cast v4, ${font}
invoke-virtual {v4}, ${font}->getStyle()${style}
move-result-object v4
invoke-virtual {v0, v4}, ${style}->equals(Ljava/lang/Object;)Z
move-result v4
if-nez v4, :invalid
add-int/lit8 v3, v3, 1
goto :loop
:add
invoke-virtual {v1, p1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
return-object p0' + invalid)
	text += touch_method('public build()${family}', 'iget-object v0, p0, ${fb}->fonts:Ljava/util/ArrayList;\nnew-instance v1, ${family}\ninvoke-direct {v1, v0}, ${family}-><init>(Ljava/util/ArrayList;)V\nreturn-object v1')
	os.write_file(smali + '/android/graphics/fonts/FontFamily$Builder.smali', text)!
	text = '.class public final ${cb}\n.super Ljava/lang/Object;\n.field private family:${family}\n.field private style:${style}\n'
	text += touch_method('public constructor <init>(${family})V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\niput-object p1, p0, ${cb}->family:${family}\nreturn-void')
	text += touch_method('public setStyle(${style})${cb}', 'iput-object p1, p0, ${cb}->style:${style}\nreturn-object p0')
	// Select the nearest member of the primary family using Android's weight
	// distance / 100 + slant penalty. First font wins ties.
	text += touch_method('public build()${face}', '
iget-object v0, p0, ${cb}->style:${style}
if-nez v0, :style
new-instance v0, ${style}
invoke-direct {v0}, ${style}-><init>()V
:style
invoke-virtual {v0}, ${style}->getWeight()I
move-result v1
invoke-virtual {v0}, ${style}->getSlant()I
move-result v2
iget-object v3, p0, ${cb}->family:${family}
invoke-virtual {v3}, ${family}->getSize()I
move-result v4
const/4 v5, 0
const/4 v6, 0
const v7, 0x7fffffff
:loop
invoke-virtual {v3, v5}, ${family}->getFont(I)${font}
move-result-object v8
invoke-virtual {v8}, ${font}->getStyle()${style}
move-result-object v9
invoke-virtual {v9}, ${style}->getWeight()I
move-result v10
sub-int/2addr v10, v1
invoke-static {v10}, Ljava/lang/Math;->abs(I)I
move-result v10
div-int/lit8 v10, v10, 100
invoke-virtual {v9}, ${style}->getSlant()I
move-result v9
if-eq v9, v2, :score
add-int/lit8 v10, v10, 2
:score
if-ge v10, v7, :next
move v7, v10
move-object v6, v8
:next
add-int/lit8 v5, v5, 1
if-lt v5, v4, :loop
invoke-virtual {v6}, ${font}->vinixTypeface()${face}
move-result-object v0
invoke-static {v0, v1, v2}, ${face}->create(${face}IZ)${face}
move-result-object v0
return-object v0')
	os.write_file(smali + '/android/graphics/Typeface$CustomFallbackBuilder.smali', text.replace('.locals 10', '.locals 11'))!
}
