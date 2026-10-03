// SPDX-License-Identifier: GPL-2.0-or-later
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.net.InetAddress;
import java.net.URL;
import java.security.KeyStore;
import java.security.cert.X509Certificate;
import java.util.Base64;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLHandshakeException;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLServerSocket;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;

/** Verify the real JSSE trust store, public HTTPS, and local untrusted rejection. */
public final class AndroidTlsProbe {
    // A public test-only RSA key and self-signed localhost
    // certificate, valid from 2000 through 2099. This root is never trusted.
    private static final String UNTRUSTED_KEYSTORE =
            "/u3+7QAAAAIAAAABAAAAAQAPdW50cnVzdGVkLWxvY2FsAAABoQI/DK4AAAUAMIIE/DAOBgorBgEEASoCEQEBBQAEggToyGbm" +
            "NUyeJegx/U+W54e77fPUBLBBAGJjWcn1FfJIRcxHE6qKJz67RnlwHyaOD0zFV/hLAoFb0N9/F/4dUzY26N8tPywx9GUkpevS" +
            "O25p65GJJsouH3cXBJgitxSXB8Mel6APbddZbWWzUMTLa89wdEV4rsoPPfKjJycCM7ns8ytsixOukMvf5pYjGLaGn5ENFmRa" +
            "fA/zIi2d7BCouBaPJnWbY9lmxmP9VOK8JCbwuLJJHUvLGFud6UJJmbdDsXWbj4j9m99Y0+td12yoWqG1ib+TLA1VbzSTclQL" +
            "emY/1P4a5eMMkQcahz/wZBdEGm8R13AQEI58ZRkf7jdi804OAazzD/ocKBawbXfWpgdygzPaU2P4zP6yOICE09UuFdE2AO5X" +
            "CkuUsMQrxlGFBUqmJdStP0wnsqlRnsmeXTPKjoFgBxnCLxaGmiQwsYDz59f11/QIo05ZlmYwDCecUxIlyvvl/5baKH23ZZtN" +
            "ZnSCcdX+R2Fy3WkcYFQgWNF6BkSmOUJrBe8YQrLtN4+qyHCwUbJLhQxsg6BR1jX1zqqQ3LU0bvLFv++cmejQ/JqP4skNrwDP" +
            "YMhEn4Dg5xLaP8ELEWXNxBDjbT+RTbFDvc0+bXWqt+LflOFgx+obOnAX+qK5UW0CbKFw2b4rP+UifPvhGoa+fmT9ASKWWDxU" +
            "tQlF5XaqAntMGAs1LNa8cv8U1B8z2J2EBk4+EptQe6T1pcYLx84JXMLdN+F6fncSdVVcYR2sDeJ4C7w76j23I0Fa7Hn5hSp7" +
            "G3nMxwEHd1ZuHv56KpNwYtajcobiAFo1II1mx93W7RZU58U6F+r9n7DlWsOxcs1dGD3GVrx3YsgqYic7phJQOeXLkeey85HQ" +
            "d9iTPt92q+YTvzbjjP1ad+coAVchz7Rqm5tprzlLpQ00pDhYJd2H/vVzFBMH3KjQUiBGp7aug4hW1VnaYWVzepb5mc2lY3Wc" +
            "e2H14YuRlVHxrI7GahdbgRAeIMduJ4Zckek2LaBEP6+hloH6afouwUOjszNUrq1LCrKSeuDKklHCFTHR2yvafxrGcNo2j4Y+" +
            "jwSUtoxREIG86aXCm/P2w4ZiNJ4omdZ+S0vrXQuodoMRN0z9tNVcpk2T0e9hNsto8m1JEE1MbHAoCdyfIm3UcspVsRMsoQUk" +
            "OxD2WFS/lUniEC1Z7eqSUTKhxtBHi5p+4XkcUzxPdjthuRi5WU8Rx7SF/a+9LEF50csgWLGE66AIiGjjBxxcJ713AVku90lC" +
            "btb9K8HjQaLrpvQTAA5jGmHX3vyp8usOiylqKfvrZdttoxLckwBVNPz8Hxf+hqobhsdHqOoPRBhu8H/THg6pSSh227d2napl" +
            "x6GNHaqWi/83C7XGWe38NkA/B7yueTMOSKfL+HLRb/U96q0E19/yzvuSac2JMXJNZJXKjvP/t/ZQryzrxyRjN/K/m7zf6X4F" +
            "sQBXdJJPz0rQEfCYKvUoMwGLDyJ98lOmHhE7pwzKts+ZJcMcLfmU17l56TkYRQG/C7K4ARxw+X0MYDYz5nYNpYj688eRgkrX" +
            "gV7peqSdc08gX/IpzL22Jh2TTliXScMClmOPWlXManfv4R7MTc3QKKZEYQC3GdNsG3mGvlbxImY7nolvrqJfsGVv+Pn2qoE7" +
            "7fzdMzjmbXOZy03M25BjqugK6nlZVk0V4mv9IHUAAAABAAVYLjUwOQAAAukwggLlMIIBzaADAgECAgRhFnc6MA0GCSqGSIb3" +
            "DQEBCwUAMBQxEjAQBgNVBAMTCWxvY2FsaG9zdDAgFw0wMDAxMDExNDUwNDhaGA8yMDk5MTIwNzE0NTA0OFowFDESMBAGA1UE" +
            "AxMJbG9jYWxob3N0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAg11nFzheKJKPxSNR6xIm8JMklDrLuP46MiXV" +
            "pjRHh8JipxK6dlDS7SbZxVVLWHpPSvZVnt31zg7S8kgQMrnMKfoXURdD4P6dadJ3LV4u03vH9tsxiXt4nlR1Uq3+SAaZJl0J" +
            "6sugDpplfS8wQHa9Hg70d+MQIUXLwPctp2pnwEgpNvoIolNWkXVA8zMQq7AXXp5wg0xOwcNTAyLjVhZYYe8Mz1EN/U68IMvt" +
            "m9CFYJUKnZVkM11iio7cwaUHCfW06TiqCOXflK3u19QR3gOCJHmz9G7i6ScozBjsE2q/x2PHVKXs7tDQ7XClcOlZv3gkzZdC" +
            "O4qT1nCkweTvvk/ohwIDAQABoz0wOzAaBgNVHREEEzARgglsb2NhbGhvc3SHBH8AAAEwHQYDVR0OBBYEFATAoMmbJUdXoPV/" +
            "slOMHMxDGzqAMA0GCSqGSIb3DQEBCwUAA4IBAQAicBfEV0/wPwrtFWaYt3PwYvx7M9CQ4KHfpwfXrVz0AFihAvyGuib+Gv0L" +
            "0HZD9QADTt++wspr6FQHf64e09y0moM88Q+C03w6nUPNQTxitBJB7PI6YCb1piRvGtNIGpatc42Ngq3Urp8teApKLOtLYwiJ" +
            "ZdPlfweGm6acNiB0aU2Y6BHvxXR6cUDmcA0NBhNOYQHkGtW7pegVkjnXAvfswXY+V0I4WGXQL6TDhl1OUclUYxSryzi9m7we" +
            "9GTGrNtlXlbgynD34yUVjfco1JGhjaWoWPoEFXCYmOhbsN5j0Rb/zxDMBmn5fyjxnxO7czWqwGgeu+YfqFSTpfQORqPLPFX+" +
            "VcZ7QholALogzJQqRzcU0wg=";

