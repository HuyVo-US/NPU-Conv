# Conv_RTL_INT8

Thu muc nay chua bo RTL va testbench dung de kiem thu rieng module convolution INT8 `matrix_conv`.

## Muc dich

Kiem tra module `matrix_conv` o muc RTL voi datapath INT8:

- Kernel truot dung tren input matrix.
- Doc dung vung input.
- Nhan dung tung cap input/kernel bang signed INT8.
- Cong du cac tich bang accumulator signed 32-bit.
- Ghi nguyen ket qua accumulator signed 32-bit ra output.
- Ghi dung vi tri output.

Thiet ke duoc tach rieng de chay trong ModelSim, khong phu thuoc cac thu muc goc `modelsim`, `software`, `verilog`.

## Cau truc file chinh

- `Conv.v`: module `matrix_conv` can kiem thu.
- `INT8_MULT.v`: module nhan signed INT8, output signed 16-bit.
- `INT8_ADD.v`: module cong product signed 16-bit vao accumulator signed 32-bit.
- `sram.v`: model SRAM co tham so do rong data; source/kernel dung 8-bit, destination dung 32-bit.
- `tb_conv.v`: testbench chay convolution, init du lieu INT8, dump hex va trace.
- `run_tb_conv.do`: script ModelSim compile va run simulation.
- `Conv_RTL_INT8.mpf`: project ModelSim.

## Thiet ke datapath

Trong `Conv.v`, input va kernel la signed INT8:

```verilog
input wire signed [7:0] src1_readdata
input wire signed [7:0] src2_readdata
```

Output convolution la signed INT32:

```verilog
output wire signed [31:0] dest_writedata
```

Phep nhan dung:

```verilog
wire signed [15:0] product;
```

Phep cong don dung:

```verilog
reg signed [31:0] sum;
wire signed [31:0] sum_plus_product;
```

Output duoc ghi truc tiep tu accumulator:

```verilog
assign dest_writedata = sum;
```

Ly do khong cat/saturate ve INT8 o output: mot convolution `3 x 3` cong 9 tich INT8. Tong trung gian co the vuot xa mien INT8 `[-128, 127]`. Neu cat truc tiep `sum[7:0]` hoac saturate ve INT8 ngay tai output, thong tin bien do cua ket qua convolution bi mat, lam giam accuracy cho cac tang tinh toan sau. Vi vay output tam thoi duoc giu o signed INT32.

## Kich thuoc du lieu

Testbench giu kich thuoc co dinh:

- Input: `28 x 28`, moi phan tu signed INT8.
- Kernel: `3 x 3`, moi phan tu signed INT8.
- Output: `26 x 26`, moi phan tu signed INT32.

Trong `tb_conv.v`, input duoc init theo mau signed INT8 lap lai tu `-8` den `7`; kernel duoc init tu `-4` den `4`.

## Cach chay bang ModelSim

Tu terminal tai thu muc `Conv_RTL_INT8`:

```powershell
vsim -c -do run_tb_conv.do
```

Hoac mo `Conv_RTL_INT8.mpf` trong ModelSim GUI, sau do chay:

```tcl
do run_tb_conv.do
```

## File output duoc sinh ra

Sau simulation, testbench sinh cac file:

- `input.hex`: input matrix `28 x 28`, moi dong la mot hang.
- `kernel.hex`: kernel matrix `3 x 3`.
- `output.hex`: output RTL `26 x 26`, moi phan tu la 32-bit hex.
- `conv_trace.log`: trace moi khi `conv_dest_write_en` duoc bat.
- `transcript_tb_conv.log`: transcript compile/sim cua ModelSim.
- `vsim.wlf`: waveform ModelSim.

## Dinh dang file hex

`input.hex` va `kernel.hex`: moi phan tu la mot gia tri INT8 two's-complement o dang hex 2 ky tu.

Vi du:

```text
f8 f9 fa fb fc fd fe ff 00 01 02 03 04 05 06 07
```

Trong do:

- `f8` la `-8`
- `ff` la `-1`
- `00` la `0`
- `07` la `7`

`output.hex`: moi phan tu la mot gia tri signed INT32 two's-complement o dang hex 8 ky tu.

Vi du:

```text
0000004e 0000004e 0000003e
fffffff0 0000000e 00000020
```

## Dinh dang trace

`conv_trace.log` dung dang key-value de de doc tung lan ghi output:

```text
WRITE[1] time=430ns address=0 row=0 col=0 data=0000004e state=4 next_state=3 start=0 done=0 src1_addr=58 src1_data=02 src2_addr=9 src2_data=00 dest_we=1 i=0 j=0 m=0 n=0 product=fff8 sum=0000004e
```

Trong do:

- `address`: dia chi ghi output.
- `row`, `col`: toa do output.
- `data`: gia tri signed INT32 ghi ra output SRAM.
- `product`: tich signed 16-bit hien tai.
- `sum`: accumulator signed 32-bit hien tai.

## Doi chieu voi C model

Sau thay doi output RTL sang signed INT32, C model trong `Conv_C_INT8` cung can duoc cap nhat neu muon so sanh tu dong:

- Tinh output la `int32_t`, khong saturate ve `int8_t`.
- Ghi `output_c_model.hex` theo hex 8 ky tu.
- Doc `output.hex` RTL theo signed INT32.
- So sanh exact tren INT32.

Neu chua cap nhat C model, khong nen dung `run_conv_int8_model.bat` de so sanh voi output RTL INT32 moi.

## Luu y

- `output.hex` la ket qua RTL signed INT32.
- `output_c_model.hex` khong do RTL tao ra; file nay duoc tao khi chay C model trong `Conv_C_INT8`.
- Neu thay doi kich thuoc input/kernel trong testbench, can cap nhat lai C model INT8 tuong ung.
