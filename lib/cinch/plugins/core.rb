require 'json'

#================================================================================
# GAME
#================================================================================

$player_count = 0

class Game


  MIN_PLAYERS = 3
  MAX_PLAYERS = 6
  BASE_ROLES = [
      :villager, :villager, :seer, :thief, :villager
    ]

  attr_accessor :started, :phase, :players, :player_cards, :table_cards, :lynch_votes, :invitation_sent
  
  def initialize
    self.started         = false
    self.players         = []
    self.invitation_sent = false
    self.player_cards    = []
    self.table_cards     = []
    self.phase           = :night # starts on night phase
    self.lynch_votes     = {}
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

  def at_max_players?
    self.player_count == MAX_PLAYERS
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
  #
  def pass_out_roles
    # assign loyalties
    extra_players = self.player_count - MIN_PLAYERS
    roles = BASE_ROLES + [:villager]*extra_players
    roles.shuffle!
    self.players.each do |player|
      role = roles.shift
      self.player_cards << role
      player.receive_role( role )
    end
    self.table_cards = roles
  end


  # Lynch votes

  def lynch_vote(player, target_player)
    self.lynch_votes[player] = target_player
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

  def lynch_totals
    totals = {}
    self.lynch_votes.each do |voter, voted|
      totals[voted] = [] if totals[voted].nil?
      totals[voted] << voter
    end
    totals
  end


  def check_game_state
    if self.started?
      status = "Waiting on players to vote: #{self.not_voted.map(&:user).join(", ")}"
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

  def waiting_on_seer_view
    seer = self.find_player_by_role(:seer)
    
    seer && seer.seer_view.nil?
  end

  def waiting_on_thief_take
    thief = self.find_player_by_role(:thief)
    
    thief && thief.thief_take.nil?
  end

  def change_to_day
    self.phase = :day
  end

  def day?
    self.phase == :day
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
    self.players.find{ |p| p.role == role }
  end

  def werewolves
    self.players.select{ |p| p.werewolf? }
  end

  def humans
    self.players.select{ |p| p.good? }
  end

end

#================================================================================
# PLAYER
#================================================================================

class Player

  attr_accessor :user, :role, :new_role, :thief_take, :seer_view

  def initialize(user)
    self.user = user
    self.role = nil
    self.new_role = nil
    self.seer_view = nil
    self.thief_take = nil
  end 

  def receive_role(role)
    self.role = role
  end

  def to_s
    self.user.nick
  end

  def werewolf?
    self.role == :werewolf
  end

  def seer?
    self.role == :seer
  end

  def thief?
    self.role == :thief
  end

  def villager?
    self.role == :villager
  end

  def good?
    self.seer? || self.thief? || self.villager?
  end

  def evil?
    self.werewolf?
  end


end





