require 'diff_patch_match'
class User

  attr_accessor :id, :editor_text, :status

  def initialize(ws, room, info)
    @joined_at = Time.now.utc
    @id = info['user_id']
    @room = room
    @ws = ws
    @dpm = DiffPatchMatch.new
    @editor_text = DEFAULT_EDITOR_TEXT
    init_ws_actions
    subscribe_to_channel(room.channel)
    get_history
  end

  def to_hash
    {joined_at: @joined_at, name: @name} #and other information
  end

  def init_ws_actions
    @ws.onmessage do |message|
      begin
        message = JSON.parse(message) #rescue exception
      rescue
        message = {}
      end
      begin
        if message['chat']
          message['chat']['text'] = sanitize_chat_text(message['chat']['text'])
          message['chat'].merge!('user_id' => @id)
          @room.channel.push(JSON.dump(message))
          @room.chat_messages << message['chat']
        elsif message['text_editor']
          if message['text_editor']['get_text']
            text = message['text_editor']['get_text']
            update_editor_texts(text)
            message['text_editor'].delete('get_text')
            message['text_editor'].merge!('new_text' => @room.editor_text)
            message['text_editor'].merge!('user_id' => @id)
            @ws.send(JSON.dump(message))
            unless message['text_editor']['force']
              message['text_editor'].delete('new_text')
              message['text_editor'].merge!('run_update' => 'true')
              @room.channel.push(JSON.dump(message))
            end
          end
        end
      rescue Exception => e
        puts "Exception! #{e}"
      end
    end

    @ws.onerror { puts 'Error' }
    @ws.onclose { puts "Closed by #{id}" }
  end


  require 'sanitize'

  def sanitize_chat_text(text)
    text =~ /\b(http(s)?:[^\s]+)\b/
    text.gsub!(/\b(http(s)?:[^\s]+)\b/, "<a href='#{$1}' target='_blank'>#{$1}</a>")
    Sanitize.clean(text, elements: ['a'], attributes: {'a' => ['href', 'target']})
  end

  def update_editor_texts(text)
    text = text[0..EDITOR_TEXT_MAX_SIZE]
    diff = @dpm.diff_main(@editor_text, text)
    patch_list = @dpm.patch_make(@editor_text, text, diff)
    @room.editor_text = @dpm.patch_apply(patch_list, @room.editor_text).first
    @editor_text = @room.editor_text
  end

  def force_set_texts(text)
    text = text[0..EDITOR_TEXT_MAX_SIZE]
    @room.editor_text = text
    @room.users.values.each do |user|
      user.editor_text = text
    end
  end

  def subscribe_to_channel(channel)
    channel.subscribe do |message|
      @ws.send(message)
    end
  end

  def get_history
    @ws.send(JSON.dump(text_editor_history_message))
    @room.chat_messages.each { |m| @ws.send(JSON.dump({'chat' => m.merge!('history' => 'true')})) }
  end

  def text_editor_history_message
    @editor_text = @room.editor_text
    message = { 'text_editor' => {} }
    message['text_editor'].merge!('history' => 'true')
    message['text_editor'].merge!('new_text' => @room.editor_text)
    message
  end

end