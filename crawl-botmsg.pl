#!/usr/bin/perl

use strict;
use utf8;
use vars qw($VERSION %IRSSI);

use Irssi;
$VERSION = '1.00';
%IRSSI = (
  authors     => 'Borek Lupomesky',
  contact     => 'borek@lupomesky.cz',
  name        => '##crawl Bot Messages Colorizer',
  description => 'This program colorizes announcements from bots' .
                 'on ##crawl channel',
  license     => 'Public Domain'
);

#===========================================================================
# USER CONFIGURATION SECTION START
#===========================================================================

# name of the window the announcements will be directed to; if this window
# does not exist, the colorized messages are displayed in the main window
# instead

my $msg_window_name = 'crawl-announce';

# following monster names are displayed in bold in kill announcements

my @mon_hlt = (
  'Mara', 'Mennas', 'Tiamat', 'the royal jelly', 'Serpent of Hell',
  'Geryon', 'Antaeus', 'Asmodeus', 'Dispater', 'Cerebov', 'Lom Lobon',
  'Ereshkigal', 'Gloorx Vloq', 'Mnoleg'
);

# following nicks are displayed in bold

my @nick_hlt = (
  'SomeNick', 'AnotherNick', 'YANick4', 'crate', 'elliptic'
);

#---- definitions ----------------------------------------------------------

my $debug = 0;

# list of known announcement bots; Kramell announces for multiple servers

my %bots = (
 'Henzell'  => [ 'CAO',  '!', 10 ],
 'Gretell'  => [ 'CDO',  '@', 3  ],
 'Sizzell'  => [ 'CSZO', '%', 5  ],
 'Lantell'  => [ 'CUE',  '$', 6  ],
 'Ruffell'  => [ 'RHF',  '#', 7  ],
 'Rotatell' => [ 'CBRO', '^', 2  ],
 'Eksell'   => [ 'CXC',  ' ', 9  ],
 'Jorgrell' => [ 'CJR',  '=', 4  ],
 'CPO'      => [ 'CPO',  'x', 4  ],
 'Kramell'  => [ '---',  'x', 11 ]
);

# channel name we will be watching

my $channel = '##crawl';

#--- public message handler ------------------------------------------------

