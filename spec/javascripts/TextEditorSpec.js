describe('TextEditor', function() {
    var room;
    var text_editor;

    beforeEach(function(){
        room = new Room('ws:localhost:9090', 'test_room', 'test_user');
        text_editor = room.text_editor;
        CodeMirror.modes = { 'null': '', 'ruby': ''}
    });

    describe('initialization', function(){
        it('should add textarea', function(){
            expect(text_editor.$text_editor_div).toContain('textarea');
        });

        it('should add select with options', function(){
            expect(text_editor.$text_editor_div).toContain('select');
            expect(text_editor.$text_editor_div).toContainHtml("<option value='text'>text</option>");
            expect(text_editor.$text_editor_div).toContainHtml("<option value='ruby'>ruby</option>");
        });

        it('should init CodeMirror', function(){
            expect(text_editor.editor).toBeDefined();
            expect(text_editor.get_text()).toEqual(text_editor.default_text);
            expect(text_editor.editor.getOption('mode')).toEqual('text');
        });
    });

    describe('actions', function(){
        it('should change mode when select new mode', function(){
            spyOn(room, 'send_text_editor_message');
            text_editor.$select.val('ruby').change();
            expect(text_editor.editor.getOption('mode')).toEqual('ruby');
            expect(room.send_text_editor_message).toHaveBeenCalledWith({'mode': 'ruby'});
        });

        describe('send_text', function(){
            beforeEach(function(){
                spyOn(room, 'send_text_editor_message');
            });

            it('should not send (texts are equal initially)', function(){
                text_editor.send_text();
                expect(room.send_text_editor_message).not.toHaveBeenCalled();
            });

            it('should send (text was changed)', function(){
                text_editor.editor.setValue('new_text');
                expect(room.send_text_editor_message).toHaveBeenCalledWith({'get_text': 'new_text'});
            });

            it('should send (force)', function(){
                message = {'get_text': text_editor.default_text, 'force': 'true' };
                text_editor.send_text(true);
                expect(room.send_text_editor_message).toHaveBeenCalledWith(message);
            });

            it('should send (one_more_time)', function(){
                message = {'get_text': text_editor.default_text };
                text_editor.send_text(false, true);
                expect(room.send_text_editor_message).toHaveBeenCalledWith(message);
            });
        });

        describe('receive message', function(){
            beforeEach(function(){
                spyOn(room, 'send_text_editor_message');
            });

            it('should process message history', function(){
                message = {'history': 'true', 'new_text': 'hello history'};
                text_editor.message_received(message);
                expect(text_editor.get_text()).toEqual('hello history');
            });

            it('should run update', function(){
                message = {'run_update': 'true', 'user_id': 'another user'};
                text_editor.message_received(message);
                message = {'get_text': text_editor.default_text, 'force': 'true' };
                expect(room.send_text_editor_message).toHaveBeenCalledWith(message);
            });

            it('should change mode', function(){
                message = {'mode': 'ruby', 'user_id': 'another user'};
                text_editor.message_received(message);
                expect(text_editor.editor.getOption('mode')).toEqual('ruby');
                expect(text_editor.$select.val()).toEqual('ruby');
            });
        });

        describe('set_text', function(){
            beforeEach(function(){
                spyOn(room, 'send_text_editor_message');
                text_editor.editor.setValue('hello world 1');
                text_editor.old_old_text = 'hello world';
            });

            it('should set text', function(){
                text_editor.set_text('hello 2 world');
                expect(text_editor.get_text()).toEqual('hello 2 world 1')
            });
        });
    });

});