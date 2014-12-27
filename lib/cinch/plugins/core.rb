require 'json'
require_relative 'constants'

#================================================================================
# GAME
#================================================================================

$player_count = 0

class Game

  attr_accessor :started, :phase, :subphase, :players, :type, :roles, :variants, :player_cards, :table_cards, :start_table_cards, :lynch_votes, :claims, :invitation_sent, :force_roles, :revealed_cards

  def initialize(init_roles = DEFAULT_ULTIMATE_ROLES)
    self.started         = false
    self.players         = []
    self.type            = :ultimate
    self.roles           = init_roles
    self.variants        = []
    self.invitation_sent = false
    self.player_cards    = []
    self.table_cards     = []
    self.start_table_cards=[]
    self.phase           = :night # starts on night phase
    self.subphase        = 1
    self.lynch_votes     = {}
    self.claims          = {}
    self.force_roles     = []
    self.revealed_cards  = {}
  end

  #----------------------------------------------
  # Game Status
  #----------------------------------------------

  def started?
    self.started == true
  end

  def not_started?
    self.started == false
  end

  def accepting_players?
    self.not_started? && ! self.at_max_players?
  end

  #----------------------------------------------
  # Game Setup
  #----------------------------------------------

  # Player handlers

  def max_players
    if self.ultimate?
      ONUWW_MAX_PLAYERS
    else
      MAX_PLAYERS
    end
  end

  def at_max_players?
    if self.ultimate?
      self.player_count == ONUWW_MAX_PLAYERS
    else
      self.player_count == MAX_PLAYERS
    end
  end

  def at_min_players?
    self.player_count >= MIN_PLAYERS
  end

  def add_player(user)
    added = nil
    unless self.has_player?(user)
      new_player = Player.new(user)
      self.players << new_player
      added = new_player
    end
    added
  end

  def has_player?(user)
    found = self.find_player(user)
    found.nil? ? false : true
  end

  def remove_player(user)
    removed = nil
    player = self.find_player(user)
    unless player.nil?
      self.players.delete(player)
      removed = player
    end
    removed
  end

  def change_type(type, options = {})
    self.type = type
    if type == :ultimate
      self.roles = options[:roles]
      unless options[:variants].nil?
        self.variants = options[:variants].map(&:to_sym)
      end
      max_players = 10
    else
      self.roles = []
      unless options[:variants].nil?
        self.variants = options[:variants].map(&:to_sym)
      end
      max_players = 6
    end
  end

  def ultimate?
    self.type == :ultimate
  end

  def with_variant?(variant)
    self.variants.include?(variant)
  end

  def with_role?(role)
    self.roles.include?(role)
  end

  # Invitation handlers

  def mark_invitation_sent
    self.invitation_sent = true
  end

  def reset_invitation
    self.invitation_sent = false
  end

  def invitation_sent?
    self.invitation_sent == true
  end

  #----------------------------------------------
  # Game
  #----------------------------------------------

  # Starts up the game
  #
  def start_game!
    self.started = true
    self.players.shuffle!
    self.pass_out_roles
    $player_count = self.player_count
  end

  # Shuffle the deck, pass out roles
  # Force roles assumes roles were shuffled already in start_game
  def pass_out_roles
    # assign loyalties
    if self.ultimate?
      gameroles = self.roles.dup
    else
      extra_players = self.player_count - MIN_PLAYERS
      gameroles = BASE_ROLES + [:villager]*extra_players
    end
    alpha_wolf = gameroles.include?(:alpha_wolf)

    gameroles.shuffle!
    game_force_roles = self.force_roles.dup
    self.players.each do |player|
      if game_force_roles.empty?
        role = gameroles.shift
      else
        role = game_force_roles.shift
        if gameroles.include?(role)
          gameroles.delete_at(gameroles.index(role))
        end
      end
      self.player_cards << role
      player.receive_role( role )
    end
    self.table_cards = gameroles.take(3)
    self.start_table_cards = table_cards.clone
    if (alpha_wolf)
      # TODO: add extra wolf for alpha wolf
    end
  end

  # Claims

  def claim_role(player, role)
    self.claims[player] = role
  end

  def unclaim_role(player)
    self.claims.delete(player)
  end

  # Lynch votes

  def lynch_vote(player, target_player)
    self.lynch_votes[player] = target_player
  end

  def revoke_lynch_vote(player)
    self.lynch_votes.delete(player)
  end

  def not_voted
    all_players = self.players
    voted_players = self.lynch_votes.keys
    not_voted = all_players.reject{ |player| voted_players.include?(player) }
    not_voted
  end

  def all_lynch_votes_in?
    self.not_voted.size == 0
  end

  def not_confirmed
    all_players = self.players
    not_confirmed_players = all_players.select{ |player| !player.confirmed? }
    not_confirmed_players
  end

  def all_roles_confirmed?
    self.not_confirmed.size == 0
  end

  def lynch_totals
    totals = {}
    self.lynch_votes.each do |voter, voted|
      totals[voted] = [] if totals[voted].nil?
      totals[voted] << voter
    end
    totals
  end

  def check_game_state
    if self.started? && self.day?
      status = "Waiting on players to vote: #{self.not_voted.map(&:user).join(", ")}"
    elsif self.started? && self.night?
      status = "Waiting on players to confirm role: #{self.not_confirmed.map(&:user).join(", ")}"
    else
      if self.player_count.zero?
        status = "No game in progress."
      else
        status = "Game is forming. #{player_count} player(s) have joined: #{self.players.map(&:user).join(", ")}"
      end
    end
    status
  end

  # GAME STATE

  def waiting_on_role_confirm
    !self.all_roles_confirmed?
  end

  def change_to_day
    self.phase = :day
  end

  def finish_subphase1
    self.subphase = 2
  end

  def day?
    self.phase == :day
  end

  def night?
    self.phase == :night
  end

  def night_subphase1?
    self.subphase == 1
  end

  #----------------------------------------------
  # Helpers
  #----------------------------------------------

  def player_count
    self.players.count
  end

  def find_player(user)
    self.players.find{ |p| p.user == user }
  end

  def find_player_by_role(role)
    self.players.find{ |p| p.role == role && !p.old_doppelganger? }
  end

  def find_player_by_cur_role(role)
    self.players.find{ |p| p.cur_role == role }
  end

  def werewolves
    self.players.select{ |p| p.werewolf? || p.dg_role?(:werewolf) }
  end

  def wolves
    self.players.select{ |p| p.wolf? || WOLF_ROLES.any?{ |role| p.dg_role?(role) } }
  end

  def waking_wolves #mystic wolf is a waking wolf, but given some wolf info during information
    self.wolves.reject{ |p| p.dream_wolf? || p.dg_role?(:dream_wolf) }
  end

  def humans
    self.players.select{ |p| p.good? }
  end

  def masons
    self.players.select{ |p| p.mason? || p.dg_role?(:mason)}
  end

  def insomniacs
    self.players.select{ |p| p.insomniac? || p.dg_role?(:insomniac)}
  end

  def minion
    self.players.select{ |p| p.minion? }
  end

  def hunter
    self.players.select{ |p| p.hunter? }
  end

  def prince
    self.players.select{ |p| p.prince? }
  end

  def bodyguard
    self.players.select{ |p| p.bodyguard? }
  end

  def cursed
    self.players.select{ |p| p.cursed? }
  end
  
  def mystic_wolf
    self.players.select{ |p| p.mystic_wolf? }
  end

  def apprentice_seer
    self.players.select{ |p| p.apprentice_seer? }
  end

  def curator
    self.players.select{ |p| p.curator? || p.dg_role?(:curator) }
  end

  def protected
      self.players.select{ |p| p.prince? || bodyguard.map{|bg| self.lynch_votes[bg]}.include?(p) }
  end

  def non_special
    self.players.select{ |p| p.non_special? }
  end

  def old_doppelganger
    self.players.find{ |p| p.old_doppelganger? }
  end

  def doppelganger_curator
    self.players.select{ |p| p.dg_role?(:curator) }
  end

  def doppelganger_role
    self.players.find{ |p| p.old_doppelganger? }.doppelganger_look[:dgrole]
  end
  
  def parse_role(role_string)
    case role_string
    when "ars", "auraseer", "aura_seer"
      role = :aura_seer
    when "aps", "apprenticeseer", "apprentice_seer"
      role = :apprentice_seer
    when "aw", "alphawolf", "alpha_wolf"
      role = :alpha_wolf
    when "bg", "bodyguard"
      role = :bodyguard
    when "ctr", "curator"
      role = :curator
    when "csd", "cursed"
      role = :cursed
    when "dg", "doppelganger", "doppleganger"
      role = :doppelganger
    when "dw", "dreamwolf", "dream_wolf"
      role = :dream_wolf
    when "dk", "drunk"
      role = :drunk
    when "h", "hunter"
      role = :hunter
    when "i", "insomniac"
      role = :insomniac
    when "msn", "mason", "masons"
      role = :mason
    when "mnn", "minion"
      role = :minion
    when "mw", "mysticwolf", "mystic_wolf"
      role = :mystic_wolf
    when "pi", "paranormal_investigator"
      role = :paranormal_investigator
    when "pr", "prince"
      role = :prince
    when "rbr", "robber"
      role = :robber
    when "rvl", "revealer"
      role = :revealer
    when "sr", "seer"
      role = :seer
    when "stl", "sentinel"
      role = :sentinel
    when "tm", "troublemaker"
      role = :troublemaker
    when "tnr", "tanner"
      role = :tanner
    when "vi", "villageidiot", "village_idiot"
      role = :village_idiot
    when "v", "vgr", "villager"
      role = :villager
    when "wtc", "witch"
      role = :witch
    when "ww", "werewolf"
      role = :werewolf
    end
    role
  end
