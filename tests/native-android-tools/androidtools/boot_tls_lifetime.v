// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The shipped wolfJSSE streams have separate read/write locks, while close
// frees their shared native session. Lease the complete stream operation,
// including getError and exception handling, without holding a monitor over I/O.
pub fn boot_tls_lifetime(smali string) ! {
	socket := 'Lcom/wolfssl/provider/jsse/WolfSSLSocket;'
	path := smali + '/com/wolfssl/provider/jsse/WolfSSLSocket.smali'
	mut source := os.read_file(path)!
	old := '.method public declared-synchronized close()V'
	if source.count(old) != 1 || source.contains('vinixIoCount') {
		return error('unexpected wolfJSSE close implementation')
	}
	source = source.replace(old, '.method private declared-synchronized vinixCloseIdle()V')
	source += '\n.field private vinixIoCount:I\n.field private volatile vinixClosing:Z\n'
	source += signature_method('public synchronized vinixEnterIo()V', '
iget-boolean v0, p0, ${socket}->vinixClosing:Z
if-nez v0, :closed
iget v0, p0, ${socket}->vinixIoCount:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${socket}->vinixIoCount:I
return-void
:closed
new-instance v0, Ljava/net/SocketException;
const-string v1, "TLS socket closed"
invoke-direct {v0, v1}, Ljava/net/SocketException;-><init>(Ljava/lang/String;)V
throw v0')
	source += signature_method('private vinixFreeIdle()V', '
iget v0, p0, ${socket}->vinixIoCount:I
if-nez v0, :done
iget-object v0, p0, ${socket}->ssl:Lcom/wolfssl/WolfSSLSession;
if-eqz v0, :done
invoke-virtual {v0}, Lcom/wolfssl/WolfSSLSession;->freeSSL()V
const/4 v0, 0
iput-object v0, p0, ${socket}->ssl:Lcom/wolfssl/WolfSSLSession;
:done
return-void')
	source += signature_method('public synchronized vinixExitIo()V', '
iget v0, p0, ${socket}->vinixIoCount:I
add-int/lit8 v0, v0, -1
iput v0, p0, ${socket}->vinixIoCount:I
if-nez v0, :done
iget-boolean v0, p0, ${socket}->vinixClosing:Z
if-eqz v0, :done
:cleanup
invoke-direct {p0}, ${socket}->vinixFreeIdle()V
:cleaned
return-void
.catch Ljava/lang/Exception; {:cleanup .. :cleaned} :failed
:failed
move-exception v0
invoke-virtual {v0}, Ljava/lang/Throwable;->printStackTrace()V
:done
return-void')
	// Idle close retains the original TLS shutdown/session-cache path. During
	// active I/O, close only the owned transport to wake readers/writers, then
	// let the last operation free the session. autoClose=false retains ownership
	// of the caller's transport; a pending operation keeps its session alive.
	source += signature_method('public synchronized close()V', '
iget-boolean v0, p0, ${socket}->vinixClosing:Z
if-nez v0, :done
const/4 v0, 1
const/4 v2, 0
:close_start
iget v1, p0, ${socket}->vinixIoCount:I
if-nez v1, :busy
invoke-direct {p0}, ${socket}->vinixCloseIdle()V
goto :close_end
:busy
iput-boolean v0, p0, ${socket}->connectionClosed:Z
iget-boolean v0, p0, ${socket}->autoClose:Z
if-eqz v0, :close_end
iget-object v0, p0, ${socket}->socket:Ljava/net/Socket;
if-eqz v0, :internal
invoke-virtual {v0}, Ljava/net/Socket;->close()V
goto :close_end
:internal
invoke-super {p0}, Ljavax/net/ssl/SSLSocket;->close()V
:close_end
goto :cleanup
.catch Ljava/lang/Exception; {:close_start .. :close_end} :close_failed
:close_failed
move-exception v2
:cleanup
:transport_start
iget-boolean v0, p0, ${socket}->autoClose:Z
if-eqz v0, :transport_end
iget-object v0, p0, ${socket}->socket:Ljava/net/Socket;
if-eqz v0, :transport_internal
invoke-virtual {v0}, Ljava/net/Socket;->close()V
goto :transport_end
:transport_internal
invoke-super {p0}, Ljavax/net/ssl/SSLSocket;->close()V
:transport_end
goto :free_start
.catch Ljava/lang/Exception; {:transport_start .. :transport_end} :transport_failed
:transport_failed
move-exception v0
if-nez v2, :free_start
move-object v2, v0
:free_start
const/4 v0, 1
iput-boolean v0, p0, ${socket}->vinixClosing:Z
invoke-direct {p0}, ${socket}->vinixFreeIdle()V
:free_end
goto :result
.catch Ljava/lang/Exception; {:free_start .. :free_end} :free_failed
:free_failed
move-exception v0
if-nez v2, :result
move-object v2, v0
:result
if-eqz v2, :done
instance-of v0, v2, Ljava/io/IOException;
if-eqz v0, :wrap
check-cast v2, Ljava/io/IOException;
throw v2
:wrap
new-instance v0, Ljava/io/IOException;
invoke-direct {v0, v2}, Ljava/io/IOException;-><init>(Ljava/lang/Throwable;)V
throw v0
:done
return-void')
	// A layered socket can be TLS-closed while its caller-owned transport stays
	// open. Report the TLS state rather than only the transport's isClosed().
	start := source.index('.method public final isClosed()Z') or { return error('wolfJSSE isClosed missing') }
	end := source.index_after('.end method', start) or { return error('wolfJSSE isClosed end missing') }
	method := source[start..end]
	if method.count('    .registers 2') != 1 { return error('unexpected isClosed registers') }
	source = source[..start] + method.replace('    .registers 2', '    .registers 2\n\n    iget-boolean v0, p0, ${socket}->vinixClosing:Z\n    if-eqz v0, :vinix_open\n    const/4 v0, 1\n    return v0\n    :vinix_open') + source[end..]
	os.write_file(path, source)!
	for kind in ['Input', 'Output'] {
		owner := 'Lcom/wolfssl/provider/jsse/WolfSSLSocket$WolfSSL${kind}Stream;'
		file := smali + '/com/wolfssl/provider/jsse/WolfSSLSocket$WolfSSL${kind}Stream.smali'
		name := if kind == 'Input' { 'read' } else { 'write' }
		result := if kind == 'Input' { 'I' } else { 'V' }
		declaration := '${name}([BII)${result}'
		mut stream := os.read_file(file)!
		header := '.method public ' + declaration
		if stream.count(header) != 1 { return error('unexpected wolfJSSE stream method') }
		stream = stream.replace(header, '.method private vinix' + declaration)
		stream += '.method public ${declaration}\n.locals 3\n' +
			'iget-object v0, p0, ${owner}->socket:${socket}\ninvoke-virtual {v0}, ${socket}->vinixEnterIo()V\n' +
			':begin\ninvoke-direct/range {p0 .. p3}, ${owner}->vinix${declaration}\n' +
			(if result == 'I' { 'move-result v1\n' } else { '' }) +
			':end\ninvoke-virtual {v0}, ${socket}->vinixExitIo()V\n' +
			(if result == 'I' { 'return v1\n' } else { 'return-void\n' }) +
			'.catchall {:begin .. :end} :failed\n:failed\nmove-exception v1\ninvoke-virtual {v0}, ${socket}->vinixExitIo()V\nthrow v1\n.end method\n'
		os.write_file(file, stream)!
	}
}
