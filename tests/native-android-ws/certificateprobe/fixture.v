// SPDX-License-Identifier: GPL-2.0-or-later
module certificateprobe

import os

// Deterministic transport tests do not substitute for live certificate checks.
pub fn install(root string) ! {
	os.write_file(root + '/smali/CertificateProbe.smali', r'.class public Lorg/vinix/bootstrap/CertificateProbe;
.super Ljava/lang/Object;
.method public static check()V
.locals 7
invoke-static {}, Lorg/vinix/bootstrap/CertificateProbe;->invalidSocket()V
new-instance v0, Lorg/vinix/bootstrap/TestTlsSocket;
invoke-direct {v0}, Lorg/vinix/bootstrap/TestTlsSocket;-><init>()V
const/16 v1, 317
invoke-virtual {v0, v1}, Ljava/net/Socket;->setSoTimeout(I)V
new-instance v2, Landroid/net/VinixCertificateSocket;
const/16 v3, 25
invoke-direct {v2, v0, v3}, Landroid/net/VinixCertificateSocket;-><init>(Ljava/net/Socket;I)V
invoke-virtual {v2}, Ljava/net/Socket;->getInputStream()Ljava/io/InputStream;
move-result-object v4
iget v5, v0, Lorg/vinix/bootstrap/TestTlsSocket;->calls:I
const/4 v6, 0
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v4}, Ljava/io/InputStream;->read()I
move-result v5
const/4 v6, 7
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v4}, Ljava/io/InputStream;->read()I
iget v5, v0, Lorg/vinix/bootstrap/TestTlsSocket;->calls:I
const/4 v6, 1
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v5, v0, Lorg/vinix/bootstrap/TestTlsSocket;->observed:I
invoke-static {v5, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Ljava/net/Socket;->getSoTimeout()I
move-result v5
invoke-static {v5, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Ljavax/net/ssl/SSLSocket;->startHandshake()V
iget v5, v0, Lorg/vinix/bootstrap/TestTlsSocket;->calls:I
const/4 v6, 2
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Ljava/net/Socket;->close()V
iget-boolean v5, v0, Lorg/vinix/bootstrap/TestTlsSocket;->closed:Z
const/4 v6, 1
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Lorg/vinix/bootstrap/TestTlsSocket;
invoke-direct {v0}, Lorg/vinix/bootstrap/TestTlsSocket;-><init>()V
new-instance v2, Landroid/net/VinixCertificateSocket;
invoke-direct {v2, v0, v3}, Landroid/net/VinixCertificateSocket;-><init>(Ljava/net/Socket;I)V
invoke-virtual {v2}, Ljava/net/Socket;->getOutputStream()Ljava/io/OutputStream;
move-result-object v4
iget v5, v0, Lorg/vinix/bootstrap/TestTlsSocket;->calls:I
const/4 v6, 0
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v5, 3
new-array v5, v5, [B
invoke-virtual {v4, v5}, Ljava/io/OutputStream;->write([B)V
iget v5, v0, Lorg/vinix/bootstrap/TestTlsSocket;->calls:I
const/4 v6, 1
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Ljava/net/Socket;->getSoTimeout()I
move-result v5
const/4 v6, 0
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Ljava/net/Socket;->close()V
new-instance v0, Lorg/vinix/bootstrap/TestTlsSocket;
invoke-direct {v0}, Lorg/vinix/bootstrap/TestTlsSocket;-><init>()V
const/4 v5, 1
iput-boolean v5, v0, Lorg/vinix/bootstrap/TestTlsSocket;->fail:Z
new-instance v2, Landroid/net/VinixCertificateSocket;
invoke-direct {v2, v0, v3}, Landroid/net/VinixCertificateSocket;-><init>(Ljava/net/Socket;I)V
:timeout
invoke-virtual {v2}, Ljavax/net/ssl/SSLSocket;->startHandshake()V
:timeout_end
new-instance v5, Ljava/lang/AssertionError;
invoke-direct {v5}, Ljava/lang/AssertionError;-><init>()V
throw v5
:timed_out
move-exception v5
iget-boolean v5, v0, Lorg/vinix/bootstrap/TestTlsSocket;->closed:Z
const/4 v6, 1
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v5, v0, Lorg/vinix/bootstrap/TestTlsSocket;->observed:I
invoke-static {v5, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/16 v0, 1000
const/4 v1, 0
invoke-static {v0, v1}, Landroid/net/SSLCertificateSocketFactory;->getDefault(ILandroid/net/SSLSessionCache;)Ljavax/net/ssl/SSLSocketFactory;
move-result-object v0
invoke-virtual {v0}, Ljavax/net/ssl/SSLSocketFactory;->getSupportedCipherSuites()[Ljava/lang/String;
move-result-object v1
array-length v1, v1
if-lez v1, :bad
invoke-virtual {v0}, Ljavax/net/ssl/SSLSocketFactory;->createSocket()Ljava/net/Socket;
move-result-object v1
const/16 v2, 157
invoke-virtual {v1, v2}, Ljava/net/Socket;->setSoTimeout(I)V
invoke-virtual {v1}, Ljava/net/Socket;->getSoTimeout()I
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Ljava/net/Socket;->isConnected()Z
move-result v3
const/4 v2, 0
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Ljava/net/Socket;->close()V
:negative
const/4 v0, -1
invoke-static {v0}, Landroid/net/SSLCertificateSocketFactory;->getDefault(I)Ljavax/net/SocketFactory;
:negative_end
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:negative_ok
move-exception v0
return-void
.catch Ljava/net/SocketTimeoutException; {:timeout .. :timeout_end} :timed_out
.catch Ljava/lang/IllegalArgumentException; {:negative .. :negative_end} :negative_ok
.end method
.method public static invalidSocket()V
.locals 2
new-instance v0, Ljava/net/Socket;
invoke-direct {v0}, Ljava/net/Socket;-><init>()V
const-string v1, "unused.invalid"
:plain
invoke-static {v0, v1}, Landroid/net/SSLCertificateSocketFactory;->verifyHostname(Ljava/net/Socket;Ljava/lang/String;)V
:plain_end
invoke-virtual {v0}, Ljava/net/Socket;->close()V
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:plain_rejected
move-exception v1
invoke-virtual {v0}, Ljava/net/Socket;->isClosed()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Ljava/net/Socket;->close()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.catch Ljava/lang/IllegalArgumentException; {:plain .. :plain_end} :plain_rejected
.end method
')!
	mut fake := r'.class public Lorg/vinix/bootstrap/TestTlsSocket;
.super Ljavax/net/ssl/SSLSocket;
.field public calls:I
.field public observed:I
.field public timeout:I
.field public fail:Z
.field public closed:Z
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljavax/net/ssl/SSLSocket;-><init>()V
return-void
.end method
.method public startHandshake()V
.locals 2
iget v0, p0, Lorg/vinix/bootstrap/TestTlsSocket;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestTlsSocket;->calls:I
iget v0, p0, Lorg/vinix/bootstrap/TestTlsSocket;->timeout:I
iput v0, p0, Lorg/vinix/bootstrap/TestTlsSocket;->observed:I
iget-boolean v0, p0, Lorg/vinix/bootstrap/TestTlsSocket;->fail:Z
if-eqz v0, :done
new-instance v0, Ljava/net/SocketTimeoutException;
invoke-direct {v0}, Ljava/net/SocketTimeoutException;-><init>()V
throw v0
:done
return-void
.end method
.method public setSoTimeout(I)V
.locals 0
iput p1, p0, Lorg/vinix/bootstrap/TestTlsSocket;->timeout:I
return-void
.end method
.method public getSoTimeout()I
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestTlsSocket;->timeout:I
return v0
.end method
.method public close()V
.locals 1
const/4 v0, 1
iput-boolean v0, p0, Lorg/vinix/bootstrap/TestTlsSocket;->closed:Z
return-void
.end method
.method public getInputStream()Ljava/io/InputStream;
.locals 3
const/4 v0, 2
new-array v0, v0, [B
const/4 v1, 0
const/4 v2, 7
aput-byte v2, v0, v1
new-instance v1, Ljava/io/ByteArrayInputStream;
invoke-direct {v1, v0}, Ljava/io/ByteArrayInputStream;-><init>([B)V
return-object v1
.end method
.method public getOutputStream()Ljava/io/OutputStream;
.locals 1
new-instance v0, Ljava/io/ByteArrayOutputStream;
invoke-direct {v0}, Ljava/io/ByteArrayOutputStream;-><init>()V
return-object v0
.end method
'
	for name in ['getSupportedCipherSuites', 'getEnabledCipherSuites', 'getSupportedProtocols', 'getEnabledProtocols'] {
		fake += '.method public ${name}()[Ljava/lang/String;\n.locals 1\nconst/4 v0, 0\nnew-array v0, v0, [Ljava/lang/String;\nreturn-object v0\n.end method\n'
	}
	for name in ['getEnableSessionCreation', 'getNeedClientAuth', 'getWantClientAuth', 'getUseClientMode'] {
		fake += '.method public ${name}()Z\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method\n'
	}
	for name in ['setEnableSessionCreation', 'setNeedClientAuth', 'setWantClientAuth', 'setUseClientMode'] {
		fake += '.method public ${name}(Z)V\n.locals 0\nreturn-void\n.end method\n'
	}
	for signature in ['setEnabledCipherSuites([Ljava/lang/String;)V', 'setEnabledProtocols([Ljava/lang/String;)V', 'addHandshakeCompletedListener(Ljavax/net/ssl/HandshakeCompletedListener;)V', 'removeHandshakeCompletedListener(Ljavax/net/ssl/HandshakeCompletedListener;)V'] {
		fake += '.method public ${signature}\n.locals 0\nreturn-void\n.end method\n'
	}
	fake += '.method public getSession()Ljavax/net/ssl/SSLSession;\n.locals 1\nconst/4 v0, 0\nreturn-object v0\n.end method\n'
	os.write_file(root + '/smali/TestTlsSocket.smali', fake)!
}
