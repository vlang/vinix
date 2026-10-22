// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Forward JSSE/Socket operations, including I/O and connection state. The
// wrapper's inherited Socket is not the connected transport. These signatures
// have single-register arguments and results.
fn tls_forward(owner string, delegate string, declaration string, target string, wrapper string) string {
	signature := declaration.all_after_last(' ')
	args := signature.all_after('(').all_before(')')
	mut registers := ['v0']
	mut offset := 0
	for offset < args.len {
		for args[offset] == `[` { offset++ }
		if args[offset] == `L` {
			offset += args[offset..].index(';') or { panic('invalid TLS descriptor') }
		}
		offset++
		registers << 'p${registers.len}'
	}
	result := signature.all_after(')')
	mut body := 'iget-object v0, p0, ${owner}->delegate:${delegate}\n' +
		'invoke-virtual {${registers.join(', ')}}, ${delegate}->${target}\n'
	if result == 'V' {
		body += 'return-void'
	} else {
		op := if result.starts_with('L') || result.starts_with('[') { '-object' } else { '' }
		body += 'move-result${op} v0\n'
		if wrapper.len > 0 {
			body += 'new-instance v1, ${wrapper}\ninvoke-direct {v1, v0}, ${wrapper}-><init>(${result})V\nmove-object v0, v1\n'
		}
		body += 'return${op} v0'
	}
	return signature_method(declaration, body)
}

