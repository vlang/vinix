// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_asset_cookies(smali string) ! {
	path := smali + '/android/content/res/AssetManager.smali'
	mut text := os.read_file(path)!
	old := 'addAssetPath(Ljava/lang/String;)V'
	if text.count('.method public final ' + old) != 1 {
		return error('AssetManager.addAssetPath declaration changed')
	}
	text = framework_replace_method(text, old, '.method public final addAssetPath(Ljava/lang/String;)I
.locals 4
monitor-enter p0
:try_start
iget-boolean v0, p0, Landroid/content/res/AssetManager;->mOpen:Z
if-nez v0, :open
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "AssetManager has been closed"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
:open
iget-object v0, p0, Landroid/content/res/AssetManager;->vinixCookiePaths:[Ljava/lang/Object;
if-eqz v0, :new_path
invoke-static {v0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
move-result-object v0
invoke-interface {v0, p1}, Ljava/util/List;->indexOf(Ljava/lang/Object;)I
move-result v3
if-ltz v3, :new_path
add-int/lit8 v3, v3, 1
goto :done
:new_path
new-instance v0, Ljava/util/ArrayList;
iget-object v1, p0, Landroid/content/res/AssetManager;->asset_paths:Ljava/util/ArrayList;
invoke-direct {v0, v1}, Ljava/util/ArrayList;-><init>(Ljava/util/Collection;)V
invoke-virtual {v0, p1}, Ljava/util/ArrayList;->indexOf(Ljava/lang/Object;)I
move-result v1
if-gez v1, :load
invoke-virtual {v0}, Ljava/util/ArrayList;->size()I
move-result v1
invoke-virtual {v0, p1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
:load
invoke-virtual {v0}, Ljava/util/ArrayList;->toArray()[Ljava/lang/Object;
move-result-object v2
invoke-direct {p0, v2, v1}, Landroid/content/res/AssetManager;->vinixSetAssetPaths([Ljava/lang/Object;I)I
move-result v3
if-eqz v3, :done
iput-object v0, p0, Landroid/content/res/AssetManager;->asset_paths:Ljava/util/ArrayList;
:done
monitor-exit p0
:try_end
return v3
:failed
move-exception v0
monitor-exit p0
throw v0
.catchall {:try_start .. :try_end} :failed
.end method')!
	text += '\n.field private vinixCookiePaths:[Ljava/lang/Object;\n' +
		'.method private native vinixSetAssetPaths([Ljava/lang/Object;I)I\n.end method\n'
	// The resource C ABI searches all APKs. Read explicitly selected XML from
	// its own archive, so an earlier cookie never opens a later APK manifest.
	text += '.method private vinixReadXmlAsset(ILjava/lang/String;)[B
.locals 8
iget-object v0, p0, Landroid/content/res/AssetManager;->vinixCookiePaths:[Ljava/lang/Object;
if-eqz v0, :missing
array-length v1, v0
if-le p1, v1, :index
goto :missing
:index
add-int/lit8 v1, p1, -1
if-ltz v1, :missing
aget-object v0, v0, v1
if-eqz v0, :missing
check-cast v0, Ljava/lang/String;
new-instance v1, Ljava/io/File;
invoke-direct {v1, v0}, Ljava/io/File;-><init>(Ljava/lang/String;)V
const/4 v2, 0
invoke-virtual {v1}, Ljava/io/File;->isDirectory()Z
move-result v3
if-eqz v3, :archive
new-instance v0, Ljava/io/File;
invoke-direct {v0, v1, p2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v1, Ljava/io/FileInputStream;
invoke-direct {v1, v0}, Ljava/io/FileInputStream;-><init>(Ljava/io/File;)V
goto :read
:archive
new-instance v2, Ljava/util/zip/ZipFile;
invoke-direct {v2, v0}, Ljava/util/zip/ZipFile;-><init>(Ljava/lang/String;)V
:zip_start
invoke-virtual {v2, p2}, Ljava/util/zip/ZipFile;->getEntry(Ljava/lang/String;)Ljava/util/zip/ZipEntry;
move-result-object v0
if-nez v0, :entry
new-instance v0, Ljava/io/FileNotFoundException;
invoke-direct {v0, p2}, Ljava/io/FileNotFoundException;-><init>(Ljava/lang/String;)V
throw v0
:entry
invoke-virtual {v2, v0}, Ljava/util/zip/ZipFile;->getInputStream(Ljava/util/zip/ZipEntry;)Ljava/io/InputStream;
move-result-object v1
:zip_end
:read
:read_start
new-instance v3, Ljava/io/ByteArrayOutputStream;
invoke-direct {v3}, Ljava/io/ByteArrayOutputStream;-><init>()V
const/16 v4, 8192
new-array v4, v4, [B
const/4 v5, 0
:loop
invoke-virtual {v1, v4}, Ljava/io/InputStream;->read([B)I
move-result v6
if-ltz v6, :copied
invoke-virtual {v3, v4, v5, v6}, Ljava/io/ByteArrayOutputStream;->write([BII)V
goto :loop
:copied
invoke-virtual {v3}, Ljava/io/ByteArrayOutputStream;->toByteArray()[B
move-result-object v7
:read_end
:stream_close_start
invoke-virtual {v1}, Ljava/io/InputStream;->close()V
:stream_close_end
if-eqz v2, :return
invoke-virtual {v2}, Ljava/util/zip/ZipFile;->close()V
:return
return-object v7
:read_failed
move-exception v0
:close_start
invoke-virtual {v1}, Ljava/io/InputStream;->close()V
:close_end
goto :close_zip
:close_failed
move-exception v3
goto :close_zip
:zip_failed
move-exception v0
:close_zip
if-eqz v2, :throw
:zip_close_start
invoke-virtual {v2}, Ljava/util/zip/ZipFile;->close()V
:zip_close_end
goto :throw
:zip_close_failed
move-exception v3
:throw
throw v0
:missing
new-instance v0, Ljava/io/FileNotFoundException;
invoke-direct {v0, p2}, Ljava/io/FileNotFoundException;-><init>(Ljava/lang/String;)V
throw v0
.catchall {:zip_start .. :zip_end} :zip_failed
.catchall {:read_start .. :read_end} :read_failed
.catchall {:stream_close_start .. :stream_close_end} :zip_failed
.catchall {:close_start .. :close_end} :close_failed
.catchall {:zip_close_start .. :zip_close_end} :zip_close_failed
.end method\n'
	os.write_file(path, text)!
	for name in ['android/content/pm/PackageParser', 'android/app/Instrumentation'] {
		caller := smali + '/' + name + '.smali'
		mut source := os.read_file(caller)!
		if source.count('->' + old) != 1 { return error('asset path caller changed: ' + name) }
		source = source.replace('->' + old, '->addAssetPath(Ljava/lang/String;)I')
		if name.ends_with('/PackageParser') {
			// The manifest belongs to this APK, not the first framework asset.
			source = source.replace('->addAssetPath(Ljava/lang/String;)I',
				'->addAssetPath(Ljava/lang/String;)I\n    move-result v24')
		}
		os.write_file(caller, source)!
	}
	// ATL loads foreground and companion APKs through this separate parser.
	// Cookie 1 belongs to framework-res, not the APK passed to loadFromPath.
	loader := smali + '/android/atl/ATLLoadedApp.smali'
	mut source := os.read_file(loader)!
	anchor := '    :try_start_26\n    const-string v6, "AndroidManifest.xml"'
	if source.count(anchor) != 1 { return error('ATL manifest loader changed') }
	source = source.replace(anchor, '    :try_start_26\n' +
		'    invoke-virtual {v1, p0}, Landroid/content/res/AssetManager;->addAssetPath(Ljava/lang/String;)I\n' +
		'    move-result v5\n\n    const-string v6, "AndroidManifest.xml"')
	os.write_file(loader, source)!
}
