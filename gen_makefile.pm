#!/usr/bin/perl

use File::Basename;
use FileHandle;
use misc;
use Cwd;

use strict;

our %database = ();
our $opt      = {};

# some configurations -> move to config
our $entity_prefix       = "";
our $entity_suffix       = "";
our $architecture_prefix = "";
our $architecture_suffix = "*_a";
our $testbench_prefix    = "";
our $testbench_suffix    = "";

# set the options for this module
sub set_makefile_options
{
  my $ref_option = $_[0];
  $opt = $ref_option;
}

# procedure to generate makefile
sub gen_makefile
{
  my ($lib, $module, $reffilebase) = @_;

  # just because %database is global
  local(%database);

  vprint("$lib> create makefile for module $module\n");
  gen_database($lib, $module, $reffilebase);

  # issue a warning if run under windows
  system("echo \"Warning: makefile for $module\_ghdl.mk will not work with windows ghdl port\" | \$GIT_PROJECTS/flow/colorize.pm") if $GLOBAL::OSTYPE eq "cygwin\n";

  gen_ghdl_makefile($lib, $module)     if $GLOBAL::toolchain eq "ghdl";
  gen_ncsim_makefile($lib, $module)    if $GLOBAL::toolchain eq "ncsim";
  gen_modelsim_makefile($lib, $module) if $GLOBAL::toolchain eq "modelsim";
  gen_isim_makefile($lib, $module)     if $GLOBAL::toolchain eq "isim";
}

