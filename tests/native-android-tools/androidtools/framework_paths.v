// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_paths(smali string) ! {
 path := smali + '/android/graphics/Path.smali'
 mut text := os.read_file(path)!
 // Native WS transfers the builder into the immutable path. Keeping both
 // fields aliased makes a later mutation append a path to itself forever.
 text = framework_replace_method(text, 'getGskPath()J', '.method public getGskPath()J
.locals 4
iget-wide v0, p0, Landroid/graphics/Path;->path:J
const-wide/16 v2, 0
cmp-long v0, v0, v2
if-nez v0, :done
iget-wide v0, p0, Landroid/graphics/Path;->builder:J
invoke-static {v0, v1}, Landroid/graphics/Path;->native_create_path(J)J
move-result-wide v0
iput-wide v0, p0, Landroid/graphics/Path;->path:J
iput-wide v2, p0, Landroid/graphics/Path;->builder:J
:done
iget-wide v0, p0, Landroid/graphics/Path;->path:J
return-wide v0
.end method')!
 text = framework_replace_method(text, 'transform(Landroid/graphics/Matrix;Landroid/graphics/Path;)V', '.method public transform(Landroid/graphics/Matrix;Landroid/graphics/Path;)V
.locals 0
if-eqz p2, :in_place
if-eq p0, p2, :in_place
invoke-virtual {p2}, Landroid/graphics/Path;->reset()V
invoke-virtual {p2, p0, p1}, Landroid/graphics/Path;->addPath(Landroid/graphics/Path;Landroid/graphics/Matrix;)V
return-void
:in_place
invoke-virtual {p0, p1}, Landroid/graphics/Path;->transform(Landroid/graphics/Matrix;)V
return-void
.end method')!
 os.write_file(path, text)!
}