    private static final char[] TEST_PASSWORD = "vinix-test".toCharArray();

    private static int defaultIssuers() throws Exception {
        TrustManagerFactory factory = TrustManagerFactory.getInstance(
                TrustManagerFactory.getDefaultAlgorithm());
        factory.init((KeyStore) null);
        int count = 0;
        for (TrustManager manager : factory.getTrustManagers()) {
            if (manager instanceof X509TrustManager) {
                count += ((X509TrustManager) manager).getAcceptedIssuers().length;
            }
        }
        if (count == 0) throw new AssertionError("default JSSE trust store is empty");
        return count;
    }

    private static void rejectUntrustedLocal() throws Exception {
        KeyStore keys = KeyStore.getInstance("JKS");
        keys.load(new ByteArrayInputStream(Base64.getDecoder().decode(UNTRUSTED_KEYSTORE)),
                TEST_PASSWORD);
        X509Certificate certificate = (X509Certificate) keys.getCertificate("untrusted-local");
        certificate.checkValidity();
        certificate.verify(certificate.getPublicKey());
        KeyManagerFactory managers = KeyManagerFactory.getInstance(
                KeyManagerFactory.getDefaultAlgorithm());
        managers.init(keys, TEST_PASSWORD);
        SSLContext context = SSLContext.getInstance("TLS");
        context.init(managers.getKeyManagers(), null, null);
        SSLServerSocket listener = (SSLServerSocket) context.getServerSocketFactory()
                .createServerSocket(0, 1, InetAddress.getByName("127.0.0.1"));
        listener.setSoTimeout(5000);
        AtomicBoolean accepted = new AtomicBoolean();
        AtomicReference<Throwable> serverFailure = new AtomicReference<>();
        Thread server = new Thread(() -> {
            try (SSLSocket socket = (SSLSocket) listener.accept()) {
                accepted.set(true);
                socket.setSoTimeout(5000);
                socket.startHandshake();
            } catch (IOException expectedAlert) {
                serverFailure.set(expectedAlert);
            } catch (Throwable failure) {
                serverFailure.set(failure);
            }
        }, "untrusted-TLS-fixture");
        server.setDaemon(true);
        server.start();
        boolean rejected = false;
        try (SSLSocket client = (SSLSocket) SSLContext.getDefault().getSocketFactory()
                .createSocket("127.0.0.1", listener.getLocalPort())) {
            client.setSoTimeout(5000);
            SSLParameters parameters = client.getSSLParameters();
            parameters.setEndpointIdentificationAlgorithm("HTTPS");
            client.setSSLParameters(parameters);
            try {
                client.startHandshake();
                throw new AssertionError("self-signed localhost certificate was trusted");
            } catch (SSLHandshakeException expected) {
                String reason = expected.toString().toLowerCase(java.util.Locale.ROOT);
                for (Throwable cause = expected.getCause(); cause != null; cause = cause.getCause()) {
                    reason += " " + cause.toString().toLowerCase(java.util.Locale.ROOT);
                }
                if (!reason.contains("certificate") && !reason.contains("certpath")
                        && !reason.contains("pkix") && !reason.contains("trust anchor")) {
                    throw new AssertionError("local handshake failed without certificate rejection", expected);
                }
                rejected = true;
                System.out.println("ANDROID-TLS-UNTRUSTED local=rejected reason=" + expected);
            }
        } finally {
            listener.close();
            server.join(7000);
        }
        if (!rejected || !accepted.get() || server.isAlive()) {
            throw new AssertionError("local TLS rejection fixture did not finish");
        }
        if (serverFailure.get() != null && !(serverFailure.get() instanceof IOException)) {
            throw new AssertionError("local TLS server failed", serverFailure.get());
        }
    }

