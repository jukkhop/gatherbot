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
my $initialpoints        = 1000;
my $pointsonwin          = 10;
my $pointsonloss         = -10;
my $pointsondraw         = 3;
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
my $topicdelimiter       = "[]";

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
my $votecaptaindone = 0;
my $captain1 = "";
my $captain2 = "";
my $chosenmap = "";
my $capt1rafflerequests = "";
my $capt2rafflerequests = "";
my $cfgheader = "";
my $defaulttopic = "";
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

sub connected {
    my $self = shift;

    # Add names in @admin to userdata
    # if not there already
    for my $name (@admins) {
        if (! exists($users{$name}) ) {
            $users{$name} = "admin.$initialpoints.0.0.0";
        }
    }

    # Auth to Q if auth info was given
    if ($authname ne '' && $authpw ne '') {
        $self->say(
            who =>     'NickServ',
            channel => 'msg',
            body =>    "AUTH $authname $authpw",
            address => 'false'
        );
    }

    return;
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
            my $outline = "Map voting has ended.";

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

                $outline .= " The winner of votemap is $chosenmap.";
                $self->emote(channel => $chan, body => $outline);

            } else {
                if ($outline ne '') {
                    $self->emote(channel => $chan, body => $outline);
                }

                $self->emote(channel => $chan,
                             body => "Received less than $neededvotes_map votes. " .
                                     "The map will be selected randomly.");
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
                $self->emote(channel => $chan,
                             body => "Voting of captains is about to begin. " .
                                     "Vote with command .votecaptain <playername>");
            }

            if ($captain1 ne '') {
                $self->emote(channel => $chan,
                             body => "The other captain is $captain1. " .
                                     "Voting of the other captain is about to begin.");

                $self->emote(channel => $chan,
                             body => "Vote with command .votecaptain <playername>");

            }

            if ($captain1 eq '' && $captain2 eq '') {
                $self->emote(channel => $chan,
                             body => "Votable players: @players");

            } else {
                my @votableplayers;

                for my $i (0 .. $#players) {
                    if ($players[$i] ne $captain1) {
                        push(@votableplayers, $players[$i]);
                    }
                }

                $self->emote(channel => $chan,
                             body => "Votable players: @players");
            }

            $self->emote(channel => $chan,
                         body => "Votecaptain ends in $votecaptaintime " .
                                 "seconds!");

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
                $self->emote(channel => $chan,
                             body => "Voting of captains has ended.");
            } else {
                $self->emote(channel => $chan,
                             body => "Voting of one captain has ended.");
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
                    $self->emote(channel => $chan,
                                 body => "Voting was one-sided; " .
                                         "The second captain will be randomly selected.");
                }

            } else {
                my $string = "";
                if ($captain1 eq '' && $captain2 eq '') {
                    $string = "Captains";
                } else {
                    $string = "The other captain ";
                }

                $self->emote(channel => $chan,
                             body => "Received less than $neededvotes_captain " .
                                     "votes. $string will be selected randomly.");
            }
        }
    }

    $self->determinecaptains();
    $self->startpicking();

    return 0;
}

