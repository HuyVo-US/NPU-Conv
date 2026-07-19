# Conv_C_INT8

## Mục đích

Folder này chứa C reference model để kiểm tra output INT8 của `../Conv_RTL_INT8/`. Model đọc ba file HEX đã được sao chép từ RTL, thực hiện convolution và post-processing bằng C, ghi output kỳ vọng rồi so sánh từng phần tử với output RTL.

Luồng dữ liệu:

```text
conv_input.hex  ─┐
                 ├─ conv2d_q7 ─ requantize ─ conv_expected_output.hex ─┐
conv_kernel.hex ─┘                                                      ├─ so sánh 676 INT8
conv_rtl_output.hex ────────────────────────────────────────────────────┘
```

Phép toán là cross-correlation 2D kiểu `valid`, stride 1, padding 0 và không lật kernel.

## Cấu hình hiện tại

| Thông số | Giá trị |
|---|---:|
| Input | 28 × 28, 784 signed INT8 |
| Kernel | 3 × 3, 9 signed INT8 |
| Input channel | 1 |
| Output channel | 1 |
| Stride | 1 |
| Padding | 0 |
| Output | 26 × 26, 676 signed INT8 |
| Bias | 37 |
| Multiplier Q31 | `0x02000000` = 33554432 |
| Shift | 2 |
| Zero-point | Không sử dụng |

Các hằng cấu hình nằm trong `conv_int8_reference.c`. Bias, multiplier và shift phải được giữ giống `TEST_BIAS`, `TEST_MULTIPLIER`, `TEST_SHIFT` trong `../Conv_RTL_INT8/tb_conv_layer.v`.

## Nguồn của hai hàm tính toán chính

Hai hàm sau được lấy từ thiết kế C gốc:

- `requantize_q7_with_multiplier_shift()` từ `../C_reference_model/source/common.h`.
- `conv2d_q7()` từ `../C_reference_model/source/conv.c`.

Trong bản kiểm thử này, zero-point được loại bỏ:

- Không trừ input zero-point trước phép nhân.
- Không cộng output zero-point sau requantization.
- Khi multiplier bằng 0, requantization trả về 0.

Ngoài phần loại bỏ zero-point, thuật toán convolution và requantization giữ theo source C. Hàm requantization dùng `double`, `lrint()` và `SATURATE_Q7()`.

## Các file

| File | Vai trò |
|---|---|
| `conv_int8_reference.c` | Đọc file, chạy C model, ghi expected output và so sánh RTL |
| `run_compare.bat` | Kiểm tra file/GCC, compile, chạy model, xóa executable trung gian và giữ console để xem kết quả |
| `conv_input.hex` | Input INT8 được sao chép từ RTL |
| `conv_kernel.hex` | Kernel INT8 được sao chép từ RTL |
| `conv_rtl_output.hex` | Output INT8 được sao chép từ RTL |
| `conv_expected_output.hex` | Output INT8 do C model tạo |

## Yêu cầu

- GCC hỗ trợ C11 và có trong biến môi trường `PATH`.
- Ba file `conv_input.hex`, `conv_kernel.hex`, `conv_rtl_output.hex` phải nằm ngay trong folder này.
- Có thư viện toán học cho `lrint()`; lệnh compile sử dụng `-lm`.

Kiểm tra GCC trên Windows:

```powershell
gcc --version
```

## Chuẩn bị dữ liệu

1. Chạy simulation trong `../Conv_RTL_INT8/`.
2. Sao chép ba file sau vào folder này:

```text
Conv_RTL_INT8/conv_input.hex
Conv_RTL_INT8/conv_kernel.hex
Conv_RTL_INT8/conv_rtl_output.hex
```

Không thêm tiêu đề, địa chỉ hoặc chú thích vào file HEX. C model yêu cầu chính xác:

- 784 giá trị trong `conv_input.hex`.
- 9 giá trị trong `conv_kernel.hex`.
- 676 giá trị trong `conv_rtl_output.hex`.

Mỗi giá trị phải nằm trong 8 bit và được viết bằng hexadecimal. Các file do testbench tạo dùng đúng hai chữ số cho mỗi giá trị.

