require 'cinch'
require 'yaml'

require_relative 'core'
require_relative 'constants'

module Cinch
  module Plugins

    CHANGELOG_FILE = File.expand_path(File.dirname(__FILE__)) + "/changelog.yml"

    class OnwwGame
      include Cinch::Plugin

      #PI werewolf doesn't count as a werewolf but is reported as one

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

        @game_timer_minutes   = nil
        @game_timer   = nil
      end

      # start
      match /join/i,             :method => :join
      match /leave/i,            :method => :leave
      match /start/i,            :method => :start_game_check

      # game
      #match /whoami/i,           :method => :whoami
      # !nightorder
      # !roleset

      # timer
      match /timer set (\d+)/i,   :method => :set_timer 
      match /timer off$/i,        :method => :turn_off_timer 
      match /timer$/i,            :method => :check_timer 

      # claims
      match /claim (.+)/i,        :method => :claim_role
      match /unclaim/i,           :method => :unclaim_role
      match /claims/i,            :method => :list_claims

      # mystic_wolf
      match /mysticview (.+)/i,   :method => :mystic_wolf_view_player#mysticview to avoid conflict with seer

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

      # curator
      match /gift (.+)/i,         :method => :curator_gift_player
      match /nogift/i,       :method => :curator_gift_none

      # troublemaker
      match /switch (.+?) (.+)/i, :method => :troublemaker_switch
      match /noswitch/i,          :method => :troublemaker_noswitch

      # paranormal investigator
      match /search (.+?) (.+)$/i, :method => :paranormal_investigator_search
      match /search ([^\s]+?)$/i,       :method => :paranormal_investigator_single_search
      match /nosearch/i,           :method => :paranormal_investigator_nosearch

      # doppelganger
      match /look ?(.+)?/i,       :method => :doppelganger_look

      match /lynch (.+)/i,        :method => :lynch_vote
      match /vote (.+)/i,         :method => :lynch_vote
      match /unlynch/i,           :method => :revoke_lynch_vote
      match /status/i,            :method => :status
      match /who$/i,              :method => :list_players
      match /confirm/i,           :method => :confirm_role

      # other
      # match /invite/i,              :method => :invite
      # match /subscribe/i,           :method => :subscribe
      # match /unsubscribe/i,         :method => :unsubscribe
      match /help ?(.+)?/i,         :method => :help
      match /intro/i,               :method => :intro
      match /rules ?(.+)?/i,        :method => :rules
      match /settings$/i,           :method => :get_game_options
      match /settings (base|ultimate)/i, :method => :set_game_options
      match /roleset (set|add|remove) (.+)/i, :method => :set_game_roles
      match /roleset$/i,            :method => :get_game_roles

      match /changelog$/i,          :method => :changelog_dir
      match /changelog (\d+)/i,     :method => :changelog
      # match /about/i,               :method => :about

      match /forceroles (set|add|remove) (.+)/i, :method => :set_force_roles
      match /forceroles$/i,                       :method => :get_force_roles
      
      # mod only commands
      match /reset/i,              :method => :reset_game
      match /replace (.+?) (.+)/i, :method => :replace_user
      match /kick (.+)/i,          :method => :kick_user
      match /room (.+)/i,          :method => :room_mode
      match /roles$/i,             :method => :what_roles#can we remove this?

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
            User(m.user).send "--- HELP PAGE 1/1 ---"
            User(m.user).send "!join - joins the game"
            User(m.user).send "!leave - leaves the game"
            User(m.user).send "!start - starts the game"
            User(m.user).send "!roleset (set|add|remove) [role|variant ...] - sets, adds to, or removes from the roleset or variants"
            User(m.user).send "!rules (rolecount|onuwwroles|nightorder) - provides rules for the game; when provided with an argument, provides specified rules"
            User(m.user).send "!confirm - confirm your role (werewolves and villagers only)"
            User(m.user).send "!lynch (player) - vote for the player you wish to lynch"
            User(m.user).send "!unlynch - revoke your existing lynch vote, if any"
            User(m.user).send "!claim (role) - claim a role"
            User(m.user).send "!unclaim - revoke your existing role claim, if any"
            User(m.user).send "!claims - show the list of current role claims"
            User(m.user).send "!timer set (time) - Sets timer in minutes"
            User(m.user).send "!timer - Views time left"
            
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
        when "nightorder"
          User(m.user).send "1: Doppelganger, 2: Werewolves, 3: Minion, 4: Masons, 5: Seer, 5b: Apprentice Seer, 6: Robber, 7: Troublemaker, 8: Drunk, 9: Insomniac, 9a: Doppelganger/Insomniac, 11: Curator"
        when "completenightorder"
          User(m.user).send "0: Sentinel, 1: Doppelganger, 2: Werewolves, 2-B: Alpha Wolf, 2-C: Mystic Wolf, 3: Minion, 4: Mason, 5: Seer, 5-B: Apprentice Seer, 5-C: Paranormal Investigator, 6: Robber, 6-B: Witch, 7: Troublemaker, 7-B: Village Idiot, 7-C: Aura Seer, 8: Drunk, 9: Insomniac, 10: Revealer, 11: Curator"
        when "onuwwroles"
          User(m.user).send "Use !nightorder or !completenightorder for role names"
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
          m.reply @game.players.map{ |p| p.user.nick }.join(' ')
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
              if @game.ultimate?
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
                    Channel(@channel_name).send "Not enough roles specified; added Villagers for empty slots"
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
        Channel(@channel_name).send "Timer set to #{@game_timer_minutes.to_s} minutes." unless @game_timer_minutes.nil?
        if @game.ultimate?
          with_variants = @game.variants.empty? ? "" : " Using variants: #{self.game_settings[:variants].join(", ")}."
          roles_msg = @game.variants.include?(:blindrandom) ? "unknown roles" : "roles: #{self.game_settings[:roles].sort.join(", ")}"
          force_roles_msg = @game.force_roles.empty? ? "" : "Using non-middle roles #{@game.force_roles.join(", ")}."
          Channel(@channel_name).send "Using #{self.game_settings[:roles].count} #{roles_msg}.#{force_roles_msg}#{with_variants}" 
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

        unless @game_timer_minutes.nil?
          @game_timer = Timer(60, shots: @game_timer_minutes) do
            self.run_game_timer
          end
        end
      end

      def run_game_timer
        if [5, 2].any?{|i| i == @game_timer.shots}
          Channel(@channel_name).send "*** #{@game_timer.shots} MINUTES LEFT *** "
        elsif @game_timer.shots == 1
          Channel(@channel_name).send "*** 1 MINUTE LEFT *** "
        elsif @game_timer.shots == 0
          Channel(@channel_name).send "*** TIME IS UP! ***"
          Channel(@channel_name).send "Vote for a player to be lynched via bot private message."
          Channel(@channel_name).moderated = true
          Channel(@channel_name).voiced.each do |user|
            Channel(@channel_name).devoice(user)
          end

          ## MESSAGE UNVOTED PLAYERS!
        end
      end

      def start_night_phase2
        @game.finish_subphase1
        #Channel(@channel_name).send "Starting night reveal"
        self.night_reveal

        self.inform_artifacts

        self.start_day_phase
      end

      def check_for_day_phase
        if @game.waiting_on_role_confirm
          players_to_confirm=@game.not_confirmed
          #Channel(@channel_name).send("Waiting on #{players_to_confirm.join(", ")}")#testing
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
          elsif (target_player == player && @game.ultimate?)
            User(m.user).send "You may not vote to lynch yourself."
          else
            @game.lynch_vote(player, target_player)
            User(m.user).send "You have voted to lynch #{target_player}."

            self.check_for_lynch
          end
        end
      end

      def revoke_lynch_vote(m)
        if @game.started? && @game.has_player?(m.user)
          player = @game.find_player(m.user)

          previously_lynched_player = @game.lynch_votes[player]
          if previously_lynched_player.nil?
            User(m.user).send "You are already lynching no one."
          else
            @game.revoke_lynch_vote(player)
            User(m.user).send "Your vote to lynch #{previously_lynched_player} has been revoked."
          end
        end
      end

      def check_for_lynch
        if @game.all_lynch_votes_in?
          self.do_end_game
        end
      end

      def claim_role(m, role_string)
        if @game.started? && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          role = @game.parse_role(role_string)

          if role.nil?
            User(m.user).send "\"#{role_string}\" is an invalid role."
          else
            @game.claim_role(player, role)
            User(m.user).send "You have claimed the role of #{role.to_s}."
          end
        end
      end

      def unclaim_role(m)
        if @game.started? && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          previously_claimed_role = @game.claims[player]

          if previously_claimed_role.nil?
            User(m.user).send "You have not claimed a role."
          else
            @game.unclaim_role(player)
            User(m.user).send "Your claim of #{previously_claimed_role} has been revoked."
          end
        end
      end

      def list_claims(m)
        claims_message = @game.players.map{ |player|
          if @game.claims[player].nil?
            "#{player} - no claim"
          else
            "#{player} - #{@game.claims[player].upcase}"
          end
        }.join(', ')
        m.reply "Claims: #{claims_message}"
      end

      def confirm_role(m)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          if player.non_special? || player.dg_non_special?
            player.confirm_role
            User(m.user).send "Your role has been confirmed"
            self.check_for_day_phase
          else
            User(m.user).send "Role: #{player.role.upcase} does not need to confirm"
          end
        end
      end

      #def status(m) #this is already defined
      #  m.reply @game.check_game_state
      #end

      def mystic_wolf_view_player(m, view)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          
          if (player.mystic_wolf? || (player.doppelganger? && player.cur_role == :mystic_wolf))
            target_player = @game.find_player(view)
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            elsif target_player.nil?
              User(m.user).send "\"#{view}\" is an invalid target."
            elsif target_player == player
              User(m.user).send "You cannot view yourself."
            else
              player.action_take = {:mysticwolfplayer => target_player}              
              player.confirm_role
              User(m.user).send "Your action has been confirmed."
              self.check_for_day_phase
            end
          else
            User(m.user).send "You are not the MYSTIC WOLF."
          end
        end
      end
      
      def paranormal_investigator_search(m, target_name1, target_name2)
        #happens before paranormal investigator changes to a different role
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          if(player.paranormal_investigator? || (player.doppelganger? && player.cur_role== :paranormal_investigator))
            target_player1=@game.find_player(target_name1)
            target_player2=@game.find_player(target_name2)
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            elsif target_player1.nil? || target_player2.nil?
              User(m.user).send "You have specified an invalid target."
            elsif target_player1 == player || target_player2 == player
              User(m.user).send "You cannot search yourself"
            else

              player.action_take = {:paranormalinvestigatorsearch => [target_player1,target_player2]}
              player.confirm_role
              User(m.user).send "Your action has been confirmed"
              self.check_for_day_phase
            end
          else
            User(m.user).send "You are not the PARANORMAL INVESTIGATOR"
          end
        end
      end

      def paranormal_investigator_single_search(m, target_name1)
        #happens before paranormal investigator changes to a different role
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          if(player.paranormal_investigator? || (player.doppelganger? && player.cur_role== :paranormal_investigator))
            target_player1=@game.find_player(target_name1)
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            elsif target_player1.nil?
              User(m.user).send "You have specified an invalid target."
            elsif target_player1 == player
              User(m.user).send "You cannot search yourself"
            else
              player.action_take = {:paranormalinvestigatorsearch => [target_player1]}
              player.confirm_role
              User(m.user).send "Your action has been confirmed"
              self.check_for_day_phase
            end
          else
            User(m.user).send "You are not the PARANORMAL INVESTIGATOR"
          end
        end
      end

      def paranormal_investigator_nosearch(m)
        #happens before paranormal investigator changes to a different role
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          if (player.paranormal_investigator? || (player.doppelganger? && player.cur_role == :paranormal_investigator))
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            else
              player.action_take = {:paranormalinvestigatornosearch => "none"}
              player.confirm_role
              User(m.user).send "Your action has been confirmed"
              self.check_for_day_phase
            end
          else
            User(m.user).send "You are not the PARANORMAL INVESTIGATOR."
          end
        else
            User(m.user).send "Can't use this command at this time"
        end
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
              if @game.ultimate?
                player.action_take = {:seertable => @game.table_cards.shuffle.first(2)}
              else
                player.action_take = {:seertable => @game.table_cards}
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
            correct_role = @game.ultimate? ? "ROBBER" : "THIEF"
            User(m.user).send "You are not the #{correct_role}."
          end
        end
      end

      def thief_take_none(m)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)
          correct_role = @game.ultimate? ? "ROBBER" : "THIEF"

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

      def curator_gift_player(m, gifted)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)

          if (player.curator?)
            target_player = @game.find_player(gifted)
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            elsif target_player.nil?
              User(m.user).send "\"#{gifted}\" is an invalid target."
            else
              player.action_take = {:giftplayer => target_player}
              player.confirm_role
              User(m.user).send "Your action has been confirmed."
              self.check_doppel_curator
              self.check_for_day_phase
            end
          elsif (player.doppelganger? && player.cur_role == :curator)
            target_player = @game.find_player(gifted)
            curator = player.doppelganger_look[:dglook]
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            elsif !curator.confirmed?
              User(m.user).send "Please wait for the curator to take their night action."
            elsif target_player.nil?
              User(m.user).send "\"#{gifted}\" is an invalid target."
            elsif curator.action_take.has_key?(:giftplayer) && curator.action_take[:giftplayer] == target_player
              User(m.user).send "#{target_player} already has an artifact."
            else
              player.action_take = {:giftplayer => target_player}
              player.confirm_role
              User(m.user).send "Your action has been confirmed."
              self.check_for_day_phase
            end
          else
            User(m.user).send "You are not the CURATOR."
          end
        end
      end

      def curator_gift_none(m)
        if @game.started? && @game.waiting_on_role_confirm && @game.has_player?(m.user)
          player = @game.find_player(m.user)

          if (player.curator?)
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            else
              player.action_take = {:giftnone => "none"}
              player.confirm_role
              User(m.user).send "Your action has been confirmed."
              self.check_doppel_curator
              self.check_for_day_phase
            end
          elsif (player.doppelganger? && player.cur_role == :curator)
            curator = player.doppelganger_look[:dglook]
            if player.confirmed?
              User(m.user).send "You have already confirmed your action."
            elsif !curator.confirmed?
              User(m.user).send "Please wait for the curator to take their night action."
            else
              player.action_take = {:giftnone => "none"}
              player.confirm_role
              User(m.user).send "Your action has been confirmed."
              self.check_for_day_phase
            end
          else
            User(m.user).send "You are not the CURATOR."
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
            if player.confirmed? || !player.doppelganger_look.nil?
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
        when *NON_SPECIALS
          loyalty_msg = "You are a #{player.cur_role.upcase}. Type !confirm to confirm your role."
        when :seer
          loyalty_msg = "You are the SEER. What do you want to view? \"!view [player]\" \"!tableview\""#technically, this is optional
        when :mystic_wolf
          other_wolf = @game.wolves.reject{ |w| w == player }
          reveal_msg = other_wolf.empty? ? "You are a lone wolf." : "You look for other werewolves and see: #{other_wolf.join(", ")}. (A doppelwolf is unknown to mystic wolf.)"#"unknown to...": see known issue -- this is due to implementation, not due to game mechanics
          loyalty_msg = "You are the MYSTIC_WOLF. #{reveal_msg} Who do you want to view? \"!mysticview [player]\""#technically, this is optional
        when :alpha_wolf#alpha wolf is not optional -- the rules state "The Alpha Wolf /must/ exchange the center werewolf card..."
          loyalty_msg = "You are the ALPHA_WOLF. Who do you want to turn into a wolf? \"!wolfify [player]\"" #removed  or \"!nowolfify\
        when :paranormal_investigator
          loyalty_msg = "You are the PARANORMAL INVESTIGATOR. Who do you want to search? \"!search [player] [player]\" or \"!nosearch\""
        when :thief
          loyalty_msg = "You are the THIEF. Do you want to take a role? \"!thief [player]\", \"!tablethief\" or \"!nothief\""
        when :robber
          loyalty_msg = "You are the ROBBER. Do you want to take a role? \"!rob [player]\" or \"!norob\""
        when :curator
          if (player.old_doppelganger?)
            curator = player.doppelganger_look[:dglook]
            if curator.action_take.has_key?(:giftnone)
              loyalty_msg = "You are the DOPPELGANGER-CURATOR. There are no artifacts placed. Do you wish to give out an artifact? \"!gift [player]\" or \"!nogift\""
            elsif curator.action_take.has_key?(:giftplayer)
              if (curator.action_take.has_key?(:giftplayer) == player)
                loyalty_msg = "You are the DOPPELGANGER-CURATOR. There is an artifact in front of you. Do you wish to give out an artifact? \"!gift [player]\" or \"!nogift\""
              else
                loyalty_msg = "You are the DOPPELGANGER-CURATOR. There is an artifact in front of #{curator.action_take[:giftplayer]}. Do you wish to give out an artifact? \"!gift [player]\" or \"!nogift\""
              end
            else
              loyalty_msg = "You are the DOPPELGANGER-CURATOR. Please wait for the CURATOR to take their night action."
            end
          else
          loyalty_msg = "You are the CURATOR. Do you wish to give out an artifact? \"!gift [player]\" or \"!nogift\""
          end
        when :troublemaker
          loyalty_msg = "You are the TROUBLEMAKER. Do you want to switch the roles of two players? \"!switch [player1] [player2]\" or \"!noswitch\""
        when :doppelganger
          loyalty_msg = "You are the DOPPELGANGER. Who do you want to look at? \"!look [player]\""
        end
        User(player.user).send loyalty_msg
      end

      def check_doppel_curator
        for player in @game.doppelganger_curator
          curator = player.doppelganger_look[:dglook]
          if curator.action_take.has_key?(:giftnone)
            loyalty_msg = "There are no artifacts placed."
          elsif curator.action_take.has_key?(:giftplayer)
            if (curator.action_take[:giftplayer] == player)
              loyalty_msg = "There is an artifact in front of you."
            else
              loyalty_msg = "There is an artifact in front of #{curator.action_take[:giftplayer]}."
            end
          end
          loyalty_msg << " Do you wish to give out an artifact? \"!gift [player]\" or \"!nogift\""
          User(player.user).send loyalty_msg
        end
      end

      def night_reveal
        #Channel(@channel_name).send "Looking for doppelganger"
        artifacts = ARTIFACTS.keys.shuffle
        unless @game.old_doppelganger.nil?
        ###Doppelganger actions
          player = @game.old_doppelganger
          player.cur_role = player.role
          #Channel(@channel_name).send "---Player #{player} is a #{player.cur_role} and copied #{@game.doppelganger_role}"
          case @game.doppelganger_role
          when :mystic_wolf
            User(player.user).send "#{player.action_take[:mysticwolfplayer]} is #{role_as_text(player.action_take[:mysticwolfplayer].cur_role)}"
          when :minion
            werewolves = @game.wolves
            reveal_msg = werewolves.empty? ? "You do not see any werewolves." : "You look for werewolves and see: #{werewolves.join(", ")}."
            User(player.user).send reveal_msg
          when :seer
            if player.action_take.has_key?(:seerplayer)
              User(player.user).send "#{player.action_take[:seerplayer]} is #{role_as_text(player.action_take[:seerplayer].cur_role)}."
            elsif player.action_take.has_key?(:seertable)
              if @game.ultimate?
                seer_msg=player.action_take[:seertable].collect {|role| role_as_text(role)}.join(" and ")
                User(player.user).send "Two of the middle cards are: #{seer_msg}."
              else
                User(player.user).send "Middle is #{role_as_text(player.action_take[:seertable])}."
              end
            end
          when :apprentice_seer
            player.action_take[:apprentice_seer] = @game.table_cards.shuffle.first
            User(player.user).send "One of the middle cards is: #{role_as_text(player.action_take[:apprentice_seer])}."
          when :paranormal_investigator
            #User(player.user).send "You are a #{player.cur_role} and saw #{player.doppelganger_look[:dgrole]} and are searching..."
            if player.action_take.has_key?(:paranormalinvestigatorsearch)
              players_searched=player.action_take[:paranormalinvestigatorsearch]
              #User(player.user).send "Searching "+players_searched.join(", ")
              night_msg="You view "
              players_searched.each do |target_player|
                #here, doppelganger_look represents what role the doppleganger is now, rather than what role they looked at
                if(player.doppelganger_look[:dgrole]==:paranormal_investigator)#only continue searching if still PI
                  #User(player.user).send "Search/check #{target_player}"                
                  night_msg+="#{role_as_text(target_player.cur_role)} and "
                  if(target_player.wolf?)#no check for doppelganger
                    player.doppelganger_look[:dgrole] = :pi_werewolf
                    night_msg+="are now a WOLF"
                    player.action_take[:pi_became]=:wolf
                  elsif(target_player.tanner?)#no check for doppelganger
                    player.doppelganger_look[:dgrole] = :pi_tanner
                    night_msg+="are now a TANNER"
                    player.action_take[:pi_became]=:tanner
                  end
                end
              end
              if(player.doppelganger_look[:dgrole] == :paranormal_investigator)
                night_msg+="remain PARANORMAL INVESTIGATOR"
              end
              User(player.user).send night_msg          
            elsif player.action_take.has_key?(:paranormalinvestigatornosearch)
              User(player.user).send "You look at no one"
            end
            #User(player.user).send "After searching, you are a #{player.doppelganger_look[:dgrole]}"
          when :robber
            if player.action_take.has_key?(:thiefnone)
              User(player.user).send "You remain the #{player.role.upcase}"
            elsif player.action_take.has_key?(:thiefplayer)
              target_player = player.action_take[:thiefplayer]

              player.cur_role,target_player.cur_role = target_player.cur_role,player.cur_role
              User(player.user).send "You are now a #{role_as_text(player.action_take[:thiefplayer].role)}."
            end
          when :troublemaker
            if player.action_take.has_key?(:troublemakerplayer)
              player.action_take[:troublemakerplayer][0].cur_role,player.action_take[:troublemakerplayer][1].cur_role = player.action_take[:troublemakerplayer][1].cur_role,player.action_take[:troublemakerplayer][0].cur_role
            end
          when :drunk
            newrole = @game.table_cards.shuffle!.shift
            @game.table_cards.push(:doppelganger)
            player.cur_role = newrole
            player.action_take = {:drunk => newrole}
            User(player.user).send "You have exchanged your card with a card from the middle."
          when :curator
            if player.action_take.has_key?(:giftnone)
              User(player.user).send "You do not give out an artifact."
            elsif player.action_take.has_key?(:giftplayer)
              target_player = player.action_take[:giftplayer]
              player.action_take[:giftplayerartifact] = artifacts.shift
              User(player.user).send "You give #{target_player} an artifact."
              target_player.artifact = ARTIFACTS[player.action_take[:giftplayerartifact]]
            end
          end
        end
        ###end doppelganger actions

        #Channel(@channel_name).send("Finished looking for doppelganger")


        ###Wolf reveal, minion reveal...
        unless @game.waking_wolves.nil?
          @game.waking_wolves.each do |p|
            other_wolf = @game.wolves.reject{ |w| w == p }
            reveal_msg = other_wolf.empty? ? "You are a lone wolf." : "You look for other werewolves and see: #{other_wolf.join(", ")}."
            User(p.user).send reveal_msg
            if (other_wolf.empty? && @game.with_variant?(:lonewolf))
              p.action_take = {:lonewolf => @game.table_cards.shuffle.first }
              User(p.user).send "LONE WOLF: You see #{role_as_text(p.action_take[:lonewolf])} in the middle"
            end
          end
        end

        player = @game.find_player_by_role(:mystic_wolf)
        unless player.nil?
          target_player = player.action_take[:mysticwolfplayer]
          player.action_take[:mysticwolfplayerrole] = target_player.cur_role
          User(player.user).send "#{player.action_take[:mysticwolfplayer]} is #{role_as_text(player.action_take[:mysticwolfplayer].cur_role)}."
        end
        
        player = @game.find_player_by_role(:minion)
        unless player.nil?
          werewolves = @game.wolves
          reveal_msg = werewolves.empty? ? "You do not see any werewolves." : "You look for werewolves and see: #{werewolves.join(", ")}."
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
            target_player = player.action_take[:seerplayer]
            player.action_take[:seerplayerrole] = target_player.cur_role
            User(player.user).send "#{player.action_take[:seerplayer]} is #{role_as_text(player.action_take[:seerplayer].cur_role)}."
          elsif player.action_take.has_key?(:seertable)
            if @game.ultimate?
              seer_msg=player.action_take[:seertable].collect {|role| role_as_text(role)}.join(" and ")
              User(player.user).send "Two of the middle cards are: #{seer_msg}."
            else
              User(player.user).send "Middle is #{role_as_text(player.action_take[:seertable])}."
            end
          end
        end

        player = @game.find_player_by_role(:apprentice_seer)
        unless player.nil?
          player.action_take = {:apprentice_seer => @game.table_cards.shuffle.first }
          User(player.user).send "One of the middle cards is: #{role_as_text(player.action_take[:apprentice_seer])}."
        end

        #Channel(@channel_name).send("Looking for paranormal investigator")
        player = @game.find_player_by_role(:paranormal_investigator)
        unless player.nil?
          #unless player.action_take.nil?
          #  User(player.user).send "You took action "+player.action_take.keys.join(", ")
          #end
          if player.action_take.has_key?(:paranormalinvestigatorsearch)
            players_searched=player.action_take[:paranormalinvestigatorsearch]
            #User(player.user).send "Searching "+players_searched.join(", ")
            night_msg="You view "
            players_searched.each do |target_player|
              if(player.cur_role==:paranormal_investigator)#only continue searching if still PI
                #User(player.user).send "Search/check #{target_player}"                
                night_msg+="#{role_as_text(target_player.cur_role)} and "
                #User(player.user).send night_msg
                if(target_player.wolf? && !target_player.old_doppelganger?)#paranormal investigator doesn't switch roles
                  player.cur_role = :pi_werewolf
                  night_msg+="are now a WOLF"
                  player.action_take[:pi_became]=:wolf
                elsif(target_player.tanner? && !target_player.old_doppelganger?)#paranormal investigator doesn't switch roles
                  player.cur_role = :pi_tanner
                  night_msg+="are now a TANNER"
                  player.action_take[:pi_became]=:tanner
                end
              end
            end
            if(player.cur_role == :paranormal_investigator)
              night_msg+="remain PARANORMAL INVESTIGATOR"
            end
            User(player.user).send night_msg          
          elsif player.action_take.has_key?(:paranormalinvestigatornosearch)
            User(player.user).send "You look at no one"
          end
          #if player.action_take.has_key?(:pi_became)
          #  if player.action_take[:pi_became].nil?
          #     User(player.user).send "Done searching for info -- Became empty"            
          #  else
          #     User(player.user).send "Done searching for info -- Became is #{player.action_take[:pi_became]}" 
          #  end                         
          #else
          #  User(player.user).send "Done searching for info -- Became doesn't exist"            
          #end
        end

        if @game.ultimate?
          player = @game.find_player_by_role(:robber)
        else
          player = @game.find_player_by_role(:thief)
        end
        unless player.nil?
          if player.action_take.has_key?(:thiefnone)
            User(player.user).send "You remain the #{role_as_text(player.role)}"
          elsif player.action_take.has_key?(:thiefplayer)
            target_player = player.action_take[:thiefplayer]
            player.action_take[:thiefplayerrole] = target_player.cur_role
            User(player.user).send "You are now a #{role_as_text(player.action_take[:thiefplayer].cur_role)}."
            #User(player.user).send "---You take a role"
            player.cur_role,target_player.cur_role = target_player.cur_role,player.cur_role
          elsif player.action_take.has_key?(:thieftable)
            new_thief = @game.table_cards.shuffle.first
            player.action_take = {:thieftable => new_thief}
            player.cur_role = new_thief
            User(player.user).send "You are now a #{role_as_text(player.action_take[:thieftable])}."
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
            insomniac_role=p.old_doppelganger? ? "DOPPELGANGER" : "INSOMNIAC"
            reveal_msg = p.cur_role == p.role ? "You are still the #{insomniac_role}" : "You are now the #{role_as_text(p.cur_role)}."
            User(p.user).send reveal_msg
          end
        end

        player = @game.find_player_by_role(:curator)
        unless player.nil?
          if player.action_take.has_key?(:giftnone)
            User(player.user).send "You do not give out an artifact."
          elsif player.action_take.has_key?(:giftplayer)
            target_player = player.action_take[:giftplayer]
            player.action_take[:giftplayerartifact] = artifacts.shift
            User(player.user).send "You give #{target_player} an artifact."
            target_player.artifact = ARTIFACTS[player.action_take[:giftplayerartifact]]
          end
        end
      end

      def inform_artifacts
        players = []
        for player in @game.curator
          if player.action_take.has_key?(:giftplayer)
            target_player = player.action_take[:giftplayer]
            artifact = player.action_take[:giftplayerartifact]
            message = "You have been given the #{artifact}."
            message << " You are now a #{ARTIFACTS[artifact]}." if ARTIFACTS[artifact]
            User(target_player.user).send message
            players.push target_player
          end
        end
        unless players.empty?
          Channel(@channel_name).send "The following players have artifacts in front of them: #{players.join(", ")}"
        end

        #Channel(@channel_name).send("Finished with reveal")

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
          Channel(@channel_name).send "DOPPELGANGER looked at #{player.doppelganger_look[:dglook]} and became #{role_as_text(player.doppelganger_look[:dgrole])}"#shows role as they saw it
          unless player.action_take.nil?
            if player.action_take.has_key?(:mysticwolfplayer)
              Channel(@channel_name).send "DOPPLEGANGER-MYSTIC_WOLF looked at #{player.action_take[:mysticwolfplayer]} and saw: #{player.action_take[:mysticwolfplayer].role.upcase}"
            elsif player.action_take.has_key?(:paranormalinvestigatorsearch)              
              pi_result_msg=player.action_take.has_key?(:pi_became) ? "became a #{player.action_take[:pi_became].upcase}" : "remained the same"
              Channel(@channel_name).send "DOPPLEGANGER-PARANORMAL_INVESTIGATOR looked at #{player.action_take[:paranormalinvestigatorsearch].join(" and ")} and #{pi_result_msg}"
            elsif player.action_take.has_key?(:paranormalinvestigatornosearch)
              Channel(@channel_name).send "DOPPLEGANGER-PARANORMAL_INVESTIGATOR looked at no one}"
            elsif player.action_take.has_key?(:seerplayer)
              Channel(@channel_name).send "DOPPELGANGER-SEER looked at #{player.action_take[:seerplayer]} and saw: #{player.action_take[:seerplayer].role.upcase}"
            elsif player.action_take.has_key?(:seertable)
              seer_msg=player.action_take[:seertable].collect {|role| role_as_text(role)}.join(" and ")
              Channel(@channel_name).send "DOPPELGANGER-SEER looked at the table and saw: #{seer_msg}"
            elsif player.action_take.has_key?(:apprentice_seer)
              Channel(@channel_name).send "DOPPELGANGER-APPRENTICE_SEER looked at the table and saw #{player.action_take[:apprentice_seer].upcase}"
            elsif player.action_take.has_key?(:thiefnone)
              Channel(@channel_name).send "DOPPELGANGER-ROBBER took from no one"
            elsif player.action_take.has_key?(:thiefplayer)
              Channel(@channel_name).send "DOPPELGANGER-ROBBER took: #{player.action_take[:thiefplayer].role.upcase} from #{player.action_take[:thiefplayer]}"
            elsif player.action_take.has_key?(:troublemakernone)
              Channel(@channel_name).send "DOPPELGANGER-TROUBLEMAKER switched no one"
            elsif player.action_take.has_key?(:troublemakerplayer)
              Channel(@channel_name).send "DOPPELGANGER-TROUBLEMAKER switched: #{player.action_take[:troublemakerplayer].join(" and ")}"
            elsif player.action_take.has_key?(:drunk)
              Channel(@channel_name).send "DOPPELGANGER-DRUNK drew #{player.action_take[:drunk].upcase} from the table"
            end
          end
        end

        if (@game.with_variant?(:lonewolf) && @game.wolves.count == 1)
          player = @game.wolves[0]
          Channel(@channel_name).send "LONE WOLF saw #{player.action_take[:lonewolf].upcase} in the middle" unless player.dream_wolf?
        end
        
        player = @game.find_player_by_role(:mystic_wolf)
        unless player.nil?
          Channel(@channel_name).send "MYSTIC_WOLF looked at #{player.action_take[:mysticwolfplayer]} and saw: #{player.action_take[:mysticwolfplayer].role.upcase}"
        end

        player = @game.find_player_by_role(:seer)
        unless player.nil?
          if player.action_take.has_key?(:seerplayer)
            Channel(@channel_name).send "SEER looked at #{player.action_take[:seerplayer]} and saw: #{player.action_take[:seerplayerrole].upcase}"
          elsif player.action_take.has_key?(:seertable)
            Channel(@channel_name).send "SEER looked at the table and saw: #{player.action_take[:seertable].map(&:upcase).join(" and ")}"
          end
        end

        player = @game.find_player_by_role(:apprentice_seer)
        unless player.nil?
          Channel(@channel_name).send "APPRENTICE_SEER looked at the table and saw #{player.action_take[:apprentice_seer].upcase}"
        end

        player = @game.find_player_by_role(:paranormal_investigator)
        unless player.nil?
          if player.action_take.has_key?(:paranormalinvestigatorsearch)
              pi_result_msg=player.action_take.has_key?(:pi_became) ? "became a #{player.action_take[:pi_became].upcase}" : "remained the same"
              Channel(@channel_name).send "PARANORMAL_INVESTIGATOR looked at #{player.action_take[:paranormalinvestigatorsearch].join(" and ")} and #{pi_result_msg}"
          elsif player.action_take.has_key?(:paranormalinvestigatornosearch)
              Channel(@channel_name).send "PARANORMAL_INVESTIGATOR looked at no one"
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
            Channel(@channel_name).send "ROBBER took: #{player.action_take[:thiefplayerrole].upcase} from #{player.action_take[:thiefplayer]}"
          end
        end

        player = @game.find_player_by_role(:troublemaker)
        unless player.nil?
          if player.action_take.has_key?(:troublemakernone)
            Channel(@channel_name).send "TROUBLEMAKER switched no one"
          elsif player.action_take.has_key?(:troublemakerplayer)
            Channel(@channel_name).send "TROUBLEMAKER switched: #{player.action_take[:troublemakerplayer].join(" and ")}"
          end
        end

        player = @game.find_player_by_role(:drunk)
        unless player.nil?
          Channel(@channel_name).send "DRUNK drew #{player.action_take[:drunk].upcase} from the table"
        end

        player = @game.find_player_by_role(:curator)
        unless player.nil?
          if (player.action_take.has_key?(:giftnone))
            Channel(@channel_name).send "CURATOR gave no artifacts"
          elsif (player.action_take.has_key?(:giftplayer))
            Channel(@channel_name).send "CURATOR gave #{player.action_take[:giftplayer]} the #{player.action_take[:giftplayerartifact]}"
          end
        end

        player = @game.old_doppelganger
        unless player.nil? || player.action_take.nil?
          if (player.action_take.has_key?(:giftnone))
            Channel(@channel_name).send "DOPPELGANGER-CURATOR gave no artifacts"
          elsif (player.action_take.has_key?(:giftplayer))
            Channel(@channel_name).send "DOPPELGANGER-CURATOR gave #{player.action_take[:giftplayer]} the #{player.action_take[:giftplayerartifact]}"
          end
        end

        # show ending role result
        roles_msg = @game.players.map{ |player|
          if (player.role != player.cur_role || player.old_doppelganger? || player.artifact)
        Format(:bold, "#{player} - #{player.cur_role.upcase}#{
              "-#{@game.doppelganger_role.upcase}" if (!@game.old_doppelganger.nil? && player.cur_role == :doppelganger)}#{
              " (#{player.artifact.upcase})" if (player.artifact)}")
          else
            "#{player} - #{player.cur_role.upcase}"
          end
        }.join(', ')

        Channel(@channel_name).send "Ending Roles: #{roles_msg}"

        unless @game.old_doppelganger.nil?
          player = @game.find_player_by_cur_role(:doppelganger)
          dg_player = @game.old_doppelganger
          unless player.nil?
            player.cur_role = dg_player.doppelganger_look[:dgrole]
          end
        end

        # replace everyones starting roles with stolen roles
        @game.players.map do |player|
          player.role = player.cur_role
        end

        # replace players with artifacts with new roles
        @game.players.map do |player|
          player.role = player.artifact if player.artifact
        end

        @game.players.map do |player|
          if player.role?(:pi_werewolf)#pi_werewolf is also listed as a wolf role
            player.role=:werewolf
          elsif player.role?(:pi_tanner)#pi_tanner is not listed as a tanner role (there is no list)
            player.role=:tanner
          end
        end
          
        lynch_totals = @game.lynch_totals

        # sort from max to min
        lynch_totals = lynch_totals.sort_by{ |vote, voters| voters.size }.reverse

        lynch_msg = lynch_totals.map do |voted, voters|
          "#{voters.count} - #{voted}#{voted.prince? ? '*' : ''} (#{voters.map{|voter| "#{voter}#{voter.bodyguard? ? '*' : ''}"}.join(', ')})"
        end.join(', ')
        Channel(@channel_name).send "Final Votes: #{lynch_msg}"

        Channel(@channel_name).send "BODYGUARD#{@game.bodyguard.size > 1 ? "S protect" : " protects"} #{@game.bodyguard.map{|p| @game.lynch_votes[p]}.uniq.join(", ")}" unless @game.bodyguard.empty?

        # find all cursed who became wolves and then make them wolves, in case a cursed votes for another cursed
        curselist = []
        lynch_totals.map do |voted, voters|
          if voted.cursed? && voters.detect{|p| p.wolf?}
            curselist.push voted
          end
        end

        for player in curselist
          Channel(@channel_name).send "CURSED #{player} becomes a wolf!"
          player.role = :werewolf
        end

        # Remove players who are either a prince or were voted for by a bodyguard
        can_lynch = lynch_totals.reject { |voted, voters| @game.protected.include?(voted) }

        # grab the first person lynched and see if anyone else matches them
        first_lynch = can_lynch.first
        lynching = can_lynch.select { |voted, voters| voters.count == first_lynch[1].count }
        lynching = lynching.map{ |voted, voters| voted}

        # Check for hunter(s) and add their target(s)
        # Do multiple times in case hunters point at other hunters
        hunter_target = []
        @game.hunter.size.times do
              if (lynching.detect{ |l| l.hunter? && !@game.protected.include?(l)} && first_lynch && first_lynch[1].count > 1)
                hunter_target = lynching.map { |lynched|
                  @game.lynch_votes[lynched] if lynched.hunter?
                }
                hunter_target.reject! { |r| r.nil? }
                (lynching += hunter_target).uniq!
              end
        end

        Channel(@channel_name).send "HUNTER chooses: #{hunter_target.empty? ? "No one" : hunter_target.map{|p| "#{p}#{"*" if @game.protected.include?(p)}"}.join(', ')}." if (lynching.detect{ |l| l.hunter? && !@game.protected.include?(l)} && first_lynch && first_lynch[1].count > 1)
        lynching.reject! { |p| @game.protected.include?(p) }

        lynched_players = (!first_lynch || first_lynch[1].count == 1) ? "No one is lynched!" : "#{lynching.join(', ')}!"
        Channel(@channel_name).send "Lynched players: #{lynched_players}"

        # return victory result
        # we lynched someone
        if first_lynch && first_lynch[1].count > 1
          # werewolf lynched villagers win
          if lynching.detect { |l| l.wolf? }
            if lynching.detect { |l| l.tanner? }
              dead_tanner = lynching.select{ |l| l.tanner? }
              Channel(@channel_name).send "Villager team and Tanner WIN! Villager Team: #{@game.humans.join(', ')}. Tanner: #{dead_tanner.join(', ')}."
            elsif @game.humans.empty?
              Channel(@channel_name).send "No one wins..."
            else
              Channel(@channel_name).send "Villager team WINS! Team: #{@game.humans.join(', ')}."
            end
          # no werewolf lynched, werewolves win
          else
            if lynching.detect { |l| l.tanner? }
              dead_tanner = lynching.select{ |l| l.tanner? }
              Channel(@channel_name).send "TANNER WINS! Tanner: #{dead_tanner.join(', ')}."
            elsif @game.wolves.empty?
              if lynching.detect { |l| l.good? }#a human was lynched
                minion_msg = @game.minion.empty? ? " Everyone loses...womp wahhhhhh." : "Minion: #{@game.minion.join(', ')}."
                Channel(@channel_name).send "Werewolves WIN!#{minion_msg}"
              else#someone was lynched, but none are a werewolf, tanner, or human
                Channel(@channel_name).send "Werewolves WIN! Everyone loses...womp wahhhhhh."
              end
            else
              minion_msg = @game.minion.empty? ? "" : " Minion: #{@game.minion.join(', ')}."
              Channel(@channel_name).send "Werewolf team WINS! Team: #{@game.wolves.join(', ')}.#{minion_msg}"
            end
          end
        # no one is lynched
        else
          if @game.wolves.empty?
            Channel(@channel_name).send "Villager team WINS! Team: #{@game.humans.join(', ')}."
          else
            minion_msg = @game.minion.empty? ? "" : " Minion: #{@game.minion.join(', ')}."
            Channel(@channel_name).send "Werewolf team WINS! Team: #{@game.wolves.join(', ')}.#{minion_msg}"
          end
        end
        #Channel(@channel_name).send "---(Stopping game timer)"
        unless @game_timer_minutes.nil?
          @game_timer.stop
        end
        #Channel(@channel_name).send "---(Game timer no longer running)"
        self.start_new_game
      end

      def start_new_game
        #with_variants = @game.variants.empty? ? "" : " Using variants: #{self.game_settings[:variants].join(", ")}."
        #roles_msg = @game.variants.include?(:blindrandom) ? "unknown roles" : "roles: #{self.game_settings[:roles].sort.join(", ")}"
        #Channel(@channel_name).send "---Type !start (after players join) to play another game using #{self.game_settings[:roles].count} #{roles_msg}.#{with_variants}" 

        Channel(@channel_name).moderated = false
        @game.players.each do |p|
          Channel(@channel_name).devoice(p.user)
        end
        @game = Game.new(@game.roles)
        @idle_timer.start
        @game_timer = nil
        @game_timer_minutes = nil
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
          Channel(@channel_name).moderated = false
          self.devoice_channel
          Channel(@channel_name).send "The game has been reset."
          @idle_timer.start
          @game_timer_minutes = nil
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
              User(m.user).send "Roles: #{self.game_settings[:roles].sort.join(", ")}" if @game.variants.include?(:blindrandom)
              User(m.user).send "Starting Roles: #{roles_msg}"
              if @game.day?
                roles_msg = @game.players.map{ |player|
                if (player.role != player.cur_role || player.old_doppelganger?)
                  if (!@game.old_doppelganger.nil? && player.cur_role == :doppelganger)
                    Format(:bold, "#{player} - #{player.cur_role.upcase}-#{@game.doppelganger_role.upcase}")
                  else
                    Format(:bold, "#{player} - #{player.cur_role.upcase}")
                  end
                else
                  "#{player} - #{player.cur_role.upcase}"
                end
                }.join(', ')
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

      def set_timer(m, minutes)
        min = minutes.to_i
        if min.is_a?(Integer) && min > 0
          @game_timer_minutes = min
          Channel(@channel_name).send "Timer set to #{minutes} minutes."
        else 
          Channel(@channel_name).send "That's not a valid number."
        end
      end

      def turn_off_timer(m)
        @game_timer_minutes = nil
        Channel(@channel_name).send "Timer turned off."
      end

      def check_timer(m)
        if @game_timer
           m.reply "Timer: #{@game_timer.shots} minutes remaining."
        else
           m.reply "There is no timer running for this game."
        end
      end

      def get_game_options(m)
        with_variants = @game.variants.empty? ? "" : " Using variants: #{self.game_settings[:variants].join(", ")}."
        if @game.ultimate?
          roles_msg = @game.variants.include?(:blindrandom) ? "unknown roles" : "roles: #{self.game_settings[:roles].sort.join(", ")}"
          m.reply "Game settings: Ultimate. Using #{self.game_settings[:roles].count} #{roles_msg}.#{with_variants}"
        else
          m.reply "Game settings: base.#{with_variants}"
        end
      end

      def set_game_options(m, game_type)
        # this is really really wonky =(
        # lots of stupid user checking
        # im sure theres a better way but im lazy
        unless @game.started?
          game_change_prefix = m.channel.nil? ? "#{m.user.nick} has changed the game" : "The game has been changed"
          if game_type.downcase == "base"
            @game.change_type :base
            game_type_message = "#{game_change_prefix} to base."
          else           
            roles = ["werewolf", "werewolf", "seer", "robber", "troublemaker", "villager"]
            @game.change_type :ultimate, :roles => roles
            roles_msg = "roles: #{self.game_settings[:roles].sort.join(", ")}" 
            game_type_message = "#{game_change_prefix} to Ultimate. Using #{self.game_settings[:roles].count} #{roles_msg}."
          end
          Channel(@channel_name).send "#{game_type_message}"
        end
      end

      def set_force_roles(m, action, roles = "")
        unless ALLOW_FORCE
          Channel(@channel_name).send("Forcing roles has been disabled")
          return
        end
            Channel(@channel_name).send("Received #{roles.split(" ").length} roles #{roles}")
            if action == 'add'
            options = @game.force_roles.map(&:to_s) + roles.downcase.split(" ")
            elsif action == 'remove'
              options = @game.force_roles.subtract_once(roles.downcase.split(" "))
            elsif action == 'set'
              options = roles.downcase.split(" ")
            end

            force_options    = options.collect{ |opt| @game.parse_role(opt) }.reject{ |opt| opt.nil? }
            rejected        = options.reject{ |opt| @game.parse_role(opt)}

            Channel(@channel_name).send("Processing #{force_options.length} options #{force_options.join(", ")}")

            ROLE_COUNTS.each do |vr, range|
              count = options.count(vr.to_s)
              #Channel(@channel_name).send("Checking role " + vr.to_s + "(chose #{count} of them)")             
              if count > range.max && range.max == 0
                force_options = nil
                Channel(@channel_name).send "#{vr} is not yet implemented."
              elsif count > range.max
                force_options = nil
                Channel(@channel_name).send "You have included #{vr} too many times."
              elsif count == 0 && range.min > 0
                force_options = nil
                Channel(@channel_name).send "You must include at least one #{vr}."
              elsif !range.include?(count)
                force_options = nil
                Channel(@channel_name).send "You have chosen an invalid number of #{vr}."
              end
            end
            
            if rejected.count > 0
              Channel(@channel_name).send "Unknown roles specified: #{rejected.join(", ")}."
            end

           if !force_options.nil?
             @game.force_roles=force_options
             Channel(@channel_name).send "Forcing roles: #{@game.force_roles.sort.join(", ")}"
           else
             Channel(@channel_name).send "Attempt to change force roles unsuccessful."
           end                        
      end        

      def get_force_roles(m)
          if !@game.force_roles.nil?
             Channel(@channel_name).send "Forcing roles: #{@game.force_roles.sort.join(", ")}"
          end
      end


      def set_game_roles(m, action, roles = "") 
        # this is really really wonky =(
        # lots of stupid user checking
        # im sure theres a better way but im lazy
        unless @game.started?
          if @game.ultimate?
            # game_change_prefix = m.channel.nil? ? "#{m.user.nick} has changed the game" : "The game has been changed"

            if action == 'add'
              options = @game.roles.map(&:to_s) + roles.downcase.split(" ")
            else
              options = roles.downcase.split(" ")
            end

            role_options    = options.collect{ |opt| @game.parse_role(opt) }.reject{ |opt| opt.nil? }
            variant_options = options.select{ |opt| VALID_VARIANTS.include?(opt) }
            rejected        = options.reject{ |opt| @game.parse_role(opt) || VALID_VARIANTS.include?(opt) }

            if action == 'remove'
              if role_options.include?(:mason)
                role_options += [:mason]
              end
              role_options = @game.roles.subtract_once(role_options)
            end

            if variant_options.include?("random") && variant_options.include?("blindrandom")
              role_options = nil
              game_options = nil
              Channel(@channel_name).send "You cannot specify both random and blindrandom."
            elsif (variant_options.include?("random") || variant_options.include?("blindrandom"))
              valid_random_role_options = RANDOM_ROLES
              if !role_options.empty?
                game_options = nil
                role_options = nil
                Channel(@channel_name).send "You cannot specify roles when using random or blindrandom"
              elsif variant_options.include?("random")
                roles = valid_random_role_options.sample(@game.player_count + 2)
                if (roles.include?(:mason) && roles.count(:mason) == 1)
                  roles = roles.reject{|r| r == :mason}.sample(@game.player_count)
                  roles += [:mason]
                end
                roles += [:werewolf]
                role_options = roles
              elsif variant_options.include?("blindrandom")
                valid_random_role_options += [:werewolf, :mason]
                roles = valid_random_role_options.sample(@game.player_count + 3)
                role_options = roles 
              end
            end

            roles = role_options
            unless variant_options.include?("blindrandom")
              ROLE_COUNTS.each do |vr, range|
                count = roles.count(vr)
                if count > range.max && range.max == 0
                  role_options = nil
                  Channel(@channel_name).send "#{vr} is not yet implemented."
                elsif count > range.max
                  role_options = nil
                  Channel(@channel_name).send "You have included #{vr} too many times."
                elsif count == 0 && range.min > 0
                  role_options = nil
                  Channel(@channel_name).send "You must include at least one #{vr}."
                elsif !range.include?(count)
                  role_options = nil
                  Channel(@channel_name).send "You have chosen an invalid number of #{vr}."
                end
              end
            end
            if rejected.count > 0
              Channel(@channel_name).send "Unknown roles specified: #{rejected.join(", ")}."
            end

            unless role_options.nil?
              roles += [:mason] if (roles.include?(:mason) && roles.count(:mason) == 1 && !variant_options.include?("blindrandom"))
              @game.change_type :ultimate, :roles => roles, :variants => variant_options
              roles_msg = @game.variants.include?(:blindrandom) ? "unknown roles" : "roles: #{self.game_settings[:roles].sort.join(", ")}" 
              game_type_message = "Using #{self.game_settings[:roles].count} #{roles_msg}."
            end
          
            with_variants = self.game_settings[:variants].empty? ? "" : " Using variants: #{self.game_settings[:variants].join(", ")}."
            Channel(@channel_name).send "#{game_type_message}#{with_variants}"
          else
            Channel(@channel_name).send "Must be set to \"ultimate\" to work."
          end
        end
      end

      def get_game_roles(m)
        roles_msg = @game.variants.include?(:blindrandom) ? "unknown roles" : "roles: #{self.game_settings[:roles].sort.join(", ")}" 
        game_type_message = "Using #{self.game_settings[:roles].count} #{roles_msg}."
        force_roles_msg = @game.force_roles.empty? ? "" : "Using non-middle roles #{@game.foce_roles.join(", ")}."
          
        with_variants = self.game_settings[:variants].empty? ? "" : " Using variants: #{self.game_settings[:variants].join(", ")}."
         m.reply "#{game_type_message}#{force_roles_msg}#{with_variants}"

      end

      def game_settings
        settings = {}
        settings[:roles] = @game.roles
        settings[:variants] = []
        if @game.ultimate?
          settings[:variants] << "Lone Wolf" if @game.variants.include?(:lonewolf)
          settings[:variants] << "Random" if @game.variants.include?(:random)
          settings[:variants] << "Blind Random" if @game.variants.include?(:blindrandom)
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

      def role_as_text(input_role)
        if input_role==:pi_werewolf || input_role==:pi_tanner
          return "PARANORMAL_INVESTIGATOR"
        else
          return input_role.upcase
        end
      end

    end#end class
  end
end

# HELPER METHODS
# 
class Array
  def subtract_once(values)
    counts = values.inject(Hash.new(0)) { |h, v| h[v] += 1; h }
    reject { |e| counts[e] -= 1 unless counts[e].zero? }
  end
end
