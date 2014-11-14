MIN_PLAYERS = 3
MAX_PLAYERS = 6
ONUWW_MAX_PLAYERS = 10

BASE_ROLES = [:werewolf, :werewolf, :seer, :thief, :villager]
DEFAULT_ULTIMATE_ROLES = [:werewolf, :werewolf, :seer, :robber, :troublemaker, :villager]

GOOD_ROLES = [:seer, :thief, :villager, :robber, :troublemaker, :drunk, :hunter, :prince, :bodyguard, :mason, :insomniac, :doppelganger, :apprentice_seer, :curator, :cursed]
WOLF_ROLES = [:werewolf, :dream_wolf, :mystic_wolf, :alpha_wolf]
EVIL_ROLES = WOLF_ROLES + [:minion]
NON_SPECIALS = [:werewolf, :villager, :tanner, :drunk, :hunter, :prince, :bodyguard, :mason, :insomniac, :minion, :apprentice_seer, :cursed, :dream_wolf]

RANDOM_ROLES = [:villager, :villager, :villager, :villager, :werewolf, :werewolf, :seer, :robber, :troublemaker, :tanner, :drunk, :hunter, :prince, :bodyguard, :apprentice_seer, :mason, :insomniac, :doppelganger]

VALID_VARIANTS = ["lonewolf", "random", "blindrandom"]

ARTIFACTS = {:claw => :werewolf, :brand => :villager, :void => nil, :void => nil, :cudgel => :tanner, :mask => nil, :bow => :hunter, :sword => :bodyguard, :cloak => :prince}

# also set maximums to 0 for roles not yet implemented
ROLE_COUNTS = {
	:alpha_wolf => [0], # NYI
	:apprentice_seer => [*0..1],
	:aura_seer => [0], # NYI
	:bodyguard => [*0..1],
	:curator => [0, 1],
	:cursed => [*0..1],
	:doppelganger => [0, 1],
	:dream_wolf => [*0..1],
	:drunk => [0, 1],
	:hunter => [*0..1],
	:mason => [0, *2],
	:minion => [*0..1],
	:mystic_wolf => [0,1],#newly implemented
	:paranormal_investigator => [0 .. 4], #newly implemented -- for testing
	:prince => [*0..1],
	:revealer => [0], # NYI
	:robber => [0, 1],
	:seer => [*0..1],
	:sentinel => [0], # NYI
	:tanner => [*0..1],
	:thief => [0, 1],
	:troublemaker => [0, 1],
	:village_idiot => [0], # NYI
	:werewolf => [*0..3], #Includes a fun new pose
	:witch => [0] # NYI
}
