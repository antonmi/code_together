class Room

  attr_reader :channel
  attr_accessor :users, :id, :editor_text, :chat_messages
  attr_reader :in_progress

  def initialize(room_id, room = {})
    @id = room['id'] || room_id
    @users = {}
    @editor_text = room['editor_text'] || DEFAULT_EDITOR_TEXT
    @chat_messages = room['chat_messages'] || []
    @channel = EM::Channel.new
    self.class.rooms.merge!(@id => self)
  end

  def add_user(user_id, ws, info)
    user = User.new(ws, self, info)
    @users.merge!(user_id => user)
  end

  def to_hash
    hash = {}
    STORED_ATTRS.each do |attr|
      hash.merge!(attr => instance_variable_get("@#{attr}"))
    end
    hash
  end

  def size
    JSON.dump(to_hash).size
  end

  def start!
      @in_progress = true
  end

  def stop!
    @in_progress = false
  end


  class << self

    def rooms
      @rooms ||= {}
    end

    def find_or_create_room(credentials, ws, info)
      room_id = credentials['room_id']
      if room = rooms[room_id]
        user_id = credentials['user_id']
        room.add_user(user_id, ws, info)
      else
        room = Room.new(room_id, {})
        user_id = credentials['user_id']
        room.add_user(user_id, ws, info)
      end
    end

    def statistic
      stats = '='*50 + "\n"
      stats << "Rooms total: #{rooms.keys.count}\n"
      rooms.each do |room_id, value|
        stats << "#{room_id}: #{value.users.keys.join(', ')}\n"
      end
      stats << '='*50 + "\n"
      stats
    end
  end

  EM::PeriodicTimer.new(10) do
    puts statistic
  end
end