sub pubmsg
{
  my ($server, $msg, $nick, $address, $target) = @_;
  my $msg_window_irssi = Irssi::window_find_name($msg_window_name);
  my $nick_quote = quotemeta($nick);
  my $explicit_server_acronym;
  
  if(!$msg_window_irssi) {
    $msg_window_irssi = Irssi::window_find_item($channel);
  }
  if(!$msg_window_irssi) {
    print "Can't find target window, directing all output to default windows instead";
  }

  #--- Kramell inserts U+200B ZERO-WIDTH SPACE into nick

  if($nick eq 'Kramell') {
    $msg =~ s/[^[:ascii:]]//g;
    $msg =~ s/\s+\[([A-Z]+)\s.*$//;
    $explicit_server_acronym = $1;
  }

  #--- following block executed if the message is from one of the recognized
  #--- announcement bots
  
  if($target eq $channel && scalar(grep(/^$nick_quote$/, keys %bots))) {
    
    eval {

      #--- server name (from bot nick)

      my $server_name = $explicit_server_acronym // $bots{$nick}[0];
      my $server_color = $bots{$nick}[2];
      my @msg;
      my $nick_col = '09';

      # Kramell special-case
      if($nick eq 'Kramell' && $explicit_server_acronym) {
        for my $k (keys %bots) {
          if($bots{$k}[0] eq $explicit_server_acronym) {
            $server_color = $bots{$k}[2];
            last;
          }
        }
      }

      push(@msg, sprintf("\x03%s%4s\x0F", $server_color, $server_name));

      #--- player name with combo and level
      # 1. <Name> (L<level> <combo>)
      # 2. <Name> the <title> (L<level> <combo>)
      if(
        $msg =~ s/^([a-z0-9]+) \((L\d{1,2} \w{4})\) //i ||
        $msg =~ s/^([a-z0-9]+ the .+) \((L\d{1,2} \w{4})\),? //i
      ) {
        my $plr_name = $1;
        my $plr_char = $2;
        my $plr_nick;
        if($plr_name =~ /^(\w+)/) { $plr_nick = $1; }
        # condition on which the nick is highlighted
        if(
          $server->{'nick'} eq $plr_nick        # either current IRC nick
          || grep { lc($plr_nick) eq lc($_) } @nick_hlt
        ) {
          $nick_col = '08';
        }
        push(@msg, sprintf("\x03%s%s\x0F (\x03%s%s\x0F)", $nick_col, $plr_name, $nick_col, $plr_char));
      } else {
        die;
      }

      #--- place
      my $place;
      if($msg =~ s/\s+(\([^()]+\))$//i) {
        $place = $1;
      }
      
      #--- "became a worshipper"
      if($msg =~ s/became a worshipper of (.+)\.$//i) {
        push (@msg, sprintf("\x0310became a worshipper of \x02%s\x02.\x0F", $1));
      }
      
      #--- "became a champion"
      if($msg =~ s/became the champion of (.+)\.$//i) {
        push (@msg, sprintf("\x0310\x02became the champion of %s\x02.\x0F", $1));
      }
      
      #--- "abandoned <god>"
      if($msg =~ s/abandoned (.+)\.$//i) {
        push (@msg, sprintf("\x0310abandoned %s.\x0F", $1));
      }

      #--- "mollified <god>"
      if($msg =~ s/mollified (.+)\.$//i) {
        push (@msg, sprintf("\x0310mollified %s.\x0F", $1));
      }

      #--- getting killed
      if($msg =~ s/([\w\s,]+) (by|to|blew themself up|shot themself with|dead) (.+) (on|in) (.+), with (\d+ points) after (\d+ turns) and ([0-9:,]+)\.$//i) {
        push(@msg, sprintf("\x035%s %s \x02%s\x02 %s \x02%s\x02, with \x02%s\x02 after \x02%s\x02 and \x02%s\x02.", $1, $2, $3, $4, $5, $6, $7, $8));
      }

      #--- killing a unique or ghost
      if($msg =~ s/killed (.+)\.$//i) {
        my $mon = $1;
        if(scalar(grep(/^$mon$/, @mon_hlt))) {
          push(@msg, sprintf("\x037killed \x02%s\x02.\x0F", $mon));
        } else {
          if($mon =~ /^the ghost of\s(\w+)\s.*$/) {
            if(lc($1) eq lc($server->{nick})) {
              push@msg, sprintf("\x037killed \x02%s\x02.\x0F", $mon);
            } else {
              push(@msg, sprintf("\x037killed %s.\x0F", $mon));
            }
          } else {
            push(@msg, sprintf("\x037killed %s.\x0F", $mon));
          }
        }
      }
      
      #--- banishing unique or ghost
      if($msg =~ s/banished (.+)\.$//i) {
        push(@msg, sprintf("\x037banished %s.\0x0F", $1));
      }
      
      #--- finding a rune
      if($msg =~ s/found (a|an) (\w+) rune of Zot\.$//i) {
        push(@msg, sprintf("found $1 \x02$2 rune\x0F of Zot.", $1, $2));
      }

      
      #--- quitting
      if($msg =~ s/(.*)quit the game (in|on) (.+), with (\d+ points) after (\d+ turns) and ([0-9:,]+)\.$//i) {
        push(@msg, sprintf("\x035%squit the game %s \x02%s\x02, with \x02%s\x02 after \x02%s\x02 and \x02%s\x02.\x0F", $1, $2, $3, $4, $5, $6));
      }

      #--- entering branch
      if($msg =~ s/entered (.*)\.$//i) {
        push(@msg, sprintf("\x036entered \x02%s\x02.\x0F", $1));
      }
      
      #--- getting abyssed
      if($msg =~ s/was cast into the Abyss!(\s\(.+\))?$//i) {
        if($1) {
          push(@msg, sprintf("\x036was cast into \x02the Abyss!\x02%s\x0F", $1));
        } else {
          push(@msg, "\x036was cast into \x02the Abyss!\x0F");
        }
      }
      
      #--- entering the Abyss
      if($msg =~ s/entered the Abyss!$//i) {
        push(@msg, "\x036entered \x02the Abyss\x02!\x0F");
      }

      #--- escaping the Abyss
      if($msg =~ s/escaped from the Abyss!$//i) {
        push(@msg, sprintf("\x036escaped from the Abyss!\x0F", $1));
      }
      
      #--- escaping to the Abyss
      if($msg =~ s/escaped \(hah\) into the Abyss!$//i) {
        push(@msg, "\x036escaped (hah) into \x02the Abyss\x02!\x0F");
      }
      
      #--- getting shafted
      if($msg =~ s/fell down a shaft to (.+).$//i) {
        push(@msg, sprintf("\x036fell down a shaft to \x02%s\x02.\x0F", $1));
      }
          
      #--- reaching level
      if($msg =~ s/reached (level \d{1,2}) of ((|the )[\w\s]+)\.$//i) {
        push(@msg, sprintf("\x036reached \x02%s\x02 of \x02%s\x02.\x0F", $1, $2));
      }
      
      #--- leaving Ziggurat
      if($msg =~ s/left a Ziggurat at level (\d+)\.$//i) {
        push(@msg, sprintf("\x036left \x02a Ziggurat\x02 at level \x02%d\x02.\x0F", $1));
      }
      
      #--- finding the Orb of Zot
      if($msg =~ s/found the Orb of Zot!$//i) {
        push(@msg, "\x02found the Orb of Zot!\x02");
      }
      
      #--- escaping with the Orb
      if($msg =~ s/([\w\s,]+)escaped with the Orb and (\d{1,2}) runes!?, with (\d+ points) after (\d+ turns) and ([0-9:,]+)\.$//i) {
        push(@msg, sprintf("%s\x16escaped with the Orb and %d runes\x16, with \x02%s\x02 after \x02%s\x02 and \x02%s\x02.", $1, $2, $3, $4, $5));
      }
      
      #--- remaining message
      push(@msg, $msg) if $msg;
      push(@msg, $place) if $place;
      
      #--- assemble the complete message
      my $msg_out = join(' ', @msg);
      if($msg_window_irssi) {
        $msg_window_irssi->print($msg_out, MSGLEVEL_PUBLIC);
      } else {
        print($msg_out, MSGLEVEL_PUBLIC);
      }

      #---
      Irssi::signal_stop();
    
    };
  }
}


#--- main ------------------------------------------------------------------

Irssi::signal_add_last('message public', 'pubmsg');
