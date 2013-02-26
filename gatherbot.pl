#     (C) 2012 Jukka Hopeavuori
#
#     This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
# 
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.


#!/usr/bin/perl
use strict;
use warnings;
use utf8;

# This is an IRC-bot that handles gather/pickup games
#
# For settings descriptions, see gatherbot.cfg

package GatherBot;
use base qw(Bot::BasicBot);
use POE;
use DateTime;
use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use Locale::TextDomain ("gatherbot" => "locale");
use POSIX;

# Bot related settings, settings in gatherbot.cfg override (if given)
my $server   = 'se.quakenet.org';
my $chan     = '#BotTestChan';
my $nick     = 'MyGatherBot';
my $authname = '';
my $authpw   = '';

# Gather related settings, settings in gatherbot.cfg override (if given)
my $team1                = 'Team1';
my $team2                = 'Team2';
my $draw                 = 'Draw';
my $maxplayers           = 10;
my @admins               = qw(admin1 admin2);
my @maps                 = qw(map1 map2 map3);
my $gameserverip         = '';
my $gameserverport       = '';
my $gameserverpw         = '';
my $voiceserverip        = '';
my $voiceserverport      = '';
my $voiceserverpw        = '';
my $neededvotes_captain  = 0;
my $neededvotes_map      = 0;
my $neededreq_replace    = 0;
my $neededreq_remove     = 0;
my $neededreq_score      = 0;
my $neededreq_rafflecapt = 0;
my $neededreq_hl         = 0;
my $initialpoints        = 1000;
my $pointsonwin          = 10;
my $pointsonloss         = -10;
my $pointsondraw         = 0;
my $p_scale_factor       = 10;
my $p_scale_factor_draw  = 15;
my $p_max_variance       = 5;
my $topdefaultlength     = 10;
my $gamehascaptains      = 1;
my $gamehasmap           = 1;
my $votecaptaintime      = 1;
my $votemaptime          = 1;
my $mutualvotecaptain    = 1;
my $mutualvotemap        = 1;
my $printpoolafterpick   = 1;
my $givegameserverinfo   = 0;
my $givevoiceserverinfo  = 1;
my $showinfointopic      = 1;
my $topicdelimiter       = '[]';
my $remindtovote         = 1;
my $websiteurl           = '';
my $locale               = 'en';

my $unrankedafter_games  = 3;
my $rankedafter_games    = 10;

# Other vars (not to be changed)
my $gamenum = 0;
my $canadd = 1;
my $canout = 1;
my $cancaptain = 1;
my $canpick = 0;
my $canvotemap = 0;
my $canvotecaptain = 0;
my $mapvotecount = 0;
my $captainvotecount = 0;
my $turn = 0;
my $lastturn = 0;
my $votecaptaindone = 0;
my $lastsentgame = 0;
my $captain1 = '';
my $captain2 = '';
my $chosenmap = '';
my $capt1rafflerequests = '';
my $capt2rafflerequests = '';
my $cfgheader = '';
my $defaulttopic = '';
my $hl_requests = '';
my @players;
my @team1;
my @team2;
my @hlignorelist;
my %qauths;
my %mapvotes;
my %mapvoters;
my %captainvotes;
my %captainvoters;
my %replacereq;
my %removereq;
my %userscorereq;
my %captainscorereq;
my %users;
my %games;

# Webserver-data related vars
my %map_pks;
my %player_pks;
my %game_player_pks;


# Called after the bot has connected
sub connected {
    my $self = shift;
    
    # Add names in @admin to userdata
    # if not there already
    for my $name (@admins) {
        if (! exists $users{$name}) {
            $users{$name} = "admin.$initialpoints.0.0.0";
        }
    }
    
    # Auth to Q if auth info was given
    if ($authname ne '' && $authpw ne '') {
        $self->say(
            who =>     'Q@CServe.quakenet.org',
            channel => 'msg',
            body =>    "AUTH $authname $authpw",
            address => 'false'
        );
    }
    
    return;
}

# Shortcut to say something on $chan
sub sayc {
    my $self = shift;
    
    $self->emote(channel => $chan, body => $_[0]);
    
    return;
}

