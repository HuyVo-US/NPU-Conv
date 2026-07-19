transcript on

# Accept execution from Conv_RTL_INT8 or from the workspace root.
if {![file exists INT8_ADD.v]} {
    if {[file exists Conv_RTL_INT8/INT8_ADD.v]} {
        cd Conv_RTL_INT8
    } else {
        error "Run run_conv_int8.do from Conv_RTL_INT8 or its parent workspace"
    }
}

if {![file exists work]} {
    vlib work
}
vmap work work

vlog -work work INT8_ADD.v
vlog -work work INT8_MULT.v
vlog -work work POST_PROCESS.v
vlog -work work Conv.v
vlog -work work CONV_LAYER.v
vlog -work work sram_int8.v
vlog -work work tb_conv_layer.v

vsim -voptargs=+acc work.tb_conv_layer

if {![batch_mode]} {
    view wave
    delete wave *
}

add wave -divider {CLOCK AND CONTROL}
add wave sim:/tb_conv_layer/clk
add wave sim:/tb_conv_layer/clk_300
add wave sim:/tb_conv_layer/reset
add wave sim:/tb_conv_layer/start
add wave sim:/tb_conv_layer/done

add wave -divider {CONVOLUTION INTERFACE}
add wave -radix unsigned sim:/tb_conv_layer/src1_address
add wave -radix hexadecimal sim:/tb_conv_layer/src1_readdata
add wave -radix unsigned sim:/tb_conv_layer/src2_address
add wave -radix hexadecimal sim:/tb_conv_layer/src2_readdata
add wave -radix unsigned sim:/tb_conv_layer/dest_address
add wave -radix hexadecimal sim:/tb_conv_layer/raw_accumulator
add wave -radix hexadecimal sim:/tb_conv_layer/dest_writedata
add wave sim:/tb_conv_layer/dest_write_en

add wave -divider {TESTBENCH LOGGING}
add wave -radix unsigned sim:/tb_conv_layer/cycle_count
add wave -radix unsigned sim:/tb_conv_layer/write_count
add wave sim:/tb_conv_layer/process_log_enable

if {![batch_mode]} {
    configure wave -namecolwidth 260
    configure wave -valuecolwidth 140
}
update

run -all
