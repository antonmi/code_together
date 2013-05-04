require 'spec_helper'

describe WebSocketServer do

  context 'basic init' do

    it "should start!" do
      EM.should_receive(:epoll)
      EM.should_receive(:run)
      WebSocketServer.start!
    end

    it 'should start websocket server' do
      EM.run do
        EM::WebSocket.should_receive(:run).with(host: SERVER_HOST, port: SERVER_PORT)
        WebSocketServer.run
        EM.stop
      end
    end

  end

  context 'message_received' do

    let(:ws) { double }
    it 'should check creds and call find_or_create' do
      creds = { 'room_id' => 'test', 'user_id' => 'test'}
      creds_dump = JSON.dump('credentials' => creds)
      Room.should_receive(:find_or_create_room).with(creds, ws)
      WebSocketServer.message_received(creds_dump, ws)
    end

    it 'should rescue silently wrong message' do
      Room.should_not_receive(:find_or_create_room)
      WebSocketServer.message_received('wrong creds', ws)
    end

  end

end