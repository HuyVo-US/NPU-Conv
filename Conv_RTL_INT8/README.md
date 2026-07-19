# Conv_RTL_INT8

## Mục đích

Folder này chứa RTL và testbench ModelSim cho phép convolution signed INT8. Thiết kế đọc input và kernel từ SRAM 8-bit, tính raw accumulator signed INT32, thực hiện bias và requantization, sau đó ghi output signed INT8 vào SRAM đích.

Phép toán hiện tại là cross-correlation 2D kiểu `valid`, stride 1, padding 0 và không lật kernel. Đây là phép toán thường được gọi là convolution trong CNN.

Luồng xử lý:

```text
SRAM input INT8 ─┐
                 ├─ matrix_conv ─ raw accumulator INT32 ─ post_process ─ output INT8
SRAM kernel INT8 ┘
```

## Cấu hình kiểm thử hiện tại

| Thông số | Giá trị |
|---|---:|
| Input | 28 × 28, signed INT8 |
| Kernel | 3 × 3, signed INT8 |
| Input channel | 1 |
| Output channel | 1 |
| Stride | 1 |
| Padding | 0 |
| Output | 26 × 26 |
| Số output | 676 |
| Bias | 37 |
| Multiplier Q31 | `0x02000000` = 33554432 |
| Shift | 2 |

`matrix_conv` chỉ tính:

```text
raw_accumulator = Σ(input × kernel)
```

`post_process` thực hiện:

```text
raw_accumulator + bias
→ nhân multiplier Q31
→ áp dụng shift
→ làm tròn nearest, ties-to-even
→ saturation [-128, 127]
→ output signed INT8
```

Ba tham số post-process được khai báo trong `tb_conv_layer.v`:

```verilog
localparam signed [31:0] TEST_BIAS       = 32'sd37;
localparam signed [31:0] TEST_MULTIPLIER = 32'sh02000000;
localparam signed [31:0] TEST_SHIFT      = 32'sd2;
```

Khi thay đổi các giá trị này để tạo bộ test mới, cần thay cùng giá trị trong `../Conv_C_INT8/conv_int8_reference.c` trước khi so sánh.

## Dữ liệu SRAM

Cả ba instance SRAM dùng chung module `sram_int8` và tự khởi tạo:

```verilog
mem[address] = address[7:0];
```

Do đó nội dung lặp tuần hoàn:

```text
00 01 02 ... 7f 80 ... ff 00 01 ...
```

Vì dữ liệu được diễn giải là signed INT8:

- `00` đến `7f` tương ứng 0 đến 127.
- `80` đến `ff` tương ứng -128 đến -1.
- Kernel sử dụng 9 địa chỉ đầu nên có giá trị `00` đến `08`.
- SRAM output ban đầu cũng có mẫu tăng dần, sau đó các địa chỉ output được RTL ghi đè khi `dest_write_en = 1`.

SRAM đọc đồng bộ bằng `clk_300`. Clock này nhanh hơn clock convolution để dữ liệu đọc ổn định trước khi `matrix_conv` sử dụng.

## Các file chính

| File | Vai trò |
|---|---|
| `Conv.v` | Module `matrix_conv`, FSM đọc kernel, trượt cửa sổ, nhân–cộng và xuất raw accumulator INT32 |
| `INT8_MULT.v` | Nhân signed INT8 × signed INT8 thành signed INT16 |
| `INT8_ADD.v` | Cộng signed INT32 accumulator với signed INT16 product thành signed INT32 |
| `POST_PROCESS.v` | Cộng bias, requantize Q31, shift, làm tròn và saturation về INT8 |
| `CONV_LAYER.v` | Wrapper nối `matrix_conv` với `post_process`; top-level DUT của testbench |
| `sram_int8.v` | Mô hình SRAM đồng bộ 8-bit với dữ liệu khởi tạo tăng tuần hoàn |
| `tb_conv_layer.v` | Testbench tạo clock/reset/start, nối ba SRAM, ghi file dữ liệu và log quá trình |
| `run_conv_int8.do` | Macro compile, khởi tạo simulation, thêm waveform và chạy đến `$finish` |
| `Conv_RTL_INT8.mpf` | Project ModelSim 10.5b |

`work/`, `vsim.wlf`, `transcript`, `modelsim.ini` và các file `.mti` là dữ liệu làm việc do ModelSim tạo, không phải mã nguồn thiết kế.

## Giao tiếp và tham số RTL

Các kích thước và địa chỉ được đưa vào `conv_layer` qua input port:

```text
src1_start_address, src1_row_size, src1_col_size
src2_start_address, src2_row_size, src2_col_size
dest_start_address
bias, multiplier, shift
```

Các tín hiệu này phải ổn định từ trước khi bật `start` cho đến khi `done` lên lại. RTL hiện không chốt chúng vào register cấu hình riêng.

