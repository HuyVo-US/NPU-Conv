# Conv_C_FP16

Thu muc nay chua C model dung de doi chieu ket qua convolution FP16 voi RTL trong `Conv_RTL_FP16`.

## Muc dich

C model duoc dung de kiem tra thuat toan convolution:

- Kernel truot dung.
- Doc dung input.
- Nhan dung cap phan tu input/kernel.
- Cong du cac tich.
- Ghi dung vi tri output.

Model nay khong nham bit-exact voi RTL. Du lieu dau vao van la FP16, nhung khi tinh toan se duoc convert sang float32, tinh bang CPU, sau do convert ket qua ve FP16.

## Cau truc file chinh

- `conv_fp16_model.c`: C model chinh.
- `conv_fp16_model.exe`: file build san neu da compile.
- `run_conv_fp16_model.bat`: double-click de chay model tren Windows.
- `input.hex`: input copy tu `Conv_RTL_FP16`.
- `kernel.hex`: kernel copy tu `Conv_RTL_FP16`.
- `output.hex`: output RTL copy tu `Conv_RTL_FP16`.
- `output_c_model.hex`: output do C model sinh ra.
- `conv.c`: file tham khao thuat toan convolution, khong can sua de chay model nay.

## Du lieu dau vao

Can copy 3 file tu `Conv_RTL_FP16` sang thu muc nay:

- `input.hex`
- `kernel.hex`
- `output.hex`

Kich thuoc du lieu co dinh:

- Input: `28 x 28`
- Kernel: `3 x 3`
- RTL output: `26 x 26`

Moi phan tu la mot word FP16 16-bit o dang hex.

## Cach chay nhanh

Double-click:

```text
run_conv_fp16_model.bat
```

Batch file se:

1. Kiem tra du `input.hex`, `kernel.hex`, `output.hex`.
2. Compile `conv_fp16_model.c` neu chua co `conv_fp16_model.exe`.
3. Chay C model.
4. Ghi `output_c_model.hex`.
5. In ket qua so sanh truc tiep ra terminal.

## Cach chay bang terminal

Tai thu muc `Conv_C_FP16`, compile:

```powershell
gcc conv_fp16_model.c -o conv_fp16_model.exe
```

Chay voi ten file mac dinh:

```powershell
.\conv_fp16_model.exe
```

Hoac truyen duong dan ro rang:

```powershell
.\conv_fp16_model.exe input.hex kernel.hex output.hex output_c_model.hex
```

## Ket qua so sanh

Chuong trinh in ra:

- So phan tu output: `676`.
- So phan tu match exact.
- So phan tu mismatch exact.
- Phan bo sai khac theo ULP.
- `max ULP diff`.
- `max abs float diff`.
- `max relative float diff`.
- Ket luan PASS/FAIL theo nguong ULP.

Nguong hien tai trong `conv_fp16_model.c`:

```c
#define ULP_TOLERANCE 4
```

Neu tat ca sai khac nam trong `<= 4 ULP`, model se bao:

```text
PASS: C FP16 logic model matches RTL output within tolerance.
```

Dieu nay co nghia la ket qua C model va RTL gan nhau ve gia tri so, sai khac den tu rounding/arithmetic FP16, khong phai dau hieu ro rang cua sai thuat toan convolution.

## Luu y quan trong

- `output_c_model.hex` co the khac `output.hex` o nhieu vi tri neu so sanh bit-exact.
- Khac biet do C model dung duong tinh:

```text
FP16 -> float32 CPU -> tinh convolution -> FP16
```

Trong khi RTL dung:

```text
FP16_MULT.v -> FP16_ADD.v
```

- Vi vay can doc ket qua ULP/tolerance thay vi chi nhin so luong mismatch hex exact.
