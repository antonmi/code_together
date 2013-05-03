module WebSocketServer

  class << self

    def message_received(message, ws)
      message = JSON.parse(message)
      if message.has_key?('credentials')
        credentials = message['credentials']
        Room.find_or_create_room(credentials, ws)
      end
    rescue
      puts "Error in Server message_received: #{message}"
    end

    def start!
      EM.epoll
      EM.run do
        puts 'Starting WebSocket Server'
        run
      end
    end

    def run
      EM::WebSocket.run(host: SERVER_HOST, port: SERVER_PORT) do |ws|
        ws.onopen { puts 'Connection opened' }
        ws.onmessage { |message| message_received(message, ws) }
      end
      statistic
    end

    def statistic
      EM::PeriodicTimer.new(10) { puts Room.statistic }
    end

  end

end