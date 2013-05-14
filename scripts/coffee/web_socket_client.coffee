class window.WebSocketClient extends WebSocket
  constructor: (@uri, @room, @post_connected_actions) ->
    @connect(@post_connected_actions)

  connect: (@post_connected_actions) ->
    #console.log "Connecting to #{@uri}"
    @ws = new WebSocket(@uri);

    @ws.onopen = =>
      @post_connected_actions?()
      @room.connection_established()

    @ws.onerror = =>
      @room.connection_lost()

    @ws.onclose = =>
      @room.connection_lost()

    @ws.onmessage = (message) =>
      message = JSON.parse(message.data)
      @room.message_received(message)

  send_message: (message) ->
    str = JSON.stringify(message)
    @ws.send(str)
