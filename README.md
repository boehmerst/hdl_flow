```
hdl_flow
A collection of perl scripts to compile VHDL sources

library structure in case of using modelsim a simulation toolchain
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
