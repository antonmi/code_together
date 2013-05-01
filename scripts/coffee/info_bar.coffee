class window.InfoBar
  constructor: (@$info_bar, @room) ->

  report: (message) ->
    if @$info_bar.find('div').length > 4
      @$info_bar.find('div').first().remove()
    @$info_bar.append("<div>#{@current_time()} : #{message}</div>")

  current_time: ->
    d = new Date()
    "#{d.getHours()}:#{d.getMinutes()}:#{d.getSeconds()}"
