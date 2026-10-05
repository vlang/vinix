#!/usr/bin/env python3
"""Build a focus-ordering DEX probe against Meson's actual ATL framework classes.

Run the output separately with ART and the corresponding installed ATL DEX
framework on its classpath. Constructor-free observing views isolate inflation
from GTK; a fixture-only logging adapter avoids initializing ATL's JNI logger.
No fixture classes belong in an application or in the runtime overlay.
"""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tempfile
import zipfile

R8_SHA256 = "900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199"
CORE_SHA256 = "f47736d9d410766a20ae1f60d679607d8e85241e8cdeb5a0c040ab260ba68f42"


def archive_classes(source: Path, output: Path) -> None:
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(source.rglob("*.class")):
            entry = zipfile.ZipInfo(path.relative_to(source).as_posix(), (1980, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o644 << 16
            archive.writestr(entry, path.read_bytes())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--framework-classes", type=Path, required=True,
                        help="Meson output/src/api-impl/hax.jar, not the installed DEX JAR")
    parser.add_argument("--stub-classes", type=Path, required=True,
                        help="Meson output/src/gstub/gstub.jar")
    parser.add_argument("--core-classes", type=Path, default=Path("/usr/lib/java/core-all_classes.jar"))
    parser.add_argument("--r8", type=Path, required=True)
    parser.add_argument("--javac", default="javac")
    parser.add_argument("--java", default="java")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    for path, expected in ((args.r8, R8_SHA256), (args.core_classes, CORE_SHA256)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            parser.error(f"pinned compiler input checksum mismatch: {path}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="layout-focus-", dir=args.output.parent) as temporary:
        scratch = Path(temporary)
        classes = scratch / "classes"
        classes.mkdir()
        logger = scratch / "Log.java"
        logger.write_text("""package android.util;
// Fixture-only logging adapter; parser and focus behavior use the actual framework.
public final class Log {
    public static int println_native(int buffer, int priority, String tag, String message) { return 0; }
    public static String getStackTraceString(Throwable error) { return error.toString(); }
}
""")
        classpath = ":".join(str(path.resolve()) for path in (
            args.framework_classes, args.stub_classes, args.core_classes))
        subprocess.run([args.javac, "-source", "1.8", "-target", "1.8", "-classpath", classpath,
                        "-d", str(classes), str(logger),
                        str(Path(__file__).with_name("AndroidLayoutFocusProbe.java"))], check=True)
        program = scratch / "probe-classes.jar"
        archive_classes(classes, program)
        dex = scratch / "dex"
        dex.mkdir()
        subprocess.run([args.java, "-cp", str(args.r8.resolve()), "com.android.tools.r8.D8",
                        "--release", "--min-api", "26", "--android-platform-build",
                        "--force-passthrough-assertions", "--lib", str(args.core_classes.resolve()),
                        "--lib", str(args.framework_classes.resolve()),
                        "--lib", str(args.stub_classes.resolve()),
                        "--output", str(dex), str(program)], check=True)
        entry = zipfile.ZipInfo("classes.dex", (1980, 1, 1, 0, 0, 0))
        entry.compress_type = zipfile.ZIP_DEFLATED
        entry.external_attr = 0o644 << 16
        with zipfile.ZipFile(args.output, "w") as output:
            output.writestr(entry, (dex / "classes.dex").read_bytes())
    print(f"Built separate layout-focus probe: {args.output}")


if __name__ == "__main__":
    main()
