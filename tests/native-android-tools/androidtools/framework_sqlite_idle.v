// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Keep eviction on a shared background Looper, independent of the UI thread.
// Every pool transition and eviction uses the pool lock. Only available
// connections can be evicted; acquisition cancels their pending message.
fn framework_sqlite_idle(smali string) ! {
	base := smali + '/android/database/sqlite/'
	config := 'Landroid/database/sqlite/SQLiteDatabaseConfiguration;'
	pool := 'Landroid/database/sqlite/SQLiteConnectionPool;'
	connection := 'Landroid/database/sqlite/SQLiteConnection;'
	helper := 'Landroid/database/sqlite/VinixSQLiteIdle;'
	mut text := os.read_file(base + 'SQLiteDatabaseConfiguration.smali')!
	text += '\n.field public idleConnectionTimeoutMs:J\n'
	anchor := '    iput p2, p0, ' + config + '->openFlags:I'
	assert text.contains(anchor)
	text = text.replace(anchor, anchor + '\n    const-wide v0, 0x7fffffffffffffffL\n    iput-wide v0, p0, ' + config + '->idleConnectionTimeoutMs:J')
	anchor_copy := '    iget v0, p1, ' + config + '->openFlags:I'
	assert text.contains(anchor_copy)
	text = text.replace(anchor_copy, '    iget-wide v0, p1, ' + config + '->idleConnectionTimeoutMs:J\n    iput-wide v0, p0, ' + config + '->idleConnectionTimeoutMs:J\n' + anchor_copy)
	os.write_file(base + 'SQLiteDatabaseConfiguration.smali', text)!

	mut source := os.read_file(base + 'SQLiteConnectionPool.smali')!
	source += '\n.field private vinixIdleHandler:Landroid/os/Handler;\n'
	for signature, insertion in {
		'finishAcquireConnectionLocked(' + connection + 'I)V': 'invoke-direct {p0, p1}, ' + pool + '->vinixCancelIdle(' + connection + ')V',
		'closeConnectionAndLogExceptionsLocked(' + connection + ')V': 'invoke-direct {p0, p1}, ' + pool + '->vinixCancelIdle(' + connection + ')V'
	} {
		start := source.index('.method private ' + signature) or { return error('Missing SQLite pool method: ' + signature) }
		end := start + (source[start..].index('.end method') or { return error('Missing method end') })
		block := source[start..end]
		registers := block.all_after('.registers ').all_before('\n')
		source = source[..start] + block.replace('.registers ' + registers, '.registers ' + registers + '\n' + insertion) + source[end..]
	}
	start := source.index('.method private open()V') or { return error('Missing pool open') }
	end := start + (source[start..].index('.end method') or { return error('Missing pool open end') })
	source = source[..start] + source[start..end].replace('    return-void', '    invoke-direct {p0}, ' + pool + '->vinixStartIdle()V\n    return-void') + source[end..]
	anchor_release := '    :goto_1f\n    monitor-exit v1'
	assert source.contains(anchor_release)
	source = source.replace(anchor_release, '    :goto_1f\n    invoke-direct {p0, p1}, ' + pool + '->vinixScheduleIdle(' + connection + ')V\n    monitor-exit v1')
	source += '.method private vinixStartIdle()V
.locals 6
iget-object v0, p0, ${pool}->mConfiguration:${config}
invoke-virtual {v0}, ${config}->isInMemoryDb()Z
move-result v3
if-nez v3, :done
iget-wide v1, v0, ${config}->idleConnectionTimeoutMs:J
const-wide v4, 0x7fffffffffffffffL
cmp-long v3, v1, v4
if-eqz v3, :done
sget-object v4, ${helper}->looper:Landroid/os/Looper;
new-instance v5, ${helper}
invoke-direct {v5, p0, v4, v1, v2}, ${helper}-><init>(${pool}Landroid/os/Looper;J)V
iput-object v5, p0, ${pool}->vinixIdleHandler:Landroid/os/Handler;
iget-object v0, p0, ${pool}->mAvailablePrimaryConnection:${connection}
invoke-direct {p0, v0}, ${pool}->vinixScheduleIdle(${connection})V
:done
return-void
.end method
.method private vinixCancelIdle(${connection})V
.locals 2
iget-object v0, p0, ${pool}->vinixIdleHandler:Landroid/os/Handler;
if-eqz v0, :done
invoke-virtual {p1}, ${connection}->getConnectionId()I
move-result v1
invoke-virtual {v0, v1}, Landroid/os/Handler;->removeMessages(I)V
:done
return-void
.end method
.method private vinixScheduleIdle(${connection})V
.locals 4
iget-object v0, p0, ${pool}->vinixIdleHandler:Landroid/os/Handler;
if-eqz v0, :done
iget-boolean v1, p0, ${pool}->mIsOpen:Z
if-eqz v1, :done
iget-object v1, p0, ${pool}->mAvailablePrimaryConnection:${connection}
if-eq v1, p1, :available
iget-object v1, p0, ${pool}->mAvailableNonPrimaryConnections:Ljava/util/ArrayList;
invoke-virtual {v1, p1}, Ljava/util/ArrayList;->contains(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :done
:available
invoke-virtual {p1}, ${connection}->getConnectionId()I
move-result v1
invoke-virtual {v0, v1}, Landroid/os/Handler;->removeMessages(I)V
iget-object v2, p0, ${pool}->mConfiguration:${config}
iget-wide v2, v2, ${config}->idleConnectionTimeoutMs:J
invoke-virtual {v0, v1, v2, v3}, Landroid/os/Handler;->sendEmptyMessageDelayed(IJ)Z
:done
return-void
.end method
.method vinixCloseIdle(I)V
.locals 5
iget-object v0, p0, ${pool}->mLock:Ljava/lang/Object;
monitor-enter v0
:try_start
iget-boolean v1, p0, ${pool}->mIsOpen:Z
if-eqz v1, :done
# A dispatched old message may have waited while this connection was acquired
# and released again. Leave the new idle deadline to its queued message.
iget-object v1, p0, ${pool}->vinixIdleHandler:Landroid/os/Handler;
invoke-virtual {v1, p1}, Landroid/os/Handler;->hasMessages(I)Z
move-result v1
if-nez v1, :done
iget-object v1, p0, ${pool}->mAvailablePrimaryConnection:${connection}
if-eqz v1, :nonprimary
invoke-virtual {v1}, ${connection}->getConnectionId()I
move-result v2
if-ne v2, p1, :nonprimary
const/4 v2, 0
iput-object v2, p0, ${pool}->mAvailablePrimaryConnection:${connection}
invoke-direct {p0, v1}, ${pool}->closeConnectionAndLogExceptionsLocked(${connection})V
goto :done
:nonprimary
iget-object v1, p0, ${pool}->mAvailableNonPrimaryConnections:Ljava/util/ArrayList;
invoke-virtual {v1}, Ljava/util/ArrayList;->size()I
move-result v2
:loop
add-int/lit8 v2, v2, -1
if-ltz v2, :done
invoke-virtual {v1, v2}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v3
check-cast v3, ${connection}
invoke-virtual {v3}, ${connection}->getConnectionId()I
move-result v4
if-ne v4, p1, :loop
invoke-virtual {v1, v2}, Ljava/util/ArrayList;->remove(I)Ljava/lang/Object;
invoke-direct {p0, v3}, ${pool}->closeConnectionAndLogExceptionsLocked(${connection})V
:done
monitor-exit v0
:try_end
return-void
.catchall {:try_start .. :try_end} :failed
:failed
move-exception v1
monitor-exit v0
throw v1
.end method
'
	os.write_file(base + 'SQLiteConnectionPool.smali', source)!
	os.write_file(base + 'VinixSQLiteIdle.smali', '.class final ${helper}
.super Landroid/os/Handler;
.field static final looper:Landroid/os/Looper;
.field private final pool:${pool}
.method static constructor <clinit>()V
.locals 2
new-instance v0, Landroid/os/HandlerThread;
const-string v1, "SQLiteIdle"
invoke-direct {v0, v1}, Landroid/os/HandlerThread;-><init>(Ljava/lang/String;)V
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/Thread;->setDaemon(Z)V
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
invoke-virtual {v0}, Landroid/os/HandlerThread;->getLooper()Landroid/os/Looper;
move-result-object v0
sput-object v0, ${helper}->looper:Landroid/os/Looper;
return-void
.end method
.method constructor <init>(${pool}Landroid/os/Looper;J)V
.locals 0
invoke-direct {p0, p2}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
iput-object p1, p0, ${helper}->pool:${pool}
return-void
.end method
.method public handleMessage(Landroid/os/Message;)V
.locals 2
iget-object v0, p0, ${helper}->pool:${pool}
iget v1, p1, Landroid/os/Message;->what:I
invoke-virtual {v0, v1}, ${pool}->vinixCloseIdle(I)V
return-void
.end method
')!
}
