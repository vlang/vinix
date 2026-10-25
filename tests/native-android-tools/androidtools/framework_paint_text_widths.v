// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Advances are indexed by UTF-16 code unit, independently of the pixel bounds
// used for glyph rasterization. String/CharSequence ranges use an exclusive
// end; char[] ranges use a count. The native overloads share measureText's font
// and decoder, and validate every range/capacity before writing any output.
fn framework_paint_text_widths(smali string) ! {
	path := smali + '/android/graphics/Paint.smali'
	mut text := os.read_file(path)!
	for signature in ['getTextWidths(Ljava/lang/String;II[F)I', 'getTextWidths([CII[F)I'] {
		text = framework_replace_method(text, signature,
			'.method public native ${signature}\n.end method')!
	}
	// AOSP's convenience overload obtains text.length() before delegation, so
	// null String throws NPE here; the explicit range overloads throw IAE.
	text = framework_replace_method(text, 'getTextWidths(Ljava/lang/String;[F)I',
		touch_method('public getTextWidths(Ljava/lang/String;[F)I', '
const/4 v0, 0
invoke-virtual {p1}, Ljava/lang/String;->length()I
move-result v1
invoke-virtual {p0, p1, v0, v1, p2}, Landroid/graphics/Paint;->getTextWidths(Ljava/lang/String;II[F)I
move-result v0
return v0'))!
	// Copy through CharSequence's content API rather than relying on toString()
	// to preserve its length and UTF-16 offsets. Range checks precede the copy.
	text = framework_replace_method(text, 'getTextWidths(Ljava/lang/CharSequence;II[F)I',
		touch_method('public getTextWidths(Ljava/lang/CharSequence;II[F)I', '
if-eqz p1, :null_text
if-ltz p2, :invalid_range
if-lt p3, p2, :invalid_range
invoke-interface {p1}, Ljava/lang/CharSequence;->length()I
move-result v0
if-gt p3, v0, :invalid_range
sub-int v1, p3, p2
array-length v0, p4
if-gt v1, v0, :short_widths
const/4 v2, 0
if-nez v1, :copy
return v2
:copy
new-array v3, v1, [C
invoke-static {p1, p2, p3, v3, v2}, Landroid/text/TextUtils;->getChars(Ljava/lang/CharSequence;II[CI)V
invoke-virtual {p0, v3, v2, v1, p4}, Landroid/graphics/Paint;->getTextWidths([CII[F)I
move-result v0
return v0
:null_text
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "text cannot be null"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:invalid_range
new-instance v0, Ljava/lang/IndexOutOfBoundsException;
invoke-direct {v0}, Ljava/lang/IndexOutOfBoundsException;-><init>()V
throw v0
:short_widths
new-instance v0, Ljava/lang/ArrayIndexOutOfBoundsException;
invoke-direct {v0}, Ljava/lang/ArrayIndexOutOfBoundsException;-><init>()V
throw v0'))!
	os.write_file(path, text)!
}
