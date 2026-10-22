// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_typefaces(smali string) ! {
 path := smali + '/android/graphics/Typeface.smali'
 // Metadata is immutable after construction. Resolve the native font lazily:
 // class initialization also runs while JNI bindings are being registered.
 mut text := os.read_file(path)! + '
.field private vinixFamily:Ljava/lang/String;
.field private vinixSource:Landroid/graphics/Typeface;
.field private vinixWeight:I
.field private vinixSlant:I
.method public synchronized native vinixResolve()J
.end method
'
 for signature, body in {
  '<init>()V': 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nconst/16 v0, 400\niput v0, p0, Landroid/graphics/Typeface;->vinixWeight:I\nreturn-void'
  '<clinit>()V': '
const-string v0, "sans-serif"
const/4 v1, 0
invoke-static {v0, v1}, Landroid/graphics/Typeface;->create(Ljava/lang/String;I)Landroid/graphics/Typeface;
move-result-object v2
sput-object v2, Landroid/graphics/Typeface;->DEFAULT:Landroid/graphics/Typeface;
sput-object v2, Landroid/graphics/Typeface;->SANS_SERIF:Landroid/graphics/Typeface;
const/4 v1, 1
invoke-static {v0, v1}, Landroid/graphics/Typeface;->create(Ljava/lang/String;I)Landroid/graphics/Typeface;
move-result-object v2
sput-object v2, Landroid/graphics/Typeface;->DEFAULT_BOLD:Landroid/graphics/Typeface;
const/4 v1, 0
const-string v0, "serif"
invoke-static {v0, v1}, Landroid/graphics/Typeface;->create(Ljava/lang/String;I)Landroid/graphics/Typeface;
move-result-object v2
sput-object v2, Landroid/graphics/Typeface;->SERIF:Landroid/graphics/Typeface;
const-string v0, "monospace"
invoke-static {v0, v1}, Landroid/graphics/Typeface;->create(Ljava/lang/String;I)Landroid/graphics/Typeface;
move-result-object v2
sput-object v2, Landroid/graphics/Typeface;->MONOSPACE:Landroid/graphics/Typeface;
return-void'
  'create(Ljava/lang/String;I)Landroid/graphics/Typeface;': '
new-instance v0, Landroid/graphics/Typeface;
invoke-direct {v0}, Landroid/graphics/Typeface;-><init>()V
iput-object p0, v0, Landroid/graphics/Typeface;->vinixFamily:Ljava/lang/String;
if-ltz p1, :done
const/4 v1, 3
if-gt p1, v1, :done
and-int/lit8 v1, p1, 1
if-eqz v1, :slant
const/16 v1, 700
iput v1, v0, Landroid/graphics/Typeface;->vinixWeight:I
:slant
and-int/lit8 v1, p1, 2
ushr-int/lit8 v1, v1, 1
iput v1, v0, Landroid/graphics/Typeface;->vinixSlant:I
:done
return-object v0'
  'create(Landroid/graphics/Typeface;I)Landroid/graphics/Typeface;': '
if-ltz p1, :normal
const/4 v0, 3
if-le p1, v0, :style
:normal
const/4 p1, 0
:style
const/16 v0, 400
and-int/lit8 v1, p1, 1
if-eqz v1, :slant
const/16 v0, 700
:slant
and-int/lit8 v1, p1, 2
ushr-int/lit8 v1, v1, 1
invoke-static {p0, v0, v1}, Landroid/graphics/Typeface;->create(Landroid/graphics/Typeface;IZ)Landroid/graphics/Typeface;
move-result-object v0
return-object v0'
  'create(Landroid/graphics/Typeface;IZ)Landroid/graphics/Typeface;': '
# Match AOSP API 35, whose runtime range check also accepts zero.
if-ltz p1, :invalid
const/16 v0, 1000
if-gt p1, v0, :invalid
if-nez p0, :base
sget-object p0, Landroid/graphics/Typeface;->DEFAULT:Landroid/graphics/Typeface;
:base
new-instance v0, Landroid/graphics/Typeface;
invoke-direct {v0}, Landroid/graphics/Typeface;-><init>()V
iget-object v1, p0, Landroid/graphics/Typeface;->vinixFamily:Ljava/lang/String;
iput-object v1, v0, Landroid/graphics/Typeface;->vinixFamily:Ljava/lang/String;
iput-object p0, v0, Landroid/graphics/Typeface;->vinixSource:Landroid/graphics/Typeface;
iput p1, v0, Landroid/graphics/Typeface;->vinixWeight:I
iput p2, v0, Landroid/graphics/Typeface;->vinixSlant:I
return-object v0
:invalid
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "weight must be in [0, 1000]"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0'
  'getWeight()I': 'iget v0, p0, Landroid/graphics/Typeface;->vinixWeight:I\nreturn v0'
  'getStyle()I': '
iget v0, p0, Landroid/graphics/Typeface;->vinixSlant:I
shl-int/lit8 v0, v0, 1
iget v1, p0, Landroid/graphics/Typeface;->vinixWeight:I
const/16 v2, 600
if-lt v1, v2, :done
or-int/lit8 v0, v0, 1
:done
return v0'
  'isBold()Z': 'invoke-virtual {p0}, Landroid/graphics/Typeface;->getStyle()I\nmove-result v0\nand-int/lit8 v0, v0, 1\nreturn v0'
  'isItalic()Z': 'iget v0, p0, Landroid/graphics/Typeface;->vinixSlant:I\nreturn v0'
 } {
  declaration := if signature == '<clinit>()V' { 'static constructor ' } else if signature == '<init>()V' { 'public constructor ' } else if signature.starts_with('create(') { 'public static ' } else { 'public ' }
  text = framework_replace_method(text, signature, touch_method(declaration + signature, body))!
 }
 os.write_file(path, text)!
}
