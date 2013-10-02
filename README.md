# Cinch-WLB

## Description

This is a Cinch plugin to enable your bot to moderate Win, Lose, or Banana by Chris Cieslik.

http://boardgamegeek.com/boardgame/47082/win-lose-or-banana

## Usage

Here's an example of what your *bot.rb* might look like: 

    require 'cinch'
    require './cinch-bananabot/lib/cinch/plugins/wlb_game'

    bot = Cinch::Bot.new do

      configure do |c|
        c.nick            = "BananaBot"
        c.server          = "irc.freenode.org"
        c.channels        = ["#playbanana"]
        c.verbose         = true
        c.plugins.plugins = [
          Cinch::Plugins::WlbGame
        ]
        c.plugins.options[Cinch::Plugins::WlbGame] = {
          :mods     => ["caitlinface"],
          :channel  => "#playbanana",
          :settings => "settings.yml"
        }
      end

    end

    bot.start

## Development

(pivotal tracker link)