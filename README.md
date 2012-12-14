gatherbot
=========

A simple and configurable IRC-bot for managing gathers/pickups


What is it?
It's my attempt to make a simple and configurable IRC-bot that manages pickups/gather 
matches. It is written in perl programming language and uses the Bot::BasicBot module as 
a base. It's under active development as of November 2012.

Needed to run: perl + Bot::BasicBot (perl module) and its dependencies installed

How to run
TBA

Background
A friend of mine who's been involved in establishing the Finnish speaking community for 
the recently released game Natural Selection 2, told me that they'd need an ircbot to 
manage gather matches. I told him I would look into getting one.

Before actually starting to code a bot of my own, I looked for existing solutions, as 
there are many. Every one that I found seemed very complex or/and hard to configure to 
our needs or was very outdated.

So I started to look for ways to make one and learned a new programming language (perl) 
while doing so. I used the Bot::BasicBot module as a base, which ment that I could go 
straight into coding the relevant stuff and skip all the underlying network stuff.

How does it work?
First aim was simple. There are only two different access levels a user can have and 
it's either 'admin' or 'user'. No authentication is required for one to become a user, 
and no explicit command is needed to add one as an user. You are simply added when you 
type your first command to the bot or otherwise storing your information is required. 
The bot uses visible irc nicks for storing userdata internally. No Q auth or anything is 
needed. Both gamedata and userdata are stored in their own files as human understandable 
text.

Another aim was configurable. Every relevant setting can be set from a .cfg file (before 
running the script) or at runtime via a command. So basically the bot can be turned from 
NS2 6v6 mode to CS 5v5 mode (or any other mode) with minimal effort and it can be done 
at runtime from IRC.

Currently implemented features (apart from the obvious or mentioned ones)

    Raffle mode (teams are raffled when the maximum amount of players are signed)
    Pickup mode (both teams have captains, who pick their own players from the player 
pool)
    Voting of maps (maps can be added and removed via command)
    Tracking of user statistics (points and matches won/lost/draws)
    User ranking based on points
    Users can request to remove someone from the pool
    Users can request to replace someone with someone from the pool
    Users can request the confirmation of match result


Full list of commands
(all users)
add
list
out
votemap
captain
notcaptain
server (prints voice server info)
voip (prints voice server info)
pick
replace
report
stats
lastgame
gameinfo
games
rank
top
whois
hl off (prevents you from being highlighted by the command .hilight)
hl on (makes you able to be highlighted again)
commands

(admins only)
abort
accesslevel (for giving admin rights)
admincommands
addmap
removemap
changename (for changing someone's name without reseting stats)
resetstats (for resetting someone's stats)
voidgame
set (for setting variables)
shutdownbot (makes the bot save config and all data and quit)
.aoe (sets channel mode -N, sends a notice about signup status to everyone on the 
channel and sets mode +N)
.hilight (highlights everyone on the channel)

