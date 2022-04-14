#!/usr/bin/perl
use File::Basename;
use FileHandle;
use vhdlalign;
use gen_makefile;
use misc;
use Cwd;

use strict;

# generate dependencies for a given library
sub gen_lib
{
  my $lib           = $_[0];
  my $sub_makefiles = $_[1];

  vprint("*********************************************************************\n");
  vprint("** generate dependencies for vhdl library $lib\n");
  vprint("*********************************************************************\n");

  # now we check the current directory structure
  process_lib($lib, $lib, $sub_makefiles);
}

# process the library
sub process_lib
{
  my $lib           = $_[0];
  my $module        = $_[1];
  my $sub_makefiles = $_[2];
  chdir($module);

  my $fh = new FileHandle;
  opendir($fh, "./");
  
  my $already_processed = 0;
  while(my $element = readdir($fh))
  { 
    if((-d $element) && ($element ne ".") && ($element ne "..") && ($element ne ".svn"))
    {
      if (($element ne "rtl") && ($element ne "rtl_tb") && ($element ne "beh")) 
      {
        vprint("$lib> found module $element\n");
        process_lib($lib, $element, $sub_makefiles);
      }
      elsif(! $already_processed)
      {
        my $act_dir = cwd();
        push(@{$sub_makefiles}, $act_dir . "/$module");
        process_module($lib, $module);
        $already_processed = 1;
      }
    }
  }
  closedir($fh);

  chdir("../");
}

# process the module (note that lib can be a module too)
sub process_module
{
  my $lib      = $_[0];
  my $module   = $_[1];
  my %filebase = ();

  vprint("$lib> process module $module\n");

  my $act_dir = cwd();
  my @files = glob($act_dir . "/rtl/" . "*.vhd");
  push(@files, glob($act_dir . "/rtl_tb/" . "*.vhd"));
  push(@files, glob($act_dir . "/beh/" . "*.vhd"));
  
  foreach my $file (@files)
  {
    my $fh = new FileHandle;
    open($fh, $file) or die "could not open $file\n";

    my $lines = [<$fh>];
    close($fh);

    my $aligned = align_file($lines);
    my $greped  = grep_file($aligned);

    $filebase{$file} = $greped;
  }

  # create makefile for the current module
  gen_makefile($lib, $module, \%filebase);
}

1;

