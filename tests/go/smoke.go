package main

import (
	"crypto/rand"
	"crypto/sha256"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"sync"
	"time"
)

var failures []string

func check(ok bool, description string) {
	result := "ok"
	if !ok {
		result = "FAIL"
		failures = append(failures, description)
	}
	fmt.Printf("%-40s %s\n", description, result)
}

func main() {
	fmt.Println("VINIX ARM64 GO SMOKE")
	check(runtime.GOOS == "linux", "Linux-compatible Go runtime")
	check(runtime.GOARCH == "arm64", "AArch64 Go runtime")
	fmt.Printf("  [info] %s %s/%s\n", runtime.Version(), runtime.GOOS, runtime.GOARCH)

	work, err := os.MkdirTemp("/tmp", "go-smoke-")
	check(err == nil, "create temporary directory")
	if err != nil {
		os.Exit(1)
	}
	defer os.RemoveAll(work)

	path := filepath.Join(work, "file")
	err = os.WriteFile(path, []byte("hello from Go\n"), 0o600)
	check(err == nil, "write a file")
	contents, err := os.ReadFile(path)
	check(err == nil && string(contents) == "hello from Go\n", "read the file back")
	err = os.WriteFile(path, []byte("Go\n"), 0o600)
	contents, readErr := os.ReadFile(path)
	check(err == nil && readErr == nil && string(contents) == "Go\n", "truncate an existing file")
	appendFile, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0)
	if err == nil {
		_, err = appendFile.WriteString("append\n")
		closeErr := appendFile.Close()
		if err == nil {
			err = closeErr
		}
	}
	contents, readErr = os.ReadFile(path)
	check(err == nil && readErr == nil && string(contents) == "Go\nappend\n", "append to an existing file")
	renamed := path + "-renamed"
	err = os.Rename(path, renamed)
	check(err == nil, "rename the file")
	err = os.Symlink(filepath.Base(renamed), filepath.Join(work, "link"))
	check(err == nil, "create a symbolic link")
	entries, err := os.ReadDir(work)
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		names = append(names, entry.Name())
	}
	sort.Strings(names)
	check(err == nil && fmt.Sprint(names) == "[file-renamed link]", "enumerate directory entries")

	const workers = 16
	results := make(chan int, workers)
	var group sync.WaitGroup
	for i := 0; i < workers; i++ {
		group.Add(1)
		go func(value int) {
			defer group.Done()
			results <- value * value
		}(i)
	}
	group.Wait()
	close(results)
	total := 0
	for value := range results {
		total += value
	}
	check(total == 1240, "goroutines, channels, and WaitGroup")

	started := time.Now()
	<-time.After(100 * time.Millisecond)
	check(time.Since(started) >= 90*time.Millisecond, "runtime timer")

	output, err := exec.Command("/bin/busybox", "echo", "Go subprocess").Output()
	check(err == nil && string(output) == "Go subprocess\n", "fork/exec subprocess")

	digest := sha256.Sum256([]byte("vinix"))
	check(fmt.Sprintf("%x", digest) == "c83faa56c46e4b8b18498b3de9adb42192e8c6fe6f246e6b36ea50bc6d02d76f", "SHA-256 standard library")
	random := make([]byte, 32)
	_, err = rand.Read(random)
	allZero := true
	for _, value := range random {
		allZero = allZero && value == 0
	}
	check(err == nil && !allZero, "crypto/rand")

	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	check(err == nil, "TCP listener")
	if err == nil {
		done := make(chan error, 1)
		go func() {
			connection, acceptErr := listener.Accept()
			if acceptErr != nil {
				done <- acceptErr
				return
			}
			defer connection.Close()
			buffer := make([]byte, 4)
			_, acceptErr = io.ReadFull(connection, buffer)
			if acceptErr == nil && string(buffer) != "ping" {
				acceptErr = fmt.Errorf("unexpected payload %q", buffer)
			}
			done <- acceptErr
		}()

		client, dialErr := net.DialTimeout("tcp4", listener.Addr().String(), time.Second)
		if dialErr == nil {
			_, dialErr = client.Write([]byte("ping"))
			client.Close()
		} else {
			listener.Close()
		}
		serverErr := <-done
		listener.Close()
		check(dialErr == nil && serverErr == nil, "TCP loopback round trip")
	}

	if len(failures) != 0 {
		fmt.Printf("GO SMOKE FAIL (%d failures): %v\n", len(failures), failures)
		os.Exit(1)
	}
	fmt.Println("GO SMOKE PASS")
}
