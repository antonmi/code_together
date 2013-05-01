module WebSocketServer

  class << self

    def message_received(message, ws)
      message = JSON.parse(message)
      if message.has_key?('credentials')
        credentials = message['credentials']
        Room.find_or_create_room(credentials, ws, credentials)
      end
    rescue
      puts 'Error in Server message_received'
      puts message
      nil #just do nothing
    end


    def start!
      EM.epoll
      EM.run do
        require 'room'
        require 'user'

        puts 'Starting WebSocket Server'
        EventMachine::WebSocket.start(host: SERVER_HOST, port: SERVER_PORT) do |ws|
          ws.onopen do
            puts 'Connection opened'
          end

          ws.onmessage do |message|
            message_received(message, ws)
          end
        end
      end
    end
  end

end