# Called when the bot receives a message
sub said {
    my $self = shift;
    my $message = shift;
    my $who = $message->{who};
    my $channel = $message->{channel};
    my $body = $message->{body};
    my $address = $message->{address};
    
    # If the message came from Q
    if ($who eq 'Q') {
        $self->check_q_msg($body);
        return;
    }
    
    # If the message was not received from 
    # the channel set in $chan, return
    if ($channel ne $chan) {
        return;
    }
    
    # If the message doesn't start with a dot, return
    if (substr($body, 0, 1) ne '.') {
        return;
    }
    
    # Split the message by whitespace to
    # get the command and any parameters
    my @commands = split ' ', $body;
    
    # If user doesn't exist in userdata, add him
    if (! exists $users{$who}) {
        $users{$who} = "user.$initialpoints.0.0.0";
    }
    
    # If there's no qauth info on the user,
    # check if he's actually authed
    if (! exists $qauths{$who}) {
        $self->whoisuser_to_q($who);
    }
    
    # Get the user's access level
    my @userdata = split '\.', $users{$who};
    my $accesslevel = $userdata[0];
    
    
    # command .add
    if ($commands[0] eq '.add' || $commands[0] eq '.sign') {
    
        if ($canadd == 0) {
            $self->sayc(__x("Sign-up is closed at the moment."));
            return;
        }

        my $tbadded;
        if ($#commands == 0) {
            $tbadded = $who;
            
        } else {
            if ($accesslevel eq 'admin') {
                $tbadded = $commands[1];
                
                if (! exists $users{$tbadded}) {
                    $users{$tbadded} = "user.$initialpoints.0.0.0";
                }
                
            } else {
                $self->sayc(__x("{who} is not an admin.", who => $who));
                return;
            }
        }
        
        # Check if already signed
        if (issigned($tbadded)) {
            $self->sayc(__x("{who} has already signed up.", who => $tbadded));
            return;
        }
        
        # Add the player on the playerlist
        push @players, $tbadded;
        my $playercount = $#players+1;
        
        # Give output
        $self->sayc(__x("{tbadded} has signed up. {playercount}/{maxplayers} have signed up.",
                        tbadded => $tbadded, playercount => $playercount, maxplayers => $maxplayers));
        
        # Remind the player to vote if remindtovote=1,
        # and he was not the last to sign up
        if ($remindtovote == 1 && $playercount < $maxplayers) {
            if ($mutualvotemap == 0 || $mutualvotecaptain == 0) {
                my $votables;
                
                if ($mutualvotemap == 0 && $mutualvotecaptain == 0) {
                    $votables = __x ("a map and a captain");
                } else {
                    if ($mutualvotemap == 0) {
                        $votables = __x ("a map");
                    } else {
                        $votables = __x ("a captain");
                    }
                }
                
                $self->sayc(__x("{tbadded}: Note! You can already vote for {votables}.",
                                tbadded => $tbadded, votables => $votables));
            }
        }
        
        # Update the topic
        # (does nothing if $showinfointopic is set to 0)
        $self->updatetopic();

        # Initialize player's votes and requests
        $self->voidusersvotes($tbadded);
        $self->voidusersrequests($tbadded);
        
        # If this was the first to sign up
        if ($playercount == 1) {
            $self->voidvotes();
        
            # If mutual voting of captains is
            # not enabled, enable votecaptain
            if ($mutualvotecaptain == 0) {
                $canvotecaptain = 1;
            }
            
            # If mutual voting of map is
            # not enabled, enable votemap
            if ($mutualvotemap == 0) {
                $canvotemap = 1;
            }
        }
        
        # If there aren't enough players to start the game, return
        if ($playercount < $maxplayers) {
            return;
        }
        
        # -- Game is about to start ---
        
        # Disable .add and .out now
        $canadd = 0;
        $canout = 0;
        
        # Decide how to start the game
        # (which number to pass to schedule_tick)
        my $waittime = 1;
        if ($gamehasmap == 1 && $votemaptime > 0) {
            $canvotemap = 1;
            $chosenmap = "";
            
            $self->sayc(__x("Votemap is about to begin. Vote with command .votemap <mapname>"));
            
            my $maps = join ' ', @maps;
            $self->sayc(__x("Votable maps: {maps}", maps => $maps));
            $self->sayc(__x("Votemap ends in {votemaptime} seconds!", votemaptime => $votemaptime));
            
            $waittime = $votemaptime;
        }
        
        # Makes tick() run after $waittime seconds have passed
        $self->schedule_tick($waittime);
        
        return;
    }
    
    
    # command .captain
    elsif ($commands[0] eq '.captain') {
    
        if ($gamehascaptains == 0) {
            $self->sayc(__x("Command {command} is not enabled (gamehascaptains = 0)",
                            command => $commands[0]));
            return;
        }
        
        if ($cancaptain == 0) {
            $self->sayc(__x("Signing up as a captain is not possible at the moment.")); 
            return;
        }
        
        my $tbcaptain;
        
        if ($#commands == 0) {
        
            # Check that the user has over $initialpoints poins
            @userdata = split '\.', $users{$who};
            my $points = $userdata[1];
            
            if ($points <= $initialpoints) {
            
                $self->sayc(__x("A captain must have over {initialpoints} points.",
                                initialpoints => $initialpoints)); 
                return;
            }
        
            $tbcaptain = $who;
            
        } else {
            if ($accesslevel ne 'admin') {
                $self->sayc(__x("{who} is not an admin.", who => $who)); 
                return;
            }
            
            $tbcaptain = $commands[1];
        }
        
        if ($tbcaptain eq $captain1 || $tbcaptain eq $captain2) {
            $self->sayc(__x("{who} is already a captain.",
                            who => $tbcaptain)); 
            return;
        }
        
        if (issigned($tbcaptain) == 0) {
            $self->sayc(__x("{who} has not signed up.",
                            who => $tbcaptain));
            return;
        }
    
        if ($captain1 eq '') {
            $captain1 = $tbcaptain;
            
        } elsif ($captain2 eq '') {
            $captain2 = $tbcaptain;
        }
        
        $self->sayc(__x("{who} is now a captain.",
                        who => $tbcaptain));
        
        if ($captain1 ne '' && $captain2 ne '') {
            $cancaptain = 0;
        }
        
        $self->updatetopic();
        
        return;
    }
    
    
    # command .uncaptain
    elsif ($commands[0] eq '.uncaptain') {
    
        if ($gamehascaptains == 0) {
            $self->sayc(__x("Command {command} is not enabled (gamehascaptains = 0)",
                            command => $commands[0]));
            return;
        }
        
        my $tbuncaptain;
        
        if ($#commands == 0) {
            $tbuncaptain = $who;
        } else {
        
            if ($accesslevel ne 'admin') {
                $self->sayc(__x("{who} is not an admin.", who => $who)); 
                return;
            }
            
            $tbuncaptain = $commands[1];
        }
        
        if ($tbuncaptain ne $captain1 && $tbuncaptain ne $captain2) {
            $self->sayc(__x("{who} is not a captain.",
                            who => $tbuncaptain));
            return;
        }
        
        if ($canpick == 1) {
            $self->sayc(__x("Player picking has already started " .
                            "(must use .rafflecaptain or .changecaptain)"));
            
            return;
        }
        
        if ($captain1 eq $tbuncaptain) {
            $captain1 = "";
        
        } elsif ($captain2 eq $tbuncaptain) {
            $captain2 = "";
        }
        
        $self->sayc(__x("{who} is not a captain anymore.",
                        who => $tbuncaptain));
        
        $self->updatetopic();
        
        $cancaptain = 1;
        
        return;
    }
    
    
    # command .rafflecaptain
    elsif ($commands[0] eq '.rafflecaptain') {
    
        if ($gamehascaptains == 0) {
            $self->sayc(__x("Command {command} is not enabled (gamehascaptains = 0)",
                            command => $commands[0]));
            return;
        }
        
        if ($canpick == 0) {
            if ($who eq $captain1 || $who eq $captain2) {
                $self->sayc(__x("Player picking has not started yet (use .uncaptain)"));
            } else {
                $self->sayc(__x("Player picking has not started yet."));
            }
            
            return;
        }
        
        if ($#commands == 0) {
            $self->sayc(__x("Syntax is {command} <captains_name>",
                            command => $commands[0]));
            return;
        }
        
        # For case-insensitivity
        my $cmd1lc = lc($commands[1]);
        my $capt1lc = lc($captain1);
        my $capt2lc = lc($captain2);
        
        if ($cmd1lc ne $capt1lc && $cmd1lc ne $capt2lc) {
        
            $self->sayc(__x("{who} is not a captain.",
                            who => $commands[1]));
            return;
        }
        
        # If not an admin
        if ($accesslevel ne 'admin') {
            
            #  Check if signed
            if (issigned($who) == 0) {
            
                $self->sayc(__x("{who} has not signed up.",
                                who => $commands[1]));
                return;
            }
        
            # Get the requesters
            my $newcaptrequests = "";
            if ($cmd1lc eq $capt1lc) {
                $newcaptrequests = $capt1rafflerequests;
            } else {
                $newcaptrequests = $capt2rafflerequests;
            }
            my @requesters = split(',', $newcaptrequests);
            
            # Find out if already requested
            my $alreadyrequested = 0;
            for my $requester (@requesters) {
                if ($who eq $requester) {
                    $alreadyrequested = 1;
                    last;
                }
            }
            
            # If not, add into requesters
            if ($alreadyrequested == 0) {
                push(@requesters, $who);
            }
            
            # Set the requests
            my $rafflecaptrequests = join(',', @requesters);
            if ($cmd1lc eq $capt1lc) {
                $capt1rafflerequests = $rafflecaptrequests;
            } else {
                $capt2rafflerequests = $rafflecaptrequests;
            }
            
            # Generate output
            my $requestersline = join(', ', @requesters);
            my $requesterscount = $#requesters+1;
            
            # Give output
            $self->sayc(__x("Raffling of a new captain in place of {who} " .
                            "have requested: {requesters} [{requestersc}/{neededreq}",
                            who => $commands[1],
                            requesters => $requestersline,
                            requestersc => $requesterscount,
                            neededreq => $neededreq_rafflecapt));
            
            # If not enough requesters yet, return.
            # Otherwise, raffle a new captain
            if ($requesterscount < $neededreq_rafflecapt) {
                return;
            }
        }
        
        # - Going to raffle a new captain -
        
        # Check that there is at least 
        # one valid captain in the pool
        my @userdata;
        my $points = 0;
        my $exists_valid_captain = 0;
        
        for my $player (@players) {
            @userdata = split '\.', $users{$player};
            $points = $userdata[1];
            if ($points > $initialpoints) {
                $exists_valid_captain = 1;
                last;
            }
        }
        
        if ($exists_valid_captain == 0) {
            $self->sayc(__x("There are no potential captains in the player pool. " .
                            "Rafflecaptain cannot be done."));
            return;
        }
        
        # Take a random player and check that
        # he is a valid captain. If not, repeat.
        my $playercount = $#players+1;
        my $randindex = 0;
        my $randplayer = "";
        
        while ($points <= $initialpoints) {
            $randindex = int(rand($playercount));
            $randplayer = $players[$randindex];
            
            @userdata = split '\.', $users{$randplayer};
            $points = $userdata[1];
        }
        
        my $newcaptain = $players[$randindex];
        my $oldcaptain = "";
        
        # Change the captain
        if ($cmd1lc eq $capt1lc) {
            $oldcaptain = $captain1;    # Get the old captain
            $capt1rafflerequests = "";  # Clear rafflerequests
            changecapt1($newcaptain);   # Change captain
            
        } else {
            $oldcaptain = $captain2;    # Get the old captain
            $capt2rafflerequests = "";  # Clear rafflerequests
            changecapt2($newcaptain);   # Change captain
        }
        
        
        $self->sayc(__x("{newcaptain} is now a captain instead of {oldcaptain}",
                        newcaptain => $newcaptain, oldcaptain => $oldcaptain));
        
        return;
    }
    
    
    # command .changecaptain
    elsif ($commands[0] eq '.changecaptain') {
        
        if ($gamehascaptains == 0) {
            $self->sayc(__x("Command {command} is not enabled (gamehascaptains = 0)",
                            command => $commands[0]));
            return;
        }
        
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who)); 
            return;
        }
        
        if ($#commands < 2) {
            $self->sayc(__x("Syntax is {command} <current_captain> <new_captain>",
                            command => $commands[0]));
            return;
        }
        
        if ($commands[1] ne $captain1 && $commands[1] ne $captain2) {
            $self->sayc(__x("{who} is not a captain.",
                            who => $commands[1])); 
            return;
        }
        
        if (isontheplayerlist($commands[2]) == 0) {
            $self->sayc(__x("{who} is not on the player list.",
                            who => $commands[2]));
            return;
        }
        
        if ($commands[2] eq $captain1 || $commands[2] eq $captain2) {
            $self->sayc(__x("{who} is already a captain.",
                            who => $commands[2]));
            return;
        }
        
        # - Going to change the captain -
        
        # If picking hasn't started yet
        if ($canpick == 0) {
            if ($commands[1] eq $captain1) {
                $captain1 = $commands[2];
            } else {
                $captain2 = $commands[2];
            }
            
            $self->updatetopic();
            
        # If picking started already
        } else {
            if ($commands[1] eq $captain1) {
                changecapt1($commands[2]);
            } else {
                changecapt2($commands[2]);
            }
        }
        
        # Give output
        $self->sayc(__x("{newcaptain} is now a captain instead of {oldcaptain}",
                        newcaptain => $commands[2],
                        oldcaptain => $commands[1]));
        return;
    }
    
    
    # command .pick
    elsif ($commands[0] eq '.pick') {
        
        if ($gamehascaptains == 0) {
            $self->sayc(__x("Command {command} is not enabled (gamehascaptains = 0)",
                            command => $commands[0]));
            return;
        }
        
        if ($canpick == 0) {
            $self->sayc(__x("Player picking has not started yet."));
            return;
        }
        
        if ($who ne $captain1 && $who ne $captain2) {
            $self->sayc(__x("{who} is not a captain.",
                            who => $who));
            return;
        }
        
        if ($#commands < 1) {
            $self->sayc(__x("Syntax is {command} <playername>",
                            command => $commands[0]));
            return;
        }
        
        if ($who eq $captain1 && $turn != 1) {
            $self->sayc(__x("It's not {who}'s turn to pick.",
                            who => $captain1));
            return;
        }
        
        if ($who eq $captain2 && $turn != 2) {
            $self->sayc(__x("It's not {who}'s turn to pick.",
                            who => $captain2));
            return;
        }
        
        if (isontheplayerlist($commands[1]) == 0) {
            $self->sayc(__x("{who} is not on the player list.",
                            who => $commands[1]));
            return;
        }
        
        # Add the picked player to team1 
        if ($who eq $captain1) {
            push @team1, $commands[1];
            
            if ($lastturn == 1) {
                $turn = 2;
            }
            
            $lastturn = 1;
        
          # Or, add the picked player to team2
        } else {
            push @team2, $commands[1];
            
            if ($lastturn == 2) {
                $turn = 1;
            }
            
            $lastturn = 2;
        }
        
        my $pickedplayercount = $#team1+1 + $#team2+1;
        
        # Remove the picked one from the playerlist
        for my $i (0 .. $#players) {
            if ($players[$i] eq $commands[1]) {
                splice(@players, $i, 1);
                last;
            }
        }
        
        my $outline = __x("{picker} picked {who}.",
                          picker => $who, who => $commands[1]);
        
        my $remainingplayercount = $#players + 1;
        my $giveplayerlist = 0;
        my $lastpickwasauto = 0;
        
        # If there are more than 1 picks remaining, or
        # there are more than one player left in the pool,
        # give output regarding the next picker
        my $nextpicker = "";
        
        if ($turn == 1) {
            $nextpicker = $captain1;
        } else {
            $nextpicker = $captain2;
        }
        
        if ($maxplayers - $pickedplayercount > 1 || $remainingplayercount > 1) {
            $outline .= __x(" {next}'s turn to pick.",
                            next => $nextpicker);

            $giveplayerlist = 1;
        
        # Else, do the last pick automatically
        } else {
            if ($#team1 < $#team2) {
                push(@team1, $players[0]);
                
            } elsif ($#team2 < $#team1) {
                push(@team2, $players[0]);
            }
            
            $lastpickwasauto = 1;
            $pickedplayercount++;
        }
        $self->sayc($outline);
        
        # Print player pool if necessary
        if ($giveplayerlist == 1 && $printpoolafterpick == 1) {
            my $playerlist = $self->format_plist(@players);
            
            $self->sayc(__x("Players: {list}",
                            list => $playerlist));
        }
        
        # Give output if the last pick was done automatically
        if ($lastpickwasauto == 1 ) {
            $self->sayc(__x("One player remained in the pool; {player} " .
                            "was automatically moved to {next}'s team.",
                            player => @players, next => $nextpicker));
        }
        
        # Return if not ready yet, otherwise go on
        if ($pickedplayercount < $maxplayers) {
            return;
        }
        
        # End picking and start the game
        $canpick = 0;
        $self->startgame();
        
        return;
    }
    
    
    # command .abort
    elsif ($commands[0] eq '.abort') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who)); 
            return;
        }
        
        my $playercount = $#players + 1;
        if ($playercount == 0) {
            $self->sayc(__x("No one has signed up."));
            return;
        }
        
        $captain1 = "";
        $captain2 = "";
        $chosenmap = "";
        $self->voidvotes();
        $self->voidrequests();
        @players=();
        @team1=();
        @team2=();
        
        $canadd = 1;
        $canout = 1;
        $cancaptain = 1;
        $canpick = 0;
        $canvotecaptain = 0;
        $canvotemap = 0;
        
        $self->sayc(__x("The starting of the game has been aborted; " .
                        "sign-up list has been cleared."));
        
        $self->updatetopic();
        
        return;
    }
    

    # command .list
    elsif ($commands[0] eq '.list'        || $commands[0] eq '.ls' ||
           $commands[0] eq '.listplayers' || $commands[0] eq '.lp' ||
           $commands[0] eq '.playerlist'  || $commands[0] eq '.pl')  {
    
        my $outline = "";
        
        if ($#players < 0) {
            $outline = __x("No one has signed up.");
            
        } else {
            my $playercount = $#players+1;
            my $list = $self->format_plist(@players);
            
            if ($canpick == 0) {
                $outline = __x("Players: {list} ({pcount}/{pmax})",
                               list => $list,
                               pcount => "\x02" . $playercount . "\x0f",
                               pmax =>   "\x02" . $maxplayers  . "\x0f");
                
            } else {
                $outline = __x("Player pool: {list}",
                               list => $list);
            }
        }
        
        $self->sayc($outline);
        return;
    }
    
    
    # command .score
    elsif ($commands[0] eq '.score' || $commands[0] eq '.report' ||
           $commands[0] eq '.result') {
        
        if ($#commands < 2) {
            $self->sayc(__x("Syntax is {command} <gameno> <{team1}|{team2}|{draw}>",
                            command => $commands[0],
                            team1 => $team1, team2 => $team2, draw => $draw));
            return;
        }
        
        my $cmd1 = $commands[1];
        my $cmd2 = $commands[2];
        
        if ($#commands > 2) {
            for my $i (3 .. $#commands) {
                $cmd2 .= " " . $commands[$i];
            }
        }
        
        # Make lowercase versions of the strings 
        # to use them in comparisons
        my $cmd2lc = lc($cmd2);
        my $team1lc = lc($team1);
        my $team2lc = lc($team2);
        my $drawlc = lc($draw);
        
        if ($cmd2lc ne $team1lc &&
            $cmd2lc ne $team2lc &&
            $cmd2lc ne $drawlc) {
            
            $self->sayc(__x("Score must be {team1}, {team2} or {draw}",
                            team1 => $team1, team2 => $team2, draw => $draw));
            
            return;
        }
        
        if (! exists $games{$cmd1}) {
            $self->sayc(__x("Game #{no} was not found.",
                            no => $cmd1));
            
            return;
        }
        
        if ( index($games{$cmd1}, 'active') == -1 ) {
            $self->sayc(__x("Game #{no} is already reported.",
                            no => $cmd1));
            
            return;
        }
        
        # Make the given result look like it should
        # (looks better when printed)
        if ($cmd2lc eq $team1lc) { $cmd2 = $team1 };
        if ($cmd2lc eq $team2lc) { $cmd2 = $team2 };
        if ($cmd2lc eq $drawlc)  { $cmd2 = $draw };
        
        # Get the players who played in this game
        my @plist = get_players_by_gameno($cmd1);
        
        # Get the teams separate from the player list
        my @t1_players = team1_from_plist(@plist);
        my @t2_players = team2_from_plist(@plist);
        
        # Find out what was maxplayers and teamsize
        my $wasmaxplayers = $#plist + 1;
        my $wasteamsize = $wasmaxplayers / 2;
        
        if ($accesslevel ne 'admin') {
        
            # Find out who were captains in this game
            my $wascaptain1 = $t1_players[0];
            my $wascaptain2 = $t2_players[0];
        
            if ($who eq $wascaptain1 || $who eq $wascaptain2) {
                if (! exists $captainscorereq{$cmd1}) {
                    $captainscorereq{$cmd1} = " , ";
                }
            
                my @captainresults = split ',', $captainscorereq{$cmd1};
                my $team = "";
                
                if ($who eq $wascaptain1) {
                    $captainresults[0] = $cmd2;
                    $team = $team1;
                }
                
                if ($who eq $wascaptain2) {
                     $captainresults[1] = $cmd2;
                     $team = $team2;
                }
                
                $captainscorereq{$cmd1} = join ',', @captainresults;
                
                $self->sayc(__x("{team}'s captain requested score {score} for game #{no}",
                                team => $team, score => $cmd2, no => $cmd1));
                
                if ($captainresults[0] ne $captainresults[1]) {
                    return;
                }
                
            } else {
            
                # Find out if the player even played in the game
                my $wasplaying = 0;
                for my $i (0 .. $#plist) {
                    if ($plist[$i] eq $who) {
                        $wasplaying = 1;
                        last;
                    }
                }
                
                if ($wasplaying == 0) {
                    
                    $self->sayc(__x("{who} didn't play in game #{no}.",
                                    who => $who, no => $cmd1));
                    
                    return;
                }
                
                # Initialize %userscorereq value if necessary
                if (! exists $userscorereq{$cmd1}) {
                    $userscorereq{$cmd1} = "";
                }
                
                my @requests = split ',', $userscorereq{$cmd1};
                my @requesters;
                my @scores;
                my @arr;
                
                for my $i (0 .. $#requests) {
                    @arr = split ':', $requests[$i];
                    push @requesters, $arr[0];
                    push @scores, $arr[1];
                }
                
                my $alreadyrequested = 0;
                for my $i (0 .. $#requesters) {
                    if ($requesters[$i] eq $who) {
                        $alreadyrequested = 1;
                        $scores[$i] = $cmd2;
                        last;
                    }
                }
                if ($alreadyrequested == 0) {
                    push @requesters, $who;
                    push @scores, $cmd2;
                }
                
                # Update to %userscorereq
                @arr=();
                for my $i (0 .. $#requesters) {
                    push @arr, "$requesters[$i]:$scores[$i]";
                }
                $userscorereq{$cmd1} = join ',', @arr;
                
                # Find out who have requested this particular score
                my @certainrequesters;
                for my $i (0 .. $#scores) {
                    if ($scores[$i] eq $cmd2) {
                        push @certainrequesters, $requesters[$i];
                    }
                }
                
                my $requestssofar = $#certainrequesters+1;
                my $requestersline = join ', ', @certainrequesters;
                
                $self->sayc(__x("Score {score} for game #{no} have requested: " .
                                "{requesters} [{requestersc}/{neededreq}",
                                score => $cmd2, no => $cmd1,
                                requesters => $requestersline,
                                requestersc => $requestssofar,
                                neededreq => $neededreq_score));
                
                if ($requestssofar < $neededreq_score) {
                    return;
                }
            }
        }
        
        # - GOING TO ACCEPT THE SCORE -
        
        # Delete score requests related to this game
        delete($userscorereq{$cmd1});
        delete($captainscorereq{$cmd1});
        
        # Get the gamedata
        my @gamedata = split ',', $games{$cmd1};
        
        # Change game status from 'active' to 'closed'
        $gamedata[0] =~ s/active/closed/;
        
        # Retrieve the team skills
        my @teamskills = split ':', $gamedata[4];
        my $t1_skill = $teamskills[0];
        my $t2_skill = $teamskills[1];
        
        my $result;
        if    ($cmd2lc eq $team1lc) { $result = 1; }
        elsif ($cmd2lc eq $team2lc) { $result = 2; }
        elsif ($cmd2lc eq $drawlc)  { $result = 3; }
        
        my @pdata;
        my @pdeltas_out;
        my $p_delta;
        my $player;
        
        for my $i (0 .. $#plist) {
            $player = $plist[$i];
            @pdata = split '\.', $users{$player};
        
            if ($result == 1) {
            
                if ($i >= 0 && $i < $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t2_skill, 'WIN');
                    $pdata[2]++;
                }
            
                if ($i >= $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t1_skill, 'LOSS');
                    $pdata[3]++;
                }
                
            } elsif ($result == 2) {
            
                if ($i >= 0 && $i < $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t2_skill, 'LOSS');
                    $pdata[3]++;
                }
            
                if ($i >= $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t1_skill, 'WIN');
                    $pdata[2]++;
                }
            
            } elsif ($result == 3) {
            
                if ($i >= 0 && $i < $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t2_skill, 'DRAW');
                    $pdata[4]++;
                }
            
                if ($i >= $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t1_skill, 'DRAW');
                    $pdata[4]++;
                }
            }
            
            # This will go in gamedata
            $plist[$i] .= "($pdata[1]:$p_delta)";
            
            # Update to userdata
            $pdata[1] += $p_delta;
            $users{$player} = join '.', @pdata;
            
            # This will go to output
            if    ($p_delta > 0)  { $p_delta = "\x0309" . "+$p_delta\x0f"; }
            elsif ($p_delta == 0) { $p_delta = "\x0312" . "$p_delta\x0f"; }
            else                  { $p_delta = "\x0304" . "$p_delta\x0f"; }
            push @pdeltas_out, "$player($p_delta)";
        }
        
        # Update gamedata
        $gamedata[3] .= $result;
        $gamedata[4] = "$t1_skill:$t2_skill";
        $gamedata[5] = join ',', @plist;
        $#gamedata = 5;
        $games{$cmd1} = join ',', @gamedata;
        
        # - Give output about the game result -
        
        # Line 1
        $cmd1 = "\x02" . "#$cmd1\x0f";
        
        $self->sayc(__x("Game #{no} has ended:",
                        no => $cmd1));
        
        # Line 2
        my $outline = __x("Result: ");
        my $won     = __x("won");
        
        $outline .= "\x02";
        if ($result == 1) { $outline .= "$team1 $won"; }
        if ($result == 2) { $outline .= "$team2 $won"; }
        if ($result == 3) { $outline .= "$draw"; }
        $outline .= "\x0f";
        $self->sayc($outline);
        
        # Line 3
        $outline = join ', ', @pdeltas_out;
        
        $self->sayc(__x("Point changes: {line}", line => $outline));
        
        # Update the topic
        $self->updatetopic();
        
        # Save data
        save();
        
        # Send stats to the webserver
        $self->senddata();
        
        return;
    }
    
    
    # command .out
    elsif ($commands[0] eq '.out' || $commands[0] eq '.remove' ||
           $commands[0] eq '.rm'  || $commands[0] eq '.del') {
           
        if ($canout == 0) {
            $self->sayc(__x("Signing out is not possible at the moment."));
            return;
        }
        
        if ($who eq $captain1 || $who eq $captain2) {
            $self->sayc(__x("A captain can't sign out (must use .uncaptain first)"));
            return;
        }
        
        my $tbremoved;
        if ($#commands == 0) {
            # Sayer wants to remove himself
            $tbremoved = $who;
            
        } else {
            # Sayer wants someone else to be removed
            if ($accesslevel ne 'admin') {
            
                # If not an admin, check that
                # the sayer is signed himself
                if (issigned($who) == 0) {
                    $self->sayc(__x("{who} has not signed up.",
                                    who => $who));
                    return;
                }
            }
            
            $tbremoved = $commands[1];
        }
        
        # Get the player's index in @players
        my $indexofplayer = -1;
        for my $i (0 .. $#players) {
            if ($players[$i] eq $tbremoved) {
                $indexofplayer = $i;
                last;
            }
        }
        
        # If he wasn't there, return
        if ($indexofplayer == -1) {
            $self->sayc(__x("{who} has not signed up.",
                            who => $tbremoved));
            return;
        }
        
        # If sayer requested someone else to
        # be removed and he is not an admin
        if ($#commands > 0 && $accesslevel ne 'admin') {
        
            # Initialize %removereq value if necessary
            if (! exists($removereq{$tbremoved}) ) {
                $removereq{$tbremoved} = "";
            }
            
            # Get the requesters
            my $removereqline = $removereq{$tbremoved};
            my @requesters = split ',', $removereqline;
            
            # Check if the user already requested this
            my $alreadyrequested = 0;
            for my $i (0 .. $#requesters) {
                if ($requesters[$i] eq $who) {
                    $alreadyrequested = 1;
                }
            }
            if ($alreadyrequested == 0) {
                push(@requesters, $who);
            }
            
            # Update the player's removerequest information
            $removereq{$tbremoved} = join ',', @requesters ;
            
            # Give output
            my $requestssofar = $#requesters+1;
            my $requestersline = join ', ', @requesters ;
            
            $self->sayc(__x("Removing {who} from the sign-up have requested: " .
                            "{requesters} [{requestersc}/{neededreq}",
                            who => $tbremoved,
                            requesters => $requestersline,
                            requestersc => $requestssofar,
                            neededreq => $neededreq_remove));
            
            if ($requestssofar < $neededreq_remove) {
                return;
            }
        }
        
        # - GOING TO REMOVE A PLAYER -
        
        $self->outplayer($tbremoved);
        
        return;
    }
    
    
    # command .stats
    elsif ($commands[0] eq '.stats') {
        my $queried;
        
        if ($#commands == 0) {
            $queried = $who;
        } else {
            $queried = $commands[1];
        }
        
        if (! exists $users{$queried}) {
            $self->sayc(__x("User {who} was not found.",
                            who => $queried));
            return;
        }
        
        my @udata = split '\.', $users{$queried};
        
        $self->sayc(__x("{who} has {p} points, {w} wins, {l} losses and {d} draws",
                        who => $queried,
                        p => $udata[1], w => $udata[2], l => $udata[3], d => $udata[4]));
        
        return;
    }
    
    
    # command .lastgame and .gameinfo
    elsif ($commands[0] eq '.lastgame' || $commands[0] eq '.lg' ||
           $commands[0] eq '.gameinfo' || $commands[0] eq '.gi') {
            
        my $query;
        if ($commands[0] eq '.lastgame' || $commands[0] eq '.lg') {
            $query = findlastgame();
            
        } else { # command was .gameinfo or .gi
        
            if ($#commands != 1) {
                $self->sayc(__x("Syntax is {gno} <gameno>",
                                gno => $commands[0]));
                return;
            }
            
            $query = $commands[1];
        }
        
        if (! exists $games{$query}) {
            $self->sayc(__x("Game #{gno} was not found.",
                            gno => $query));
            return;
        }
        
        # Get the gamedata
        my @gamedata = split ',', $games{$query};
        
        # Get the time of the game
        my @timedata = split ':', $gamedata[1];
        my $ept = $timedata[1];
        my $timezone = get_timezone();
        my $dt = DateTime->from_epoch(epoch => $ept, time_zone=> $timezone);
        my $dtstr = $dt->day. "." .$dt->month. "." .$dt->year. " " .$dt->hms;
        
        # Get the players who played in this game
        my @plist = get_players_by_gameno($query);
        
        # Separate the teams from the player list
        my @t1_players = team1_from_plist(@plist);
        my @t2_players = team2_from_plist(@plist);
        
        # Get formatted playerlists
        my $team1str = $self->formatteam(@t1_players);
        my $team2str = $self->formatteam(@t2_players);
        
        # Find out what was the maxplayers and teamsize
        my $wasmaxplayers = $#plist + 1;
        my $wasteamsize = $#t1_players + 1;
        
        # Retrieve the team skills
        my @teamskills = split ':', $gamedata[4];
        my $t1_skill = $teamskills[0];
        my $t2_skill = $teamskills[1];
        
        my $game = __x("Game");
        $self->sayc("$game " . "\x02" . "#$query\x0f" . " ($dtstr):");
        $self->sayc("$team1 (" . "\x02" . "$t1_skill\x0f" . "): $team1str");
        $self->sayc("$team2 (" . "\x02" . "$t2_skill\x0f" . "): $team2str");
        
        # If the game had a map, also print map info
        my @mapdata = split ':', $gamedata[2];
        if ($#mapdata > 0) {
            $self->sayc("Map: " . "\x02" . "$mapdata[1]\x0f");
        }
        
        my $outline = "";
        my @gamedata0 = split ':', $gamedata[0];
        
        if ($gamedata0[1] eq 'active') {
            my $statuss = __x("Status");
            my $status = "\x02" . __x("active") . "\x0f";
            $outline = $statuss . ": " . $status;
        
        } elsif ($gamedata0[1] eq 'closed') {
        
            my @resultdata = split ':', $gamedata[3];
            $outline = __x("Result: ");
            my $won  = __x("won");
            
            $outline .= "\x02";
            
            if ($resultdata[1] == 1) { $outline .= "$team1 $won"; }
            if ($resultdata[1] == 2) { $outline .= "$team2 $won"; }
            if ($resultdata[1] == 3) { $outline .= "$draw"; }
            
            $outline .= "\x0f";
            
        } else {
            print STDERR "Invalid line in gamedata: $games{$query}\n";
        }
        
        $self->sayc($outline);
        
        return;
    }
    
    
    # command .whois
    elsif ($commands[0] eq '.whois' || $commands[0] eq '.who') {
        my $queried;
        
        if ($#commands == 0) {
            $queried = $who;
        } else {
            $queried = $commands[1];
        }
        
        if (! exists $users{$queried}) {
            $self->sayc(__x("User {who} was not found.",
                            who => $queried));
            return;
        }
        
        my @udata = split '\.', $users{$queried};
        
        $self->sayc("$queried: $udata[0]");
        
        return;
    }
    
    
    # command .server
    elsif ($commands[0] eq '.server' || $commands[0] eq '.srv') {
    
        $self->printserverinfo();
        
        return;
    }
    
    
    # command .mumble
    elsif ($commands[0] eq '.mumble' || $commands[0] eq '.mb') {
    
        $self->printvoipinfo();
        
        return;
    }
    
    
    # command .votecaptain
    elsif ($commands[0] eq '.votecaptain' || $commands[0] eq '.vc') {
    
        if ($gamehascaptains == 0) {
            $self->sayc(__x("Command {command} is not enabled (gamehascaptains = 0)",
                            command => $commands[0]));
            return;
        }
        
        # Get a list of potential captains
        my @votableplayers;
        my @userdata;
        my $points;
        
        for my $i (0 .. $#players) {
            # If not a captain
            if ($players[$i] ne $captain1 && $players[$i] ne $captain2) {
            
                @userdata = split '\.', $users{$players[$i]};
                $points = $userdata[1];
                
                # If has sufficient points
                if ($points > $initialpoints) {
                    push @votableplayers, $players[$i];
                }
            }
        }
        my $players = join ' ', @votableplayers;
        
        if ($#commands < 1) {
            $self->sayc(__x("Syntax is {command} <playername>",
                            command => $commands[0]));
            
            $self->sayc(__x("Votable players are: {players}",
                            players => $players));
            
            $self->sayc(__x("A given vote can be removed by giving a dot as the name." .
                            " Given votes can be viewed with command {command} votes",
                            command => $commands[0]));
            return;
        }
        
        if ($canvotecaptain == 0) {
            $self->sayc(__x("Voting of captain is not possible at the moment."));
            return;
        }
        
        my $outline;
        
        # User wanted to see the votes
        if ($commands[1] eq 'votes') {
            if ($captainvotecount == 0) {
                $outline = __x("No captainvotes yet.");
                
            } else {
                $outline = __x("Captainvotes: ");
                
                for my $player (@votableplayers) {
                    if ($captainvotes{$player} > 0) {
                        $outline .= "$player\[$captainvotes{$player}\], ";
                    }
                }
                
                if ($#votableplayers > -1) {
                    chop $outline; chop $outline;
                }
            }
            
            $self->sayc($outline);
            return;
        }
        
        if (issigned($who) == 0) {
            $self->sayc(__x("One must be signed up to be able to vote for a captain."));
            return;
        }
        
        
        my $validvote = 0;
        for my $player (@votableplayers) {
            if ($commands[1] eq $player || $commands[1] eq '.') {
                $validvote = 1;
                last;
            }
        }
        if ($validvote == 0) {
            $self->sayc(__x("Invalid player name given. Votable players are: {players}",
                            players => $players));
            
            return;
        }
        
        if (! exists $captainvoters{$who}) {
            $captainvoters{$who} = "";
        }
        
        # Check if voter has a former vote
        my $hasformervote = 0;
        if ($captainvoters{$who} ne '') {
            $hasformervote = 1;
        }
        
        # If voter has a former vote, check if
        # it's the same vote he made now
        my $samevote = 0;
        if ($hasformervote == 1) {
            if ($captainvoters{$who} eq $commands[1]) {
                $samevote = 1;
            }
        }
        
        # Check if a change happened in the user's vote
        my $changehappened = 0;
        if ($hasformervote == 1 && $samevote == 0) {
            $changehappened = 1;
        }
        
        if ($hasformervote == 0 && $commands[1] ne '.') {
            $changehappened = 1;
        }
        
        # User wanted to void his vote
        if ($commands[1] eq '.') {
            if ($captainvoters{$who} ne '') {
                
                if (exists $captainvotes{$captainvoters{$who}} &&
                    $captainvotes{$captainvoters{$who}} > 0) {
                    
                    $captainvotes{$captainvoters{$who}} -= 1;
                    $captainvotecount--;
                }
                
                $captainvoters{$who} = '';
            }
        
        # User voted for a player
        } else {
            if ($captainvoters{$who} ne $commands[1]) {
            
                if (exists $captainvotes{$captainvoters{$who}} &&
                    $captainvotes{$captainvoters{$who}} > 0) {
                    
                    $captainvotes{$captainvoters{$who}} -= 1;
                    $captainvotecount--;
                }
                
                $captainvotes{$commands[1]} += 1;
                $captainvoters{$who} = $commands[1];
                $captainvotecount++;
            }
        }
        
        if ($changehappened == 1) {
            $outline = __x("Captainvotes: ");
            
            for my $player (@votableplayers) { 
                if ($captainvotes{$player} > 0) {
                    $outline .= "$player\[$captainvotes{$player}\], ";
                }
            }
            
            if ($#votableplayers > -1) {
                chop $outline; chop $outline;
            }
        
        } else {
            if ($hasformervote == 0) {
                $outline = __x("{who} hasn't voted for a captain yet.", who => $who);
            }
            
            if ($samevote == 1) {
                $outline = __x("{who} has  already voted for {vote} as a captain.",
                               who => $who, vote => $commands[1]);
            }
        }
        
        $self->sayc($outline);
        return;
    }
    
    
    # command .votemap
    elsif ($commands[0] eq '.votemap' || $commands[0] eq '.vm') {
    
        if ($gamehasmap == 0) {
            $self->sayc(__x("Command {command} is not enabled (gamehasmap = 0)",
                            command => $commands[0]));
            return;
        }
        
        my $maps = join ', ', @maps;
        
        if ($#commands < 1) {
            $self->sayc(__x("Syntax is {command} <mapname>",
                            command => $commands[0]));
            
            $self->sayc(__x("Votable maps are: {maps}",
                            maps => $maps));
                            
            $self->sayc(__x("A given vote can be removed by giving a dot as the map." .
                            " Given votes can be viewed with command {command} votes",
                            command => $commands[0]));
            return;
        }
        
        if ($canvotemap == 0) {
            $self->sayc(__x("Voting of map is not possible at the moment."));
            return;
        }
        
        my $outline;
        if ($commands[1] eq 'votes') {
            if ($mapvotecount == 0) {
                $outline = __x("No mapvotes yet.");
                
            } else {
                $outline = __x("Mapvotes: ");
                
                for my $map (@maps) {
                    $outline .= "$map\[$mapvotes{$map}\], ";
                }
                chop $outline; chop $outline;
            }
            
            $self->sayc($outline);
            return;
        }
        
        if (issigned($who) == 0) {
            $self->sayc(__x("One must be signed up to be able to vote for a map."));
            return;
        }
        
        my $validvote = 0;
        for my $map (@maps) {
            if ($commands[1] eq $map || $commands[1] eq '.') {
                $validvote = 1;
                last;
            }
        }
        if ($validvote == 0) {
            $self->sayc(__x("Invalid map. Votable maps are: {maps}",
                            maps => $maps));
            return;
        }
        
        if (! exists $mapvoters{$who}) {
            $mapvoters{$who} = "";
        }
        
        # Check if voter has a former vote
        my $hasformervote = 0;
        if ($mapvoters{$who} ne '') {
            $hasformervote = 1;
        }
        
        # If voter has a former vote, check if
        # it's the same vote he made now
        my $samevote = 0;
        if ($hasformervote == 1) {
            if ($mapvoters{$who} eq $commands[1]) {
                $samevote = 1;
            }
        }
        
        # Check if a change happened in the user's vote
        my $changehappened = 0;
        if ($hasformervote == 1 && $samevote == 0) {
            $changehappened = 1;
        }
        
        if ($hasformervote == 0 && $commands[1] ne '.') {
            $changehappened = 1;
        }
        
        # User wanted to void his vote
        if ($commands[1] eq '.') {
            if ($mapvoters{$who} ne '') {
                
                if (exists $mapvotes{$mapvoters{$who}} &&
                    $mapvotes{$mapvoters{$who}} > 0) {
                    
                    $mapvotes{$mapvoters{$who}} -= 1;
                    $mapvotecount--;
                }
                
                $mapvoters{$who} = '';
            }
        
        # User voted for a map
        } else {
            if ($mapvoters{$who} ne $commands[1]) {
            
                if (exists $mapvotes{$mapvoters{$who}} &&
                    $mapvotes{$mapvoters{$who}} > 0) {
                    
                    $mapvotes{$mapvoters{$who}} -= 1;
                    $mapvotecount--;
                }
                
                $mapvotes{$commands[1]} += 1;
                $mapvoters{$who} = $commands[1];
                $mapvotecount++;
            }
        }
        
        if ($changehappened == 1) {
            $outline = __x("Mapvotes: ");
            
            for my $map (@maps) { $outline .= "$map\[$mapvotes{$map}\], "; }
            chop $outline; chop $outline;
        
        } else {
            if ($hasformervote == 0) {
                $outline = __x("{who} hasn't voted for a map yet.", who => $who);
            }
            
            if ($samevote == 1) {
                $outline = __x("{who} has already voted for {vote} as a map.",
                               who => $who, vote => $commands[1]);
            }
        }
        
        $self->sayc($outline);
        return;
    }
    
    
    # command .replace
    elsif ($commands[0] eq '.replace') {
            
        if ($#commands < 2) {
            if ($accesslevel eq 'admin') {
            
                $self->sayc(__x("Syntax is:"));
                
                $self->sayc(__x("To a game about to begin: {command} " . 
                                "<to-be-replaced> <replacement>",
                                command => $commands[0]));
                
                $self->sayc(__x("To a game that already started: {command} " .
                                "<gameno> <to-be-replaced> <replacement>",
                                command => $commands[0]));
            
            } else {
                $self->sayc(__x("Syntax is {command} <to-be-replaced> <replacement>",
                                command => $commands[0]));
            }
            
            return;
        }
        
        if ($#commands < 3) {
            # - Replace someone in the current signup -
            
            if ($commands[1] eq $captain1 || $commands[1] eq $captain2) {
                $self->sayc(__x("A captain cannot be replaced."));
                return;
            }
            
            my $replacedindex = -1;
            for my $i (0 .. $#players) {
                if ($players[$i] eq $commands[1]) {
                    $replacedindex = $i;
                }
            }
            
            if ($replacedindex == -1) {
                $self->sayc(__x("{who} has not signed up.",
                                who => $commands[1]));
                return;
            }
            
            if (issigned($commands[2])) {
                $self->sayc(__x("{who} has already signed up.",
                                who => $commands[2]));
                return;
            }
            
            # If sayer is an admin
            if ($accesslevel eq 'admin') {
            
                # If the replacement doesn't exist in userdata, add him
                if (! exists $users{$commands[2]}) {
                    $users{$commands[2]} = "user.$initialpoints.0.0.0";
                }
                
                $self->voidusersvotes($commands[1]);
                $self->voidusersrequests($commands[1]);
                
                splice(@players, $replacedindex, 1, $commands[2]);
                $self->sayc(__x("Replaced {rem} with player {rep}.",
                                rem => $commands[1], rep => $commands[2]));
                
                return;
            }
            
            # - Sayer is an user -
            
            if (issigned($who) == 0) {
                $self->sayc(__x("{who} has not signed up.",
                                who => $who));
                return;
            }
            
            if (! exists $replacereq{$commands[1]}) {
                $replacereq{$commands[1]} = "";
            }
            
            my $requestline = $replacereq{$commands[1]};
            my @requests = split ',', $requestline;
            my @requesters;
            my @replacements;
            my @arr;
            
            for my $request (@requests) {
                @arr = split ':', $request;
                push @requesters, $arr[0];
                push @replacements, $arr[1];
            }
            
            my $samerequest = 0;
            for my $i (0 .. $#requesters) {
                if ($requesters[$i] eq $who && $replacements[$i] eq $commands[2]) {
                    $samerequest = 1;
                }
            }
                
            if ($samerequest == 0) {
                push @requesters, $who;
                push @replacements, $commands[2];
            }
            
            # Update to %replacereq 
            @arr=();
            for my $i (0 .. $#requesters) {
                push @arr, "$requesters[$i]:$replacements[$i]";
            }
            $replacereq{$commands[1]} = join ',', @arr;
            
            # Find out who requested this player to be
            # requested with this particular player
            my @certainrequesters;
            
            for my $i (0 .. $#replacements) {
                if ($replacements[$i] eq $commands[2]) {
                    push @certainrequesters, $requesters[$i];
                }
            }
            
            my $requestssofar = $#certainrequesters+1;
            my $requestersline = join ', ', @certainrequesters;
            
            $self->sayc(__x("Replacing {rem} with {rep} have requested: " .
                            "{requesters} [{requestersc}/{neededreq}",
                            rem => $commands[1], rep => $commands[2],
                            requesters => $requestersline,
                            requestersc => $requestssofar,
                            neededreq => $neededreq_replace));
            
            # If not enough requests yet, return
            if ($requestssofar < $neededreq_replace) {
                return;
            }
            
            # - Going to make the replacement -
            
            # Add the replacement player into %users if not there already
            if (! exists $users{$commands[2]}) {
                $users{$commands[2]} = "user.$initialpoints.0.0.0";
            }
            
            # Make the replacement
            splice(@players, $replacedindex, 1, $commands[2]);
            
            $self->sayc(__x("Replaced {rem} with player {rep}.",
                            rem => $commands[1], rep => $commands[2]));
            
            # Void votes of the player who was replaced
            $self->voidusersvotes($commands[1]);
            $self->voidusersrequests($commands[1]);
            
            $self->updatetopic();
            
            return;
        }
        
        # - Replace someone in a game that already started -
        
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("Only an admin can make a replace to a game that already started."));
            return;
        }
        
        if (! exists $games{$commands[1]} ) {
            $self->sayc(__x("Game #{no} was not found.",
                            no => $commands[1]));
            return;
        }

        # Get the gamedata
        my @gamedata = split ',', $games{$commands[1]};
        
        # Get the players that played in this game
        my @plist = get_players_by_gameno($commands[1]);
        
        # Check that the replacement is not already on the player list
        my $validrep = 1;
        for my $p (@plist) {
            if ($commands[3] eq $p) {
                $validrep = 0;
                last;
            }
        }
        if ($validrep == 0) {
            $self->sayc(__x("{who} is already on the player list (in game #{no})",
                            who => $commands[3], no => $commands[1]));
            return;
        }
        
        # Find out what was the maxplayers and teamsize
        my $wasmaxplayers = $#plist + 1;
        my $wasteamsize = $wasmaxplayers / 2;
        
        # Get the game number and game status
        my @gamedata0 = split ':', $gamedata[0];
        
        # Check if the game is 'closed'
        if ($gamedata0[1] eq 'closed') {
            $self->sayc(__x("Game #{no} has already ended.",
                            no => $commands[1]));
            return;
        }
        
        my $wasreplaced = 0;
        
        # Search for the player in the player list
        for my $i (0 .. $#plist) {
        
            # If the player was found
            if ($plist[$i] eq $commands[2]) {
            
                # Add the replacement player to %users if necessary
                if (! exists $users{$commands[3]}) {
                    $users{$commands[3]} = "user.$initialpoints.0.0.0";
                }
                
                # Update to %games
                $plist[$i] = $commands[3];
                $gamedata[5] = join ',', @plist;
                $#gamedata = 5;
                $games{$commands[1]} = join ',', @gamedata;
                
                $wasreplaced = 1;
            }
        }
        
        if ($wasreplaced == 1) {
            $self->sayc(__x("Replaced {rem} with player {rep} (in game #{no})",
                            rem => $commands[2], rep => $commands[3],
                            no => $commands[1]));
            
        } else {
            $self->sayc(__x("Player {rem} was not found (from game #{no})",
                            rem => $commands[2],
                            no => $commands[1]));
        }
        
        return;
    }
    
    
    # command .games
    elsif ($commands[0] eq '.games') {
        
        my $activegames = getactivegames();
        my $outline = "";
        
        if ($activegames eq '') {
            
            $outline = __x("No ongoing games.");
        } else {
            $outline = __x("Ongoing games: {games}", games => $activegames);
        }
        
        $self->sayc($outline);
        return;
    }
    
    
    # command .accesslevel
    elsif ($commands[0] eq '.accesslevel') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who));
            return;
        }
        
        if ($#commands < 2 ||
            $commands[2] ne 'admin' && $commands[2] ne 'user') {
            
            $self->sayc(__x("Syntax is {command} <username> <admin|user>",
                            command => $commands[0]));
            return;
        }
        
        # Case new user
        if (! exists $users{$commands[1]}) {
            $users{$commands[1]} = "$commands[2].$initialpoints.0.0.0";
            
            $self->sayc(__x("{who} is now an {accesslevel}.",
                            who => $commands[1],
                            accesslevel => $commands[2]));
            return;
        }
        
        # Case existing user
        my @uservalues = split '\.', $users{$commands[1]};
        my $currentaccess = $uservalues[0];
        
        if ($currentaccess eq $commands[2]) {
        
            $self->sayc(__x("{who} is already an {accesslevel}.",
                            who => $commands[1],
                            accesslevel => $commands[2]));
            return;
        
        } else {
        
            if ($currentaccess eq 'admin') {
                my $isoriginaladmin = 0;
                for my $admin (@admins) {
                    if ($who eq $admin) {
                        $isoriginaladmin = 1;
                    }
                }
                
                if ($isoriginaladmin == 0) {
                    $self->sayc(__x("{who} is not an original admin.",
                                    who => $who));
                    return;
                }
            }
        
            $uservalues[0] = $commands[2];
            $users{$commands[1]} = join '.', @uservalues;
            
            $self->sayc(__x("{who} is now an {accesslevel}.",
                            who => $commands[1],
                            accesslevel => $commands[2]));
        }
        
        return;
    }
    
    
    # command .resetstats
    elsif ($commands[0] eq '.resetstats') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who));
            return;
        }
        
        if ($#commands < 1) {
            $self->sayc(__x("Syntax is {command} <username>",
                            command => $commands[0]));
            return;
        }
        
        if (! exists $users{$commands[1]}) {
            $users{$commands[1]} = "user.$initialpoints.0.0.0";
            
            $self->sayc(__x("{who}'s stats have been reseted.",
                            who => $commands[1]));
            return;
        }
        
        my @uservalues = split '\.', $users{$commands[1]};
        $users{$commands[1]} = "$uservalues[0]" . "." . "$initialpoints" . ".0.0.0";
        
        $self->sayc(__x("{who}'s stats have been reseted.",
                        who => $commands[1]));
                        
        return;
    }
    
    
    # command .voidgame
    elsif ($commands[0] eq '.voidgame') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who));
            return;
        }
        
        if ($#commands < 1) {
            $self->sayc(__x("Syntax is {command} <gameno>",
                            command => $commands[0]));
            return;
        }
        
        if (! exists $games{$commands[1]}) {
            $self->sayc(__x("Game #{no} was not found.",
                            no => $commands[1]));
            return;
        }
        
        # Get the gamedata
        my @gamedata = split ',', $games{$commands[1]};
        
        # Check if game is still actie
        if ( index($gamedata[0], 'active') != -1 ) {
        
            $self->sayc(__x("Game #{no} is still active.",
                            no => $commands[1]));
            return;
        }
        
        # Get result from gamedata
        my @result = split ':', $gamedata[3];
        my $result = $result[1];

        # Get the players that played in this game
        my @plist = get_players_by_gameno($commands[1]);
        
        # Get the point deltas of the players
        my @pdeltas = get_points_by_gameno($commands[1], 'delta');
        
        # Find out what was the maxplayers and teamsize
        my $wasmaxplayers = $#plist + 1;
        my $wasteamsize = $wasmaxplayers / 2;
        
        my @pdata;
        my $p_delta;
        
        for my $i (0 .. $#plist) {
            @pdata = split '\.', $users{$plist[$i]};
        
            if ($result == 1) {
            
                if ($i >= 0 && $i < $wasteamsize) {
                    $pdata[2]--;
                }
            
                if ($i >= $wasteamsize) {
                    $pdata[3]--;
                }
                
            } elsif ($result == 2) {
            
                if ($i >= 0 && $i < $wasteamsize) {
                    $pdata[3]--;
                }
            
                if ($i >= $wasteamsize) {
                    $pdata[2]--;
                }
            
            } elsif ($result == 3) {
                $pdata[4]--;
            }
            
            # Update to userdata
            $pdata[1] -= $pdeltas[$i];
            $users{$plist[$i]} = join '.', @pdata;
        }
        
        delete $games{$commands[1]};
        
        $self->sayc(__x("Game #{no} voided.",
                        no => $commands[1]));
        
        return;
    }
    
    
    # command .changename
    elsif ($commands[0] eq '.changename') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who));
            return;
        }
        
        if ($#commands != 2) {
            $self->sayc(__x("Syntax is {command} <current_name> <new_name>",
                            command => $commands[0]));
            return;
        }
        
        if (! exists $users{$commands[1]}) {
            $self->sayc(__x("User {who} was not found.",
                            who => $commands[1]));
            return;
        }
        
        if ( exists $users{$commands[2]}) {
            $self->sayc(__x("A user named {who} already exists.",
                            who => $commands[2]));
            return;
        }
        
        # Make changes to userdata
        $users{$commands[2]} = $users{$commands[1]};
        delete($users{$commands[1]});
        
        # Make changes to gamedata
        foreach (keys %games) {
            $games{$_} =~ s/$commands[1]/$commands[2]/g;
        }
        
        $self->sayc(__x("{old} is now renamed to {new}",
                        old => $commands[1], new => $commands[2]));
                        
        return;
    }
    
    # command .combineusers
    elsif ($commands[0] eq '.combineusers') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who));
            return;
        }
        
        if ($#commands < 2) {
            $self->sayc(__x("{command} combines the stats of two " .
                            "users and deletes the other account.",
                            command => $commands[0]));
            
            $self->sayc(__x("Syntax is {command} <remaining_user> <user_to-be-removed>",
                            command => $commands[0]));
            return;
        }
        
        if (! exists $users{$commands[1]}) {
            $self->sayc(__x("User {who} was not found.",
                            who => $commands[1]));
            return;
        }
        
        if (! exists $users{$commands[2]}) {
            $self->sayc(__x("User {who} was not found.",
                            who => $commands[2]));
            return;
        }
        
        my @user1_data = split '\.', $users{$commands[1]};
        my @user2_data = split '\.', $users{$commands[2]};
        
        # If user2 is an admin, make sure the
        # new account will be admin as well.
        # Otherwise, don't do changes to the accesslevel.
        if ($user2_data[0] eq 'admin') {
            $user1_data[0] = "admin";
        }
        
        # Calculate how much points have to be
        # added to/subtracted from the new account
        my $pointschange = $user2_data[1] - $initialpoints;
        $user1_data[1] += $pointschange;
        
        # Add the amount of wins/losses/draws
        $user1_data[2] += $user2_data[2];
        $user1_data[3] += $user2_data[3];
        $user1_data[4] += $user2_data[4];
        
        # Update the data of the user that remains
        $users{$commands[1]} = join('.', @user1_data);
        
        # Delete the other user
        delete $users{$commands[2]};
        
        # Make changes to gamedata
        foreach (keys %games) {
            $games{$_} =~ s/$commands[2]/$commands[1]/g;
        }
        
        $self->sayc(__x("The stats of {rem} and {del} are now " .
                        "combined. User {del} deleted.",
                        rem => $commands[1], del => $commands[2]));
        
        return;
    }
    
    
    # command .rank
    elsif ($commands[0] eq '.rank' || $commands[0] eq '.top') {
    
        if ($commands[0] eq '.rank') {
            if ($#commands > 0) {
                $who = $commands[1];
            }
            
            if (! exists $users{$who}) {
                $self->sayc(__x("User {who} was not found.",
                                who => $who));
                return;
            }
        }
        
        my @ranklist;
        my @uservalues;
        my @temp; my @temp2;
        my $temp3;
        my $playedmatches;
        
        foreach (keys %users) {
            @uservalues = split('\.', $users{$_});
            $playedmatches = $uservalues[2] + $uservalues[3] + $uservalues[4];
            if ($playedmatches >= $rankedafter_games) {
                push(@ranklist, "$_.$uservalues[1]");
                
                if ($#ranklist > 0) {   # list with a size of 1 is considered sorted
                    for (my $i=$#ranklist ; $i>0 ; $i--) {  # sort using insertion sort
                        @temp = split('\.', $ranklist[$i]);
                        @temp2 = split('\.', $ranklist[$i-1]);
                        
                        if ($temp[1] > $temp2[1]) {
                            $temp3 = $ranklist[$i];
                            $ranklist[$i] = $ranklist[$i-1];
                            $ranklist[$i-1] = $temp3;
                        } else { last; }
                    }
                }
            }
        }
        
        my $outline = "";
        
        if ($commands[0] eq '.rank') {
            @temp=();
            my $usersrank = -1;
            for my $i (0 .. $#ranklist) {
                @temp = split('\.', $ranklist[$i]);
                if ($temp[0] eq $who) {
                    $usersrank = $i+1;
                    last;
                }
            }
            
            if ($usersrank != -1) { 
                $outline = __x("{who} is ranked {rank} with points {points}",
                               who => $who, rank => $usersrank, points => $temp[1]);
            } else {
                
                $outline = __x("{who} is not ranked yet.", who => $who);
            }

        } else { # if command was .top
        
            if ($#ranklist == -1) {
                $self->sayc(__x("There are no ranked users."));
                return;
            }
        
            my $listlength = $topdefaultlength;
            if ($#commands > 0 && $commands[1] =~ /^[+-]?\d+$/ ) {
                $listlength = $commands[1];
            }
            
            if ($#ranklist+1 < $listlength) {
                $listlength = $#ranklist+1
            }
            
            $outline = "Top $listlength: ";
            my @arr;
            
            for my $i (0 .. $listlength-1) {
                @arr = split('\.', $ranklist[$i]);
                $outline .= "\x02" . ($i+1) . ".\x0f" . " $arr[0]\($arr[1]\), ";
            }
            chop $outline, chop $outline;
            
            if ($listlength > $topdefaultlength) {
                $self->say(channel => "msg", who => $who, body => $outline);
                return;
            }
        }
        
        $self->sayc($outline);
        return;
    }
    
    
    # command .shutdown
    elsif ($commands[0] eq '.shutdown') {
    
        my $originaladmin = 0;
        for my $admin (@admins) {
            if ($who eq $admin) {
                $originaladmin = 1;
            }
        }
        
        if ($originaladmin == 0) {
            $self->sayc(__x("{who} is not an original admin.",
                            who => $who));
            return;
        }
        
        $self->save();
        $self->shutdown();
        return;
    }
    
    
    # command .commands
    elsif ($commands[0] eq '.commands' || $commands[0] eq '.commandlist' || 
           $commands[0] eq '.cmdlist' || $commands[0] eq '.cmds' || $commands[0] eq '.help') {
    
        if ($#commands == 1 && $commands[1] eq 'verbose') {
            my $adddesc = __x("           = Signs you up for the game.");
            my $listdesc = __x("          = Shows you list of signed up players.");
            my $outdesc = __x("           = Signs you out from the game. In addition, you can request an another player to be removed.");
            my $votemapdesc = __x("       = Syntax is .votemap <mapname>. More info with .votemap");
            my $votecaptaindesc = __x("   = Syntax is .votecaptain <playername>. More info with .votecaptain");
            my $captaindesc = __x("       = Makes you a captain. Command is only available if there is a free captain slot.");
            my $uncaptaindesc = __x("     = Frees the captain slot from you, supposing that you are a captain and player picking hasn't started");
            my $rafflecaptaindesc = __x(" = Requests the raffling of a new captain to replace a current captain. Available after the picking of players has started. More info with .rafflecaptain");
            my $serverdesc = __x("        = Prints the game server info.");
            my $mumbledesc = __x("        = Prints the mumble server info.");
            my $pickdesc = __x("          = Captain's command to pick a player into his team.");
            my $reportdesc = __x("        = You can request a score for a game with this command. More info with .report");
            my $statsdesc = __x("         = Prints your stats (or someone else's stats with .stats <playername>)");
            my $lastgamedesc = __x("      = Prints the info on the last game that was started.");
            my $gameinfodesc = __x("      = Syntax is .gameinfo <gameno>. Prints the info of the given game.");
            my $replacedesc = __x("       = You can request a player to be replaced with another player with this command. More info with .replace");
            my $gamesdesc = __x("         = Prints a list of the games that are active.");
            my $rankdesc = __x("          = Prints your ranking (or someone else's with .rank playername)");
            my $topdesc = __x("           = Prints a list of top ranked players. You can define the length of the list with .top <length>");
            my $hl_offdesc = __x("        = Puts you into hilight-ignore, (you're no longer hilighted on command .hilight)");
            my $hl_ondesc = __x("         = Removes you from the hilight-ignore (you can again be hilighted on command .hilight)");
            my $whoisdesc = __x("         = Prints your (or someone else's) username and accesslevel.");
            my $admincommandsdesc = __x(" = (Admins only) Gives a list of commands available to admins as a private message.");
            
            $self->say(channel => "msg", who => $who, body => ".add $adddesc");
            $self->say(channel => "msg", who => $who, body => ".list $listdesc");
            $self->say(channel => "msg", who => $who, body => ".out $outdesc");
            $self->say(channel => "msg", who => $who, body => ".votemap $votemapdesc");
            $self->say(channel => "msg", who => $who, body => ".votecaptain $votecaptaindesc");
            $self->say(channel => "msg", who => $who, body => ".captain $captaindesc");
            $self->say(channel => "msg", who => $who, body => ".uncaptain $uncaptaindesc");
            $self->say(channel => "msg", who => $who, body => ".rafflecaptain $rafflecaptaindesc");
            $self->say(channel => "msg", who => $who, body => ".server $serverdesc");
            $self->say(channel => "msg", who => $who, body => ".mumble $mumbledesc");
            $self->say(channel => "msg", who => $who, body => ".pick $pickdesc");
            $self->say(channel => "msg", who => $who, body => ".report $reportdesc");
            $self->say(channel => "msg", who => $who, body => ".stats $statsdesc");
            $self->say(channel => "msg", who => $who, body => ".lastgame $lastgamedesc");
            $self->say(channel => "msg", who => $who, body => ".gameinfo $gameinfodesc");
            $self->say(channel => "msg", who => $who, body => ".replace $replacedesc");
            $self->say(channel => "msg", who => $who, body => ".games $gamesdesc");
            $self->say(channel => "msg", who => $who, body => ".rank $rankdesc");
            $self->say(channel => "msg", who => $who, body => ".top $topdesc");
            $self->say(channel => "msg", who => $who, body => ".hl off $hl_offdesc");
            $self->say(channel => "msg", who => $who, body => ".hl on $hl_ondesc");
            $self->say(channel => "msg", who => $who, body => ".whois $whoisdesc");
            $self->say(channel => "msg", who => $who, body => ".admincommands $admincommandsdesc");
            
            return;
        }
        my $outline = __x("Commands are ");
        $outline .= ".add .list .out .votemap .votecaptain .captain .uncaptain " .
                       ".rafflecaptain .server .mumble .pick .report .stats .lastgame " .
                       ".gameinfo .replace .games .rank .top .hl off/on .whois .admincommands";
                        
        $self->sayc($outline);
        $self->sayc(__x("To get descriptions for the commands, use {command} verbose",
                        command => $commands[0]));
        
        return;
    }
    
    
    # command .admincommands
    elsif ($commands[0] eq '.admincommands') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who));
            return;
        }
        
        my $adddesc = __x("            = Signs a player up for the game. Syntax is .add <playername>");
        my $outdesc = __x("            = Signs a player out from the game. Syntax is .out <playername>");
        my $abortdesc = __x("          = Aborts the sign-up and clears the player list.");
        my $captaindesc = __x("        = You can make someone a captain with this command, supposing that there's a free captain slot and that the player is signed up.");
        my $uncaptaindesc = __x("      = Frees a captain slot from someone. Syntax is .uncaptain <captains_name>. After the picking has started, use .changecaptain or rafflecaptain.");
        my $changecaptaindesc = __x("  = You can change the captain with this command under any circumstances. Syntax is .changecaptain <curr_captain> <new_captain>.");
        my $rafflecaptaindesc = __x("  = You can request the raffling of a new captain to replace a current captain, supposing that picking has started. Syntax is .rafflecaptain <captains_name>.");
        my $replacedesc = __x("        = Replaces a player in the signup or in a game that already started. More info on .replace");
        my $aoedesc = __x("            = Sends a private irc-notice to everyone on the channel about the status of the signup.");
        my $hilightdesc = __x("        = Highlights everyone on the channel at once.");
        my $reportdesc = __x("         = Sets the score of a game. Syntax is .report <gameno> <{team1}|{team2}|{draw}", team1=>$team1, team2=>$team2, draw=>$draw);
        my $voidgamedesc = __x("       = Voids a game as if it was never played. Syntax is .voidgame <gameno>");
        my $accessleveldesc = __x("    = Sets the given user's accesslevel to the given level. Syntax is .accesslevel <username> <admin|user>");
        my $changenamedesc = __x("     = Changes the given user's username. Syntax is .changename <current_name> <new_name>");
        my $combineusersdesc = __x("   = Combines the stats of two players and deletes the other user. Syntax is .combineusers <user-to-remain> <user-to-be-deleted>");
        my $resetstatsdesc = __x("     = Resets the given user's stats. Syntax is .resetstats <username>");
        my $setdesc = __x("            = Sets the value of the given variable or prints its current value if a value is not given. Syntax is .set <variable> <value>. More info on .set");
        my $addmapdesc = __x("         = Adds a map into the map pool.");
        my $removemapdesc = __x("      = Removes a map from the map pool.");
        my $shutdowndesc = __x("       = (Original admins only) Saves all data and shuts the bot down.");
        
        $self->say(channel => "msg", who => $who, body => ".add $adddesc");
        $self->say(channel => "msg", who => $who, body => ".out $outdesc");
        $self->say(channel => "msg", who => $who, body => ".abort $abortdesc");
        $self->say(channel => "msg", who => $who, body => ".captain $captaindesc");
        $self->say(channel => "msg", who => $who, body => ".uncaptain $uncaptaindesc");
        $self->say(channel => "msg", who => $who, body => ".rafflecaptain $rafflecaptaindesc");
        $self->say(channel => "msg", who => $who, body => ".replace $replacedesc");
        $self->say(channel => "msg", who => $who, body => ".aoe $aoedesc");
        $self->say(channel => "msg", who => $who, body => ".hilight $hilightdesc");
        $self->say(channel => "msg", who => $who, body => ".report $reportdesc");
        $self->say(channel => "msg", who => $who, body => ".voidgame $voidgamedesc");
        $self->say(channel => "msg", who => $who, body => ".accesslevel $accessleveldesc");
        $self->say(channel => "msg", who => $who, body => ".changename $changenamedesc");
        $self->say(channel => "msg", who => $who, body => ".combineusers $combineusersdesc");
        $self->say(channel => "msg", who => $who, body => ".resetstats $resetstatsdesc");
        $self->say(channel => "msg", who => $who, body => ".set $setdesc");
        $self->say(channel => "msg", who => $who, body => ".addmap $addmapdesc");
        $self->say(channel => "msg", who => $who, body => ".removemap $removemapdesc");
        $self->say(channel => "msg", who => $who, body => ".shutdown $shutdowndesc");

        return;
    }
    
    # command .addmap
    elsif ($commands[0] eq '.addmap') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.", who => $who));
            return;
        }
        
        if ($#commands < 1) {
            $self->sayc(__x("Syntax is {command} <mapname>",
                            command => $commands[0]));
            return;
        }
        
        my $mapexists = 0;
        for my $map (@maps) {
            if ($map eq $commands[1]) {
                $mapexists = 1;
            }
        }
        
        if ($mapexists == 0) {
            push(@maps, $commands[1]);
            $mapvotes{$commands[1]} = 0;
            
            $self->sayc(__x("\"{map}\" added to the map pool.",
                            map => $commands[1]));
        } else {
            $self->sayc(__x("\"{map}\" is already in the map pool.",
                            map => $commands[1]));
        }
        
        return;
    }
    
    
    # command .removemap
    elsif ($commands[0] eq '.removemap') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.", who => $who));
            return;
        }
        
        if ($#commands < 1) {
            $self->sayc(__x("Syntax is {command} <mapname>",
                            command => $commands[0]));
            return;
        }
        
        for my $i (0 .. $#maps) {
            if ($maps[$i] eq $commands[1]) {
                splice(@maps, $i, 1);
                
                $self->sayc(__x("\"{map}\" removed from the map pool.",
                                map => $commands[1]));
                return;
            }
        }
        
        return;
    }
    
    
    # command .set
    elsif ($commands[0] eq '.set') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.", who => $who));
            return;
        }
        
        if ($#commands == 0) {
            $self->sayc(__x("Syntax is {command} <variable> <value>",
                            command => $commands[0]));
                            
            $self->sayc(__x("Use {command} list to get a list of the variables",
                            command => $commands[0]));
            
            return;
        }
        
        my $outline = __x("Variables: ");
        
        if ($#commands > 0 && $commands[1] eq 'list') {
            
            $outline .= "team1, team2, draw, maxplayers, gameserverip, " .
                       "gameserverport, gameserverpw, voiceserverip, " .
                       "voiceserverport, voiceserverpw, neededvotes_captain, " .
                       "neededvotes_map, neededreq_replace, neededreq_remove, " .
                       "neededreq_score, neededreq_rafflecapt, neededreq_hl";
            $self->sayc($outline);
            
            $outline = "initialpoints, pointsonwin, pointsonloss, pointsondraw, " .
                       "p_scale_factor, p_scale_factor_draw, p_max_variance " .
                       "topdefaultlength, gamehascaptains, gamehasmap, votecaptaintime, " .
                       "votemaptime, mutualvotecaptain, mutualvotemap, printpoolafterpick, " .
                       "givegameserverinfo, givevoiceserverinfo, showinfointopic, " .
                       "topicdelimiter, remindtovote, websiteurl, locale";
            $self->sayc($outline);
            
            return;
        }
        
        if ($#commands == 1) {
            if    ($commands[1] eq 'team1')                { $outline = "$commands[1] = $team1"; }
            elsif ($commands[1] eq 'team2')                { $outline = "$commands[1] = $team2"; }
            elsif ($commands[1] eq 'draw')                 { $outline = "$commands[1] = $draw"; }
            elsif ($commands[1] eq 'maxplayers')           { $outline = "$commands[1] = $maxplayers"; }
            elsif ($commands[1] eq 'gameserverip')         { $outline = "$commands[1] = $gameserverip"; }
            elsif ($commands[1] eq 'gameserverpw')         { $outline = "$commands[1] = $gameserverpw"; }
            elsif ($commands[1] eq 'gameserverport')       { $outline = "$commands[1] = $gameserverport"; }
            elsif ($commands[1] eq 'voiceserverip')        { $outline = "$commands[1] = $voiceserverip"; }
            elsif ($commands[1] eq 'voiceserverpw')        { $outline = "$commands[1] = $voiceserverpw"; }
            elsif ($commands[1] eq 'voiceserverport')      { $outline = "$commands[1] = $voiceserverport"; }
            elsif ($commands[1] eq 'neededvotes_captain')  { $outline = "$commands[1] = $neededvotes_captain"; }
            elsif ($commands[1] eq 'neededvotes_map')      { $outline = "$commands[1] = $neededvotes_map"; }
            elsif ($commands[1] eq 'neededreq_replace')    { $outline = "$commands[1] = $neededreq_replace"; }
            elsif ($commands[1] eq 'neededreq_remove')     { $outline = "$commands[1] = $neededreq_remove"; }
            elsif ($commands[1] eq 'neededreq_score')      { $outline = "$commands[1] = $neededreq_score"; }
            elsif ($commands[1] eq 'neededreq_rafflecapt') { $outline = "$commands[1] = $neededreq_rafflecapt"; }
            elsif ($commands[1] eq 'neededreq_hl')         { $outline = "$commands[1] = $neededreq_hl"; }
            elsif ($commands[1] eq 'initialpoints')        { $outline = "$commands[1] = $initialpoints"; }
            elsif ($commands[1] eq 'pointsonwin')          { $outline = "$commands[1] = $pointsonwin"; }
            elsif ($commands[1] eq 'pointsonloss')         { $outline = "$commands[1] = $pointsonloss"; }
            elsif ($commands[1] eq 'pointsondraw')         { $outline = "$commands[1] = $pointsondraw"; }
            elsif ($commands[1] eq 'p_scale_factor')       { $outline = "$commands[1] = $p_scale_factor"; }
            elsif ($commands[1] eq 'p_scale_factor_draw')  { $outline = "$commands[1] = $p_scale_factor_draw"; }
            elsif ($commands[1] eq 'p_max_variance')       { $outline = "$commands[1] = $p_max_variance"; }
            elsif ($commands[1] eq 'topdefaultlength')     { $outline = "$commands[1] = $topdefaultlength"; }
            elsif ($commands[1] eq 'gamehascaptains')      { $outline = "$commands[1] = $gamehascaptains"; }
            elsif ($commands[1] eq 'gamehasmap')           { $outline = "$commands[1] = $gamehasmap"; }
            elsif ($commands[1] eq 'votecaptaintime')      { $outline = "$commands[1] = $votecaptaintime"; }
            elsif ($commands[1] eq 'votemaptime')          { $outline = "$commands[1] = $votemaptime"; }
            elsif ($commands[1] eq 'mutualvotecaptain')    { $outline = "$commands[1] = $mutualvotecaptain"; }
            elsif ($commands[1] eq 'mutualvotemap')        { $outline = "$commands[1] = $mutualvotemap"; }
            elsif ($commands[1] eq 'printpoolafterpick')   { $outline = "$commands[1] = $printpoolafterpick"; }
            elsif ($commands[1] eq 'givegameserverinfo')   { $outline = "$commands[1] = $givegameserverinfo"; }
            elsif ($commands[1] eq 'givevoiceserverinfo')  { $outline = "$commands[1] = $givevoiceserverinfo"; }
            elsif ($commands[1] eq 'showinfointopic')      { $outline = "$commands[1] = $showinfointopic"; }
            elsif ($commands[1] eq 'topicdelimiter')       { $outline = "$commands[1] = $topicdelimiter"; }
            elsif ($commands[1] eq 'remindtovote')         { $outline = "$commands[1] = $remindtovote"; }
            elsif ($commands[1] eq 'websiteurl')           { $outline = "$commands[1] = $websiteurl"; }
            elsif ($commands[1] eq 'locale')               { $outline = "$commands[1] = $locale"; }
            else {
                $self->sayc(__x("Invalid variable name."));
                return;
            }
            
            $self->sayc($outline);
            return;
        }
        
        my $validvalue = 1;
        
        # Concatenate commands[2 .. n] into one string
        # (to be able to have whitespace in $team1 etc)
        my @cmdarr;
        for my $i (2 .. $#commands) {
            push @cmdarr, $commands[$i];
        }
        my $cmdstring = join ' ', @cmdarr;
        
        if    ($commands[1] eq 'team1')          { $team1 = $cmdstring; }
        elsif ($commands[1] eq 'team2')          { $team2 = $cmdstring; }
        elsif ($commands[1] eq 'draw')           { $draw = $cmdstring;}
        elsif ($commands[1] eq 'gameserverip')   { $gameserverip = $commands[2]; }
        elsif ($commands[1] eq 'gameserverpw')   { $gameserverpw = $commands[2]; }
        elsif ($commands[1] eq 'voiceserverip')  { $voiceserverip = $commands[2]; }
        elsif ($commands[1] eq 'voiceserverpw')  { $voiceserverpw = $commands[2]; }
        elsif ($commands[1] eq 'topicdelimiter') { $topicdelimiter = $cmdstring; }
        elsif ($commands[1] eq 'websiteurl')     { $websiteurl = $cmdstring; }
        elsif ($commands[1] eq 'locale')         { set_locale($commands[2]); }
        
        elsif ($commands[1] eq 'maxplayers') {
            if ( containsletters($commands[2]) || $commands[2] < 0  || ($commands[2] % 2) != 0 ) {
                $validvalue = 0;
            } else { resetmaxplayers($commands[2]); }
        }
        
        elsif ($commands[1] eq 'gameserverport') {
            if ( containsletters($commands[2]) ) {
                $validvalue = 0;
            } else { $gameserverport = $commands[2]; }
        }
        elsif ($commands[1] eq 'voiceserverport') {
            if ( containsletters($commands[2]) ) {
                $validvalue = 0;
            } else { $voiceserverport = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'neededvotes_captain') {
            if ( containsletters($commands[2]) || $commands[2] < 0  ) {
                $validvalue = 0;
                
            } else { $neededvotes_captain = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'neededvotes_map') {
            if ( containsletters($commands[2]) || $commands[2] < 0  ) {
                $validvalue = 0;
                
            } else { $neededvotes_map = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'neededreq_replace') {
            if ( containsletters($commands[2]) || $commands[2] < 0  ) {
                $validvalue = 0;
                
            } else { $neededreq_replace = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'neededreq_remove') {
            if ( containsletters($commands[2]) || $commands[2] < 0  ) {
                $validvalue = 0;
                
            } else { $neededreq_remove = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'neededreq_score') {
            if ( containsletters($commands[2]) || $commands[2] < 0  ) {
                $validvalue = 0;
                
            } else { $neededreq_score = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'neededreq_rafflecapt') {
            if ( containsletters($commands[2]) || $commands[2] < 0  ) {
                $validvalue = 0;
                
            } else { $neededreq_rafflecapt = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'neededreq_hl') {
            if ( containsletters($commands[2]) || $commands[2] < 0  ) {
                $validvalue = 0;
                
            } else { $neededreq_hl = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'initialpoints') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $initialpoints = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'pointsonwin') {
            if ( containsletters($commands[2])) {
                $validvalue = 0;
            } else { $pointsonwin = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'pointsonloss') {
            if ( containsletters($commands[2])) {
                $validvalue = 0;
            } else { $pointsonloss = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'pointsondraw') {
            if ( containsletters($commands[2])) {
                $validvalue = 0;
            } else { $pointsondraw = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'p_scale_factor') {
            if ( containsletters($commands[2])) {
                $validvalue = 0;
            } else { $p_scale_factor = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'p_scale_factor_draw') {
            if ( containsletters($commands[2])) {
                $validvalue = 0;
            } else { $p_scale_factor_draw = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'p_max_variance') {
            if ( containsletters($commands[2])) {
                $validvalue = 0;
            } else { $p_max_variance = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'topdefaultlength') {
            if ( containsletters($commands[2]) || $commands[2] < 1 ) {
                $validvalue = 0;
            } else { $topdefaultlength = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'gamehascaptains') {
            if ( containsletters($commands[2]) || $commands[2] < 0) {
                $validvalue = 0;
            } else { $gamehascaptains = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'gamehasmap') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $gamehasmap = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'votecaptaintime') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $votecaptaintime = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'votemaptime') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $votemaptime = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'mutualvotecaptain') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $mutualvotecaptain = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'mutualvotemap') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $mutualvotemap = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'printpoolafterpick') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $printpoolafterpick = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'givegameserverinfo') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $givegameserverinfo = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'givevoiceserverinfo') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $givevoiceserverinfo = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'showinfointopic') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $showinfointopic = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'remindtovote') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $remindtovote = $commands[2]; }
        }
        
        else {
            $self->sayc(__x("Invalid variable name."));
            return;
        }
        
        
        if ($validvalue == 1) {
            $self->sayc(__x("Variable {var} is now set to {val}.",
                            var => $commands[1], val => $commands[2]));
        } else {
            $self->sayc(__x("Invalid value given for variable {var}.",
                            var => $commands[1]));
        }
        
        return;
    }
    
    
    # command .aoe
    elsif ($commands[0] eq '.aoe') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who));
            return;
        }
        
        $self->say(channel => "msg", who => "Q", body => "CHANMODE $chan -N");
        
        my $playercount = $#players+1;
        my $notice = __x("{chan} - sign up for gather is on! " .
                         "{pcount}/{pmax} players have signed up.",
                         chan => $chan, pcount => $playercount, pmax => $maxplayers);
        
        my $chandata = $self->channel_data($chan);
        foreach my $nick_ (keys %$chandata) {
            $self->notice(channel => "msg", who => $nick_, body => $notice);
        }
        
        $self->say(channel => "msg", who => "Q", body => "CHANMODE $chan +N");
        
        return;
    }
    
    
    # command .hilight
    elsif ($commands[0] eq '.hilight' || $commands[0] eq '.hl') {
    
        # command was just ".hl"
        if ($#commands == 0) {
            if ($accesslevel ne 'admin') {
            
                # Check that the requester has signed
                if (issigned($who) == 0) {
                    $self->sayc(__x("{who} has not signed up.",
                                    who => $who));
                    return;
                }
            
                my @requesters = split ',', $hl_requests;
                
                # Find out if already requested
                my $alreadyrequested = 0;
                for my $nick (@requesters) {
                    if ($nick eq $who) {
                        $alreadyrequested = 1;
                        last;
                    }
                }
                
                # If already requested
                if ($alreadyrequested == 1) {
                    $self->sayc(__x("{who} has already requested highlight.",
                                    who => $who));
                    return;
                    
                # Else, add into @requesters
                } else {
                    push @requesters, $who;
                }
                
                # Save the requests
                $hl_requests = join ',', @requesters;
                
                # Put requesters in a nice string
                # and count their amount
                my $requestersline = join ', ', @requesters;
                my $requesterscount = $#requesters + 1;
                
                # Make and give the output
                my $outline = __x("Highlight have requested: " .
                                  "{requesters} [{requestersc}/{neededreq}]",
                                  requesters => $requestersline,
                                  requestersc => $requesterscount,
                                  neededreq => $neededreq_hl);
                                  
                $self->sayc($outline);
                
                # If not enough requesters yet, return
                if ($requesterscount < $neededreq_hl) {
                    return;
                }
            }
            
            # HL going to happen, reset requests
            $hl_requests = "";
                
            my $chandata = $self->channel_data($chan);
            my @nicks;
            
            foreach my $nick_ (keys %$chandata) {
                my $isignored = 0;
                
                for my $ignorednick (@hlignorelist) {
                    if ($ignorednick eq $nick_) {
                        $isignored = 1;
                    }
                }
                
                # Don't hilight signed players
                if (issigned($nick_) == 1) {
                    $isignored = 1;
                }
                
                # Don't hilight the bot either
                if ($nick_ eq $nick) {
                    $isignored = 1;
                }
                
                if ($isignored == 0) {
                    push @nicks, $nick_;
                }
            }
            
            my $hilightline = join ' ', @nicks;
            $self->sayc($hilightline);
            
            return;
        }
        
        # - More parameters were given -
        
        if ($commands[1] ne 'off' && $commands[1] ne 'on') {
            $self->sayc(__x("Syntax is {command} <off|on>",
                            command => $commands[0]));
            return;
        }
        
        if ($commands[1] eq 'off') {
            my $isignored = 0;
            
            for my $i (0 .. $#hlignorelist) {
                if ($hlignorelist[$i] eq $who) {
                    $isignored = 1;
                }
            }
            
            if ($isignored == 1) {
                $self->sayc(__x("{who} was already in hilight-ignore.",
                                who => $who));
            } else {
                push @hlignorelist, $who;
                $self->sayc(__x("{who} is now in hilight-ignore.",
                                who => $who));
            }
            
            return;
        }
        
        if ($commands[1] eq 'on') {
            my $wasignored = 0;
            
            for my $i (0 .. $#hlignorelist) {
                if ($hlignorelist[$i] eq $who) {
                    splice(@hlignorelist, $i, 1);
                    $wasignored = 1;
                    last;
                }
            }
            
            if ($wasignored == 0) {
                $self->sayc(__x("{who} was not in hilight-ignore.",
                                who => $who));
            
            } else {
                $self->sayc(__x("{who} is no longer in hilight-ignore.",
                                who => $who));
            }
            
            return;
        }
        
        return;
    }
    
    
    # command .captains
    elsif ($commands[0] eq '.captains') {
    
        if ($gamehascaptains == 0) {
            $self->sayc(__x("Command {command} is not enabled (gamehascaptains = 0)",
                            command => $commands[0]));
            return;
        }
        
        my @captains;
        
        if ($captain1 ne '') {
            push @captains, $captain1;
        }
        
        if ($captain2 ne '') {
            push @captains, $captain2;
        }
        
        if ($#captains == -1) {
            $self->sayc(__x("There are no captains currently."));
            return;
        }
        
        my $captainsstr = join ', ', @captains;
        
        $self->sayc(__x("The captains are: {captains}",
                        captais => $captainsstr));
        
        return;
    }
    
    
    # command .teams
    elsif ($commands[0] eq '.teams') {
    
        if ($#team1 == -1 && $#team2 == -1) {
            $self->sayc(__x("The teams are empty."));
            return;
        }
    
        # Get formatted list and skills
        my $t1_list = $self->formatteam(@team1);
        my $t2_list = $self->formatteam(@team2);
        my $t1_skill = get_team_skill(@team1);
        my $t2_skill = get_team_skill(@team2);
        
        # Output
        $self->sayc("$team1 ($t1_skill): $t1_list");
        $self->sayc("$team2 ($t2_skill): $t2_list");
    
        return;
    }
    
    
    # command .turn
    elsif ($commands[0] eq '.turn') {
    
        if ($gamehascaptains == 0) {
            $self->sayc(__x("Command {command} is not enabled (gamehascaptains = 0)",
                            command => $commands[0]));
            return;
        }
        
        if ($canpick == 0) {
            $self->sayc(__x("Player picking has not started yet."));
            return;
        }
        
        my $picker = "";
        
        if ($turn == 1) {
            $picker = $captain1;
        } else {
            $picker = $captain2;
        }
        
        $self->sayc(__x(" {next}'s turn to pick.",
                        next => $picker));
        
        return;
    }
    
    
    # command .hasauth (debugging cmd)
    elsif ($commands[0] eq '.hasauth') {
        
        if ($#commands < 1) {
            $self->sayc(__x("Syntax is {command} <playername>",
                            command => $commands[0]));
            return;
        }
        
        my $username = $commands[1];
        
        if (! exists $qauths{$username}) {
            $self->sayc(__x("No Q-auth info for user {who}",
                            who => $username));
        } else {
            $self->sayc(__x("{who} is authed to Q on account {acc}",
                            who => $username, acc => $qauths{$username}));
        }
        
        return;
    }
    
    # command .lookupauth (debugging cmd)
    elsif ($commands[0] eq '.lookupauth') {
    
        if ($#commands < 1) {
            $self->sayc(__x("Syntax is {command} <playername>",
                            command => $commands[0]));
            return;
        }
        
        $self->whoisuser_to_q($commands[1]);
        
        return;
    }
    
    
    # command .senddata
    elsif ($commands[0] eq '.senddata') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who));
            return;
        }
        
        if ($#commands == 1) {
            if ($commands[1] ne 'all') {
                $self->sayc(__x("Wrong syntax."));
                return;
            }
            
            %player_pks      = ();
            %game_player_pks = ();
            %map_pks         = ();
            $lastsentgame    = 0;
        }
        
        $self->senddata();
        
        return;
    }
    
    
    # command .recalcpoints
    elsif ($commands[0] eq '.recalcpoints') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who));
            return;
        }
        
        $self->recalcpoints();
        
        return;
    }
    
    
    # command .savedata
    elsif ($commands[0] eq '.savedata') {
    
        if ($accesslevel ne 'admin') {
            $self->sayc(__x("{who} is not an admin.",
                            who => $who));
            return;
        }
        
        save();
        $self->sayc(__x("Data saved."));
        
        return;
    }
    
    
    # command .printcolors
    elsif ($commands[0] eq '.printcolors') {
    
        $self->printcolors();
        
        return;
    }
    
    
    # command .foo
    elsif ($commands[0] eq '.foo') {
        return;
    }
    
    
}