# generate database
sub gen_database
{
  my ($lib, $module, $reffilebase) = @_;

  foreach my $file (keys(%$reffilebase))
  {    
    my $lines = $$reffilebase{$file};

    foreach my $refline (@{$lines})
    {
      chomp($$refline);

      # begin search for use (ignore use in configurations)
      if($$refline =~ / use /i && $$refline =~ /;/)
      {
        if(!($$refline =~ / configuration /i || $$refline =~ / entity /i))
        {
          (my $use = $$refline) =~ s/ use / /ig;
          $use                  =~ s/.all/ /ig;
          $use                  =~ s/;/ /g;
          $use                  =~ s/,/ /g;
          $use                  =~ s/ //g;
          
          my @pkg_element = split(/\./, $use);
          my $dep_lib     = $pkg_element[0];
          my $pkg         = $pkg_element[1];
          
          if($dep_lib =~ /work/ig) # map work library when refered to
          {
            $dep_lib = $lib;
          }
                
          if(!($dep_lib =~ /ieee/ig | $dep_lib =~ /std/ig) and !defined($GLOBAL::blacklist{$dep_lib}))
          {
            vvprint("$lib> $file uses package \"$pkg\" from lib \"$dep_lib\"\n");

            my $dep_file;
            get_dep_file($dep_lib, $pkg, \$dep_file, \&check_pkg);
            
            if(defined($dep_file))
            {
              #add_entry($file, $lib, $dep_file);
              add_entry($file, $dep_lib, $dep_file);
            }
            else
            {
              die "could not find $pkg in $dep_lib\n";
            }
          }
        }
      }
      # end search for use

      # begin search for components
      #if(($$refline =~ / component /i && $$refline =~ / port /i) || ($$refline =~ / component /i && $$refline =~ / is /i))
      if(($$refline =~ / component /i && $$refline =~ / port /i) || ($$refline =~ / component /i))
      {
        if(!($$refline =~ / end /i))
        {
          # make sure it is a package file otherwise the instanciation will do
          # the actual job and the component declaration can be ignored
          if(is_pkg($file))
          {
            if($$refline =~ /(\w+)(\s+)(\w+)/)
            {
              my $inst_name = $3;
              vvprint("$lib> $file declares component \"$inst_name\" as package\n");
               
              my $dep_file;
              get_dep_file($lib, $inst_name, \$dep_file, \&check_entity);

              if(defined($dep_file))
              {
                add_entry($file, $lib, $dep_file);
              }
              else
              {
                die "could not find $inst_name in \"work\"\n";
              }
            }
          }
          # if it is not a package we handle the dependencies right here
          # note: entity instanciation is not handled here 
          else
          {
            if($$refline =~ /(component)(\s+)(\w+)/)
            {
              my $inst_name = $3;
              $inst_name    =~ tr/A-Z/a-z/;
              vvprint("$lib> $file has component instance \"$inst_name\"\n");

              my $dep_file;
              get_dep_file($lib, $inst_name, \$dep_file, \&check_entity);

              if(defined($dep_file))
              {
                add_entry($file, $lib, $dep_file);
              }
              else
              {
                die "could not find $inst_name in \"work\"\n";
              }
            }
          }
        }
      }
      # end search for components

      # begin search for instances
      if($$refline =~ / : / && !($$refline =~ /;/))
      {
        if(($$refline =~ /entity/)) # an entity instantiation
        {
          if($$refline =~ /(\w+)(\s+)(:)(\s+)(\w+)(\s+)(\w+)(.)(\w+)/)
          {
            my $dep_lib   = $7;
            my $inst_name = $9;
            
            if($dep_lib =~ /work/ig) # map work library when refered to
            {
              $dep_lib = $lib;
            }
             
            vvprint("$lib> $file has entity instance \"$inst_name\" from lib \"$dep_lib\"\n");

            my $dep_file;
            get_dep_file($dep_lib, $inst_name, \$dep_file, \&check_entity);

            if(defined($dep_file))
            {
              #add_entry($file, $lib, $dep_file);
              add_entry($file, $dep_lib, $dep_file);
            }
            else
            {
              die "could not find $inst_name in $dep_lib\n";
            }
          }
        }
      }
      # end search for instances
      
      # begin search for architecture
      if(${$$opt{'sep-arch'}{'ref'}} == 1)
      {
        if($$refline =~ /^(\s+)(architecture)(\s+)(\w+)(\s+)(of)(\s+)(\w+)(\s*)(\w*)/)
        {
          my $entity = $8;

          my $dep_file;
          get_dep_file($lib, $entity, \$dep_file, \&check_entity);
          
          if(defined($dep_file))
          {
            my @file_parsed     = fileparse($file, ".vhd");
            my @dep_file_parsed = fileparse($dep_file, ".vhd");

            # only add to database if the base names differ
            my $base_idx = 0;
            if($file_parsed[$base_idx] ne $dep_file_parsed[$base_idx])
            {
              add_entry($file, $lib, $dep_file);
              vvvprint("$lib> found splitted entity  / architecture pair $file_parsed[$base_idx].vhd and $dep_file_parsed[$base_idx].vhd\n");
            }
          }
          else
          {
            die "could not find $entity in $lib\n";
          }
        }
      }
      # end search for architecture

      # begin search for package body
      if(${$$opt{'sep-body'}{'ref'}} == 1)
      {
        if($$refline =~ /^(\s+)(package)(\s+)(body)(\s+)(\w+)(\s*)(\w*)/)
        {
          my $pkg = $6;
          
          my $dep_file;
          get_dep_file($lib, $pkg, \$dep_file, \&check_pkg);
          
          if(defined($dep_file))
          {
            my @file_parsed     = fileparse($file, ".vhd");
            my @dep_file_parsed = fileparse($dep_file, ".vhd");

            # only add to database if the base names differ
            my $base_idx = 0;
            if($file_parsed[$base_idx] ne $dep_file_parsed[$base_idx])
            {
              add_entry($file, $lib, $dep_file);
              vvvprint("$lib> found splitted package / body pair $file_parsed[$base_idx].vhd and $dep_file_parsed[$base_idx].vhd\n");
            }
          }
          else
          {
            die "could not find $pkg in $lib\n";
          }
        }
      }
      # end search for package body
      
      # add file to database in case there are no further dependencies
      if(! defined($database{$file}))
      {
        $database{$file} = [];
      }
    }
  }
}

# get the dependency file to a given lib.identifier
sub get_dep_file
{
  my ($lib, $identifier, $ref_vhdl_file, $check) = @_;

  my $act_dir = cwd();
  my $fh      = new FileHandle;
  my $root    = $ENV{'GIT_PROJECTS'};
  my $dir     = $root . "/vhdl/" . $lib;

  chdir($dir) or die "could not open directory $dir\n";
  opendir($fh, "./");

  # cycle through the folders to find rtl files
  my $found_candidate = 0;
  while(my $element = readdir($fh))
  {
    if( (-d $element) && ($element ne ".") && ($element ne "..") && ($element ne ".svn"))
    {
      if(($element ne "rtl") && ($element ne "rtl_tb") && ($element ne "beh"))
      {
        # we need to iterate until $lib/$module/.../rtl(_tb)
        my $lib_module = $lib . "/" .$element;
        get_dep_file($lib_module, $identifier, $ref_vhdl_file, $check);
      }
      else
      {
        # we are in an rtl or rtl_tb folder, so check files
        my $candidate = &$check($element, $identifier);
        if(defined($candidate))
        {
          my $vhdl_file = $lib . "/" . $candidate;
          if($found_candidate)
          {
            die "found 2nd candidate $vhdl_file for $identifier\n";
          }
          # return the dependency file
          vvvprint("$lib> found file $vhdl_file to contain \"$identifier\"\n");
          $$ref_vhdl_file  = $vhdl_file;
          $found_candidate = 1;
        }
      }
    }
  }

  closedir($fh);
  chdir($act_dir);
}

