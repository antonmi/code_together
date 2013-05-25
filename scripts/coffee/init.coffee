$ ->

  show_room = ->
    $('#no_room').hide()
    $('#content').show()
    $('#sidebar').show()

  hide_room = ->
    $('#no_room').show()
    $('#content').hide()
    $('#sidebar').hide()

  ids = window.location.hash.split('#')
  if ids.length == 3
    user_id = ids.pop().replace('user_id=', '')
    room_id = ids.pop().replace('room_id=', '')
    $('#room_id').val(room_id)
    $('#user_id').val(user_id)
    if room_id && user_id
#      window.room = new Room('ws:185.4.65.79:9090', room_id, user_id)
#      window.room = new Room('ws:127.0.0.1:9090', room_id, user_id)
      window.room = new Room('ws:thawing-garden-2267.herokuapp.com:5000', room_id, user_id)
      show_room()
  else
    hide_room()

  $('#go_form').on 'submit', ->
    room_id = $('#room_id').val()
    user_id = $('#user_id').val()
    if room_id && user_id
      window.location.href = window.location.origin + window.location.pathname + "#room_id=#{room_id}#user_id=#{user_id}"
      window.location.reload()
    false
