#!/usr/bin/perl
use strict;
use warnings;
use utf8;

# This bot is designed only to handle gather matches

package GatherBot;
use base qw(Bot::BasicBot);
use POE;

# Bot related settings, settings in gatherbot.cfg override these (if they exist)
my $server   = 'se.quakenet.org';
my $chan     = 'BotTestChan';
my $nick     = 'MyGatherBot';
my $authname = '';
my $authpw   = '';

# Gather related settings, settings in gatherbot.cfg override these (if they exist)
my $team1             = 'Team1';
my $team2             = 'Team2';
my $draw              = 'Draw';
my $maxplayers        = 10;
my @admins            = qw(admin1);
my @maps              = qw(map1 map2 map3);
my $gameserverip      = '';
my $gameserverport    = '';
my $gameserverpw      = '';
my $voiceserverip     = '';
my $voiceserverport   = '';
my $voiceserverpw     = '';
my $requeststoreplace = 3;      # amount of requests needed by non-admins to replace someone
my $requeststoremove  = 3;      # amount of requests needed by non-admins to remove someone
my $requeststoscore   = 3;      # amount of requests needed by non-admins to report a score
my $initialpoints     = 1000;   # the skill points everyone starts with
my $pointsdelta       = 10;     # the skill points change on won/lost game
my $topdefaultlength  = 10;     # the default length of .top list

# Other vars (not to be changed)
my $gamenum = 3;
my $mapvotecount = 0;
my $teamsize = $maxplayers/2;
my $canadd = 1;
my $canout = 1;
my $cancaptain = 1;
my $canvotemap = 0;
my $canpick = 0;
my $captain1 = "";
my $captain2 = "";
my $cfgheader = '';
my $turn = 0;
my $lastturn = 0;
my $requestsfornewcapt;
my $team1captrequests = "";
my $team2captrequests = "";
my @players;
my @team1;
my @team2;
my @hlignorelist;
my %mapvotes;
my %mapvoters;
my %replacereq;
my %removereq;
my %userscorereq;
my %captainscorereq;
my %users;
my %games;


=for comment
    $self->say(
        who =>     'Q@CServe.quakenet.org',
        channel => 'msg',
        body =>    "AUTH $authname $authpw",
        address => 'false'
    );
=cut


sub connected {
    my $self = shift;

    # -IMPORTANT- In order to be admin, uncomment when running the 1st time
    # -IMPORTANT- Comment again afterwards to preserve your stats
    #
    # for my $name (@admins) {
    #     $users{$name} = "admin.$initialpoints.0.0.0";
    # }
    
    for my $map (@maps) {
        $mapvotes{$map} = 0;
    }
    
    # Uncomment to enable Q-Auth
    #$self->say(
    #    who =>     'Q@CServe.quakenet.org',
    #    channel => 'msg',
    #    body =>    "AUTH $authname $authpw",
    #    address => 'false'
    #);
}

