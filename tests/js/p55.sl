// `fetch`'s `reuse` option is read the same way on both back ends, before anything is dialled.
//
// **The interpreter keeps a pool and a JavaScript host keeps its own**, so `reuse: false` changes the
// transport in one and nothing a program can see in either -- which is why what can be compared here
// is the reading: a yes-or-no taken, and anything else refused at the call in one sentence. The port
// is one nothing listens on, and no request is ever made: a refused option faults before the dial.

anything(v) = v

print(fetch("http://127.0.0.1:9/", { reuse: anything("no") }) catch e -> e.message)
print(fetch("http://127.0.0.1:9/", { reuse: anything(0) }) catch e -> e.message)
