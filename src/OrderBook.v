`timescale 1ns/1ps
module OrderBook #(
  parameter MAX_ORDER = 1024,  // table depth
  parameter ID_BITS   = 10,
  parameter DATA_BITS = 16     // width of price & size
)(
  input                         clk,
  input                         rst_n,
  input                         ADD,
  input                         CANCEL,
  input                         EXEC,
  input      [DATA_BITS-1:0]    price_in,
  input      [DATA_BITS-1:0]    size_in,
  input      [ID_BITS-1:0]      order_id_in,
  output reg [DATA_BITS-1:0]    size_out
);

  // --------------------------------------------------------------------------
  // 1) Declare the RAM arrays WITHOUT any reset loop:
  //    This lets your tool infer real BRAM blocks.
  // --------------------------------------------------------------------------
  reg [DATA_BITS-1:0] price_ram [0:MAX_ORDER-1];
  reg [DATA_BITS-1:0] size_ram  [0:MAX_ORDER-1];

  // --------------------------------------------------------------------------
  // 2) Synchronous readback of size_out, with an async reset only for size_out.
  // --------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      size_out <= {DATA_BITS{1'b0}};
    end else begin
      // read from BRAM at the given ID each cycle
      size_out <= size_ram[order_id_in];
    end
  end

  // --------------------------------------------------------------------------
  // 3) Separate process to do BRAM writes (no resets here).
  //    All writes use non-blocking <= so they happen in BRAM.
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (ADD) begin
      price_ram[order_id_in] <= price_in;
      size_ram [order_id_in] <= size_in;
      $display("[%0t] WRITE ADD   id=%0d size=%d",
               $time, order_id_in, size_in);
    end

    if (CANCEL) begin
      size_ram[order_id_in] <= {DATA_BITS{1'b0}};
      $display("[%0t] WRITE CANCEL id=%0d",
               $time, order_id_in);
    end

    if (EXEC) begin
      if (size_ram[order_id_in] > size_in) begin
        size_ram[order_id_in] <= size_ram[order_id_in] - size_in;
        $display("[%0t] WRITE EXEC   id=%0d, sub=%d",
                 $time, order_id_in, size_in);
      end else begin
        size_ram[order_id_in] <= {DATA_BITS{1'b0}};
        $display("[%0t] WRITE EXEC   id=%0d, zero",
                 $time, order_id_in);
      end
    end
  end

endmodule
