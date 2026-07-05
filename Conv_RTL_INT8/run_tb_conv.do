transcript file transcript_tb_conv.log

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -work work INT8_MULT.v
vlog -work work INT8_ADD.v
vlog -work work Conv.v
vlog -work work sram.v
vlog -work work tb_conv.v

vsim -t 1ns work.tb_conv

add wave -r sim:/tb_conv/*
run -all
quit -sim