// Android clients discover legacy ALPN by the platform provider class. Contexts
// explicitly delegate to wolfJSSE, preserving its trust and protocol policy.
fn framework_tls_provider(smali string) ! {
	provider := 'Lcom/android/org/conscrypt/OpenSSLProvider;'
	context := 'Landroid/atl/VinixSSLContext;'
	factory := 'Landroid/atl/VinixSSLSocketFactory;'
	socket := 'Landroid/atl/VinixSSLSocket;'
	wolf := 'Lcom/wolfssl/provider/jsse/WolfSSLSocket;'
	path := smali + '/com/android/org/conscrypt/OpenSSLProvider.smali'
	if os.exists(path) { return error('a platform TLS provider already exists') }
	os.mkdir_all(os.dir(path))!
	mut body := '
move-object v0, p0
const-string v1, "VinixTLS"
const-wide/high16 v2, 0x3ff0000000000000L
const-string v4, "Vinix Android TLS adapter backed by wolfJSSE"
invoke-direct {v0, v1, v2, v3, v4}, Ljava/security/Provider;-><init>(Ljava/lang/String;DLjava/lang/String;)V
const-string v0, "wolfJSSE"
invoke-static {v0}, Ljava/security/Security;->getProvider(Ljava/lang/String;)Ljava/security/Provider;
move-result-object v0
if-nez v0, :services
new-instance v0, Ljava/security/ProviderException;
const-string v1, "wolfJSSE TLS provider is not installed"
invoke-direct {v0, v1}, Ljava/security/ProviderException;-><init>(Ljava/lang/String;)V
throw v0
:services
'
	for i, algorithm in ['SSL', 'TLS', 'TLSv1', 'TLSv1.1', 'TLSv1.2', 'TLSv1.3', 'Default'] {
		name := 'VinixSSLContext${i}'
		body += '
const-string v1, "SSLContext"
const-string v2, "${algorithm}"
invoke-virtual {v0, v1, v2}, Ljava/security/Provider;->getService(Ljava/lang/String;Ljava/lang/String;)Ljava/security/Provider$Service;
move-result-object v1
if-eqz v1, :next_${i}
const-string v1, "SSLContext.${algorithm}"
const-string v2, "android.atl.${name}"
invoke-virtual {p0, v1, v2}, Ljava/security/Provider;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
:next_${i}
'
		child := 'Landroid/atl/${name};'
		os.write_file(smali + '/android/atl/${name}.smali', '.class public final ${child}\n.super ${context}\n' +
			signature_method('public constructor <init>()V', 'const-string v0, "${algorithm}"\ninvoke-direct {p0, v0}, ${context}-><init>(Ljava/lang/String;)V\nreturn-void'))!
	}
	os.write_file(path, '.class public final ${provider}\n.super Ljava/security/Provider;\n' +
		signature_method('public constructor <init>()V', body + 'return-void') +
		signature_method('public static synchronized install()V', '
const-string v0, "VinixTLS"
invoke-static {v0}, Ljava/security/Security;->getProvider(Ljava/lang/String;)Ljava/security/Provider;
move-result-object v0
if-nez v0, :done
const-string v0, "keystore.type"
const-string v1, "JKS"
invoke-static {v0, v1}, Ljava/security/Security;->setProperty(Ljava/lang/String;Ljava/lang/String;)V
new-instance v0, ${provider}
invoke-direct {v0}, ${provider}-><init>()V
invoke-static {}, Ljava/security/Security;->getProviders()[Ljava/security/Provider;
move-result-object v1
const/4 v2, 0
:find
array-length v3, v1
if-ge v2, v3, :missing
aget-object v3, v1, v2
add-int/lit8 v2, v2, 1
invoke-virtual {v3}, Ljava/security/Provider;->getName()Ljava/lang/String;
move-result-object v3
const-string v4, "wolfJSSE"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :find
invoke-static {v0, v2}, Ljava/security/Security;->insertProviderAt(Ljava/security/Provider;I)I
goto :done
:missing
new-instance v0, Ljava/security/ProviderException;
const-string v1, "wolfJSSE TLS provider disappeared"
invoke-direct {v0, v1}, Ljava/security/ProviderException;-><init>(Ljava/lang/String;)V
throw v0
:done
return-void'))!

	mut spi := '.class public ${context}\n.super Ljavax/net/ssl/SSLContextSpi;\n.field private delegate:Ljavax/net/ssl/SSLContext;\n' +
		signature_method('public constructor <init>(Ljava/lang/String;)V', '
invoke-direct {p0}, Ljavax/net/ssl/SSLContextSpi;-><init>()V
const-string v0, "wolfJSSE"
invoke-static {p1, v0}, Ljavax/net/ssl/SSLContext;->getInstance(Ljava/lang/String;Ljava/lang/String;)Ljavax/net/ssl/SSLContext;
move-result-object v0
iput-object v0, p0, ${context}->delegate:Ljavax/net/ssl/SSLContext;
return-void')
	for target in ['init([Ljavax/net/ssl/KeyManager;[Ljavax/net/ssl/TrustManager;Ljava/security/SecureRandom;)V',
		'createSSLEngine()Ljavax/net/ssl/SSLEngine;', 'createSSLEngine(Ljava/lang/String;I)Ljavax/net/ssl/SSLEngine;',
		'getSocketFactory()Ljavax/net/ssl/SSLSocketFactory;', 'getServerSocketFactory()Ljavax/net/ssl/SSLServerSocketFactory;',
		'getClientSessionContext()Ljavax/net/ssl/SSLSessionContext;', 'getServerSessionContext()Ljavax/net/ssl/SSLSessionContext;',
		'getDefaultSSLParameters()Ljavax/net/ssl/SSLParameters;', 'getSupportedSSLParameters()Ljavax/net/ssl/SSLParameters;'] {
		name := target[..1].to_upper() + target[1..]
		spi += tls_forward(context, 'Ljavax/net/ssl/SSLContext;', 'protected engine' + name, target,
			if target.starts_with('getSocketFactory(') { factory } else { '' })
	}
	os.write_file(smali + '/android/atl/VinixSSLContext.smali', spi)!

	mut sockets := '.class public final ${factory}\n.super Ljavax/net/ssl/SSLSocketFactory;\n.field private delegate:Ljavax/net/ssl/SSLSocketFactory;\n' +
		signature_method('public constructor <init>(Ljavax/net/ssl/SSLSocketFactory;)V', '
invoke-direct {p0}, Ljavax/net/ssl/SSLSocketFactory;-><init>()V
iput-object p1, p0, ${factory}->delegate:Ljavax/net/ssl/SSLSocketFactory;
return-void')
	for target in ['getDefaultCipherSuites()[Ljava/lang/String;', 'getSupportedCipherSuites()[Ljava/lang/String;',
		'createSocket()Ljava/net/Socket;', 'createSocket(Ljava/lang/String;I)Ljava/net/Socket;',
		'createSocket(Ljava/lang/String;ILjava/net/InetAddress;I)Ljava/net/Socket;',
		'createSocket(Ljava/net/InetAddress;I)Ljava/net/Socket;',
		'createSocket(Ljava/net/InetAddress;ILjava/net/InetAddress;I)Ljava/net/Socket;',
		'createSocket(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;',
		'createSocket(Ljava/net/Socket;Ljava/io/InputStream;Z)Ljava/net/Socket;'] {
		sockets += tls_forward(factory, 'Ljavax/net/ssl/SSLSocketFactory;', 'public ' + target, target,
			if target.starts_with('createSocket(') { socket } else { '' })
	}
	os.write_file(smali + '/android/atl/VinixSSLSocketFactory.smali', sockets)!

	mut transport := '.class public final ${socket}\n.super Ljavax/net/ssl/SSLSocket;\n.field private delegate:${wolf}\n' +
		signature_method('public constructor <init>(Ljava/net/Socket;)V', '
invoke-direct {p0}, Ljavax/net/ssl/SSLSocket;-><init>()V
check-cast p1, ${wolf}
iput-object p1, p0, ${socket}->delegate:${wolf}
return-void') + signature_method('public getNpnSelectedProtocol()[B', 'const/4 v0, 0\nreturn-object v0') +
		// Legacy Android clients configure both ALPN and NPN. NPN is obsolete
		// and unavailable in this TLS backend; keep ALPN configuration intact.
		signature_method('public setNpnProtocols([B)V', 'return-void')
	for target in ['addHandshakeCompletedListener(Ljavax/net/ssl/HandshakeCompletedListener;)V',
		'removeHandshakeCompletedListener(Ljavax/net/ssl/HandshakeCompletedListener;)V',
		'getEnableSessionCreation()Z', 'getEnabledCipherSuites()[Ljava/lang/String;', 'getEnabledProtocols()[Ljava/lang/String;',
		'getNeedClientAuth()Z', 'getSession()Ljavax/net/ssl/SSLSession;', 'getHandshakeSession()Ljavax/net/ssl/SSLSession;',
		'getSupportedCipherSuites()[Ljava/lang/String;', 'getSupportedProtocols()[Ljava/lang/String;',
		'getUseClientMode()Z', 'getWantClientAuth()Z', 'getSSLParameters()Ljavax/net/ssl/SSLParameters;',
		'setEnableSessionCreation(Z)V', 'setEnabledCipherSuites([Ljava/lang/String;)V', 'setEnabledProtocols([Ljava/lang/String;)V',
		'setNeedClientAuth(Z)V', 'setSSLParameters(Ljavax/net/ssl/SSLParameters;)V', 'setUseClientMode(Z)V',
		'setWantClientAuth(Z)V', 'startHandshake()V', 'getAlpnSelectedProtocol()[B', 'setAlpnProtocols([B)V',
		'setUseSessionTickets(Z)V', 'bind(Ljava/net/SocketAddress;)V', 'close()V', 'connect(Ljava/net/SocketAddress;)V',
		'connect(Ljava/net/SocketAddress;I)V', 'getChannel()Ljava/nio/channels/SocketChannel;',
		'getInetAddress()Ljava/net/InetAddress;', 'getInputStream()Ljava/io/InputStream;', 'getKeepAlive()Z',
		'getLocalAddress()Ljava/net/InetAddress;', 'getLocalPort()I', 'getLocalSocketAddress()Ljava/net/SocketAddress;',
		'getOOBInline()Z', 'getOutputStream()Ljava/io/OutputStream;', 'getPort()I', 'getReceiveBufferSize()I',
		'getRemoteSocketAddress()Ljava/net/SocketAddress;', 'getReuseAddress()Z', 'getSendBufferSize()I',
		'getSoLinger()I', 'getSoTimeout()I', 'getTcpNoDelay()Z', 'getTrafficClass()I', 'isBound()Z', 'isClosed()Z',
		'isConnected()Z', 'isInputShutdown()Z', 'isOutputShutdown()Z', 'sendUrgentData(I)V', 'setKeepAlive(Z)V',
		'setOOBInline(Z)V', 'setPerformancePreferences(III)V', 'setReceiveBufferSize(I)V', 'setReuseAddress(Z)V',
		'setSendBufferSize(I)V', 'setSoLinger(ZI)V', 'setSoTimeout(I)V', 'setTcpNoDelay(Z)V', 'setTrafficClass(I)V',
		'shutdownInput()V', 'shutdownOutput()V', 'toString()Ljava/lang/String;'] {
		transport += tls_forward(socket, wolf, 'public ' + target, target, '')
	}
	// The factory sets the peer host. Also support clients that create an
	// unconnected socket and then configure Android's explicit SNI API.
	transport += signature_method('public setHostname(Ljava/lang/String;)V', '
new-instance v0, Ljavax/net/ssl/SNIHostName;
invoke-direct {v0, p1}, Ljavax/net/ssl/SNIHostName;-><init>(Ljava/lang/String;)V
invoke-static {v0}, Ljava/util/Collections;->singletonList(Ljava/lang/Object;)Ljava/util/List;
move-result-object v0
iget-object v1, p0, ${socket}->delegate:${wolf}
invoke-virtual {v1}, ${wolf}->getSSLParameters()Ljavax/net/ssl/SSLParameters;
move-result-object v2
invoke-virtual {v2, v0}, Ljavax/net/ssl/SSLParameters;->setServerNames(Ljava/util/List;)V
invoke-virtual {v1, v2}, ${wolf}->setSSLParameters(Ljavax/net/ssl/SSLParameters;)V
return-void')
	os.write_file(smali + '/android/atl/VinixSSLSocket.smali', transport)!
}
