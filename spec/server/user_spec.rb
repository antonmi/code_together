require 'spec_helper'
require 'diff_patch_match'

describe User do

  let(:creds) { { 'room_id' => 'test_room', 'user_id' => 'test_user'} }

  before do
    @ws = double
    channel = double
    EM::Channel.stub(:new).and_return(channel)
    @room = Room.new('test_room')
  end

  context 'initialization' do

    it 'should create new user' do
      User.any_instance.should_receive(:init_ws_actions)
      User.any_instance.should_receive(:subscribe_to_channel)
      User.any_instance.should_receive(:report_connected)
      User.any_instance.should_receive(:get_history)
      user = User.new(@ws, @room, creds)
      expect(user.id).to eq('test_user')
      expect(user.instance_variable_get(:@room)).to eq(@room)
      expect(user.editor_text).to eq(DEFAULT_EDITOR_TEXT)
      expect(user.instance_variable_get(:@dpm)).to be_an_instance_of(DiffPatchMatch)
    end

    context 'init_ws_actions' do
      before do
        User.any_instance.stub(:subscribe_to_channel)
        User.any_instance.should_receive(:report_connected)
        User.any_instance.stub(:get_history)
        @ws.stub(:onerror)
        @ws.stub(:onclose)
        @ws.instance_eval do
          def onmessage(&block)
            @block = block
          end
          def block
            @block
          end
        end
      end

      it 'ws should receive on message' do
        @ws.should_receive(:onmessage)
        User.new(@ws, @room, creds)
      end

      context 'onmessage' do
        before do
          @user = User.new(@ws, @room, creds)
          @onmessage = @ws.block
        end

        it 'should parse message' do
          JSON.should_receive(:parse).with('message')
          @onmessage.call('message')
        end

        context 'chat messages' do
          before do
            @message = {'chat' => { 'text' => 'hello world'} }
            JSON.stub(:parse).and_return(@message)
            JSON.stub(:dump).and_return('dumped')
          end

          it 'should perform the following' do
            @user.should_receive(:sanitize_chat_text)
            @room.channel.should_receive(:push).with('dumped')
            @onmessage.call('test')
            expect(@message['chat']['user_id']).to eq('test_user')
            chat_message = @room.chat_messages.last
            expect(chat_message).to eq(@message['chat'])
          end
        end

        context 'text_editor messages' do
          before do
            @message = {'text_editor' => { 'get_text' => 'hello world' } }
            JSON.stub(:parse).and_return(@message)
            JSON.stub(:dump).and_return('dumped')
          end

          context 'get_text' do
            it 'should perform the following' do
              @user.should_receive(:update_editor_texts).with('hello world')
              @ws.should_receive(:send).with('dumped')
              @room.should_receive(:editor_text)
              @room.channel.should_receive(:push).with('dumped')
              @onmessage.call('test')
              expect(@message['text_editor']['get_text']).to be_nil
              expect(@message['text_editor']['user_id']).to eq('test_user')
              expect(@message['text_editor']['run_update']).to eq('true')
            end

            it 'should perform "force" actions' do
              @ws.stub(:send)
              @message['text_editor'].merge!('force' => 'true')
              @room.channel.should_not_receive(:push).with('dumped')
              @onmessage.call('test')
            end

            it 'should change mode' do
              @message = {'text_editor' => { 'mode' => 'ruby' } }
              JSON.stub(:parse).and_return(@message)
              @room.channel.should_receive(:push).with('dumped')
              @onmessage.call('test')
              expect(@message['text_editor']['user_id']).to eq('test_user')
              expect(@room.editor_mode).to eq('ruby')
            end
          end

        end
      end

    end

    context 'subscribe to channel' do
      before do
        User.any_instance.stub(:init_ws_actions)
        User.any_instance.stub(:report_connected)
        User.any_instance.stub(:get_history)
      end
      it 'should subscribe user to room channel' do
        @room.channel.should_receive(:subscribe)
        @user = User.new(@ws, @room, creds)
      end
    end

    context 'get history' do
      before do
        User.any_instance.stub(:init_ws_actions)
        User.any_instance.stub(:subscribe_to_channel)
        User.any_instance.stub(:report_connected)
        User.any_instance.stub(:text_editor_history_message).and_return('text_editor history')
      end

      it 'should send history messages' do
        @ws.should_receive(:send).with(JSON.dump('text_editor history'))
        @user = User.new(@ws, @room, creds)
      end
    end

  end

  context 'instance methods' do
    before do
      User.any_instance.stub(:subscribe_to_channel)
      User.any_instance.stub(:get_history)
      User.any_instance.stub(:init_ws_actions)
      User.any_instance.stub(:report_connected)
      @user = User.new(@ws, @room, creds)
      @room.editor_text = 'hello world 1'
      @user.editor_text = 'hello world'
      @room.users = { 'test_user' => @user }
    end

    it 'should sanitize text' do
      sanitized = @user.send(:sanitize_chat_text, 'http://hello.world')
      expect(sanitized).to eq('<a href="http://hello.world" target="_blank">http://hello.world</a>')
    end

    it 'should update editor text' do
      text = 'hello 2 world'
      @user.send(:update_editor_texts, text)
      expect(@room.editor_text).to eq('hello 2 world 1')
      expect(@user.editor_text).to eq('hello 2 world 1')
    end

    it 'should force update texts' do
      text = 'force hello world'
      @user.send(:force_set_texts, text)
      expect(@room.editor_text).to eq(text)
      expect(@user.editor_text).to eq(text)
    end

  end

end