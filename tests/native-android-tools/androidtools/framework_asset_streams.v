// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_asset_streams(smali string) ! {
 path := smali + '/android/content/res/AssetManager$AssetInputStream.smali'
 text := os.read_file(path)!
 // Bound against the remaining length before addition, so Long.MAX_VALUE
 // cannot overflow the target position. InputStream skips never go backwards.
 os.write_file(path, framework_replace_method(text, 'skip(J)J', '.method public final skip(J)J
.locals 11
const-wide/16 v4, 0
cmp-long v0, p1, v4
if-gtz v0, :positive
return-wide v4
:positive
iget-object v1, p0, Landroid/content/res/AssetManager$AssetInputStream;->this$0:Landroid/content/res/AssetManager;
iget-wide v2, p0, Landroid/content/res/AssetManager$AssetInputStream;->mAsset:J
const/4 v6, 0
invoke-static/range {v1 .. v6}, Landroid/content/res/AssetManager;->access$600(Landroid/content/res/AssetManager;JJI)J
move-result-wide v7
iget-wide v9, p0, Landroid/content/res/AssetManager$AssetInputStream;->mLength:J
sub-long/2addr v9, v7
cmp-long v0, p1, v9
if-lez v0, :bounded
move-wide p1, v9
:bounded
move-wide v4, p1
invoke-static/range {v1 .. v6}, Landroid/content/res/AssetManager;->access$600(Landroid/content/res/AssetManager;JJI)J
move-result-wide v9
sub-long/2addr v9, v7
return-wide v9
.end method')!)!
}
