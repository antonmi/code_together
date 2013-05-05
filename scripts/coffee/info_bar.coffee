class window.InfoBar
  constructor: (@$info_bar, @room) ->
    @max_lines = 5

  report: (message) ->
    if @$info_bar.find('div').length >= @max_lines
      @$info_bar.find('div').first().remove()
    @$info_bar.append("<div>#{@current_time()} : #{message}</div>")

  message_received: (message) ->
    @report(message)


  current_time: ->
    d = new Date()
    @build_time_string(d)

  build_time_string: (d) ->
    hours = d.getHours()
    hours = "0#{hours}" if hours < 10
    mins = d.getMinutes()
    mins = "0#{mins}" if mins < 10
    secs = d.getSeconds()
    secs = "0#{secs}" if secs < 10
    "#{hours}:#{mins}:#{secs}"
