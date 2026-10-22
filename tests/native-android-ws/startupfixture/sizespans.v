// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_size_span_probe(dir string) ! {
 mut body := '
new-instance v0, Landroid/text/TextPaint;
invoke-direct {v0}, Landroid/text/TextPaint;-><init>()V
const/high16 v1, 0x40200000
iput v1, v0, Landroid/text/TextPaint;->density:F
const/high16 v1, 0x41c00000
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->setTextSize(F)V
const-string v1, "WWW"
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v7
'
 for size, dip in {24: false, 19: true, 0: false, -7: true} {
  bit := if dip { 1 } else { 0 }
  body += '
new-instance v1, Landroid/text/style/AbsoluteSizeSpan;
const/16 v2, ${size}
const/4 v3, ${bit}
invoke-direct {v1, v2, v3}, Landroid/text/style/AbsoluteSizeSpan;-><init>(IZ)V
invoke-static {v1, v2, v3}, Lorg/vinix/bootstrap/SizeSpanProbe;->metadata(Landroid/text/style/AbsoluteSizeSpan;IZ)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v4
const/4 v5, 0
invoke-virtual {v1, v4, v5}, Landroid/text/style/AbsoluteSizeSpan;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v4, v5}, Landroid/os/Parcel;->setDataPosition(I)V
# Read independently to verify the platform wire layout.
invoke-virtual {v4}, Landroid/os/Parcel;->readInt()I
move-result v6
if-ne v6, v2, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->readInt()I
move-result v6
if-ne v6, v3, :bad
invoke-virtual {v4, v5}, Landroid/os/Parcel;->setDataPosition(I)V
new-instance v6, Landroid/text/style/AbsoluteSizeSpan;
invoke-direct {v6, v4}, Landroid/text/style/AbsoluteSizeSpan;-><init>(Landroid/os/Parcel;)V
invoke-static {v6, v2, v3}, Lorg/vinix/bootstrap/SizeSpanProbe;->metadata(Landroid/text/style/AbsoluteSizeSpan;IZ)V
invoke-virtual {v4}, Landroid/os/Parcel;->dataPosition()I
move-result v6
const/16 v5, 8
if-ne v6, v5, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->recycle()V
'
  if size <= 0 { continue }
  for name in ['updateMeasureState', 'updateDrawState'] {
   value := if dip { '0x423e0000' } else { '0x41c00000' } // 47.5 or 24 pixels
   body += '
const/high16 v5, 0x41000000
invoke-virtual {v0, v5}, Landroid/graphics/Paint;->setTextSize(F)V
invoke-virtual {v1, v0}, Landroid/text/style/AbsoluteSizeSpan;->${name}(Landroid/text/TextPaint;)V
invoke-virtual {v1, v0}, Landroid/text/style/AbsoluteSizeSpan;->${name}(Landroid/text/TextPaint;)V
invoke-virtual {v0}, Landroid/graphics/Paint;->getTextSize()F
move-result v5
const v6, ${value}
cmpl-float v6, v5, v6
if-nez v6, :bad
'
  }
  if dip {
   body += '
const-string v5, "WWW"
invoke-virtual {v0, v5}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v5
cmpl-float v5, v5, v7
if-lez v5, :bad
# Density is read at application time, rather than construction time.
const/high16 v5, 0x3f800000
iput v5, v0, Landroid/text/TextPaint;->density:F
invoke-virtual {v1, v0}, Landroid/text/style/MetricAffectingSpan;->updateMeasureState(Landroid/text/TextPaint;)V
invoke-virtual {v0}, Landroid/graphics/Paint;->getTextSize()F
move-result v5
const/high16 v6, 0x41980000
cmpl-float v6, v5, v6
if-nez v6, :bad
'
  }
 }
 body += '
# Single-argument constructor uses pixels. Parcel treats any nonzero dip as true.
new-instance v1, Landroid/text/style/AbsoluteSizeSpan;
const/16 v2, 37
const/4 v3, 0
invoke-direct {v1, v2}, Landroid/text/style/AbsoluteSizeSpan;-><init>(I)V
invoke-static {v1, v2, v3}, Lorg/vinix/bootstrap/SizeSpanProbe;->metadata(Landroid/text/style/AbsoluteSizeSpan;IZ)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v4
invoke-virtual {v4, v2}, Landroid/os/Parcel;->writeInt(I)V
const/4 v5, -3
invoke-virtual {v4, v5}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v4, v3}, Landroid/os/Parcel;->setDataPosition(I)V
new-instance v6, Landroid/text/style/AbsoluteSizeSpan;
invoke-direct {v6, v4}, Landroid/text/style/AbsoluteSizeSpan;-><init>(Landroid/os/Parcel;)V
const/4 v3, 1
invoke-static {v6, v2, v3}, Lorg/vinix/bootstrap/SizeSpanProbe;->metadata(Landroid/text/style/AbsoluteSizeSpan;IZ)V
invoke-virtual {v4}, Landroid/os/Parcel;->recycle()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-SIZE-SPANS-PASS metadata pixels density draw measure repeat dispatch parcel wire-layout"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "absolute size span state or paint/parcel behavior"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir + '/SizeSpanProbe.smali', '.class public Lorg/vinix/bootstrap/SizeSpanProbe;\n.super Ljava/lang/Object;\n' + method('public static check()V', body) + method('private static metadata(Landroid/text/style/AbsoluteSizeSpan;IZ)V', '
invoke-virtual {p0}, Landroid/text/style/AbsoluteSizeSpan;->getSize()I
move-result v0
if-ne v0, p1, :bad
invoke-virtual {p0}, Landroid/text/style/AbsoluteSizeSpan;->getDip()Z
move-result v0
if-ne v0, p2, :bad
instance-of v0, p0, Landroid/os/Parcelable;
if-eqz v0, :bad
instance-of v0, p0, Landroid/text/ParcelableSpan;
if-eqz v0, :bad
invoke-virtual {p0}, Landroid/text/style/AbsoluteSizeSpan;->getSpanTypeId()I
move-result v0
const/16 v1, 16
if-ne v0, v1, :bad
invoke-virtual {p0}, Landroid/text/style/AbsoluteSizeSpan;->describeContents()I
move-result v0
if-nez v0, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "absolute size span metadata"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
