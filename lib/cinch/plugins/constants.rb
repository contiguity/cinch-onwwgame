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

# only impose maximums on roles that would cause timing issues
# if someone wants a game with 9 tanners, might as well let them
# also set maximums to 0 for roles not yet implemented
ROLE_COUNTS = {
	:alpha_wolf => [0], # NYI
	:apprentice_seer => [*0..20],
	:aura_seer => [0], # NYI
	:bodyguard => [*0..20],
	:curator => [0, 1],
	:cursed => [*0..20],
	:doppelganger => [0, 1],
	:dream_wolf => [*0..20],
	:drunk => [0, 1],
	:hunter => [*0..20],
	:mason => [0, *2..20],
	:minion => [*0..20],
	:mystic_wolf => [0], # NYI
	:paranormal_investigator => [0], # NYI
	:prince => [*0..20],
	:revealer => [0], # NYI
	:robber => [0, 1],
	:seer => [*0..20],
	:sentinel => [0], # NYI
	:tanner => [*0..20],
	:thief => [0, 1],
	:troublemaker => [0, 1],
	:village_idiot => [0], # NYI
	:werewolf => [*0..20],
	:witch => [0] # NYI
}