# This subr is called when
# someone parts from the channel
sub chanpart {
    my $self = shift;
    my $message = shift;
    my $who = $message->{who};
    my $channel = $message->{channel};
    
    # Check if the part happened in $chan
    if ($channel ne $chan) {
        return;
    }
    
    # If the player is signed, remove him
    $self->outplayer($who);
    
    return;
}

# This subr is called when
# someone quits from irc
sub userquit {
    my $self = shift;
    my $message = shift;
    my $who = $message->{who};
    
    # If the player is signed, remove him
    $self->outplayer($who);
    
    return;
}

# Removes the given player from the sign-up
sub outplayer {
    my $self = shift;
    my $tbremoved = $_[0];
    
    # Get the player's index in @players
    my $indexofplayer = -1;
    for my $i (0 .. $#players) {
        if ($players[$i] eq $tbremoved) {
            $indexofplayer = $i;
            last;
        }
    }
    
    if ($indexofplayer == -1) {
        return;
    }
    
    # Remove the player
    splice(@players, $indexofplayer, 1);
    
    # Remove player's votes and requests
    $self->voidusersvotes($tbremoved);
    $self->voidusersrequests($tbremoved);
    
    # Give output
    my $playercount = $#players+1;
    $self->sayc(__x("{who} signed out. {pcount}/{pmax} have signed up.",
                    who => $tbremoved,
                    pcount => $playercount, pmax => $maxplayers));
    
    # If playerlist became empty
    if ($playercount == 0) {
    
        # Clear all votes and requests
        $self->voidvotes();
        $self->voidrequests();
        $canvotemap = 0;
        $canvotecaptain = 0;
    }
    
    $self->updatetopic();
}


