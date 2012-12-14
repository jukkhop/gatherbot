<font face="Cambria">

<font face="Candara">   <h1>jukkan's gatherbot</h1>     </font>
<hr>
<br>
<font face="Candara">   <h3>What is it?</h3>    </font>
It's my attempt to make a simple and configurable IRC-bot that manages pickups/gather matches. It is written in perl programming language and uses the Bot::BasicBot module as a base. It's under active development as of November 2012. <br><br>

Needed to run: <b>perl</b> + <b>Bot::BasicBot</b> (perl module) and its dependencies installed
<br><br>

<font face="Candara">   <h3>Background</h3>     </font>
A friend of mine who's been involved in establishing the Finnish speaking community for the recently released game Natural Selection 2, told me that they'd need an ircbot to manage gather matches. I told him I would look into getting one.<br><br>

Before actually starting to code a bot of my own, I looked for existing solutions, as there are many. Every one that I found seemed very complex or/and hard to configure to our needs or was very outdated.<br><br>

So I started to look for ways to make one and learned a new programming language (perl) while doing so. I used the Bot::BasicBot module as a base, which ment that I could go straight into coding the relevant stuff and skip all the underlying network stuff.<br><br>


<font face="Candara">   <h3>How does it work?</h3>   </font>
First aim was simple. There are only two different access levels a user can have and it's either 'admin' or 'user'. No authentication is required for one to become a user, and no explicit command is needed to add one as an user. You are simply added when you type your first command to the bot or otherwise storing your information is required. The bot uses visible irc nicks for storing userdata internally. No Q auth or anything is needed. Both gamedata and userdata are stored in their own files as human understandable text.<br><br>

Another aim was configurable. Every relevant setting can be set from a .cfg file (before running the script) or at runtime via a command. So basically the bot can be turned from NS2 6v6 mode to CS 5v5 mode (or any other mode) with minimal effort and it can be done at runtime from IRC.<br><br>


<font face="Candara">   <h3>Currently implemented features <small>(apart from the obvious or mentioned ones)</small></h3>   </font>
<ul>
<li>Raffle mode (teams are raffled when the maximum amount of players are signed)</li>
<li>Pickup mode (both teams have captains, who pick their own players from the player pool)</li>
<li>Voting of maps (maps can be added and removed via command)</li>
<li>Tracking of user statistics (points and matches won/lost/draws)</li>
<li>User ranking based on points</li>
<li>Users can request to remove someone from the pool</li>
<li>Users can request to replace someone with someone from the pool</li>
<li>Users can request the confirmation of match result</li>
</ul><br>

<font face="Candara">   <h3>Full list of commands</h3>  </font>
(all users)<br>
add<br>
list<br>
out<br>
votemap<br>
captain<br>
notcaptain<br>
server (prints voice server info)<br>
voip (prints voice server info)<br>
pick<br>
replace<br>
report<br>
stats<br>
lastgame<br>
gameinfo<br>
games<br>
rank<br>
top<br>
whois<br>
hl off (prevents you from being highlighted by the command .hilight)<br>
hl on (makes you able to be highlighted again)<br>
commands<br>
<br>
(admins only)<br>
abort<br>
accesslevel (for giving admin rights)<br>
admincommands<br>
addmap<br>
removemap<br>
changename (for changing someone's name without reseting stats)<br>
resetstats (for resetting someone's stats)<br>
voidgame<br>
set (for setting variables)<br>
shutdownbot (makes the bot save config and all data and quit)<br>
.aoe (sets channel mode -N, sends a notice about signup status to everyone on the channel and sets mode +N)<br>
.hilight (highlights everyone on the channel)<br>

<br>
<br>
<br>
</font>
