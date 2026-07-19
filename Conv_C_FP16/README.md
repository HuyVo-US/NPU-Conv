# Conv_C_FP16

## Mục đích

Folder này chứa C reference model độc lập để kiểm tra kết quả convolution của RTL. Model đọc ba file HEX do testbench RTL tạo ra, chuyển input và kernel từ FP16 sang `float`, thực hiện convolution bằng phép toán `float` của CPU, chuyển output C về FP16 rồi so sánh với output FP16 của RTL.

Luồng dữ liệu:

```text
conv_input.hex  ─┐
                 ├─ FP16 → float CPU → convolution → FP16 ─┐
conv_kernel.hex ─┘                                          ├─ so sánh số học
conv_output.hex ─────────────────────────────────────────────┘
```

Phép toán là cross-correlation 2D kiểu `valid`, stride 1, không padding và không lật kernel, tương ứng cách convolution thường dùng trong CNN và cách `matrix_conv` đang thực hiện.

## Cấu hình hiện tại

| Thông số | Giá trị |
|---|---:|
| Input | 28 × 28, 784 phần tử |
| Kernel | 3 × 3, 9 phần tử |
| Output | 26 × 26, 676 phần tử |
| Phép tính trung gian của C | `float` CPU |
| Dữ liệu file vào/ra | FP16/binary16 chứa trong `uint16_t` |

## Các file

| File | Vai trò |
|---|---|
| `conv_reference.c` | Toàn bộ C reference model trong một source file |
| `run_compare.bat` | Kiểm tra dữ liệu, compile vào thư mục tạm, chạy model và so sánh |
| `conv_input.hex` | Input FP16 được sao chép từ RTL |
| `conv_kernel.hex` | Kernel FP16 được sao chép từ RTL |
| `conv_output.hex` | Output FP16 của RTL |
| `conv_c_output.hex` | Output FP16 do C model tạo ra |

## Yêu cầu

- GCC hỗ trợ C11 và có trong biến môi trường `PATH`.
- Ba file `conv_input.hex`, `conv_kernel.hex`, `conv_output.hex` phải nằm trong folder này nếu chạy bằng cấu hình mặc định.
- Trên Windows có thể kiểm tra GCC bằng:

```powershell
gcc --version
```

## Chuẩn bị dữ liệu

1. Chạy simulation trong `../Conv_RTL_FP16/`.
2. Sao chép ba file sau vào folder này:

```text
Conv_RTL_FP16/conv_input.hex
Conv_RTL_FP16/conv_kernel.hex
Conv_RTL_FP16/conv_output.hex
```

Không thêm tiêu đề, địa chỉ hoặc chú thích vào các file HEX. Chương trình yêu cầu đúng 784 từ input, 9 từ kernel và 676 từ output.

## Cách chạy nhanh trên Windows

Nhấp đúp:

```text
run_compare.bat
```

Batch file sẽ tự động:

1. Kiểm tra GCC và các file cần thiết.
2. Compile `conv_reference.c` thành executable trong `%TEMP%`.
3. Chạy convolution và so sánh.
4. Ghi `conv_c_output.hex` vào folder hiện tại.
5. Xóa executable tạm và giữ cửa sổ để đọc kết quả.

## Biên dịch và chạy thủ công

Trong PowerShell hoặc Command Prompt tại folder này:

```powershell
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -ffp-contract=off conv_reference.c -o conv_reference.exe -lm
.\conv_reference.exe
```

Khi chạy không có tham số, chương trình dùng các tên mặc định:

```text
conv_input.hex
conv_kernel.hex
conv_output.hex
conv_c_output.hex
```

Cũng có thể chỉ định đường dẫn:

```powershell
.\conv_reference.exe input.hex kernel.hex rtl_output.hex c_output.hex
```

Tham số output C cuối cùng là tùy chọn:

```powershell
.\conv_reference.exe input.hex kernel.hex rtl_output.hex
```

## Cách model xử lý dữ liệu

1. `read_fp16_hex()` đọc mỗi từ HEX vào `uint16_t` và kiểm tra không vượt quá 16 bit.
2. `fp16_to_float()` diễn giải các bit binary16 thành `float` CPU.
3. `convolution_float32()` thực hiện 9 phép nhân và tích lũy cho mỗi output hoàn toàn bằng `float`.
4. `float_to_fp16()` chuyển kết quả cuối cùng về mã FP16.
5. `compare_outputs()` chuyển output C và RTL về số thực để đếm các cặp khác nhau và tìm sai số tuyệt đối lớn nhất.