sub said {
    my $self = shift;
    my $message = shift;
    my $who = $message->{who};
    my $channel = $message->{channel};
    my $body = $message->{body};
    my $address = $message->{address};

    # print STDERR "$body\n";

    # If the message comes from Q
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
    if (substr($body, 0, 1) ne '!') {
        return;
    }

    # Split the message by whitespace
    # to get the command+parameters
    my @commands = split(' ', $body);

    # If user doesn't exist in userdata, add him
    if (! exists($users{$who}) ) {
        $users{$who} = "user.$initialpoints.0.0.0";
    }

    # If there's no qauth info on the user,
    # check if he's actually authed
    if (! exists($qauths{$who}) ) {
        $self->whoisuser_to_q($who);
    }

    # Get the user's access level
    my @userdata = split('\.', $users{$who});
    my $accesslevel = $userdata[0];


    # command .add
    if ($commands[0] eq '!add' || $commands[0] eq '!sign') {

        if ($canadd == 0) {
            $self->emote(channel => $chan,
                         body => "Sign-up is not open at the moment.");
            return;
        }

        my $tbadded;
        if ($#commands == 0) {
            $tbadded = $who;

        } else {
            if ($accesslevel eq 'admin') {
                $tbadded = "$commands[1]";

                if (! exists($users{$tbadded}) ) {
                    $users{$tbadded} = "user.$initialpoints.0.0.0";
                }

            } else {
                $self->emote(channel => $chan,
                             body => "$who is not an admin.");
                return;
            }
        }

        # Check if already signed
        if (issigned($tbadded)) {
            $self->emote(channel => $chan,
                         body => "$tbadded has already signed up.");
            return;
        }

        # Add the player on the playerlist
        push(@players, $tbadded);
        my $playercount = $#players+1;

        $self->emote(channel => $chan,
                     body => "$tbadded has signed up " .
                             "($playercount/$maxplayers)");

        $self->updatetopic();

        # Init player's votes and requests
        $self->voidusersvotes($tbadded);
        $self->voidusersrequests($tbadded);

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

        # Set stuff
        $canadd = 0;
        $canout = 0;

        # Decide how to start the game
        # (which number to pass to schedule_tick)
        my $waittime = 1;
        if ($gamehasmap == 1 && $votemaptime > 0) {
            $canvotemap = 1;
            $chosenmap = "";

            $self->emote(channel => $chan,
                         body => "Votemap is about to begin. " .
                                 "Vote with command .votemap <mapname>");

            $self->emote(channel => $chan,
                         body => "Votable maps: @maps");

            $self->emote(channel => $chan,
                         body => "Votemap ends in $votemaptime seconds!");

            $waittime = $votemaptime;
        }

        # Makes tick() run after $waittime seconds have passed
        $self->schedule_tick($waittime);

        return;
    }


    # command .captain
    elsif ($commands[0] eq '!captain') {

        if ($gamehascaptains == 0) {
            $self->emote(channel => $chan,
                         body => "Command $commands[0] is not enabled " .
                                 "(gamehascaptains = 0)");
            return;
        }

        if ($cancaptain == 0) {
            $self->emote(channel => $chan,
                         body => "Signing up as a captain is not possible " .
                                 "at the moment.");
            return;
        }

        my $tbcaptain;

        if ($#commands == 0) {
            $tbcaptain = $who;
        } else {
            if ($accesslevel ne 'admin') {
                $self->emote(channel => $chan,
                             body => "$who is not an admin.");
                return;
            }
            $tbcaptain = $commands[1];
        }

        if ($tbcaptain eq $captain1 || $tbcaptain eq $captain2) {
            $self->emote(channel => $chan,
                         body => "$tbcaptain is already a captain.");
            return;
        }

        if (issigned($tbcaptain) == 0) {
            $self->emote(channel => $chan,
                         body => "$tbcaptain has not signed up.");
            return;
        }

        if ($captain1 eq '') {
            $captain1 = $tbcaptain;
            $self->emote(channel => $chan,
                         body => "$tbcaptain is now a captain.");

        } elsif ($captain2 eq '') {
            $captain2 = $tbcaptain;
            $self->emote(channel => $chan,
                         body => "$tbcaptain is now a captain.");
        }

        if ($captain1 ne '' && $captain2 ne '') {
            $cancaptain = 0;
        }

        $self->updatetopic();

        return;
    }


    # command .uncaptain
    elsif ($commands[0] eq '!uncaptain') {

        if ($gamehascaptains == 0) {
            $self->emote(channel => $chan,
                         body => "Command $commands[0] is not enabled " .
                                 "(gamehascaptains = 0)");
            return;
        }

        my $tbuncaptain;

        if ($#commands == 0) {
            $tbuncaptain = $who;
        } else {
            if ($accesslevel ne 'admin') {
                $self->emote(channel => $chan,
                             body => "$who is not an admin..");
                return;
            }
            $tbuncaptain = $commands[1];
        }

        if ($tbuncaptain ne $captain1 && $tbuncaptain ne $captain2) {
            $self->emote(channel => $chan,
                         body => "$tbuncaptain is not a captain.");
            return;
        }

        if ($canpick == 1) {
            $self->emote(channel => $chan,
                         body => "Player picking has already started " .
                                 "(must use .rafflecaptain or .changecaptain)");
            return;
        }

        if ($captain1 eq $tbuncaptain) {
            $captain1 = "";
            $self->emote(channel => $chan,
                         body => "$tbuncaptain is not a captain anymore.");

        } elsif ($captain2 eq $tbuncaptain) {
            $captain2 = "";
            $self->emote(channel => $chan,
                         body => "$tbuncaptain is not a captain anymore.");
        }

        $self->updatetopic();

        $cancaptain = 1;

        return;
    }


    # command .rafflecaptain
    elsif ($commands[0] eq '!rafflecaptain') {

        if ($gamehascaptains == 0) {
            $self->emote(channel => $chan,
                         body => "Command $commands[0] is not enabled " .
                                 "(gamehascaptains = 0)");
            return;
        }

        if ($canpick == 0) {
            if ($who eq $captain1 || $who eq $captain2) {
                $self->emote(channel => $chan,
                             body => "Player picking has not started yet " .
                                     "(use .uncaptain)");
            } else {
                $self->emote(channel => $chan,
                             body => "Player picking has not started yet.");
            }

            return;
        }

        if ($#commands == 0) {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] <captains_name>");
            return;
        }

        # For case-insensitivity
        my $cmd1lc = lc($commands[1]);
        my $capt1lc = lc($captain1);
        my $capt2lc = lc($captain2);

        if ($cmd1lc ne $capt1lc && $cmd1lc ne $capt2lc) {
            $self->emote(channel => $chan,
                         body => "$commands[1] is not a captain.");
            return;
        }

        # If not an admin
        if ($accesslevel ne 'admin') {

            #  Check if signed
            if (issigned($who) == 0) {
                $self->emote(channel => $chan,
                             body => "$who has not signed up.");
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
            $self->emote(channel => $chan,
                         body => "Raffling of a new captain in place of $commands[1] " .
                                 "have requested: $requestersline " .
                                 "\[$requesterscount / $neededreq_rafflecapt\]");

            # If not enough requesters yet, return.
            # Otherwise, raffle a new captain
            if ($requesterscount < $neededreq_rafflecapt) {
                return;
            }
        }

        # Raffle new captain from the player pool
        my $playercount = $#players+1;
        my $randindex = int(rand($playercount));
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

        $self->emote(channel => $chan,
                     body => "$newcaptain is now a captain instead of $oldcaptain");

        return;
    }


    # command .changecaptain
    elsif ($commands[0] eq '!changecaptain') {

        if ($gamehascaptains == 0) {
            $self->emote(channel => $chan,
                         body => "Command $commands[0] is not enabled " .
                                 "(gamehascaptains = 0)");
            return;
        }

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "$who is not an admin.");
            return;
        }

        if ($#commands < 2) {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] <current_captain> " .
                                 "<new_captain>");
            return;
        }

        if ($commands[1] ne $captain1 && $commands[1] ne $captain2) {
            $self->emote(channel => $chan,
                         body => "$commands[1] is not a captain.");
            return;
        }

        if (isontheplayerlist($commands[2]) == 0) {
            $self->emote(channel => $chan,
                         body => "$commands[2] is not on the player list.");
            return;
        }

        if ($commands[2] eq $captain1 || $commands[2] eq $captain2) {
            $self->emote(channel => $chan,
                         body => "$commands[2] is already a captain.");
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
        $self->emote(channel => $chan,
                     body => "$commands[2] is now a captain " .
                             "instead of $commands[1]");

        return;
    }


    # command .pick
    elsif ($commands[0] eq '!pick') {

        if ($gamehascaptains == 0) {
            $self->emote(channel => $chan,
                         body => "Command $commands[0] is not enabled " .
                                 "(gamehascaptains = 0)");
            return;
        }

        if ($canpick == 0) {
            $self->emote(channel => $chan, body => "Player picking has not started.");
            return;
        }

        if ($who ne $captain1 && $who ne $captain2) {
            $self->emote(channel => $chan, body => "$who is not a captain.");
            return;
        }

        if ($#commands < 1) {
            $self->emote(channel => $chan, body => "Syntax is $commands[0] <playername>");
            return;
        }

        if ($who eq $captain1 && $turn != 1) {
            $self->emote(channel => $chan, body => "It's not $captain1" . "'s turn to pick.");
            return;
        }

        if ($who eq $captain2 && $turn != 2) {
            $self->emote(channel => $chan, body => "It's not $captain2's turn to pick.");
            return;
        }

        if (isontheplayerlist($commands[1]) == 0) {
            $self->emote(channel => $chan,
                         body => "$commands[1] is not in the player pool.");
            return;
        }

        # Add the picked player to team1 and set the next turn
        if ($who eq $captain1) {
            push(@team1, $commands[1]);
            $turn = 2;
        }

        # Else, add the picked player to team2 and set the next turn
        if ($who eq $captain2) {
            push(@team2, $commands[1]);
            $turn = 1;
        }

        # If this was the 2nd pick (two captains + two players = 4),
        # make the 2nd captain pick again
        my $pickedplayercount = $#team1+1 + $#team2+1;
        if ($pickedplayercount == 4) {
            $turn = 1;
        }

        # Remove the picked one from the playerlist
        for my $i (0 .. $#players) {
            if ($players[$i] eq $commands[1]) {
                splice(@players, $i, 1);
                last;
            }
        }

        my $outline = "$who picked $commands[1].";
        # my $pickedplayercount = $#team1+1 + $#team2+1;
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
            $outline .= " $nextpicker's turn to pick.";
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

        $self->emote(channel => $chan, body => $outline);

        # Print player pool if necessary
        if ($giveplayerlist == 1 && $printpoolafterpick == 1) {
            my $playerlist = $self->formatplayerlist(@players);

            $self->emote(channel => $chan,
                         body => "Players: $playerlist");
        }

        # Give output if the last pick was done automatically
        if ($lastpickwasauto == 1 ) {
            $self->emote(channel => $chan,
                         body => "One player remained in the pool; @players " .
                                 "was automatically moved to $nextpicker's team.");
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
    elsif ($commands[0] eq '!abort') {

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "$who is not an admin..");
            return;
        }

        my $playercount = $#players + 1;
        if ($playercount == 0) {
            $self->emote(channel => $chan,
                         body => "No one has signed up.");
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

        $self->emote(channel => $chan,
                     body => "The starting of the game has been aborted; " .
                             "cleared the sign-up list.");

        $self->updatetopic();

        return;
    }


    # command .list
    elsif ($commands[0] eq '!list'        || $commands[0] eq '!ls' ||
           $commands[0] eq '!listplayers' || $commands[0] eq '!lp' ||
           $commands[0] eq '!playerlist'  || $commands[0] eq '!pl')  {

        my $outline = "";

        if ($#players < 0) {
            $outline = "No one has signed up.";

        } else {
            my $playercount = $#players+1;
            my $list = $self->formatplayerlist(@players);

            if ($canpick == 0) {
                $outline = "Players: $list ($playercount/$maxplayers)";

            } else {
                $outline = "Player pool: $list";
            }
        }

        $self->emote(channel => $chan, body => $outline);
        return;
    }


    # command .score
    elsif ($commands[0] eq '!score' || $commands[0] eq '!report' ||
           $commands[0] eq '!result') {

        if ($#commands < 2) {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] " .
                                 "<gameno> <$team1|$team2|$draw>");
            return;
        }

        my $cmd1 = $commands[1];
        my $cmd2 = $commands[2];

        # Make lowercase versions of the strings
        # to use them in comparisons
        my $cmd2lc = lc($cmd2);
        my $team1lc = lc($team1);
        my $team2lc = lc($team2);
        my $drawlc = lc($draw);

        if ($cmd2lc ne $team1lc && $cmd2lc ne $team2lc && $cmd2lc ne $drawlc) {
            $self->emote(channel => $chan,
                         body => "Score must be $team1, $team2 or $draw");
            return;
        }

        if (! exists($games{$cmd1}) ) {
            $self->emote(channel => $chan,
                         body => "Game #$cmd1 was not found.");
            return;
        }

        if ( index($games{$cmd1}, 'active') == -1 ) {
            $self->emote(channel => $chan,
                         body => "Game #$cmd1 is closed already.");
            return;
        }

        # Make the given result look like it should
        # (looks better when printed)
        if ($cmd2lc eq $team1lc) { $cmd2 = $team1 };
        if ($cmd2lc eq $team2lc) { $cmd2 = $team2 };
        if ($cmd2lc eq $drawlc)  { $cmd2 = $draw };

        # Get the gamedata
        my @gamedata = split(',', $games{$cmd1});

        # Find out what was the maxplayers and teamsize
        my $wasmaxplayers = ($#gamedata+1) -4;
        my $wasteamsize = $wasmaxplayers / 2;

        if ($accesslevel ne 'admin') {

            # Find out who were captains in this game
            my $wascaptain1 = $gamedata[4];
            my $wascaptain2 = $gamedata[4+$wasteamsize];

            if ($who eq $wascaptain1 || $who eq $wascaptain2) {
                if (! exists($captainscorereq{$cmd1}) ) {
                    $captainscorereq{$cmd1} = " , ";
                }

                my @captainresults = split(',', $captainscorereq{$cmd1});
                my $team = "";

                if ($who eq $wascaptain1) {
                    $captainresults[0] = $cmd2;
                    $team = $team1;
                }

                if ($who eq $wascaptain2) {
                     $captainresults[1] = $cmd2;
                     $team = $team2;
                }

                $captainscorereq{$cmd1} = join(',', @captainresults);

                $self->emote(channel => $chan,
                             body => "$team" . "'s captain requested score \"$cmd2\" " .
                                     "for game #$cmd1");

                if ($captainresults[0] ne $captainresults[1]) {
                    return;
                }

            } else {

                # Find out if the player even played in the game
                # (use @gamedata from before)
                my $wasplaying = 0;
                for my $i (4 .. $#gamedata) {
                    if ($gamedata[$i] eq $who) {
                        $wasplaying = 1;
                    }
                }

                if ($wasplaying == 0) {
                    $self->emote(channel => $chan,
                                 body => "$who didn't play in game #$cmd1.");
                    return;
                }

                # Initialize %userscorereq value if necessary
                if (! exists($userscorereq{$cmd1}) ) {
                    $userscorereq{$cmd1} = "";
                }

                my @requests = split(',', $userscorereq{$cmd1});
                my @requesters;
                my @scores;
                my @arr;

                for my $i (0 .. $#requests) {
                    @arr = split(':', $requests[$i]);
                    push(@requesters, $arr[0]);
                    push(@scores, $arr[1]);
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
                    push(@requesters, $who);
                    push(@scores, $cmd2)
                }

                # Update the scorereqline in %scorereq
                @arr=();
                for my $i (0 .. $#requesters) {
                    push(@arr, "$requesters[$i]:$scores[$i]");
                }

                $userscorereq{$cmd1} = join(',', @arr);

                # Find out who have requested this particular score
                my @certainrequesters;
                for my $i (0 .. $#scores) {
                    if ($scores[$i] eq $cmd2) {
                        push(@certainrequesters, $requesters[$i]);
                    }
                }

                my $requestssofar = $#certainrequesters+1;
                my $requestersline = join(', ', @certainrequesters);

                $self->emote(channel => $chan,
                             body => "Score \"$cmd2\" for game #$cmd1 have requested: " .
                                     "$requestersline \[$requestssofar / $neededreq_score\]");

                if ($requestssofar < $neededreq_score) {
                    return;
                }
            }
        }

        # - GOING TO ACCEPT THE SCORE -

        # Delete score requests related to this game
        delete($userscorereq{$cmd1});
        delete($captainscorereq{$cmd1});

        # Change game status from 'active' to 'closed'
        $gamedata[0] =~ s/active/closed/g;

        my $result;
        my @userinfo;

        if ($cmd2lc eq $team1lc) {
            $result = 1;

            for my $i (4 .. 3+$wasteamsize) {
                @userinfo = split('\.', $users{$gamedata[$i]});
                $userinfo[1] += $pointsonwin;
                $userinfo[2]++;
                $users{$gamedata[$i]} = join('.', @userinfo);
            }

            for my $i (4+$wasteamsize .. 3+$wasmaxplayers) {
                @userinfo = split('\.', $users{$gamedata[$i]});
                $userinfo[1] += $pointsonloss;
                $userinfo[3]++;
                $users{$gamedata[$i]} = join('.', @userinfo);
            }

        } elsif ($cmd2lc eq $team2lc) {
            $result = 2;

            for my $i (4 .. 3+$wasteamsize) {
                @userinfo = split('\.', $users{$gamedata[$i]});
                $userinfo[1] += $pointsonloss;
                $userinfo[3]++;
                $users{$gamedata[$i]} = join('.', @userinfo);
            }

            for my $i (4+$wasteamsize .. 3+$wasmaxplayers) {
                @userinfo = split('\.', $users{$gamedata[$i]});
                $userinfo[1] += $pointsonwin;
                $userinfo[2]++;
                $users{$gamedata[$i]} = join('.', @userinfo);
            }

        } elsif ($cmd2lc eq $drawlc) {
            $result = 3;

            for my $i (4 .. 3+$maxplayers) {
                @userinfo = split('\.', $users{$gamedata[$i]});
                $userinfo[1] += $pointsondraw;
                $userinfo[4]++;
                $users{$gamedata[$i]} = join('.', @userinfo);
            }
        }

        $gamedata[3] .= "$result";
        $games{$cmd1} = join(',', @gamedata);

        $self->emote(channel => $chan,
                     body => "Game #$cmd1 ended; reported.");

        my $outline = "Tulos: ";
        if ($cmd2lc eq $team1lc) { $outline .= "$team1 won"; }
        if ($cmd2lc eq $team2lc) { $outline .= "$team2 won"; }
        if ($cmd2lc eq $drawlc)  { $outline .= "$draw"; }

        $self->emote(channel => $chan, body => $outline);

        $self->updatetopic();

        return;
    }


    # command .out
    elsif ($commands[0] eq '!out' || $commands[0] eq '!remove' ||
           $commands[0] eq '!rm') {

        if ($canout == 0) {
            $self->emote(channel => $chan,
                         body => "Signing out is not possible at the moment.");
            return;
        }

        if ($who eq $captain1 || $who eq $captain2) {
            $self->emote(channel => $chan,
                         body => "The captain can't sign out (must use .uncaptain first)");
            return;
        }

        my $tbremoved;
        if ($#commands == 0) {
            # Sayer wants to remove himself
            $tbremoved = $who;

        } else {
            # Sayer wants to remove someone else
            if ($accesslevel ne 'admin') {

                # If not an admin, check that
                # the sayer is signed himself.
                # If not, return
                if (issigned($who) == 0) {
                    $self->emote(channel => $chan,
                                 body => "$who has not signed up.");
                    return;
                }
            }

            $tbremoved = $commands[1];
        }

        # Find out if and where the
        # to-be-removed is on the playerlist
        my $indexofplayer = -1;
        for my $i (0 .. $#players) {
            if ($players[$i] eq $tbremoved) {
                $indexofplayer = $i;
                last;
            }
        }

        # If he wasn't there, return
        if ($indexofplayer == -1) {
            $self->emote(channel => $chan,
                         body => "$tbremoved has not signed up.");
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
            my @requesters = split(',', $removereqline);

            # Check if he already made the request
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
            $removereq{$tbremoved} = join(',', @requesters);

            # Give output
            my $requestssofar = $#requesters+1;
            my $requestersline = join(', ', @requesters);
            $self->emote(channel => $chan,
                         body => "Removing $tbremoved from the sign-up have requested: " .
                                 "$requestersline " .
                                 "\[$requestssofar / $neededreq_remove\]");


            if ($requestssofar < $neededreq_remove) {
                return;
            }
        }

        # - GOING TO REMOVE A PLAYER -

        # Remove the player
        splice(@players, $indexofplayer, 1);

        # Remove player's votes and requests
        $self->voidusersvotes($tbremoved);
        $self->voidusersrequests($tbremoved);

        # Give output
        my $playercount = $#players+1;
        $self->emote(channel => $chan,
                     body => "$tbremoved signed out. " .
                             "$playercount/$maxplayers have signed up.");

        # If playerlist became empty
        if ($playercount == 0) {

            # Clear all votes and requests
            $self->voidvotes();
            $self->voidrequests();
            $canvotemap = 0;
            $canvotecaptain = 0;
        }

        $self->updatetopic();

        return;
    }


    # command .stats
    elsif ($commands[0] eq '!stats') {
        my $tbprinted;

        if ($#commands == 0) {
            if (! exists($users{$who}) ) {
                $self->emote(channel => "$chan",
                            body => "User $who was not found.");
                return;

            } else { $tbprinted = $who; }


        } else {
            my $cmd1 = $commands[1];

            if (! exists($users{$cmd1}) ) {
                $self->emote(channel => "$chan",
                            body => "User $cmd1 was not found.");
                return;

            } else { $tbprinted = $cmd1; }

        }

        my @userline = split('\.', $users{$tbprinted});
        $self->emote(channel => "$chan",
                     body => "$tbprinted has " .
                             "$userline[1] points, " .
                             "$userline[2] wins, " .
                             "$userline[3] losses and " .
                             "$userline[4] draws");
        return;
    }


    # command .lastgame and .gameinfo
    elsif ($commands[0] eq '!lastgame' || $commands[0] eq '!lg' ||
           $commands[0] eq '!gameinfo' || $commands[0] eq '!gi') {

        my $query;
        if ($commands[0] eq '!lastgame' || $commands[0] eq '!lg') {
            $query = findlastgame();

        } else { # if command was .gameinfo or .gi
            if ($#commands != 1) {
                $self->emote(channel => $chan,
                             body => "Syntax is $commands[0] <gameno>");
                    return;
            }
            $query = $commands[1];
        }

        if (! exists($games{$query}) ) {
            $self->emote(channel => $chan,
                         body => "Game #$query was not found.");
            return;
        }

        # Get the gamedata
        my @gamedata = split(',', $games{$query});

        # Get the time of the game
        my @timedata = split(':', $gamedata[1]);
        my $ept = $timedata[1];
        my $dt = DateTime->from_epoch(epoch => $ept, time_zone=>'Europe/Helsinki');
        my $dtstr = $dt->day. "." .$dt->month. "." .$dt->year. " " .$dt->hms;

        # Find out what was the maxplayers and teamsize
        my $wasmaxplayers = ($#gamedata+1) -4;
        my $wasteamsize = $wasmaxplayers / 2;

        my @team1list;
        my @team2list;

        # Find out who played in team1
        for my $i (4 .. 3+$wasteamsize) {
            push(@team1list, $gamedata[$i]);
        }

        # Find out who played in team2
        for my $i (4+$wasteamsize .. 3+$wasmaxplayers) {
            push(@team2list, $gamedata[$i]);
        }

        my $team1str = $self->formatteam(@team1list);
        my $team2str = $self->formatteam(@team2list);

        $self->emote(channel => $chan, body => "Game #$query ($dtstr):");
        $self->emote(channel => $chan, body => "$team1: $team1str");
        $self->emote(channel => $chan, body => "$team2: $team2str");

        # If the game had a map, also print map info
        my @mapdata = split(':', $gamedata[2]);
        if ($#mapdata > 0) {
            $self->emote(channel => $chan,
                         body => "Map: $mapdata[1]");
        }

        my $outline = "";
        my @gamedata0 = split(':', $gamedata[0]);

        if ($gamedata0[1] eq 'active') {
            $outline = "Status: active";

        } elsif ($gamedata0[1] eq 'closed') {

            my @resultdata = split(':', $gamedata[3]);
            $outline = "Tulos: ";

            if ($resultdata[1] == 1) { $outline .= "$team1 won"; }
            if ($resultdata[1] == 2) { $outline .= "$team2 won"; }
            if ($resultdata[1] == 3) { $outline .= "$draw"; }

        } else {
            print STDERR "Invalid line in gamedata: $games{$query}\n";
        }

        $self->emote(channel => $chan, body => $outline);

        return;
    }


    # command .whois
    elsif ($commands[0] eq '!whois' || $commands[0] eq '!who') {
        my $tbprinted;

        if ($#commands == 0) {
            $tbprinted = $who;
        } else {
            $tbprinted = $commands[1];
        }

        if (! exists $users{$tbprinted}) {
            $self->emote(channel => $chan,
                         body => "User $who was not found.");
            return;
        }

        my @userline = split('\.', $users{$tbprinted});
        $self->emote(channel => $chan,
                     body => "$tbprinted: $userline[0]");
        return;
    }


    # command .server
    elsif ($commands[0] eq '!server' || $commands[0] eq '!srv') {

        $self->printserverinfo();

        return;
    }


    # command .mumble
    elsif ($commands[0] eq '!mumble' || $commands[0] eq '!mb') {

        $self->printvoipinfo();

        return;
    }


    # command .votecaptain
    elsif ($commands[0] eq '!votecaptain' || $commands[0] eq '!vc') {

        if ($gamehascaptains == 0) {
            $self->emote(channel => $chan,
                         body => "Command $commands[0] is not enabled " .
                                 "(gamehascaptains = 0)");
            return;
        }

        # Get a list of non-captain players
        my @votableplayers;
        for my $i (0 .. $#players) {
            if ($players[$i] ne $captain1 && $players[$i] ne $captain2) {
                push(@votableplayers, $players[$i]);
            }
        }

        if ($#commands < 1) {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] <playername>");

            $self->emote(channel => $chan,
                         body => "Votable players are: @votableplayers");

            $self->emote(channel => $chan,
                         body => "A given vote can be removed by giving a dot as the name. " .
                                 "You can view the given votes with command $commands[0] votes");

            return;
        }

        if ($canvotecaptain == 0) {
            $self->emote(channel => $chan,
                         body => "Voting of captain is not possible at the moment.");

            return;
        }

        my $outline;

        # User wanted to see the votes
        if ($commands[1] eq 'votes') {
            if ($captainvotecount == 0) {
                $outline = "No captainvotes yet.";

            } else {
                $outline = "Captainvotes: ";

                for my $player (@votableplayers) {
                    if ($captainvotes{$player} > 0) {
                        $outline .= "$player\[$captainvotes{$player}\], ";
                    }
                }

                if ($#votableplayers > -1) {
                    chop $outline; chop $outline;
                }
            }

            $self->emote(channel => $chan, body => $outline);
            return;
        }

        if (issigned($who) == 0) {
            $self->emote(channel => $chan,
                         body => "You must be signed up to " .
                                 "be able to vote for a captain.");
            return;
        }


        my $validvote = 0;
        for my $player (@votableplayers) {
            if ($commands[1] eq $player || $commands[1] eq '!') {
                $validvote = 1;
                last;
            }
        }
        if ($validvote == 0) {
            $self->emote(channel => $chan,
                         body => "Invalid player name given. " .
                                 "Votable players are: @votableplayers");
            return;
        }

        if (! exists $captainvoters{$who} ) {
            $captainvoters{$who} = "";
        }

        my $changehappened = 0;
        my $samevote = 0;
        my $hadformervote = 1;

        if ($commands[1] eq '!') {  # User wanted to void his vote
            if ($captainvoters{$who} ne "") {
                $changehappened = 1;

                if ($captainvotes{$captainvoters{$who}} > 0) {
                    $captainvotes{$captainvoters{$who}} -= 1;
                    $captainvotecount--;
                }

                $captainvoters{$who} = "";

            } else { $hadformervote = 0; }

        } else {    # A player was voted
            if ($captainvoters{$who} ne $commands[1]) {
                $changehappened = 1;

                if (exists $captainvotes{$captainvoters{$who}} &&
                    $captainvotes{$captainvoters{$who}} > 0) {

                    $captainvotes{$captainvoters{$who}} -= 1;
                    $captainvotecount--;
                }

                $captainvotes{$commands[1]} += 1;
                $captainvoters{$who} = $commands[1];
                $captainvotecount++;

            } else { $samevote = 1; }
        }

        if ($changehappened == 1) {
            $outline = "Captainvotes: ";

            for my $player (@votableplayers) {
                if ($captainvotes{$player} > 0) {
                    $outline .= "$player\[$captainvotes{$player}\], ";
                }
            }

            if ($#votableplayers > -1) {
                chop $outline; chop $outline;
            }

        } else {
            if ($samevote == 1) {
                $outline = "$who already voted for $commands[1] as a captain.";

            } elsif ($hadformervote == 0) {
                $outline = "$who hasn't made a votecaptain yet.";

            } else {
                $outline = "";
            }
        }

        $self->emote(channel => $chan, body => $outline);
        return;
    }


    # command .votemap
    elsif ($commands[0] eq '!votemap' || $commands[0] eq '!vm') {

        if ($gamehasmap == 0) {
            $self->emote(channel => $chan,
                         body => "Command $commands[0] is not enabled " .
                                 "(gamehasmap = 0)");
            return;
        }

        my $maps = join(', ', @maps);

        if ($#commands < 1) {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] <mapname>");
            $self->emote(channel => $chan,
                         body => "Votable maps are: $maps");
            $self->emote(channel => $chan,
                         body => "A given vote can be removed by giving a dot as the map. " .
                                 "You can view the given votes with command $commands[0] votes");
            return;
        }

        if ($canvotemap == 0) {
            $self->emote(channel => $chan,
                         body => "Voting of map is not possible at the moment.");

            return;
        }

        my $outline;
        if ($commands[1] eq 'votes') {
            if ($mapvotecount == 0) {
                $outline = "No mapvotes yet.";

            } else {
                $outline = "Mapvotes: ";

                for my $map (@maps) {
                    $outline .= "$map\[$mapvotes{$map}\], ";
                }
                chop $outline; chop $outline;
            }

            $self->emote(channel => $chan,
                         body => $outline);
            return;
        }

        if (issigned($who) == 0) {
            $self->emote(channel => $chan,
                           body => "You must be signed up to " .
                                   "be able to vote for a map.");

            return;
        }

        my $validvote = 0;
        for my $map (@maps) {
            if ($commands[1] eq $map || $commands[1] eq '!') {
                $validvote = 1;
                last;
            }
        }
        if ($validvote == 0) {
            $self->emote(channel => $chan,
                         body => "Invalid map. Votable maps are: $maps");
            return;
        }

        if (! exists $mapvoters{$who} ) {
            $mapvoters{$who} = "";
        }

        my $changehappened = 0;
        my $samevote = 0;
        my $hadformervote = 1;

        if ($commands[1] eq '!') {  # User wanted to void his vote
            if ($mapvoters{$who} ne "") {
                $changehappened = 1;

                if ($mapvotes{$mapvoters{$who}} > 0) {
                    $mapvotes{$mapvoters{$who}} -= 1;
                    $mapvotecount--;
                }

                $mapvoters{$who} = "";

            } else { $hadformervote = 0; }

        } else {    # A malid map was voted
            if ($mapvoters{$who} ne $commands[1]) {
                $changehappened = 1;

                if (exists $mapvotes{$mapvoters{$who}} && $mapvotes{$mapvoters{$who}} > 0) {
                    $mapvotes{$mapvoters{$who}} -= 1;
                    $mapvotecount--;
                }

                $mapvotes{$commands[1]} += 1;
                $mapvoters{$who} = $commands[1];
                $mapvotecount++;

            } else { $samevote = 1; }
        }

        if ($changehappened == 1) {
            $outline = "Mapvotes: ";
            for my $map (@maps) { $outline .= "$map\[$mapvotes{$map}\], "; }
            chop $outline; chop $outline;

        } else {
            if ($samevote == 1) {
                $outline = "$who has already voted for map $commands[1]";

            } elsif ($hadformervote == 0) {
                $outline = "$who hasn't voted for a map yet.";

            } else {
                $outline = "";
            }
        }

        $self->emote(channel => $chan, body => $outline);
        return;
    }


    # command .replace
    elsif ($commands[0] eq '!replace') {

        if ($#commands < 2) {
            if ($accesslevel eq 'admin') {
                $self->emote(channel => $chan,
                             body => "Syntax is:");

                $self->emote(channel => $chan,
                             body => "To a game about to begin: " .
                                     "$commands[0] <to-be-replaced> <replacement>");

                $self->emote(channel => $chan,
                             body => "To a game that already started: " .
                                     "$commands[0] <gameno> <to-be-replaced> <replacement>");

            } else {
                $self->emote(channel => $chan,
                             body => "Syntax is $commands[0] <to-be-replaced> <replacement>");
            }

            return;
        }

        if ($#commands < 3) {
            # - Replace someone in the current signup -

            if ($commands[1] eq $captain1 || $commands[1] eq $captain2) {
                $self->emote(channel => $chan,
                             body => "A captain cannot be replaced.");
                return;
            }

            my $replacedindex = -1;
            for my $i (0 .. $#players) {
                if ($players[$i] eq $commands[1]) {
                    $replacedindex = $i;
                }
            }

            if ($replacedindex == -1) {
                $self->emote(channel => $chan,
                             body => "$commands[1] has not signed up.");
                return;
            }

            if (issigned($commands[2])) {
                $self->emote(channel => $chan,
                             body => "$commands[2] has already signed up.");
                return;
            }

            # If sayer is an admin
            if ($accesslevel eq 'admin') {

                # If the replacement doesn't exist in userdata, add him
                if (! exists($users{$commands[2]}) ) {
                    $users{$commands[2]} = "user.$initialpoints.0.0.0";
                }

                $self->voidusersvotes($commands[1]);
                $self->voidusersrequests($commands[1]);

                splice(@players, $replacedindex, 1, $commands[2]);
                $self->emote(channel => $chan,
                             body => "Replaced $commands[1] with player $commands[2].");

                return;
            }

            # - Sayer is an user -

            if (issigned($who) == 0) {
                $self->emote(channel => $chan,
                             body => "$who has not signed up.");
                return;
            }

            if (! exists($replacereq{$commands[1]}) ) {
                $replacereq{$commands[1]} = "";
            }

            my $requestline = $replacereq{$commands[1]};
            my @requests = split(',', $requestline);
            my @requesters;
            my @replacements;
            my @arr;

            for my $request (@requests) {
                @arr = split(':', $request);
                push(@requesters, $arr[0]);
                push(@replacements, $arr[1]);
            }

            my $samerequest = 0;
            for my $i (0 .. $#requesters) {
                if ($requesters[$i] eq $who && $replacements[$i] eq $commands[2]) {
                    $samerequest = 1;
                }
            }

            if ($samerequest == 0) {
                push(@requesters, $who);
                push(@replacements, $commands[2]);
            }

            # Update to %replacereq
            @arr=();
            for my $i (0 .. $#requesters) {
                push(@arr, "$requesters[$i]:$replacements[$i]");
            }
            $replacereq{$commands[1]} = join(',', @arr);

            # Find out who requested this player to be
            # requested with this particular player
            my @certainrequesters;

            for my $i (0 .. $#replacements) {
                if ($replacements[$i] eq $commands[2]) {
                    push(@certainrequesters, $requesters[$i]);
                }
            }

            my $requestssofar = $#certainrequesters+1;
            my $requestersline = join(', ', @certainrequesters);

            $self->emote(channel => $chan,
                         body => "Replacing $commands[1] with $commands[2] " .
                                 "have requested: $requestersline " .
                                 "\[$requestssofar / $neededreq_replace\]");

            # If not enough requests yet, return
            if ($requestssofar < $neededreq_replace) {
                return;
            }

            # - Going to make the replacement -

            # Add the replacement player into %users if not there already
            if (! exists($users{$commands[2]}) ) {
                $users{$commands[2]} = "user.$initialpoints.0.0.0";
            }

            # Make the replacement
            splice(@players, $replacedindex, 1, $commands[2]);

            $self->emote(channel => $chan,
                         body => "Replaced $commands[1] with player $commands[2].");

            # Void votes of the player who was replaced
            $self->voidusersvotes($commands[1]);
            $self->voidusersrequests($commands[1]);

            $self->updatetopic();

            return;
        }

        # - Replace someone in a game that already started -

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "Only an admin can make a replace " .
                                 "to a game that already started. ");
            return;
        }

        if (! exists $games{$commands[1]} ) {
            $self->emote(channel => $chan,
                         body => "Game #$commands[1] was not found.");
            return;
        }

        # Get the gamedata
        my @gamedata = split(',', $games{$commands[1]});

        # Find out what was the maxplayers and teamsize
        my $wasmaxplayers = ($#gamedata+1) -4;
        my $wasteamsize = $wasmaxplayers / 2;

        # Get the game number and game status
        my @gamedata0 = split(':', $gamedata[0]);

        # Check if the game is 'closed'
        if ($gamedata0[1] eq 'closed') {
            $self->emote(channel => $chan,
                         body => "Game #$commands[1] is already closed.");
            return;
        }

        my $wasreplaced = 0;

        # Search for the player in the gamedata
        for my $i (4 .. $wasmaxplayers+3) {

            # If the player was found
            if ($gamedata[$i] eq $commands[2]) {

                # Add the replacement player into %users if not already added
                if (! exists($users{$commands[3]}) ) {
                    $users{$commands[3]} = "user.$initialpoints.0.0.0";
                }

                # Update to %games
                $gamedata[$i] = $commands[3];
                $games{$commands[1]} = join(',', @gamedata);

                $wasreplaced = 1;
            }
        }

        if ($wasreplaced == 1) {
            $self->emote(channel => $chan,
                         body => "Replaced $commands[2] with player $commands[3] " .
                                 "(in game #$commands[1])");
        } else {
            $self->emote(channel => $chan,
                         body => "Player $commands[2] was not found " .
                                 "(in game #$commands[1].");
        }

        return;
    }


    # command .games
    elsif ($commands[0] eq '!games') {

        my $activegames = getactivegames();
        my $outline = "";

        if ($activegames eq '') {
            $outline = "No ongoing games.";
        } else {
            $outline = "Ongoing games: $activegames";
        }

        $self->emote(channel => $chan, body => $outline);
        return;
    }


    # command .accesslevel
    elsif ($commands[0] eq '!accesslevel') {

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "$who is not an admin.");
            return;
        }

        if ($#commands < 2 ||
            $commands[2] ne 'admin' && $commands[2] ne 'user') {

                $self->emote(channel => $chan,
                             body => "Syntax is $commands[0] <username> <admin|user>");
                return;
        }

        # Case new user
        if (! exists($users{$commands[1]}) ) {
            $users{$commands[1]} = "$commands[2].$initialpoints.0.0.0";

            $self->emote(channel => $chan,
                         body => "$commands[1] is now an $commands[2].");
            return;
        }

        # Case existing user
        my @uservalues = split('\.', $users{$commands[1]});
        my $currentaccess = $uservalues[0];

        if ($currentaccess eq $commands[2]) {
            $self->emote(channel => $chan,
                         body => "$commands[1] is already an $commands[2].");
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
                    $self->emote(channel => $chan,
                                 body => "$who is not an original admin.");
                    return ;
                }
            }

            $uservalues[0] = $commands[2];
            $users{$commands[1]} = join('.', @uservalues);

            $self->emote(channel => $chan,
                         body => "$commands[1] is now an $commands[2].");
        }

        return;
    }


    # command .resetstats
    elsif ($commands[0] eq '!resetstats') {

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "$who is not an admin.");
            return;
        }

        if ($#commands != 1) {
            $self->emote(channel => $chan,
                            body => "Syntax is $commands[0] <username> <admin|user>");
        }

        if (! exists($users{$commands[1]}) ) {
            $users{$commands[1]} = "user.$initialpoints.0.0.0";

            $self->emote(channel => $chan,
                         body => "$commands[1]'s stats have been reseted.");
            return;
        }

        my @uservalues = split('\.', $users{$commands[1]});
        $uservalues[1] = "$initialpoints";
        $uservalues[2] = "0";
        $uservalues[3] = "0";
        $uservalues[4] = "0";
        $users{$commands[1]} = join('.', @uservalues);

        $self->emote(channel => $chan,
                     body => "$commands[1]'s stats have been reseted.");
        return;
    }


    # command .voidgame
    elsif ($commands[0] eq '!voidgame') {

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "$who is not an admin.");
            return;
        }

        if ($#commands != 1) {
            $self->emote(channel => $chan,
                        body => "Syntax is $commands[0] <gameno>");
            return;
        }

        if (! exists($games{$commands[1]}) ) {
            $self->emote(channel => $chan,
                    body => "Game #$commands[1] was not found.");
            return;
        }

        # Get the gamedata
        my @gamedata = split(',', $games{$commands[1]});

        # Check if game is still actie
        if ( index($gamedata[0], 'active') != -1 ) {
            $self->emote(channel => $chan,
                         body => "Game #$commands[1] is still active.");
            return;
        }

        # Get result from gamedata
        my @result = split(':', $gamedata[3]);

        # Find out what was the maxplayers and teamsize
        my $wasmaxplayers = ($#gamedata+1) -4;
        my $wasteamsize = $wasmaxplayers / 2;

        my @userinfo;

        if ($result[1] == 1) {

            for my $i (4 .. 3+$wasteamsize) {
                @userinfo = split('\.', $users{$gamedata[$i]});
                $userinfo[1] -= $pointsonwin;
                $userinfo[2]--;
                $users{$gamedata[$i]} = join('.', @userinfo);
            }

            for my $i (4+$wasteamsize .. 3+$wasmaxplayers) {
                @userinfo = split('\.', $users{$gamedata[$i]});
                $userinfo[1] -= $pointsonloss;
                $userinfo[3]--;
                $users{$gamedata[$i]} = join('.', @userinfo);
            }

        } elsif ($result[1] == 2) {
            for my $i (4 .. 3+$wasteamsize) {
                @userinfo = split('\.', $users{$gamedata[$i]});
                $userinfo[1] -= $pointsonloss;
                $userinfo[3]--;
                $users{$gamedata[$i]} = join('.', @userinfo);
            }

            for my $i (4+$wasteamsize .. 3+$wasmaxplayers) {
                @userinfo = split('\.', $users{$gamedata[$i]});
                $userinfo[1] -= $pointsonwin;
                $userinfo[2]--;
                $users{$gamedata[$i]} = join('.', @userinfo);
            }

        } elsif ($result[1] == 3) {
            for my $i (4 .. 3+$wasmaxplayers) {
                @userinfo = split('\.', $users{$gamedata[$i]});
                $userinfo[1] -= $pointsondraw;
                $userinfo[4]--;
                $users{$gamedata[$i]} = join('.', @userinfo);
            }

        } else {
            print STDERR "Internal data corruption!\n";
        }

        delete($games{$commands[1]});

        $self->emote(channel => $chan, body => "Game #$commands[1] voided.");
        return;
    }


    # command .changename
    elsif ($commands[0] eq '!changename') {

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "$who is not an admin.");
            return;
        }

        if ($#commands != 2) {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] <current_name> <new_name>");
            return;
        }

        if (! exists($users{$commands[1]}) ) {
            $self->emote(channel => $chan,
                         body => "$commands[1] was not found.");
            return;
        }

        if ( exists($users{$commands[2]}) ) {
            $self->emote(channel => $chan,
                         body => "A user named $commands[2] already exists.");
            return;
        }

        $users{$commands[2]} = $users{$commands[1]};
        delete($users{$commands[1]});

        $self->emote(channel => $chan,
                     body => "$commands[1] is now renamed to $commands[2]");
        return;
    }

    # command .combineusers
    elsif ($commands[0] eq '!combineusers') {

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "$who is not an admin.");
            return;
        }

        if ($#commands < 2) {
            $self->emote(channel => $chan,
                         body => "$commands[0] combines the data of two users " .
                                 "into one user and deletes the other account.");

            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] " .
                                 "<remaining_name> <name-to-be-removed>");
            return;
        }

        if (! exists($users{$commands[1]}) ) {
            $self->emote(channel => $chan,
                         body => "User $commands[1] was not found.");
            return;
        }

        if (! exists($users{$commands[2]}) ) {
            $self->emote(channel => $chan,
                         body => "User $commands[2] was not found.");
            return;
        }

        my @user1_data = split('\.', $users{$commands[1]});
        my @user2_data = split('\.', $users{$commands[2]});

        # If user2 is an admin, make sure the new account will be
        # admin as well. Otherwise, don't do changes to the accesslevel.
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
        delete($users{$commands[2]});

        $self->emote(channel => $chan,
                     body => "The stats of $commands[1] and $commands[2] are now" .
                             "combined. User $commands[2] deleted.");
        return;
    }


    # command .rank
    elsif ($commands[0] eq '!rank' || $commands[0] eq '!top') {

        if ($commands[0] eq '!rank') {
            if ($#commands > 0) {
                $who = $commands[1];
            }

            if (! exists($users{$who}) ) {
                $self->emote(channel => $chan, body => "$who was not found.");
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
            if ($playedmatches > 0) {
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

        if ($commands[0] eq '!rank') {
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
                $outline = "$who is ranked $usersrank with points $temp[1]";
            } else {
                $outline = "$who is not ranked yet.";
            }

        } else { # if command was .top

            if ($#ranklist == -1) {
                $self->say(channel => $chan,
                           body => "Rank list is empty.");
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
                $outline .= $i+1 . ". $arr[0]\($arr[1]\), ";
            }
            chop $outline, chop $outline;

            if ($listlength > $topdefaultlength) {
                $self->say(channel => "msg", who => $who, body => $outline);
                return;
            }
        }

        $self->emote(channel => $chan, body => $outline);
        return;
    }


    # command .shutdownbot
    elsif ($commands[0] eq '!shutdownbot') {

        my $originaladmin = 0;
        for my $admin (@admins) {
            if ($who eq $admin) {
                $originaladmin = 1;
            }
        }

        if ($originaladmin == 0) {
            $self->emote(channel => $chan,
                         body => "$who is not an original admin.");
            return;
        }

        $self->writedata();
        $self->writecfg();
        $self->shutdown();
        return;
    }


    # command .commands
    elsif ($commands[0] eq '!commands' || $commands[0] eq '!commandlist' ||
           $commands[0] eq '!cmdlist' ||$commands[0] eq '!cmds' || $commands[0] eq '!help') {

        if ($#commands == 1 && $commands[1] eq 'verbose') {
            my $adddesc = "           = Signs you up for the game.";
            my $listdesc = "          = Shows you list of signed up players.";
            my $outdesc = "           = Signs you out from the game. In addition, you can request an another player to be removed.";
            my $votemapdesc = "       = Syntax is .votemap <mapname>. More info with .votemap";
            my $votecaptaindesc = "   = Syntax is .votecaptain <playername>. More info with .votecaptain";
            my $captaindesc = "       = Makes you a captain. Command is only available if there is a free captain slot.";
            my $uncaptaindesc = "     = Frees the captain slot from you. You must of course have made yourself a captain with .captain";
            my $rafflecaptaindesc = " = Requests the raffling of new captain instead of the current captain. Available after the picking of players has started. More info with .rafflecaptain";
            my $serverdesc = "        = Prints the game server info.";
            my $mumbledesc = "        = Prints the mumble server info.";
            my $pickdesc = "          = Captain's command to pick a player in his team.";
            my $reportdesc = "        = You can request a score for a game with this command. More info with .report";
            my $statsdesc = "         = Prints your stats (or someone else's stats with .stats playername)";
            my $lastgamedesc = "      = Prints the info on the last game that was started.";
            my $gameinfodesc = "      = Syntax is .gameinfo <gameno>. Prints the info of the given game.";
            my $replacedesc = "       = You can request a player to be replaced with another player with this command. More info with .replace";
            my $gamesdesc = "         = Prints the game numbers of the games that are active.";
            my $rankdesc = "          = Prints your ranking (or someone else's with .rank playername)";
            my $topdesc = "           = Prints a list of top ranked players. You can define the length of the list with .top <length>";
            my $hl_offdesc = "        = Puts you into hilight-ignore, (you're no longer hilighted on command .hilight)";
            my $hl_ondesc = "         = Removes you from the hilight-ignore (you can again be hilighted on command .hilight)";
            my $whoisdesc = "         = Prints your (or someone else's) username and accesslevel.";
            my $admincommandsdesc = " = (Admins only) Gives a list of commands available to admins as a private message.";

            $self->say(channel => "msg", who => $who, body => "!add $adddesc");
            $self->say(channel => "msg", who => $who, body => "!list $listdesc");
            $self->say(channel => "msg", who => $who, body => "!out $outdesc");
            $self->say(channel => "msg", who => $who, body => "!votemap $votemapdesc");
            $self->say(channel => "msg", who => $who, body => "!votecaptain $votecaptaindesc");
            $self->say(channel => "msg", who => $who, body => "!captain $captaindesc");
            $self->say(channel => "msg", who => $who, body => "!uncaptain $uncaptaindesc");
            $self->say(channel => "msg", who => $who, body => "!rafflecaptain $rafflecaptaindesc");
            $self->say(channel => "msg", who => $who, body => "!server $serverdesc");
            $self->say(channel => "msg", who => $who, body => "!mumble $mumbledesc");
            $self->say(channel => "msg", who => $who, body => "!pick $pickdesc");
            $self->say(channel => "msg", who => $who, body => "!report $reportdesc");
            $self->say(channel => "msg", who => $who, body => "!stats $statsdesc");
            $self->say(channel => "msg", who => $who, body => "!lastgame $lastgamedesc");
            $self->say(channel => "msg", who => $who, body => "!gameinfo $gameinfodesc");
            $self->say(channel => "msg", who => $who, body => "!replace $replacedesc");
            $self->say(channel => "msg", who => $who, body => "!games $gamesdesc");
            $self->say(channel => "msg", who => $who, body => "!rank $rankdesc");
            $self->say(channel => "msg", who => $who, body => "!top $topdesc");
            $self->say(channel => "msg", who => $who, body => "!hl off $hl_offdesc");
            $self->say(channel => "msg", who => $who, body => "!hl on $hl_ondesc");
            $self->say(channel => "msg", who => $who, body => "!whois $whoisdesc");
            $self->say(channel => "msg", who => $who, body => "!admincommands $admincommandsdesc");

            return;
        }

        my $outline = "Commands are !add !list !out !votemap !votecaptain !captain !uncaptain " .
                      "!rafflecaptain !server !mumble !pick !report !stats !lastgame " .
                      "!gameinfo !replace !games !rank !top !hl off/on !whois !admincommands ";

        $self->emote(channel => $chan, body => $outline);
        $self->emote(channel => $chan, body => "To get descriptions of the commands. " .
                                               "use $commands[0] verbose");
        return;
    }


    # command .admincommands
    elsif ($commands[0] eq '!admincommands') {

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan, body => "$who is not an admin.");
            return;
        }

        my $adddesc = "            = Signs a player in the game. Syntax is .add <playername>";
        my $outdesc = "            = Signs a player out from the game. Syntax is .out <playername>";
        my $abortdesc = "          = Aborts the sign-up and clears the player list.";
        my $captaindesc = "        = You can make someone a captain with this command, supposing that there's a free captain slot and that the player is signed up.";
        my $uncaptaindesc = "      = Frees a captain slot from someone. Syntax is .uncaptain <captains_name>. After the picking has started, use .changecaptain or rafflecaptain.";
        my $changecaptaindesc = "  = You can change the captain with this command under any circumstances. Syntax is .changecaptain <curr_captain> <new_captain>.";
        my $rafflecaptaindesc = "  = You can make the bot raffle a new captain to replace a current captain, supposing that the picking has started. Syntax is .rafflecaptain <captains_name>.";
        my $replacedesc = "        = Replaces a player in the signup or in a game that already started. More info on .replace";
        my $aoedesc = "            = Sends a private irc-notice to everyone on the channel about the status of the signup. ";
        my $hilightdesc = "        = Highlights everyone on the channel at once.";
        my $reportdesc = "         = Sets the score of a game. Syntax is .report <gameno> <$team1|$team2|$draw>";
        my $voidgamedesc = "       = Voids a game (as in like it was never played). Syntax is .voidgame <gameno>";
        my $accessleveldesc = "    = Sets the given user's accesslevel to the given level. Syntax is .accesslevel <username> <admin|user>";
        my $changenamedesc = "     = Change the given user's username. Syntax is .changename <current_name> <new_name>";
        my $combineusersdesc = "   = Combines the stats of two players and deletes the other user. Syntax is .combineusers <user-to-remain> <user-to-be-deleted>";
        my $resetstatsdesc = "     = Resets the given user's stats. Syntax is .resetstats <username>";
        my $setdesc = "            = Sets the value of the given variable or prints its current value of a value is not given. Syntax is .set <variable> <value>. List of variables on .set list";
        my $addmapdesc = "         = Adds a map into the map pool.";
        my $removemapdesc = "      = Removes a map from the map pool.";
        my $shutdownbotdesc = "    = (Original admin only) Saves all data and shuts the bot down.";

        $self->say(channel => "msg", who => $who, body => "!add $adddesc");
        $self->say(channel => "msg", who => $who, body => "!out $outdesc");
        $self->say(channel => "msg", who => $who, body => "!abort $abortdesc");
        $self->say(channel => "msg", who => $who, body => "!captain $captaindesc");
        $self->say(channel => "msg", who => $who, body => "!uncaptain $uncaptaindesc");
        $self->say(channel => "msg", who => $who, body => "!rafflecaptain $rafflecaptaindesc");
        $self->say(channel => "msg", who => $who, body => "!replace $replacedesc");
        $self->say(channel => "msg", who => $who, body => "!aoe $aoedesc");
        $self->say(channel => "msg", who => $who, body => "!hilight $hilightdesc");
        $self->say(channel => "msg", who => $who, body => "!report $reportdesc");
        $self->say(channel => "msg", who => $who, body => "!voidgame $voidgamedesc");
        $self->say(channel => "msg", who => $who, body => "!accesslevel $accessleveldesc");
        $self->say(channel => "msg", who => $who, body => "!changename $changenamedesc");
        $self->say(channel => "msg", who => $who, body => "!combineusers $combineusersdesc");
        $self->say(channel => "msg", who => $who, body => "!resetstats $resetstatsdesc");
        $self->say(channel => "msg", who => $who, body => "!set $setdesc");
        $self->say(channel => "msg", who => $who, body => "!addmap $addmapdesc");
        $self->say(channel => "msg", who => $who, body => "!removemap $removemapdesc");
        $self->say(channel => "msg", who => $who, body => "!shutdownbot $shutdownbotdesc");

        return;
    }

    # command .addmap
    elsif ($commands[0] eq '!addmap') {

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "$who is not an admin.");
            return;
        }

        if ($#commands < 1) {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] <mapname>");
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

            $self->emote(channel => $chan,
                        body => "\"$commands[1]\" added to the map pool.");

        } else {
            $self->emote(channel => $chan,
                         body => "Mappi \"$commands[1]\" is already in the map pool.");
        }

        return;
    }


    # command .removemap
    elsif ($commands[0] eq '!removemap') {

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "$who is not an admin.");
            return;
        }

        if ($#commands < 1) {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] <mapname>");
            return;
        }

        for my $i (0 .. $#maps) {
            if ($maps[$i] eq $commands[1]) {
                splice(@maps, $i, 1);

                $self->emote(channel => $chan,
                             body => "\"$commands[1]\" removed from the map pool.");
                return;
            }
        }

        return;
    }


    # command .set
    elsif ($commands[0] eq '!set') {

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "$who is not an admin.");
            return;
        }

        if ($#commands == 0) {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] <variable> <value>");

            $self->emote(channel => $chan,
                         body => "Use $commands[0] list to get a list of the variables");
            return;
        }

        my $outline = "";

        if ($#commands > 0 && $commands[1] eq 'list') {
            $outline = "Variables: team1, team2, draw, maxplayers, gameserverip, " .
                       "gameserverport, gameserverpw, voiceserverip, " .
                       "voiceserverport, voiceserverpw, neededvotes_captain, " .
                       "neededvotes_map, neededreq_replace, neededreq_remove, " .
                       "neededreq_score, neededreq_rafflecapt, initialpoints, ";
            $self->emote(channel => $chan, body => $outline);

            $outline = "pointsonwin, pointsonloss, pointsondraw, topdefaultlength, " .
                       "gamehascaptains, gamehasmap, votecaptaintime, votemaptime, " .
                       "mutualvotecaptain, mutualvotemap, printpoolafterpick, " .
                       "givegameserverinfo, givevoiceserverinfo, showinfointopic, " .
                       "topicdelimiter";
            $self->emote(channel => $chan, body => $outline);

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
            elsif ($commands[1] eq 'initialpoints')        { $outline = "$commands[1] = $initialpoints"; }
            elsif ($commands[1] eq 'pointsonwin')          { $outline = "$commands[1] = $pointsonwin"; }
            elsif ($commands[1] eq 'pointsonloss')         { $outline = "$commands[1] = $pointsonloss"; }
            elsif ($commands[1] eq 'pointsondraw')         { $outline = "$commands[1] = $pointsondraw"; }
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
            else {
                $self->emote(channel => $chan,
                             body => "Invalid variable name.");
                return;
            }

            $self->emote(channel => $chan, body => $outline);
            return;
        }

        my $validvalue = 1;

        # Combine @commands[2 .. n] into one string
        # (to be able to have whitespace in $team1 etc)
        my @cmdarr;
        my $cmdstring = "";
        for my $i (2 .. $#commands) {
            push @cmdarr, $commands[$i];
        }
        $cmdstring = join ' ', @cmdarr;

        if    ($commands[1] eq 'team1')          { $team1 = $cmdstring; }
        elsif ($commands[1] eq 'team2')          { $team2 = $cmdstring; }
        elsif ($commands[1] eq 'draw')           { $draw = $cmdstring;}
        elsif ($commands[1] eq 'gameserverip')   { $gameserverip = $commands[2]; }
        elsif ($commands[1] eq 'gameserverpw')   { $gameserverpw = $commands[2]; }
        elsif ($commands[1] eq 'voiceserverip')  { $voiceserverip = $commands[2]; }
        elsif ($commands[1] eq 'voiceserverpw')  { $voiceserverpw = $commands[2]; }
        elsif ($commands[1] eq 'topicdelimiter') { $topicdelimiter = $cmdstring; }

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

        else {
            $self->emote(channel => $chan,
                         body => "Invalid variable name");
            return;
        }


        if ($validvalue == 1) {
            $self->emote(channel => $chan,
                         body => "Variable $commands[1] is now set to $commands[2].");
            return;

        } else {
            $self->emote(channel => $chan,
                         body => "Invalid value given for variable $commands[1].");
            return;
        }

        return;
    }


    # command .aoe
    elsif ($commands[0] eq '!aoe') {

        if ($accesslevel ne 'admin') {
            $self->emote(channel => $chan,
                         body => "$who is not an admin.");
            return;
        }

        $self->say(channel => "msg", who => "Q", body => "CHANMODE $chan -N");

        my $playercount = $#players+1;
        my $noticemessage = "$chan - sign-up for gather is on! " .
                            "$playercount/$maxplayers players have signed up.";

        my $chandata = $self->channel_data($chan);
        foreach my $nick_ (keys %$chandata) {
            $self->notice(channel => "msg", who => $nick_, body => $noticemessage);
        }

        $self->say(channel => "msg", who => "Q", body => "CHANMODE $chan +N");

        return;
    }


    # command .hilight
    elsif ($commands[0] eq '!hilight' || $commands[0] eq '!hl') {

        if ($#commands == 0) {
            if ($accesslevel ne 'admin') {
                $self->emote(channel => $chan,
                             body => "$who is not an admin.");
                return;
            }

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
                    push(@nicks, $nick_);
                }
            }

            my $hilightline = join(' ', @nicks);
            $self->emote(channel => $chan, body => $hilightline);

            return;
        }


        if ($commands[1] ne 'off' && $commands[1] ne 'on') {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] <off|on>");
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
                $self->emote(channel => $chan,
                             body => "$who is already in hilight-ignore.");

            } else {
                push(@hlignorelist, $who);

                $self->emote(channel => $chan,
                             body => "$who is now in hilight-ignore.");
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
                $self->emote(channel => $chan,
                             body => "$who was not in hilight-ignore.");

            } else {
                $self->emote(channel => $chan,
                             body => "$who is no longer in hilight-ignore.");
            }

            return;
        }

        return;
    }


    # command .captains
    elsif ($commands[0] eq '!captains') {

        if ($gamehascaptains == 0) {
            $self->emote(channel => $chan,
                         body => "Command $commands[0] is not enabled " .
                                 "(gamehascaptains = 0)");
            return;
        }

        my @captains;

        if ($captain1 ne '') {
            push(@captains, $captain1);
        }

        if ($captain2 ne '') {
            push(@captains, $captain2);
        }

        if ($#captains == -1) {
            $self->emote(channel => $chan,
                         body => "There are no captains at the moment.");
            return;
        }

        my $captainsstr = join(', ', @captains);

        $self->emote(channel => $chan,
                     body => "The captains are: $captainsstr.");

        return;
    }


    # command .teams
    elsif ($commands[0] eq '!teams') {

        if ($#team1 == -1 && $#team2 == -1) {
            $self->emote(channel => $chan,
                         body => "The teams are empty.");

            return;
        }

        # Print the teams
        my $team1list = $self->formatteam(@team1);
        my $team2list = $self->formatteam(@team2);
        my $team1pts = calcteampoints(@team1);
        my $team2pts = calcteampoints(@team2);
        $self->emote(channel => $chan, body => "$team1 ($team1pts" . "p" . "): $team1list");
        $self->emote(channel => $chan, body => "$team2 ($team2pts" . "p" . "): $team2list");

        return;
    }


    # command .turn
    elsif ($commands[0] eq '!turn') {

        if ($gamehascaptains == 0) {
            $self->emote(channel => $chan,
                         body => "Command $commands[0] is not enabled " .
                                 "(gamehascaptains = 0)");
            return;
        }

        if ($canpick == 0) {
            $self->emote(channel => $chan,
                         body => "Picking of players has not started.");
            return;
        }

        my $picker = "";

        if ($turn == 1) {
            $picker = $captain1;
        } else {
            $picker = $captain2;
        }

        $self->emote(channel => $chan,
                     body => "$picker" . "'s turn to pick.");

        return;
    }


    # command .hasauth
    elsif ($commands[0] eq '!hasauth') {

        if ($#commands < 1) {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] <username>");

            return;
        }



        if (! exists $qauths{$commands[1]} ) {
            $self->emote(channel => $chan,
                         body => "No Q-auth info for user $commands[1]");
        } else {
            $self->emote(channel => $chan,
                         body => "$commands[1] is authed to Q " .
                                 "on account $qauths{$commands[1]}");
        }

        return;
    }

    # command .lookupauth (debugging cmd)
    elsif ($commands[0] eq '!lookupauth') {

        if ($#commands < 1) {
            $self->emote(channel => $chan,
                         body => "Syntax is $commands[0] <username>");
            return;
        }

        $self->whoisuser_to_q($commands[1]);

        return;
    }

    # command .foo
    elsif ($commands[0] eq '!foo') {
        return;
    }

}

