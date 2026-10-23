// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_font_builders_probe(dir string) ! {
 probe := 'Lorg/vinix/bootstrap/FontBuildersProbe;'
 font := 'Landroid/graphics/fonts/Font;'
 style := 'Landroid/graphics/fonts/FontStyle;'
 builder := 'Landroid/graphics/fonts/Font$Builder;'
 family := 'Landroid/graphics/fonts/FontFamily;'
 fb := 'Landroid/graphics/fonts/FontFamily$Builder;'
 cb := 'Landroid/graphics/Typeface$CustomFallbackBuilder;'
 face := 'Landroid/graphics/Typeface;'
 bad := '
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "resource font builders, immutable family or rendered selection"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n'
 text += method('private static resource(Landroid/content/Context;Ljava/lang/String;)I', '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
const-string v1, "font"
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v2
invoke-virtual {v0, p1, v1, v2}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v0
return v0')
 text += method('private static load(Landroid/content/Context;Ljava/lang/String;)${font}', '
invoke-static {p0, p1}, ${probe}->resource(Landroid/content/Context;Ljava/lang/String;)I
move-result v0
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v1
new-instance v2, ${builder}
invoke-direct {v2, v1, v0}, ${builder}-><init>(Landroid/content/res/Resources;I)V
invoke-virtual {v2}, ${builder}->build()${font}
move-result-object v0
return-object v0')
 text += method('private static style(${font}II)V', '
invoke-virtual {p0}, ${font}->getStyle()${style}
move-result-object v0
invoke-virtual {v0}, ${style}->getWeight()I
move-result v1
if-ne v1, p1, :bad
invoke-virtual {v0}, ${style}->getSlant()I
move-result v1
if-ne v1, p2, :bad
new-instance v1, ${style}
invoke-direct {v1, p1, p2}, ${style}-><init>(II)V
invoke-virtual {v0, v1}, ${style}->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v0}, ${style}->hashCode()I
move-result v2
invoke-virtual {v1}, ${style}->hashCode()I
move-result v1
if-ne v1, v2, :bad
return-void' + bad)
 text += method('private static pixels(${face})[I', '
const/16 v0, 128
const/16 v1, 64
sget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v0
new-instance v1, Landroid/graphics/Canvas;
invoke-direct {v1, v0}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
new-instance v5, Landroid/graphics/Paint;
invoke-direct {v5}, Landroid/graphics/Paint;-><init>()V
invoke-virtual {v5, p0}, Landroid/graphics/Paint;->setTypeface(${face})${face}
const/high16 v2, 0x42000000
invoke-virtual {v5, v2}, Landroid/graphics/Paint;->setTextSize(F)V
const-string v2, "Wim"
const/high16 v3, 0x40800000
const/high16 v4, 0x42200000
invoke-virtual {v1, v2, v3, v4, v5}, Landroid/graphics/Canvas;->drawText(Ljava/lang/String;FFLandroid/graphics/Paint;)V
move-object v8, v1
move-object v9, v0
const/16 v1, 8192
new-array v1, v1, [I
const/4 v2, 0
const/16 v3, 128
const/4 v4, 0
const/4 v5, 0
const/16 v6, 128
const/16 v7, 64
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
const/4 v3, 0
invoke-virtual {v8, v3}, Landroid/graphics/Canvas;->setBitmap(Landroid/graphics/Bitmap;)V
invoke-virtual {v9}, Landroid/graphics/Bitmap;->recycle()V
return-object v1')
 text += method('private static selection(${family}II${font})V', '
new-instance v0, ${cb}
invoke-direct {v0, p0}, ${cb}-><init>(${family})V
new-instance v1, ${style}
invoke-direct {v1, p1, p2}, ${style}-><init>(II)V
invoke-virtual {v0, v1}, ${cb}->setStyle(${style})${cb}
invoke-virtual {v0}, ${cb}->build()${face}
move-result-object v0
invoke-virtual {v0}, ${face}->getWeight()I
move-result v1
if-ne v1, p1, :bad
invoke-virtual {v0}, ${face}->isItalic()Z
move-result v1
if-ne v1, p2, :bad
invoke-static {v0}, ${probe}->pixels(${face})[I
move-result-object v0
invoke-virtual {p3}, ${font}->vinixTypeface()${face}
move-result-object v1
invoke-static {v1}, ${probe}->pixels(${face})[I
move-result-object v1
invoke-static {v0, v1}, Ljava/util/Arrays;->equals([I[I)Z
move-result v0
if-eqz v0, :bad
return-void' + bad)
 text += method('public static check(Landroid/content/Context;)V', '
const-string v0, "fixture_font"
invoke-static {p0, v0}, ${probe}->load(Landroid/content/Context;Ljava/lang/String;)${font}
move-result-object v1
const-string v0, "fixture_bold"
invoke-static {p0, v0}, ${probe}->load(Landroid/content/Context;Ljava/lang/String;)${font}
move-result-object v2
const-string v0, "fixture_italic"
invoke-static {p0, v0}, ${probe}->load(Landroid/content/Context;Ljava/lang/String;)${font}
move-result-object v3
const/16 v7, 400
const/4 v8, 0
invoke-static {v1, v7, v8}, ${probe}->style(${font}II)V
const/16 v7, 700
invoke-static {v2, v7, v8}, ${probe}->style(${font}II)V
const/16 v7, 400
const/4 v8, 1
invoke-static {v3, v7, v8}, ${probe}->style(${font}II)V
new-instance v4, ${fb}
invoke-direct {v4, v1}, ${fb}-><init>(${font})V
invoke-virtual {v4}, ${fb}->build()${family}
move-result-object v5
invoke-virtual {v4, v2}, ${fb}->addFont(${font})${fb}
invoke-virtual {v4, v3}, ${fb}->addFont(${font})${fb}
invoke-virtual {v4}, ${fb}->build()${family}
move-result-object v6
invoke-virtual {v5}, ${family}->getSize()I
move-result v0
const/4 v7, 1
if-ne v0, v7, :bad
invoke-virtual {v6}, ${family}->getSize()I
move-result v0
const/4 v7, 3
if-ne v0, v7, :bad
const/4 v0, 1
invoke-virtual {v6, v0}, ${family}->getFont(I)${font}
move-result-object v0
if-ne v0, v2, :bad
:duplicate_start
invoke-virtual {v4, v1}, ${fb}->addFont(${font})${fb}
:duplicate_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:duplicate_start .. :duplicate_end} :duplicate_ok
:duplicate_ok
move-exception v0
const/16 v7, 400
const/4 v8, 0
invoke-static {v6, v7, v8, v1}, ${probe}->selection(${family}II${font})V
const/16 v7, 700
invoke-static {v6, v7, v8, v2}, ${probe}->selection(${family}II${font})V
const/16 v7, 400
const/4 v8, 1
invoke-static {v6, v7, v8, v3}, ${probe}->selection(${family}II${font})V
# A singleton bold family keeps its real pixels with default style 400/0.
new-instance v4, ${fb}
invoke-direct {v4, v2}, ${fb}-><init>(${font})V
invoke-virtual {v4}, ${fb}->build()${family}
move-result-object v4
new-instance v5, ${cb}
invoke-direct {v5, v4}, ${cb}-><init>(${family})V
invoke-virtual {v5}, ${cb}->build()${face}
move-result-object v5
invoke-virtual {v5}, ${face}->getWeight()I
move-result v0
const/16 v7, 400
if-ne v0, v7, :bad
invoke-static {v5}, ${probe}->pixels(${face})[I
move-result-object v5
invoke-virtual {v2}, ${font}->vinixTypeface()${face}
move-result-object v0
invoke-static {v0}, ${probe}->pixels(${face})[I
move-result-object v0
invoke-static {v0, v5}, Ljava/util/Arrays;->equals([I[I)Z
move-result v0
if-eqz v0, :bad
# Different source fonts really have different rasterized pixels.
invoke-virtual {v1}, ${font}->vinixTypeface()${face}
move-result-object v0
invoke-static {v0}, ${probe}->pixels(${face})[I
move-result-object v0
invoke-static {v0, v5}, Ljava/util/Arrays;->equals([I[I)Z
move-result v0
if-nez v0, :bad
invoke-static {p0}, ${probe}->errors(Landroid/content/Context;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-FONT-BUILDERS-PASS resource weight slant immutable reuse duplicate selection all-pixels xml range unsupported"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void' + bad)
 mut errors := '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v9
const-string v0, "fixture_font"
invoke-static {p0, v0}, ${probe}->resource(Landroid/content/Context;Ljava/lang/String;)I
move-result v8
new-instance v7, ${builder}
invoke-direct {v7, v9, v8}, ${builder}-><init>(Landroid/content/res/Resources;I)V
invoke-virtual {v7}, ${builder}->build()${font}
move-result-object v6
const/16 v0, 650
invoke-virtual {v7, v0}, ${builder}->setWeight(I)${builder}
const/4 v0, -1
invoke-virtual {v7, v0}, ${builder}->setSlant(I)${builder}
invoke-virtual {v7}, ${builder}->build()${font}
move-result-object v5
const/16 v0, 650
const/4 v1, 1
invoke-static {v5, v0, v1}, ${probe}->style(${font}II)V
const/16 v0, 400
const/4 v1, 0
invoke-static {v6, v0, v1}, ${probe}->style(${font}II)V'
 cases := [
  ['const/4 v0, 0\ninvoke-virtual {v7, v0}, ${builder}->setWeight(I)${builder}', 'Ljava/lang/IllegalArgumentException;'],
  ['new-instance v0, ${style}\nconst/16 v1, 1001\nconst/4 v2, 0\ninvoke-direct {v0, v1, v2}, ${style}-><init>(II)V', 'Ljava/lang/IllegalArgumentException;'],
  ['new-instance v0, ${style}\nconst/16 v1, 400\nconst/4 v2, 2\ninvoke-direct {v0, v1, v2}, ${style}-><init>(II)V', 'Ljava/lang/IllegalArgumentException;'],
  ['new-instance v0, ${fb}\nconst/4 v1, 0\ninvoke-direct {v0, v1}, ${fb}-><init>(${font})V', 'Ljava/lang/NullPointerException;'],
  ['const-string v0, "fixture_family"\ninvoke-static {p0, v0}, ${probe}->resource(Landroid/content/Context;Ljava/lang/String;)I\nmove-result v0\nnew-instance v1, ${builder}\ninvoke-direct {v1, v9, v0}, ${builder}-><init>(Landroid/content/res/Resources;I)V\ninvoke-virtual {v1}, ${builder}->build()${font}', 'Ljava/io/IOException;'],
  ['const/4 v0, 1\ninvoke-virtual {v7, v0}, ${builder}->setTtcIndex(I)${builder}\ninvoke-virtual {v7}, ${builder}->build()${font}', 'Ljava/lang/UnsupportedOperationException;'],
  ['const/4 v0, 0\ninvoke-virtual {v7, v0}, ${builder}->setTtcIndex(I)${builder}\nconst-string v0, "\'wght\' 650"\ninvoke-virtual {v7, v0}, ${builder}->setFontVariationSettings(Ljava/lang/String;)${builder}\ninvoke-virtual {v7}, ${builder}->build()${font}', 'Ljava/lang/UnsupportedOperationException;'],
 ]
 for i, c in cases {
  errors += '\n:case${i}\n${c[0]}\n:end${i}\ngoto :bad\n.catch ${c[1]} {:case${i} .. :end${i}} :caught${i}\n:caught${i}\nmove-exception v0\n'
 }
 text += method('private static errors(Landroid/content/Context;)V', errors + '\nreturn-void' + bad)
 os.write_file(dir + '/FontBuildersProbe.smali', text)!
}