# check for package
sub check_pkg
{
  my ($lib_module, $pkg) = @_;
  
  # try to find file through naming convention
  my $candidate = $lib_module . "/" . $pkg . ".vhd";

  if(-e $candidate)
  { 
    my $fh = new FileHandle;
    open($fh, $candidate) or die "could not open $candidate";
    my $lines = [<$fh>];
    close($fh);

    # now make sure the candidate really contains the pkg
    my $aligned = align_file($lines);
    my $greped  = grep_file($aligned);

    foreach my $line (@{$greped})
    {
      chomp($$line);
      if($$line =~ /^(\s+)(package)(\s+)(\w+)(\s*)(\w*)/)
      {
        # compare if packet fits
        if($4 eq $pkg)
        {
          return $candidate;
        }
      }
    }
    die "$candidate does not contain pkg $pkg\n";
  }
  elsif( ${$$opt{'break-naming'}{'ref'}} == 1 ) # only if broken naming conventions are allowed
  {
    # try to find through scanning all files in directory
    my @files = glob($lib_module . "/" . "*.vhd");
    foreach my $file (@files)
    {
      my $fh = new FileHandle;
      open($fh, $file);
      my $lines = [<$fh>];
      close($fh);

      my $aligned = align_file($lines);
      my $greped  = grep_file($aligned);

      foreach my $line (@{$greped})
      {
        chomp($$line);
        if($$line =~ /^(\s+)(package)(\s+)(\w+)(\s*)(\w*)/)
        {
          # compare if package fits
          if($4 eq $pkg)
          {
            vvvprint("found package \"$pkg\" in file $file breaking the naming convention\n");
            return $file;
          }
        }
      }
    }
  }
  
  # return nothing if not successfull
  return;
}

# check for entity (entity instanciation)
sub check_entity
{
  my ($lib_module, $inst_name) = @_;
  
  # make an educated guess...
  my $candidate = $lib_module . "/" . $entity_prefix . $inst_name . $entity_suffix . ".vhd";

  # return value
  my $dep_file;
  my @dep_file;
  my $found_dep_file = 0;

  if(-e $candidate)
  { 
    my $fh = new FileHandle;
    open($fh, $candidate) or die "could not open $candidate";
    my $lines = [<$fh>];
    close($fh);

    # now make sure the candidate really contains the entity
    my $aligned = align_file($lines);
    my $greped  = grep_file($aligned);

    foreach my $line (@{$greped})
    {
      chomp($$line);
      if($$line =~ /^(\s+)(entity)(\s+)(\w+)(\s*)(\w*)/)
      {
        # compare if entity fits
        if($4 eq $inst_name)
        {
          $found_dep_file = 1;
          $dep_file       = $candidate;
          last;
        }
      }
    }

    die "$candidate does not contain entity $inst_name\n" if $found_dep_file == 0;
  }
  elsif( ${$$opt{'break-naming'}{'ref'}} == 1 ) # only if broken naming conventions are allowed
  {
    # try to find through scanning all files in directory
    my @files = glob($lib_module . "/" . "*.vhd");
    foreach my $file (@files)
    {
      my $fh = new FileHandle;
      open($fh, $file);
      my $lines = [<$fh>];
      close($fh);

      my $aligned = align_file($lines);
      my $greped  = grep_file($aligned);

      foreach my $line (@{$greped})
      {
        chomp($$line);
        if($$line =~ /^(\s+)(entity)(\s+)(\w+)(\s*)(\w*)/)
        {
          # compare if entity fits
          if($4 eq $inst_name)
          {
            vvvprint("found entity \"$inst_name\" in file $file breaking the naming convention\n");
            $dep_file = $file;
            last;
          }
        }
      }
    }
  }

  # undefined if not successfull
  return $dep_file;
}

