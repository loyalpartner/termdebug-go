package main

import "fmt"

type Test struct {
	Name string `json:"name"`
}

func sayhello() {
	fmt.Println("hello")
}

func plus(a, b int) int {
	return a + b
}

func minus(a, b int) int {
	return plus(a, -1*b)
}

func main() {
	fmt.Println("vim-go: %v", minus(3, 1))
}
