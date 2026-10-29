// SPDX-License-Identifier: GPL-2.0-or-later
// Real ART network observations. Exit zero means complete observations.
module main

import crypto.sha256
import json2
import os
import strconv

const owner = 'Lorg/vinix/bootstrap/Main;'
const task = 'Lorg/vinix/bootstrap/NetworkTask;'
const host = 'mobilemaps.googleapis.com'
const prefix = 'MAPS-NETWORK '
const pass_marker = 'MAPS-NETWORK-PASS observations-complete'
const prefix_v2 = 'MAPS-NETWORK-V2 '
const pass_marker_v2 = 'MAPS-NETWORK-V2-PASS observations-complete'
const prefix_v3 = 'MAPS-NETWORK-V3 '
const pass_marker_v3 = 'MAPS-NETWORK-V3-PASS observations-complete'
const wrong_host = 'vinix-network-probe.invalid'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn task_source() string {
	mut text := '.class public final ${task}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n'
	for field in ['mode:I', 'address:Ljava/net/InetAddress;', 'socket:Ljava/net/Socket;', 'addresses:[Ljava/net/InetAddress;', 'status:I', 'error:I', 'errno:I', 'latch:Ljava/util/concurrent/CountDownLatch;'] {
		text += '.field public volatile ${field}\n'
	}
	text += method('public constructor <init>(ILjava/net/InetAddress;Ljava/net/Socket;)V', 2, '
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput p1, p0, ${task}->mode:I
iput-object p2, p0, ${task}->address:Ljava/net/InetAddress;
iput-object p3, p0, ${task}->socket:Ljava/net/Socket;
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 1
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
iput-object v0, p0, ${task}->latch:Ljava/util/concurrent/CountDownLatch;
return-void')
	text += method('public run()V', 8, '
:begin
iget v0, p0, ${task}->mode:I
if-eqz v0, :dns
const/4 v1, 1
if-eq v0, v1, :tcp
const/4 v1, 2
if-eq v0, v1, :constructor
goto :tls
:dns
const-string v0, "${host}"
invoke-static {v0}, Ljava/net/InetAddress;->getAllByName(Ljava/lang/String;)[Ljava/net/InetAddress;
move-result-object v0
iput-object v0, p0, ${task}->addresses:[Ljava/net/InetAddress;
goto :success
:tcp
new-instance v0, Ljava/net/Socket;
invoke-direct {v0}, Ljava/net/Socket;-><init>()V
iput-object v0, p0, ${task}->socket:Ljava/net/Socket;
new-instance v1, Ljava/net/InetSocketAddress;
iget-object v2, p0, ${task}->address:Ljava/net/InetAddress;
const/16 v3, 443
invoke-direct {v1, v2, v3}, Ljava/net/InetSocketAddress;-><init>(Ljava/net/InetAddress;I)V
const/16 v2, 3000
invoke-virtual {v0, v1, v2}, Ljava/net/Socket;->connect(Ljava/net/SocketAddress;I)V
goto :success
:constructor
new-instance v0, Ljava/net/Socket;
const-string v1, "${host}"
const/16 v2, 443
invoke-direct {v0, v1, v2}, Ljava/net/Socket;-><init>(Ljava/lang/String;I)V
iput-object v0, p0, ${task}->socket:Ljava/net/Socket;
invoke-virtual {v0}, Ljava/net/Socket;->getInetAddress()Ljava/net/InetAddress;
move-result-object v0
iput-object v0, p0, ${task}->address:Ljava/net/InetAddress;
goto :success
:tls
invoke-static {}, Ljavax/net/ssl/SSLSocketFactory;->getDefault()Ljavax/net/SocketFactory;
move-result-object v0
check-cast v0, Ljavax/net/ssl/SSLSocketFactory;
iget-object v1, p0, ${task}->socket:Ljava/net/Socket;
const-string v2, "${host}"
const/16 v3, 443
const/4 v4, 1
invoke-virtual/range {v0 .. v4}, Ljavax/net/ssl/SSLSocketFactory;->createSocket(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;
move-result-object v0
iput-object v0, p0, ${task}->socket:Ljava/net/Socket;
check-cast v0, Landroid/atl/VinixSSLSocket;
invoke-virtual {v0, v2}, Landroid/atl/VinixSSLSocket;->setHostname(Ljava/lang/String;)V
const/16 v1, 3000
invoke-virtual {v0, v1}, Ljava/net/Socket;->setSoTimeout(I)V
invoke-virtual {v0}, Ljavax/net/ssl/SSLSocket;->startHandshake()V
invoke-virtual {v0}, Ljavax/net/ssl/SSLSocket;->getSession()Ljavax/net/ssl/SSLSession;
move-result-object v1
invoke-static {}, Ljavax/net/ssl/HttpsURLConnection;->getDefaultHostnameVerifier()Ljavax/net/ssl/HostnameVerifier;
move-result-object v0
invoke-interface {v0, v2, v1}, Ljavax/net/ssl/HostnameVerifier;->verify(Ljava/lang/String;Ljavax/net/ssl/SSLSession;)Z
move-result v0
if-nez v0, :success
new-instance v0, Ljavax/net/ssl/SSLPeerUnverifiedException;
const-string v1, "fixture hostname verification failed"
invoke-direct {v0, v1}, Ljavax/net/ssl/SSLPeerUnverifiedException;-><init>(Ljava/lang/String;)V
throw v0
:success
const/4 v0, 0
iput v0, p0, ${task}->status:I
goto :finish
:failed
move-exception v0
const/4 v1, 1
iput v1, p0, ${task}->status:I
invoke-static {v0}, ${owner}->classify(Ljava/lang/Throwable;)I
move-result v1
iput v1, p0, ${task}->error:I
invoke-static {v0}, ${owner}->errno(Ljava/lang/Throwable;)I
move-result v1
iput v1, p0, ${task}->errno:I
:finish
iget-object v0, p0, ${task}->latch:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
return-void
.catch Ljava/lang/Throwable; {:begin .. :success} :failed')
	text += method('public close()V', 1, '
:begin
iget-object v0, p0, ${task}->socket:Ljava/net/Socket;
if-eqz v0, :end
invoke-virtual {v0}, Ljava/net/Socket;->close()V
:end
return-void
:ignored
move-exception v0
return-void
.catch Ljava/lang/Throwable; {:begin .. :end} :ignored')
	return text
}

fn helpers() string {
	mut text := method('public static family(Ljava/net/InetAddress;)I', 1, '
instance-of v0, p0, Ljava/net/Inet4Address;
if-eqz v0, :six
const/4 v0, 4
return v0
:six
instance-of v0, p0, Ljava/net/Inet6Address;
if-eqz v0, :unknown
const/4 v0, 6
return v0
:unknown
const/4 v0, 0
return v0')
	mut classify := ''
	for index, class in ['java/net/SocketTimeoutException', 'java/net/ConnectException', 'java/net/UnknownHostException', 'javax/net/ssl/SSLHandshakeException', 'javax/net/ssl/SSLPeerUnverifiedException', 'javax/net/ssl/SSLException', 'java/net/SocketException', 'java/lang/SecurityException', 'java/io/IOException'] {
		classify += 'instance-of v0, p0, L${class};\nif-eqz v0, :next${index}\nconst/16 v0, ${index + 1}\nreturn v0\n:next${index}\n'
	}
	text += method('public static classify(Ljava/lang/Throwable;)I', 1, classify + 'const/16 v0, 10\nreturn v0')
	text += method('public static errno(Ljava/lang/Throwable;)I', 3, '
const/4 v1, 4
:next
if-eqz p0, :none
instance-of v0, p0, Landroid/system/ErrnoException;
if-eqz v0, :cause
check-cast p0, Landroid/system/ErrnoException;
iget v0, p0, Landroid/system/ErrnoException;->errno:I
if-ltz v0, :none
const/16 v2, 4095
if-gt v0, v2, :none
return v0
:cause
invoke-virtual {p0}, Ljava/lang/Throwable;->getCause()Ljava/lang/Throwable;
move-result-object p0
add-int/lit8 v1, v1, -1
if-nez v1, :next
:none
const/4 v0, 0
return v0')
	mut body := 'new-instance v0, Ljava/lang/StringBuilder;\nconst-string v1, "${prefix}stage="\ninvoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V\n'
	for index, name in ['stage', 'index', 'family', 'status', 'error', 'errno'] {
		if index > 0 { body += 'const-string v1, " ${name}="\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' }
		body += 'invoke-virtual {v0, p${index}}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\n'
	}
	body += 'invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\nmove-result-object v0\nsget-object v1, Ljava/lang/System;->out:Ljava/io/PrintStream;\ninvoke-virtual {v1, v0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
	text += method('public static emit(IIIIII)V', 2, body)
	text += method('private static await(Lorg/vinix/bootstrap/NetworkTask;)Z', 5, '
new-instance v0, Ljava/lang/Thread;
invoke-direct {v0, p0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/Thread;->setDaemon(Z)V
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
iget-object v0, p0, ${task}->latch:Ljava/util/concurrent/CountDownLatch;
const-wide/16 v1, 3000
sget-object v3, Ljava/util/concurrent/TimeUnit;->MILLISECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v0, v1, v2, v3}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v0
return v0')
	return text
}

fn emit(stage int, index string, family string, status string) string {
	return 'const/16 v0, ${stage}\nmove v1, ${index}\nmove v2, ${family}\nmove v3, ${status}\nconst/4 v4, 0\nconst/4 v5, 0\ninvoke-static/range {v0 .. v5}, ${owner}->emit(IIIIII)V\n'
}

fn emit_task(stage int, object string, index string, family string) string {
	return 'const/16 v0, ${stage}\nmove v1, ${index}\nmove v2, ${family}\nconst/4 v3, 2\nconst/4 v4, 0\nconst/4 v5, 0\nif-eqz v6, :emit${stage}\niget v3, ${object}, ${task}->status:I\niget v4, ${object}, ${task}->error:I\niget v5, ${object}, ${task}->errno:I\n:emit${stage}\ninvoke-static/range {v0 .. v5}, ${owner}->emit(IIIIII)V\n'
}

fn main_source() string {
	mut text := '.class public ${owner}\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n.field public static volatile finished:Z\n' + method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') + helpers()
	text += method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Observing ART DNS, TCP and verified TLS. No HTTP requests."
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
new-instance v0, Lorg/vinix/bootstrap/NetworkDeadline;
invoke-direct {v0}, Lorg/vinix/bootstrap/NetworkDeadline;-><init>()V
new-instance v1, Ljava/lang/Thread;
invoke-direct {v1, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
const/4 v2, 1
invoke-virtual {v1, v2}, Ljava/lang/Thread;->setDaemon(Z)V
invoke-virtual {v1}, Ljava/lang/Thread;->start()V
new-instance v0, Ljava/lang/Thread;
invoke-direct {v0, p0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
return-void')
	text += method('public run()V', 15, '
const/4 v10, 0
const/4 v11, 0
const/4 v13, 0
' + emit(1, 'v10', 'v11', 'v13') + '
new-instance v7, ${task}
const/4 v0, 0
const/4 v1, 0
invoke-direct {v7, v0, v1, v1}, ${task}-><init>(ILjava/net/InetAddress;Ljava/net/Socket;)V
invoke-static {v7}, ${owner}->await(Lorg/vinix/bootstrap/NetworkTask;)Z
move-result v6
const/4 v9, 0
const/4 v8, 0
if-eqz v6, :dns_ready
iget v0, v7, ${task}->status:I
if-nez v0, :dns_ready
iget-object v8, v7, ${task}->addresses:[Ljava/net/InetAddress;
array-length v9, v8
const/16 v0, 8
if-le v9, v0, :dns_ready
const/16 v9, 8
const/4 v0, 3
iput v0, v7, ${task}->status:I
:dns_ready
' + emit_task(2, 'v7', 'v9', 'v11') + '
:address
if-ge v10, v9, :constructor
aget-object v14, v8, v10
invoke-static {v14}, ${owner}->family(Ljava/net/InetAddress;)I
move-result v11
const/4 v13, 0
' + emit(3, 'v10', 'v11', 'v13') + '
new-instance v12, ${task}
const/4 v0, 1
const/4 v1, 0
invoke-direct {v12, v0, v14, v1}, ${task}-><init>(ILjava/net/InetAddress;Ljava/net/Socket;)V
invoke-static {v12}, ${owner}->await(Lorg/vinix/bootstrap/NetworkTask;)Z
move-result v6
' + emit_task(4, 'v12', 'v10', 'v11') + '
if-eqz v6, :skip_tls
iget v0, v12, ${task}->status:I
if-nez v0, :skip_tls
new-instance v7, ${task}
const/4 v0, 3
iget-object v1, v12, ${task}->socket:Ljava/net/Socket;
invoke-direct {v7, v0, v14, v1}, ${task}-><init>(ILjava/net/InetAddress;Ljava/net/Socket;)V
invoke-static {v7}, ${owner}->await(Lorg/vinix/bootstrap/NetworkTask;)Z
move-result v6
' + emit_task(6, 'v7', 'v10', 'v11') + '
invoke-virtual {v7}, ${task}->close()V
goto :next
:skip_tls
const/4 v13, 3
' + emit(6, 'v10', 'v11', 'v13') + '
:next
invoke-virtual {v12}, ${task}->close()V
add-int/lit8 v10, v10, 1
goto :address
:constructor
new-instance v7, ${task}
const/4 v0, 2
const/4 v1, 0
invoke-direct {v7, v0, v1, v1}, ${task}-><init>(ILjava/net/InetAddress;Ljava/net/Socket;)V
invoke-static {v7}, ${owner}->await(Lorg/vinix/bootstrap/NetworkTask;)Z
move-result v6
const/4 v10, 0
const/4 v11, 0
if-eqz v6, :constructor_ready
iget v0, v7, ${task}->status:I
if-nez v0, :constructor_ready
iget-object v0, v7, ${task}->address:Ljava/net/InetAddress;
invoke-static {v0}, ${owner}->family(Ljava/net/InetAddress;)I
move-result v11
:constructor_ready
' + emit_task(5, 'v7', 'v10', 'v11') + '
invoke-virtual {v7}, ${task}->close()V
const/4 v11, 0
const/4 v13, 0
' + emit(9, 'v9', 'v11', 'v13') + '
const/4 v0, 1
sput-boolean v0, ${owner}->finished:Z
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void')
	return text
}

fn deadline_source() string {
	return '.class public final Lorg/vinix/bootstrap/NetworkDeadline;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' + method('public constructor <init>()V', 0, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') + method('public run()V', 6, '
const-wide/32 v0, 60000
invoke-static {v0, v1}, Ljava/lang/Thread;->sleep(J)V
sget-boolean v0, ${owner}->finished:Z
if-nez v0, :done
const/16 v0, 8
const/4 v1, 0
const/4 v2, 0
const/4 v3, 2
const/4 v4, 0
const/4 v5, 0
invoke-static/range {v0 .. v5}, ${owner}->emit(IIIIII)V
const/4 v0, 2
invoke-static {v0}, Ljava/lang/System;->exit(I)V
:done
return-void')
}

// Keep the original generator byte-for-byte stable. The opt-in profile adds
// observations around the same operations without selecting another factory.
fn replace_once(text string, before string, after string) !string {
	if text.count(before) != 1 { return error('diagnostic insertion point differs') }
	return text.replace(before, after)
}

fn task_source_v2() !string {
	mut text := replace_once(task_source(), '.field public volatile mode:I\n',
		'.field public volatile mode:I\n.field public volatile tls_step:I\n')!
	for index, operation in [
		'invoke-static {}, Ljavax/net/ssl/SSLSocketFactory;->getDefault()Ljavax/net/SocketFactory;',
		'invoke-virtual/range {v0 .. v4}, Ljavax/net/ssl/SSLSocketFactory;->createSocket(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;',
		'check-cast v0, Landroid/atl/VinixSSLSocket;',
		'invoke-virtual {v0, v2}, Landroid/atl/VinixSSLSocket;->setHostname(Ljava/lang/String;)V',
		'invoke-virtual {v0, v1}, Ljava/net/Socket;->setSoTimeout(I)V',
		'invoke-virtual {v0}, Ljavax/net/ssl/SSLSocket;->startHandshake()V',
		'invoke-virtual {v0}, Ljavax/net/ssl/SSLSocket;->getSession()Ljavax/net/ssl/SSLSession;',
		'invoke-static {}, Ljavax/net/ssl/HttpsURLConnection;->getDefaultHostnameVerifier()Ljavax/net/ssl/HostnameVerifier;',
		'invoke-interface {v0, v2, v1}, Ljavax/net/ssl/HostnameVerifier;->verify(Ljava/lang/String;Ljavax/net/ssl/SSLSession;)Z',
	] {
		text = replace_once(text, operation, 'const/16 v7, ${index + 1}\niput v7, p0, ${task}->tls_step:I\n' + operation)!
	}
	return text
}

fn main_source_v2() !string {
	mut text := replace_once(main_source(), '.field public static volatile finished:Z\n',
		'.field public static volatile finished:Z\n.field public static tls_step:I\n')!
	text = replace_once(text, '"${prefix}stage="', '"${prefix_v2}stage="')!
	text = replace_once(text, '"${pass_marker}"', '"${pass_marker_v2}"')!
	text = replace_once(text, emit(3, 'v10', 'v11', 'v13'),
		'const/4 v0, 0\nsput v0, ${owner}->tls_step:I\n' + emit(3, 'v10', 'v11', 'v13'))!
	text = replace_once(text, emit_task(6, 'v7', 'v10', 'v11'),
		'iget v0, v7, ${task}->tls_step:I\nsput v0, ${owner}->tls_step:I\n' + emit_task(6, 'v7', 'v10', 'v11'))!
	text = replace_once(text, 'invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;', '
const-string v1, " step="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const/4 v1, 6
if-ne p0, v1, :no_step
sget v1, ${owner}->tls_step:I
goto :append_step
:no_step
const/4 v1, 0
:append_step
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;')!
	mut extra := ''
	for index, class in ['java/lang/ClassCastException', 'java/lang/NoSuchMethodError',
		'java/lang/NoClassDefFoundError', 'java/lang/VerifyError',
		'java/lang/UnsupportedOperationException', 'java/lang/NoSuchMethodException',
		'java/lang/AbstractMethodError', 'java/lang/LinkageError'] {
		extra += 'instance-of v0, p0, L${class};\nif-eqz v0, :extra${index}\nconst/16 v0, ${index + 11}\nreturn v0\n:extra${index}\n'
	}
	head := '.method public static classify(Ljava/lang/Throwable;)I\n.locals 1\n'
	return replace_once(text, head, head + extra)!
}

// V3 uses only standard JSSE interfaces. Keep the v1/v2 adapters and their
// emitted classes intact so historical observations remain reproducible.
fn tls_step_v3(step int) string {
	return 'const/16 v7, ${step}\niput v7, p0, ${task}->tls_step:I\n'
}

fn task_source_v3() !string {
	mut text := replace_once(task_source_v2()!, '.field public volatile tls_step:I\n',
		'.field public volatile tls_step:I\n.field public volatile verified:I\n')!
	text = replace_once(text, 'goto :tls\n:dns', 'const/4 v1, 4\nif-eq v0, v1, :verify\nconst/4 v1, 5\nif-eq v0, v1, :verify\ngoto :tls\n:dns')!
	begin := text.index('\n:tls\n') or { return error('TLS block absent') }
	end := text.index('\n:success\n') or { return error('TLS completion absent') }
	if end <= begin { return error('TLS block order differs') }
	new_tls := '\n:tls\n' + tls_step_v3(1) + '
invoke-static {}, Ljavax/net/ssl/SSLSocketFactory;->getDefault()Ljavax/net/SocketFactory;
move-result-object v0
check-cast v0, Ljavax/net/ssl/SSLSocketFactory;
iget-object v1, p0, ${task}->socket:Ljava/net/Socket;
const-string v2, "${host}"
const/16 v3, 443
const/4 v4, 1
' + tls_step_v3(2) + '
const/16 v5, 3000
invoke-virtual {v1, v5}, Ljava/net/Socket;->setSoTimeout(I)V
invoke-virtual/range {v0 .. v4}, Ljavax/net/ssl/SSLSocketFactory;->createSocket(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;
move-result-object v0
iput-object v0, p0, ${task}->socket:Ljava/net/Socket;
' + tls_step_v3(3) + '
check-cast v0, Ljavax/net/ssl/SSLSocket;
' + tls_step_v3(4) + '
invoke-virtual {v0}, Ljavax/net/ssl/SSLSocket;->getSSLParameters()Ljavax/net/ssl/SSLParameters;
move-result-object v1
' + tls_step_v3(5) + '
new-instance v3, Ljavax/net/ssl/SNIHostName;
invoke-direct {v3, v2}, Ljavax/net/ssl/SNIHostName;-><init>(Ljava/lang/String;)V
invoke-static {v3}, Ljava/util/Collections;->singletonList(Ljava/lang/Object;)Ljava/util/List;
move-result-object v3
invoke-virtual {v1, v3}, Ljavax/net/ssl/SSLParameters;->setServerNames(Ljava/util/List;)V
' + tls_step_v3(6) + '
const-string v3, "HTTPS"
invoke-virtual {v1, v3}, Ljavax/net/ssl/SSLParameters;->setEndpointIdentificationAlgorithm(Ljava/lang/String;)V
' + tls_step_v3(7) + '
invoke-virtual {v0, v1}, Ljavax/net/ssl/SSLSocket;->setSSLParameters(Ljavax/net/ssl/SSLParameters;)V
' + tls_step_v3(8) + '
const/16 v1, 3000
invoke-virtual {v0, v1}, Ljava/net/Socket;->setSoTimeout(I)V
' + tls_step_v3(9) + '
invoke-virtual {v0}, Ljavax/net/ssl/SSLSocket;->startHandshake()V
goto :success
:verify
' + tls_step_v3(10) + '
iget-object v0, p0, ${task}->socket:Ljava/net/Socket;
check-cast v0, Ljavax/net/ssl/SSLSocket;
invoke-virtual {v0}, Ljavax/net/ssl/SSLSocket;->getSession()Ljavax/net/ssl/SSLSession;
move-result-object v1
' + tls_step_v3(11) + '
invoke-static {}, Ljavax/net/ssl/HttpsURLConnection;->getDefaultHostnameVerifier()Ljavax/net/ssl/HostnameVerifier;
move-result-object v0
iget v3, p0, ${task}->mode:I
const/4 v4, 4
const-string v2, "${host}"
if-eq v3, v4, :hostname_ready
const-string v2, "${wrong_host}"
:hostname_ready
' + tls_step_v3(12) + '
invoke-interface {v0, v2, v1}, Ljavax/net/ssl/HostnameVerifier;->verify(Ljava/lang/String;Ljavax/net/ssl/SSLSession;)Z
move-result v0
const/4 v1, 2
if-eqz v0, :verified_result
const/4 v1, 1
:verified_result
iput v1, p0, ${task}->verified:I
goto :success'
	return replace_once(text, text[begin..end], new_tls)!
}

fn emit_v3(stage int, index string, family string, status string) string {
	return 'const/4 v0, 0\nsput v0, ${owner}->tls_step:I\nsput v0, ${owner}->verified:I\n' + emit(stage, index, family, status)
}

fn emit_task_v3(stage int, index string, family string) string {
	return 'iget v0, v7, ${task}->tls_step:I\nsput v0, ${owner}->tls_step:I\nconst/4 v0, 0\nsput v0, ${owner}->verified:I\nif-eqz v6, :no_result${stage}\niget v0, v7, ${task}->verified:I\nsput v0, ${owner}->verified:I\n:no_result${stage}\n' + emit_task(stage, 'v7', index, family)
}

fn verify_task_v3(mode int, stage int) string {
	return 'iget-object v1, v7, ${task}->socket:Ljava/net/Socket;\nnew-instance v7, ${task}\nconst/16 v0, ${mode}\ninvoke-direct {v7, v0, v14, v1}, ${task}-><init>(ILjava/net/InetAddress;Ljava/net/Socket;)V\ninvoke-static {v7}, ${owner}->await(Lorg/vinix/bootstrap/NetworkTask;)Z\nmove-result v6\n' + emit_task_v3(stage, 'v10', 'v11')
}

fn main_source_v3() !string {
	mut text := replace_once(main_source_v2()!, '.field public static tls_step:I\n',
		'.field public static tls_step:I\n.field public static verified:I\n')!
	text = replace_once(text, '"${prefix_v2}stage="', '"${prefix_v3}stage="')!
	text = replace_once(text, '"${pass_marker_v2}"', '"${pass_marker_v3}"')!
	// Four addresses fit all four 3-second phases plus DNS and the host
	// constructor inside the unchanged 60-second process watchdog.
	text = replace_once(text, 'const/16 v0, 8\nif-le v9, v0, :dns_ready', 'const/16 v0, 4\nif-le v9, v0, :dns_ready')!
	text = replace_once(text, 'const/16 v9, 8', 'const/16 v9, 4')!
	text = replace_once(text, 'const/4 v1, 6\nif-ne p0, v1, :no_step',
		'const/4 v1, 6\nif-eq p0, v1, :tls_step\nconst/4 v1, 7\nif-eq p0, v1, :tls_step\nconst/16 v1, 10\nif-ne p0, v1, :no_step\n:tls_step')!
	text = replace_once(text, 'invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;', '
const-string v1, " verified="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const/4 v1, 7
if-eq p0, v1, :verification_result
const/16 v1, 10
if-eq p0, v1, :verification_result
const/4 v1, 0
goto :append_verification
:verification_result
sget v1, ${owner}->verified:I
:append_verification
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;')!
	old_tls := 'iget v0, v7, ${task}->tls_step:I\nsput v0, ${owner}->tls_step:I\n' + emit_task(6, 'v7', 'v10', 'v11') + '\ninvoke-virtual {v7}, ${task}->close()V\ngoto :next'
	new_tls := emit_task_v3(6, 'v10', 'v11') + '
if-eqz v6, :skip_verify
iget v0, v7, ${task}->status:I
if-nez v0, :skip_verify
' + verify_task_v3(4, 7) + '
if-eqz v6, :skip_negative
iget v0, v7, ${task}->status:I
if-nez v0, :skip_negative
' + verify_task_v3(5, 10) + '
goto :close_tls
:skip_verify
const/4 v13, 3
' + emit_v3(7, 'v10', 'v11', 'v13') + '
:skip_negative
const/4 v13, 3
' + emit_v3(10, 'v10', 'v11', 'v13') + '
:close_tls
invoke-virtual {v7}, ${task}->close()V
goto :next'
	text = replace_once(text, old_tls, new_tls)!
	return replace_once(text, emit(6, 'v10', 'v11', 'v13'),
		emit_v3(6, 'v10', 'v11', 'v13') + emit_v3(7, 'v10', 'v11', 'v13') + emit_v3(10, 'v10', 'v11', 'v13'))!
}

struct Record {
	stage int
	index int
	family int
	status int
	error int
	system_errno int
}

fn parse(line string) !Record {
	return parse_record(line, 10)
}

fn parse_record(line string, max_error int) !Record {
	if line.len > 128 || !line.starts_with(prefix) { return error('invalid record prefix or length') }
	parts := line[prefix.len..].split(' ')
	keys := ['stage', 'index', 'family', 'status', 'error', 'errno']
	if parts.len != keys.len { return error('invalid record field count') }
	mut values := []int{}
	for i, part in parts {
		start := keys[i] + '='
		if !part.starts_with(start) { return error('invalid record field order') }
		value := part[start.len..]
		if value == '' || value.len > 4 || (value.len > 1 && value[0] == `0`) || !value.bytes().all(it >= `0` && it <= `9`) { return error('invalid canonical number') }
		values << strconv.atoi(value)!
	}
	r := Record{values[0], values[1], values[2], values[3], values[4], values[5]}
	if r.stage !in [1, 2, 3, 4, 5, 6, 8, 9] || r.index > 8 || r.family !in [0, 4, 6] || r.status > 3 || r.error > max_error || r.system_errno > 4095 { return error('record outside finite schema') }
	if r.status != 1 && (r.error != 0 || r.system_errno != 0) { return error('nonexception record contains error data') }
	if r.status == 1 && r.error == 0 { return error('exception classification absent') }
	return r
}

fn validate(records []Record) ! {
	if records.len < 4 || records.len > 28 { return error('incomplete or oversized observations') }
	if records[0] != Record{stage: 1} { return error('begin record differs') }
	dns := records[1]
	if dns.stage != 2 || dns.family != 0 || (dns.status in [1, 2] && dns.index != 0) || (dns.status == 3 && dns.index != 8) { return error('invalid DNS result') }
	mut at := 2
	for index in 0 .. dns.index {
		if at + 3 > records.len { return error('missing address observations') }
		address, tcp, tls := records[at], records[at + 1], records[at + 2]
		if address.stage != 3 || address.index != index || address.family !in [4, 6] || address.status != 0 || address.error != 0 || address.system_errno != 0 || tcp.stage != 4 || tcp.index != index || tcp.family != address.family || tcp.status > 2 || tls.stage != 6 || tls.index != index || tls.family != address.family || (tcp.status != 0 && tls.status != 3) || (tcp.status == 0 && tls.status == 3) { return error('address/TCP/TLS observation order or family differs') }
		at += 3
	}
	if at + 2 != records.len { return error('extra or missing terminal observations') }
	constructor := records[at]
	if constructor.stage != 5 || constructor.index != 0 || constructor.status > 2 || (constructor.status == 0 && constructor.family !in [4, 6]) || (constructor.status != 0 && constructor.family != 0) { return error('invalid constructor observation') }
	if records[at + 1] != Record{stage: 9, index: dns.index} { return error('complete record differs') }
}

fn read_records(text string) ![]Record {
	mut records := []Record{}
	mut completed := false
	lines := text.split('\n')
	for index, line in lines {
		if !line.starts_with('MAPS-NETWORK') { continue }
		if index == lines.len - 1 { return error('unterminated public record') }
		if completed { return error('public output after completion marker') }
		if line == pass_marker {
			validate(records)!
			completed = true
			continue
		}
		if records.len >= 28 { return error('oversized observations') }
		records << parse(line)!
	}
	if !completed { return error('completion marker absent') }
	validate(records)!
	return records
}

struct TlsRecord {
	stage int
	index int
	family int
	status int
	error int
	system_errno int
	step int
}

fn parse_v2(line string) !TlsRecord {
	if line.len > 144 || !line.starts_with(prefix_v2) { return error('invalid v2 prefix or length') }
	parts := line.split(' step=')
	if parts.len != 2 || parts[1].len != 1 || parts[1][0] < `0` || parts[1][0] > `9` {
		return error('invalid v2 step')
	}
	base := parse_record(prefix + parts[0][prefix_v2.len..], 18)!
	step := int(parts[1][0] - `0`)
	if (base.stage != 6 && step != 0) || (base.stage == 6 && base.status == 3 && step != 0)
		|| (base.stage == 6 && base.status == 0 && step != 9)
		|| (base.stage == 6 && base.status == 1 && step == 0) {
		return error('v2 step does not match operation')
	}
	return TlsRecord{base.stage, base.index, base.family, base.status, base.error, base.system_errno, step}
}

fn validate_v2(records []TlsRecord) ! {
	mut base := []Record{}
	for r in records { base << Record{r.stage, r.index, r.family, r.status, r.error, r.system_errno} }
	validate(base)!
}

fn read_records_v2(text string) ![]TlsRecord {
	mut records := []TlsRecord{}
	mut completed := false
	lines := text.split('\n')
	for index, line in lines {
		if !line.starts_with('MAPS-NETWORK') { continue }
		if index == lines.len - 1 || completed { return error('incomplete or trailing v2 public output') }
		if line == pass_marker_v2 {
			validate_v2(records)!
			completed = true
			continue
		}
		if records.len >= 28 { return error('oversized v2 observations') }
		records << parse_v2(line)!
	}
	if !completed { return error('v2 completion marker absent') }
	validate_v2(records)!
	return records
}

struct JsseRecord {
	stage int
	index int
	family int
	status int
	error int
	system_errno int
	step int
	verified int
}

fn parse_v3(line string) !JsseRecord {
	if line.len > 160 || !line.starts_with(prefix_v3) { return error('invalid v3 prefix or length') }
	parts := line[prefix_v3.len..].split(' ')
	keys := ['stage', 'index', 'family', 'status', 'error', 'errno', 'step', 'verified']
	if parts.len != keys.len { return error('invalid v3 field count') }
	mut values := []int{}
	for i, part in parts {
		start := keys[i] + '='
		if !part.starts_with(start) { return error('invalid v3 field order') }
		value := part[start.len..]
		if value == '' || value.len > 4 || (value.len > 1 && value[0] == `0`) || !value.bytes().all(it >= `0` && it <= `9`) { return error('invalid v3 canonical number') }
		values << strconv.atoi(value)!
	}
	r := JsseRecord{values[0], values[1], values[2], values[3], values[4], values[5], values[6], values[7]}
	if r.stage !in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] || r.index > 4 || r.family !in [0, 4, 6] || r.status > 3 || r.error > 18 || r.system_errno > 4095 || r.step > 12 || r.verified > 2 { return error('v3 record outside finite schema') }
	if (r.status != 1 && (r.error != 0 || r.system_errno != 0)) || (r.status == 1 && r.error == 0) { return error('v3 exception classification differs') }
	if r.stage !in [6, 7, 10] && (r.step != 0 || r.verified != 0) { return error('v3 diagnostic outside TLS') }
	if r.stage == 6 && (r.step > 9 || r.verified != 0 || (r.status == 0 && r.step != 9) || (r.status == 1 && r.step == 0) || (r.status == 3 && r.step != 0)) { return error('v3 handshake step differs') }
	if r.stage in [7, 10] {
		if (r.step != 0 && r.step < 10) || (r.status == 0 && (r.step != 12 || r.verified == 0)) || (r.status != 0 && r.verified != 0) || (r.status == 1 && r.step == 0) || (r.status == 3 && r.step != 0) { return error('v3 hostname step or outcome differs') }
	}
	return r
}

fn validate_v3(records []JsseRecord) ! {
	if records.len < 4 || records.len > 24 { return error('incomplete or oversized v3 observations') }
	if records[0] != JsseRecord{stage: 1} { return error('v3 begin record differs') }
	dns := records[1]
	if dns.stage != 2 || dns.family != 0 || (dns.status in [1, 2] && dns.index != 0) || (dns.status == 3 && dns.index != 4) { return error('invalid v3 DNS result') }
	mut at := 2
	for index in 0 .. dns.index {
		if at + 5 > records.len { return error('missing v3 address observations') }
		address, tcp, handshake := records[at], records[at + 1], records[at + 2]
		verification, control := records[at + 3], records[at + 4]
		if address.stage != 3 || address.index != index || address.family !in [4, 6] || address.status != 0 || address.error != 0 || address.system_errno != 0 || tcp.stage != 4 || tcp.index != index || tcp.family != address.family || tcp.status > 2 || handshake.stage != 6 || handshake.index != index || handshake.family != address.family || (tcp.status != 0 && handshake.status != 3) || (tcp.status == 0 && handshake.status == 3) { return error('v3 address/TCP/handshake order or family differs') }
		if verification.stage != 7 || control.stage != 10 || verification.index != index || control.index != index || verification.family != address.family || control.family != address.family || (handshake.status != 0 && verification.status != 3) || (handshake.status == 0 && verification.status == 3) || (verification.status != 0 && control.status != 3) || (verification.status == 0 && control.status == 3) { return error('v3 hostname/control order or prerequisites differ') }
		at += 5
	}
	if at + 2 != records.len { return error('extra or missing v3 terminal observations') }
	constructor := records[at]
	if constructor.stage != 5 || constructor.index != 0 || constructor.status > 2 || (constructor.status == 0 && constructor.family !in [4, 6]) || (constructor.status != 0 && constructor.family != 0) { return error('invalid v3 constructor observation') }
	if records[at + 1] != JsseRecord{stage: 9, index: dns.index} { return error('v3 complete record differs') }
}

fn read_records_v3(text string) ![]JsseRecord {
	mut records := []JsseRecord{}
	mut completed := false
	lines := text.split('\n')
	for index, line in lines {
		if !line.starts_with('MAPS-NETWORK') { continue }
		if index == lines.len - 1 || completed { return error('incomplete or trailing v3 public output') }
		if line == pass_marker_v3 {
			validate_v3(records)!
			completed = true
			continue
		}
		if records.len >= 24 { return error('oversized v3 observations') }
		records << parse_v3(line)!
	}
	if !completed { return error('v3 completion marker absent') }
	validate_v3(records)!
	return records
}

fn self_test_v3() ! {
	lines := [
		'MAPS-NETWORK-V3 stage=1 index=0 family=0 status=0 error=0 errno=0 step=0 verified=0',
		'MAPS-NETWORK-V3 stage=2 index=1 family=0 status=0 error=0 errno=0 step=0 verified=0',
		'MAPS-NETWORK-V3 stage=3 index=0 family=4 status=0 error=0 errno=0 step=0 verified=0',
		'MAPS-NETWORK-V3 stage=4 index=0 family=4 status=0 error=0 errno=0 step=0 verified=0',
		'MAPS-NETWORK-V3 stage=6 index=0 family=4 status=0 error=0 errno=0 step=9 verified=0',
		'MAPS-NETWORK-V3 stage=7 index=0 family=4 status=0 error=0 errno=0 step=12 verified=1',
		'MAPS-NETWORK-V3 stage=10 index=0 family=4 status=0 error=0 errno=0 step=12 verified=2',
		'MAPS-NETWORK-V3 stage=5 index=0 family=0 status=2 error=0 errno=0 step=0 verified=0',
		'MAPS-NETWORK-V3 stage=9 index=1 family=0 status=0 error=0 errno=0 step=0 verified=0',
	]
	stream := lines.join('\n') + '\n' + pass_marker_v3 + '\n'
	records := read_records_v3(stream)!
	assert records[4].step == 9 && records[5].verified == 1 && records[6].verified == 2
	// An accepted wrong host remains visible as an adverse observation. The
	// completion marker never recasts it as a successful policy check.
	control_accepted := read_records_v3(stream.replace('step=12 verified=2', 'step=12 verified=1'))!
	assert control_accepted[6].verified == 1
	mut failed := lines.clone()
	failed[4] = failed[4].replace('status=0 error=0 errno=0 step=9', 'status=1 error=4 errno=0 step=9')
	failed[5] = failed[5].replace('status=0 error=0 errno=0 step=12 verified=1', 'status=3 error=0 errno=0 step=0 verified=0')
	failed[6] = failed[6].replace('status=0 error=0 errno=0 step=12 verified=2', 'status=3 error=0 errno=0 step=0 verified=0')
	failed_records := read_records_v3(failed.join('\n') + '\n' + pass_marker_v3 + '\n')!
	assert failed_records[4].error == 4
	failed[4] = failed[4].replace('status=1 error=4 errno=0 step=9', 'status=2 error=0 errno=0 step=0')
	timeout_records := read_records_v3(failed.join('\n') + '\n' + pass_marker_v3 + '\n')!
	assert timeout_records[4].step == 0
	mut tcp_failed := failed.clone()
	tcp_failed[3] = tcp_failed[3].replace('status=0 error=0', 'status=1 error=2')
	tcp_failed[4] = tcp_failed[4].replace('status=2', 'status=3')
	assert read_records_v3(tcp_failed.join('\n') + '\n' + pass_marker_v3 + '\n')!.len == 9
	mut verify_failed := lines.clone()
	verify_failed[5] = verify_failed[5].replace('status=0 error=0 errno=0 step=12 verified=1', 'status=1 error=6 errno=0 step=11 verified=0')
	verify_failed[6] = failed[6]
	assert read_records_v3(verify_failed.join('\n') + '\n' + pass_marker_v3 + '\n')!.len == 9
	verify_failed[5] = verify_failed[5].replace('status=1 error=6 errno=0 step=11', 'status=2 error=0 errno=0 step=0')
	assert read_records_v3(verify_failed.join('\n') + '\n' + pass_marker_v3 + '\n')!.len == 9
	no_addresses := [lines[0], lines[1].replace('index=1', 'index=0').replace('status=0', 'status=2'), lines[7], lines[8].replace('index=1', 'index=0')]
	assert read_records_v3(no_addresses.join('\n') + '\n' + pass_marker_v3 + '\n')!.len == 4
	mut four_addresses := [lines[0], lines[1].replace('index=1', 'index=4').replace('status=0', 'status=3')]
	for index in 0 .. 4 {
		for line in lines[2..7] { four_addresses << line.replace('index=0', 'index=${index}') }
	}
	four_addresses << lines[7]
	four_addresses << lines[8].replace('index=1', 'index=4')
	four_stream := four_addresses.join('\n') + '\n' + pass_marker_v3 + '\n'
	assert read_records_v3(four_stream)!.len == 24
	for malformed in [stream.replace('step=9 verified=0', 'step=3 verified=0'),
		stream.replace('step=12 verified=1', 'step=9 verified=1'),
		stream.replace('step=12 verified=2', 'step=12 verified=0'),
		stream.replace('step=12 verified=2', 'step=12 verified=3'),
		stream.replace('step=12 verified=2', 'step=012 verified=2'),
		stream.replace('errno=0 step=0', 'errno=4096 step=0'),
		stream.replace('stage=10', 'stage=7'), stream.replace('verified=2', 'verified=2 secret=value'),
		stream + pass_marker_v3 + '\n', stream.trim_right('\n'), stream.replace('\n', '\r\n'),
		stream.replace(lines[5], failed[5]), stream.replace(lines[4], failed[4]),
		stream.replace(lines[5] + '\n', ''), four_stream.replace('index=4', 'index=5'),
		stream.replace(prefix_v3, prefix_v2)] {
		if _ := read_records_v3(malformed) { return error('invalid v3 observation accepted') }
	}
	if _ := read_records(stream) { return error('v1 checker accepted v3 output') }
	if _ := read_records_v2(stream) { return error('v2 checker accepted v3 output') }
	new_task := task_source_v3()!
	new_main := main_source_v3()!
	assert !new_task.contains('VinixSSLSocket') && !new_task.contains('printStackTrace') && !new_task.contains('getMessage')
	assert !new_task.contains('setDefault') && !new_task.contains('TrustManager')
	assert new_task.contains('check-cast v0, Ljavax/net/ssl/SSLSocket;')
	assert new_task.contains('Ljavax/net/ssl/SNIHostName;-><init>(Ljava/lang/String;)V')
	assert new_task.contains('->setEndpointIdentificationAlgorithm(Ljava/lang/String;)V')
	assert new_task.contains('const-string v3, "HTTPS"') && new_task.contains(wrong_host)
	assert new_main.contains(pass_marker_v3) && new_main.contains(' verified=')
	assert new_main.contains('const/16 v0, 4\nif-le v9, v0, :dns_ready')
	assert new_main.contains('const/16 v9, 4') && !new_main.contains('const/16 v9, 8')
}

fn self_test() ! {
	lines := ['MAPS-NETWORK stage=1 index=0 family=0 status=0 error=0 errno=0', 'MAPS-NETWORK stage=2 index=1 family=0 status=0 error=0 errno=0', 'MAPS-NETWORK stage=3 index=0 family=4 status=0 error=0 errno=0', 'MAPS-NETWORK stage=4 index=0 family=4 status=0 error=0 errno=0', 'MAPS-NETWORK stage=6 index=0 family=4 status=1 error=4 errno=0', 'MAPS-NETWORK stage=5 index=0 family=0 status=2 error=0 errno=0', 'MAPS-NETWORK stage=9 index=1 family=0 status=0 error=0 errno=0']
	mut records := []Record{}
	for line in lines { records << parse(line)! }
	validate(records)!
	stream := lines.join('\n') + '\n' + pass_marker + '\n'
	assert read_records(stream)! == records
	for bad_text in [lines.join('\n'), stream.trim_right('\n'), stream.replace('\n', '\r\n'), stream + 'MAPS-NETWORK\tstage=9\n', stream + pass_marker + '\n'] {
		if _ := read_records(bad_text) { return error('incomplete or noncanonical public stream accepted') }
	}
	for malformed in [lines[0] + ' secret=value', lines[0].replace('stage=1', 'stage=01'), lines[0].replace('index=0', 'index=-1'), lines[0].replace('family=0', 'family=5'), lines[0].replace('errno=0', 'errno=4096'), lines[0].replace('status=0', 'status=1'), lines[0] + '\r', lines[0] + '\n'] {
		if _ := parse(malformed) { return error('malformed public extension accepted') }
	}
	if _ := validate(records[..records.len - 1]) { return error('missing completion accepted') }
	mut swapped := records.clone()
	swapped[2], swapped[3] = swapped[3], swapped[2]
	if _ := validate(swapped) { return error('reordered observations accepted') }
	assert !task_source().contains('printStackTrace') && !task_source().contains('getMessage')
	// The original emitted classes remain pinned independently of v2.
	assert sha256.sum(main_source().bytes()).hex() == 'd8cdb2e0b440ef78dd423253b7ddaa6d4b3783fb1b8e2b418a32fe112b0a0f2c'
	assert sha256.sum(task_source().bytes()).hex() == '80ae068d0b16282f1e829fc43781f82df81cc97156fbb63b15c397b9fb4ac3ea'
	assert sha256.sum(deadline_source().bytes()).hex() == 'e41339ed53124f6b4695f4bca420dc0cdab221d615454b12ecdd3ce050cd405b'
	mut v2 := []string{}
	for line in lines {
		v2 << line.replace(prefix, prefix_v2) + if line.contains('stage=6 ') { ' step=3' } else { ' step=0' }
	}
	v2[4] = v2[4].replace('error=4', 'error=11')
	v2_stream := v2.join('\n') + '\n' + pass_marker_v2 + '\n'
	parsed_v2 := read_records_v2(v2_stream)!
	assert parsed_v2[4].error == 11
	startup_timeout := read_records_v2(v2_stream.replace('status=1 error=11 errno=0 step=3',
		'status=2 error=0 errno=0 step=0'))!
	assert startup_timeout[4].status == 2 && startup_timeout[4].step == 0
	for malformed in [v2_stream.replace('step=3', 'step=0'), v2_stream.replace('error=11', 'error=19'),
		v2_stream.replace('step=3', 'step=03'), v2_stream + pass_marker_v2 + '\n',
		v2_stream.trim_right('\n'), v2_stream.replace('\n', '\r\n')] {
		if _ := read_records_v2(malformed) { return error('invalid v2 observation accepted') }
	}
	new_task := task_source_v2()!
	new_main := main_source_v2()!
	assert new_task.count('->tls_step:I\n') == 9
	assert new_main.contains(pass_marker_v2)
	assert sha256.sum(new_main.bytes()).hex() == '7fabaac27d184499535574886d50e417b56e7cb60bcdcf50eb51e6f39a794d91'
	assert sha256.sum(new_task.bytes()).hex() == '0ba3eedd6178812466e1762b33ddc2f87bf8dc29072ba0cb2b319a36dcbb1877'
	self_test_v3()!
	println('MAPS-NETWORK SELF-TEST PASS canonical-finite-schema ordered-observations incomplete-and-private-extension-rejection')
}

fn checked(args []string) ! {
	result := os.exec(args)
	if result.exit_code != 0 { return error(result.output) }
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len == 3 && os.args[1] == '--check' {
		if os.file_size(os.args[2]) > 8 * 1024 * 1024 { eprintln('bounded log required'); exit(1) }
		text := os.read_file(os.args[2]) or { eprintln(err); exit(1) }
		records := read_records(text) or { eprintln(err); exit(1) }
		println(json2.encode(records))
		println('MAPS-NETWORK CHECK PASS observations complete; connectivity outcomes remain diagnostic')
		return
	}
	if os.args.len == 3 && os.args[1] == '--check-v2' {
		if os.file_size(os.args[2]) > 8 * 1024 * 1024 { eprintln('bounded log required'); exit(1) }
		text := os.read_file(os.args[2]) or { eprintln(err); exit(1) }
		records := read_records_v2(text) or { eprintln(err); exit(1) }
		println(json2.encode(records))
		println('MAPS-NETWORK-V2 CHECK PASS observations complete; TLS steps remain diagnostic')
		return
	}
	if os.args.len == 3 && os.args[1] == '--check-v3' {
		if os.file_size(os.args[2]) > 8 * 1024 * 1024 { eprintln('bounded log required'); exit(1) }
		text := os.read_file(os.args[2]) or { eprintln(err); exit(1) }
		records := read_records_v3(text) or { eprintln(err); exit(1) }
		println(json2.encode(records))
		println('MAPS-NETWORK-V3 CHECK PASS observations complete; handshake and hostname outcomes remain diagnostic')
		return
	}
	v2 := os.args.len == 8 && os.args[1] == '--tls-diagnostics-v2'
	v3 := os.args.len == 8 && os.args[1] == '--tls-v3'
	if os.args.len != 7 && !v2 && !v3 { eprintln('usage: maps-network-fixture [--tls-diagnostics-v2|--tls-v3] OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER | --check[-v2|-v3] LOG | --self-test'); exit(2) }
	build(if v3 { 3 } else if v2 { 2 } else { 1 }) or { eprintln(err); exit(1) }
}

fn build(profile int) ! {
	v2, v3 := profile == 2, profile == 3
	offset := if v2 || v3 { 1 } else { 0 }
	out, aapt, resources := os.abs_path(os.args[1 + offset]), os.real_path(os.args[2 + offset]), os.real_path(os.args[3 + offset])
	tools, java, signer := os.real_path(os.args[4 + offset]), os.real_path(os.args[5 + offset]), os.real_path(os.args[6 + offset])
	if os.exists(out) || os.is_link(out) { return error('fresh output directory required') }
	dir := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(dir)!
	os.write_file(dir + '/Main.smali', if v3 { main_source_v3()! } else if v2 { main_source_v2()! } else { main_source() })!
	os.write_file(dir + '/NetworkTask.smali', if v3 { task_source_v3()! } else if v2 { task_source_v2()! } else { task_source() })!
	os.write_file(dir + '/NetworkDeadline.smali', deadline_source())!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><uses-permission android:name="android.permission.INTERNET"/><application android:label="ART network observations"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])!
	checked([aapt, 'link', '--manifest', out + '/AndroidManifest.xml', '-I', resources, '-o', out + '/unsigned.apk'])!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])!
	checked([os.dir(java) + '/keytool', '-genkeypair', '-keystore', out + '/fixture.p12', '-storetype', 'PKCS12', '-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname', 'CN=Vinix ART Network Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])!
	checked([java, '-jar', signer, 'sign', '--ks', out + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])!
	os.write_file(out + '/fixture.json', json2.encode({'format': json2.Any(1), 'profile': json2.Any(if v3 { 'tls-v3' } else if v2 { 'tls-diagnostics-v2' } else { 'network-v1' }), 'source_sha256': json2.Any(sha256.sum(os.read_bytes(@FILE)!).hex()), 'host': json2.Any(host), 'port': json2.Any(443), 'address_cap': json2.Any(if v3 { 4 } else { 8 }), 'phase_deadline_ms': json2.Any(3000), 'process_deadline_ms': json2.Any(60000), 'scope': json2.Any('Real ART DNS, TCP and TLS observations; no HTTP requests, credentials or authentication claim. The completion marker and checker establish complete observations, not Internet availability.')}, prettify: true) + '\n')!
	println('MAPS-NETWORK-APK ' + out + '/probe.apk')
}
