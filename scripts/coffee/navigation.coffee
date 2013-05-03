$ ->
  $('#go_button').on 'click', ->
    room_id = $('#room_id').val()
    user_id = $('#user_id').val()
    if room_id && user_id
      window.room = new Room('ws:localhost:9090', room_id, user_id)
