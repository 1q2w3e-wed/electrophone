create_clock -name clk_50m -period 20 -waveform {0 10} [get_ports {clk}]

# The LFO changes once per audio sample (about 1024 clocks), so its pitch
# lookup has two full clock periods available before the next LFO update.
set_multicycle_path -from [get_pins {synth/lfo_sample_0_s1/DO[*]}] -to [get_pins {synth/pitch_factor_global_0_s1/AD[*]}] -setup -end 2
set_multicycle_path -from [get_pins {synth/lfo_sample_0_s1/DO[*]}] -to [get_pins {synth/pitch_factor_global_0_s1/AD[*]}] -hold -start 1