## Cách chạy nhanh trên Windows

Nhấp đúp:

```text
run_compare.bat
```

Batch file sẽ:

1. Chuyển working directory về `Conv_C_INT8`.
2. Kiểm tra đủ ba file HEX.
3. Kiểm tra `gcc` trong `PATH`.
4. Compile `conv_int8_reference.c` thành executable trung gian.
5. Chạy convolution, tạo `conv_expected_output.hex` và so sánh RTL.
6. Xóa executable trung gian.
7. Giữ cửa sổ console mở để đọc kết quả.

Tùy chọn `--no-pause` dùng khi chạy tự động:

```powershell
cmd /c run_compare.bat --no-pause
```

## Biên dịch và chạy thủ công

Trong PowerShell hoặc Command Prompt tại folder này:

```powershell
gcc -std=c11 -Wall -Wextra -O2 -o conv_int8_reference.exe conv_int8_reference.c -lm
.\conv_int8_reference.exe
```

Chương trình luôn đọc các tên file local:

```text
conv_input.hex
conv_kernel.hex
conv_rtl_output.hex
```

## Cách model xử lý dữ liệu

1. `read_int8_hex()` đọc từng token HEX, kiểm tra giá trị không vượt quá 8 bit và diễn giải bit pattern thành signed `int8_t`.
2. `conv2d_q7()` duyệt output theo row-major, lấy input nhân kernel và tích lũy vào `q31_t` bắt đầu từ bias.
3. `requantize_q7_with_multiplier_shift()` áp dụng multiplier Q31, shift, `lrint()` và saturation về signed INT8.
4. `write_int8_hex()` ghi output C thành ma trận 26 × 26, mỗi giá trị là hai chữ số HEX bù hai.
5. `compare_int8_outputs()` so sánh đủ 676 giá trị C và RTL.

Input và kernel được lưu bằng `q7_t`/`int8_t`. Trước phép nhân, toán hạng được ép sang `q31_t` để không làm mất product; accumulator và bias là signed INT32. Output chỉ trở về signed INT8 sau requantization và saturation.

## Ý nghĩa kết quả

Khi toàn bộ output giống nhau:

```text
Comparison : MATCH (all 676 outputs are identical)
```

Nếu có sai lệch, chương trình in tối đa 20 vị trí đầu tiên:

```text
MISMATCH [row][col] index=N: expected=xx (...) rtl=yy (...)
```

Sau đó chương trình báo tổng số output khác nhau. Exit code bằng 0 khi `MATCH` và khác 0 khi có lỗi đọc file, lỗi ghi file hoặc `MISMATCH`.

Với ba file và tham số hiện tại, C model khớp toàn bộ 676 output của RTL.

## Định dạng file

Các ma trận được lưu row-major:

```text
index = row * number_of_columns + column
```

Ví dụ đầu file input:

```text
00 01 02 03 04 05 ...
```

Đây là bit pattern INT8. Khi đọc dưới dạng signed:

- `00` đến `7f` là 0 đến 127.
- `80` đến `ff` là -128 đến -1.

## Giới hạn hiện tại

- Kích thước và tham số đang cố định trong source C; muốn đổi bộ test phải sửa các hằng và đồng bộ với testbench RTL.
- Hàm `conv2d_q7()` dùng một tham số `K`, vì vậy kernel được giả định vuông.
- Chỉ kiểm thử một input channel và một output channel.
- Không sử dụng zero-point.
- Không tạo hoặc so sánh raw accumulator; luồng hiện tại chỉ so sánh output INT8 cuối cùng.
- Kết quả là cross-correlation, không lật kernel như convolution toán học cổ điển.

## Kiểm thử nên bổ sung

- Input impulse và kernel bất đối xứng để kiểm tra hướng kernel.
- Các bộ dữ liệu âm/dương có chủ ý.
- Nhiều bộ dữ liệu ngẫu nhiên.
- Các trường hợp làm tròn đúng nửa và gần ngưỡng saturation.
- Các multiplier và shift khác nhau nhưng phải được đồng bộ giữa C và RTL.

Xem thêm [README của RTL testbench](../Conv_RTL_INT8/README.md).