Hai công thức `fp16_to_float()` và `float_to_fp16()` được giữ theo cách chuyển đổi trong `software/npu.c` để kiểm thử với thiết kế gốc. Hai helper đổi cách nhìn bit giữa `float` và `uint32_t` bằng `memcpy`, tránh ép con trỏ vi phạm strict-aliasing.

## Ý nghĩa kết quả

Chương trình không đưa ra PASS/FAIL. Kết quả chỉ mô tả mức khác nhau giữa C và RTL:

```text
Different pairs   : số output có giá trị C khác RTL / tổng số output
Largest real error: giá trị lớn nhất của |C - RTL| sau khi đổi về số thực
Largest-error pair: địa chỉ, hàng, cột và hai giá trị tại vị trí sai lệch lớn nhất
```

`Different pairs` đếm mọi sai lệch, kể cả chỉ khác một mức biểu diễn FP16. Vì vậy số lượng cặp khác nhau lớn không đồng nghĩa thuật toán convolution sai.

## Kết quả hiện tại

Với dữ liệu SRAM tăng dần hiện tại:

```text
Different pairs   : 569/676
Largest real error: 32
Largest-error pair: address=509 row=19 col=15
                    c_value=21248 rtl_value=21216
```

Tại address 509, phép tính toán học là:

```text
547×0 + 548×1 + 549×2
+ 575×3 + 576×4 + 577×5
+ 603×6 + 604×7 + 605×8
= 21246
```

C giữ tổng trong `float` rồi chuyển về FP16 thành 21248. RTL cắt mantissa sau từng phép nhân và phép cộng nên cho 21216. Tại vùng giá trị này, các số FP16 liên tiếp cách nhau 16; hai kết quả cách nhau hai mức FP16.

Thống kê hướng sai lệch:

```text
C bằng RTL    : 107 output
C lớn hơn RTL : 569 output
RTL lớn hơn C :   0 output
```

Xu hướng một chiều này phù hợp với việc RTL cắt các bit thấp của mantissa trên dữ liệu không âm.

## Kết luận đánh giá

Với cấu hình hiện tại, kết quả cho thấy RTL thực hiện đúng chuỗi thao tác trượt cửa sổ, nhân từng cặp và cộng 9 tích của convolution/CNN cross-correlation. Sai lệch quan sát được phù hợp với cách RTL lượng tử hóa FP16 sau từng phép toán, trong khi C chỉ lượng tử hóa một lần ở output.

Kết luận này chỉ áp dụng cho bộ test 28 × 28, kernel 3 × 3, dữ liệu không âm tăng dần hiện tại. Một bộ dữ liệu duy nhất không chứng minh RTL đúng với mọi kích thước và mọi mẫu FP16.

## Giới hạn hiện tại

- Công thức chuyển đổi FP16 được tái sử dụng từ `software/npu.c`, chủ yếu phục vụ dữ liệu hữu hạn hiện tại; chưa phải bộ chuyển đổi IEEE-754 tổng quát cho mọi NaN, Infinity, subnormal và overflow.
- Input/kernel hiện chỉ là số không âm được tạo từ địa chỉ SRAM.
- Input và kernel đều vuông nên chưa kiểm tra chắc chắn việc phân biệt hàng/cột trong RTL.
- C tích lũy bằng `float`, còn RTL cắt về FP16 sau từng phép toán; hai output không được kỳ vọng bit-exact.
- Kết quả đang kiểm tra cross-correlation, không lật kernel như convolution toán học cổ điển.

## Kiểm thử nên bổ sung

- Input impulse và kernel bất đối xứng để xác nhận hướng kernel.
- Giá trị âm và phân số FP16.
- Nhiều bộ input/kernel ngẫu nhiên.
- Input hoặc kernel hình chữ nhật.
- Các giá trị gần giới hạn exponent và mantissa FP16.
- Một C model phụ chỉ mô phỏng làm tròn sau từng phép toán nếu cần đối chiếu bit-exact với datapath RTL.

Xem thêm [README của RTL testbench](../Conv_RTL_FP16/README.md).

