// SPDX-License-Identifier: GPL-2.0-or-later
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/** Exercise platform Java lambdas that previously failed during APK startup. */
public final class ArtBootProbe {
    public static void main(String[] args) {
        String date = LocalDate.parse("2026-10-03", DateTimeFormatter.ISO_LOCAL_DATE)
                .format(DateTimeFormatter.ISO_LOCAL_DATE);
        String epoch = DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ssXXX", Locale.ROOT)
                .withZone(ZoneOffset.UTC).format(Instant.EPOCH);
        String ordered = Stream.of("2026-10-03", "1970-01-01")
                .map(LocalDate::parse).sorted().map(DateTimeFormatter.ISO_LOCAL_DATE::format)
                .collect(Collectors.joining("|"));
        if (!date.equals("2026-10-03") || !epoch.equals("1970-01-01T00:00:00Z")
                || !ordered.equals("1970-01-01|2026-10-03")) {
            throw new AssertionError("platform date/time or stream result differs");
        }
        System.out.println("ANDROID-BOOTCLASSPATH-PASS date=" + date + " epoch=" + epoch
                + " ordered=" + ordered);
    }
}
