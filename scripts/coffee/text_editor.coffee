class window.TextEditor
  constructor: (@ckeditor, @room) ->
    @dmp = new diff_match_patch
    @default_text = "test" #duplicate in room_server/config
    @old_old_text = @default_text
    @max_size = 50000 #duplicate in room_server/config
    @can_send = true
    window.te = @
    window.ck = @ckeditor
    @init_code_mirror()
    @editor.setValue(@default_text)
    @config_callbacks()

  init_code_mirror: ->
    @editor = CodeMirror.fromTextArea(document.getElementById("texteditor"), {
      mode: "text/x-ruby",
      indentUnit: 2
    })
    window.editor = @editor

  config_callbacks: ->
    @get_new_text_callback = =>
      @send_text()
    @force_get_new_text_callback = =>
      @send_text(true)
    @one_more_time_get_new_text_callback = =>
      @send_text(false, true)
    @editor.on 'change', @get_new_text_callback

  get_text: ->
    @editor.getValue().substr(0, @max_size)

  send_text: (force = false, one_more_time = false) ->
    @new_text = @get_text()
    if (force || one_more_time || @new_text != @old_old_text) && @can_send
      console.log 'SENDING'
      window.clearTimeout(@one_more_time_update_timeout) if @one_more_time_update_timeout
      message = { 'get_text': @new_text }
      message['force'] = 'true' if force
      @old_old_text = @new_text
      @can_send = false
      @send_message(message)
      unless (one_more_time || force)
        @one_more_time_update_timeout = window.setTimeout(@one_more_time_get_new_text_callback, 1010)

  send_message: (message) ->
    @room.send_text_editor_message(message)

  message_received: (message) ->
    if message['new_text'] != undefined
      if message['history'] == 'true'
        @editor.setValue(message['new_text'])
      else
        @set_text(message['new_text'])
    if message['run_update']
      if message['user_id'] != @room.user_id
        @send_text(true)

  set_text: (text) ->
    @editor.setCursor(@editor.getCursor()) #should deselect
    @editor.replaceSelection('`|~')
    @old_text = @get_text()
    @merge_texts(text)
    @editor.setValue(@new_text)
    @return_cursor()
    @old_old_text = @get_text()
    @can_send = true

  merge_texts: (text) ->
    diff = @dmp.diff_main(@old_old_text, text, true)
    patch_list = @dmp.patch_make(@old_old_text, text, diff)
    @new_text = @dmp.patch_apply(patch_list, @old_text)[0]

  return_cursor: ->
    c = @editor.getSearchCursor('`|~')
    if c.findNext()
      from = c.from()
      to = c.to()
      c.replace('')
      @editor.setCursor(from)