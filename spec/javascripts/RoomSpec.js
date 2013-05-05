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

});
