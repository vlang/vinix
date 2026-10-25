// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

pub fn install_superscript_span_probe(dir string) ! {
 c := 'Lorg/vinix/bootstrap/SuperscriptSpanProbe;'
 span := 'Landroid/text/style/SuperscriptSpan;'
 paint := 'Landroid/text/TextPaint;'
 fake := 'Lorg/vinix/bootstrap/SuperscriptPaint;'
 mut override := '.class public ${fake}\n.super ${paint}\n.field public value:F\n.field public calls:I\n.field public overwrite:I\n'
 override += method('public constructor <init>()V', 'invoke-direct {p0}, ${paint}-><init>()V\nreturn-void')
 override += method('public ascent()F', 'iget v0, p0, ${fake}->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${fake}->calls:I\niget v0, p0, ${fake}->overwrite:I\nif-eqz v0, :value\niput v0, p0, ${paint}->baselineShift:I\n:value\niget v0, p0, ${fake}->value:F\nreturn v0')
 os.write_file(dir + '/SuperscriptPaint.smali', override)!
 mut text := '.class public ${c}\n.super Ljava/lang/Object;\n'
 text += method('private static fail()V', 'new-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "SuperscriptSpan metadata, range, baseline or parcel contract"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0')
 text += method('private static baseline(${paint}I)V', 'iget v0, p0, ${paint}->baselineShift:I\nif-eq v0, p1, :done\ninvoke-static {}, ${c}->fail()V\n:done\nreturn-void')
 text += method('private static unchanged(${paint})V', '
invoke-virtual {p0}, Landroid/graphics/Paint;->getTextSize()F
move-result v0
const/high16 v1, 0x41c00000
cmpl-float v0, v0, v1
if-nez v0, :bad
invoke-virtual {p0}, Landroid/graphics/Paint;->getColor()I
move-result v0
const v1, 0xff123456
if-ne v0, v1, :bad
iget v0, p0, ${paint}->density:F
const/high16 v1, 0x40200000
cmpl-float v0, v0, v1
if-nez v0, :bad
return-void
:bad
invoke-static {}, ${c}->fail()V
return-void')
 text += method('private static metadata(${span})V', '
instance-of v0, p0, Landroid/text/style/MetricAffectingSpan;
if-eqz v0, :bad
instance-of v0, p0, Landroid/text/style/UpdateLayout;
if-eqz v0, :bad
instance-of v0, p0, Landroid/text/ParcelableSpan;
if-eqz v0, :bad
instance-of v0, p0, Landroid/os/Parcelable;
if-eqz v0, :bad
invoke-virtual {p0}, ${span}->getSpanTypeId()I
move-result v0
const/16 v1, 14
if-ne v0, v1, :bad
invoke-virtual {p0}, ${span}->getSpanTypeIdInternal()I
move-result v0
if-ne v0, v1, :bad
invoke-virtual {p0}, ${span}->describeContents()I
move-result v0
if-nez v0, :bad
invoke-virtual {p0}, Landroid/text/style/MetricAffectingSpan;->getUnderlying()Landroid/text/style/MetricAffectingSpan;
move-result-object v0
if-ne v0, p0, :bad
invoke-virtual {p0}, ${span}->toString()Ljava/lang/String;
move-result-object v0
const-string v1, "SuperscriptSpan{}"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
# Match the actual Maps static initialization and the copied span range.
new-instance v0, Landroid/text/SpannableStringBuilder;
invoke-direct {v0}, Landroid/text/SpannableStringBuilder;-><init>()V
const-string v1, "*"
invoke-virtual {v0, v1}, Landroid/text/SpannableStringBuilder;->append(Ljava/lang/CharSequence;)Landroid/text/SpannableStringBuilder;
const/4 v1, 0
const/4 v2, 1
const/16 v3, 0x21
invoke-virtual {v0, p0, v1, v2, v3}, Landroid/text/SpannableStringBuilder;->setSpan(Ljava/lang/Object;III)V
new-instance v4, Landroid/text/SpannableString;
invoke-direct {v4, v0}, Landroid/text/SpannableString;-><init>(Ljava/lang/CharSequence;)V
invoke-virtual {v4, p0}, Landroid/text/SpannableString;->getSpanStart(Ljava/lang/Object;)I
move-result v0
if-nez v0, :bad
invoke-virtual {v4, p0}, Landroid/text/SpannableString;->getSpanEnd(Ljava/lang/Object;)I
move-result v0
if-ne v0, v2, :bad
invoke-virtual {v4, p0}, Landroid/text/SpannableString;->getSpanFlags(Ljava/lang/Object;)I
move-result v0
if-ne v0, v3, :bad
return-void
:bad
invoke-static {}, ${c}->fail()V
return-void')
 mut paint_test := '
new-instance v0, ${fake}
invoke-direct {v0}, ${fake}-><init>()V
const/4 v1, 5
iput v1, v0, ${paint}->baselineShift:I
const/high16 v1, 0x41c00000
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->setTextSize(F)V
const v1, 0xff123456
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->setColor(I)V
const/high16 v1, 0x40200000
iput v1, v0, ${paint}->density:F
const/high16 v1, 0xc1580000
iput v1, v0, ${fake}->value:F
invoke-virtual {p0, v0}, Landroid/text/style/MetricAffectingSpan;->updateDrawState(${paint})V
const/4 v1, -1
invoke-static {v0, v1}, ${c}->baseline(${paint}I)V
invoke-virtual {p0, v0}, Landroid/text/style/MetricAffectingSpan;->updateMeasureState(${paint})V
const/4 v1, -7
invoke-static {v0, v1}, ${c}->baseline(${paint}I)V
invoke-static {p0}, Landroid/text/style/CharacterStyle;->wrap(Landroid/text/style/CharacterStyle;)Landroid/text/style/CharacterStyle;
move-result-object v2
instance-of v1, v2, Landroid/text/style/MetricAffectingSpan;
if-eqz v1, :bad
invoke-virtual {v2}, Landroid/text/style/CharacterStyle;->getUnderlying()Landroid/text/style/CharacterStyle;
move-result-object v1
if-ne v1, p0, :bad
invoke-virtual {v2, v0}, Landroid/text/style/CharacterStyle;->updateDrawState(${paint})V
const/16 v1, -13
invoke-static {v0, v1}, ${c}->baseline(${paint}I)V
const/high16 v1, 0x41580000
iput v1, v0, ${fake}->value:F
invoke-virtual {p0, v0}, ${span}->updateMeasureState(${paint})V
const/4 v1, -7
invoke-static {v0, v1}, ${c}->baseline(${paint}I)V
const/high16 v1, 0xbfc00000
iput v1, v0, ${fake}->value:F
invoke-virtual {p0, v0}, ${span}->updateDrawState(${paint})V
const/4 v1, -7
invoke-static {v0, v1}, ${c}->baseline(${paint}I)V
const/4 v1, 0
iput v1, v0, ${fake}->value:F
invoke-virtual {p0, v0}, ${span}->updateMeasureState(${paint})V
const/4 v1, -7
invoke-static {v0, v1}, ${c}->baseline(${paint}I)V
invoke-static {v0}, ${c}->unchanged(${paint})V
# Compound assignment saves the old baseline before the virtual ascent call.
const/4 v1, 5
iput v1, v0, ${paint}->baselineShift:I
const/16 v1, 100
iput v1, v0, ${fake}->overwrite:I
const/high16 v1, 0xc1580000
iput v1, v0, ${fake}->value:F
invoke-virtual {p0, v0}, ${span}->updateDrawState(${paint})V
const/4 v1, -1
invoke-static {v0, v1}, ${c}->baseline(${paint}I)V
iget v1, v0, ${fake}->calls:I
const/4 v2, 7
if-ne v1, v2, :bad
# Existing native ascent must also supply a real negative font metric.
new-instance v0, ${paint}
invoke-direct {v0}, ${paint}-><init>()V
const/high16 v1, 0x41c00000
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->setTextSize(F)V
invoke-virtual {v0}, Landroid/graphics/Paint;->ascent()F
move-result v1
const/4 v2, 0
cmpg-float v2, v1, v2
if-gez v2, :bad
const/high16 v2, 0x40000000
div-float/2addr v1, v2
float-to-int v1, v1
if-gez v1, :bad
const/16 v2, 19
iput v2, v0, ${paint}->baselineShift:I
invoke-virtual {p0, v0}, ${span}->updateDrawState(${paint})V
add-int/lit8 v2, v1, 19
invoke-static {v0, v2}, ${c}->baseline(${paint}I)V
invoke-virtual {p0, v0}, ${span}->updateMeasureState(${paint})V
add-int/2addr v2, v1
invoke-static {v0, v2}, ${c}->baseline(${paint}I)V
'
 for name in ['updateDrawState', 'updateMeasureState'] {
  paint_test += ':${name}_start\nconst/4 v0, 0\ninvoke-virtual {p0, v0}, ${span}->${name}(${paint})V\n:${name}_end\ngoto :bad\n.catch Ljava/lang/NullPointerException; {:${name}_start .. :${name}_end} :${name}_caught\n:${name}_caught\nmove-exception v0\n'
 }
 paint_test += 'return-void\n:bad\ninvoke-static {}, ${c}->fail()V\nreturn-void'
 text += method('private static paint(${span})V', paint_test)
 mut parcel := ''
 for writer in ['writeToParcel', 'writeToParcelInternal'] {
  parcel += '
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
const v1, 0x12345678
invoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v0}, Landroid/os/Parcel;->dataPosition()I
move-result v2
const/4 v3, 0
invoke-virtual {p0, v0, v3}, ${span}->${writer}(Landroid/os/Parcel;I)V
invoke-virtual {v0}, Landroid/os/Parcel;->dataPosition()I
move-result v4
if-ne v4, v2, :bad
invoke-virtual {v0, v3}, Landroid/os/Parcel;->setDataPosition(I)V
new-instance v4, ${span}
invoke-direct {v4, v0}, ${span}-><init>(Landroid/os/Parcel;)V
invoke-virtual {v0}, Landroid/os/Parcel;->dataPosition()I
move-result v5
if-nez v5, :bad
invoke-static {v4}, ${c}->metadata(${span})V
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v4
if-ne v4, v1, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->dataPosition()I
move-result v4
if-ne v4, v2, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
'
 }
 parcel += '
# The empty payload constructor and writer do not dereference a null Parcel.
const/4 v0, 0
new-instance v1, ${span}
invoke-direct {v1, v0}, ${span}-><init>(Landroid/os/Parcel;)V
invoke-static {v1}, ${c}->metadata(${span})V
invoke-virtual {v1, v0, v0}, ${span}->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v1, v0, v0}, ${span}->writeToParcelInternal(Landroid/os/Parcel;I)V
return-void
:bad
invoke-static {}, ${c}->fail()V
return-void'
 text += method('private static parcel(${span})V', parcel)
 mut check := 'new-instance v0, ${span}\ninvoke-direct {v0}, ${span}-><init>()V\n'
 for part in ['metadata', 'paint', 'parcel'] {
  check += 'invoke-static {v0}, ${c}->${part}(${span})V\nsget-object v1, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v2, "SUPERSCRIPT-SPAN-${part.to_upper()}-PASS"\ninvoke-virtual {v1, v2}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
 }
 check += 'const-string v2, "SUPERSCRIPT-SPAN-PASS"\ninvoke-virtual {v1, v2}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
 text += method('public static check()V', check)
 os.write_file(dir + '/SuperscriptSpanProbe.smali', text)!
}
