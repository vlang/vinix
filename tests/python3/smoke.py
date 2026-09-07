import hashlib
import os
import select
import socket
import subprocess
import sys
import threading
import time


failures = []


def check(condition, description):
    print("%-40s %s" % (description, "ok" if condition else "FAIL"), flush=True)
    if not condition:
        failures.append(description)


check(sys.version_info.major == 3, "interpreter is Python 3")
print("  [info] %s" % sys.version.replace("\n", " "), flush=True)

# Filesystem operations used by the import machinery and package installers.
workdir = "/tmp/python3-smoke-%d" % os.getpid()
os.makedirs(workdir, exist_ok=True)
path = os.path.join(workdir, "file")
with open(path, "w") as output:
    output.write("hello\n" * 100)
check(os.path.getsize(path) == 600, "write and stat a file")
with open(path) as source:
    check(len(source.readlines()) == 100, "read it back")
os.rename(path, path + "2")
check(os.path.exists(path + "2") and not os.path.exists(path), "os.rename")
os.symlink("file2", os.path.join(workdir, "link"))
check(os.readlink(os.path.join(workdir, "link")) == "file2", "symlink and readlink")
check(sorted(os.listdir(workdir)) == ["file2", "link"], "os.listdir")
os.truncate(path + "2", 10)
check(os.path.getsize(path + "2") == 10, "os.truncate")
check(os.statvfs("/tmp").f_bsize > 0, "os.statvfs")

# fork/exec/wait and pipe EOF are the foundation of subprocess.
read_fd, write_fd = os.pipe()
pid = os.fork()
if pid == 0:
    os.close(read_fd)
    os.write(write_fd, b"from the child")
    os._exit(3)
os.close(write_fd)
data = os.read(read_fd, 64)
_, status = os.waitpid(pid, 0)
check(data == b"from the child", "fork and pipe")
check(os.WIFEXITED(status) and os.WEXITSTATUS(status) == 3, "waitpid exit status")
os.close(read_fd)

result = subprocess.run(
    ["/bin/busybox", "echo", "subprocess works"],
    capture_output=True,
    text=True,
)
check(result.returncode == 0 and "subprocess works" in result.stdout, "subprocess.run")

# clone(CLONE_THREAD), TLS and futex wakeups.
seen = []
seen_lock = threading.Lock()


def worker(number):
    with seen_lock:
        seen.append(number)


threads = [threading.Thread(target=worker, args=(number,)) for number in range(8)]
for thread in threads:
    thread.start()
for thread in threads:
    thread.join()
check(sorted(seen) == list(range(8)), "eight threads with a lock")

wake = threading.Event()


def waiter():
    wake.wait(5)
    seen.append("woken")


thread = threading.Thread(target=waiter)
thread.start()
time.sleep(0.2)
wake.set()
thread.join()
check("woken" in seen, "threading.Event")

# select, poll and epoll readiness.
read_fd, write_fd = os.pipe()
check(select.select([read_fd], [], [], 0) == ([], [], []), "select sees nothing ready")
os.write(write_fd, b"x")
check(select.select([read_fd], [], [], 1)[0] == [read_fd], "select sees a readable pipe")
poller = select.poll()
poller.register(read_fd, select.POLLIN)
check(poller.poll(1000)[0][0] == read_fd, "select.poll")
if hasattr(select, "epoll"):
    epoll = select.epoll()
    epoll.register(read_fd, select.EPOLLIN)
    check(len(epoll.poll(1)) == 1, "select.epoll")
    epoll.close()
os.close(read_fd)
os.close(write_fd)

# Connected and pathname-based Unix sockets.
left, right = socket.socketpair()
left.send(b"ping")
check(right.recv(16) == b"ping", "socketpair round trip")
left.close()
right.close()

socket_path = os.path.join(workdir, "server.sock")
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(socket_path)
server.listen(1)
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.connect(socket_path)
connection, _ = server.accept()
client.sendall(b"over a unix socket")
check(connection.recv(64) == b"over a unix socket", "unix socket connect/accept")
client.close()
connection.close()
server.close()
os.unlink(socket_path)
check(not os.path.exists(socket_path), "unlink unix socket path")

started = time.monotonic()
time.sleep(0.3)
check(time.monotonic() - started >= 0.25, "time.sleep and monotonic")
check(time.time() > 1_000_000, "time.time")
check(os.getuid() == 0 and os.geteuid() == 0, "process credentials")
check(os.getpid() > 0, "process ID")
check(len(bytearray(1 << 20)) == 1 << 20, "allocate a megabyte")
check(len(os.urandom(32)) == 32 and os.urandom(32) != os.urandom(32), "os.urandom")

# Native extension modules and their shared-library dependencies.
for module_name in (
    "bz2",
    "ctypes",
    "datetime",
    "decimal",
    "hashlib",
    "lzma",
    "math",
    "sqlite3",
    "ssl",
    "struct",
    "zlib",
):
    try:
        __import__(module_name)
        check(True, "import " + module_name)
    except Exception as error:
        check(False, "import %s (%s)" % (module_name, type(error).__name__))

import zlib

blob = b"vinix" * 1000
check(zlib.decompress(zlib.compress(blob)) == blob, "zlib round trip")
check(len(hashlib.sha256(blob).hexdigest()) == 64, "sha256")

# Positioned I/O, seeking beyond EOF and sparse-file holes.
positioned_path = os.path.join(workdir, "positioned-io")
fd = os.open(positioned_path, os.O_CREAT | os.O_RDWR, 0o600)
os.pwrite(fd, b"SQLite format 3\0", 0)
check(os.pread(fd, 16, 0) == b"SQLite format 3\0", "positioned file I/O")
os.ftruncate(fd, 0)
os.lseek(fd, 24, os.SEEK_SET)
check(os.fstat(fd).st_size == 0 and os.read(fd, 1) == b"", "seek/read beyond EOF")
os.write(fd, b"x")
check(os.pread(fd, 25, 0) == b"\0" * 24 + b"x", "zero-filled sparse write")
os.close(fd)

import sqlite3

database_path = os.path.join(workdir, "database.sqlite")
database = sqlite3.connect(database_path)
database.execute("create table rows (number int, text text)")
database.executemany(
    "insert into rows values (?, ?)",
    [(number, "row%d" % number) for number in range(100)],
)
database.commit()
check(database.execute("select count(*) from rows").fetchone()[0] == 100, "sqlite3 insert and select")
database.close()

print(
    "PYTHON3 SMOKE %s (%d failures)" % ("FAIL" if failures else "PASS", len(failures)),
    flush=True,
)
if failures:
    print("failed: " + ", ".join(failures), flush=True)
    raise SystemExit(1)
