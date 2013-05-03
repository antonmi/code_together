require 'spec_helper'

describe Room do

  let(:creds) { { 'room_id' => 'test', 'user_id' => 'test'} }
  let(:ws) { double }
  let(:room) { double }

  context 'class methods' do

    it 'should create new room and add user' do
      Room.stub(:new).and_return(room)
      room.should_receive(:add_user).with('test', ws, creds)
      Room.find_or_create_room(creds, ws)
    end

    it 'should find room in rooms and add user' do
      Room.rooms.merge!('test' => room)
      Room.should_not_receive(:new)
      room.should_receive(:add_user).with('test', ws, creds)
      Room.find_or_create_room(creds, ws)
    end

    it 'should create new room' do
      room = Room.new('test')
      expect(room.id).to eq('test')
      expect(room.users).to eq({})
      expect(room.editor_text).to eq(DEFAULT_EDITOR_TEXT)
      expect(room.chat_messages).to eq([])
      expect(room.channel).to be_an_instance_of(EM::Channel)
      expect(Room.rooms.keys).to include('test')
    end
  end

  context 'instance methods' do

    it 'should add user to room' do
      room = Room.new('test')
      User.should_receive(:new).with(ws, room, creds)
      room.add_user('test', ws, creds)
      expect(room.users.keys).to include('test')
    end

  end

end