# This subr is used when a match starts.
#
# We use tick because its execution can be scheduled without
# blocking the bot from reacting to messages, which is
# necessary for implementing timeout for votings.
#
sub tick {
    my $self = shift;
    
    # A dirty way to end this subr when it's
    # called automatically 5 secs after init
    if ($canadd == 1) {
        return 0;
    }
    
    if ($gamehasmap == 1 && $chosenmap eq '') {
        if ($votemaptime > 0 || $mutualvotemap == 0) {
        
            $canvotemap = 0;
            my $outline = __x("Map voting has ended.");
            
            my $mostvoted = "";
            my $mostvotes = 0;
            
            if ($mapvotecount >= $neededvotes_map) {
                foreach (keys %mapvotes) {
                    if ($mapvotes{$_} > $mostvotes) {
                        $mostvoted = $_;
                        $mostvotes = $mapvotes{$_};
                    }
                }
                $chosenmap = $mostvoted;
                
                $outline .= __x(" The winner of votemap is {map}.",
                                map => $chosenmap);
                                
                $self->sayc($outline);
                
            } else {
                if ($outline ne '') {
                    $self->sayc($outline);
                }
                
                $self->sayc(__x("Received less than {neededvotes} votes. " .
                                "The map will be selected randomly.",
                                neededvotes => $neededvotes_map));
            }
        }
        
        if ($chosenmap eq '') {
            $self->rafflemap();
        }
    }
    
    if ($votecaptaindone == 0) {
        
        # Disable the command .captain now
        $cancaptain = 0;
        
        my $waittime = 1;
        
        # Decide whether we are going to vote captains
        if ($gamehascaptains == 1 && $votecaptaintime > 0 && $captain2 eq '') {
        
            if ($captain1 eq '' && $captain2 eq '') {
                $self->sayc(__x("Voting of captains is about to begin. " .
                                "Vote with command .votecaptain <playername>"));
            }
            
            if ($captain1 ne '') {
                $self->sayc(__x("The other captain is {capt}. Voting " .
                                "of the other captain is about to begin.",
                                capt => $captain1));
                
                $self->sayc(__x("Vote with command .votecaptain <playername>"));
            }
            
            my @votableplayers;
            my @userdata;
            my $points;
            
            for my $i (0 .. $#players) {
                # If not a captain
                if ($players[$i] ne $captain1) {
                
                    # Get user's points
                    @userdata = split '\.', $users{$players[$i]};
                    $points = $userdata[1];
                    
                    # If points are sufficient
                    if ($points > $initialpoints) {
                        push @votableplayers, $players[$i];
                    }
                }
            }
            
            my $players = join ' ', @votableplayers;
            $self->sayc(__x("Votable players are: {players}",
                            players => $players));
                            
            $self->sayc(__x("Voting ends in {secs} seconds!",
                            secs => $votecaptaintime));
            
            $canvotecaptain = 1;
            $waittime =  $votecaptaintime;
        }
        
        $votecaptaindone = 1;
        
        # Calls tick again after $waittime seconds
        return $waittime;
    }
    
    $votecaptaindone = 0;
    
    if ($gamehascaptains == 0) {
        $self->raffleteams();
        $self->startgame();
        return 0;
    }
    
    if ($votecaptaintime > 0 || $mutualvotecaptain == 0) {
        if ($captain1 eq '' || $captain2 eq '') {
            $canvotecaptain = 0;
            
            if ($captain1 eq '' && $captain2 eq '') {
                $self->sayc(__x("Voting of captains has ended."));
            } else {
                $self->sayc(__x("Voting of a captain has ended."));
            }
        
            if ($captainvotecount >= $neededvotes_captain) {
                my $mostvoted = "";
                my $mostvotes = 0;
                
                # If we voted for 2 captains
                if ($captain1 eq '') {
                    foreach (keys %captainvotes) {
                        if ($captainvotes{$_} > $mostvotes) {
                            $mostvoted = $_;
                            $mostvotes = $captainvotes{$_};
                        }
                    }
                    $captain1 = $mostvoted;
                    
                    delete($captainvotes{$captain1});
                }
                
                $mostvoted = "";
                $mostvotes = 0;
                
                foreach (keys %captainvotes) {
                    if ($captainvotes{$_} > $mostvotes) {
                        $mostvoted = $_;
                        $mostvotes = $captainvotes{$_};
                    }
                }
                $captain2 = $mostvoted;
                
                # If the voting was totally one sided
                if ($captain2 eq '') {
                    $self->sayc(__x("Voting was one-sided; The second " .
                                    "captain will be randomly selected."));
                }
                
            } else {
                my $string = "";
                if ($captain1 eq '' && $captain2 eq '') {
                    $string = __x("The captains");
                } else {
                    $string = __x("The other captain");
                }
                $self->sayc(__x("Received less than {neededvotes} votes. " .
                                "{str} will be selected randomly.",
                                neededvotes => $neededvotes_captain,
                                str => $string));
            }
        }
    }
    
    $self->determinecaptains();
    $self->startpicking();
    
    return 0;
}

