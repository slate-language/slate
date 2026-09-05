# `slate:llhttp`

The HTTP parser itself — the state machine under [`slate:http`](http.md).

```slate
import { httpParser, httpFeed, httpTake } from slate:llhttp
```

`httpParser  httpStream  httpFeed  httpTake  httpTakePart  httpFinish  httpClose  httpUpgraded`

**This is the lowest module slate has, and it is public on purpose.** `slate:http` is the server a program
wants; this is for the programs that want something else — a proxy, a client that keeps its connections, a
test double that has to answer exactly the bytes it was asked about, or a protocol that begins as HTTP and
then stops being it. **Every one of those is an ordinary package**, where otherwise it would have been a
change to slate.

**Node hid the same seam and its own client had to route around it**: undici carries llhttp compiled to
wasm because `internalBinding('http_parser')` is not reachable. Two parsers in one process is the cost of
that policy.

**The names keep their `http` prefix** rather than being shortened to fit the module. They are the seam
`slate:http` is written against and they are spelled this way inside it, so a reader moving between the
module's source and a package that uses the same calls sees one vocabulary.

**Under [`slate js`](../reference/javascript.md) the grammar is written out rather than bound**, node's
own parser being unreachable from a program — which is the seam node hid and the reason undici carries
llhttp compiled to wasm. The two readings answer the same things about the same bytes, which is what
`tests/js/p26.sl` is for; a browser has no sockets to read from and every name refuses there.
