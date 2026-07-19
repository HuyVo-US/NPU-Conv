# Conv_RTL_FP16

## Mục đích

Folder này dùng ModelSim để kiểm thử module `matrix_conv` với dữ liệu FP16. Testbench lấy dữ liệu nguyên tăng dần từ SRAM mô phỏng, chuyển từng giá trị sang IEEE-754 binary16 trước khi đưa vào RTL, chạy phép convolution và xuất input, kernel, output cùng log ghi dữ liệu.

Phép toán hiện tại là cross-correlation 2D kiểu `valid`, stride 1, không padding và không lật kernel. Đây là phép toán thường được gọi là convolution trong CNN.

## Cấu hình kiểm thử hiện tại

| Thông số | Giá trị |
|---|---:|
| Input | 28 × 28 |
| Kernel | 3 × 3 |
| Output | 26 × 26 |
| Số output | 676 |
| Stride | 1 |
| Padding | 0 |
| Kiểu dữ liệu vào RTL | FP16/binary16, 16 bit |

SRAM khởi tạo `mem[address] = address`. Testbench dùng `uint16_to_fp16()` để chuyển các số nguyên không dấu này thành mã FP16 trước khi nối vào `matrix_conv`.

## Các file chính

| File | Vai trò |
|---|---|
| `Conv.v` | Module `matrix_conv`, điều khiển FSM, trượt kernel và tích lũy output |
| `FP16_MULT.v` | Phép nhân FP16 của RTL |
| `FP16_ADD.v` | Phép cộng FP16 của RTL |
| `sram.v` | Mô hình SRAM với dữ liệu nguyên tăng dần |
| `tb_conv.v` | Testbench, chuyển dữ liệu SRAM sang FP16, chạy DUT và ghi file |
| `run_conv.do` | Macro tự động compile, mở simulation, thêm waveform và chạy đến hết |
| `Conv_RTL_FP16.mpf` | Project ModelSim |

`work/`, `vsim.wlf`, `transcript` và các file `.mti` là dữ liệu làm việc do ModelSim tạo ra, không phải mã nguồn của thiết kế.

## Yêu cầu

- ModelSim hoặc QuestaSim có hỗ trợ Verilog.
- Project hiện được chuẩn bị và kiểm tra với ModelSim 10.5b trên Windows.
- Nên giữ nguyên các file Verilog và `run_conv.do` trong cùng folder.

## Cách chạy bằng project ModelSim

1. Mở `Conv_RTL_FP16.mpf` bằng ModelSim.
2. Trong cửa sổ Transcript, chạy:

```tcl
do run_conv.do
```

Macro sẽ tự động:

1. Tạo và ánh xạ thư viện `work` nếu cần.
2. Compile `FP16_ADD.v`, `FP16_MULT.v`, `sram.v`, `Conv.v` và `tb_conv.v` theo đúng thứ tự.
3. Khởi tạo top-level `work.tb_conv`.
4. Thêm các tín hiệu điều khiển, địa chỉ, dữ liệu FP16 và kết quả trung gian vào cửa sổ Wave.
5. Chạy simulation cho đến khi testbench gọi `$finish`.

File `.mpf` chứa đường dẫn tuyệt đối của workspace hiện tại. Nếu folder được chuyển sang vị trí khác, nên dùng trực tiếp `run_conv.do` hoặc cập nhật lại project.

## Cách chạy trực tiếp từ ModelSim

Trong Transcript, chuyển đến folder này rồi chạy macro:

```tcl
cd D:/Huy/KLTN-MT_HTN/Neural_Processing_Unit_on_FPGA_v2/Conv_RTL_FP16
do run_conv.do
```

Cũng có thể đứng tại thư mục cha của workspace và chạy:

```tcl
do Conv_RTL_FP16/run_conv.do
```

## Các file kết quả

Sau simulation, testbench tạo hoặc ghi đè các file sau:

| File | Kích thước ma trận | Nội dung |
|---|---:|---|
| `conv_input.hex` | 28 × 28 | Input FP16 theo thứ tự địa chỉ tăng dần |
| `conv_kernel.hex` | 3 × 3 | Kernel FP16 theo thứ tự địa chỉ tăng dần |
| `conv_output.hex` | 26 × 26 | Output FP16 do RTL ghi vào SRAM đích |
| `conv_internal_process.log` | 676 dòng ghi | Một dòng cho mỗi lần `dest_write_en` bật |

Ba file HEX chỉ chứa các từ 16 bit dạng hexadecimal, không có tiêu đề hoặc chú thích. Mỗi hàng trong file tương ứng một hàng của ma trận và dữ liệu được lưu row-major:

```text
address = row * number_of_columns + column
```

Ví dụ đầu file input:

```text
0000 3c00 4000 4200 ...
```

Các giá trị trên lần lượt là mã FP16 của `0.0`, `1.0`, `2.0`, `3.0`, ...

Mỗi dòng log output có dạng tương tự:

```text
WRITE[510] time=112410ns address=509 output_row=19 output_col=15 data=752e ...
```

Log hiện chỉ ghi tại thời điểm output được ghi, không ghi từng phép nhân–cộng nội bộ. Nếu cần debug chi tiết hơn, có thể mở các tín hiệu `product`, `sum` và `sum_plus_product` trong Wave.

## Kết quả hiện tại

Simulation tạo đủ 676 output. Tại output có sai lệch lớn nhất khi so với C reference:

```text
address    = 509
output_row = 19
output_col = 15
RTL FP16   = 0x752e = 21216
```

Kết quả toán học của cửa sổ tương ứng là 21246, trong khi C tính bằng `float` rồi chuyển về FP16 thành 21248. RTL thấp hơn vì các module FP16 cắt bớt mantissa sau từng phép nhân và phép cộng.

## Nhận xét về RTL

Với bộ test hiện tại, RTL thực hiện đúng quá trình:

```text
đọc kernel → trượt cửa sổ 3 × 3 → nhân từng cặp → cộng 9 tích → ghi output
```

Các kết quả khớp cấu trúc với C reference; sai lệch số học có dạng lượng tử FP16 và có xu hướng RTL thấp hơn C do cắt mantissa. Không thấy dấu hiệu sai địa chỉ, sai thứ tự output hoặc sai vị trí kernel trong cấu hình 28 × 28 và 3 × 3 hiện tại.

Kết luận này chưa bao phủ mọi trường hợp. Test hiện tại chỉ dùng dữ liệu không âm, tăng dần, input vuông và kernel vuông. Một số vị trí trong `Conv.v` sử dụng `row_size` và `col_size` chưa nhất quán; cấu hình vuông có thể che giấu lỗi hoán đổi hàng/cột.

## Các kiểm thử nên bổ sung

- Input impulse để kiểm tra chính xác hướng và vị trí kernel.
- Kernel bất đối xứng với số âm và số phân số FP16.
- Dữ liệu ngẫu nhiên với nhiều seed.
- Input hoặc kernel không vuông để kiểm tra `row_size`/`col_size`.
- Các trường hợp gần zero, overflow và giới hạn exponent FP16.
- Log từng bước nhân–cộng khi cần xác định vị trí bắt đầu sai lệch.

## So sánh với C reference model

Sau khi chạy RTL:

1. Sao chép `conv_input.hex`, `conv_kernel.hex` và `conv_output.hex` sang `../Conv_C_FP16/`.
2. Chạy `../Conv_C_FP16/run_compare.bat`.
3. Xem số cặp output khác nhau và sai số thực lớn nhất.

Xem thêm [README của C reference model](../Conv_C_FP16/README.md).

