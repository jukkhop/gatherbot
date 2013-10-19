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
<p>
.add            = Signs you up for the game.<br>
.list           = Shows you list of signed up players.<br>
.out            = Signs you out from the game. In addition, you can request an another player to be removed.<br>
.votemap        = Syntax is .votemap &lt;mapname&gt;. More info with .votemap<br>
.votecaptain    = Syntax is .votecaptain &lt;playername&gt;. More info with .votecaptain<br>
.captain        = Makes you a captain. Command is only available if there is a free captain slot.<br>
.uncaptain      = Frees the captain slot from you, supposing that you are a captain and player picking hasn't started<br>
.rafflecaptain  = Requests the raffling of a new captain to replace a current captain. Available after the picking of players has started. More info with .rafflecaptain<br>
.server         = Prints the game server info.<br>
.mumble         = Prints the mumble server info.<br>
.pick           = Captain's command to pick a player into his team.<br>
.report         = You can request a score for a game with this command. More info with .report<br>
.stats          = Prints your stats (or someone else's stats with .stats &lt;playername&gt;)<br>
.lastgame       = Prints the info on the last game that was started.<br>
.gameinfo       = Syntax is .gameinfo &lt;gameno&gt;. Prints the info of the given game.<br>
.replace        = You can request a player to be replaced with another player with this command. More info with .replace .<br>
.games          = Prints a list of the games that are active.<br>
.rank           = Prints your ranking (or someone else's with .rank playername)<br>
.top            = Prints a list of top ranked players. You can define the length of the list with .top &lt;length&gt;<br>
.hl off         = Puts you into hilight-ignore, (you're no longer hilighted on command .hilight)<br>
.hl on          = Removes you from the hilight-ignore (you can again be hilighted on command .hilight)<br>
.whois          = Prints your (or someone else's) username and accesslevel.<br>
.admincommands  = (Admins only) Gives a list of commands available to admins as a private message.
</p>

<font face="Candara"><h3>Full list of commands</h3></font>
<p>
.add             = Signs a player up for the game. Syntax is .add &lt;playername&gt;<br>
.out             = Signs a player out from the game. Syntax is .out &lt;playername&gt;<br>
.abort           = Aborts the sign-up and clears the player list.<br>
.captain         = You can make someone a captain with this command, supposing that there's a free captain slot and that the player is signed up.<br>
.uncaptain       = Frees a captain slot from someone. Syntax is .uncaptain &lt;captains_name&gt;. After the picking has started, use .changecaptain or .rafflecaptain.<br>
.rafflecaptain   = You can request the raffling of a new captain to replace a current captain, supposing that picking has started. Syntax is .rafflecaptain &lt;captains_name&gt;.<br>
.replace         = Replaces a player in the signup or in a game that already started. More info on .replace<br>
.aoe             = Sends a private irc-notice to everyone on the channel about the status of the signup.<br>
.hilight         = Highlights everyone on the channel at once.<br
.report          = Sets the score of a game. Syntax is <br>
.report &lt;gameno&gt; <Team 1|Team 2|Draw<br>
.voidgame        = Voids a game as if it was never played. Syntax is <br>
.voidgame &lt;gameno&gt;<br>
.accesslevel     = Sets the given user's accesslevel to the given level. Syntax is <br>
.accesslevel &lt;username&gt; &lt;admin|user&gt;<br>
.changename      = Changes the given user's username. Syntax is <br>
.changename &lt;current_name&gt; &lt;new_name&gt;<br>
.combineusers    = Combines the stats of two players and deletes the other user. Syntax is <br>
.combineusers &lt;user-to-remain&gt; &lt;user-to-be-deleted&gt;<br>
.resetstats      = Resets the given user's stats. Syntax is <br>
.resetstats &lt;username&gt;<br>
.set             = Sets the value of the given variable or prints its current value if a value is not given. Syntax is .set &lt;variable&gt; &lt;value&gt;. More info on
.set<br>
.addmap          = Adds a map into the map pool.<br>
.removemap       = Removes a map from the map pool.<br>
.shutdown        = (Original admins only) Saves all data and shuts the bot down.
</p>

<br>
<br>
<br>
</font>