sub said {
    my $self = shift;
    my $message = shift;
    my $who = $message->{who};
    my $channel = $message->{channel};
    my $body = $message->{body};
    my $address = $message->{address};
    
    
    # Unless the message was received from the channel
    # that was set in $chan, return
    if ($channel ne $chan) {
        return;
    }
    
    # Unless the message starts with a dot, return
    if (substr($body, 0, 1) ne '.') {
        return;
    }
    
    # Split the message by whitespace to get
    # the command and its parameters
    my @commands = split(' ', $body);
    
    # If user doesn't exist in userdata, add him
    if (! exists($users{$who}) ) {
        $users{$who} = "user.$initialpoints.0.0.0";
    }
    
    my @userstring = split('\.', $users{$who});
    my $accesslevel = $userstring[0];
    
    
    # command .add
    if ($commands[0] eq '.add' || $commands[0] eq '.sign') {
    
        if ($canadd == 0) {
            $self->emote(channel => "$chan",
                         body => "Ilmoittautuminen on tällä hetkellä kiinni.");
            return;
        }

        my $tbadded;
        if ($#commands == 0) {
            $tbadded = "$who";
            
        } else {
            if ($accesslevel eq 'admin') {
                $tbadded = "$commands[1]";
                
                if (! exists($users{$tbadded}) ) {
                    $users{$tbadded} = "user.$initialpoints.0.0.0";
                }
                
            } else {
                $self->emote(channel => "$chan",
                             body => "$who ei ole admin.");
                return;
            }
        }
        
        # Check if he is already signed
        for my $player (@players) {
            if ($player eq $tbadded) {
                $self->emote(channel => "$chan",
                             body => "$tbadded on jo ilmoittautunut peliin.");
                return;
            }
        }

        # Add the player on the playerlist
        push(@players, "$tbadded");
        my $playercount = $#players+1;
        
        $self->emote(channel => "$chan",
                     body => "$tbadded ilmoittautui peliin. " .
                             "Pelaajia on $playercount/$maxplayers");
        
        if ($playercount == 1) {
            $canvotemap = 1;
        }
        
        # If there aren't enough players to start the game, return.
        # Otherwise, start the game.
        if ($playercount < $maxplayers) {
            return;
        }
        
        $canadd = 0;
        $canout = 0;
        $cancaptain = 0;
        $canvotemap = 0;
        
        my $randindex;
        
        # Raffle captain for team1, if needed
        if ($captain1 eq "") {
            $randindex = int(rand($playercount));
            $captain1 = $players[$randindex];
        }
        
        # Remove captain1 from player pool
        # and add him in his team
        for my $i (0 .. $#players) {
            if ($players[$i] eq $captain1) {
                splice(@players, $i, 1);
                $playercount--;
                last;
            }
        }
        push(@team1, $captain1);
        
        # Raffle captain for team2, if needed
        if ($captain2 eq "") {
            $randindex = int(rand($playercount));
            $captain2 = $players[$randindex];
        }
        
        # Remove captain2 from player pool
        # and add him in his team
        for my $i (0 .. $#players) {
            if ($players[$i] eq $captain2) {
                splice(@players, $i, 1);
                $playercount--;
                last;
            }
        }
        push(@team2, $captain2);
        
        $self->emote(channel => "$chan",
                     body => "$captain1 ja $captain2 ovat kapteeneita. " .
                             "Aloitetaan pelaajien poiminta.");
        
        
        my $playerlist = join(', ', @players);
        $self->emote(channel => "$chan",
                     body => "Pelaajapooli: $playerlist");
                     
        
        # Set channel to moderated and give +v to captains
        $self->mode("$chan +m");
        $self->mode("$chan +v $captain1");
        $self->mode("$chan +v $captain2");
        
        $self->emote(channel => "$chan",
                     body => "$captain2:n vuoro poimia.");
        
        $canpick = 1;
        $turn = 2;
        $lastturn = 2;  # makes the first pickturn include only one pick
        
        return;
    }
    
    
    # command .captain
    elsif ($commands[0] eq '.captain') {
        
        if ($cancaptain == 0) {
            $self->emote(channel => $chan,
                         body => "Kapteeniksi ilmoittautuminen ei ole tällä hetkellä mahdollista.");
            return;
        }
        
        if ($who eq $captain1 || $who eq $captain2) {
            $self->emote(channel => $chan,
                         body => "$who on jo kapteeni.");
            return;
        }
        
        my $isplaying = 0;
        for my $player (@players) {
            if ($player eq $who) {
                $isplaying = 1;
            }
        }
        
        if ($isplaying == 0) {
            $self->emote(channel => $chan,
                         body => "$who ei ole ilmoittautunut peliin.");
            return;
        }
    
        if ($captain1 eq "") {
            $captain1 = $who;
            $self->emote(channel => $chan,
                         body => "$who on nyt $team1:n kapteeni.");
            
        } elsif ($captain2 eq "") {
            $captain2 = $who;
            $self->emote(channel => $chan,
                         body => "$who on nyt $team2:n kapteeni.");
        }
        
        if ($captain1 ne "" && $captain2 ne "") {
            $cancaptain = 0;
        }
        
        return;
    }
    
    # command .notcaptain
    elsif ($commands[0] eq '.notcaptain') {
    
        if ($canpick == 1) {
            $self->emote(channel => "$chan",
                         body => "Pelaajien poiminta on jo alkanut (käytettävä .newcaptain)");
            return;
        }
        
        if ($who ne $captain1 && $who ne $captain2) {
            $self->emote(channel => "$chan",
                         body => "$who ei ole kapteeni.");
            return;
        }
        
        if ($captain1 eq $who) {
            $captain1 = "";
            $self->emote(channel => $chan,
                         body => "$who ei enää ole $team1:n kapteeni.");
                         
        } elsif ($captain2 eq $who) {
            $captain2 = "";
            $self->emote(channel => $chan,
                         body => "$who ei enää ole $team2:n kapteeni.");
        }
        
        $cancaptain = 1;
        
        return;
    }
    
    
    # command .newcaptain
    elsif ($commands[0] eq '.newcaptain') {
    
        if ($canpick == 0) {
            $self->emote(channel => "$chan",
                         body => "Pelaajien poiminta ei ole vielä alkanut.");
            return;
        }
    
        if ($#commands == 0) {
    
            if ($who ne $captain1 && $who ne $captain2) {
                $self->emote(channel => "$chan",
                             body => "$who ei ole kapteeni.");
                return;
            }
            
            # Raffle new captain from the player pool
            my $playercount = $#players+1;
            my $randindex = int(rand($playercount));
            my $newcaptain = $players[$randindex];
            
            if ($who eq $captain1) {
                # Remove the new captain from the player pool
                splice(@players, $randindex, 1);
                
                # Remove the current captain from his team
                splice(@team1, 0, 1);
                
                # Put the current captain back in the player pool
                push(@players, $captain1);
                
                # Devoice current captain
                $self->mode("$chan -v $captain1");
                
                # Make the newly raffled player the captain 
                # and put him in his team
                $captain1 = $newcaptain;
                push(@team1, $captain1);
                
                # Voice new captain
                $self->mode("$chan +v $captain1");
                
                $self->emote(channel => $chan,
                             body => "$captain1 on nyt $team1:n kapteeni.");
                
                $team1captrequests = "";
                
            } else {
                # Remove the new captain from the player pool
                splice(@players, $randindex, 1);
                
                # Remove the current captain from his team
                splice(@team2, 0, 1);
                
                # Put the current captain back in the player pool
                push(@players, $captain2);
                
                # Devoice current captain
                $self->mode("$chan -v $captain1");
                
                # Make the newly raffled player the captain 
                # and put him in his team
                $captain2 = $newcaptain;
                push(@team2, $captain2);
                
                # Voice new captain
                $self->mode("$chan +v $captain2");
                
                $self->emote(channel => $chan,
                             body => "$captain2 on nyt $team2:n kapteeni.");
                
                $team2captrequests = "";
            }
            
            return;
        }
        # only if $#commands > 0, we come here
        
        if ($commands[1] ne $team1 && $commands[1] ne $team2) {
            $self->emote(channel => "$chan",
                         body => "Syntaksi on $commands[0] <$team1|$team2> <uusikapteeni>");
            return;
        }
        
        my $isplaying = 0;
        for my $player (@players) {
            if ($player eq $who) {
                $isplaying = 1;
            }
        }
        if ($captain1 eq $who) {
            $isplaying = 1;
        }
        if ($captain2 eq $who) {
            $isplaying = 1;
        }
        
        if ($isplaying == 0 && $accesslevel ne 'admin') {
            $self->emote(channel => "$chan",
                         body => "$who ei ole ilmoittautunut peliin.");
            return;
        }
        
        my $newcaptrequests = "";
        if ($commands[1] eq $team1) {
            $newcaptrequests = $team1captrequests;
        } else {
            $newcaptrequests = $team2captrequests;
        }
        
        my @requesters = split(',', $newcaptrequests);
        
        my $alreadyrequested = 0;
        for my $requester (@requesters) {
            if ($who eq $requester) {
                $alreadyrequested = 1;
            }
        }
        
        if ($alreadyrequested == 0) {
            push(@requesters, $who);
        }
        
        $newcaptrequests = join(',', @requesters);
        my $requestersline = join(', ', @requesters);   # just for output
        my $requesterscount = $#requesters+1;
        $requestsfornewcapt = ($maxplayers-4) / 2;
        my $team;
        
        if ($commands[1] eq $team1) {
            $team = $team1;
            $team1captrequests = $newcaptrequests;
        } else {
            $team = $team2;
            $team2captrequests = $newcaptrequests;
        }
        
        $self->emote(channel => "$chan",
                        body => "Uutta kapteenia $team:lle on ehdottanut: " .
                                "$requestersline \[$requesterscount / $requestsfornewcapt\]");
        
        # If not enough requesters yet and
        # the requester is not an admin, return.
        # Otherwise, go on to raffle a new captain
        if ($requesterscount < $requestsfornewcapt && $accesslevel ne 'admin') {
            return;
        }
        
        # Raffle new captain from the player pool
        my $playercount = $#players+1;
        my $randindex = int(rand($playercount));
        my $newcaptain = $players[$randindex];
        
        if ($commands[1] eq $team1) {
            # Remove the new captain from the player pool
            splice(@players, $randindex, 1);
            
            # Remove the current captain from his team
            splice(@team1, 0, 1);
            
            # Put the current captain back in the player pool
            push(@players, $captain1);
            
            # Devoice current captain
            $self->mode("$chan -v $captain1");
            
            # Make the newly raffled player the captain 
            # and put him in his team
            $captain1 = $newcaptain;
            push(@team1, $captain1);
            
            $self->emote(channel => $chan,
                         body => "$captain1 on nyt $team1:n kapteeni.");
                         
            # Voice new captain
            $self->mode("$chan +v $captain1");
                         
            $team1captrequests = "";
            
        } else {
            # Remove the new captain from the player pool
            splice(@players, $randindex, 1);
            
            # Remove the current captain from his team
            splice(@team2, 0, 1);
            
            # Put the current captain back in the player pool
            push(@players, $captain2);
            
            # Devoice current captain
            $self->mode("$chan -v $captain1");
            
            # Make the newly raffled player the captain 
            # and put him in his team
            $captain2 = $newcaptain;
            push(@team2, $captain2);
            
            $self->emote(channel => $chan,
                         body => "$captain2 on nyt $team2:n kapteeni.");
                         
            # Voice new captain
            $self->mode("$chan +v $captain2");
                         
            $team2captrequests = "";
        }
        
        return;
    }
    
    
    # command .pick
    elsif ($commands[0] eq '.pick') {
        if ($canpick == 0) {
            $self->emote(channel => "$chan", body => "Pelaajien poiminta ei ole meneillään.");
            return;
        }
        
        if ($who ne $captain1 && $who ne $captain2) {
            $self->emote(channel => "$chan", body => "$who ei ole kapteeni.");
            return;
        }
        
        if ($#commands < 1) {
            $self->emote(channel => "$chan", body => "Syntaksi on $commands[0] <pelaaja>");
            return;
        }
        
        if ($who eq $captain1 && $turn != 1) {
            $self->emote(channel => "$chan", body => "Ei ole $captain1:n vuoro poimia.");
            return;
        }
        
        if ($who eq $captain2 && $turn != 2) {
            $self->emote(channel => "$chan", body => "Ei ole $captain2:n vuoro poimia.");
            return;
        }
        
        my $isplaying = 0;
        for my $i (0.. $#players) {
            if ($players[$i] eq $commands[1]) {
                $isplaying = 1;
            }
        }
        
        if ($isplaying == 0) {
            $self->emote(channel => $chan,
                         body => "$commands[1] ei ole pelaajapoolissa.");
            return;
        }
        
        # Add the picked player to team1 and decide who picks next
        if ($who eq $captain1) {
            push(@team1, $commands[1]);
            if ($lastturn == 1) {
                $turn = 2;
            }
            $lastturn = 1;
        }
        
        # Else, add the picked player to team2 and decide who picks next
        if ($who eq $captain2) {
            push(@team2, $commands[1]);
            if ($lastturn == 2) {
                $turn = 1;
            }
            $lastturn = 2;
        }
        
        # Remove the picked one from the playerlist
        for my $i (0 .. $#players) {
            if ($players[$i] eq $commands[1]) {
                splice(@players, $i, 1);
                last;
            }
        }
        
        my $outline = "$who poimi $commands[1]:n.";
        
        my $pickedplayercount = $#team1+1 + $#team2+1;
        # print STDERR "pickedplayercount: $pickedplayercount \n";
        
        if ($pickedplayercount < $maxplayers) {
            my $nextpicker;
            if ($turn == 1) {
                $nextpicker = $captain1;
                
            } else {
                $nextpicker = $captain2;
            }

            $outline .= " $nextpicker:n vuoro poimia.";
        }
        
        $self->emote(channel => "$chan", body => "$outline");
        
        # Return if not ready yet, otherwise go on
        if ($pickedplayercount < $maxplayers) {
            return;
        }
        
        # Devoice captains and set channel to -moderated
        $self->mode("$chan -v $captain1");
        $self->mode("$chan -v $captain2");
        $self->mode("$chan -m");
        
        # Start the game
        $gamenum++;
        $self->emote(channel => "$chan", body => "Peli numero $gamenum alkaa!");
        
        # Print the teams
        my $team1list = $self->formatteam(@team1);
        my $team2list = $self->formatteam(@team2);
        $self->emote(channel => "$chan", body => "$team1: $team1list");
        $self->emote(channel => "$chan", body => "$team2: $team2list");
        
        # Add game to the gamedata
        my $gamedataline = "$gamenum:active,result:,";
        $team1list = join(",", @team1);
        $team2list = join(",", @team2);
        $gamedataline .= $team1list;
        $gamedataline .= ',';
        $gamedataline .= $team2list;
        
        $games{$gamenum} = $gamedataline;
        
        $captain1 = "";
        $captain2 = "";
        $self->voidvotes();
        $self->voidrequests();
        @players=();
        @team1=();
        @team2=();
        
        $canpick = 0;
        $canvotemap = 0;
        $canadd = 1;
        $canout = 1;
        $cancaptain = 1;
        
        return;
    }
    
    
    # command .abort
    elsif ($commands[0] eq '.abort') {
    
        if ($accesslevel ne 'admin') {
            $self->emote(channel => "$chan",
                            body => "$who ei ole admin.");
            return;
        }
        
        $captain1 = "";
        $captain2 = "";
        $self->voidvotes();
        $self->voidrequests();
        @players=();
        @team1=();
        @team2=();
        
        $canadd = 1;
        $canout = 1;
        $cancaptain = 1;
        $canvotemap = 0;
        $canpick = 0;
        
        $self->emote(channel => $chan,
                     body => "Peli keskeytetty ja ilmoittautuneiden lista tyhjennetty.");
                     
        return;
    }
    

    # command .list
    elsif ($commands[0] eq '.list'        || $commands[0] eq '.ls' ||
           $commands[0] eq '.listplayers' || $commands[0] eq '.lp' ||
           $commands[0] eq '.playerlist'  || $commands[0] eq '.pl')  {
    
        my $outline = "";
        
        if ($#players < 0) {
            $outline = "Ei ilmoittautuneita.";
            
        } else {
            my $playercount = $#players+1;
            my $list = $self->formatplayerlist(@players);
            
            if ($canpick == 0) {
                $outline = "Ilmoittautuneet: $list. Pelaajia on $playercount/$maxplayers";
                
            } else {
                $outline = "Pelaajapooli: $list";
            }
        }
        
        $self->emote(channel => $chan, body => $outline);
        return;
    }
    
    
    # command .score
    elsif ($commands[0] eq '.score' || $commands[0] eq '.report' ||
           $commands[0] eq '.result') {
        
        if ($#commands < 2) {
            $self->emote(channel => "$chan",
                         body => "Syntaksi on $commands[0] <pelinro> <$team1|$team2|$draw>");
            return;
        }
        
        my $cmd1 = $commands[1];
        my $cmd2 = $commands[2];
        
        # Make lowercase versions of the strings and use them in comparisons
        my $cmd2lc = lc($cmd2);
        my $team1lc = lc($team1);
        my $team2lc = lc($team2);
        my $drawlc = lc($draw);
        
        if ($cmd2lc ne $team1lc && $cmd2lc ne $team2lc && $cmd2lc ne $drawlc) {
            $self->emote(channel => "$chan",
                         body => "Tulokseksi annettava $team1, $team2 tai $draw");
            return;
        }
        
        if (! exists($games{$cmd1}) ) {
            $self->emote(channel => "$chan",
                         body => "Peliä numero $cmd1 ei löydy.");
            return;
        }
        
        if ( index($games{$cmd1}, 'active') == -1 ) {
            $self->emote(channel => "$chan",
                         body => "Peli numero $cmd1 on jo reportoitu.");
            return;
        }
        
        # Make the given result look like it should (looks nice when printed)
        if ($cmd2lc eq $team1lc) { $cmd2 = $team1 };
        if ($cmd2lc eq $team2lc) { $cmd2 = $team2 };
        if ($cmd2lc eq $drawlc)  { $cmd2 = $draw };
        
        # Find out who were captains in this particular game
        my @gamedata = split(',', $games{$cmd1});
        my $wasteamsize = (($#gamedata+1) -2) / 2;
        my $wascaptain1 = $gamedata[2];
        my $wascaptain2 = $gamedata[2+$wasteamsize];
        
        
        if ($accesslevel ne 'admin') {
        
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
                
                $self->emote(channel => "$chan",
                           body => "$team kapteeni ehdotti pelille numero " .
                                   "$cmd1 tulosta \"$cmd2\"");
                                    
                if ($captainresults[0] ne $captainresults[1]) {
                    return;
                }
                
            } else {
            
                # Find out if the player even played in the game
                # (use @gamedata from before)
                my $wasplaying = 0;
                for my $i (2 .. $#gamedata) {
                    if ($gamedata[$i] eq $who) {
                        $wasplaying = 1;
                    }
                }
                
                if ($wasplaying == 0) {
                    $self->emote(channel => $chan,
                                 body => "$who ei pelannut pelissä numero $cmd1.");
                    return;
                }
                
                # Initialize hash value if necessary
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
                
                if ($requestssofar < $requeststoscore) {
                    my $requestersline = join(', ', @certainrequesters);
                    
                    $self->emote(channel => "$chan",
                                 body => "Tulosta \"$cmd2\" pelille numero $cmd1 on ehdottanut: " .
                                         "$requestersline " .
                                         "\[$requestssofar / $requeststoreplace\]");
                    return;
                }
            }
        }
        
        delete($userscorereq{$cmd1});
        
        my @gamevalues = split(',', $games{$cmd1});
        $gamevalues[0] =~ s/active/closed/g;
        
        my $result;
        my @userinfo;
        
        if ($cmd2lc eq $team1lc) {
            $result = 1;
            
            for my $i (2 .. $teamsize+1) {
                @userinfo = split('\.', $users{$gamevalues[$i]});
                $userinfo[1] += $pointsdelta; $userinfo[2]++;
                $users{$gamevalues[$i]} = join('.', @userinfo);
            }
            
            for my $i ($teamsize+2 .. $maxplayers+1) {
                @userinfo = split('\.', $users{$gamevalues[$i]});
                $userinfo[1] -= $pointsdelta; $userinfo[3]++;
                $users{$gamevalues[$i]} = join('.', @userinfo);
            }
            
        } elsif ($cmd2lc eq $team2lc) {
            $result = 2;
            
            for my $i (2 .. $teamsize+1) {
                @userinfo = split('\.', $users{$gamevalues[$i]});
                $userinfo[1] -= $pointsdelta; $userinfo[3]++;
                $users{$gamevalues[$i]} = join('.', @userinfo);
            }
            
            for my $i ($teamsize+2 .. $maxplayers+1) {
                @userinfo = split('\.', $users{$gamevalues[$i]});
                $userinfo[1] += $pointsdelta; $userinfo[2]++;
                $users{$gamevalues[$i]} = join('.', @userinfo);
            }
            
        } elsif ($cmd2lc eq $drawlc) {
            $result = 3;
            
            for my $i (2 .. $maxplayers+1) {
                @userinfo = split('\.', $users{$gamevalues[$i]});
                $userinfo[4]++;
                $users{$gamevalues[$i]} = join('.', @userinfo);
            }
        }
        
        $gamevalues[1] .= "$result";
        $games{$cmd1} = join(',', @gamevalues);
        
        $self->emote(channel => "$chan",
                     body => "Peli numero $cmd1 päättynyt; reportoitu.");
        
        my $outline = "Tulos: ";
        if ($cmd2lc eq $team1lc) { $outline .= "$team1 voitti"; }
        if ($cmd2lc eq $team2lc) { $outline .= "$team2 voitti"; }
        if ($cmd2lc eq $drawlc)  { $outline .= "$draw"; }
        
        $self->emote(channel => "$chan", body => "$outline");
        return;
    }
    
    
    # command .out
    elsif ($commands[0] eq '.out' || $commands[0] eq '.remove' ||
           $commands[0] eq '.rm') {
    
        my $tbremoved;
        if ($#commands == 0) {
            $tbremoved = "$who";
            
        } else {
            if ($accesslevel ne 'admin') {
                my $isplaying = 0;
                for my $player (@players) {
                    if ($player eq $who) {
                        $isplaying = 1;
                    }
                }
                
                if ($isplaying == 0) {
                    $self->emote(channel => "$chan",
                                 body => "$who ei ole ilmoittautunut.");
                    return;
                }
            }
            
            $tbremoved = "$commands[1]";
        }
        
        if ($canout == 0) {
            $self->emote(channel => "$chan",
                         body => "Poistuminen ei ole mahdollista tällä hetkellä.");
            return;
        }
    
        for my $i (0 .. $#players) {
            if ($players[$i] eq $tbremoved) {
            
                if ($accesslevel ne 'admin' && $#commands != 0) {
                    if (! exists($removereq{$tbremoved}) ) {
                        $removereq{$tbremoved} = "";
                    }
                    
                    my $removereqline = $removereq{$tbremoved};
                    my @requesters = split(',', $removereqline);
                    
                    my $alreadyrequested = 0;
                    for my $j (0 .. $#requesters) {
                        if ($requesters[$j] eq $who) {
                            $alreadyrequested = 1;
                        }
                    }
                    if ($alreadyrequested == 0) {
                        push(@requesters, $who);
                        
                    }
                    
                    # Update the player's removerequest information
                    $removereq{$tbremoved} = join(',', @requesters);
                    
                    my $requestssofar = $#requesters+1;
                    
                    my $requestersline = join(', ', @requesters);
                    $self->emote(channel => "$chan",
                                 body => "$tbremoved:n poistamista on pyytänyt: " .
                                         "$requestersline " .
                                         "\[$requestssofar / $requeststoremove\]");
                    
                    
                    if ($requestssofar < $requeststoremove) {
                        return;
                    }
                }
                
                splice(@players, $i, 1);
                
                my $playercount = $#players+1;
                if ($playercount == 0) {
                    $canvotemap = 0;
                }
                
                if ($tbremoved eq $captain1) {
                    $captain1 = "";
                }
                
                if ($tbremoved eq $captain2) {
                    $captain2 = "";
                }
                
                $self->voidusersvotes($tbremoved);
                $self->voidusersrequests($tbremoved);
                
                $self->emote(channel => $chan,
                             body => "$tbremoved poistui pelistä. " .
                                     "Pelaajia on $playercount/$maxplayers");

                return;
            }
        }
        
        $self->emote(channel => "$chan",
                     body => "$tbremoved ei ole ilmoittautunut.");
        return;
    }
    
    
    # command .stats
    elsif ($commands[0] eq '.stats') {
        my $tbprinted;
        
        if ($#commands == 0) {
            if (! exists($users{$who}) ) {
                $self->emote(channel => "$chan",
                            body => "Käyttäjää $who ei löydy.");
                return;
                            
            } else { $tbprinted = $who; }
            
            
        } else {
            my $cmd1 = $commands[1];
            
            if (! exists($users{$cmd1}) ) {
                $self->emote(channel => "$chan",
                            body => "Käyttäjää $cmd1 ei löydy.");
                return;
                            
            } else { $tbprinted = $cmd1; }
            
        }
        
        my @userline = split('\.', $users{$tbprinted});
        $self->emote(channel => "$chan",
                    body => "$tbprinted:lla on " .
                            "$userline[1] pistettä, " .
                            "$userline[2] voittoa, " .
                            "$userline[3] häviötä ja " .
                            "$userline[4] tasapeliä");
        return;
    }
    
    
    # command .lastgame and .gameinfo
    elsif ($commands[0] eq '.lastgame' || $commands[0] eq '.lg' ||
            $commands[0] eq '.gameinfo' || $commands[0] eq '.gi') {
            
        my $query;
        if ($commands[0] eq '.lastgame' || $commands[0] eq '.lg') {
            $query = $gamenum;
            
        } else { # if command was .gameinfo or .gi
            if ($#commands != 1) {
                $self->emote(channel => "$chan",
                             body => "Syntaksi on $commands[0] <pelinumero>");
                    return;
            }
            $query = $commands[1];
        }
        
        if (! exists($games{$query}) ) {
            $self->emote(channel => "$chan",
                         body => "Peliä numero $query ei löydy.");
            return;
        }
        
        my @gdata = split(',', $games{$query});
        my @gdata2 = split(':', $gdata[0]);
        
        my @team1list; my @team2list;
        
        for (my $i = 2; $i<=$teamsize+1; $i++) {
            push(@team1list, $gdata[$i]);
        }
        
        for (my $i = $teamsize+2; $i<=$maxplayers+1; $i++) {
            push(@team2list, $gdata[$i]);
        }
        
        my $team1str = $self->formatteam(@team1list);
        my $team2str = $self->formatteam(@team2list);
        
        $self->emote(channel => "$chan", body => "Peli numero $query:");
        $self->emote(channel => "$chan", body => "$team1: $team1str");
        $self->emote(channel => "$chan", body => "$team2: $team2str");
        
        my $outline;
        
        if ($gdata2[1] eq 'active') {
            $outline = "Tila: käynnissä";
        
        } elsif ($gdata2[1] eq 'closed') {
        
            my @resultdata = split(':', $gdata[1]);
            my $resultstr;
            $outline = "Tulos: ";
            
            if ($resultdata[1] == 1) { $outline .= "$team1 voitti"; }
            if ($resultdata[1] == 2) { $outline .= "$team2 voitti"; }
            if ($resultdata[1] == 3) { $outline .= "tasapeli"; }
            
        } else { $outline = "Sisäinen datakorruptio!"; }
        
        
        $self->emote(channel => "$chan", body => "$outline");
        return;
    }
    
    
    # command .whois
    elsif ($commands[0] eq '.whois' || $commands[0] eq '.who') {
        my $tbprinted;
        
        if ($#commands == 0) {
            if (! exists($users{$who}) ) {
                $self->emote(channel => "$chan",
                             body => "Käyttäjää $who ei löydy.");
                return;
                            
            } else { $tbprinted = $who; }
            
            
        } else {
            my $cmd1 = $commands[1];
            
            if (! exists($users{$cmd1}) ) {
                $self->emote(channel => "$chan",
                             body => "Käyttäjää $cmd1 ei löydy.");
                return;
                            
            } else { $tbprinted = $cmd1; }
            
        }
        
        my @userline = split('\.', $users{$tbprinted});
        $self->emote(channel => "$chan",
                    body => "$tbprinted: $userline[0]");
        return;
    }
    
    
    # command .server
    elsif ($commands[0] eq '.server' || $commands[0] eq '.srv') {
    
        if ($gameserverip eq "") {
            return;
        }
    
        $self->emote(channel => "$chan",
                    body => "Serverin IP: $gameserverip:$gameserverport - " .
                            "Passu: $gameserverpw");
        return;
    }
    
    
    # command .mumble
    elsif ($commands[0] eq '.mumble' || $commands[0] eq '.mb') {
    
        if ($voiceserverip eq "") {
            return;
        }
    
        $self->emote(channel => "$chan",
                     body => "Mumblen IP: $voiceserverip - " .
                             "Portti: $voiceserverport - " .
                             "Passu: $voiceserverpw");
        return;
    }
    
    # command .votemap
    elsif ($commands[0] eq '.votemap' || $commands[0] eq '.vm') {

        my $maps = join(', ', @maps);
        
        if ($#commands < 1) {
            $self->emote(channel => "$chan",
                         body => "Syntaksi on $commands[0] <mappi>");
            $self->emote(channel => "$chan",
                         body => "Äänestettävissä olevat mapit: $maps");
            $self->emote(channel => "$chan",
                         body => "Annetun äänen voi vetää pois antamalla mapiksi pisteen. " .
                                 "Äänestystilanteen näkee komennolla $commands[0] votes");
            return;
        }
        
        if ($canvotemap == 0) {
            $self->emote(channel => "$chan",
                        body => "Votemap ei ole päällä " .
                                "(ketään ei ole ilmoittautunut)");
            return;
        }
        
        my $outline;
        if ($commands[1] eq 'votes') {
            if ($mapvotecount == 0) {
                $outline = "Ei yhtään mapvotea vielä.";
                
            } else {
                $outline = "Mappivotet: ";
                
                for my $map (@maps) {
                    $outline .= "$map\[$mapvotes{$map}\], ";
                }
                chop $outline; chop $outline;
            }
            
            $self->emote(channel => "$chan", body => $outline);
            return;
        }
        
        my $validvoter = 0;
        for my $player (@players) { # Is on the player list?
            if ($who eq $player) {
                $validvoter = 1;
                last;
            }
        }
        for my $player (@team1) { # Is in team1?
            if ($who eq $player) {
                $validvoter = 1;
                last;
            }
        }
        for my $player (@team2) {  # Is in team2?
            if ($who eq $player) {
                $validvoter = 1;
                last;
            }
        }
        if (! $validvoter) {
            $self->emote(channel => "$chan",
                         body => "Voidakseen äänestää mappia, täytyy olla " .
                                 "ilmoittautunut peliin.");
            return;
        }
        
        my $validvote = 0;
        for my $map (@maps) {
            if ($commands[1] eq $map || $commands[1] eq '.') {
                $validvote = 1;
                last;
            }
        }
        if (! $validvote) {
            $self->emote(channel => "$chan",
                        body => "Virheellinen mappi. Äänestettävissä olevat mapit: $maps");
            return;
        }
        
        if (! exists $mapvoters{$who} ) {
            $mapvoters{$who} = "";
        }
        
        my $changehappened = 0;
        my $samevote = 0;
        my $hadformervote = 1;
        
        if ($commands[1] eq '.') {  # User wanted to void his vote
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
        
        if ($changehappened) {
            $outline = "Mappivotet: ";
            for my $map (@maps) { $outline .= "$map\[$mapvotes{$map}\], "; }
            chop $outline; chop $outline;
        
        } else {
            if ($samevote) {
                $outline = "$who on jo äänestänyt mappia $commands[1]";
                
            } elsif (!$hadformervote) {
                $outline = "$who ei ole äänestänyt vielä mitään mappia";
                
            } else {
                $outline = "";
            }
        }
        
        $self->emote(channel => "$chan", body => "$outline");
        return;
    }
    
    
    # command .replace
    elsif ($commands[0] eq '.replace' || $commands[0] eq '.rep') {
            
        if ($#commands < 2) {
            $self->emote(channel => "$chan",
                         body => "Syntaksi on $commands[0] <korvattava> <korvaava>");
            return;
        }
        
        if ($canout == 0) {
            $self->emote(channel => "$chan",
                         body => "Poistuminen ei ole mahdollista tällä hetkellä.");
            return;
        }
        
        my $replacedindex = -1;
        my $validreplacement = 1;
        for my $i (0 .. $#players) {
            if ($players[$i] eq $commands[1]) {
                $replacedindex = $i;
            }
            
            if ($players[$i] eq $commands[2]) {
                $validreplacement = 0;
            }
        }
        
        if ($replacedindex == -1) {
            $self->emote(channel => "$chan",
                         body => "$commands[1] ei ole ilmoittautunut peliin.");
            return;
        }
        
        if ($commands[1] eq $captain1 || $commands[1] eq $captain2) {
            $self->emote(channel => "$chan",
                         body => "Kapteenia ei ole mahdollista korvata.");
            return;
        }

        if ($validreplacement == 0) {
            $self->emote(channel => "$chan",
                         body => "$commands[2] on jo ilmoittautuneiden listalla.");
            return;
        }
        
        # If caller is an admin
        if ($accesslevel eq 'admin') {
            # If the replacement doesn't exist in userdata, add him
            if (! exists($users{$commands[2]}) ) {
                $users{$commands[2]} = "user.$initialpoints.0.0.0";
            }
            
            $self->voidusersvotes($commands[1]);
            $self->voidusersrequests($commands[1]);
            
            splice(@players, $replacedindex, 1, $commands[2]);
            $self->emote(channel => "$chan",
                         body => "$commands[1] korvattu pelaajalla $commands[2].");
        
        # If caller is an user
        } else {
            
            my $isplaying = 0;
            for my $player (@players) {
                if ($player eq $who) {
                    $isplaying = 1;
                    last;
                }
            }
            if ($isplaying == 0) {
                $self->emote(channel => "$chan",
                             body => "$who ei ole ilmoittautunut peliin.");
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
            
            my $requestno = -1;
            for my $i (0 .. $#requesters) {
                if ($requesters[$i] eq $who) {
                    $requestno = $i;
                }
            }
                
            if ($requestno != -1) {
                $replacements[$requestno] = $commands[2];
                
            } else {
                push(@requesters, $who);
                push(@replacements, $commands[2]);
            }
            
            # Update the information where it was read from (%replacereq)
            @arr=();
            for my $i (0 .. $#requesters) {
                $arr[$i] = "$requesters[$i]:$replacements[$i]";
            }
            $requestline = join(',', @arr);
            $replacereq{$commands[1]} = $requestline;   # <--
            
            for my $i (0 .. $#replacements) {
                if ($replacements[$i] eq $commands[2]) {
                    
                } else { splice(@requesters, $i, 1); }
            }
            
            my $requestssofar = $#requesters+1;
            my $requestersline = join(', ', @requesters);
            
            if ($requestssofar == $requeststoreplace) {
                
                if (! exists($users{$commands[2]}) ) {
                    $users{$commands[2]} = "user.$initialpoints.0.0.0";
                }
                
                splice(@players, $replacedindex, 1, $commands[2]);
                $self->emote(channel => "$chan",
                             body => "$commands[1] korvattu pelaajalla $commands[2].");
                
                $self->voidusersvotes($commands[1]);
                $self->voidusersrequests($commands[1]);
                        
            } else {
                $self->emote(channel => "$chan",
                             body => "$commands[1]:n korvaamista $commands[2]:lla " .
                                     "on pyytänyt: $requestersline " .
                                     "\[$requestssofar / $requeststoreplace\]");
            }
        }
        
        return;
    }
    
    
    # command .games
    elsif ($commands[0] eq '.games') {
        
        my $outline = "Käynnissä olevat pelit: ";
        my $indexofcolon;
        my @activegames;
        
        foreach (keys %games) {
            if ( index($games{$_}, 'active') != -1) {
                $indexofcolon = index($games{$_}, ':');
                push(@activegames, "pelinro " . substr($games{$_}, 0, $indexofcolon));
            }
        }
        
        if ($#activegames < 0) {
                $outline = "Ei yhtään peliä käynnissä.";
        } else {
            $outline .= join(', ', @activegames);
        }
            
        $self->emote(channel => "$chan", body => "$outline");
        return;
    }
    
    
    # command .accesslevel
    elsif ($commands[0] eq '.accesslevel') {
    
        if ($accesslevel ne 'admin') {
            $self->emote(channel => "$chan", body => "$who ei ole admin.");
            return;
        }
        
        if ($#commands < 2 ||
            $commands[2] ne 'admin' && $commands[2] ne 'user') {
            
                $self->emote(channel => "$chan",
                             body => "Syntaksi on $commands[0] <käyttäjä> <admin|user>");
            return;
        }
        
        # Case new user
        if (! exists($users{$commands[1]}) ) {
            $users{$commands[1]} = "$commands[2].$initialpoints.0.0.0";
            $self->emote(channel => "$chan",
                        body => "$commands[1] on nyt $commands[2].");
            return;
        }
        
        # Case existing user
        my @uservalues = split('\.', $users{$commands[1]});
        my $currentaccess = $uservalues[0];
        
        if ($currentaccess eq $commands[2]) {
            $self->emote(channel => "$chan",
                        body => "$commands[1] on jo $commands[2].");
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
                    $self->emote(channel => "$chan",
                                 body => "$who ei ole alkuperäinen admin.");
                    return ;
                }
            }
        
            $uservalues[0] = $commands[2];
            $users{$commands[1]} = join('.', @uservalues);
            
            $self->emote(channel => "$chan",
                         body => "$commands[1] on nyt $commands[2].");
        }
        
        return;
    }
    
    
    # command .resetstats
    elsif ($commands[0] eq '.resetstats') {
    
        if ($accesslevel ne 'admin') {
            $self->emote(channel => "$chan",
                        body => "$who ei ole admin");
            return;
        }
        
        if ($#commands != 1) {
                $self->emote(channel => "$chan",
                        body => "Syntaksi on $commands[0] <käyttäjä> <admin|user>");
        }
        
        if (! exists($users{$commands[1]}) ) {
            $users{$commands[1]} = "user.$initialpoints.0.0.0";
            return;
        }
        
        my @uservalues = split('\.', $users{$commands[1]});
        $uservalues[1] = "$initialpoints";
        $uservalues[2] = "0";
        $uservalues[3] = "0";
        $uservalues[4] = "0";
        $users{$commands[1]} = join('.', @uservalues);
        
        $self->emote(channel => "$chan",
                    body => "$commands[1]:n tilastot nollattu.");
        return;
    }
    
    
    # command .voidgame
    elsif ($commands[0] eq '.voidgame') {
    
        if ($accesslevel ne 'admin') {
            $self->emote(channel => "$chan",
                        body => "$who ei ole admin");
            return;
        }
        
        if ($#commands != 1) {
            $self->emote(channel => "$chan",
                        body => "Syntaksi on $commands[0] <pelinro>");
            return;
        }
        
        if (! exists($games{$commands[1]}) ) {
            $self->emote(channel => "$chan",
                    body => "Peliä numero $commands[1] ei löydy.");
            return;
        }
        
        my @gamevalues = split(',', $games{$commands[1]});
        
        if ( index($gamevalues[0], 'active') != -1 ) {
            $self->emote(channel => "$chan",
                        body => "Peli numero $commands[1] on edelleen käynnissä.");
            return;
        }
        
        my @result = split(':', $gamevalues[1]);
        my @userinfo;
        my $outline = "Peli numero $commands[1] mitätöity.";
        
        if ($result[1] == 1) {
            
            for my $i (2 .. $teamsize+1) {
                @userinfo = split('\.', $users{$gamevalues[$i]});
                $userinfo[1] -= $pointsdelta; $userinfo[2]--;
                $users{$gamevalues[$i]} = join('.', @userinfo);
            }
            
            for my $i ($teamsize+2 .. $maxplayers+1) {
                @userinfo = split('\.', $users{$gamevalues[$i]});
                $userinfo[1] += $pointsdelta; $userinfo[3]--;
                $users{$gamevalues[$i]} = join('.', @userinfo);
            }
            
        } elsif ($result[1] == 2) {
            for my $i (2 .. $teamsize+1) {
                @userinfo = split('\.', $users{$gamevalues[$i]});
                $userinfo[1] += $pointsdelta; $userinfo[3]--;
                $users{$gamevalues[$i]} = join('.', @userinfo);
            }
            
            for my $i ($teamsize+2 .. $maxplayers+1) {
                @userinfo = split('\.', $users{$gamevalues[$i]});
                $userinfo[1] -= $pointsdelta; $userinfo[2]--;
                $users{$gamevalues[$i]} = join('.', @userinfo);
            }
            
        } elsif ($result[1] == 3) {
            for my $i (2 .. $maxplayers+1) {
                @userinfo = split('\.', $users{$gamevalues[$i]});
                $userinfo[4]--;
                $users{$gamevalues[$i]} = join('.', @userinfo);
            }
            
        } else {
            $self->emote(channel => "$chan", body => "Sisäinen datakorruptio!");
        }
        
        delete($games{$commands[1]});
        
        $self->emote(channel => "$chan", body => "Peli numero $commands[1] mitätöity.");
        return;
    }
    
    
    # command .changename
    elsif ($commands[0] eq '.changename') {
    
        if ($accesslevel ne 'admin') {
            $self->emote(channel => "$chan",
                        body => "$who ei ole admin");
            return;
        }
        
        if ($#commands != 2) {
            $self->emote(channel => "$chan",
                        body => "Syntaksi on $commands[0] <nykyinennimi> <uusinimi>");
            return;
        }
        
        if (! exists($users{$commands[1]}) ) {
            $self->emote(channel => "$chan",
                        body => "$commands[1] ei löydy.");
            return;
        }
        
        if ( exists($users{$commands[2]}) ) {
            $self->emote(channel => "$chan",
                        body => "$commands[2] niminen käyttäjä on jo olemassa.");
            return;
        }
        
        $users{$commands[2]} = $users{$commands[1]};
        delete($users{$commands[1]});
        
        $self->emote(channel => "$chan",
                    body => "$commands[1] on nyt $commands[2]");
        return;
    }
    
    
    # command .rank
    elsif ($commands[0] eq '.rank' || $commands[0] eq '.top') {
    
        if ($commands[0] eq '.rank') {
            if ($#commands > 0) {
                $who = $commands[1];
            }
            
            if (! exists($users{$who}) ) {
                $self->emote(channel => "$chan", body => "$who ei löydy.");
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
        
        my $outline;
        
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
                $outline = "$who:n sijoitus on $usersrank pisteillä $temp[1]";
            } else {
                $outline = "$who:lla ei ole vielä sijoitusta.";
            }

        } else { # if command was .top
        
            if ($#ranklist == -1) {
                $self->say(channel => "msg", who => "$who", body => "Sijoituslista on tyhjä.");
                return;
            }
        
            my $listlength = $topdefaultlength;
            if ($#commands > 0 && $commands[1] =~ /^[+-]?\d+$/ ) {
                $listlength = $commands[1];
            }
            
            if ($#ranklist+1 < $listlength) {
                $listlength = $#ranklist+1
            }
            
            my $outline = "Top $listlength: ";
            my @arr;
            
            for my $i (0 .. $listlength-1) {
                @arr = split('\.', $ranklist[$i]);
                $outline .= $i+1 . ". $arr[0]\[$arr[1]\], ";
            }
            chop $outline, chop $outline;
            
            $self->say(channel => "msg", who => "$who", body => "$outline");
            return;
        }
        
        $self->emote(channel => "$chan", body => "$outline");
        return;
    }
    
    
    # command .shutdownbot
    elsif ($commands[0] eq '.shutdownbot') {
    
        my $originaladmin = 0;
        for my $admin (@admins) {
            if ($who eq $admin) {
                $originaladmin = 1;
            }
        }
        
        if (!$originaladmin) {
            $self->emote(channel => "$chan", body => "$who ei ole alkuperäinen admin.");
            return;
        }
        
        $self->writedata();
        $self->writecfg();
        $self->shutdown();
        return;
    }
    
    
    # command .commands
    elsif ($commands[0] eq '.commands' || $commands[0] eq '.commandlist' || 
           $commands[0] eq '.cmdlist' ||$commands[0] eq '.cmds' || $commands[0] eq '.help') {
    
        if ($#commands == 1 && $commands[1] eq 'verbose') {
            my $adddesc = "           = Lisää sinut pelaajapooliin.";
            my $listdesc = "          = Näyttää listan poolissa olevista pelaajista.";
            my $outdesc = "           = Poistaa sinut pelaajapoolista. Lisäksi voit ehdottaa jotain toista " .
                                        "pelaajaa poistettavaksi.";
            my $votemapdesc = "       = Syntaksi on .votemap <mapinnimi>. Lisätietoa komennolla .votemap";
            my $captaindesc = "       = Tekee sinusta pelin kapteenin. Käytettävissä ainoastaan, jos kapteenin paikka " .
                                        "on vielä vapaa.";
            my $notcaptaindesc = "    = Vapauttaa kapteenin paikan sinulta. Edellyttää, että olet ensin " .
                                        "ilmoittautunut kapteeniksi komennolla .captain";
            my $newcaptaindesc = "    = Ehdottaa uuden kapteenin arvontaa joukkueelle. Edellyttää, että pelaajien poiminta on käynnissä. " .
                                        "Jos komennon antaa kapteeni, ehdotus menee läpi välittömästi. Lisätietoa komennolla .newcaptain";
            my $serverdesc = "        = Tulostaa peliserverin tiedot.";
            my $mumbledesc = "        = Tulostaa mumbleserverin tiedot.";
            my $pickdesc = "          = Kapteenin komento, jolla poimii pelaajan joukkueeseensa.";
            my $reportdesc = "        = Komennolla voit ehdottaa pelin tulosta. Lisätietoa komennolla .report";
            my $statsdesc = "         = Tulostaa sinulle tilastosi. Jonkun toisen tilastot saa komennolla " .
                                        ".stats <pelaaja>";
            my $lastgamedesc = "      = Tulostaa viimeksi pelatun pelin tiedot";
            my $gameinfodesc = "      = Syntaksi on .gameinfo <pelinro>. Tulostaa annetun pelin tiedot";
            my $replacedesc = "       = Komennolla voit ehdottaa jotain pelaajaa korvattavaksi jollain toisella " .
                                        "pelaajalla. Lisätietoa komennolla .replace";
            my $gamesdesc = "         = Tulostaa käynnissä olevien pelien pelinumerot.";
            my $rankdesc = "          = Tulostaa sinulle sijoituksesi. Jonkun toisen sijoituksen saa komennolla " .
                                        ".rank <pelaaja>";
            my $topdesc = "           = Antaa listan parhaiten sijoittuneista pelaajista yksityisviestinä. Voit " .
                                        "myös määrittää listan pituuden komennolla .top <lkm>";
            my $hloffdesc = "        = Lisää sinut hilight-ignoreen, jolloin sinua ei highlightata komennolla .hilight.";
            my $hlondesc = "         = Poistaa sinut hilight-ignoresta, jolloin sinua jälleen highlightataan komennolla .hilight.";
            my $whoisdesc = "         = Tulostaa omasi (tai jonkun toisen) käyttäjänimen ja käyttöoikeudet.";
            my $admincommandsdesc = " = (Vain admineille) Tulostaa listan vain admineille käytettävissä olevista komennoista yksityisviestinä.";
            
            $self->say(channel => "msg", who => "$who", body => ".add $adddesc");
            $self->say(channel => "msg", who => "$who", body => ".list $listdesc");
            $self->say(channel => "msg", who => "$who", body => ".out $outdesc");
            $self->say(channel => "msg", who => "$who", body => ".votemap $votemapdesc");
            $self->say(channel => "msg", who => "$who", body => ".captain $captaindesc");
            $self->say(channel => "msg", who => "$who", body => ".notcaptain $notcaptaindesc");
            $self->say(channel => "msg", who => "$who", body => ".newcaptain $newcaptaindesc");
            $self->say(channel => "msg", who => "$who", body => ".server $serverdesc");
            $self->say(channel => "msg", who => "$who", body => ".mumble $mumbledesc");
            $self->say(channel => "msg", who => "$who", body => ".pick $pickdesc");
            $self->say(channel => "msg", who => "$who", body => ".report $reportdesc");
            $self->say(channel => "msg", who => "$who", body => ".stats $statsdesc");
            $self->say(channel => "msg", who => "$who", body => ".lastgame $lastgamedesc");
            $self->say(channel => "msg", who => "$who", body => ".gameinfo $gameinfodesc");
            $self->say(channel => "msg", who => "$who", body => ".replace $replacedesc");
            $self->say(channel => "msg", who => "$who", body => ".games $gamesdesc");
            $self->say(channel => "msg", who => "$who", body => ".rank $rankdesc");
            $self->say(channel => "msg", who => "$who", body => ".top $topdesc");
            $self->say(channel => "msg", who => "$who", body => ".hl off $hloffdesc");
            $self->say(channel => "msg", who => "$who", body => ".hl on $hlondesc");
            $self->say(channel => "msg", who => "$who", body => ".whois $whoisdesc");
            $self->say(channel => "msg", who => "$who", body => ".admincommands $admincommandsdesc");
            
            return;
        }
        
        my $outline = "Komennot ovat .add .list .out .votemap .captain .notcaptain .newcaptain " .
                      ".server .mumble .pick .report .stats .lastgame .gameinfo " .
                      ".replace .games .rank .top .hl off/on .whois .admincommands ";
                        
        $self->emote(channel => "$chan", body => "$outline");
        $self->emote(channel => "$chan", body => "Komentojen tarkemmat selitteet saa komennolla " .
                                                 "$commands[0] verbose");
        return;
    }
    
    
    # command .admincommands
    elsif ($commands[0] eq '.admincommands') {
    
        if ($accesslevel ne 'admin') {
            $self->emote(channel => "$chan", body => "$who ei ole admin.");
            return;
        }
        
        my $adddesc = "        = Lisää pelaajan pooliin. Syntaksi on .add <pelaaja>";
        my $outdesc = "        = Poistaa pelaajan poolista. Syntaksi on .out <pelaaja>";
        my $abortdesc = "      = Nollaa ilmoittautumistilanteen eli tyhjentää pelaajapoolin.";
        my $replacedesc = "    = Korvaa poolissa olevan pelaajan toisella pelaajalla. Syntaksi on " .
                                 ".replace <korvattava> <korvaava>";
        my $aoedesc = "        = Komennolla botti lähettää jokaiselle kanavalla olevalle IRC-noticen gatherin tilanteesta.";
        my $hilightdesc = "    = Komennolla botti highlightaa jokaista kanavalla olevaa yhdellä kerralla.";
        my $reportdesc = "     = Asettaa pelin tuloksen. Syntaksi on .report <pelinro> <$team1|$team2|$draw>";
        my $voidgamedesc = "   = Mitätöi pelin tulokset. Syntaksi on .voidgame <pelinro>";
        my $accessleveldesc = "= Asettaa annetun käyttäjän käyttöoikeudet annetulle tasolle. " .
                                 "Syntaksi on .accesslevel <käyttäjä> <admin|user>";
        my $changenamedesc = " = Muuttaa annetun käyttäjän nimen säilyttäen tilastot. " .
                                 "Syntaksi on .changename <nykyinennimi> <uusinimi>";
        my $resetstatsdesc = " = Resetoi annetun käyttäjän tilastot. " .
                                 "Syntaksi on .resetstats <käyttäjä>";
        my $shutdownbotdesc = "= (Vain alkup. admin) Tallentaa asetukset ja datan sekä sammuttaa botin.";
        my $setdesc = "        = Muuttaa annetun muuttujan arvon tai tulostaa sen arvon. " .
                                 "Syntaksi on .set <muuttuja> <arvo>. Lisätietoa komennolla .set";
        my $addmapdesc = "     = Lisää annetun kartan äänestettäväksi kartaksi.";
        my $removemapdesc = "  = Poista annetun kartan äänestettävien karttojen listalta.";
        
        $self->say(channel => "msg", who => "$who", body => ".add $adddesc");
        $self->say(channel => "msg", who => "$who", body => ".out $outdesc");
        $self->say(channel => "msg", who => "$who", body => ".abort $abortdesc");
        $self->say(channel => "msg", who => "$who", body => ".replace $replacedesc");
        $self->say(channel => "msg", who => "$who", body => ".aoe $aoedesc");
        $self->say(channel => "msg", who => "$who", body => ".hilight $hilightdesc");
        $self->say(channel => "msg", who => "$who", body => ".report $reportdesc");
        $self->say(channel => "msg", who => "$who", body => ".voidgame $voidgamedesc");
        $self->say(channel => "msg", who => "$who", body => ".accesslevel $accessleveldesc");
        $self->say(channel => "msg", who => "$who", body => ".changename $changenamedesc");
        $self->say(channel => "msg", who => "$who", body => ".resetstats $resetstatsdesc");
        $self->say(channel => "msg", who => "$who", body => ".shutdownbot $shutdownbotdesc");
        $self->say(channel => "msg", who => "$who", body => ".set $setdesc");
        $self->say(channel => "msg", who => "$who", body => ".addmap $addmapdesc");
        $self->say(channel => "msg", who => "$who", body => ".removemap $removemapdesc");

        return;
    }
    
    # command .addmap
    elsif ($commands[0] eq '.addmap') {
    
        if ($accesslevel ne 'admin') {
            $self->emote(channel => "$chan", body => "$who ei ole admin.");
            return;
        }
        
        if ($#commands < 1) {
            $self->emote(channel => "$chan", body => "Syntaksi on $commands[0] <mapinnimi>");
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
            
        } else {
            $self->emote(channel => "$chan", body => "Mappi \"$commands[1]\" on jo karttavalikoimassa.");
            return;
        }
        
        $self->emote(channel => "$chan", body => "Mappi \"$commands[1]\" lisätty");
        return;
    }
    
    
    # command .removemap
    elsif ($commands[0] eq '.removemap') {
    
        if ($accesslevel ne 'admin') {
            $self->emote(channel => "$chan", body => "$who ei ole admin.");
            return;
        }
        
        if ($#commands < 1) {
            $self->emote(channel => "$chan", body => "Syntaksi on $commands[0] <mapinnimi>");
            return;
        }
        
        for my $i (0 .. $#maps) {
            if ($maps[$i] eq $commands[1]) {
                splice(@maps, $i, 1);
                $self->emote(channel => "$chan", body => "Mappi \"$commands[1]\" poistettu");
                return;
            }
        }
        
        return;
    }
    
    
    # command .set
    elsif ($commands[0] eq '.set') {
    
        if ($accesslevel ne 'admin') {
            $self->emote(channel => "$chan", body => "$who ei ole admin");
            return;
        }
        
        if ($#commands == 0) {
            $self->emote(channel => "$chan",
                         body => "Syntaksi on $commands[0] <muuttuja> <arvo>");
                        
            $self->emote(channel => "$chan",
                         body => "Listan muuttujista saa komennolla $commands[0] list");
            return;
        }
        
        if ($#commands > 0 && $commands[1] eq 'list') {
            $self->emote(channel => "$chan",
                         body => "Muuttujat: team1, team2, draw, maxplayers, gameserverip, gameserverport, gameserverpw, " .
                                 "voiceserverip, voiceserverport, voiceserverpw, requeststoreplace, requeststoremove" .
                                 "requeststoscore, initialpoints, pointsdelta, topdefaultlength");
            return;
        }
        
        my $outline;
        
        if ($#commands == 1) {
            if    ($commands[1] eq 'team1')             { $outline =  "$commands[1] = $team1"; }
            elsif ($commands[1] eq 'team2')             { $outline =  "$commands[1] = $team2"; }
            elsif ($commands[1] eq 'draw')              { $outline =  "$commands[1] = $draw"; }
            elsif ($commands[1] eq 'maxplayers')        { $outline =  "$commands[1] = $maxplayers"; }
            elsif ($commands[1] eq 'gameserverip')      { $outline =  "$commands[1] = $voiceserverip"; }
            elsif ($commands[1] eq 'gameserverpw')      { $outline =  "$commands[1] = $voiceserverpw"; }
            elsif ($commands[1] eq 'gameserverport')    { $outline =  "$commands[1] = $voiceserverport"; }
            elsif ($commands[1] eq 'voiceserverip')     { $outline =  "$commands[1] = $voiceserverip"; }
            elsif ($commands[1] eq 'voiceserverpw')     { $outline =  "$commands[1] = $voiceserverpw"; }
            elsif ($commands[1] eq 'voiceserverport')   { $outline =  "$commands[1] = $voiceserverport"; }
            elsif ($commands[1] eq 'requeststoreplace') { $outline =  "$commands[1] = $requeststoreplace"; }
            elsif ($commands[1] eq 'requeststoremove')  { $outline =  "$commands[1] = $requeststoremove"; }
            elsif ($commands[1] eq 'requeststoscore')   { $outline =  "$commands[1] = $requeststoscore"; }
            elsif ($commands[1] eq 'initialpoints')     { $outline =  "$commands[1] = $initialpoints"; }
            elsif ($commands[1] eq 'pointsdelta')       { $outline =  "$commands[1] = $pointsdelta"; }
            elsif ($commands[1] eq 'topdefaultlength')  { $outline =  "$commands[1] = $topdefaultlength"; } 
            else {
                $self->emote(channel => "$chan", body => "Virheellinen muuttujan nimi.");
                return;
            }
            
            
            $self->emote(channel => "$chan", body => $outline);
            return;
        }
        
        my $validvalue = 1;
        
        if    ($commands[1] eq 'team1')         { $team1 = $commands[2]; }
        elsif ($commands[1] eq 'team2')         { $team2 = $commands[2]; }
        elsif ($commands[1] eq 'draw')          { $draw = $commands[2];}
        
        elsif ($commands[1] eq 'gameserverip')   { $gameserverip = $commands[2]; }
        elsif ($commands[1] eq 'gameserverport') { $gameserverport = $commands[2]; }
        elsif ($commands[1] eq 'gameserverpw')   { $gameserverpw = $commands[2]; }
        
        elsif ($commands[1] eq 'voiceserverip') { $voiceserverip = $commands[2]; }
        elsif ($commands[1] eq 'voiceserverpw') { $voiceserverpw = $commands[2]; }

        elsif ($commands[1] eq 'maxplayers') {
            if ( containsletters($commands[2]) || $commands[2] < 0  || ($commands[2] % 2) != 0 ) {
                $validvalue = 0;
            } else { $maxplayers = $commands[2]; $teamsize = $maxplayers / 2; }
        }
        
        elsif ($commands[1] eq 'voiceserverport') {
            if ( containsletters($commands[2]) ) {
                $validvalue = 0;
            } else { $voiceserverport = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'requeststoreplace') {
            if ( containsletters($commands[2]) || $commands[2] < 0  ) {
                $validvalue = 0;
                
            } else { $requeststoreplace = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'requeststoremove') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $requeststoremove = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'initialpoints') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $initialpoints = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'pointsdelta') {
            if ( containsletters($commands[2]) || $commands[2] < 0 ) {
                $validvalue = 0;
            } else { $pointsdelta = $commands[2]; }
        }
        
        elsif ($commands[1] eq 'topdefaultlength') {
            if ( containsletters($commands[2]) || $commands[2] < 1 ) {
                $validvalue = 0;
            } else { $topdefaultlength = $commands[2]; }
            
        } else {
            $self->emote(channel => "$chan",
                         body => "Virheellinen muuttujan nimi.");
            return;
        }
        
        
        if ($validvalue) {
            $self->emote(channel => "$chan",
                         body => "Muuttujan $commands[1] arvo asetettu.");
            return;
            
        } else {
            $self->emote(channel => "$chan",
                         body => "Annettu arvo on virheellinen muuttujalle $commands[1].");
            return;
        }
        
        return;
    }
    
    
    # command .aoe
    elsif ($commands[0] eq '.aoe') {
    
        if ($accesslevel ne 'admin') {
            $self->emote(channel => "$chan",
                         body => "$who ei ole admin");
            return;
        }
        
        $self->say(channel => "msg", who => "Q", body => "CHANMODE $chan -N");
        
        my $playercount = $#players+1;
        my $noticemessage = "$chan - gatheriin ilmoittautuminen käynnissä! Pelaajia on $playercount/$maxplayers";
        
        my $nicks = $self->channel_data($chan);
        foreach my $nick_ (keys %$nicks) {
            $self->notice(channel => "msg", who => $nick_, body => $noticemessage);
        }
        
        #$self->notice(channel => $chan, body => $noticemessage);
        
        $self->say(channel => "msg", who => "Q", body => "CHANMODE $chan +N");
        
        return;
    }
    
    
    # command .hilight
    elsif ($commands[0] eq '.hilight' || $commands[0] eq '.hl') {
    
        if ($#commands == 0) {
            if ($accesslevel ne 'admin') {
                $self->emote(channel => "$chan",
                             body => "$who ei ole admin");
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
                
                # Exclude bot's nick too
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
            $self->emote(channel => "$chan",
                         body => "Syntaksi on $commands[0] <off|on>");
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
                             body => "$who on jo hilight-ignoressa.");
                
            } else {
                push(@hlignorelist, $who);
                
                $self->emote(channel => $chan,
                             body => "$who on nyt hilight-ignoressa.");
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
                             body => "$who ei ollut hilight-ignoressa.");
                             
            } else {
                $self->emote(channel => $chan,
                             body => "$who ei enää ole hilight-ignoressa.");
            }
            
            return;
        }
        
        return;
    }
    
    
    # command .foo
    elsif ($commands[0] eq '.foo') {
        return;
    }
    
    
}

