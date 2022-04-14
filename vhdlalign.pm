#!/usr/bin/perl

use File::Basename;
use FileHandle;
use Cwd;

use strict;

# align vhdl file
sub align_file
{
  my $lines    = $_[0];
  my $string;

  foreach my $line (@{$lines})
  {
    chomp($line);
    $line = lc($line);
    $line =~ s/^/ /g;                      #add a space at start
    $line =~ s/$/ /g;                      #add a space at end
    $line =~ s/\-\-.*//g;                  #remove comments
    $line =~ s/;\s+/ ;/g;                  #add space
    $line =~ s/\(/ \( /g;                  #add space
    $line =~ s/\)/ \) /g;                  #add space
    $line =~ s/,/ , /g;                    #add space
    $line =~ s/:/ : /g;                    #add space
    $line =~ s/</ < /g;                    #add space
    $line =~ s/< =/<=/g;                   #remove space
    $line =~ s/>/ > /g;                    #add space
    $line =~ s/= >/=>/g;                   #remove space
    $line =~ s/\t+/ /g;                    #No tabs wanted
    $line =~ s/\s+/ /g;                    #Only single spaces wanted
    if(!($line =~ /\S/))                   #Skip empty lines
    {
      next;
    }
    $line =~ s/;/;\n/g;                    #Append a \n to line after ;
    $line =~ s/ is / is \n/ig;             #Append a \n to line after is
    $line =~ s/ block / block \n/ig;       #Append a \n to line before use
    $line =~ s/ generate / generate \n/ig; #Append a \n after generate

    $line =~ s/ generic / \n generic /ig;  #Prepend \n befor generic to workaround component declaration without 'is'
    $line =~ s/ port / \n port /ig;

    # cocanate the individual parts
    $string = $string . $line;
  }

  return \$string;
}

# grep relevant info from aligned vhdl
sub grep_file
{
  my $string = $_[0];
  my $ref    = [];

  # split string into lines
  my @lines = split("\n", $$string);

  foreach my $line (@lines)
  {
    #chomp($line);
    if($line =~ /( generate )|( process )|( signal )|( block )/i)
    {
      next;
    }

    if($line =~ /( configuration )|( component )|( package )|( entity )|( architecture )|( library )|( use )|((\w+)(\s+)(:)(\s+)(\w+).*(port\s+map))/i)
    {
      $line =~ s/port\s+map.*/port map/ig; # what about gerneric map ??

      #$line =~ s/;/;\n/ig;
      #print "test: $line\n";
      push(@{$ref}, \$line);
    }
  }

  return $ref;
}


1;

