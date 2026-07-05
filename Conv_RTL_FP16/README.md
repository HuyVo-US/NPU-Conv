# Conv_RTL_FP16

Thu muc nay chua bo RTL va testbench dung de kiem thu rieng module convolution FP16 `matrix_conv`.

## Muc dich

Kiem tra module `matrix_conv` o muc RTL:

- Kernel truot dung tren input matrix.
- Doc dung vung input.
- Nhan dung tung cap input/kernel bang FP16.
- Cong du cac tich.
- Ghi dung vi tri output.

Thiet ke duoc tach rieng de chay trong ModelSim, khong phu thuoc cac thu muc goc `modelsim`, `software`, `verilog`.

## Cau truc file chinh

- `Conv.v`: module `matrix_conv` can kiem thu.
- `FP16_MULT.v`: module nhan FP16 duoc `matrix_conv` su dung.
- `FP16_ADD.v`: module cong FP16 duoc `matrix_conv` su dung.
- `sram.v`: model SRAM dung trong testbench.
- `tb_conv.v`: testbench chay convolution, init du lieu, dump hex va trace.
- `run_tb_conv.do`: script ModelSim compile va run simulation.
- `Conv_RTL_FP16.mpf`: project ModelSim.

## Kich thuoc du lieu

Testbench giu kich thuoc co dinh:

- Input: `28 x 28`
- Kernel: `3 x 3`
- Output: `26 x 26`

Trong `tb_conv.v`, input duoc init theo day gia tri toan hoc tang dan `1..784`, kernel duoc init `1..9`. Cac gia tri nay duoc ma hoa thanh FP16 truoc khi ghi vao SRAM.

Vi du:

- `1.0 -> 3c00`
- `2.0 -> 4000`
- `3.0 -> 4200`

## Cach chay bang ModelSim

Tu terminal tai thu muc `Conv_RTL_FP16`:

```powershell
vsim -c -do run_tb_conv.do
```

Hoac mo `Conv_RTL_FP16.mpf` trong ModelSim GUI, sau do chay:

```tcl
do run_tb_conv.do
```

## File output duoc sinh ra

Sau simulation, testbench sinh cac file:

- `input.hex`: input matrix `28 x 28`, moi dong la mot hang.
- `kernel.hex`: kernel matrix `3 x 3`.
- `output.hex`: output RTL `26 x 26`.
- `conv_trace.log`: trace moi khi `conv_dest_write_en` duoc bat.
- `transcript_tb_conv.log`: transcript compile/sim cua ModelSim.
- `vsim.wlf`: waveform ModelSim.

Ba file `input.hex`, `kernel.hex`, `output.hex` la cac file can copy sang `Conv_C_FP16` de doi chieu voi C model.

## Dinh dang file hex

Moi phan tu la mot word FP16 16-bit o dang hex 4 ky tu.

Vi du:

```text
3c00 4000 4200
4400 4500 4600
4700 4800 4880
```

File chi chua du lieu, khong co label dia chi.

## Luu y

- `output.hex` la ket qua cua RTL su dung logic trong `FP16_MULT.v` va `FP16_ADD.v`.
- Ket qua nay co the khac bit-exact voi model C tinh bang float32 CPU roi convert ve FP16.
- Khi doi chieu voi C model, nen xem them sai khac ULP thay vi chi so sanh hex exact.