`done` có hành vi:

- Mức 1 trong `IDLE` và `DONE`.
- Mức 0 trong khi convolution đang xử lý.
- Sau khi hoàn tất, `done` giữ mức 1 khi FSM quay lại `IDLE`; đây không phải xung một chu kỳ.

Các cấu hình đang cố định trong kiến trúc RTL:

- Một input channel và một output channel.
- Stride 1.
- Padding 0.
- Không dùng input/output zero-point.
- Kernel buffer vật lý là 3 × 3; bộ test hiện tại phải giữ kernel 3 × 3.

## Yêu cầu

- ModelSim hoặc QuestaSim hỗ trợ Verilog.
- Thiết kế hiện được chuẩn bị và kiểm tra với ModelSim 10.5b trên Windows.
- Giữ các file Verilog và `run_conv_int8.do` trong cùng folder.

## Cách chạy bằng project ModelSim

1. Mở `Conv_RTL_INT8.mpf` bằng ModelSim.
2. Trong cửa sổ Transcript, chạy:

```tcl
do run_conv_int8.do
```

Macro sẽ:

1. Tạo và ánh xạ thư viện `work` nếu cần.
2. Compile các module số học, post-process, convolution, SRAM và testbench theo đúng thứ tự.
3. Khởi tạo top-level `work.tb_conv_layer`.
4. Thêm clock, điều khiển, địa chỉ, dữ liệu, raw accumulator và thông tin logging vào Wave.
5. Chạy simulation cho đến khi testbench gọi `$finish`.

File `.mpf` chứa đường dẫn tuyệt đối của workspace hiện tại. Nếu chuyển project sang vị trí khác, nên chạy trực tiếp macro hoặc cập nhật lại project.

## Cách chạy trực tiếp từ ModelSim

Tại workspace root:

```tcl
do Conv_RTL_INT8/run_conv_int8.do
```

Hoặc chuyển vào folder RTL:

```tcl
cd D:/Huy/KLTN-MT_HTN/Neural_Processing_Unit_on_FPGA_v2/Conv_RTL_INT8
do run_conv_int8.do
```

## Các file kết quả

Sau simulation, testbench tạo hoặc ghi đè:

| File | Kích thước | Nội dung |
|---|---:|---|
| `conv_input.hex` | 28 × 28 = 784 giá trị | Input signed INT8 thực tế trong SRAM |
| `conv_kernel.hex` | 3 × 3 = 9 giá trị | Kernel signed INT8 thực tế trong SRAM |
| `conv_rtl_output.hex` | 26 × 26 = 676 giá trị | Output signed INT8 do RTL ghi vào SRAM đích |
| `conv_internal_process.log` | Một dòng header và một dòng mỗi chu kỳ `clk` được ghi | FSM, địa chỉ, dữ liệu, vị trí kernel/output, product, raw accumulator và output |

Ba file HEX dùng biểu diễn bù hai 8-bit, mỗi giá trị gồm đúng hai chữ số hexadecimal. Dữ liệu được lưu row-major:

```text
address = row * number_of_columns + column
```

Ví dụ đầu file input:

```text
00 01 02 03 04 05 ...
```

Testbench hiện chỉ cấp stimulus và ghi dữ liệu/quá trình. Nó không so sánh số học và không tự kết luận PASS/FAIL. `write_count` chỉ là thông tin quan sát số giao dịch có `dest_write_en = 1`.

## So sánh với C reference model

Sau khi chạy RTL:

1. Sao chép ba file sau sang `../Conv_C_INT8/`:

```text
conv_input.hex
conv_kernel.hex
conv_rtl_output.hex
```

2. Nhấp đúp `../Conv_C_INT8/run_compare.bat`.
3. Xem kết quả `MATCH` hoặc danh sách vị trí `MISMATCH` trong cửa sổ console.

Với dữ liệu và tham số hiện tại, C model và RTL khớp toàn bộ 676 output INT8.

Xem thêm [README của C reference model](../Conv_C_INT8/README.md).

## Giới hạn và kiểm thử nên bổ sung

- Input/kernel hiện là mẫu tăng tuần hoàn theo địa chỉ, chưa bao phủ nhiều phân bố dữ liệu.
- Input và kernel đều vuông; chưa kiểm tra chắc chắn trường hợp hình chữ nhật.
- Chỉ có một input channel và một output channel.
- Chưa hỗ trợ stride khác 1 hoặc padding khác 0.
- Chưa dùng zero-point.
- Nên bổ sung input impulse, kernel bất đối xứng, các giá trị âm có chủ ý, dữ liệu ngẫu nhiên và trường hợp gần ngưỡng saturation.
- Nên kiểm tra riêng các trường hợp rounding ties-to-even và shift âm/dương khi đánh giá `POST_PROCESS.v`.
