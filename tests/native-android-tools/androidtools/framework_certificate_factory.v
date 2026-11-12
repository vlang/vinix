// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Android's secure factory verifies host-name overloads eagerly. Address-only
// and unconnected overloads retain JSSE chain verification; their caller must
// supply the peer identity. The optional cache currently has no backend.
pub fn framework_certificate_factory(smali string) ! {
	factory := 'Landroid/net/SSLCertificateSocketFactory;'
	socket := 'Landroid/net/VinixCertificateSocket;'
	path := smali + '/android/net/SSLCertificateSocketFactory.smali'
	mut source := '.class public ${factory}\n.super Ljavax/net/ssl/SSLSocketFactory;\n.field private delegate:Ljavax/net/ssl/SSLSocketFactory;\n.field private timeout:I\n'
	source += signature_method('public constructor <init>(I)V', '
invoke-direct {p0}, Ljavax/net/ssl/SSLSocketFactory;-><init>()V
if-ltz p1, :bad
iput p1, p0, ${factory}->timeout:I
invoke-static {}, Ljavax/net/ssl/SSLContext;->getDefault()Ljavax/net/ssl/SSLContext;
move-result-object v0
invoke-virtual {v0}, Ljavax/net/ssl/SSLContext;->getSocketFactory()Ljavax/net/ssl/SSLSocketFactory;
move-result-object v0
iput-object v0, p0, ${factory}->delegate:Ljavax/net/ssl/SSLSocketFactory;
return-void
:bad
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "negative handshake timeout"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0')
	for declaration in ['public static getDefault(I)Ljavax/net/SocketFactory;',
		'public static getDefault(ILandroid/net/SSLSessionCache;)Ljavax/net/ssl/SSLSocketFactory;'] {
		source += signature_method(declaration, 'new-instance v0, ${factory}\ninvoke-direct {v0, p0}, ${factory}-><init>(I)V\nreturn-object v0')
	}
	for target in ['getDefaultCipherSuites()[Ljava/lang/String;', 'getSupportedCipherSuites()[Ljava/lang/String;'] {
		source += tls_forward(factory, 'Ljavax/net/ssl/SSLSocketFactory;', 'public ' + target, target, '')
	}
	for spec in [
		['createSocket()Ljava/net/Socket;', '', ''],
		['createSocket(Ljava/lang/String;I)Ljava/net/Socket;', ', p1, p2', 'p1'],
		['createSocket(Ljava/lang/String;ILjava/net/InetAddress;I)Ljava/net/Socket;', ', p1, p2, p3, p4', 'p1'],
		['createSocket(Ljava/net/InetAddress;I)Ljava/net/Socket;', ', p1, p2', ''],
		['createSocket(Ljava/net/InetAddress;ILjava/net/InetAddress;I)Ljava/net/Socket;', ', p1, p2, p3, p4', ''],
		['createSocket(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;', ', p1, p2, p3, p4', 'p2'],
	] {
		mut body := 'iget-object v0, p0, ${factory}->delegate:Ljavax/net/ssl/SSLSocketFactory;\ninvoke-virtual {v0${spec[1]}}, Ljavax/net/ssl/SSLSocketFactory;->${spec[0]}\nmove-result-object v0\nnew-instance v1, ${socket}\niget v2, p0, ${factory}->timeout:I\ninvoke-direct {v1, v0, v2}, ${socket}-><init>(Ljava/net/Socket;I)V\n'
		if spec[2] != '' {
			body += 'invoke-static {v1, ${spec[2]}}, ${factory}->verifyHostname(Ljava/net/Socket;Ljava/lang/String;)V\n'
		}
		source += signature_method('public ' + spec[0], body + 'return-object v1')
	}
	source += signature_method('public static verifyHostname(Ljava/net/Socket;Ljava/lang/String;)V', '
instance-of v0, p0, Ljavax/net/ssl/SSLSocket;
if-eqz v0, :not_ssl
:verify
check-cast p0, Ljavax/net/ssl/SSLSocket;
invoke-virtual {p0}, Ljavax/net/ssl/SSLSocket;->startHandshake()V
invoke-static {}, Ljavax/net/ssl/HttpsURLConnection;->getDefaultHostnameVerifier()Ljavax/net/ssl/HostnameVerifier;
move-result-object v0
invoke-virtual {p0}, Ljavax/net/ssl/SSLSocket;->getSession()Ljavax/net/ssl/SSLSession;
move-result-object v1
invoke-interface {v0, p1, v1}, Ljavax/net/ssl/HostnameVerifier;->verify(Ljava/lang/String;Ljavax/net/ssl/SSLSession;)Z
move-result v0
if-eqz v0, :mismatch
return-void
:mismatch
new-instance v0, Ljavax/net/ssl/SSLPeerUnverifiedException;
const-string v1, "Peer certificate does not match host"
invoke-direct {v0, v1}, Ljavax/net/ssl/SSLPeerUnverifiedException;-><init>(Ljava/lang/String;)V
throw v0
:verify_end
:failed
move-exception v0
:close
invoke-virtual {p0}, Ljava/net/Socket;->close()V
:close_end
throw v0
:close_failed
move-exception v1
throw v0
:not_ssl
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Expected an SSL socket"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
.catchall {:verify .. :verify_end} :failed
.catch Ljava/io/IOException; {:close .. :close_end} :close_failed')
	os.write_file(path, source)!
	certificate_socket(smali, socket)!
}

fn certificate_socket(smali string, socket string) ! {
	delegate := 'Ljavax/net/ssl/SSLSocket;'
	mut source := '.class public final ${socket}\n.super ${delegate}\n.field private delegate:${delegate}\n.field private timeout:I\n.field private handshaken:Z\n'
	source += signature_method('public constructor <init>(Ljava/net/Socket;I)V', '
invoke-direct {p0}, Ljavax/net/ssl/SSLSocket;-><init>()V
check-cast p1, Ljavax/net/ssl/SSLSocket;
iput-object p1, p0, ${socket}->delegate:${delegate}
iput p2, p0, ${socket}->timeout:I
return-void')
	source += signature_method('public synchronized startHandshake()V', '
iget-object v0, p0, ${socket}->delegate:${delegate}
invoke-virtual {v0}, Ljava/net/Socket;->getSoTimeout()I
move-result v1
:handshake
iget v2, p0, ${socket}->timeout:I
invoke-virtual {v0, v2}, Ljava/net/Socket;->setSoTimeout(I)V
invoke-virtual {v0}, Ljavax/net/ssl/SSLSocket;->startHandshake()V
invoke-virtual {v0, v1}, Ljava/net/Socket;->setSoTimeout(I)V
const/4 v1, 1
iput-boolean v1, p0, ${socket}->handshaken:Z
:handshake_end
return-void
:failed
move-exception v1
:close
invoke-virtual {v0}, Ljava/net/Socket;->close()V
:close_end
throw v1
:close_failed
move-exception v2
throw v1
.catchall {:handshake .. :handshake_end} :failed
.catch Ljava/io/IOException; {:close .. :close_end} :close_failed')
	source += signature_method('public synchronized ensureHandshake()V', '
iget-boolean v0, p0, ${socket}->handshaken:Z
if-nez v0, :done
invoke-virtual {p0}, ${socket}->startHandshake()V
:done
return-void')
	source += signature_method('public getSession()Ljavax/net/ssl/SSLSession;', '
:ensure
invoke-virtual {p0}, ${socket}->ensureHandshake()V
:ensure_end
goto :session
:failed
move-exception v0
:session
iget-object v0, p0, ${socket}->delegate:${delegate}
invoke-virtual {v0}, Ljavax/net/ssl/SSLSocket;->getSession()Ljavax/net/ssl/SSLSession;
move-result-object v0
return-object v0
.catch Ljava/io/IOException; {:ensure .. :ensure_end} :failed')
	for target in ['addHandshakeCompletedListener(Ljavax/net/ssl/HandshakeCompletedListener;)V',
		'removeHandshakeCompletedListener(Ljavax/net/ssl/HandshakeCompletedListener;)V',
		'getEnableSessionCreation()Z', 'getEnabledCipherSuites()[Ljava/lang/String;', 'getEnabledProtocols()[Ljava/lang/String;',
		'getNeedClientAuth()Z', 'getHandshakeSession()Ljavax/net/ssl/SSLSession;',
		'getSupportedCipherSuites()[Ljava/lang/String;', 'getSupportedProtocols()[Ljava/lang/String;',
		'getUseClientMode()Z', 'getWantClientAuth()Z', 'getSSLParameters()Ljavax/net/ssl/SSLParameters;',
		'setEnableSessionCreation(Z)V', 'setEnabledCipherSuites([Ljava/lang/String;)V', 'setEnabledProtocols([Ljava/lang/String;)V',
		'setNeedClientAuth(Z)V', 'setSSLParameters(Ljavax/net/ssl/SSLParameters;)V', 'setUseClientMode(Z)V',
		'setWantClientAuth(Z)V', 'bind(Ljava/net/SocketAddress;)V', 'close()V', 'connect(Ljava/net/SocketAddress;)V',
		'connect(Ljava/net/SocketAddress;I)V', 'getChannel()Ljava/nio/channels/SocketChannel;',
		'getInetAddress()Ljava/net/InetAddress;', 'getKeepAlive()Z',
		'getLocalAddress()Ljava/net/InetAddress;', 'getLocalPort()I', 'getLocalSocketAddress()Ljava/net/SocketAddress;',
		'getOOBInline()Z', 'getPort()I', 'getReceiveBufferSize()I',
		'getRemoteSocketAddress()Ljava/net/SocketAddress;', 'getReuseAddress()Z', 'getSendBufferSize()I',
		'getSoLinger()I', 'getSoTimeout()I', 'getTcpNoDelay()Z', 'getTrafficClass()I', 'isBound()Z', 'isClosed()Z',
		'isConnected()Z', 'isInputShutdown()Z', 'isOutputShutdown()Z', 'sendUrgentData(I)V', 'setKeepAlive(Z)V',
		'setOOBInline(Z)V', 'setPerformancePreferences(III)V', 'setReceiveBufferSize(I)V', 'setReuseAddress(Z)V',
		'setSendBufferSize(I)V', 'setSoLinger(ZI)V', 'setSoTimeout(I)V', 'setTcpNoDelay(Z)V', 'setTrafficClass(I)V',
		'shutdownInput()V', 'shutdownOutput()V', 'toString()Ljava/lang/String;'] {
		source += tls_forward(socket, delegate, 'public ' + target, target, '')
	}
	for kind in ['Input', 'Output'] {
		stream := 'Ljava/io/${kind}Stream;'
		wrapper := 'Landroid/net/VinixCertificate${kind};'
		source += signature_method('public get${kind}Stream()${stream}', '
iget-object v0, p0, ${socket}->delegate:${delegate}
invoke-virtual {v0}, Ljava/net/Socket;->get${kind}Stream()${stream}
move-result-object v0
new-instance v1, ${wrapper}
invoke-direct {v1, p0, v0}, ${wrapper}-><init>(${socket}${stream})V
return-object v1')
		mut text := '.class public final ${wrapper}\n.super ${stream}\n.field private socket:${socket}\n.field private delegate:${stream}\n' + signature_method('public constructor <init>(${socket}${stream})V', 'invoke-direct {p0}, ${stream}-><init>()V\niput-object p1, p0, ${wrapper}->socket:${socket}\niput-object p2, p0, ${wrapper}->delegate:${stream}\nreturn-void')
		targets := if kind == 'Input' { ['read()I', 'read([B)I', 'read([BII)I'] } else { ['write(I)V', 'write([B)V', 'write([BII)V'] }
		for target in targets {
			forward := tls_forward(wrapper, stream, 'public ' + target, target, '')
			text += forward.replace('iget-object v0, p0, ${wrapper}->delegate:', 'iget-object v0, p0, ${wrapper}->socket:${socket}\ninvoke-virtual {v0}, ${socket}->ensureHandshake()V\niget-object v0, p0, ${wrapper}->delegate:')
		}
		for target in if kind == 'Input' { ['available()I', 'close()V', 'mark(I)V', 'reset()V', 'markSupported()Z'] } else { ['close()V', 'flush()V'] } {
			text += tls_forward(wrapper, stream, 'public ' + target, target, '')
		}
		os.write_file(smali + '/android/net/VinixCertificate${kind}.smali', text)!
	}
	os.write_file(smali + '/android/net/VinixCertificateSocket.smali', source)!
}
