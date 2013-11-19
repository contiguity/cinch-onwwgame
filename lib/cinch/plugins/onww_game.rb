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
      match /start/i,            :method => :start_game_check

      # game
      #match /whoami/i,           :method => :whoami 

      # seer
      match /view (.+)/i,         :method => :seer_view_player
      match /tableview/i,         :method => :seer_view_table

      # thief
      match /thief (.+)/i,        :method => :thief_take_player
      match /tablethief/i,        :method => :thief_take_table
      match /nothief/i,           :method => :thief_take_none

      # robber
      match /rob (.+)/i,          :method => :thief_take_player
      match /norob/i,             :method => :thief_take_none

      # troublemaker
      match /switch (.+?) (.+)/i, :method => :troublemaker_switch
      match /noswitch/i,          :method => :troublemaker_noswitch

      # doppelganger
      match /look ?(.+)?/i,       :method => :doppelganger_look

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
      match /settings$/i,           :method => :get_game_settings
      match /settings (base|onuww) ?(.+)?/i, :method => :set_game_settings

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
            User(m.user).send "!rules (rolecount|onuwwroles) - provides rules for the game; when provided with an argument, provides specified rules"
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
        when "onuwwroles"
          User(m.user).send "INSERT ONUWW ROLES HERE!"
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
              Channel(@channel_name).send "#{m.user.nick} has joined the game (#{@game.players.count}/#{@game.max_players})"
              Channel(@channel_name).voice(m.user)
            end
          else
            if @game.started?
              Channel(@channel_name).send "#{m.user.nick}: Game has already started."
            elsif @game.at_max_players?
              Channel(@channel_name).send "#{m.user.nick}: Game is at max players. Switch to ONUWW to add more players"
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
            Channel(@channel_name).send "#{m.user.nick} has left the game (#{@game.players.count}/#{@game.max_players})"
            Channel(@channel_name).devoice(m.user)
          end
        else
          if @game.started?
            m.reply "Game is in progress.", true
          end
        end
      end

      def start_game_check(m)
        unless @game.started?
          if @game.at_min_players?
            if @game.has_player?(m.user)
              if @game.onuww?
                #check to make sure we have the right number of roles
                num_total_cards = @game.player_count + 3
                if self.game_settings[:roles].count < num_total_cards
                  num_lacking_cards = num_total_cards - self.game_settings[:roles].count
                  if num_lacking_cards <= (3 - self.game_settings[:roles].count(:villager))
                    num_lacking_cards.times {
                      roles = self.game_settings[:roles]
                      roles += ["villager"]
                      @game.change_type :onuww, :roles => roles
                    }
                    self.do_start_game
                  else
                    Channel(@channel_name).send "Not enough roles specified for number of players."
                  end
                elsif self.game_settings[:roles].count > num_total_cards
                  Channel(@channel_name).send "More roles specified than number of players."
                else
                 self.do_start_game 
                end
              else
                self.do_start_game
              end
            else
              m.reply "You are not in the game.", true
            end
          else
            m.reply "Need #{Game::MIN_PLAYERS} to start a game.", true
          end
        end
      end

      def do_start_game
        @idle_timer.stop

        Channel(@channel_name).send "The game has started."
        if @game.onuww?
          with_variants = @game.variants.empty? ? "" : " Using variants: #{self.game_settings[:variants].join(", ")}."
          Channel(@channel_name).send "Using roles: #{self.game_settings[:roles].sort.join(", ")}.#{with_variants}"
          Channel(@channel_name).send "Players: #{@game.players.map(&:user).join(", ")}" 
        end

        @game.start_game!
        self.start_night_phase
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
      end

      def start_day_phase
        @game.change_to_day
        Channel(@channel_name).send "*** DAY ***"
        Channel(@channel_name).moderated = false
        @game.players.each do |p|
          Channel(@channel_name).voice(p.user)
        end
      end

      def start_night_phase2
        @game.finish_subphase1
        self.night_reveal

        self.start_day_phase
      end

      def check_for_day_phase
        if @game.waiting_on_role_confirm

        else
          self.start_night_phase2
        end
      end

      def lynch_vote(m, vote)
        if @game.started? && @game.has_player?(m.user)
          player = @game.find_player(m.user)
    
          target_player = @game.find_player(vote)
          if target_player.nil?
            User(m.user).send "\"#{vote}\" is an invalid target."  
          elsif (target_player == player && @game.onuww?)
            User(m.user).send "You may not vote to lynch yourself."
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
          else
            User(m.user).send "Role: #{player.role.upcase} does not need to confirm"
          end
        end
      end

      def status(m)
        m.reply @game.check_game_state
      end

      def seer_view_player(m, view)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
    
          if (player.seer? || (player.doppelganger? && player.cur_role == :seer))
            target_player = @game.find_player(view)
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            elsif target_player.nil?
              User(m.user).send "\"#{view}\" is an invalid target."  
            elsif target_player == player
              User(m.user).send "You cannot view yourself."
            else
              player.action_take = {:seerplayer => target_player}
              player.confirm_role
              User(m.user).send "Your action has been confirmed."
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
    
          if (player.seer? || (player.doppelganger? && player.cur_role == :seer))
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            else
              if @game.onuww?
                player.action_take = {:seertable => @game.table_cards.shuffle.first(2).map(&:upcase).join(" and ")}
              else
                player.action_take = {:seertable => @game.table_cards.map(&:upcase).join(" and ")}
              end
              player.confirm_role
              User(m.user).send "Your action has been confirmed."
              self.check_for_day_phase
            end
          else 
            User(m.user).send "You are not the SEER."
          end
        end
      end

      def thief_take_player(m, stolen)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
    
          if (player.thief? || player.robber? || (player.doppelganger? && player.cur_role == :robber))
            target_player = @game.find_player(stolen)
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            elsif target_player.nil?
              User(m.user).send "\"#{stolen}\" is an invalid target."  
            elsif target_player == player
              User(m.user).send "You cannot steal from yourself."
            else
              player.action_take = {:thiefplayer => target_player}
              player.confirm_role
              User(m.user).send "Your action has been confirmed."
              self.check_for_day_phase
            end
          else 
            correct_role = @game.onuww? ? "ROBBER" : "THIEF"
            User(m.user).send "You are not the #{correct_role}."
          end
        end
      end

      def thief_take_none(m)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          correct_role = @game.onuww? ? "ROBBER" : "THIEF"

          if (player.thief? || player.robber? || (player.doppelganger? && player.cur_role == :robber))
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            else
              player.action_take = {:thiefnone => "none"}
              player.confirm_role
              User(m.user).send "Your action has been confirmed."
              self.check_for_day_phase
            end
          else 
            User(m.user).send "You are not the #{correct_role}."
          end
        end
      end

      def thief_take_table(m)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
      
          if player.thief?
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            else
              new_thief = @game.table_cards.shuffle.first
              player.action_take = {:thieftable => new_thief}
              player.confirm_role
              User(m.user).send "Your action has been confirmed."
              self.check_for_day_phase
            end
          else 
            User(m.user).send "You are not the THIEF."
          end
        end
      end

      def troublemaker_switch(m, switch1, switch2)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          if (player.troublemaker? || (player.doppelganger? && player.cur_role == :troublemaker))
            target_player1 = @game.find_player(switch1)
            target_player2 = @game.find_player(switch2)
            
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            elsif target_player1.nil? || target_player2.nil?
              User(m.user).send "You have specified an invalid target."
            elsif target_player1 == player || target_player2 == player
              User(m.user).send "You cannot switch your own role"
            else
              player.action_take = {:troublemakerplayer => [target_player1, target_player2]}
              player.confirm_role
              User(m.user).send "Your action has been confirmed"
              self.check_for_day_phase
            end
          else
            User(m.user).send "You are not the TROUBLEMAKER"
          end
        end
      end

      def troublemaker_noswitch(m)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          if (player.troublemaker? || (player.doppelganger? && player.cur_role == :troublemaker))
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            else
              player.action_take = {:troublemakernone => "none"}
              player.confirm_role
              User(m.user).send "Your action has been confirmed"
              self.check_for_day_phase
            end
          else
            User(m.user).send "You are not the TROUBLEMAKER."
          end
        end
      end

      def doppelganger_look(m, look)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          if player.doppelganger?
            target_player = @game.find_player(look)
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            elsif target_player.nil?
              User(m.user).send "\"#{look}\" is an invalid target."
            elsif target_player == player
              User(m.user).send "You cannot choose yourself."
            else
              player.doppelganger_look = {:dglook => target_player, :dgrole => target_player.cur_role}
              player.cur_role = target_player.role
              self.tell_role_to(player)
            end
          else
            User(m.user).send "You are not the DOPPELGANGER"
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
        case player.cur_role
        when :villager, :werewolf, :mason
          loyalty_msg = "You are a #{player.cur_role.upcase}. Type !confirm to confirm your role."
        when :seer
          loyalty_msg = "You are the SEER. What do you want to view? \"!view [player]\" \"!tableview\""
        when :thief
          loyalty_msg = "You are the THIEF. Do you want to take a role? \"!thief [player]\", \"!tablethief\" or \"!nothief\""
        when :robber
          loyalty_msg = "You are the ROBBER. Do you want to take a role? \"!rob [player]\" or \"!norob\""
        when :troublemaker
          loyalty_msg = "You are the TROUBLEMAKER. Do you want to switch the roles of two players? \"!switch [player1] [player2]\" or \"!noswitch\""
        when :tanner, :drunk, :hunter, :insomniac, :minion
          loyalty_msg = "You are the #{player.cur_role.upcase}. Type !confirm to confirm your role."
        when :doppelganger
          loyalty_msg = "You are the DOPPELGANGER. Who do you want to look at? \"!look [player]\""
        end
        User(player.user).send loyalty_msg
      end

      def night_reveal
        unless @game.old_doppelganger.nil?
          player.cur_role = player.role
          case @game.doppelganger_role
          when :minion
            werewolves = @game.werewolves
            reveal_msg = werewolves.empty? ? "You do not see any werewolves." : "You look for other werewolves and see: #{werewolves.join(", ")}."
            User(player.user).send reveal_msg
          when :seer
            if player.action_take.has_key?(:seerplayer)
              User(player.user).send "#{player.action_take[:seerplayer]} is #{player.action_take[:seerplayer].cur_role.upcase}."
            elsif player.action_take.has_key?(:seertable)
              if @game.onuww?
                User(player.user).send "Two of the middle cards are: #{player.action_take[:seertable]}."
              else
                User(player.user).send "Middle is #{player.action_take[:seertable]}."
              end
            end
          when :robber
            if player.action_take.has_key?(:thiefnone)
              User(player.user).send "You remain the #{player.role.upcase}"
            elsif player.action_take.has_key?(:thiefplayer)
              target_player = player.action_take[:thiefplayer]
              player.cur_role,target_player.cur_role = target_player.cur_role,player.cur_role
              User(player.user).send "You are now a #{player.action_take[:thiefplayer].role.upcase}."
            end
          when :troublemaker
            if player.action_take.has_key?(:troublemakerplayer)
              player.action_take[:troublemakerplayer][0].cur_role,player.action_take[:troublemakerplayer][1].cur_role = player.action_take[:troublemakerplayer][1].cur_role,player.action_take[:troublemakerplayer][0].cur_role
            end          
          when :drunk
            newrole = @game.table_cards.shuffle.shift
            @game.table_cards.push(:drunk)
            player.cur_role = newrole
            player.action_take = {:drunk => newrole}
            User(player.user).send "You have exchanged your card with a card from the middle."
          end
        end

        unless @game.werewolves.nil?
          @game.werewolves.each do |p|
            other_wolf = @game.werewolves.reject{ |w| w == p }
            reveal_msg = other_wolf.empty? ? "You are a lone wolf." : "You look for other werewolves and see: #{other_wolf.join(", ")}."
            User(p.user).send reveal_msg
          end
        end

        player = @game.find_player_by_role(:minion)
        unless player.nil?
          werewolves = @game.werewolves
          reveal_msg = werewolves.empty? ? "You do not see any werewolves." : "You look for other werewolves and see: #{werewolves.join(", ")}."
          User(player.user).send reveal_msg
        end

        unless @game.masons.nil?
          @game.masons.each do |p|
            other_mason = @game.masons.reject{ |m| m == p }
            reveal_msg = other_mason.empty? ? "You are the only mason." : "You look for other masons and see: #{other_mason.join(", ")}."
            User(p.user).send reveal_msg
          end
        end

        player = @game.find_player_by_role(:seer)
        unless player.nil?
          if player.action_take.has_key?(:seerplayer)
            User(player.user).send "#{player.action_take[:seerplayer]} is #{player.action_take[:seerplayer].cur_role.upcase}."
          elsif player.action_take.has_key?(:seertable)
            if @game.onuww?
              User(player.user).send "Two of the middle cards are: #{player.action_take[:seertable]}."
            else
              User(player.user).send "Middle is #{player.action_take[:seertable]}."
            end
          end 
        end

        if @game.onuww?
          player = @game.find_player_by_role(:robber)
        else
          player = @game.find_player_by_role(:thief)
        end
        unless player.nil?
          if player.action_take.has_key?(:thiefnone)
            User(player.user).send "You remain the #{player.role.upcase}"
          elsif player.action_take.has_key?(:thiefplayer)
            target_player = player.action_take[:thiefplayer]
            player.cur_role,target_player.cur_role = target_player.cur_role,player.cur_role
            User(player.user).send "You are now a #{player.action_take[:thiefplayer].role.upcase}."
          elsif player.action_take.has_key?(:thieftable)
            new_thief = @game.table_cards.shuffle.first
            player.action_take = {:thieftable => new_thief}
            player.cur_role = new_thief
            User(player.user).send "You are now a #{player.action_take[:thieftable].upcase}."
          end
        end

        player = @game.find_player_by_role(:troublemaker)
        unless player.nil?
          if player.action_take.has_key?(:troublemakerplayer)
            player.action_take[:troublemakerplayer][0].cur_role,player.action_take[:troublemakerplayer][1].cur_role = player.action_take[:troublemakerplayer][1].cur_role,player.action_take[:troublemakerplayer][0].cur_role
          end
        end
        
        player = @game.find_player_by_role(:drunk)
        unless player.nil?
          newrole = @game.table_cards.shuffle.first
          player.cur_role = newrole
          player.action_take = {:drunk => newrole}
          User(player.user).send "You have exchanged your card with a card from the middle."
        end

        unless @game.insomniacs.nil?
          @game.insomniacs.each do |p|
            reveal_msg = player.cur_role == player.role ? "You are still the INSOMNIAC." : "You are now the #{player.cur_role.upcase}."
            User(player.user).send reveal_msg
          end
        end
      end

      def do_end_game
        # first reveal game intro info
        roles_msg = @game.players.map do |player|
          if player == @game.old_doppelganger
            "#{player} - DOPPELGANGER"
          else
            "#{player} - #{player.role.upcase}"
          end
        end.join(', ')
        Channel(@channel_name).send "Starting Roles: #{roles_msg}"
        Channel(@channel_name).send "Middle Cards: #{@game.table_cards.map(&:upcase).join(', ')}"

        # now reveal night actions
        # need to turn this into repeatable functions
        player = @game.old_doppelganger
        unless player.nil?
          Channel(@channel_name).send "DOPPELGANGER looked at #{player.doppelganger_look} and became #{player.doppelganger_look.role.upcase}"
          if player.action_take.has_key?(:seerplayer)
            Channel(@channel_name).send "DOPPELGANGER-SEER looked at #{player.action_take[:seerplayer]} and saw: #{player.action_take[:seerplayer].role.upcase}"
          elsif player.action_take.has_key?(:seertable)
            Channel(@channel_name).send "DOPPELGANGER-SEER looked at the table and saw: #{player.action_take[:seertable]}"
          elsif player.action_take.has_key?(:thiefnone)
            Channel(@channel_name).send "DOPPELGANGER-ROBBER took from no one"
          elsif player.action_take.has_key?(:thiefplayer)
            Channel(@channel_name).send "DOPPELGANGER-ROBBER took: #{player.action_take[:thiefplayer].role.upcase} from #{player.action_take[:thiefplayer]}"
          elsif player.action_take.has_key?(:troublemakernone)
            Channel(@channel_name).send "DOPPELGANGER-TROUBLEMAKER switched no one"
          elsif player.action_take.has_key?(:troublemakerplayer)
            Channel(@channel_name).send "OPPELGANGER-TROUBLEMAKER switched: #{player.action_take[:troublemakerplayer]}"
          elsif player.action_take.has_key?(:drunk)
            Channel(@channel_name).send "DOPPELGANGER-DRUNK drew #{player.action_take[:drunk].upcase} from the table"
          end
        end

        player = @game.find_player_by_role(:seer)
        unless player.nil?
          if player.action_take.has_key?(:seerplayer)
            Channel(@channel_name).send "SEER looked at #{player.action_take[:seerplayer]} and saw: #{player.action_take[:seerplayer].role.upcase}"
          elsif player.action_take.has_key?(:seertable)
            Channel(@channel_name).send "SEER looked at the table and saw: #{player.action_take[:seertable]}"
          end
        end
        
        player = @game.find_player_by_role(:thief)
        unless player.nil?
          if player.action_take.has_key?(:thiefnone)
            Channel(@channel_name).send "THIEF took from no one"
          elsif player.action_take.has_key?(:thiefplayer)
            Channel(@channel_name).send "THIEF took: #{player.action_take[:thiefplayer].role.upcase} from #{player.action_take[:thiefplayer]}"
          elsif player.action_take.has_key?(:thieftable)
            Channel(@channel_name).send "THIEF took: #{player.action_take[:thieftable].upcase} from the table" 
          end
        end

        player = @game.find_player_by_role(:robber)
        unless player.nil?
          if player.action_take.has_key?(:thiefnone)
            Channel(@channel_name).send "ROBBER took from no one"
          elsif player.action_take.has_key?(:thiefplayer)
            Channel(@channel_name).send "ROBBER took: #{player.action_take[:thiefplayer].role.upcase} from #{player.action_take[:thiefplayer]}"
          end
        end

        player = @game.find_player_by_role(:troublemaker)
        unless player.nil?
          if player.action_take.has_key?(:troublemakernone)
            Channel(@channel_name).send "TROUBLEMAKER switched no one"
          elsif player.action_take.has_key?(:troublemakerplayer)
            Channel(@channel_name).send "TROUBLEMAKER switched: #{player.action_take[:troublemakerplayer]}"
          end
        end

        player = @game.find_player_by_role(:drunk)
        unless player.nil?
          Channel(@channel_name).send "DRUNK drew #{player.action_take[:drunk].upcase} from the table"
        end


        # show ending role result
        roles_msg = @game.players.map{ |player| player.role != player.cur_role || player.old_doppelganger? ? Format(:bold, "#{player} - #{player.cur_role.upcase}") : "#{player} - #{player.cur_role.upcase}" }.join(', ')
        Channel(@channel_name).send "Ending Roles: #{roles_msg}"

        # replace everyones starting roles with stolen roles        
        @game.players.map do |player|
          player.role = player.cur_role
        end

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

        # Check for hunter and add their target
        if (lynching.detect{ |l| l.hunter? } && first_lynch[1].count > 1)
          hunter_target = lynching.map { |lynched|
            @game.lynch_votes[lynched] if lynched.hunter?
          }
          (lynching+=hunter_target).uniq!
        end

        # Do it again in case the target of a hunter is another hunter
        # Yay edge cases!
        if (lynching.detect{ |l| l.hunter? } && first_lynch[1].count > 1)
          hunter_target = lynching.map { |lynched|
            @game.lynch_votes[lynched] if lynched.hunter?
          }
          hunter_target.reject! { |r| r.nil? }
          Channel(@channel_name).send "HUNTER chooses: #{hunter_target.join(', ')}."
          (lynching+=hunter_target).uniq!
        end

        lynched_players = first_lynch[1].count == 1 ? "No one is lynched!" : lynching.join(', ')
        Channel(@channel_name).send "Lynched players: #{lynched_players}."

        # return victory result
        # we lynched someone
        if first_lynch[1].count > 1
          # werewolf lynched villagers win
          if lynching.detect { |l| l.werewolf? }
            if lynching.detect { |l| l.tanner? }
              dead_tanner = lynching.select{ |l| l.tanner? }
              Channel(@channel_name).send "Villager team and Tanner WIN! Villager Team: #{@game.humans.join(', ')}. Tanner: #{dead_tanner.join(', ')}."
            else
              Channel(@channel_name).send "Villager team WINS! Team: #{@game.humans.join(', ')}."
            end
          # no werewolf lynched, werewolves win
          else
            if lynching.detect { |l| l.tanner? }
              dead_tanner = lynching.select{ |l| l.tanner? }
              Channel(@channel_name).send "TANNER WINS! Tanner: #{dead_tanner.join(', ')}."
            elsif @game.werewolves.empty?
              if lynching.detect { |l| l.good? }
                minion_msg = @game.minion.empty? ? " Everyone loses...womp wahhhhhh." : " Minion: #{@game.minion.join(', ')}."
                Channel(@channel_name).send "Werewolves WIN!#{minion_msg}"
              else 
                Channel(@channel_name).send "Werewolves WIN! Everyone loses...womp wahhhhhh."
              end
            else
              minion_msg = @game.minion.empty? ? "" : " Minion: #{@game.minion.join(', ')}."
              Channel(@channel_name).send "Werewolf team WINS! Team: #{@game.werewolves.join(', ')}.#{minion_msg}"
            end
          end
        # no one is lynched
        else
          if @game.werewolves.empty?
            Channel(@channel_name).send "Villager team WINS! Team: #{@game.humans.join(', ')}."
          else
            minion_msg = @game.minion.empty? ? "" : " Minion: #{@game.minion.join(', ')}."
            Channel(@channel_name).send "Werewolf team WINS! Team: #{@game.werewolves.join(', ')}.#{minion_msg}"
          end
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
            Channel(@channel_name).send "#{user.nick} has left the game (#{@game.players.count}/#{@game.max_players})"
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
              Channel(@channel_name).send "#{user.nick} has left the game (#{@game.players.count}/#{@game.max_players})"
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
                if player == @game.old_doppelganger
                 "#{player} - DOPPELGANGER"
                else
                  "#{player} - #{player.role.upcase}"
                end
              end.join(', ')
              User(m.user).send "Starting Roles: #{roles_msg}"
              if @game.day?
                roles_msg = @game.players.map{ |player| player.role != player.cur_role || player.old_doppelganger? ? Format(:bold, "#{player} - #{player.cur_role.upcase}") : "#{player} - #{player.cur_role.upcase}" }.join(', ')
                User(m.user).send "Current Roles: #{roles_msg}"
                player = @game.find_player_by_role(:seer)
                unless player.nil?
                  if player.action_take.has_key?(:seerplayer)
                    User(m.user).send "Seer looked at #{player.action_take[:seerplayer]} and saw: #{player.action_take[:seerplayer].role.upcase}"
                  elsif player.action_take.has_key?(:seertable)
                    User(m.user).send "Seer looked at the table and saw: #{player.action_take[:seertable]}"
                  end
                end
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
     
      def get_game_settings(m)
        with_variants = @game.variants.empty? ? "" : " Using variants: #{self.game_settings[:variants].join(", ")}."
        if @game.onuww?
          m.reply "Game settings: ONUWW. Using #{self.game_settings[:roles].count} roles: #{self.game_settings[:roles].sort.join(", ")}.#{with_variants}"
        else
          m.reply "Game settings: base.#{with_variants}"
        end
      end

      def set_game_settings(m, game_type, game_options = "")
        # this is really really wonky =(
        # lots of stupid user checking
        # im sure theres a better way but im lazy
        unless @game.started?
          game_change_prefix = m.channel.nil? ? "#{m.user.nick} has changed the game" : "The game has been changed"
          options = game_options || ""
          options = options.downcase.split(" ")
          if game_type.downcase == "onuww"
            valid_role_options    = ["villager", "werewolf", "seer", "robber", "troublemaker", "tanner", "drunk", "hunter", "mason", "insomniac", "minion", "doppelganger", "masons"]
            valid_variant_options = ["lonewolf"]

            role_options    = options.select{ |opt| valid_role_options.include?(opt) }
            variant_options = options.select{ |opt| valid_variant_options.include?(opt) }

            if role_options.include?("masons")
              role_options -= ["masons"]
              role_options += ["mason"]
            end
            unknown_options = options.select{ |opt| !valid_role_options.include?(opt) && !valid_variant_options.include?(opt)}
            if !game_options.nil?
              roles = role_options
              valid_role_options.map{ |vr|
                if (vr == "werewolf" && !roles.include?("werewolf"))
                  role_options = nil
                  Channel(@channel_name).send "You must include at least one werewolf."
                elsif (vr !="werewolf" && vr != "villager" && vr != "mason" && roles.count(vr) > 1) || (vr == "werewolf" && (roles.count(vr) > 2)) || (vr == "villager" && roles.count(vr) > 3) || (vr == "mason" && roles.count("mason") > 2)
                  role_options = nil
                  Channel(@channel_name).send "You have included #{vr} too many times."
                end
                
              }
              if unknown_options.count > 0
                Channel(@channel_name).send "Unknown roles specified: #{unknown_options.join(", ")}."
              end
            else
              roles = ["werewolf", "werewolf", "seer", "robber", "troublemaker", "villager"]
            end
            unless role_options.nil?
              roles += ["mason"] if (roles.include?("mason") && roles.count("mason") == 1)
              @game.change_type :onuww, :roles => roles, :variants => variant_options
              game_type_message = "#{game_change_prefix} to ONUWW. Using #{self.game_settings[:roles].count} roles: #{self.game_settings[:roles].sort.join(", ")}."
            end
          else
            @game.change_type :base
            game_type_message = "#{game_change_prefix} to base."
          end
          with_variants = self.game_settings[:variants].empty? ? "" : " Using variants: #{self.game_settings[:variants].join(", ")}."
          Channel(@channel_name).send "#{game_type_message}#{with_variants}"
        end
      end

      def game_settings
        settings = {}
        settings[:roles] = @game.roles
        settings[:variants] = []
        if @game.onuww?
          settings[:variants] << "Lone Wolf" if @game.variants.include?(:lonewolf)
        else
          #do other stuff
        end
        settings
      end

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
