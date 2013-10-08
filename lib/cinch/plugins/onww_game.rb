require 'cinch'
require 'yaml'

require File.expand_path(File.dirname(__FILE__)) + '/core'

module Cinch
  module Plugins

    CHANGELOG_FILE = File.expand_path(File.dirname(__FILE__)) + "/changelog.yml"

    class OnwwGame
      include Cinch::Plugin

      def initialize(*args)
        super
        @game = Game.new
 
        @changelog     = self.load_changelog

        @mods          = config[:mods]
        @channel_name  = config[:channel]
        @settings_file = config[:settings]
        @games_dir     = config[:games_dir]

        @idle_timer_length    = config[:allowed_idle]
        @invite_timer_length  = config[:invite_reset]

        @idle_timer   = self.start_idle_timer
      end

      # start
      match /join/i,             :method => :join
      match /leave/i,            :method => :leave
      match /start/i,            :method => :start_game

      # game
      #match /whoami/i,           :method => :whoami

      match /view (.+)/i,         :method => :seer_view_player
      match /tableview/i,         :method => :seer_view_table
      match /thief (.+)/i,        :method => :thief_take_player
      match /tablethief/i,        :method => :thief_take_table
      match /nothief/i,           :method => :thief_take_none
 
      match /lynch (.+)/i,        :method => :lynch_vote
      match /status/i,            :method => :status
      match /confirm/i,           :method => :confirm_role

      # other
      # match /invite/i,              :method => :invite
      # match /subscribe/i,           :method => :subscribe
      # match /unsubscribe/i,         :method => :unsubscribe
      match /help ?(.+)?/i,         :method => :help
      match /intro/i,               :method => :intro
      match /rules ?(.+)?/i,        :method => :rules
      match /changelog$/i,          :method => :changelog_dir
      match /changelog (\d+)/i,     :method => :changelog
      # match /about/i,               :method => :about
   
      # mod only commands
      match /reset/i,              :method => :reset_game
      match /replace (.+?) (.+)/i, :method => :replace_user
      match /kick (.+)/i,          :method => :kick_user
      match /room (.+)/i,          :method => :room_mode
      match /roles/i,              :method => :what_roles

      listen_to :join,          :method => :voice_if_in_game
      listen_to :leaving,       :method => :remove_if_not_started
      listen_to :op,            :method => :devoice_everyone_on_start


      #--------------------------------------------------------------------------------
      # Listeners & Timers
      #--------------------------------------------------------------------------------
      
      def voice_if_in_game(m)
        if @game.has_player?(m.user)
          Channel(@channel_name).voice(m.user)
        end
      end

      def remove_if_not_started(m, user)
        if @game.not_started?
          self.remove_user_from_game(user)
        end
      end

      def devoice_everyone_on_start(m, user)
        if user == bot
          self.devoice_channel
        end
      end

      def start_idle_timer
        Timer(300) do
          @game.players.map{|p| p.user }.each do |user|
            user.refresh
            if user.idle > @idle_timer_length
              self.remove_user_from_game(user)
              user.send "You have been removed from the #{@channel_name} game due to inactivity."
            end
          end
        end
      end

      #--------------------------------------------------------------------------------
      # Helpers
      #--------------------------------------------------------------------------------

      def help(m, page)
        if page.to_s.downcase == "mod" && self.is_mod?(m.user.nick)
          User(m.user).send "--- HELP PAGE MOD ---"
          User(m.user).send "!reset - completely resets the game to brand new"
          User(m.user).send "!replace nick1 nick1 - replaces a player in-game with a player out-of-game"
          User(m.user).send "!kick nick1 - removes a presumably unresponsive user from an unstarted game"
          User(m.user).send "!room silent|vocal - switches the channel from voice only users and back"
        else 
          # case page
          # when "2"
          #   User(m.user).send "--- HELP PAGE 2/3 ---"
          # when "3"
          #   User(m.user).send "--- HELP PAGE 3/3 ---"
          #   User(m.user).send "!rules - provides rules for the game"
          # else
            User(m.user).send "--- HELP PAGE 1/3 ---"
            User(m.user).send "!lynch (player) - vote for the player you wish to lynch"
            User(m.user).send "!confirm - confirm your role (werewolves and villagers only)"
            User(m.user).send "!join - joins the game"
            User(m.user).send "!leave - leaves the game"
            User(m.user).send "!start - starts the game"
            User(m.user).send "!rules (rolecount) - provides rules for the game; when provided with an argument, provides specified rules"
          # end
        end
      end

      def intro(m)
        User(m.user).send "Welcome to ONWWBot. You can join a game if there's one getting started with the command \"!join\". For more commands, type \"!help\". If you don't know how to play, you can read a rules summary with \"!rules\". If already know how to play, great."
      end

      def rules(m, section)
        case section.to_s.downcase
        when "rolecount"
          User(m.user).send "Role counts are as follows:"
          User(m.user).send "3 players: 2 werewolves, 1 villager, 1 seer, 1 thief"
          User(m.user).send "4 players: 2 werewolves, 2 villagers, 1 seer, 1 thief"
          User(m.user).send "5 players: 2 werewolves, 3 villagers, 1 seer, 1 thief"
          User(m.user).send "6~7 players: 2 werewolves, 4 villagers, 1 seer, 1 thief"
        else  
          User(m.user).send "One Night Werewolf is based on the party game \"Are you a werewolf?\'. In One Night Werewolf, there is a single night phase and a single day phase.  Just as in Werewolf, players are dealt roles which are kept hidden for the duration of the game.  There are always two more roles than the number of players.  During the night phase, the seer and thief (if in play) can use their abilities in order."
          User(m.user).send "First, the werewolves reveal to each other, or learn that they are the only one currently in play.  Next, the seer can either look at ONE player's role or look at the two remaining roles on the table. Finally, the thief can then choose to either exchange roles with another player, exchange roles with one of the remaining roles from the table, or not at all.  If the thief exchanges with another player, the chosen player does not know if their role was exchanged or not."
          User(m.user).send "During the day phase, players discuss who the werewolves are (or if there even are werewolves...).  Then, all players vote on who should be lynched.  The player with the most votes is lynched.  In the case of a tie, all tied players are lynched. If at least one werewolf is lynched, the humans win. If no werewolf is lynched, the werewolves win."
          User(m.user).send "In the case that all players get 1 vote, nobody is lynched.  If there are no werewolves, everyone wins. But, if at least 1 player is a werewolf, the werewolves win."
        end
      end

      def list_players(m)
        if @game.players.empty?
          m.reply "No one has joined the game yet."
        else
          m.reply @game.players.map{ |p| p == @game.hammer ? "#{dehighlight_nick(p.user.nick)}*" : dehighlight_nick(p.user.nick) }.join(' ')
        end
      end

      def status(m)
        m.reply @game.check_game_state
      end

      def changelog_dir(m)
        @changelog.first(5).each_with_index do |changelog, i|
          User(m.user).send "#{i+1} - #{changelog["date"]} - #{changelog["changes"].length} changes" 
        end
      end

      def changelog(m, page = 1)
        changelog_page = @changelog[page.to_i-1]
        User(m.user).send "Changes for #{changelog_page["date"]}:"
        changelog_page["changes"].each do |change|
          User(m.user).send "- #{change}"
        end
      end

      def invite(m)
        if @game.accepting_players?
          if @game.invitation_sent?
            m.reply "An invitation cannot be sent out again so soon."
          else      
            @game.mark_invitation_sent
            User("BG3PO").send "!invite_to_onww_game"
            User(m.user).send "Invitation has been sent."

            settings = load_settings || {}
            subscribers = settings["subscribers"]
            current_players = @game.players.map{ |p| p.user.nick }
            subscribers.each do |subscriber|
              unless current_players.include? subscriber
                User(subscriber).refresh
                if User(subscriber).online?
                  User(subscriber).send "A game of ONWW is gathering in #playonww ..."
                end
              end
            end

            # allow for reset after provided time
            Timer(@invite_timer_length, shots: 1) do
              @game.reset_invitation
            end
          end
        end
      end

      def subscribe(m)
        settings = load_settings || {}
        subscribers = settings["subscribers"] || []
        if subscribers.include?(m.user.nick)
          User(m.user).send "You are already subscribed to the invitation list."
        else
          if User(m.user).authed?
            subscribers << m.user.nick 
            settings["subscribers"] = subscribers
            save_settings(settings)
            User(m.user).send "You've been subscribed to the invitation list."
          else
            User(m.user).send "Whoops. You need to be identified on freenode to be able to subscribe. Either identify (\"/msg Nickserv identify [password]\") if you are registered, or register your account (\"/msg Nickserv register [email] [password]\")"
            User(m.user).send "See http://freenode.net/faq.shtml#registering for help"
          end
        end
      end

      def unsubscribe(m)
        settings = load_settings || {}
        subscribers = settings["subscribers"] || []
        if subscribers.include?(m.user.nick)
          if User(m.user).authed?
            subscribers.delete_if{ |sub| sub == m.user.nick }
            settings["subscribers"] = subscribers
            save_settings(settings)
            User(m.user).send "You've been unsubscribed to the invitation list."
          else
            User(m.user).send "Whoops. You need to be identified on freenode to be able to unsubscribe. Either identify (\"/msg Nickserv identify [password]\") if you are registered, or register your account (\"/msg Nickserv register [email] [password]\")"
            User(m.user).send "See http://freenode.net/faq.shtml#registering for help"
          end
        else
          User(m.user).send "You are not subscribed to the invitation list."
        end
      end


      #--------------------------------------------------------------------------------
      # Main IRC Interface Methods
      #--------------------------------------------------------------------------------

      def join(m)
        # self.reset_timer(m)
        if Channel(@channel_name).has_user?(m.user)
          if @game.accepting_players? 
            added = @game.add_player(m.user)
            unless added.nil?
              Channel(@channel_name).send "#{m.user.nick} has joined the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
              Channel(@channel_name).voice(m.user)
            end
          else
            if @game.started?
              Channel(@channel_name).send "#{m.user.nick}: Game has already started."
            elsif @game.at_max_players?
              Channel(@channel_name).send "#{m.user.nick}: Game is at max players."
            else
              Channel(@channel_name).send "#{m.user.nick}: You cannot join."
            end
          end
        else
          User(m.user).send "You need to be in #{@channel_name} to join the game."
        end
      end

      def leave(m)
        if @game.not_started?
          left = @game.remove_player(m.user)
          unless left.nil?
            Channel(@channel_name).send "#{m.user.nick} has left the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
            Channel(@channel_name).devoice(m.user)
          end
        else
          if @game.started?
            m.reply "Game is in progress.", true
          end
        end
      end

      def start_game(m)
        unless @game.started?
          if @game.at_min_players?
            if @game.has_player?(m.user)
              @idle_timer.stop
              @game.start_game!

              Channel(@channel_name).send "The game has started."

              self.start_night_phase
            else
              m.reply "You are not in the game.", true
            end
          else
            m.reply "Need #{Game::MIN_PLAYERS} to start a game.", true
          end
        end
      end



      #--------------------------------------------------------------------------------
      # Game interaction methods
      #--------------------------------------------------------------------------------

      def start_night_phase
        Channel(@channel_name).send "*** NIGHT ***"
        Channel(@channel_name).moderated = true
        Channel(@channel_name).voiced.each do |user|
          Channel(@channel_name).devoice(user)
        end

        self.pass_out_roles

        # first see if we need to wait, if we do, just wait
        # if not, artificially wait
        if @game.waiting_on_role_confirm
          # wait
        else
          self.start_day_artifically
        end

      end

      def start_day_phase
        @game.change_to_day
        Channel(@channel_name).send "*** DAY ***"
        Channel(@channel_name).moderated = false
        @game.players.each do |p|
          Channel(@channel_name).voice(p.user)
        end
      end


      def start_day_artifically
        # no timer for now, but will be a random timer after we notice
        # how long it takes players usually
        self.start_day_phase
      end

      def check_for_day_phase
        if @game.waiting_on_role_confirm

        else
          self.start_day_phase
        end
      end

      def lynch_vote(m, vote)
        if @game.started? && @game.has_player?(m.user)
          player = @game.find_player(m.user)
    
          target_player = @game.find_player(vote)
          if target_player.nil?
            User(m.user).send "\"#{vote}\" is an invalid target."  
          else
            @game.lynch_vote(player, target_player)
            User(m.user).send "You have voted to lynch #{target_player}."
            self.check_for_lynch
          end
        end
      end

      def check_for_lynch
        if @game.all_lynch_votes_in?
          self.do_end_game
        end
      end

      def confirm_role(m)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          if player.non_special?
            player.confirm_role
            User(m.user).send "Your role has been confirmed"
            self.check_for_day_phase
          end
        end
      end

      def status(m)
        m.reply @game.check_game_state
      end

      def seer_view_player(m, view)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
    
          if player.seer?
            target_player = @game.find_player(view)
            if target_player.nil?
              User(m.user).send "\"#{view}\" is an invalid target."  
            elsif target_player == player
              User(m.user).send "You cannot view yourself."
            else
              player.seer_view = {:player => target_player}
              player.confirm_role
              User(m.user).send "#{target_player} is #{target_player.role.upcase}."
              self.check_for_day_phase
            end
          else 
            User(m.user).send "You are not the SEER."
          end
        end
      end

      def seer_view_table(m)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
    
          if player.seer?
            player.seer_view = {:table => @game.table_cards.map(&:upcase).join(" and ")}
            player.confirm_role
            User(m.user).send "Middle is #{@game.table_cards.map(&:upcase).join(" and ")}."
            self.check_for_day_phase
          else 
            User(m.user).send "You are not the SEER."
          end
        end
      end

      def thief_take_player(m, stolen)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
    
          if player.thief?
            target_player = @game.find_player(stolen)
            if target_player.nil?
              User(m.user).send "\"#{stolen}\" is an invalid target."  
            elsif target_player == player
              User(m.user).send "You cannot steal from yourself."
            else
              player.thief_take = {:player => target_player}
              player.new_role = target_player.role
              player.confirm_role
              target_player.new_role = :thief
              User(m.user).send "You are now a #{target_player.role.upcase}."
              self.check_for_day_phase
            end
          else 
            User(m.user).send "You are not the THIEF."
          end
        end
      end

      def thief_take_none(m)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
    
          if player.thief?
            player.thief_take = {:none => "none"}
            player.confirm_role
            User(m.user).send "You remain THIEF."
            self.check_for_day_phase
          else 
            User(m.user).send "You are not the THIEF."
          end
        end
      end

      def thief_take_table(m)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
      
          if player.thief?
            new_thief = @game.table_cards.shuffle.first
            player.thief_take = {:table => new_thief}
            player.new_role = new_thief
            player.confirm_role
            User(m.user).send "You are now a #{new_thief.upcase}."
            self.check_for_day_phase
          else 
            User(m.user).send "You are not the THIEF."
          end
        end
      end

      def pass_out_roles
        @game.players.each do |p|
          User(p.user).send "="*40
          self.tell_role_to(p)
        end
      end

      def whoami(m)
        if @game.started? && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          self.tell_role_to(player)
        end
      end
      
      def tell_role_to(player)
        case player.role
        when :villager
          loyalty_msg = "You are a VILLAGER. Type !confirm to confirm your role."
        when :seer
          loyalty_msg = "You are the SEER. What do you want to view? \"!view [player]\" \"!tableview\""
        when :thief
          loyalty_msg = "You are the THIEF. Do you want to take a role? \"!thief [player]\", \"!tablethief\" or \"!nothief\""
        when :werewolf
          other_wolf = @game.werewolves.reject{ |w| w == player }
          msg = other_wolf.empty? ? "You are a lone wolf." : "The other wolf is #{other_wolf.first}."
          loyalty_msg = "You are a WEREWOLF. #{msg} Type !confirm to confirm your role."
        end
        User(player.user).send loyalty_msg
      end

      def do_end_game
        lynch_totals = @game.lynch_totals

        # sort from max to min
        lynch_totals = lynch_totals.sort_by{ |vote, voters| voters.size }.reverse

        lynch_msg = lynch_totals.map do |voted, voters|
          "#{voters.count} - #{voted} (#{voters.join(', ')})"
        end.join(', ')
        Channel(@channel_name).send "Final Votes: #{lynch_msg}"

        #grab the first person lynched and see if anyone else matches them
        first_lynch = lynch_totals.first
        lynching = lynch_totals.select { |voted, voters| voters.count == first_lynch[1].count }
        lynching = lynching.map{ |voted, voters| voted}
        
        lynched_players = first_lynch[1].count == 1 ? "No one is lynched!" : lynching.join(', ')
        Channel(@channel_name).send "Lynched players: #{lynched_players}"

        # now reveal roles of everyone
        roles_msg = @game.players.map do |player|
          "#{player} - #{player.role.upcase}"
        end.join(', ')
        Channel(@channel_name).send "Starting Roles: #{roles_msg}"

        #now reveal seer and thief actions
        player = @game.find_player_by_role(:seer)
        unless player.nil?
          if player.seer_view.has_key?(:player)
            Channel(@channel_name).send "Seer looked at #{player.seer_view[:player]} and saw: #{player.seer_view[:player].role.upcase}"
          elsif player.seer_view.has_key?(:table)
            Channel(@channel_name).send "Seer looked at the table and saw: #{player.seer_view[:table]}"
          end
        end
        
        player = @game.find_player_by_role(:thief)
        unless player.nil?
          if player.thief_take.has_key?(:none)
            Channel(@channel_name).send "Thief took from no one"
          elsif player.thief_take.has_key?(:player)
            Channel(@channel_name).send "Thief took: #{player.thief_take[:player].role.upcase} from #{player.thief_take[:player]}"
          elsif player.thief_take.has_key?(:table)
            Channel(@channel_name).send "Thief took: #{player.thief_take[:table].upcase} from the table" 
          end
        end

        #replace everyones starting roles with stolen roles        
        @game.players.map do |player|
          player.role = player.new_role unless player.new_role.nil?
        end

        #return victory result
        if (lynching.detect { |l| l.werewolf? } && first_lynch[1].count > 1) || (!lynching.detect { |l| l.werewolf? } && first_lynch[1].count == 1)
          Channel(@channel_name).send "Humans WIN! Team: #{@game.humans.join(', ')}"
        elsif @game.werewolves.empty?
          Channel(@channel_name).send "Werewolves WIN! Everyone loses...womp wahhhhhh"
        else
          Channel(@channel_name).send "Werewolves WIN! Team: #{@game.werewolves.join(', ')}"
        end

        self.start_new_game
      end

      def start_new_game
        Channel(@channel_name).moderated = false
        @game.players.each do |p|
          Channel(@channel_name).devoice(p.user)
        end
        @game = Game.new
        @idle_timer.start
      end


      def devoice_channel
        Channel(@channel_name).voiced.each do |user|
          Channel(@channel_name).devoice(user)
        end
      end

      def remove_user_from_game(user)
        if @game.not_started?
          left = @game.remove_player(user)
          unless left.nil?
            Channel(@channel_name).send "#{user.nick} has left the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
            Channel(@channel_name).devoice(user)
          end
        end
      end

      def dehighlight_nick(nickname)
        nickname.scan(/.{2}|.+/).join(8203.chr('UTF-8'))
      end

      #--------------------------------------------------------------------------------
      # Mod commands
      #--------------------------------------------------------------------------------

      def is_mod?(nick)
        # make sure that the nick is in the mod list and the user in authenticated 
        user = User(nick) 
        user.authed? && @mods.include?(user.authname)
      end

      def reset_game(m)
        if self.is_mod? m.user.nick
          if @game.started?
            #spies, resistance = get_loyalty_info
            #Channel(@channel_name).send "The spies were: #{spies.join(", ")}"
            #Channel(@channel_name).send "The resistance were: #{resistance.join(", ")}"
          end
          @game = Game.new
          self.devoice_channel
          Channel(@channel_name).send "The game has been reset."
          @idle_timer.start
        end
      end

      def kick_user(m, nick)
        if self.is_mod? m.user.nick
          if @game.not_started?
            user = User(nick)
            left = @game.remove_player(user)
            unless left.nil?
              Channel(@channel_name).send "#{user.nick} has left the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
              Channel(@channel_name).devoice(user)
            end
          else
            User(m.user).send "You can't kick someone while a game is in progress."
          end
        end
      end

      def replace_user(m, nick1, nick2)
        if self.is_mod? m.user.nick
          # find irc users based on nick
          user1 = User(nick1)
          user2 = User(nick2)
          
          # replace the users for the players
          player = @game.find_player(user1)
          player.user = user2

          # devoice/voice the players
          Channel(@channel_name).devoice(user1)
          Channel(@channel_name).voice(user2)

          # inform channel
          Channel(@channel_name).send "#{user1.nick} has been replaced with #{user2.nick}"

          # tell loyalty to new player
          User(player.user).send "="*40
          self.tell_loyalty_to(player)
        end
      end

      def room_mode(m, mode)
        if self.is_mod? m.user.nick
          case mode
          when "silent"
            Channel(@channel_name).moderated = true
          when "vocal"
            Channel(@channel_name).moderated = false
          end
        end
      end

      def what_roles(m)
        if self.is_mod? m.user.nick
          if @game.started?
            if @game.has_player?(m.user)
              User(m.user).send "You are in the game, goof!"
            else
              roles_msg = @game.players.map do |player|
                "#{player} - #{player.role.upcase}"
              end.join(', ')
              User(m.user).send "Starting Roles: #{roles_msg}"
              if @game.day?
                roles_msg = @game.players.map{ |player| player.new_role.nil? ? "#{player} - #{player.role.upcase}" : Format(:bold, "#{player} - #{player.new_role.upcase}")}.join(', ')
                User(m.user).send "Current Roles: #{roles_msg}"
              end
            end
          else
            User(m.user).send "There is no game going on."
          end
        end
      end


      #--------------------------------------------------------------------------------
      # Settings
      #--------------------------------------------------------------------------------
      
      def save_settings(settings)
        output = File.new(@settings_file, 'w')
        output.puts YAML.dump(settings)
        output.close
      end

      def load_settings
        output = File.new(@settings_file, 'r')
        settings = YAML.load(output.read)
        output.close

        settings
      end

      def load_changelog
        output = File.new(CHANGELOG_FILE, 'r')
        changelog = YAML.load(output.read)
        output.close

        changelog
      end
      

    end
    
  end
end
