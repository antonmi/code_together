class window.Chat

  @chat_html: ->
    html = "<h3>Chat</h3><div class='chat_table'></div>"
    html += "<form id='chat_form' class='chat_form'>"
    html += "<textarea rows='1' class='new_message'></textarea>"
    html += "<div><button type='submit' class='btn btn-small btn-warning send_message'>Send</button></div></form>"
    html

  constructor: (@$chat_div, @room) ->
    @add_html()
    @init_elements()
    @init_history()
    @init_actions()

  add_html: ->
    @$chat_div.html(Chat.chat_html());

  init_elements: ->
    @$chat_table = @$chat_div.find('.chat_table')
    @$form = @$chat_div.find('#chat_form')
    @$input = @$chat_div.find('.new_message')

  init_history: ->
    @history = []
    @history_cursor = 1
    @showing_history = false

  init_actions: ->
    @$form.on 'submit', (e) =>
      e.preventDefault()
      if @$input.val().length
        @send_message(@$input.val())
        @$input.val('').trigger('update')
      false
    @$input.keydown (e) =>
      @process_keydown(e)

  send_message: (message) ->
    @room.send_chat_message(message)

  message_received: (message) ->
    if message['user_id'] == @room.user_id
      @history.push(message['text'])
      @history_cursor = @history.length
      @showing_history = false
    user = message['user_id']
    text = message['text']
    @append_to_chat(user, text)
    $('#chat_div').show() unless message['history']
    @$chat_table.scrollTop(@$chat_table[0].scrollHeight)

  append_to_chat: (user, text) ->
    $div = $("<div class='message'><span class='user'></span>&nbsp<span class='text'></span></div>")
    $div.find('.user').html("#{user}:")
    $div.find('.text').html(text)
    @$chat_table.append($div)

  process_keydown: (e) ->
    if e.keyCode == 13 && !e.shiftKey
      @$form.trigger('submit')
      e.preventDefault()
    if (e.keyCode == 38 || e.keyCode == 40) && (@showing_history || @$input.val() == '')
      @show_history(e)
      e.preventDefault()

  show_history: (e) ->
    if e.keyCode == 38 && @history_cursor > 0
      @history_cursor -= 1
    if e.keyCode == 40 && @history_cursor < @history.length
      @history_cursor += 1
    @$input.val(@history[@history_cursor])
    if e.keyCode == 40 && @history_cursor == @history.length
      @$input.val('')
    @showing_history = true
