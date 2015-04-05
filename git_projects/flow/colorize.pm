#!/usr/bin/perl

my %color = ('red'    => "\033[0;31m",
             'yellow' => "\033[0;33m",
             'off'    => "\033[0;37m"
            );

while(my $line  = <STDIN>)
{
  my $color = $color{'off'};

  if($line =~ /warning/i)
  {
    $color = $color{'yellow'};
  }

  if($line =~ /error/i)
  {
    $color = $color{'red'};
  }

  print $color . "$line" . $color{'off'};
}

