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
      window.room = new Room('ws:178.159.244.149:9090', room_id, user_id)
#      window.room = new Room('ws:localhost:9090', room_id, user_id)
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
