## Nim-LibP2P
## Copyright (c) 2019 Status Research & Development GmbH
## Licensed under either of
##  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
##  * MIT license ([LICENSE-MIT](LICENSE-MIT))
## at your option.
## This file may not be copied, modified, or distributed except according to
## those terms.

import chronos, chronicles
import ../protocols/protocol,
       ../connection,
       ../errors

logScope:
  topic = "Muxer"

type
  StreamHandler* = proc(conn: Connection): Future[void] {.gcsafe.}
  MuxerHandler* = proc(muxer: Muxer): Future[void] {.gcsafe.}

  Muxer* = ref object of RootObj
    streamHandler*: StreamHandler
    connection*: Connection

  # user provider proc that returns a constructed Muxer
  MuxerConstructor* = proc(conn: Connection): Muxer {.gcsafe, closure.}

  # this wraps a creator proc that knows how to make muxers
  MuxerProvider* = ref object of LPProtocol
    newMuxer*: MuxerConstructor
    streamHandler*: StreamHandler # triggered every time there is a new stream, called for any muxer instance
    muxerHandler*: MuxerHandler # triggered every time there is a new muxed connection created

# muxer interface
method newStream*(m: Muxer, name: string = "", lazy: bool = false):
  Future[Connection] {.base, async, gcsafe.} = discard
method close*(m: Muxer) {.base, async, gcsafe.} = discard
method handle*(m: Muxer): Future[void] {.base, async, gcsafe.} = discard

proc newMuxerProvider*(creator: MuxerConstructor, codec: string): MuxerProvider {.gcsafe.} =
  new result
  result.newMuxer = creator
  result.codec = codec
  result.init()

method init(c: MuxerProvider) =
  proc handler(conn: Connection, proto: string) {.async, gcsafe, closure.} =
    let
      muxer = c.newMuxer(conn)

    if not isNil(c.streamHandler):
      muxer.streamHandler = c.streamHandler

    var futs = newSeq[Future[void]]()

    futs &= muxer.handle()

    # finally await both the futures
    if not isNil(c.muxerHandler):
      futs &= c.muxerHandler(muxer)

    # log and re-raise on errors
    futs = await allFinished(futs)
    checkFutures(futs)

  c.handler = handler
