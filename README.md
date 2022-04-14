```
hdl_flow
A collection of perl scripts to compile VHDL sources

you need to set the following variables:
 export GIT_PROJECTS=/path_to/git_projects
 export DEST_PROJECTS=/path_to/dest_projects
 export MODEL_TECH=$GIT_PROJECTS
 export MODELSIM=$GIT_PROJECTS/modelsim.ini
 export PATH=$PATH:$GIT_PROJECTS/flow

place a modelsim.ini of you choise into the flow directories
 cp /path_to_your_modelsim/modelsim.ini $GIT_PROJECTS/flow/dflt_modelsim.ini

use the following command to get help
 compile --help

use the following commands to build dependencies and compile the sources using modelsim
 compile -e -c --tc=modelsim
 compile -make

you can do it in one command also
 compile -e --tc=modelsim

library structure in case of using modelsim as simulation toolchain
hdl_flow
 |--dest_projects
 |   |--library1
 |   |   |--modelsim
 |   |--library2
 |        |--modelsim
 |--git_projects
 |--flow
 |   |--colorize.pm
 |   |--compile
 |   |--dflt_modelsim.ini (use your modelsim.ini)
 |   |--gen_lib.pm
 |   |--gen_makefile.pm
 |   |--misc.pm
 |   |--vhdl_align.pm
 |--vhdl
 |  |--library1
 |  |   |--beh
 |  |   |--rtl
 |  |   |--rtl_tb
 |  |--library2
 |  |   |--beh
 |  |   |--rtl
 |  |   |--rtl_tb
 |  |--blacklist
 |--makefile
 |--modelsim.ini
```