# check if file is a package
sub is_pkg
{
  my $file = $_[0];
  
  # just guess from the filename
  if($file =~ /_pkg/i)
  {
    return 1;
  }
  
  return 0;
}


# add entry to the database
sub add_entry
{
  my ($file, $lib, $dep_file) = @_;
  my $entry = [$lib, $dep_file];

  push(@{$database{$file}}, $entry)
}


# read configuration file
sub read_cfg
{
  my $cfg_file = $_[0];

  my $cfg = new FileHandle;
  #my $cfg_file = $ENV{'GIT_PROJECTS'} . "/ghdl.ini";
 
  open($cfg, $cfg_file) or die "could not open $cfg_file\n";
  my $lines = [<$cfg>];
  close($cfg);

  my %flags;
  my $key = "";

  # read config file into a database
  foreach my $line (@{$lines})
  {
    chomp($line);
    $line =~ s/#.*//g;             # remove comments
    next if( !($line =~ /\S/) );   # skip empty lines

    if($line =~ /^\[.*/g)          # found a key
    {
      $line =~ s/\[//g;            # remove '['
      $line =~ s/\]//g;            # remove ']'
      $key = $line;
      next;
    }
    push(@{$flags{$key}}, $line);
  }

  # return reference to hash
  return \%flags;
}


# generate makefile for ghdl toolchain
sub gen_ghdl_makefile
{
  my ($lib, $module) = @_;

  my $fh = new FileHandle;
  open($fh, ">$module" . "_ghdl.mk") or die "could not create makefile for $module\n";

  my $MOD_LIB    = uc($module) . "_LIB";
  my $MOD        = uc($module) . "_MOD";
  my $COM_FLAGS  = uc($module) . "_COMFLAGS";
  my $ELAB_FLAGS = uc($module) . "_ELABFLAGS"; 

  my $timestamp = localtime();
  my $user      = $ENV{'USER'};
  my $host      = $ENV{'HOSTNAME'};

  my $GHDL      = $ENV{'GHDL'};

  if(!defined($GHDL))
  {
    $GHDL = "ghdl"
  }

  print $fh "# automatic generated ghdl makefile do not edit manually\n";
  #print $fh "# $timestamp by $user\@$host for architecture $GLOBAL::OSTYPE\n\n";
  
  print $fh "# library and module name\n";
  print $fh "$MOD_LIB = $lib\n";
  print $fh "$MOD = $module\n\n";

  print $fh "# compiler and flags\n";
  print $fh "COMP = $GHDL -a\n";
  print $fh "ELAB = $GHDL -e\n";

  # read compile flags from config file
  my $ref_flags = read_cfg($ENV{'GIT_PROJECTS'} . "/ghdl.ini");

  # extract compile flags from database
  my $add_comp_flags = "";
  foreach my $line (@{$$ref_flags{'compile_flags'}})
  {
    $add_comp_flags = $add_comp_flags . " $line";
  }

  # extract elaborate flags from database
  my $add_elab_flags = "";
  foreach my $line (@{$$ref_flags{'elaborate_flags'}})
  {
    $add_elab_flags = $add_elab_flags . " $line";
  }

  # generate ghdl compile flags
  my $compile_flags = "--work=\${$MOD_LIB} --workdir=\$\$DEST_PROJECTS/\${$MOD_LIB}/ghdl $add_comp_flags";
  my $elab_flags    = "--work=\${$MOD_LIB} --workdir=\$\$DEST_PROJECTS/\${$MOD_LIB}/ghdl $add_elab_flags";

  print $fh "$COM_FLAGS = $compile_flags\n";
  print $fh "$ELAB_FLAGS = $elab_flags\n";

  # generate entry point
  print $fh "\n# to have an entry point\n";
  print $fh "all:";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    my $prefix = "\${DEST_PROJECTS}/\${$MOD_LIB}/ghdl/";

    $base      = lc($base);
    my $dep    = $prefix . $base . ".o";

    print $fh " $dep";

    if(${$$opt{'elab'}{'ref'}} == 1)
    {
      # in case of a testbench add executable as dependency
      if(($base =~ /^tb_/) or ($base =~ /_tb$/))
      {
        my $dep = $prefix . $base;
        print $fh " $dep";
      }
    }
  }
  print $fh "\n";

  if(${$$opt{'elab'}{'ref'}} == 1)
  {
    # generate targets to elaborate entities
    my $elaborate_cmd   = "\$(ELAB) \$($ELAB_FLAGS)";
    print $fh "\n# targets to elaborate entities\n";
    foreach my $file (keys(%database))
    {
      my ($base, $path, $suffix) = fileparse($file, ".vhd");

      $base = lc($base);

      # only "testbench entities" will be elaborated 
      if(($base =~ /^tb_/) or ($base =~ /_tb$/))
      {
        my $prefix     = "\${DEST_PROJECTS}/\${$MOD_LIB}/ghdl/";
        my $target     = $prefix . $base;
        my $dep        = $prefix . $base . ".o";

        print $fh "$target: $dep\n" .
                  "\t\@echo \"elaborate entity...\" $base\n" .
                  "\t\@$elaborate_cmd $base\n" .
		  #NOTE: this is a hacky way to get a $1 for additional command line arguments into the shell script
		  "\t\@echo -n \"#/bin/bash\\n\\nghdl -r $elab_flags \" > $target.sh\n" .
		  "\t\@echo -n \"$base \" >> $target.sh\n" .
		  "\t\@echo -n \'\$\$\' >> $target.sh\n" .
		  "\t\@echo \"1\" >> $target.sh\n\n";
      }
    }
  }

  # generate targets to analyze files
  my $analyze_cmd   = "\$(COMP) \$($COM_FLAGS) \$<";
  print $fh "# targets to analyze files\n";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    
    my $src_prefix = substr($path, rindex($path, $lib), length($path));
    my $prefix     = "\${DEST_PROJECTS}/\${$MOD_LIB}/ghdl/";

    #FIXME: force to lower case might break something?
    my $target     = $prefix . lc($base) . ".o";
    my $dep        = "\${GIT_PROJECTS}/vhdl/" . $src_prefix . $base . $suffix;

    print $fh "$target: $dep\n" .
              "\t\@echo \"compile file.......\" \$<\n" .
              #"\t\@$analyze_cmd\n\n";
              #TODO: depending of ghdl backend an object file is generated or not
              "\t\@$analyze_cmd\n\t\@touch $target\n\n";
  }

  # generate file dependencies
  print $fh "# file dependencies\n";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    my $prefix = "\${DEST_PROJECTS}/\${$MOD_LIB}/ghdl/";

    $base      = lc($base);
    my $target = $prefix . $base . ".o";

    print $fh "$target:";
    
    foreach my $ref (@{$database{$file}})
    {
      my $dep_lib  = $$ref[0]; #$ref->[0]
      my $dep_file = $$ref[1]; #$ref->[1]

      my ($base, $path, $suffix) = fileparse($dep_file, ".vhd");

      $base      = lc($base);
      my $prefix = "\${DEST_PROJECTS}/$dep_lib/ghdl/";
      my $dep    = $prefix . $base . ".o";

      print $fh " $dep";
    }

    print $fh "\n\n";
  }

  close($fh);
}


