// SPDX-License-Identifier: GPL-2.0-or-later

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.concurrent.atomic.AtomicReference;

public final class VinixJavaSmoke {
    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    public static void main(String[] args) throws Exception {
        require("Vinix".equals(System.getProperty("os.name")), "unexpected os.name");
        require("aarch64".equals(System.getProperty("os.arch")), "unexpected os.arch");
        Path work = Files.createTempDirectory("vinix-java-");
        Path messageFile = work.resolve("message.txt");
        Files.writeString(messageFile, "OpenJDK on Vinix\n", StandardCharsets.UTF_8);
        require(Files.readString(messageFile).equals("OpenJDK on Vinix\n"),
                "NIO file round trip failed");

        String digest = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest("vinix".getBytes(StandardCharsets.UTF_8)));
        require(digest.equals("c83faa56c46e4b8b18498b3de9adb42192e8c6fe6f246e6b36ea50bc6d02d76f"),
                "SHA-256 mismatch");

        try (ServerSocket server = new ServerSocket(0, 1, InetAddress.getLoopbackAddress())) {
            AtomicReference<String> received = new AtomicReference<>();
            AtomicReference<Throwable> serverFailure = new AtomicReference<>();
            Thread serverThread = new Thread(() -> {
                try (Socket peer = server.accept();
                     BufferedReader input = new BufferedReader(new InputStreamReader(
                             peer.getInputStream(), StandardCharsets.UTF_8))) {
                    received.set(input.readLine());
                } catch (Exception error) {
                    serverFailure.set(error);
                }
            }, "vinix-java-loopback");
            serverThread.start();
            try (Socket client = new Socket(InetAddress.getLoopbackAddress(), server.getLocalPort())) {
                client.getOutputStream().write("loopback works\n".getBytes(StandardCharsets.UTF_8));
            }
            serverThread.join(10_000);
            require(!serverThread.isAlive(), "loopback server thread did not exit");
            require(serverFailure.get() == null, "loopback server failed: " + serverFailure.get());
            require("loopback works".equals(received.get()), "threaded loopback socket failed");
        }

        System.out.printf("OpenJDK %s (%s) on Vinix: PASS%n",
                Runtime.version().feature(), System.getProperty("java.vm.name"));
    }
}
