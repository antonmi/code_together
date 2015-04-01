// Generated by CoffeeScript 1.4.0
(function() {

  window.Chat = (function() {

    Chat.chat_html = function() {
      var html;
      html = "<h3>Chat</h3><div class='chat_table'></div>";
      html += "<form id='chat_form' class='chat_form'>";
      html += "<textarea rows='1' class='new_message'></textarea>";
      html += "<div><button type='submit' class='btn btn-small btn-warning send_message'>Send</button></div></form>";
      return html;
    };

    function Chat($chat_div, room) {
      this.$chat_div = $chat_div;
      this.room = room;
      this.add_html();
      this.init_elements();
      this.init_history();
      this.init_actions();
    }

    Chat.prototype.add_html = function() {
      return this.$chat_div.html(Chat.chat_html());
    };

    Chat.prototype.init_elements = function() {
      this.$chat_table = this.$chat_div.find('.chat_table');
      this.$form = this.$chat_div.find('#chat_form');
      return this.$input = this.$chat_div.find('.new_message');
    };

    Chat.prototype.init_history = function() {
      this.history = [];
      this.history_cursor = 1;
      return this.showing_history = false;
    };

    Chat.prototype.init_actions = function() {
      var _this = this;
      this.$form.on('submit', function(e) {
        e.preventDefault();
        if (_this.$input.val().length) {
          _this.send_message(_this.$input.val());
          _this.$input.val('').trigger('update');
        }
        return false;
      });
      return this.$input.keydown(function(e) {
        return _this.process_keydown(e);
      });
    };

    Chat.prototype.send_message = function(message) {
      return this.room.send_chat_message(message);
    };

    Chat.prototype.message_received = function(message) {
      var text, user;
      if (message['user_id'] === this.room.user_id) {
        this.history.push(message['text']);
        this.history_cursor = this.history.length;
        this.showing_history = false;
      }
      user = message['user_id'];
      text = message['text'];
      this.append_to_chat(user, text);
      if (!message['history']) {
        $('#chat_div').show();
      }
      return this.$chat_table.scrollTop(this.$chat_table[0].scrollHeight);
    };

    Chat.prototype.append_to_chat = function(user, text) {
      var $div;
      $div = $("<div class='message'><span class='user'></span>&nbsp<span class='text'></span></div>");
      $div.find('.user').html("" + user + ":");
      $div.find('.text').html(text);
      return this.$chat_table.append($div);
    };

    Chat.prototype.process_keydown = function(e) {
      if (e.keyCode === 13 && !e.shiftKey) {
        this.$form.trigger('submit');
        e.preventDefault();
      }
      if ((e.keyCode === 38 || e.keyCode === 40) && (this.showing_history || this.$input.val() === '')) {
        this.show_history(e);
        return e.preventDefault();
      }
    };

    Chat.prototype.show_history = function(e) {
      if (e.keyCode === 38 && this.history_cursor > 0) {
        this.history_cursor -= 1;
      }
      if (e.keyCode === 40 && this.history_cursor < this.history.length) {
        this.history_cursor += 1;
      }
      this.$input.val(this.history[this.history_cursor]);
      if (e.keyCode === 40 && this.history_cursor === this.history.length) {
        this.$input.val('');
      }
      return this.showing_history = true;
    };

    return Chat;

  })();

}).call(this);