# generate makefile for the ncsim toolchain
sub gen_ncsim_makefile
{
  my ($lib, $module) = @_;

  my $fh = new FileHandle;
  open($fh, ">$module" . "_ncsim.mk") or die "could not create makefile for $module\n";

  my $MOD_LIB    = uc($module) . "_LIB";
  my $MOD        = uc($module) . "_MOD";
  my $COM_FLAGS  = uc($module) . "_COMFLAGS";
  my $ELAB_FLAGS = uc($module) . "_ELABFLAGS";

  my $timestamp = localtime();
  my $user      = $ENV{'USER'};
  my $host      = $ENV{'HOSTNAME'};

  print $fh "# automatic generated ncsim makefile do not edit manually\n";
  #print $fh "# $timestamp by $user\@$host for architecture $GLOBAL::OSTYPE\n\n";
  
  print $fh "# library and module name\n";
  print $fh "$MOD_LIB = $lib\n";
  print $fh "$MOD = $module\n\n";

  print $fh "# compiler and flags\n";
  print $fh "COMP = ncvhdl\n";
  print $fh "ELAB = ncelab\n";

  # read compile flags from config file
  my $ref_flags = read_cfg($ENV{'GIT_PROJECTS'} . "/flow/dflt_ncsim.ini");

  # extract compile flags from database
  my $add_comp_flags = "";
  foreach my $line (@{$$ref_flags{'compile_flags'}})
  {
    $add_comp_flags = $add_comp_flags . " $line";
  }

  # extract elaborate flags from database
  my $add_elab_flags = "";
  foreach my $line (@{$$ref_flags{'elaborate_flags'}})
  {
    $add_elab_flags = $add_elab_flags . " $line";
  }

  # generate ncsim compile flags
  my $compile_flags = "-work \${$MOD_LIB} -cdslib \${GIT_PROJECTS}/cds.lib $add_comp_flags";
  my $elab_flags    = "-work \${$MOD_LIB} -cdslib \${GIT_PROJECTS}/cds.lib $add_elab_flags";

  print $fh "$COM_FLAGS = $compile_flags\n";
  print $fh "$ELAB_FLAGS = $elab_flags\n";

  # generate entry point
  print $fh "\n# to have an entry point\n";
  print $fh "all:";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    my $prefix = "\${DEST_PROJECTS}/\${$MOD_LIB}/ncsim/";
    my $dep    = $prefix . $base . ".o";

    print $fh " $dep";
    
    if(${$$opt{'elab'}{'ref'}} == 1)
    {
      # in case of a testbench add executable as dependency
      if(($base =~ /^tb_/) or ($base =~ /_tb$/))
      {
        my $dep = $prefix . $base;
        print $fh " $dep";
      }
    }
  }
  print $fh "\n";

  if(${$$opt{'elab'}{'ref'}} == 1)
  {
    # generate targets to elaborate entities
    my $elaborate_cmd   = "\$(ELAB) \$($ELAB_FLAGS)";
    print $fh "\n# targets to elaborate entities\n";
    foreach my $file (keys(%database))
    {
      my ($base, $path, $suffix) = fileparse($file, ".vhd");

      # only "testbench entities" will be elaborated 
      if(($base =~ /^tb_/) or ($base =~ /_tb$/))
      {
        my $prefix     = "\${DEST_PROJECTS}/\${$MOD_LIB}/ncsim/";
        my $target     = $prefix . $base . ".sh";
        my $dep        = $prefix . $base . ".o";

        print $fh "$target: $dep\n" .
                  "\t\@echo \"elaborate entity...\" $base\n" . 
                  "\t\@$elaborate_cmd $base:beh\n" .
                  "\t\@echo \"ncsim -cdslib \$\${GIT_PROJECTS}/cds.lib \${$MOD_LIB}.$base:beh\" > $target\n" .
                  "\t\@chmod +x $target\n\n";
      }
    }
  }

  # generate targets to analyze files
  my $analyze_cmd   = "\$(COMP) \$($COM_FLAGS) \$<";
  print $fh "# targets to analyze files\n";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    
    my $src_prefix = substr($path, rindex($path, $lib), length($path));
    my $prefix     = "\${DEST_PROJECTS}/\${$MOD_LIB}/ncsim/";
    my $target     = $prefix . $base . ".o";
    my $dep        = "\${GIT_PROJECTS}/vhdl/" . $src_prefix . $base . $suffix;

    print $fh "$target: $dep\n" .
              "\t\@echo \"compile file.......\" \$<\n" .
              "\t\@$analyze_cmd\n\t\@touch $target\n\n";
  }

  # generate file dependencies
  print $fh "# file dependencies\n";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    my $prefix = "\${DEST_PROJECTS}/\${$MOD_LIB}/ncsim/";
    my $target = $prefix . $base . ".o";

    print $fh "$target:";
    
    foreach my $ref (@{$database{$file}})
    {
      my $dep_lib  = $$ref[0]; #$ref->[0]
      my $dep_file = $$ref[1]; #$ref->[1]

      my ($base, $path, $suffix) = fileparse($dep_file, ".vhd");
      my $prefix = "\${DEST_PROJECTS}/$dep_lib/ncsim/";
      my $dep    = $prefix . $base . ".o";

      print $fh " $dep";
    }

    print $fh "\n\n";
  }

  close($fh);
}


