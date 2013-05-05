describe('Room', function() {
    var room;

    beforeEach(function(){
       room = new Room('ws:localhost:9090', 'test_room', 'test_user');
    });

    it('should define room parts', function(){
       expect(room.info_bar).toBeDefined();
       expect(room.chat).toBeDefined();
       expect(room.text_editor).toBeDefined();
       expect(room.ws_client).toBeDefined();
    });

    describe('proxy messages', function(){
        beforeEach(function(){
           spyOn(room.ws_client, 'send_message');
        });

        it('should sent chat message', function(){
           room.send_chat_message('hello');
            message = {chat: {'text': 'hello'} };
            expect(room.ws_client.send_message).toHaveBeenCalledWith(message)
        });

        it('should sent text_editor message', function(){
            room.send_text_editor_message('hello');
            message = { 'text_editor': 'hello' };
            expect(room.ws_client.send_message).toHaveBeenCalledWith(message)
        });

        it('should call message received on chat', function(){
            spyOn(room.chat, 'message_received');
            message = { 'chat': 'hello' };
            room.message_received(message);
            expect(room.chat.message_received).toHaveBeenCalledWith('hello')
        });

        it('should call message received on text_editor', function(){
            spyOn(room.text_editor, 'message_received');
            message = { 'text_editor': 'hello' };
            room.message_received(message);
            expect(room.text_editor.message_received).toHaveBeenCalledWith('hello')
        });

        it('should call message received on info_bar', function(){
            spyOn(room.info_bar, 'message_received');
            message = { 'info_bar': 'hello' };
            room.message_received(message);
            expect(room.info_bar.message_received).toHaveBeenCalledWith('hello')
        });
    })

});