end

#================================================================================
# PLAYER
#================================================================================

class Player

  attr_accessor :user, :role, :cur_role, :action_take, :doppelganger_look, :confirm, :artifact

  def initialize(user)
    self.user = user
    self.role = nil
    self.cur_role = nil
    self.action_take = {}
    self.doppelganger_look = nil
    self.confirm = false
    self.artifact = nil
  end

  def receive_role(role)
    self.role = role
    self.cur_role = role
  end

  def confirm_role
    self.confirm = true
  end

  def to_s
    self.user.nick
  end

  def alpha_wolf?
    self.role == :alpha_wolf
  end

  def apprentice_seer?
    self.role == :apprentice_seer
  end

  def aura_seer?
    self.role == :aura_seer
  end

  def bodyguard?
    self.role == :bodyguard
  end

  def curator?
    self.role == :curator
  end

  def cursed?
    self.role == :cursed
  end

  def dream_wolf?
    self.role == :dream_wolf
  end

  def drunk?
    self.role == :drunk
  end

  def doppelganger?
    self.role == :doppelganger
  end

  def hunter?
    self.role == :hunter
  end

  def insomniac?
    self.role == :insomniac
  end

  def mason?
    self.role == :mason
  end

  def minion?
    self.role == :minion
  end

  def mystic_wolf?
    self.role == :mystic_wolf
  end

  def paranormal_investigator?
    self.role == :paranormal_investigator
  end

  def prince?
    self.role == :prince
  end

  def revealer?
    self.role == :revealer
  end

  def robber?
    self.role == :robber
  end

  def seer?
    self.role == :seer
  end

  def sentinel?
    self.role == :sentinel
  end

  def tanner?
    self.role == :tanner
  end


  def thief?
    self.role == :thief
  end

  def troublemaker?
    self.role == :troublemaker
  end
  
  def villager?
    self.role == :villager
  end

  def village_idiot?
    self.role == :village_idiot
  end

  def werewolf?
    self.role == :werewolf
  end

  def witch?
    self.role == :witch
  end

  def wolf?#doppelwolf counts as a wolf here
    WOLF_ROLES.any?{ |role| role == self.role }
  end
  
  def good?
    GOOD_ROLES.any?{ |role| role == self.role }
  end

  def evil?
    EVIL_ROLES.any?{ |role| role == self.role }
  end

  def non_special?
    NON_SPECIALS.any?{ |role| role == self.role }
  end

  def dg_non_special?
    NON_SPECIALS.any?{ |role| self.dg_role?(role) }
  end

  def confirmed?
    self.confirm
  end

  def role?(role)
    self.role == role
  end

  #def no_pi_role?(role)
  #  self.pi_role.nil?
  #  #self.pi_role == :werewolf || self.pi_role == :tanner
  #end

  def dg_role?(role)
#    if self.doppelganger?
      unless self.doppelganger_look.nil?
        self.doppelganger_look[:dgrole] == role
      end
#    end
  end

  def old_doppelganger?
    !self.doppelganger_look.nil?
  end
    
  def pi_role_as_text
    if self.role?(:pi_werewolf)
      "WEREWOLF" #return
    elsif self.role?(:pi_tanner)
      "TANNER" #return
    else
      "ROLE UNKNOWN" #return
    end
  end
end