sub resetuserdata {
    my @userdata;

    foreach (keys %users) {
        @userdata = split '\.', $users{$_};
        
        $userdata[1] = $initialpoints;
        $userdata[2] = 0;
        $userdata[3] = 0;
        $userdata[4] = 0;
    
        $users{$_} = join '.', @userdata;
    }
    
    return;
}

sub recalcpoints {
    my $self = shift;
    
    # Reset userdata
    resetuserdata();
    
    my @plist;
    my @gamedata;
    my @gendata;
    my @resultdata;
    my @t1_players;
    my @t2_players;
    my $gameno;
    my $gamestatus;
    my $result;
    my $t1_skill;
    my $t2_skill;
    my $wasmaxplayers;
    my $wasteamsize;
    my $outline;
    
    for my $i ( 1 .. $gamenum ) {
        if (exists $games{$i})
        {
        
        @gamedata = split ',', $games{$i};
        
        # Get gameno and status
        @gendata = split ':', $gamedata[0];
        $gameno = $gendata[0];
        $gamestatus = $gendata[1];
        
        if ($gamestatus eq 'closed')
        {
        
        # Get the players who played in this game
        @plist = get_players_by_gameno($gameno);
        
        # Make sure every player is in userdata
        # (because we just reseted all userdata)
        for my $name (@plist) {
            if (! exists $users{$name}) {
                $users{$name} = "user.$initialpoints.0.0.0";
            }
        }

        # Separate the teams from the player list
        @t1_players = team1_from_plist(@plist);
        @t2_players = team2_from_plist(@plist);
        
        # Get teams' players
        my $team1list = $self->format_plist(@t1_players);
        my $team2list = $self->format_plist(@t2_players);
        
        # Retrieve teams' skills and add to gamedata
        $t1_skill = get_team_skill(@t1_players);
        $t2_skill = get_team_skill(@t2_players);
        $gamedata[4] = "$t1_skill:$t2_skill";
        
        # Find out maxplayers and teamsize
        $wasmaxplayers = $#plist + 1;
        $wasteamsize = $wasmaxplayers / 2;
        
        # Get the game result
        @resultdata = split ':', $gamedata[3];
        $result = $resultdata[1];
        
        my $player;
        my $p_delta;
        my @pdata;
        my @pdeltas_out;
        
        for my $i (0 .. $#plist) {
        
            $player = $plist[$i];
            @pdata = split '\.', $users{$player};
        
            if ($result == 1) {
            
                if ($i >= 0 && $i < $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t2_skill, 'WIN');
                    $pdata[2]++;
                }
            
                if ($i >= $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t1_skill, 'LOSS');
                    $pdata[3]++;
                }
                
            } elsif ($result == 2) {
            
                if ($i >= 0 && $i < $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t2_skill, 'LOSS');
                    $pdata[3]++;
                }
            
                if ($i >= $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t1_skill, 'WIN');
                    $pdata[2]++;
                }
            
            } elsif ($result == 3) {
            
                if ($i >= 0 && $i < $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t2_skill, 'DRAW');
                    $pdata[4]++;
                }
            
                if ($i >= $wasteamsize) {
                    $p_delta = calc_pointsdelta($pdata[1], $t1_skill, 'DRAW');
                    $pdata[4]++;
                }
            }
            
            # This will go to gamedata
            $plist[$i] .= "($pdata[1]:$p_delta)";
            
            # Update to userdata
            $pdata[1] += $p_delta;
            $users{$player} = join '.', @pdata;
            
            # This will go to output
            if    ($p_delta > 0)  { $p_delta = "\x0309" . "+$p_delta\x0f"; }
            elsif ($p_delta == 0) { $p_delta = "\x0312" . "$p_delta\x0f"; }
            else                  { $p_delta = "\x0304" . "$p_delta\x0f"; }
            push @pdeltas_out, "$player($p_delta)";
        }
        
        $gamedata[5] = join ',', @plist;
        $#gamedata = 5;
        
        # Save gamedata
        $games{$gameno} = join ',', @gamedata;
        
