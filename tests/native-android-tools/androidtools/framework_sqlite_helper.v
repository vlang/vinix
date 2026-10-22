// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Preserve the existing helper's migrations, callbacks and read-only fallback.
// Both disk-open paths must configure the pool before its first connection opens.
fn framework_sqlite_helper(smali string) ! {
	path := smali + '/android/database/sqlite/SQLiteOpenHelper.smali'
	helper := 'Landroid/database/sqlite/SQLiteOpenHelper;'
	db := 'Landroid/database/sqlite/SQLiteDatabase;'
	factory := 'Landroid/database/sqlite/SQLiteDatabase$CursorFactory;'
	handler := 'Landroid/database/DatabaseErrorHandler;'
	params := 'Landroid/database/sqlite/SQLiteDatabase$OpenParams;'
	builder := 'Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;'
	mut source := os.read_file(path)!
	anchor := '    invoke-direct {p0}, Ljava/lang/Object;-><init>()V'
	assert source.count(anchor) == 1
	source = source.replace(anchor, anchor + '\n    const-wide v0, 0x7fffffffffffffffL\n    iput-wide v0, p0, ' + helper + '->vinixIdleTimeout:J')
	source += '\n.field private vinixIdleTimeout:J\n'
	source = framework_replace_method(source, 'setIdleConnectionTimeout(J)V', '.method public synchronized setIdleConnectionTimeout(J)V
.locals 2
iget-object v0, p0, ${helper}->mDatabase:${db}
if-eqz v0, :validate
invoke-virtual {v0}, ${db}->isOpen()Z
move-result v0
if-eqz v0, :validate
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "Connection timeout setting cannot be changed after opening the database"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
:validate
const-wide/16 v0, 0
cmp-long v0, p1, v0
if-gez v0, :valid
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Idle timeout must not be negative"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:valid
iput-wide p1, p0, ${helper}->vinixIdleTimeout:J
return-void
.end method')!
	writable := '    invoke-static {v2, v0, v3}, ' + db + '->openOrCreateDatabase(Ljava/lang/String;' + factory + handler + ')' + db
	readonly := '    invoke-static {v2, v0, v3, v4}, ' + db + '->openDatabase(Ljava/lang/String;' + factory + 'I' + handler + ')' + db
	assert source.count(writable) == 1 && source.count(readonly) == 1
	method := '->vinixOpenDatabase(Ljava/lang/String;' + factory + 'I' + handler + ')' + db
	source = source.replace(writable, '    const/high16 v4, 0x10000000\n    invoke-direct {p0, v2, v0, v4, v3}, ' + helper + method)
	source = source.replace(readonly, '    invoke-direct {p0, v2, v0, v3, v4}, ' + helper + method)
	source += '.method private vinixOpenDatabase(Ljava/lang/String;${factory}I${handler})${db}
.locals 3
new-instance v0, ${builder}
invoke-direct {v0}, ${builder}-><init>()V
invoke-virtual {v0, p2}, ${builder}->setCursorFactory(${factory})${builder}
invoke-virtual {v0, p3}, ${builder}->setOpenFlags(I)${builder}
invoke-virtual {v0, p4}, ${builder}->setErrorHandler(${handler})${builder}
iget-wide v1, p0, ${helper}->vinixIdleTimeout:J
invoke-virtual {v0, v1, v2}, ${builder}->setIdleConnectionTimeout(J)${builder}
invoke-virtual {v0}, ${builder}->build()${params}
move-result-object v0
invoke-static {p1, v0}, ${db}->openDatabase(Ljava/lang/String;${params})${db}
move-result-object v0
return-object v0
.end method
'
	os.write_file(path, source)!
}