sub resetmaxplayers {
    $maxplayers = $_[0];

    setneededvotes_captain($maxplayers/2);
    setneededvotes_map($maxplayers/2);
    setneededreq_replace($maxplayers/2);
    setneededreq_remove($maxplayers/2);
    setneededreq_score($maxplayers/2);
    setneededreq_rafflecapt($maxplayers/2);

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


    # Void all remove requests that are related to the given user
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
        $randindex = int(rand($playercount));
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
        $randindex = int(rand($playercount));
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
    $self->emote(channel => $chan,
                 body => "The captains are $captain1 and $captain2.");

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

    # Make the newly raffled player the captain
    # and put him in his team
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

    $self->emote(channel => $chan,
                 body => "The picking of players is about to start.");

    my $list= $self->formatplayerlist(@players);

    $self->emote(channel => $chan,
                 body => "Player pool: $list");


    # Set channel to moderated and give +v to captains
    #$self->mode("$chan +m");
    #$self->mode("$chan +v $captain1");
    #$self->mode("$chan +v $captain2");

    $self->emote(channel => $chan,
                 body => "$captain2's turn to pick.");

    $canpick = 1;
    $turn = 2;

    return;
}

sub startgame {
    my $self = shift;

    # - STARTING THE GAME -

    # Increment game number
    $gamenum++;

    $self->emote(channel => $chan,
                 body => "Game #$gamenum begins!");

    # Print the teams
    my $team1list = $self->formatteam(@team1);
    my $team2list = $self->formatteam(@team2);
    my $team1pts = calcteampoints(@team1);
    my $team2pts = calcteampoints(@team2);
    $self->emote(channel => $chan, body => "$team1 ($team1pts" . "p" . "): $team1list");
    $self->emote(channel => $chan, body => "$team2 ($team2pts" . "p" . "): $team2list");

    # If the game has a map, print it
    if ($gamehasmap == 1) {
        $self->emote(channel => $chan,
                     body => "Map: $chosenmap");
    }

    if ($givegameserverinfo == 1) {
        $self->printserverinfo();
    }

    if ($givevoiceserverinfo == 1) {
        $self->printvoipinfo();
    }

    # Add game to the gamedata
    # my $dt = DateTime->now(time_zone=>'Europe/Helsinki');
    my $dt = DateTime->now();
    my $ept = $dt->epoch();

    my $gamedataline = "$gamenum:active,time:$ept,map:$chosenmap,result:,";
    $team1list = join(",", @team1);
    $team2list = join(",", @team2);
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

sub mode {
   my $self = shift;
   my $mode = join ' ', @_;

   $poe_kernel->post ($self->{ircnick} => mode => $mode);
}


sub formatplayerlist {
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
            @userdata = split('\.', $users{$player});

            $playedmatches = $userdata[2] + $userdata[3] + $userdata[4];

            # If the user has 0 played matches
            if ($playedmatches == 0) {
                $append .= "(" . "\x0312" . "Rookie" . "\x0f" . ")";

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

    if ($points < 1000) {
        return "\x0304" . "$points\x0f";

    } elsif ($points == 1000) {
         return "\x0308" . "$points\x0f";

    } elsif ($points > 1000) {
        return "\x0303" . "$points\x0f";
    }

    return $points;
}

sub calcteampoints {
    my @userdata;
    my $totalpoints = 0;

    for my $player (@_) {
        @userdata = split '\.', $users{$player};
        $totalpoints += $userdata[1];
    }

    return $totalpoints;
}

sub formatteam {
    my $self = shift;
    my @team = @_;

    my @formattedteam;
    for my $player (@team) {
        push(@formattedteam, $player);
    }

    if ($#formattedteam > -1) {
        $formattedteam[0] .= "[C]";
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

    if ($value =~ /[\p{L}]+/) {  # check if the given parameter contains any letters
        return 1;
    }
    return 0;
}

sub printserverinfo {
    my $self = shift;

    if ($gameserverip eq "") {
        return;
    }

    $self->emote(channel => $chan,
                 body => "Gameserver: $gameserverip:$gameserverport - " .
                         "password: $gameserverpw");
    return;
}

sub printvoipinfo {
    my $self = shift;

    if ($voiceserverip eq "") {
        return;
    }

    $self->emote(channel => $chan,
                 body => "Mumble: $voiceserverip:$voiceserverport - " .
                         "password: $voiceserverpw");
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
            print STDERR "existing matching qauth info for nick $ircnick\n";
            return;
        }

        # If there's existing qauth info on this nick
        # but for a different authname, announce overwrite
        if ( exists($qauths{$ircnick}) && $qauths{$ircnick} ne $authname) {
            print STDERR "going to overwrite qauth info for nick $ircnick " .
                            "(oldauth=$qauths{$ircnick} newauth=$authname)\n";
        }

        # If there's existing info for this authname
        # but on a different irc-nick, delete the info
        # and change the user's name in userdata
        foreach (keys %qauths) {
            if ($qauths{$_} eq $authname && $ircnick ne $_) {

                print STDERR "deleting qauth info for nick $_ (auth=$qauths{$_})\n";

                # Delete the existing qauth info
                delete $qauths{$_};

                # Copy the user's data under the new
                # name and delete the old data
                $users{$ircnick} = $users{$_};
                delete($users{$_});

                $self->emote(channel => $chan,
                             body => "$ircnick was identified as user $_ via " .
                                     "Q-auth info; username changed to $ircnick");

                last;
            }
        }

        # Add (or overwrite) the qauth info
        $qauths{$ircnick} = $authname;
        print STDERR "added qauth info for nick $ircnick (auth=$authname)\n";
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
    # parse the user-set part of topic and
    # save it as the default topic
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

sub updatetopic {
    my $self = shift;

    if ($showinfointopic == 0) {
        return;
    }

    my $topic = $defaulttopic;

    $topic .= get_topicplayerstr();
    $topic .= get_topicgamesstr();

    # print STDERR "newtopic: $topic\n";

    my $poeself = $self->pocoirc();
    $poe_kernel->post($poeself->session_id() => topic => $chan => $topic);

    return;
}

sub get_topicplayerstr {
    my $outline = "";

    if ($#players < 0) {
        return $outline;
    }

    $outline .= " $topicdelimiter Captains: ";

    my @captains;

    if ($captain1 ne '') {
        push(@captains, $captain1);
    } else {
        push(@captains, "x");
    }

    if ($captain2 ne '') {
        push(@captains, $captain2);
    } else {
        push(@captains, "x");
    }

    my $cptstr = join ', ', @captains;
    $outline .= "($cptstr)";

    my @plist;

    # Populate @plist with non-captain players
    for my $i (0 .. $#players) {
        if ($players[$i] ne $captain1 && $players[$i] ne $captain2) {
            push(@plist, $players[$i])
        }
    }

    # Populate the rest of @plist with x's
    for my $i ($#plist+1 .. $maxplayers-3) {
        push(@plist, "x")
    }

    my $playerstr = join ', ', @plist;
    $outline .= " Players: ($playerstr)";

    return $outline;
}

sub get_topicgamesstr {
    my $outline = "";

    my $activegames = getactivegames();

    if ($activegames ne '') {
        $outline .= " $topicdelimiter Ongoing games: $activegames";
    }

    return $outline;
}

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

        # Get the highest game number and put it to gamenum
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
            # print STDERR "= jalkeinen osa: $elements[1]\n";
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
            elsif ($elements[0] eq 'initialpoints')        { $initialpoints = $elements[1]; }
            elsif ($elements[0] eq 'pointsonwin')          { $pointsonwin = $elements[1]; }
            elsif ($elements[0] eq 'pointsonloss')         { $pointsonloss = $elements[1]; }
            elsif ($elements[0] eq 'pointsondraw')         { $pointsondraw = $elements[1]; }
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

sub writecfg {
    my $cfgfilename = 'gatherbot.cfg';
    my $cfgfile;

    unless (open $cfgfile, '>', $cfgfilename
            or die "error while overwriting file $cfgfilename: $!") {
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
                   "initialpoints        = $initialpoints\t\t\t$initialpointsdesc\n" .
                   "pointsonwin          = $pointsonwin\t\t\t$pointsonwindesc\n" .
                   "pointsonloss         = $pointsonloss\t\t\t$pointsonlossdesc\n" .
                   "pointsondraw         = $pointsondraw\t\t\t$pointsondrawdesc\n" .
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
                   "topicdelimiter       = $topicdelimiter\t\t\t$topicdelimiterdesc\n";
    return;
}


readcfg();
readdata();

GatherBot->new(
    server =>   $server,
    channels => [ "$chan" ],
    nick =>     $nick,
    flood =>    0,
)->run();
