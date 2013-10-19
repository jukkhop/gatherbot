<font face="Cambria">

<font face="Candara"><h1>gatherbot by jukkan</h1></font>
Contact irc: jukkan @ quakenet, mail: jukka.hopea@gmail.com

<hr>

<font face="Candara"><h3>What is it?</h3></font>
<p>My attempt to make a configurable IRC-bot that manages pickups/gather matches. It's written in perl programming language and uses the Bot::BasicBot module as a base library.<p>

<font face="Candara"><h3>Needed to run</h3></font>
perl<br>
perl modules: Bot::BasicBot, DateTime (at least, to be complemented later)

<p>If you're interested to run this bot on your channel and want advice/help, drop me a message (contact info is at the top).</p>

<font face="Candara"><h3>Currently implemented features</h3></font>
!add            = Signs you up for the game.
!list           = Shows you list of signed up players.
!out            = Signs you out from the game. In addition, you can request an another player to be removed.
!votemap        = Syntax is !votemap &lt;mapname&gt;. More info with !votemap
!votecaptain    = Syntax is !votecaptain &lt;playername&gt;. More info with !votecaptain
!captain        = Makes you a captain. Command is only available if there is a free captain slot.
!uncaptain      = Frees the captain slot from you, supposing that you are a captain and player picking hasn't started
!rafflecaptain  = Requests the raffling of a new captain to replace a current captain. Available after the picking of players has started. More info with !rafflecaptain
!server         = Prints the game server info.
!mumble         = Prints the mumble server info.
!pick           = Captain's command to pick a player into his team.
!report         = You can request a score for a game with this command. More info with !report
!stats          = Prints your stats (or someone else's stats with !stats &lt;playername&gt;)
!lastgame       = Prints the info on the last game that was started.
!gameinfo       = Syntax is !gameinfo &lt;gameno&gt;. Prints the info of the given game.
!replace        = You can request a player to be replaced with another player with this command. More info with !replace
!games          = Prints a list of the games that are active.
!rank           = Prints your ranking (or someone else's with !rank playername)
!top            = Prints a list of top ranked players. You can define the length of the list with !top &lt;length&gt;
!hl off         = Puts you into hilight-ignore, (you're no longer hilighted on command !hilight)
!hl on          = Removes you from the hilight-ignore (you can again be hilighted on command !hilight)
!whois          = Prints your (or someone else's) username and accesslevel.
!admincommands  = (Admins only) Gives a list of commands available to admins as a private message.

<font face="Candara"><h3>Full list of commands</h3></font>
!add             = Signs a player up for the game. Syntax is !add &lt;playername&gt;
!out             = Signs a player out from the game. Syntax is !out &lt;playername&gt;
!abort           = Aborts the sign-up and clears the player list.
!captain         = You can make someone a captain with this command, supposing that there's a free captain slot and that the player is signed up.
!uncaptain       = Frees a captain slot from someone. Syntax is !uncaptain <captains_name&gt;. After the picking has started, use !changecaptain or !rafflecaptain.
!rafflecaptain   = You can request the raffling of a new captain to replace a current captain, supposing that picking has started. Syntax is !rafflecaptain &lt;captains_name&gt;.
!replace         = Replaces a player in the signup or in a game that already started. More info on !replace
!aoe             = Sends a private irc-notice to everyone on the channel about the status of the signup.
!hilight         = Highlights everyone on the channel at once.
!report          = Sets the score of a game. Syntax is !report &lt;gameno&gt; <Team 1|Team 2|Draw
!voidgame        = Voids a game as if it was never played. Syntax is !voidgame &lt;gameno&gt;
!accesslevel     = Sets the given user's accesslevel to the given level. Syntax is !accesslevel &lt;username&gt; &lt;admin|user&gt;
!changename      = Changes the given user's username. Syntax is !changename &lt;current_name&gt; &lt;new_name&gt;
!combineusers    = Combines the stats of two players and deletes the other user. Syntax is !combineusers &lt;user-to-remain&gt; &lt;user-to-be-deleted&gt;
!resetstats      = Resets the given user's stats. Syntax is !resetstats &lt;username&gt;
!set             = Sets the value of the given variable or prints its current value if a value is not given. Syntax is !set &lt;variable&gt; &lt;value&gt;. More info on !set
!addmap          = Adds a map into the map pool.
!removemap       = Removes a map from the map pool.
!shutdown        = (Original admins only) Saves all data and shuts the bot down.

<br>
<br>
<br>
</font>
