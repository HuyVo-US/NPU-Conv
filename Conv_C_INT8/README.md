# Conv_C_INT8

Thu muc nay chua C model dung de doi chieu ket qua convolution INT8 voi RTL trong `Conv_RTL_INT8`.

## Muc dich

C model duoc dung lam reference de kiem tra thuat toan convolution INT8:

- Doc dung input matrix va kernel signed INT8.
- Nhan dung tung cap phan tu input/kernel.
- Cong du 9 tich cua kernel `3 x 3` bang accumulator signed 32-bit.
- Ghi output `26 x 26` o dang signed INT32.
- So sanh exact voi `output.hex` do RTL sinh ra.

Khac voi model FP16, model nay khong convert qua `float32`. Tat ca phep tinh dung signed integer.

## Cau truc file chinh

- `conv_int8_model.c`: C model chinh.
- `conv_int8_model.exe`: file build san neu da compile.
- `run_conv_int8_model.bat`: double-click de chay model tren Windows.
- `input.hex`: input copy tu `Conv_RTL_INT8`.
- `kernel.hex`: kernel copy tu `Conv_RTL_INT8`.
- `output.hex`: output RTL copy tu `Conv_RTL_INT8`.
- `output_c_model.hex`: output do C model sinh ra.

## Dinh dang du lieu

Kich thuoc du lieu co dinh:

- Input: `28 x 28`, moi phan tu signed INT8.
- Kernel: `3 x 3`, moi phan tu signed INT8.
- Output: `26 x 26`, moi phan tu signed INT32.

`input.hex` va `kernel.hex`: moi phan tu la INT8 two's-complement, hex 2 ky tu.

Vi du:

- `00` la `0`
- `01` la `1`
- `7f` la `127`
- `80` la `-128`
- `ff` la `-1`

`output.hex` va `output_c_model.hex`: moi phan tu la INT32 two's-complement, hex 8 ky tu.

Vi du:

- `0000004e` la `78`
- `fffffff0` la `-16`

## Cach chay nhanh

Copy 3 file sau tu `Conv_RTL_INT8` sang thu muc nay:

- `input.hex`
- `kernel.hex`
- `output.hex`

Sau do double-click:

```text
run_conv_int8_model.bat
```

Batch file se:

1. Kiem tra du `input.hex`, `kernel.hex`, `output.hex`.
2. Compile `conv_int8_model.c` neu chua co `conv_int8_model.exe`.
3. Chay C model.
4. Ghi `output_c_model.hex` theo hex 8 ky tu moi phan tu.
5. In ket qua so sanh exact voi RTL ra terminal.

## Cach chay bang terminal

Tai thu muc `Conv_C_INT8`, compile:

```powershell
gcc conv_int8_model.c -o conv_int8_model.exe
```

Chay voi ten file mac dinh:

```powershell
.\conv_int8_model.exe
```

Hoac truyen duong dan ro rang:

```powershell
.\conv_int8_model.exe input.hex kernel.hex output.hex output_c_model.hex
```

Co the doi chieu truc tiep voi file trong `Conv_RTL_INT8` ma khong can copy:

```powershell
.\conv_int8_model.exe ..\Conv_RTL_INT8\input.hex ..\Conv_RTL_INT8\kernel.hex ..\Conv_RTL_INT8\output.hex output_c_model.hex
```

## Ket qua so sanh

Chuong trinh in ra:

- Tong so phan tu output: `676`.
- So phan tu match exact.
- So phan tu mismatch exact.
- Sai khac signed lon nhat.
- Ket luan PASS/FAIL.

Neu tat ca output khop exact, model se bao:

```text
PASS: C INT8-input/INT32-output logic model matches RTL output exactly.
```

## Luu y quan trong

- File `output_c_model.hex` la ket qua C model, khong phai file RTL tao ra.
- File `output.hex` la ket qua RTL can so sanh.
- C model hien tai khop voi `Conv_RTL_INT8` ban output INT32. Neu RTL doi lai output INT8, can doi C model tuong ung.
