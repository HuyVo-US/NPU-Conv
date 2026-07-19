transcript on

# ModelSim 10.5b does not expose the active macro path through [info script].
# Accept execution from this folder or from the workspace root.
if {![file exists FP16_ADD.v]} {
    if {[file exists Conv_RTL_FP16/FP16_ADD.v]} {
        cd Conv_RTL_FP16
    } else {
        error "Run run_conv.do from Conv_RTL_FP16 or its parent workspace"
    }
}

if {![file exists work]} {
    vlib work
}
vmap work work

# Compile dependencies before the DUT and testbench.
vlog -work work FP16_ADD.v
vlog -work work FP16_MULT.v
vlog -work work sram.v
vlog -work work Conv.v
vlog -work work tb_conv.v

vsim -voptargs=+acc work.tb_conv

view wave
delete wave *

add wave -divider {CLOCK AND CONTROL}
add wave sim:/tb_conv/clk
add wave sim:/tb_conv/clk_300
add wave sim:/tb_conv/reset
add wave sim:/tb_conv/conv_start
add wave sim:/tb_conv/conv_done

add wave -divider {FSM AND POSITIONS}
add wave -radix unsigned sim:/tb_conv/uut/state
add wave -radix unsigned sim:/tb_conv/uut/next_state
add wave -label output_row -radix unsigned sim:/tb_conv/uut/m
add wave -label output_col -radix unsigned sim:/tb_conv/uut/n
add wave -label kernel_row -radix unsigned sim:/tb_conv/uut/i
add wave -label kernel_col -radix unsigned sim:/tb_conv/uut/j

add wave -divider {SOURCE 1 INPUT}
add wave -radix unsigned sim:/tb_conv/conv_src1_address
add wave -radix hexadecimal sim:/tb_conv/sram_src1_readdata
add wave -radix hexadecimal sim:/tb_conv/conv_src1_readdata

add wave -divider {SOURCE 2 KERNEL}
add wave -radix unsigned sim:/tb_conv/conv_src2_address
add wave -radix hexadecimal sim:/tb_conv/sram_src2_readdata
add wave -radix hexadecimal sim:/tb_conv/conv_src2_readdata
add wave -radix hexadecimal sim:/tb_conv/debug_kernel_value

add wave -divider {FP16 ARITHMETIC}
add wave -radix hexadecimal sim:/tb_conv/uut/product
add wave -radix hexadecimal sim:/tb_conv/uut/sum
add wave -radix hexadecimal sim:/tb_conv/uut/sum_plus_product

add wave -divider {DESTINATION OUTPUT}
add wave -radix unsigned sim:/tb_conv/conv_dest_address
add wave -radix hexadecimal sim:/tb_conv/conv_dest_writedata
add wave sim:/tb_conv/conv_dest_write_en

configure wave -namecolwidth 260
configure wave -valuecolwidth 140
update

run -all
