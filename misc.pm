#!/usr/bin/perl

use strict;

sub vprint
{
  print "$_[0]" if $GLOBAL::verbosity > 0;
}

sub vvprint
{
  print "$_[0]" if $GLOBAL::verbosity > 1;
}

sub vvvprint
{
  print "$_[0]" if $GLOBAL::verbosity > 2;
}

1;