sub voidvotes {
    for my $map (@maps) {
        $mapvotes{$map} = 0;
    }
}

sub voidusersvotes {
    my $self = shift;
    my $username = $_[0];
    
    if ( exists($mapvoters{$username}) && exists($mapvotes{$mapvoters{$username}}) ) {
        if ($mapvotes{$mapvoters{$username}} > 0) {
            $mapvotes{$mapvoters{$username}} -= 1;
        }
    }
    $mapvoters{$username} = "";
}

sub voidrequests {
    foreach (keys %replacereq) {
        $replacereq{$_} = "";
    }
    
    foreach (keys %removereq) {
        $removereq{$_} = "";
    }
    
    $team1captrequests = "";
    $team2captrequests = "";
    
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


sub mode {
   my $self = shift;
   my $mode = join ' ', @_;

   $poe_kernel->post ($self->{IRCNAME} => mode => $mode);
}


sub formatplayerlist {
    my $self = shift;
    my @pool = @_;
    
    my @formattedpool;
    for my $player (@pool) {
        push(@formattedpool, $player);
    }
    
    if ($#formattedpool > -1) {
        if ($formattedpool[0] eq $captain1 || $formattedpool[0] eq $captain2) {
            $formattedpool[0] .= "[C]";
        }
    }
    
    if ($#formattedpool > 0) {
        if ($formattedpool[1] eq $captain1 || $formattedpool[1] eq $captain2) {
            $formattedpool[1] .= "[C]";
        }
    }

    my $playerlist = join(', ', @formattedpool);

    return $playerlist;
}

sub formatteam {
    my $self = shift;
    my @team = @_;
    
    my @formattedteam;
    for my $player (@team) {
        push(@formattedteam, $player);
    }
    
    $formattedteam[0] .= "[C]";
    my $teamlist = join(', ', @formattedteam);
    
    return $teamlist;
}

sub containsletters {
    my $value = shift;
    
    if ($value =~ /[\p{L}]+/) {  # check if the given parameter contains any letters
        return 1;
    }
    return 0;
}

sub writedata {
    my $self = shift;
    my $userdatafilename = 'userdata.txt';
    my $gamedatafilename = 'gamedata.txt';
    my $userdatafile; my $gamedatafile;
    
    unless (open $userdatafile, '>', $userdatafilename
            or die "virhe ylikirjoittaessa tiedostoa $userdatafilename: $!") {
        return;
    }

    unless (open $gamedatafile, '>', $gamedatafilename
            or die "virhe ylikirjoittaessa tiedostoa $gamedatafilename: $!") {
        return;
    }
    
    foreach (keys %users) {
        print $userdatafile "$_=$users{$_}\n";
    }
    foreach (keys %games) {
        print $gamedatafile "$games{$_}\n";
    }
    
    return;
}

sub readdata {
    my $userdatafilename = 'userdata.txt';
    my $gamedatafilename = 'gamedata.txt';
    my $userdatafile; my $gamedatafile;
    my $line;
    
    if (-e $userdatafilename && (open $userdatafile, $userdatafilename) ) { 
        my @elements; my @values;
        while (<$userdatafile>) {
            $line = $_;
            chomp($line);
            @elements = split('=', $line);
            if ($#elements > 0) {
                @values = split('\.', $elements[1]);
                if ($#values >= 4) {
                    $users{$elements[0]} = $elements[1];
                    
                } else {
                    print STDERR "Virheellinen rivi tiedostossa $userdatafilename:\n$line\n";
                }
            }
        }
    }
    
    if (-e $gamedatafilename && (open $gamedatafile, $gamedatafilename) ) { 
        my @elements; my @values; my @values2;
        while (<$gamedatafile>) {
            $line = $_;
            chomp($line);
            @elements = split(',', $line);
            if ($#elements >= 3) {
                @values = split(':', $elements[0]);
                @values2 = split(':', $elements[1]);
                if ($#values > 0 && $#values2 > -1) {
                    $games{$values[0]} = $line;
                
                } else {
                    print STDERR "Virheellinen rivi tiedostossa $gamedatafilename:\n$line\n";
                }
                
            } else {
                print STDERR "Virheellinen rivi tiedostossa $gamedatafilename:\n$line\n";
            }
        }
    }
    return;
}

sub readcfg {
    my $cfgfilename = 'gatherbot.cfg';
    my $cfgfile;
    
    unless (-e $cfgfilename) { return; }
    unless (open $cfgfile, "$cfgfilename" or die "virhe avatessa tiedostoa $cfgfilename: $!") {
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
            if    ($elements[0] eq 'server')            { $server = $elements[1]; }
            elsif ($elements[0] eq 'chan')              { $chan = "#" . "$elements[1]"; }
            elsif ($elements[0] eq 'nick')              { $nick = $elements[1]; }
            elsif ($elements[0] eq 'authname')          { $authname = $elements[1]; }
            elsif ($elements[0] eq 'authpw')            { $authpw = $elements[1]; }
            elsif ($elements[0] eq 'team1')             { $team1 = $elements[1]; }
            elsif ($elements[0] eq 'team2')             { $team2 = $elements[1]; }
            elsif ($elements[0] eq 'draw' )             { $draw = $elements[1]; }
            elsif ($elements[0] eq 'maxplayers')        { $maxplayers = $elements[1]; $teamsize = $maxplayers / 2; }
            elsif ($elements[0] eq 'gameserverip')      { $gameserverip = $elements[1]; }
            elsif ($elements[0] eq 'gameserverport')    { $gameserverport = $elements[1]; }
            elsif ($elements[0] eq 'gameserverpw')      { $gameserverpw = $elements[1]; }
            elsif ($elements[0] eq 'voiceserverip')     { $voiceserverip = $elements[1]; }
            elsif ($elements[0] eq 'voiceserverport')   { $voiceserverport = $elements[1]; }
            elsif ($elements[0] eq 'voiceserverpw')     { $voiceserverpw = $elements[1]; }
            elsif ($elements[0] eq 'requeststoreplace') { $requeststoreplace = $elements[1]; }
            elsif ($elements[0] eq 'requeststoremove')  { $requeststoremove = $elements[1]; }
            elsif ($elements[0] eq 'requeststoscore')   { $requeststoscore = $elements[1]; }
            elsif ($elements[0] eq 'initialpoints')     { $initialpoints = $elements[1]; }
            elsif ($elements[0] eq 'pointsdelta')       { $pointsdelta = $elements[1]; }
            elsif ($elements[0] eq 'topdefaultlength')  { $topdefaultlength = $elements[1]; }
            
            elsif ($elements[0] eq 'admins') {
                my $adminsstring = join(' ', @values);
                @admins = split(/\s+/, $adminsstring);
            }
            elsif ($elements[0] eq 'maps') {
                my $mapsstring = join(' ', @values);
                @maps = split(/\s+/, $mapsstring);
            }
            
            else {
                print STDERR "Virheellinen rivi tiedostossa $cfgfilename:\n$line";
            }
        }
    }
    return;
}

