// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

// Keep the operand objects in the native argument list so ART roots their
// handles until the operation finishes. Only replace the receiver on success.
fn framework_path_ops(source string) !string {
	mut text := framework_replace_method(source, 'native_op(Landroid/graphics/Path;Landroid/graphics/Path;JIJII)J', '.method private static native native_op(Landroid/graphics/Path;Landroid/graphics/Path;JIJII)J\n.end method')!
	text = framework_replace_method(text, 'native_is_empty(Landroid/graphics/Path;J)Z', '.method private static native native_is_empty(Landroid/graphics/Path;J)Z\n.end method')!
	// A successful operation can return a nonzero handle with no geometry.
	// Query both existing handles without creating a path or consuming a builder.
	text = framework_replace_method(text, 'isEmpty()Z', '.method public isEmpty()Z
.locals 3
iget-wide v0, p0, Landroid/graphics/Path;->path:J
invoke-static {p0, v0, v1}, Landroid/graphics/Path;->native_is_empty(Landroid/graphics/Path;J)Z
move-result v2
if-eqz v2, :done
iget-wide v0, p0, Landroid/graphics/Path;->builder:J
invoke-static {p0, v0, v1}, Landroid/graphics/Path;->native_is_empty(Landroid/graphics/Path;J)Z
move-result v2
:done
return v2
.end method')!
	text = framework_replace_method(text, 'op(Landroid/graphics/Path;Landroid/graphics/Path$Op;)Z', '.method public op(Landroid/graphics/Path;Landroid/graphics/Path$Op;)Z
.locals 1
invoke-virtual {p0, p0, p1, p2}, Landroid/graphics/Path;->op(Landroid/graphics/Path;Landroid/graphics/Path;Landroid/graphics/Path$Op;)Z
move-result v0
return v0
.end method')!
	return framework_replace_method(text, 'op(Landroid/graphics/Path;Landroid/graphics/Path;Landroid/graphics/Path$Op;)Z', '.method public op(Landroid/graphics/Path;Landroid/graphics/Path;Landroid/graphics/Path$Op;)Z
.locals 12
invoke-virtual {p3}, Ljava/lang/Enum;->ordinal()I
move-result v8
invoke-virtual {p1}, Landroid/graphics/Path;->getFillType()Landroid/graphics/Path$FillType;
move-result-object v11
invoke-virtual {v11}, Ljava/lang/Enum;->ordinal()I
move-result v4
invoke-virtual {p2}, Landroid/graphics/Path;->getFillType()Landroid/graphics/Path$FillType;
move-result-object v11
invoke-virtual {v11}, Ljava/lang/Enum;->ordinal()I
move-result v7
move-object v0, p1
move-object v1, p2
invoke-virtual {p1}, Landroid/graphics/Path;->getGskPath()J
move-result-wide v2
invoke-virtual {p2}, Landroid/graphics/Path;->getGskPath()J
move-result-wide v5
invoke-static/range {v0 .. v8}, Landroid/graphics/Path;->native_op(Landroid/graphics/Path;Landroid/graphics/Path;JIJII)J
move-result-wide v9
const-wide/16 v2, 0
cmp-long v0, v9, v2
if-eqz v0, :failed
# The finite result uses parity contours. Its fill outside all contours is
# the Boolean operation applied to the operands inverse-fill flags.
shr-int/lit8 v0, v4, 1
shr-int/lit8 v1, v7, 1
if-eqz v8, :difference
const/4 v2, 1
if-eq v8, v2, :intersect
const/4 v2, 2
if-eq v8, v2, :union
const/4 v2, 3
if-eq v8, v2, :xor
xor-int/lit8 v0, v0, 1
and-int/2addr v0, v1
goto :fill
:difference
xor-int/lit8 v1, v1, 1
and-int/2addr v0, v1
goto :fill
:intersect
and-int/2addr v0, v1
goto :fill
:union
or-int/2addr v0, v1
goto :fill
:xor
xor-int/2addr v0, v1
:fill
sget-object v11, Landroid/graphics/Path$FillType;->EVEN_ODD:Landroid/graphics/Path$FillType;
if-eqz v0, :install
sget-object v11, Landroid/graphics/Path$FillType;->INVERSE_EVEN_ODD:Landroid/graphics/Path$FillType;
:install
invoke-virtual {p0}, Landroid/graphics/Path;->reset()V
iput-wide v9, p0, Landroid/graphics/Path;->path:J
iput-object v11, p0, Landroid/graphics/Path;->fillType:Landroid/graphics/Path$FillType;
const/4 v0, 1
return v0
:failed
const/4 v0, 0
return v0
.end method')!
}
