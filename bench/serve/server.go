// The Go server of the server benchmark: `net/http`.
//
//	go run bench/serve/server.go <port> [<cert.pem> <key.pem>]
//
// With a certificate it is HTTPS, and net/http negotiates h2 by ALPN on its own. The three
// endpoints are the ones in `app.sl`; the 404 and 405 texts match it too.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"sync/atomic"
)

var seq atomic.Int64

func reply(w http.ResponseWriter, status int, kind, body string) {
	w.Header().Set("Content-Type", kind)
	w.WriteHeader(status)
	io.WriteString(w, body)
}

func main() {
	port := "0"
	if len(os.Args) > 1 {
		port = os.Args[1]
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/plain", func(w http.ResponseWriter, r *http.Request) {
		reply(w, 200, "text/plain", "hello")
	})
	mux.HandleFunc("/json", func(w http.ResponseWriter, r *http.Request) {
		out, _ := json.Marshal(map[string]any{"server": "go", "seq": seq.Add(1), "ok": true, "items": []int{1, 2, 3}})
		reply(w, 200, "application/json", string(out))
	})
	mux.HandleFunc("/echo", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			reply(w, 405, "text/plain", "POST only")
			return
		}
		body, _ := io.ReadAll(r.Body)
		reply(w, 200, "text/plain", string(body))
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		reply(w, 404, "text/plain", "not found")
	})

	listener, err := net.Listen("tcp", ":"+port)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	fmt.Println("listening", listener.Addr().(*net.TCPAddr).Port)
	if len(os.Args) > 3 {
		err = http.ServeTLS(listener, mux, os.Args[2], os.Args[3])
	} else {
		err = http.Serve(listener, mux)
	}
	fmt.Println(err)
}
