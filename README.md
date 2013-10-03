# Cinch-ONWWGame

## Description

This is a Cinch plugin to enable your bot to moderate One Night Werewolf by Akihisa Okui.

http://boardgamegeek.com/boardgame/142503/one-night-werewolf

## Usage

Here's an example of what your *bot.rb* might look like: 

    require 'cinch'
    require './cinch-onwwgame/lib/cinch/plugins/onww_game'

    bot = Cinch::Bot.new do

      configure do |c|
        c.nick            = "ONWWBot-Dev"
        c.server          = "chat.freenode.net"
        c.channels        = ["#playonww-dev"]
        c.verbose         = true
        c.plugins.plugins = [
          Cinch::Plugins::OnwwGame
        ]
        c.plugins.options[Cinch::Plugins::OnwwGame] = {
          :mods     => ["caitlinface"],
          :channel  => "#playonww-dev",
          :settings => "settings.yml"
        }
      end

    end

    bot.start

## Development

(pivotal tracker link)