# generate makefile for the modelsim toolchain
sub gen_modelsim_makefile
{
  my ($lib, $module) = @_;

  my $fh = new FileHandle;
  open($fh, ">$module" . "_modelsim.mk") or die "could not create makefile for $module\n";

  my $MOD_LIB    = uc($module) . "_LIB";
  my $MOD        = uc($module) . "_MOD";
  my $COM_FLAGS  = uc($module) . "_FLAGS";

  my $timestamp = localtime();
  my $user      = $ENV{'USER'};
  my $host      = $ENV{'HOSTNAME'};

  print $fh "# automatic generated modelsim makefile do not edit manually\n";
  #print $fh "# $timestamp by $user\@$host for architecture $GLOBAL::OSTYPE\n\n";
  
  print $fh "# library and module name\n";
  print $fh "$MOD_LIB = $lib\n";
  print $fh "$MOD = $module\n\n";

  print $fh "# compiler and flags\n";
  print $fh "COMP = vcom\n";
  
  # generate modelsim compile flags
  my $compile_flags = "-work \${$MOD_LIB} -quiet";

  print $fh "$COM_FLAGS = $compile_flags\n";

  # generate entry point
  print $fh "\n# to have an entry point\n";
  print $fh "all:";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    my $prefix = "\${DEST_PROJECTS}/\${$MOD_LIB}/modelsim/";
    my $dep    = $prefix . $base . ".o";

    print $fh " $dep";

    if(${$$opt{'elab'}{'ref'}} == 1)
    {
      # in case of a testbench add executable as dependency
      if(($base =~ /^tb_/) or ($base =~ /_tb$/))
      {
        my $dep = $prefix . $base . ".sh";
        print $fh " $dep";
      }
    }
  }
  print $fh "\n";

  # generate targets to elaborate entities
  if(${$$opt{'elab'}{'ref'}} == 1)
  {
    print $fh "\n# targets to elaborate entities\n";
    foreach my $file (keys(%database))
    {
      my ($base, $path, $suffix) = fileparse($file, ".vhd");

      # only "testbench entities" will be elaborated 
      if(($base =~ /^tb_/) or ($base =~ /_tb$/))
      {
        my $prefix     = "\${DEST_PROJECTS}/\${$MOD_LIB}/modelsim/";
        my $target     = $prefix . $base . ".sh";
        my $dep        = $prefix . $base . ".o";

        print $fh "$target: $dep\n" .
                  "\t\@echo \"elaborate entity...\" $base\n" .
                  "\t\@echo \"vsim -c \${$MOD_LIB}.$base\" > $target\n" .
                  "\t\@chmod +x $target\n\n";
      }
    }
  }

  # generate targets to analyze files
  my $analyze_cmd   = "\$(COMP) \$($COM_FLAGS) \$<";
  print $fh "# targets to analyze files\n";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    
    my $src_prefix = substr($path, rindex($path, $lib), length($path));
    my $prefix     = "\${DEST_PROJECTS}/\${$MOD_LIB}/modelsim/";
    my $target     = $prefix . $base . ".o";
    my $dep        = "\${GIT_PROJECTS}/vhdl/" . $src_prefix . $base . $suffix;

    print $fh "$target: $dep\n" .
              "\t\@echo \"compile file.......\" \$<\n" .
              "\t\@$analyze_cmd\n" .
              "\t\@touch $target\n\n";
  }

  # generate file dependencies
  print $fh "# file dependencies\n";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    my $prefix = "\${DEST_PROJECTS}/\${$MOD_LIB}/modelsim/";
    my $target = $prefix . $base . ".o";

    print $fh "$target:";
    
    foreach my $ref (@{$database{$file}})
    {
      my $dep_lib  = $$ref[0]; #$ref->[0]
      my $dep_file = $$ref[1]; #$ref->[1]

      my ($base, $path, $suffix) = fileparse($dep_file, ".vhd");
      my $prefix = "\${DEST_PROJECTS}/$dep_lib/modelsim/";
      my $dep    = $prefix . $base . ".o";

      print $fh " $dep";
    }

    print $fh "\n\n";
  }

  close($fh);
}


