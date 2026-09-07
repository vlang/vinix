package main

/*
static int vinix_add(int left, int right) {
	return left + right;
}
*/
import "C"

import "fmt"

func main() {
	if got := int(C.vinix_add(19, 23)); got != 42 {
		panic(fmt.Sprintf("cgo returned %d, want 42", got))
	}
	fmt.Println("VINIX CGO SMOKE PASS")
}
