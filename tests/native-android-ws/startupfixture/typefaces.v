// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_typeface_probe(dir string) ! {
 os.write_file(dir + '/TypefaceProbe.smali', '.class public Lorg/vinix/bootstrap/TypefaceProbe;\n.super Ljava/lang/Object;\n.field private static phase:Ljava/lang/String;\n' +
 method('private static pixels(Landroid/graphics/Typeface;)I', '
const/16 v0, 128
const/16 v1, 64
sget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v0
new-instance v1, Landroid/graphics/Canvas;
invoke-direct {v1, v0}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
new-instance v5, Landroid/graphics/Paint;
invoke-direct {v5}, Landroid/graphics/Paint;-><init>()V
invoke-virtual {v5, p0}, Landroid/graphics/Paint;->setTypeface(Landroid/graphics/Typeface;)Landroid/graphics/Typeface;
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
const/4 v2, 0
const/4 v3, 0
const/16 v4, 8192
:pixel
aget v5, v1, v3
ushr-int/lit8 v6, v5, 24
xor-int/2addr v5, v6
mul-int/lit8 v2, v2, 31
add-int/2addr v2, v5
add-int/lit8 v3, v3, 1
if-lt v3, v4, :pixel
const/4 v3, 0
invoke-virtual {v8, v3}, Landroid/graphics/Canvas;->setBitmap(Landroid/graphics/Bitmap;)V
invoke-virtual {v9}, Landroid/graphics/Bitmap;->recycle()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TYPEFACE-PIXELS "
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->print(Ljava/lang/String;)V
invoke-virtual {v0, v2}, Ljava/io/PrintStream;->println(I)V
return v2') +
 method('public static check(Landroid/content/Context;)V', '
const-string v9, "default and style pixels"
sput-object v9, Lorg/vinix/bootstrap/TypefaceProbe;->phase:Ljava/lang/String;
sget-object v0, Landroid/graphics/Typeface;->DEFAULT:Landroid/graphics/Typeface;
invoke-virtual {v0}, Landroid/graphics/Typeface;->getWeight()I
move-result v1
const/16 v2, 400
if-ne v1, v2, :bad
invoke-virtual {v0}, Landroid/graphics/Typeface;->getStyle()I
move-result v1
if-nez v1, :bad
invoke-static {v0}, Lorg/vinix/bootstrap/TypefaceProbe;->pixels(Landroid/graphics/Typeface;)I
move-result v6
const/16 v1, 700
const/4 v2, 1
invoke-static {v0, v1, v2}, Landroid/graphics/Typeface;->create(Landroid/graphics/Typeface;IZ)Landroid/graphics/Typeface;
move-result-object v3
invoke-virtual {v3}, Landroid/graphics/Typeface;->getWeight()I
move-result v4
if-ne v1, v4, :bad
invoke-virtual {v3}, Landroid/graphics/Typeface;->getStyle()I
move-result v4
const/4 v5, 3
if-ne v4, v5, :bad
invoke-virtual {v3}, Landroid/graphics/Typeface;->isItalic()Z
move-result v4
if-eqz v4, :bad
invoke-virtual {v3}, Landroid/graphics/Typeface;->isBold()Z
move-result v4
if-eqz v4, :bad
invoke-static {v3}, Lorg/vinix/bootstrap/TypefaceProbe;->pixels(Landroid/graphics/Typeface;)I
move-result v7
if-eq v6, v7, :bad
const/4 v2, 0
invoke-static {v0, v1, v2}, Landroid/graphics/Typeface;->create(Landroid/graphics/Typeface;IZ)Landroid/graphics/Typeface;
move-result-object v3
invoke-static {v3}, Lorg/vinix/bootstrap/TypefaceProbe;->pixels(Landroid/graphics/Typeface;)I
move-result v8
if-eq v6, v8, :bad
if-eq v7, v8, :bad
const/16 v1, 400
const/4 v2, 1
invoke-static {v0, v1, v2}, Landroid/graphics/Typeface;->create(Landroid/graphics/Typeface;IZ)Landroid/graphics/Typeface;
move-result-object v3
invoke-static {v3}, Lorg/vinix/bootstrap/TypefaceProbe;->pixels(Landroid/graphics/Typeface;)I
move-result v9
if-eq v6, v9, :bad
if-eq v7, v9, :bad
if-eq v8, v9, :bad
# Unknown families fall back to the installed default.
const-string v9, "Unknown families"
sput-object v9, Lorg/vinix/bootstrap/TypefaceProbe;->phase:Ljava/lang/String;
const-string v1, "absent-font-family"
const/4 v2, 0
invoke-static {v1, v2}, Landroid/graphics/Typeface;->create(Ljava/lang/String;I)Landroid/graphics/Typeface;
move-result-object v3
invoke-static {v3}, Lorg/vinix/bootstrap/TypefaceProbe;->pixels(Landroid/graphics/Typeface;)I
move-result v4
if-ne v6, v4, :bad
# Mono has equal advances, serif uses another real font.
const-string v9, "Mono has equal"
sput-object v9, Lorg/vinix/bootstrap/TypefaceProbe;->phase:Ljava/lang/String;
new-instance v4, Landroid/graphics/Paint;
invoke-direct {v4}, Landroid/graphics/Paint;-><init>()V
sget-object v3, Landroid/graphics/Typeface;->MONOSPACE:Landroid/graphics/Typeface;
invoke-virtual {v4, v3}, Landroid/graphics/Paint;->setTypeface(Landroid/graphics/Typeface;)Landroid/graphics/Typeface;
const-string v1, "I"
invoke-virtual {v4, v1}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v5
const-string v1, "W"
invoke-virtual {v4, v1}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v6
cmpl-float v1, v5, v6
if-nez v1, :bad
invoke-static {v3}, Lorg/vinix/bootstrap/TypefaceProbe;->pixels(Landroid/graphics/Typeface;)I
move-result v7
sget-object v3, Landroid/graphics/Typeface;->SERIF:Landroid/graphics/Typeface;
invoke-static {v3}, Lorg/vinix/bootstrap/TypefaceProbe;->pixels(Landroid/graphics/Typeface;)I
move-result v8
if-eq v7, v8, :bad
invoke-virtual {v4}, Landroid/graphics/Paint;->reset()V
const-string v1, "I"
invoke-virtual {v4, v1}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v5
const-string v1, "W"
invoke-virtual {v4, v1}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v6
cmpl-float v1, v5, v6
if-eqz v1, :bad
# Weight range: API 35 accepts zero as well as documented 1..1000.
const-string v9, "Weight range:"
sput-object v9, Lorg/vinix/bootstrap/TypefaceProbe;->phase:Ljava/lang/String;
const/4 v0, 0
const/4 v1, 0
const/4 v2, 0
invoke-static {v0, v1, v2}, Landroid/graphics/Typeface;->create(Landroid/graphics/Typeface;IZ)Landroid/graphics/Typeface;
move-result-object v3
invoke-virtual {v3}, Landroid/graphics/Typeface;->getWeight()I
move-result v4
if-nez v4, :bad
const/16 v1, 1000
invoke-static {v0, v1, v2}, Landroid/graphics/Typeface;->create(Landroid/graphics/Typeface;IZ)Landroid/graphics/Typeface;
move-result-object v3
invoke-virtual {v3}, Landroid/graphics/Typeface;->getWeight()I
move-result v4
if-ne v1, v4, :bad
const/4 v1, -1
:low_start
invoke-static {v0, v1, v2}, Landroid/graphics/Typeface;->create(Landroid/graphics/Typeface;IZ)Landroid/graphics/Typeface;
:low_end
.catch Ljava/lang/IllegalArgumentException; {:low_start .. :low_end} :low_ok
goto :bad
:low_ok
move-exception v3
const/16 v1, 1001
:high_start
invoke-static {v0, v1, v2}, Landroid/graphics/Typeface;->create(Landroid/graphics/Typeface;IZ)Landroid/graphics/Typeface;
:high_end
.catch Ljava/lang/IllegalArgumentException; {:high_start .. :high_end} :high_ok
goto :bad
:high_ok
move-exception v3
# Derivation keeps the only custom font in this resource family alive.
const-string v9, "Derivation keeps"
sput-object v9, Lorg/vinix/bootstrap/TypefaceProbe;->phase:Ljava/lang/String;
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
const-string v1, "fixture_font"
const-string v2, "font"
const-string v3, "org.vinix.bootstrap"
invoke-virtual {v0, v1, v2, v3}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getFont(I)Landroid/graphics/Typeface;
move-result-object v0
invoke-static {v0}, Lorg/vinix/bootstrap/TypefaceProbe;->pixels(Landroid/graphics/Typeface;)I
move-result v6
const/16 v1, 500
const/4 v2, 0
invoke-static {v0, v1, v2}, Landroid/graphics/Typeface;->create(Landroid/graphics/Typeface;IZ)Landroid/graphics/Typeface;
move-result-object v3
invoke-static {v3}, Lorg/vinix/bootstrap/TypefaceProbe;->pixels(Landroid/graphics/Typeface;)I
move-result v7
if-ne v6, v7, :bad
iget-wide v4, v0, Landroid/graphics/Typeface;->native_instance:J
iget-wide v6, v3, Landroid/graphics/Typeface;->native_instance:J
cmp-long v2, v4, v6
if-nez v2, :bad
invoke-virtual {v0}, Landroid/graphics/Typeface;->getWeight()I
move-result v2
const/16 v4, 400
if-ne v2, v4, :bad
invoke-virtual {v3}, Landroid/graphics/Typeface;->getWeight()I
move-result v2
if-ne v2, v1, :bad
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const/4 v1, 3
invoke-virtual {v0, v3, v1}, Landroid/widget/TextView;->setTypeface(Landroid/graphics/Typeface;I)V
invoke-virtual {v0}, Landroid/widget/TextView;->getTypeface()Landroid/graphics/Typeface;
move-result-object v3
invoke-virtual {v3}, Landroid/graphics/Typeface;->getStyle()I
move-result v2
if-ne v1, v2, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TYPEFACES-PASS weight-range null-family styles family-metrics rendered-pixels fallback resource-retention textview"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
sget-object v1, Lorg/vinix/bootstrap/TypefaceProbe;->phase:Ljava/lang/String;
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