    private static int publicHttps(String address) throws Exception {
        URL url = new URL(address);
        if (!url.getProtocol().equals("https")) throw new IllegalArgumentException("HTTPS required");
        HttpsURLConnection connection = (HttpsURLConnection) url.openConnection();
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(10000);
        connection.setInstanceFollowRedirects(false);
        try {
            int status = connection.getResponseCode();
            if (status < 100 || status > 599 || connection.getServerCertificates().length == 0
                    || connection.getCipherSuite() == null) {
                throw new AssertionError("public HTTPS response lacks verified TLS session");
            }
            System.out.println("ANDROID-TLS-PUBLIC host=" + url.getHost() + " status=" + status
                    + " cipher=" + connection.getCipherSuite());
            return status;
        } finally {
            connection.disconnect();
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length > 1) throw new IllegalArgumentException("optional HTTPS URL only");
        int issuers = defaultIssuers();
        System.out.println("ANDROID-TLS-TRUST issuers=" + issuers);
        rejectUntrustedLocal();
        int status = publicHttps(args.length == 1 ? args[0] : "https://clientsettingscdn.roblox.com/");
        System.out.println("ANDROID-TLS-PASS issuers=" + issuers + " provider="
                + SSLContext.getDefault().getProvider().getName() + " public-status=" + status
                + " untrusted-local=rejected");
    }
}