#         if ($gamenum - $gameno <= 0) {
#         # if ($gameno == -1) {
#             # Give output about the game result
#             $gameno = "\x0300" . "#$gameno\x0f";
#             
#             $self->emote(channel => $chan,
#                          body => "Peli $gameno on päättynyt:");
#             
#             $t1_skill = "\x0300" . "$t1_skill\x0f";
#             $self->emote(channel => $chan,
#                          body => "$team1 ($t1_skill): $team1list");
#                         
#             $t2_skill = "\x0300" . "$t2_skill\x0f";
#             $self->emote(channel => $chan,
#                          body => "$team2 ($t2_skill): $team2list");
#             
#             $outline = "Tulos: ";
#             $outline .= "\x0300";
#             if ($result == 1) { $outline .= "$team1 voitti"; }
#             if ($result == 2) { $outline .= "$team2 voitti"; }
#             if ($result == 3) { $outline .= "$draw"; }
#             $outline .= "\x0f";
#             
#             $self->emote(channel => $chan, body => $outline);
#             
#             # Give output about changes in points
#             $outline = join ', ', @pdeltas_out;
#             $self->emote(channel => $chan,
#                          body => "Pistemuutokset: $outline");
#             
#             $self->emote(channel => $chan,
#                          body => "---------------------------------" .
#                                  "---------------------------------" .
#                                  "---------------------------------");
#         } # if gameno
        
        
        } # if closed
        } # if exists
        
    } # for
    
    $self->sayc(__x("Points have been recalculated."));

    return;
}

sub resetmaxplayers {
    $maxplayers = $_[0];
    
    setneededvotes_captain($maxplayers/2);
    setneededvotes_map($maxplayers/2);
    setneededreq_replace($maxplayers/2);
    setneededreq_remove($maxplayers/2);
    setneededreq_score($maxplayers/2);
    setneededreq_rafflecapt($maxplayers/2);
    setneededreq_hl($maxplayers/2);
    
    return;
}

sub setneededvotes_captain {
    my $arg = $_[0];
    
    if ($arg > 0) {
        $neededvotes_captain = $arg;
    } else {
        $neededvotes_captain = $maxplayers / 2;
    }
    
    return;
}

sub setneededvotes_map {
    my $arg = $_[0];
    
    if ($arg > 0) {
        $neededvotes_map = $arg;
    } else {
        $neededvotes_map = $maxplayers / 2;
    }
    
    return;
}

sub setneededreq_replace {
    my $arg = $_[0];
    
    if ($arg > 0) {
        $neededreq_replace = $arg;
    } else {
        $neededreq_replace = $maxplayers / 2;
    }
    
    return;
}

sub setneededreq_remove {
    my $arg = $_[0];
    
    if ($arg > 0) {
        $neededreq_remove = $arg;
    } else {
        $neededreq_remove = $maxplayers / 2;
    }
    
    return;
}

sub setneededreq_score {
    my $arg = $_[0];
    
    if ($arg > 0) {
        $neededreq_score = $arg;
    } else {
        $neededreq_score = $maxplayers / 2;
    }
    
    return;
}

sub setneededreq_rafflecapt {
    my $arg = $_[0];
    
    if ($arg > 0) {
        $neededreq_rafflecapt = $arg;
    } else {
        $neededreq_rafflecapt = $maxplayers / 2;
    }
    
    return;
}

sub setneededreq_hl {
    my $arg = $_[0];
    
    if ($arg > 0) {
        $neededreq_hl = $arg;
    } else {
        $neededreq_hl = $maxplayers / 2;
    }
    
    return;
}

sub voidvotes {
    # Void all mapvotes
    foreach (keys %mapvotes) {
        $mapvotes{$_} = 0;
    }
    for my $map (@maps) {
        $mapvotes{$map} = 0;
    }
    foreach (keys %mapvoters) {
        $mapvoters{$_} = "";
    }
    $mapvotecount = 0;
    
    # Void all captainvotes
    foreach (keys %captainvotes) {
        $captainvotes{$_} = 0;
    }
    for my $player (@players) {
        $captainvotes{$player} = 0;
    }
    foreach (keys %captainvoters) {
        $captainvoters{$_} = "";
    }
    $captainvotecount = 0;
    
    return;
}

sub voidusersvotes {
    my $self = shift;
    my $username = $_[0];
    
    # Void user's mapvote
    if ( exists($mapvoters{$username}) && exists($mapvotes{$mapvoters{$username}}) ) {
        if ($mapvotes{$mapvoters{$username}} > 0) {
            $mapvotes{$mapvoters{$username}} -= 1;
            $mapvotecount--;
        }
    }
    $mapvoters{$username} = "";
    
    # Void user's captainvote
    if ( exists($captainvoters{$username}) && exists($captainvotes{$captainvoters{$username}}) ) {
        if ($captainvotes{$captainvoters{$username}} > 0) {
            $captainvotes{$captainvoters{$username}} -= 1;
            $captainvotecount--;
        }
    }
    $captainvoters{$username} = "";
    $captainvotes{$username} = 0;
}

sub voidrequests {
    # Void replace requests
    foreach (keys %replacereq) {
        $replacereq{$_} = "";
    }
    
    # Void remove requests
    foreach (keys %removereq) {
        $removereq{$_} = "";
    }
    
    # Void rafflecaptain requests
    $capt1rafflerequests = "";
    $capt2rafflerequests = "";
    
    return;
}

sub voidusersrequests {
    my $self = shift;
    my $username = $_[0];
    
    my @requests; my @requesters; my @replacements;
    my @newrequesters; my @newreplacements;
    my @temp;
    
    # Void all replace requests that relate to the given user
    $replacereq{$username} = "";
    foreach (keys %replacereq) {
        @requests=();
        @requesters=();
        @replacements=();
        @newrequesters=();
        @newreplacements=();
        @temp=();
    
        if (index($replacereq{$_}, $username) != -1) {
            @requests = split(',', $replacereq{$_});
            
            for my $i (0 .. $#requests) {
                @temp = split(':', $requests[$i]);
                push(@requesters, $temp[0]);
                push(@replacements, $temp[1]);
            }
            
            for my $i (0 .. $#requesters) {
                if ($requesters[$i] ne $username && $replacements[$i] ne $username) {
                    push(@newrequesters, $requesters[$i]);
                    push(@newreplacements, $replacements[$i]);
                }
            }
            
            @temp=();
            
            for my $i (0 .. $#newrequesters) {
                push(@temp, "$newrequesters[$i]:$newreplacements[$i]");
            }
            
            $replacereq{$_} = join(',', @temp);
        }
    }
    
   
    # Void all remove requests that relate to the given user
    $removereq{$username} = "";
    foreach (keys %removereq) {
        @requesters=();
        @newrequesters=();
        
        if (index($removereq{$_}, $username) != -1) {
            @requesters = split(',', $removereq{$_});
            
            for my $i (0 .. $#requesters) {
                if ($requesters[$i] ne $username) {
                    push(@newrequesters, $requesters[$i]);
                }
            }
            
            $removereq{$_} = join(',', @newrequesters);
        }
    }
    
    # If user had a HL request, void it
    @requesters = split ',', $hl_requests;
    
    for my $i (0 .. $#requesters) {
        if ($requesters[$i] eq $username) {
            splice(@requesters, $i, 1);
            last;
        }
    }

    return;
}

sub rafflemap {
    my $self = shift;

    my $mapcount = $#maps + 1;
    my $randindex = int(rand($mapcount));
    $chosenmap = $maps[$randindex];
    
    return;
}

sub determinecaptains {
    my $self = shift;
    
    # According to a random number,
    # maybe swap captains with each other
    if (int(rand(10) < 5)) {
        my $temp = $captain1;
        $captain1 = $captain2;
        $captain2 = $temp;
    }
    
    my $playercount;
    my $randindex;
    
    # Raffle the first captain, if needed
    if ($captain1 eq "") {
        $playercount = $#players + 1;
        
        # Check that there is at least 
        # one valid captain in the pool
        my @userdata;
        my $points = 0;
        my $exists_valid_captain = 0;
        
        for my $player (@players) {
            @userdata = split '\.', $users{$player};
            $points = $userdata[1];
            if ($points > $initialpoints) {
                $exists_valid_captain = 1;
                last;
            }
        }
        
        # If there are valid captains
        if ($exists_valid_captain == 1) {
        
            # Get user's points and check that they are 
            # sufficient. If not, raffle a new captain.
            my @userdata;
            my $points = 0;
            
            while ($points <= 1000) {
                $randindex = int(rand($playercount));
                @userdata = split '\.', $users{$players[$randindex]};
                $points = $userdata[1];
            }
        
        # Otherwise, accept the first random player
        } else {
            $randindex = int(rand($playercount));
        }
        
        $captain1 = $players[$randindex];
    }
    
    # Remove captain1 from player pool
    for my $i (0 .. $#players) {
        if ($players[$i] eq $captain1) {
            splice(@players, $i, 1);
            last;
        }
    }
    # Put captain1 into his team
    push(@team1, $captain1);
    
    
    # Raffle the second captain, if needed
    if ($captain2 eq "") {
        $playercount = $#players + 1;
        
        # Check that there is at least 
        # one valid captain in the pool
        my @userdata;
        my $points = 0;
        my $exists_valid_captain = 0;
        
        for my $player (@players) {
            @userdata = split '\.', $users{$player};
            $points = $userdata[1];
            if ($points > $initialpoints) {
                $exists_valid_captain = 1;
                last;
            }
        }
        
        # If there are valid captains
        if ($exists_valid_captain == 1) {
        
            # Get user's points and check that they are 
            # sufficient. If not, raffle a new captain.
            my @userdata;
            my $points = 0;
            
            while ($points <= 1000) {
                $randindex = int(rand($playercount));
                @userdata = split '\.', $users{$players[$randindex]};
                $points = $userdata[1];
            }
        
        # Otherwise, accept the first random player
        } else {
            $randindex = int(rand($playercount));
        }
        
        $captain2 = $players[$randindex];
    }
    
    # Remove captain2 from player pool
    for my $i (0 .. $#players) {
        if ($players[$i] eq $captain2) {
            splice(@players, $i, 1);
            last;
        }
    }
    # Put captain2 into his team
    push(@team2, $captain2);
    
    # Give the output
    $self->sayc(__x("{capt1} and {capt2} are the captains.",
                    capt1 => $captain1, capt2 => $captain2));
    
    return;
}

sub changecapt1 {
    my $newcaptain = $_[0];
    
    # Remove the current captain from his team
    for my $i (0 .. $#team1) {
        if ($team1[$i] eq $captain1) {
            splice(@team1, $i, 1);
            last;
        }
    }
    
    # Remove the new captain from the player pool
    for my $i (0 .. $#players) {
        if ($players[$i] eq $newcaptain) {
            splice(@players, $i, 1);
            last;
        }
    }
    
    # Put the current captain back in the player pool
    push(@players, $captain1);
    
    # Make the newly raffled player the
    # captain and put him in his team
    $captain1 = $newcaptain;
    push(@team1, $captain1);
    
    return;
}

sub changecapt2 {
    my $newcaptain = $_[0];
     
    # Remove the current captain from his team
    for my $i (0 .. $#team2) {
        if ($team2[$i] eq $captain2) {
            splice(@team2, $i, 1);
            last;
        }
    }
    
    # Remove the new captain from the player pool
    for my $i (0 .. $#players) {
        if ($players[$i] eq $newcaptain) {
            splice(@players, $i, 1);
            last;
        }
    }
    
    # Put the current captain back in the player pool
    push(@players, $captain2);
    
    # Make the newly raffled player the
    # captain and put him in his team
    $captain2 = $newcaptain;
    push(@team2, $captain2);
    
    return;
}

sub startpicking {
    my $self = shift;
    $self->sayc(__x("The picking of players is about to start."));
    
    my $list = $self->format_plist(@players);
    $self->sayc(__x("Player pool: {list}",
                    list => $list));
    
    
    $self->sayc(__x(" {next}'s turn to pick.",
                    next => $captain2));
    
    $canpick = 1;
    $turn = 2;
    $lastturn = 2;
    
    return;
}

sub startgame {
    my $self = shift;
    
    # Increment the game number
    $gamenum++;
    
    my $gamenums = "\x02" . "#$gamenum" . "\x0f";
    $self->sayc(__x("Game {no} begins!", no => $gamenums));
    
    # Print the teams
    my $team1list = $self->formatteam(@team1);
    my $team2list = $self->formatteam(@team2);
    my $t1_skill = get_team_skill(@team1);
    my $t2_skill = get_team_skill(@team2);
    my $t1_skill_c = "\x02" . "$t1_skill\x0f";
    my $t2_skill_c = "\x02" . "$t2_skill\x0f";
    
    $self->sayc("$team1 ($t1_skill_c): $team1list");
    $self->sayc("$team2 ($t2_skill_c): $team2list");
    
    # If the game has a map, print it
    if ($gamehasmap == 1) {
        $self->sayc("Map: " . "\x02" . "$chosenmap\x0f");
    }
    
    if ($givegameserverinfo == 1) {
        $self->printserverinfo();
    }
    
    if ($givevoiceserverinfo == 1) {
        $self->printvoipinfo();
    }
    
    # Add game to the gamedata
    my $timezone = get_timezone();
    my $dt = DateTime->now(time_zone => $timezone);
    my $ept = $dt->epoch();
    
    my $gamedataline = "$gamenum:active,time:$ept,map:$chosenmap,result:,$t1_skill:$t2_skill,";
    $team1list = join ',', @team1;
    $team2list = join ',', @team2;
    $gamedataline .= $team1list . ',' . $team2list;
    
    $games{$gamenum} = $gamedataline;
    
    $captain1 = "";
    $captain2 = "";
    $chosenmap = "";
    $self->voidvotes();
    $self->voidrequests();
    
    @players=();
    @team1=();
    @team2=();
    
    $canadd = 1;
    $canout = 1;
    $cancaptain = 1;
    $canpick = 0;
    
    $self->updatetopic();
    
    return;
}

