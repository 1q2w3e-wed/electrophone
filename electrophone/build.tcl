# Run from this project's directory: gw_sh.exe build.tcl
open_project electrophone.gprj
set_option -top_module electrophone
# E2 is a dual-purpose CPU/SSPI pin on the selected GW5A-25A device.
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
run syn
run pnr
