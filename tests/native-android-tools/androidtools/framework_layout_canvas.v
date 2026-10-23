// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Custom canvases include Picture/RenderNode recorders. Dispatch through their
// virtual drawText method so drawing is recorded with its Paint snapshot and
// replayed using the destination canvas's transform, clip and bitmap target.
// This uses the existing WS layout's line metrics; it does not add shaping,
// styled runs, paragraph alignment or selection/highlight rendering.
fn framework_layout_canvas(smali string) ! {
 path := smali + '/android/text/Layout.smali'
 text := os.read_file(path)!
 replacement := touch_method('protected native_draw_custom_canvas(JLandroid/graphics/Canvas;Landroid/graphics/Paint;)V', '
invoke-virtual {p0}, Landroid/text/Layout;->getText()Ljava/lang/CharSequence;
move-result-object v0
if-eqz v0, :done
invoke-interface {v0}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;
move-result-object v0
invoke-virtual {p0}, Landroid/text/Layout;->getLineCount()I
move-result v1
const/4 v2, 0
:line
if-ge v2, v1, :done
invoke-virtual {p0, v2}, Landroid/text/Layout;->getLineStart(I)I
move-result v3
invoke-virtual {p0, v2}, Landroid/text/Layout;->getLineEnd(I)I
move-result v4
:trim
if-le v4, v3, :next
add-int/lit8 v7, v4, -1
invoke-virtual {v0, v7}, Ljava/lang/String;->charAt(I)C
move-result v8
const/16 v9, 10
if-eq v8, v9, :newline
const/16 v9, 13
if-ne v8, v9, :draw
:newline
move v4, v7
goto :trim
:draw
invoke-virtual {v0, v3, v4}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v4
invoke-virtual {p0, v2}, Landroid/text/Layout;->getLineLeft(I)F
move-result v5
invoke-virtual {p0, v2}, Landroid/text/Layout;->getLineBaseline(I)I
move-result v6
int-to-float v6, v6
invoke-virtual {p3, v4, v5, v6, p4}, Landroid/graphics/Canvas;->drawText(Ljava/lang/String;FFLandroid/graphics/Paint;)V
:next
add-int/lit8 v2, v2, 1
goto :line
:done
return-void')
 os.write_file(path, framework_replace_method(text, 'native_draw_custom_canvas(JLandroid/graphics/Canvas;Landroid/graphics/Paint;)V', replacement)!)!
}
