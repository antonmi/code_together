class window.Room
  constructor: (@uri, @room_id, @user_id) ->
    @info_bar = new InfoBar($('#info_bar_div'), @)
    @report 'Initializing'
    @credentials = { room_id : @room_id, user_id : @user_id }
    @chat = new Chat($('#chat_div'), @)
    @text_editor = new TextEditor($('#texteditor'), @)
    console.log 'initializing chats'
    @ws_client = new WebSocketClient(@uri, @)
    @report 'Initialized Successfully'


  message_handelrs: ->
    { 'chat' : @chat, 'text_editor' : @text_editor }

  report: (message) ->
    @info_bar.report(message)

  connection_established: ->
    @report 'Connection Established'
    @send_credentials()

  connection_lost: ->
    @report 'Connection Lost'
    @report 'Reconnecting'
    reconnect = =>
      @ws_client.connect()
    window.clearTimeout(window.reconnect_timeout)
    window.reconnect_timeout = setTimeout(reconnect, 3000)

  send_credentials: ->
    @ws_client.send_message(credentials : @credentials)

  message_received: (message) ->
    for key, val of @message_handelrs()
      val.message_received(message[key]) if message[key]

  send_chat_message: (mes) ->
    message = { chat : { text : mes } }
    @ws_client.send_message(message)

  send_text_editor_message: (mes) ->
    message = { text_editor :  mes }
    @ws_client.send_message(message)