# generate makefile for isim toolchain
sub gen_isim_makefile
{
  my ($lib, $module) = @_;

  my $fh = new FileHandle;
  open($fh, ">$module" . "_isim.mk") or die "could not create makefile for $module\n";

  my $MOD_LIB    = uc($module) . "_LIB";
  my $MOD        = uc($module) . "_MOD";
  my $COM_FLAGS  = uc($module) . "_COMFLAGS";
  my $ELAB_FLAGS = uc($module) . "_ELABFLAGS"; 

  my $timestamp = localtime();
  my $user      = $ENV{'USER'};
  my $host      = $ENV{'HOSTNAME'};

  print $fh "# automatic generated ghdl makefile do not edit manually\n";
  #print $fh "# $timestamp by $user\@$host for architecture $GLOBAL::OSTYPE\n\n";
  
  print $fh "# library and module name\n";
  print $fh "$MOD_LIB = $lib\n";
  print $fh "$MOD = $module\n\n";

  print $fh "# compiler and flags\n";
  print $fh "COMP = vhpcomp\n";
  print $fh "ELAB = fuse\n";

  # read compile flags from config file
  my $ref_flags = read_cfg($ENV{'GIT_PROJECTS'} . "/isim.ini");

  # extract compile flags from database
  my $add_comp_flags = "";
  foreach my $line (@{$$ref_flags{'compile_flags'}})
  {
    $add_comp_flags = $add_comp_flags . " $line";
  }

  # extract elaborate flags from database
  my $add_elab_flags = "";
  foreach my $line (@{$$ref_flags{'elaborate_flags'}})
  {
    $add_elab_flags = $add_elab_flags . " $line";
  }

  # generate isim compile flags
  my $compile_flags = "-work \${$MOD_LIB}=\$\$DEST_PROJECTS/\${$MOD_LIB}/isim $add_comp_flags";
  my $elab_flags    = "$add_elab_flags";

  print $fh "$COM_FLAGS = $compile_flags\n";
  print $fh "$ELAB_FLAGS = $elab_flags\n";

  # generate entry point
  print $fh "\n# to have an entry point\n";
  print $fh "all:";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    my $prefix = "\${DEST_PROJECTS}/\${$MOD_LIB}/isim/";
    my $dep    = $prefix . $base . ".o";

    print $fh " $dep";

    # in case of a testbench add executable as dependency
    if(${$$opt{'elab'}{'ref'}} == 1)
    {
      if(($base =~ /^tb_/) or ($base =~ /_tb$/))
      {
        my $dep = $prefix . $base;
        print $fh " $dep";
      }
    }
  }
  print $fh "\n";

  # generate targets to elaborate entities
  if(${$$opt{'elab'}{'ref'}} == 1)
  {
    my $elaborate_cmd   = "\$(ELAB) \$($ELAB_FLAGS)";
    print $fh "\n# targets to elaborate entities\n";
    foreach my $file (keys(%database))
    {
      my ($base, $path, $suffix) = fileparse($file, ".vhd");

      # only "testbench entities" will be elaborated 
      if(($base =~ /^tb_/) or ($base =~ /_tb$/))
      {
        my $prefix     = "\${DEST_PROJECTS}/\${$MOD_LIB}/isim/";
        my $target     = $prefix . $base;
        my $dep        = $prefix . $base . ".o";

        print $fh "$target: $dep\n" .
                  "\t\@echo \"elaborate entity...\" $base\n" .
                   "\t\@$elaborate_cmd $lib.$base -o $target > /dev/null\n" .
                  "\t\@mv fuse.log $prefix\n\n";
      }
    }
  }

  # generate targets to analyze files
  my $analyze_cmd   = "\$(COMP) \$($COM_FLAGS) \$<";
  print $fh "# targets to analyze files\n";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    
    my $src_prefix = substr($path, rindex($path, $lib), length($path));
    my $prefix     = "\${DEST_PROJECTS}/\${$MOD_LIB}/isim/";
    my $target     = $prefix . $base . ".o";
    my $dep        = "\${GIT_PROJECTS}/vhdl/" . $src_prefix . $base . $suffix;

    print $fh "$target: $dep\n" .
              "\t\@echo \"compile file.......\" \$<\n" .
              "\t\@$analyze_cmd > /dev/null\n" .
              "\t\@touch $target\n\n";
  }

  # generate file dependencies
  print $fh "# file dependencies\n";
  foreach my $file (keys(%database))
  {
    my ($base, $path, $suffix) = fileparse($file, ".vhd");
    my $prefix = "\${DEST_PROJECTS}/\${$MOD_LIB}/isim/";
    my $target = $prefix . $base . ".o";

    print $fh "$target:";
    
    foreach my $ref (@{$database{$file}})
    {
      my $dep_lib  = $$ref[0]; #$ref->[0]
      my $dep_file = $$ref[1]; #$ref->[1]

      my ($base, $path, $suffix) = fileparse($dep_file, ".vhd");
      my $prefix = "\${DEST_PROJECTS}/$dep_lib/isim/";
      my $dep    = $prefix . $base . ".o";

      print $fh " $dep";
    }

    print $fh "\n\n";
  }

  close($fh);
}


1;

