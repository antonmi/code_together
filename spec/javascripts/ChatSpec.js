describe('Chat', function() {
    var room;
    var chat;

    beforeEach(function(){
        room = new Room('ws:localhost:9090', 'test_room', 'test_user');
        chat = room.chat;
    });

    describe('after initialize actions', function(){
        it('should contain html elements', function(){
            expect(chat.$chat_div).toContain('div.chat_table');
            expect(chat.$chat_div).toContain('#chat_form');
            expect(chat.$chat_div).toContain('textarea.new_message');
        });

        it('should init elements', function(){
            expect(chat.$chat_table).toBe('.chat_table');
            expect(chat.$form).toBe('#chat_form');
            expect(chat.$input).toBe('textarea.new_message');
        });

        it('should init history', function(){
            expect(chat.history).toEqual([]);
            expect(chat.history_cursor).toEqual(1);
            expect(chat.showing_history).toEqual(false);
        });
    });



    describe('send and receive messages', function(){
        it('should send message', function(){
            spyOn(room, 'send_chat_message');
            chat.$input.val('test_message');
            chat.$form.submit();
            expect(room.send_chat_message).toHaveBeenCalled();
        });

        it('should show new message', function(){
            message = { 'text': 'hello world', 'user_id': 'test_user' };
            chat.message_received(message);
            expect(chat.$chat_div).toContainText('test_user');
            expect(chat.$chat_div).toContainText('hello world');
        });

        it('should add message to history', function(){
            room.user_id = 'test_user';
            message = { 'text': 'hello world', 'user_id': 'test_user' };
            chat.message_received(message);
            expect(chat.history).toEqual(['hello world']);
        });
    });

    describe('chat history', function(){
        beforeEach(function(){
            room.user_id = 'test_user';
            message = { 'text': 'hello1', 'user_id': 'test_user' };
            chat.message_received(message);
            message = { 'text': 'hello2', 'user_id': 'test_user' };
            chat.message_received(message);
            message = { 'text': 'hello3', 'user_id': 'test_user' };
            chat.message_received(message);
        });

        it('should remember all messages', function(){
            expect(chat.history).toEqual(['hello1', 'hello2', 'hello3']);
            expect(chat.history_cursor).toEqual(3);
        });

        it('should get previous messages', function(){
            e = { keyCode: 38 };
            chat.show_history(e);
            expect(chat.$input.val()).toEqual('hello3');
            chat.show_history(e);
            expect(chat.$input.val()).toEqual('hello2');
        });

        it('should get next messages', function(){
            e = { keyCode: 38 };
            chat.show_history(e);
            chat.show_history(e);
            e = { keyCode: 40 };
            chat.show_history(e);
            expect(chat.$input.val()).toEqual('hello3');
        })


    });
});