sub writecfg {
    my $cfgfilename = 'gatherbot.cfg';
    my $cfgfile;
    
    unless (open $cfgfile, '>', $cfgfilename
            or die "virhe ylikirjoittaessa tiedostoa $cfgfilename: $!") {
        return;
    }
    
    my $requeststoreplacedesc = "# amount of requests needed by non-admins to replace someone";
    my $requeststoremovedesc  = "# amount of requests needed by non-admins to remove someone";
    my $requeststoscoredesc   = "# amount of requests needed by non-admins to report a score";
    my $initialpointsdesc     = "# the skill points everyone starts with";
    my $pointsdeltadesc       = "# the skill points delta on won/lost game";
    my $topdefaultlengthdesc  = "# the default length of .top list";
    
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
    
    my $chanwosign = substr($chan, 1);
    
    print $cfgfile  "$cfgheader" .
                    "\n" .
                    "\n" .
                    "# Bot related settings\n" .
                    "server            = $server\n" .
                    "chan              = $chanwosign\n" .
                    "nick              = $nick\n" .
                    "authname          = $authname\n" .
                    "authpw            = $authpw\n" .
                    "\n" .
                    "# Gather related settings\n" .
                    "team1             = $team1\n" .
                    "team2             = $team2\n" .
                    "draw              = $draw\n" .
                    "maxplayers        = $maxplayers\n" .
                    "admins            = @admins\n" .
                    "maps              = @maps\n" .
                    "gameserverip      = $gameserverip\n" .
                    "gameserverport    = $gameserverport\n" .
                    "gameserverpw      = $gameserverpw\n" .
                    "voiceserverip     = $voiceserverip\n" .
                    "voiceserverport   = $voiceserverport\n" .
                    "voiceserverpw     = $voiceserverpw\n" .
                    "requeststoreplace = $requeststoreplace\t\t\t$requeststoreplacedesc\n" .
                    "requeststoremove  = $requeststoremove\t\t\t$requeststoremovedesc\n" .
                    "requeststoscore   = $requeststoscore\t\t\t$requeststoscoredesc\n" .
                    "initialpoints     = $initialpoints\t\t$initialpointsdesc\n" .
                    "pointsdelta       = $pointsdelta\t\t\t$pointsdeltadesc\n" .
                    "topdefaultlength  = $topdefaultlength\t\t\t$topdefaultlengthdesc";
    return;
}

readcfg();
readdata();

GatherBot->new(
    server =>   "$server",
    channels => [ "$chan" ],
    nick =>     "$nick",
    flood =>    0,
)->run();