sub get_players_by_gameno {
    my $gameno = $_[0];
    
    # Get the gamedata
    my @gamedata = split ',', $games{$gameno};
    
    # Determine the index of the first player
    # in @gamedata by checking whether the
    # gamedata[4] contains team skill data
    # or not
    my @gamedata4 = split ':', $gamedata[4];
    my $i_first;
    if ($#gamedata4 > 0) {
        $i_first = 5;
    } else {
        $i_first = 4;
    }
    
    # Find out what was the maxplayers
    my $wasmaxplayers = ($#gamedata+1) - $i_first;
    
    my @players;
    my $player;
    my $left_par;
    
    for my $i ($i_first .. $#gamedata) {
        
        $player = $gamedata[$i];
        $left_par = index $player, '(';

        if ($left_par != -1) {
            $player = substr $player, 0, $left_par;
        }
        
        push @players, $player;
    }
    
    return @players;
}

sub get_points_by_gameno {
    my ($gameno, $arg) = @_;
    
    # Get the gamedata
    my @gamedata = split ',', $games{$gameno};
    
    # Determine the index of the first player in
    # @gamedata by checking whether the
    # gamedata[4] contains team skill data or not
    my @gamedata4 = split ':', $gamedata[4];
    my $i_first;
    if ($#gamedata4 > 0) {
        $i_first = 5;
    } else {
        $i_first = 4;
    }
    
    my $player;
    my $left_par;
    my $right_par;
    my $sublength;
    my $pointstr;
    my @pointdata;
    my $temp;
    my @returndata;
    
    for my $i ($i_first .. $#gamedata) {
        
        $player = $gamedata[$i];
        $left_par = index $player, '(';
        $right_par = index $player, ')';
        
        $sublength = $right_par - $left_par -1;
        
        if ($left_par != -1 && $right_par != -1) {
            # Get the "p_before:p_delta"
            $pointstr = substr $player, $left_par+1, $sublength;
            
            # Split by the colon
            @pointdata = split ':', $pointstr;
            
            # If points before was wanted
            if ($arg eq 'before') {
                $temp = $pointdata[0];
                
            # If point deltas was wanted
            } elsif ($arg eq 'delta') {
                $temp = $pointdata[1];
            }
            
            push @returndata, $temp;
        }
    }
    
    return @returndata;
}

sub team1_from_plist {
    my @plist = @_;
    my @team;
    
    my $pcount = $#plist + 1;
    my $tsize = $pcount / 2;
    
    for my $i ( 0 .. $tsize-1 ) {
        push @team, $plist[$i];
    }
    
    return @team;
}

sub team2_from_plist {
    my @plist = @_;
    my @team;
    
    my $pcount = $#plist + 1;
    my $tsize = $pcount / 2;
    
    for my $i ( $tsize .. $pcount-1 ) {
        push @team, $plist[$i];
    }
    
    return @team;
}

sub calc_pointsdelta {
    my ($p_player, $p_opp, $result) = @_;
    
    # The points difference between the
    # player and the opponent team
    my $p_diff = $p_opp - $p_player;
    
    # The amount of extra points delta
    my $p_extra = 0;
    
    # The eventual points delta
    my $p_delta = 0;
    
    if ($result eq 'WIN') {
        $p_extra = int($p_diff / $p_scale_factor);
        $p_delta = $pointsonwin + $p_extra;
        
        
        # Check that the points delta is within the allowed variance
        if ($p_delta < ($pointsonwin - $p_max_variance)) {
            $p_delta = $pointsonwin - $p_max_variance;
        }
        
        if ($p_delta > ($pointsonwin + $p_max_variance)) {
            $p_delta = $pointsonwin + $p_max_variance;
        }
        
        
    } elsif ($result eq 'LOSS') {
        $p_extra = int($p_diff / $p_scale_factor);
        $p_delta = $pointsonloss + $p_extra;
        
        
        # Check that the points delta is within the allowed variance
        if ($p_delta < ($pointsonloss - $p_max_variance)) {
            $p_delta = $pointsonloss - $p_max_variance;
        }
        
        if ($p_delta > ($pointsonloss + $p_max_variance)) {
            $p_delta = $pointsonloss + $p_max_variance;
        }
        
        
    } elsif ($result eq 'DRAW') {
        $p_extra = int($p_diff / $p_scale_factor_draw);
        $p_delta = $pointsondraw + $p_extra;
        
        
        # Check that the points delta is within the allowed variance
        if ($p_delta < ($pointsondraw - $p_max_variance)) {
            $p_delta = $pointsondraw - $p_max_variance;
        }
        
        if ($p_delta > ($pointsondraw + $p_max_variance)) {
            $p_delta = $pointsondraw + $p_max_variance;
        }
        
    }
    
    return $p_delta;
}

sub get_team_skill {
    my @arg = @_;
    
    my @team;
    for my $p (@arg) {
        push @team, $p;
    }
    
    my $p1 = "";
    my $p2 = "";
    my @p1data;
    my @p2data;
    
    # sort by points
    for my $i ( 1.. $#team ) {
        for (my $j = $i ; $j>0 ; $j--) {
        
            $p1 = $team[$j-1];
            $p2 = $team[$j];
            
            @p1data = split '\.', $users{$p1};
            @p2data = split '\.', $users{$p2};
            
            if ($p2data[1] < $p1data[1]) {
                $team[$j] = $p1;
                $team[$j-1] = $p2;
            }
        }
    }
    
    # Change these if you want to leave out
    # the worst and the best from the avg, OR
    # if you want to take median.
    my $i_first = 0;
    my $i_last = $#team;
    
    my @pdata;
    my $points = 0;
    
    for my $i ($i_first .. $i_last) {
        @pdata = split '\.', $users{$team[$i]};
        $points += $pdata[1];
    }
    
    my $avg = int($points / ($i_last - $i_first + 1));
    
    return $avg;
}


sub mode {
   my $self = shift;
   my $mode = join ' ', @_;

   $poe_kernel->post ($self->{ircnick} => mode => $mode);
}


sub format_plist {
    my $self = shift;
    my @pool = @_;
    
    my @formattedpool;
    my @userdata;
    my $append = "";
    my $playedmatches = 0;
    my $points = "";
    
    for my $player (@pool) {
        if ($player eq $captain1 || $player eq $captain2) {
            $append .= "[" . "\x0311" . "C" . "\x0f" . "]";
        }
        
        if (exists $users{$player}) {
            @userdata = split '\.', $users{$player};
            $playedmatches = $userdata[2] + $userdata[3] + $userdata[4];
            
            # If the user has less than $unrankedafter_games
            # games, append 'Rookie'
            if ($playedmatches < $unrankedafter_games) {
                $append .= "(" . "\x0315" . "Rookie" . "\x0f" . ")";
                
            # If the user has less than $rankedafter_games
            # games, append 'Unranked'
            } elsif ($playedmatches < $rankedafter_games) {
                $append .= "(" . "\x0312" . "Unranked" . "\x0f" . ")";
            
            # Otherwise, append the user's points
            } else {
                $points = get_colored_points($userdata[1]);
                $append .= "($points)";
            }
        }
        
        $player .= $append;
        push(@formattedpool, $player);
        
        # Prepare for the next round
        $append = "";
        $playedmatches = 0;
    }

    my $playerlist = join(', ', @formattedpool);

    return $playerlist;
}

sub get_colored_points {
    my $points = $_[0];
    
    if ($points < 990) {
        return "\x0304" . "$points\x0f";
        
    } elsif ($points > 1010) {
         return "\x0309" . "$points\x0f";
         
    } else {
        return "\x0308" . "$points\x0f";
    }
    
    return $points;
}

# # formatting
# BOLD        => "\x02",
# UNDERLINE   => "\x1f",
# REVERSE     => "\x16",
# ITALIC      => "\x1d",
# FIXED       => "\x11",
# BLINK       => "\x06",
# 
# # mIRC colors
# WHITE       => "\x0300",
# BLACK       => "\x0301",
# BLUE        => "\x0302",
# GREEN       => "\x0303",
# RED         => "\x0304",
# BROWN       => "\x0305",
# PURPLE      => "\x0306",
# ORANGE      => "\x0307",
# YELLOW      => "\x0308",
# LIGHT_GREEN => "\x0309",
# TEAL        => "\x0310",
# LIGHT_CYAN  => "\x0311",
# LIGHT_BLUE  => "\x0312",
# PINK        => "\x0313",
# GREY        => "\x0314",
# LIGHT_GREY  => "\x0315",
sub printcolors {
    my $self = shift;
    my $outline = "";
    
    $outline = __x("Available colors are: ");
    $outline .= "\x0300" . "White\x0f " .
                "\x0301" . "Black\x0f " .
                "\x0302" . "Blue\x0f " .
                "\x0303" . "Green\x0f " .
                "\x0304" . "Red\x0f " .
                "\x0305" . "Brown\x0f " .
                "\x0306" . "Purple\x0f " .
                "\x0307" . "Orange\x0f " .
                "\x0308" . "Yellow\x0f " .
                "\x0309" . "Light Green\x0f " .
                "\x0310" . "Teal\x0f " .
                "\x0311" . "Light Cyan\x0f " .
                "\x0312" . "Light Blue\x0f " .
                "\x0313" . "Pink\x0f " .
                "\x0314" . "Grey\x0f " .
                "\x0315" . "Light Grey\x0f ";
    
    $self->sayc($outline);
    
    return;
}

sub formatteam {
    my $self = shift;
    my @team = @_;
    
    my @formattedteam;
    for my $player (@team) {
        push(@formattedteam, $player);
    }
    
    if ($#formattedteam > -1) {
        $formattedteam[0] .= "[" . "\x0311" . "C\x0f" . "]";
    }
    
    my $teamlist = join(', ', @formattedteam);
    
    return $teamlist;
}

sub isacaptain {
    my $queried = $_[0];
    
    if ($queried eq $captain1 || $queried eq $captain2) {
        return 1;
    }
    
    return 0;
}

sub issigned {
    my $queried = $_[0];
    
    if (isontheplayerlist($queried)) {
        return 1;
    }
    
    if (isinteam1($queried)) {
        return 1;
    }
    
    if (isinteam2($queried)) {
        return 1;
    }
    
    return 0;
}

sub isontheplayerlist {
    my $queried = $_[0];
    
    for my $player (@players) {
        if ($player eq $queried) {
            return 1;
        }
    }
    
    return 0;
}
    
sub isinteam1 {
    my $queried = $_[0];
    
    for my $player (@team1) {
        if ($player eq $queried) {
            return 1;
        }
    }
    
    return 0;
}

sub isinteam2 {
    my $queried = $_[0];
    
    for my $player (@team2) {
        if ($player eq $queried) {
            return 1;
        }
    }
    
    return 0;
}

sub raffleteams {
    my $self = shift;
    
    # Raffle teams
    my $switch = 0;
    my $randindex;
    my $randplayer;
    my $playercount = $#players + 1;
    
    while ($playercount > 0) {
        $randindex = int(rand($playercount));
        $randplayer = $players[$randindex];
        splice(@players, $randindex, 1);
        
        if ($switch == 0) {
            push(@team1, $randplayer);
            $switch = 1;
            
        } elsif ($switch == 1) {
            push(@team2, $randplayer);
            $switch = 0;
        }
        $playercount--;
    }
    
    return;
}

sub containsletters {
    my $value = shift;
    
    # check if the given parameter contains any letters
    if ($value =~ /[\p{L}]+/) {  
        return 1;
    }
    
    return 0;
}

sub printserverinfo {
    my $self = shift;
    
    if ($gameserverip eq "") {
        return;
    }
    my $str1 = __x("Gameserver: ");
    my $str2 = __x("Password: ");
    
    $self->sayc("$str1 $gameserverip:$gameserverport - " .
                "$str2 $gameserverpw");
    
    return;
}

sub printvoipinfo {
    my $self = shift;
    
    if ($voiceserverip eq "") {
        return;
    }
    
    my $str1 = __x("Password: ");
    
    $self->sayc("Mumble: $voiceserverip:$voiceserverport - " .
                "$str1 $voiceserverpw");
    
    return;
}

sub whoisuser_to_q {
    my $self = shift;
    my $queried = $_[0];
    
    $self->say(
        who =>     'Q',
        channel => 'msg',
        body =>    "WHOIS $queried",
    );
}

sub check_q_msg {
    my $self = shift;
    my $body = $_[0];

    # Split the message by whitespace
    my @words = split ' ', $body;

    # If the message contains someone's qauth info
    if ($#words >= 6 &&
        $words[0] eq '-Information' &&
        $words[1] eq 'for' &&
        $words[2] eq 'user' &&
        $words[4] eq '(using' &&
        $words[5] eq 'account')
    {
        # Get the IRC nick
        my $ircnick = $words[3];
        
        # Get the Q-auth name
        my $rpar_index = index $words[6], ')';
        my $authname = substr $words[6], 0, $rpar_index;
        
        # If there's existing matching qauth info, return
        if ( exists($qauths{$ircnick}) && $qauths{$ircnick} eq $authname) {
            return;
        }
        
        # If there's existing qauth info on this nick
        # but for a different authname, announce overwrite
        if ( exists($qauths{$ircnick}) && $qauths{$ircnick} ne $authname) {
            print STDERR "going to overwrite qauth info for nick $ircnick " .
                         "(oldauth=$qauths{$ircnick} newauth=$authname)\n";
        }
        
        # If there's existing info for this authname
        # but on a different irc-nick, update
        # the info and the user's name in data
        foreach (keys %qauths) {
            if ($qauths{$_} eq $authname && $ircnick ne $_) {
            
                # Delete the existing qauth info
                delete $qauths{$_};
                
                # Copy the user's data under the
                # new name and delete the old data
                $users{$ircnick} = $users{$_};
                delete($users{$_});
                
                my $oldnick = $_;
                
                # Also change the player's name in gamedata
                foreach (keys %games) {
                    $games{$_} =~ s/$oldnick/$ircnick/g;
                }
                
                # If the player is signed up,
                # change the nick there too.
                #
                # TODO: Change the nick in votes/requests too
                #       (otherwise the user could vote twice)
                for my $i (0 .. $#players) {
                    if ($players[$i] eq $oldnick) {
                        $players[$i] = $ircnick;
                        last;
                    }
                }
                
                # Check for the rare case that
                # the user is now signed twice
                my $count = 0;
                for my $i (0 .. $#players) {
                
                    if ($players[$i] eq $ircnick) {
                        $count += 1;
                    }
                    
                    if ($count > 1) {
                        splice @players, $i, 1;
                        last;
                    }
                }
                
                # Change the name in %player_pks
                foreach (keys %player_pks) {
                    if ($_ eq $oldnick) {
                        # Save the pk
                        my $pk = $player_pks{$_};
                        
                        # Delete old key
                        delete $player_pks{$_};
                        
                        # Save the new key
                        $player_pks{$ircnick} = $pk;
                        
                        # Break the loop
                        last;
                    }
                }
                
                $self->sayc(__x("{who} was identified as user {old} via " .
                                "Q-auth; username changed to {who}",
                                who => $ircnick, old => $_));
                
                last;
            }
        }
        
        # Add (or overwrite) the qauth info
        $qauths{$ircnick} = $authname;
    }

    return;
}

# Returns an array of the number of
# games that are active
sub getactivegames {
    my @activegames;
    my $indexofcolon;

    foreach (keys %games) {
        if ( index($games{$_}, 'active') != -1) {
            $indexofcolon = index($games{$_}, ':');
            push(@activegames, '#' . substr($games{$_}, 0, $indexofcolon));
        }
    }
    
    my $outline = "";
    
    if ($#activegames > -1) {
        $outline = join(', ', @activegames);
    }
    
    return $outline;
}

sub topic {
    my $self = shift;
    my $message = shift;
    
    my $who = "";
    my $topic = "";
    
    if (defined $message->{who} ) {
        $who = $message->{who};
    }
    
    if (defined $message->{topic} ) {
        $topic = $message->{topic};
    }
    
    # If the changer was not the bot itself,
    # (or the bot just connected to the channel),
    # parse the user-set part of topic and save
    # it as the default topic
    if ($who ne $nick) {
        my @arr = split ' ', $topic;
        my @arr2;

        if ($#arr > -1) {
            for my $i (0 .. $#arr) {
                if ($arr[$i] eq $topicdelimiter) {
                    last;
                }
                
                push @arr2, $arr[$i];
            }
        }
        
        $defaulttopic = join ' ', @arr2;
        $self->updatetopic();
    }
    
    return;
}

# Updates the channel topic,
# (if showinfointopic is set to 1)
sub updatetopic {
    my $self = shift;
    
    if ($showinfointopic == 0) {
        return;
    }
    
    my $topic = $defaulttopic;
    
    $topic .= get_topicplayerstr();
    $topic .= get_topicgamesstr(); 

    my $poeself = $self->pocoirc();
    $poe_kernel->post($poeself->session_id() => topic => $chan => $topic);
    
    return;
}

# Formats the players string for topic
sub get_topicplayerstr {
    my $outline = "";
    
    if ($#players < 0) {
        return $outline;
    }
    
    $outline .= " $topicdelimiter ";
    
    my @plist;
    
    # Populate @plist
    for my $i (0 .. $#players) {
        push(@plist, $players[$i]);
        
        if ($players[$i] eq $captain1 || $players[$i] eq $captain2) {
            $plist[$i] .= "[" . "\x0311" . "C" . "\x0f" . "]";
        }
    }
    
    my $playercount_ = $#players+1;
    $playercount_ = "\x02" . "$playercount_" . "\x0f";    # make colored
    my $maxplayers_ = "\x02" . "$maxplayers" . "\x0f";    # make colored
    my $howmanysigned = "$playercount_/$maxplayers_";
    
    my $playerstr .= join ', ', @plist;
    
    my $str1 = __x("Players:");
    $outline .= "$str1 $howmanysigned ($playerstr)";
    
    return $outline;
}

# Formats the games string for topic
sub get_topicgamesstr {
    my $outline = "";
    
    my $activegames = getactivegames();
    
    if ($activegames ne '') {
        my $str1 = __x("Ongoing games:");
        $outline .= " $topicdelimiter $str1 $activegames";
    }
    
    return $outline;
}

# Writes data to files
sub writedata {
    my $self = shift;
    my $userdatafilename   = 'userdata.txt';
    my $gamedatafilename   = 'gamedata.txt';
    my $ignoredatafilename = 'ignoredata.txt';
    my $authdatafilename   = 'authdata.txt';
    
    my $userdatafile;
    my $gamedatafile;
    my $ignoredatafile;
    my $authdatafile;
    
    # Write userdata
    if (open $userdatafile, '>', $userdatafilename
            or die "error while overwriting file $userdatafilename: $!") {
            
        foreach (keys %users) {
            print $userdatafile "$_=$users{$_}\n";
        }
    }
    
    # Write gamedata
    if (open $gamedatafile, '>', $gamedatafilename
            or die "error while overwriting file $gamedatafilename: $!") {
            
        foreach (keys %games) {
            print $gamedatafile "$games{$_}\n";
        }
    }
    
    # Write ignoredata
    if (open $ignoredatafile, '>', $ignoredatafilename
            or die "error while overwriting file $ignoredatafilename: $!") {
        
        for my $name (@hlignorelist) {
            print $ignoredatafile "$name\n";
        }
    }
    
    # Write authdata
    if (open $authdatafile, '>', $authdatafilename
            or die "error while overwriting file $authdatafilename: $!") {
        
        foreach (keys %qauths) {
            print $authdatafile "$_:$qauths{$_}\n";
        }
    }
    
    return;
}

# Reads data from files
sub readdata {
    my $userdatafilename   = 'userdata.txt';
    my $gamedatafilename   = 'gamedata.txt';
    my $ignoredatafilename = 'ignoredata.txt';
    my $authdatafilename   = 'authdata.txt';
    
    my $userdatafile;
    my $gamedatafile;
    my $ignoredatafile;
    my $authdatafile;
    
    my $line;
    
    # Read userdata
    if (-e $userdatafilename && (open $userdatafile, $userdatafilename) ) {
        my @elements;
        my @values;
        while (<$userdatafile>) {
            $line = $_;
            chomp($line);
            @elements = split('=', $line);
            if ($#elements > 0) {
                @values = split('\.', $elements[1]);
                if ($#values >= 4) {
                    $users{$elements[0]} = $elements[1];
                    
                } else {
                    print STDERR "Invalid line in file $userdatafilename:\n$line\n";
                }
            }
        }
    }
    
    # Read gamedata
    if (-e $gamedatafilename && (open $gamedatafile, $gamedatafilename) ) {
        my @elements;
        my @values0;
        my @values1;
        my @values2;
        my @values3;
        my $highestgamenum = 0;
        
        while (<$gamedatafile>) {
            $line = $_;
            chomp($line);
            @elements = split(',', $line);
            if ($#elements >= 4) {
                @values0 = split(':', $elements[0]);    # <gameno>:<active|closed>
                @values1 = split(':', $elements[1]);    # time:<epochtime> (unix timestamp)
                @values2 = split(':', $elements[2]);    # map:<map>
                @values3 = split(':', $elements[3]);    # result:<1|2|3>
                if ($#values0 > 0 && $#values1 > 0 && $#values2 > -1 && $#values3 > -1) {
                
                    # Put the line into %games
                    $games{$values0[0]} = $line;
                    
                
                } else {
                    print STDERR "Invalid line in file $gamedatafilename:\n$line\n";
                }
                
            } else {
                print STDERR "Invalid line in file $gamedatafilename:\n$line\n";
            }
        }
        
        # Find the last game played
        $gamenum = findlastgame();
    }
    
    # Read ignoredata
    if (-e $ignoredatafilename && (open $ignoredatafile, $ignoredatafilename) ) {
        while (<$ignoredatafile>) {
            $line = $_;
            chomp($line);
            push(@hlignorelist, $line);
        }
    }
    
    # Read authdata
    if (-e $authdatafilename && (open $authdatafile, $authdatafilename) ) {
        my @authdata;
        
        while (<$authdatafile>) {
            $line = $_;
            chomp($line);
            @authdata = split(':', $line);
            
            if ($#authdata == 1) {
                $qauths{$authdata[0]} = $authdata[1];
                
            } else {
                print STDERR "Invalid line in file $authdatafilename:\n$line\n";
            }
        }
    }
    
    return;
}

sub findlastgame {
    my $highestgamenum = -1;

    foreach (keys %games) {
        my @gamedata = split(',', $games{$_});
        
        if ($#gamedata < 1) {
            print STDERR "Invalid line in gamedata: $games{$_}\n";
            return -1;
        }
        
        my @gamedata0 = split(':', $gamedata[0]);
        
        if ($#gamedata0 < 1) {
            print STDERR "Invalid string in gamedata: $gamedata[0]\n";
            return -1;
        }
        
        if ($gamedata0[0] > $highestgamenum) {
            $highestgamenum = $gamedata0[0];
        }
    }
    
    return $highestgamenum;
}

sub readcfg {
    my $cfgfilename = 'gatherbot.cfg';
    my $cfgfile;
    
    unless (-e $cfgfilename) { return; }
    unless (open $cfgfile, "$cfgfilename" or die "error opening file $cfgfilename: $!") {
        return;
    }
    my @elements; my @values;
    my $line; my $indexofcommentchar;
    
    while (<$cfgfile>) {
        $line = $_;
        chomp($line);
        $line =~ s/^\s+//;      # remove leading whitespace
        $line =~ s/\s+$//;      # remove trailing whitespace
        $indexofcommentchar = index($line, '#');
        if ($indexofcommentchar != -1) {
            if ($indexofcommentchar == 0) {
                unless ($line eq '# Bot related settings' || $line eq '# Gather related settings') {
                    $cfgheader .= "$line\n";
                }
            }
            $line = substr($line, 0, $indexofcommentchar);
        }
        @elements = split('=', $line);
        if ($#elements > 0) {
            $elements[0] =~ s/^\s+//;  $elements[1] =~ s/^\s+//;    # remove leading whitespace
            $elements[0] =~ s/\s+$//;  $elements[1] =~ s/\s+$//;    # remove trailing whitespace
            @values = split(/\s+/, $elements[1]);
            
            if    ($elements[0] eq 'server')               { $server = $elements[1]; }
            elsif ($elements[0] eq 'chan')                 { $chan = "#" . "$elements[1]"; }
            elsif ($elements[0] eq 'nick')                 { $nick = $elements[1]; }
            elsif ($elements[0] eq 'authname')             { $authname = $elements[1]; }
            elsif ($elements[0] eq 'authpw')               { $authpw = $elements[1]; }
            elsif ($elements[0] eq 'team1')                { $team1 = $elements[1]; }
            elsif ($elements[0] eq 'team2')                { $team2 = $elements[1]; }
            elsif ($elements[0] eq 'draw' )                { $draw = $elements[1]; }
            elsif ($elements[0] eq 'maxplayers')           { $maxplayers = $elements[1]; }
            elsif ($elements[0] eq 'gameserverip')         { $gameserverip = $elements[1]; }
            elsif ($elements[0] eq 'gameserverport')       { $gameserverport = $elements[1]; }
            elsif ($elements[0] eq 'gameserverpw')         { $gameserverpw = $elements[1]; }
            elsif ($elements[0] eq 'voiceserverip')        { $voiceserverip = $elements[1]; }
            elsif ($elements[0] eq 'voiceserverport')      { $voiceserverport = $elements[1]; }
            elsif ($elements[0] eq 'voiceserverpw')        { $voiceserverpw = $elements[1]; }
            elsif ($elements[0] eq 'neededvotes_captain')  { setneededvotes_captain($elements[1]); }
            elsif ($elements[0] eq 'neededvotes_map')      { setneededvotes_map($elements[1]); }
            elsif ($elements[0] eq 'neededreq_replace')    { setneededreq_replace($elements[1]); }
            elsif ($elements[0] eq 'neededreq_remove')     { setneededreq_remove($elements[1]); }
            elsif ($elements[0] eq 'neededreq_score')      { setneededreq_score($elements[1]); }
            elsif ($elements[0] eq 'neededreq_rafflecapt') { setneededreq_rafflecapt($elements[1]); }
            elsif ($elements[0] eq 'neededreq_hl')         { setneededreq_hl($elements[1]); }
            elsif ($elements[0] eq 'initialpoints')        { $initialpoints = $elements[1]; }
            elsif ($elements[0] eq 'pointsonwin')          { $pointsonwin = $elements[1]; }
            elsif ($elements[0] eq 'pointsonloss')         { $pointsonloss = $elements[1]; }
            elsif ($elements[0] eq 'pointsondraw')         { $pointsondraw = $elements[1]; }
            elsif ($elements[0] eq 'p_scale_factor')       { $p_scale_factor = $elements[1]; }
            elsif ($elements[0] eq 'p_scale_factor_draw')  { $p_scale_factor_draw = $elements[1]; }
            elsif ($elements[0] eq 'p_max_variance')       { $p_max_variance = $elements[1]; }
            elsif ($elements[0] eq 'topdefaultlength')     { $topdefaultlength = $elements[1]; }
            elsif ($elements[0] eq 'gamehascaptains')      { $gamehascaptains = $elements[1]; }
            elsif ($elements[0] eq 'gamehasmap')           { $gamehasmap = $elements[1]; }
            elsif ($elements[0] eq 'votecaptaintime')      { $votecaptaintime = $elements[1]; }
            elsif ($elements[0] eq 'votemaptime')          { $votemaptime = $elements[1]; }
            elsif ($elements[0] eq 'mutualvotecaptain')    { $mutualvotecaptain = $elements[1]; }
            elsif ($elements[0] eq 'mutualvotemap')        { $mutualvotemap = $elements[1]; }
            elsif ($elements[0] eq 'printpoolafterpick')   { $printpoolafterpick = $elements[1]; }
            elsif ($elements[0] eq 'givegameserverinfo')   { $givegameserverinfo = $elements[1]; }
            elsif ($elements[0] eq 'givevoiceserverinfo')  { $givevoiceserverinfo = $elements[1]; }
            elsif ($elements[0] eq 'showinfointopic')      { $showinfointopic = $elements[1]; }
            elsif ($elements[0] eq 'topicdelimiter')       { $topicdelimiter = $elements[1]; }
            elsif ($elements[0] eq 'remindtovote')         { $remindtovote = $elements[1]; }
            elsif ($elements[0] eq 'websiteurl')           { $websiteurl = $elements[1]; }
            elsif ($elements[0] eq 'locale')               { set_locale($elements[1]); }
            
            elsif ($elements[0] eq 'admins') {
                my $adminsstring = join(' ', @values);
                @admins = split(/\s+/, $adminsstring);
            }
            
            elsif ($elements[0] eq 'maps') {
                my $mapsstring = join(' ', @values);
                @maps = split(/\s+/, $mapsstring);
            }
            
            else {
                print STDERR "Invalid line in file $cfgfilename:\n$line\n";
            }
        }
    }
    return;
}

sub get_timezone {

    if ($locale eq 'fi') {
        return 'Europe/Helsinki';
    }
    
    return 'UTC';
}

sub set_locale {
    my $param = $_[0];
    
    if ($param eq 'fi') {
        $locale = $param;
        $param = 'fi_FI';
        
    } else {
        $locale = $param;
        $param = 'en_US';
    }
    
    setlocale(LC_MESSAGES, $param);
    
    # Needed to make it work in UTF-8 locales in Perl-5.8.
    binmode STDOUT, ':raw';

    return;
}

sub writecfg {
    my $cfgfilename = 'gatherbot.cfg';
    my $cfgfile;
    
    unless (open $cfgfile, '>', $cfgfilename
            or die "error in overwriting file $cfgfilename: $!") {
        return;
    }
    
    if ($cfgheader eq '') {
        $cfgheader = "# gatherbot settings\n" .
                     "#\n" .
                     "# The settings here are read on init and overwritten on shutdown.\n" .
                     "#\n" .
                     "# Syntax:\n" .
                     "# variable = value\n" .
                     "#    OR\n" .
                     "# variable = list of values, separated by whitespace\n";
    }
    
    my $chan_wo_fence = substr($chan, 1);
    
    my $neededvotes_captaindesc  = "# total number of votes needed for captainvotes to have affect (0 defaults to maxplayers/2)";
    my $neededvotes_mapdesc      = "# total number of votes needed for mapvotes to have affect (0 defaults to maxplayers/2)";
    my $neededreq_replacedesc    = "# number of requests needed by non-admins to replace someone (0 defaults to maxplayers/2)";
    my $neededreq_removedesc     = "# number of requests needed by non-admins to remove someone (0 defaults to maxplayers/2)";
    my $neededreq_scoredesc      = "# number of requests needed by non-admins to report a score (0 defaults to maxplayers/2)";
    my $neededreq_rafflecaptdesc = "# number of requests needed by non-admins to raffle a new captain (0 defaults to maxplayers/2)";
    my $neededreq_hldesc         = "# number of requests needed by non-admins to have the bot hilight everyone (0 defaults to maxplayers/2)";
    my $initialpointsdesc        = "# the amount of points one starts with";
    my $pointsonwindesc          = "# the points change on win";
    my $pointsonlossdesc         = "# the points change on loss";
    my $pointsondrawdesc         = "# the points change on draw";
    my $topdefaultlengthdesc     = "# the default length of .top list";
    my $gamehascaptainsdesc      = "# toggle whether the games have captains";
    my $gamehasmapdesc           = "# toggle whether the games have a map";
    my $votecaptaintimedesc      = "# time in seconds to vote for captains after signup completes (0 to disable)";
    my $votemaptimedesc          = "# time in seconds to vote for map after signup completes (0 to disable)";
    my $mutualvotecaptaindesc    = "# toggle whether voting of captains is disabled until signup completes (1 together with votecaptaintime=0 disables votecaptain)";
    my $mutualvotemapdesc        = "# toggle whether mapvoting is disabled until signup completes (1 together with votemaptime=0 disables votemap)";
    my $printpoolafterpickdesc   = "# toggle whether the player pool should be printed after each pick";
    my $givegameserverinfodesc   = "# toggle whether to print game server info when the game starts";
    my $givevoiceserverinfodesc  = "# toggle whether to print voice server info when the game starts";
    my $showinfointopicdesc      = "# toggle whether to show signup and game info in topic";
    my $topicdelimiterdesc       = "# determines the delimiter string between topic elements";
    my $remindtovotedesc         = "# toggle whether to remind the player to vote for map/captains upon signing up";
    my $p_scale_factordesc       = "# the linear points scale factor on win/loss";
    my $p_scale_factor_drawdesc  = "# the linear points scale factor on draw";
    my $p_max_variancedesc       = "# the maximum amount of variance that the extra points are allowed to have on the points delta";
    my $websiteurldesc           = "# the url of the website that the bot will try to send statistics to";
    my $localedesc               = "# the language that the bot's replies will be in. Possible values: en, fi";

    
    print $cfgfile "$cfgheader" .
                   "\n" .
                   "\n" .
                   "# Bot related settings\n" .
                   "server               = $server\n" .
                   "chan                 = $chan_wo_fence\n" .
                   "nick                 = $nick\n" .
                   "authname             = $authname\n" .
                   "authpw               = $authpw\n" .
                   "\n" .
                   "# Gather related settings\n" .
                   "team1                = $team1\n" .
                   "team2                = $team2\n" .
                   "draw                 = $draw\n" .
                   "maxplayers           = $maxplayers\n" .
                   "admins               = @admins\n" .
                   "maps                 = @maps\n" .
                   "gameserverip         = $gameserverip\n" .
                   "gameserverport       = $gameserverport\n" .
                   "gameserverpw         = $gameserverpw\n" .
                   "voiceserverip        = $voiceserverip\n" .
                   "voiceserverport      = $voiceserverport\n" .
                   "voiceserverpw        = $voiceserverpw\n" .
                   "neededvotes_captain  = $neededvotes_captain\t\t\t$neededvotes_captaindesc\n" .
                   "neededvotes_map      = $neededvotes_map\t\t\t$neededvotes_mapdesc\n" .
                   "neededreq_replace    = $neededreq_replace\t\t\t$neededreq_replacedesc\n" .
                   "neededreq_remove     = $neededreq_remove\t\t\t$neededreq_removedesc\n" .
                   "neededreq_score      = $neededreq_score\t\t\t$neededreq_scoredesc\n" .
                   "neededreq_rafflecapt = $neededreq_rafflecapt\t\t\t$neededreq_rafflecaptdesc\n" .
                   "neededreq_hl         = $neededreq_hl\t\t\t$neededreq_hldesc\n" .
                   "initialpoints        = $initialpoints\t\t\t$initialpointsdesc\n" .
                   "pointsonwin          = $pointsonwin\t\t\t$pointsonwindesc\n" .
                   "pointsonloss         = $pointsonloss\t\t\t$pointsonlossdesc\n" .
                   "pointsondraw         = $pointsondraw\t\t\t$pointsondrawdesc\n" .
                   "p_scale_factor       = $p_scale_factor\t\t\t$p_scale_factordesc\n" .
                   "p_scale_factor_draw  = $p_scale_factor_draw\t\t\t$p_scale_factor_drawdesc\n" .
                   "p_max_variance       = $p_max_variance\t\t\t$p_max_variancedesc\n" .
                   "topdefaultlength     = $topdefaultlength\t\t\t$topdefaultlengthdesc\n" .
                   "gamehascaptains      = $gamehascaptains\t\t\t$gamehascaptainsdesc\n" .
                   "gamehasmap           = $gamehasmap\t\t\t$gamehasmapdesc\n" .
                   "votecaptaintime      = $votecaptaintime\t\t\t$votecaptaintimedesc\n" .
                   "votemaptime          = $votemaptime\t\t\t$votemaptimedesc\n" .
                   "mutualvotecaptain    = $mutualvotecaptain\t\t\t$mutualvotecaptaindesc\n" .
                   "mutualvotemap        = $mutualvotemap\t\t\t$mutualvotemapdesc\n" .
                   "printpoolafterpick   = $printpoolafterpick\t\t\t$printpoolafterpickdesc\n" .
                   "givegameserverinfo   = $givegameserverinfo\t\t\t$givegameserverinfodesc\n" .
                   "givevoiceserverinfo  = $givevoiceserverinfo\t\t\t$givevoiceserverinfodesc\n" .
                   "showinfointopic      = $showinfointopic\t\t\t$showinfointopicdesc\n" .
                   "topicdelimiter       = $topicdelimiter\t\t\t$topicdelimiterdesc\n" .
                   "remindtovote         = $remindtovote\t\t\t$remindtovotedesc\n" .
                   "websiteurl           = $websiteurl\t\t\t$websiteurldesc\n" .
                   "locale               = $locale\t\t\t$localedesc\n";
    return;
}

sub senddata {
    my $self = shift;
    
    my @gamedata;
    my @gendata;
    my @timedata;
    my @mapdata;
    my @resultdata;
    my @tskilldata;
    
    my $map;
    my $map_pk = 1;
    $map_pks{'none'} = 1;
    
    my $highestgameno = 0;
    my $hadgamestosend = 0;
    
    my @jsons;
    
    # Preparation
    push(@jsons, '{"pk": 1, "model": "gathers.team", "fields": {"name": "Team 1"}}');
    push(@jsons, '{"pk": 2, "model": "gathers.team", "fields": {"name": "Team 2"}}');
    push(@jsons, '{"pk": 1, "model": "gathers.map", "fields": {"name": "none"}}');

    foreach (keys %games) {
        @gamedata = split ',', $games{$_};
        @gendata  = split ':', $gamedata[0];
        
        my $gameno = $gendata[0];
        
        # If the game is closed AND was not already sent
        if ($gendata[1] eq 'closed' && $gameno > $lastsentgame) {
            
            $hadgamestosend = 1;
            
            @timedata = split ':', $gamedata[1];
            @mapdata  = split ':', $gamedata[2];
            @resultdata = split ':', $gamedata[3];
            @tskilldata = split ':', $gamedata[4];
            
            my $gameno = $gendata[0];
            my $time = $timedata[1];
            my $result = $resultdata[1];
            my $t1_skill = $tskilldata[0];
            my $t2_skill = $tskilldata[1];
            
            if ($gameno > $highestgameno) {
                $highestgameno = $gameno;
            }
            
            my $dt = DateTime->from_epoch(epoch => $time);
            my $datestr = $dt->datetime();
            $datestr .= 'Z';    # append Z to DateTime (Webserver expects this)
            
            if ($#mapdata > 0) {
                $map = $mapdata[1];
                
                if ($map eq 'nsl_summit') {
                    $map = 'summit';
                }
                
            } else {
                $map = 'none';
            }
            
            # Add the map if not added yet
            if (! exists $map_pks{$map}) {
                my $pk = gethighest_pk('map');
                $pk += 1;
                
                $map_pks{$map} = $pk;
                
                # - ADD MAP TO THE DATA -
                push(@jsons, '{"pk": ' . $pk . ', "model": "gathers.map", "fields": {"name": "' . $map . '"}}');
            }
        
            # Get map's primary key
            $map_pk = $map_pks{$map};

            # - ADD GAME TO THE DATA -
            push(@jsons, '{"pk": ' . $gameno . ', "model": "gathers.game", "fields": {"date": "' . $datestr .
                         '", "map": ' . $map_pk . ', "result": ' . $result . ', "t1_skill": ' . $t1_skill . 
                         ', "t2_skill": ' . $t2_skill . '}}');
            
            # Get the players that played in this game
            my @plist = get_players_by_gameno($gameno);
            
            # Get the player's points before the game
            my @pbefore = get_points_by_gameno($gameno, 'before');
            
            # Get the player's point deltas of the game
            my @pdeltas = get_points_by_gameno($gameno, 'delta');
            
            # Find out what was the team size
            my $wasmaxplayers = $#plist + 1;
            my $wasteamsize = $wasmaxplayers / 2;
            
            # Add players (Player & Game_Player objects) to the data
            for my $i (0 .. $#plist) {
            
                my $player = $plist[$i];
                
                # Add to %player_pks if necessary
                if (! exists $player_pks{$player}) {
                    my $pk = gethighest_pk('player');
                    $player_pks{$player} = $pk + 1;
                }
                
                # print STDERR "player: $player\n";
                
                # Get player's pk and userdata
                my $player_pk = $player_pks{$player};
                my @userdata = split '\.', $users{$player};
                
                # - ADD PLAYER ENTRY TO THE DATA -
                push(@jsons, '{"pk": ' . $player_pk . ', "model": "gathers.player", "fields": {"points": ' . $userdata[1] .
                             ', "wins": ' . $userdata[2] . ', "losses": ' . $userdata[3] . ', "draws": ' . $userdata[4] .
                             ', "accesslevel": "' . $userdata[0] . '", "name": "' . $player . '"}}');
                
                # Get game_player primary key
                my $gp_pk = gethighest_pk('game_player');
                $gp_pk += 1;
                $game_player_pks{$gameno . $player} = $gp_pk;
                
                my $pointsdelta = $pdeltas[$i];
                my $pointsbefore = $pbefore[$i];
                
                # Find out the team
                my $team;
                if ($i >= 0 && $i < $wasteamsize) {
                    $team = 1;
                } else {
                    $team = 2;
                }
                
                # Find out if captain
                my $captain = 'false';
                if ($i == 0 || $i == $wasteamsize) {
                    $captain = 'true';
                }
                
                # - ADD GAME_PLAYER ENTRY TO THE DATA -
                push(@jsons, '{"pk": ' . $gp_pk . ', "model": "gathers.game_player", "fields": {"pointsdelta": ' . $pointsdelta .
                             ', "pointsbefore": ' . $pointsbefore . ', "player": ' . $player_pk . ', "game": ' . $gameno . 
                             ', "team": ' . $team . ', "captain": ' . $captain . '}}');
            }
        }
    }
    
    if ($hadgamestosend == 1) {
        $lastsentgame = $highestgameno;
    }
    
    # Put data into one JSON
    my $json = '[' . join(', ', @jsons) . ']';
    
    # print STDERR "JSONS: \n";
    # for my $str (@jsons) {
    #     print STDERR "$str \n";
    # }
    
    my $req = HTTP::Request->new( 'POST', $websiteurl );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content($json);

    my $lwp = LWP::UserAgent->new;
    my $res = $lwp->request($req);
    my $res_str = $res->decoded_content;
    
    $self->sayc(__x("Answer from web-server: {ans}",
                    ans => $res_str));
    
    return;
}

sub gethighest_pk {
    my $attr = $_[0];

    my $highest = 0;
    
    if ($attr eq 'map') {
        foreach (keys %map_pks) {
            if ($map_pks{$_} > $highest) {
                $highest = $map_pks{$_};
            }
        }
    }
    
    if ($attr eq 'player') {
        foreach (keys %player_pks) {
            if ($player_pks{$_} > $highest) {
                $highest = $player_pks{$_};
            }
        }
    }
    
    if ($attr eq 'game_player') {
        foreach (keys %game_player_pks) {
            if ($game_player_pks{$_} > $highest) {
                $highest = $game_player_pks{$_};
            }
        }
    }
    
    return $highest;
}

sub save {
    writedata();
    writecfg();
}

readcfg();
readdata();

GatherBot->new(
    server =>   $server,
    channels => [ "$chan" ],
    nick =>     $nick,
    flood =>    0,
)->run();
