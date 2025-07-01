`timescale 1ns/1ps
module Parser #(
  parameter PAYLOAD_LEN = 4
)(
  input               clk,
  input               rst_n,
  input       [1:0]   msg_type,
  input               msg_valid,
  input [PAYLOAD_LEN*8-1:0] msg_payload,

  output reg          ADD,
  output reg          CANCEL,
  output reg          EXEC,
  output reg [15:0]   order_id,
  output reg [15:0]   price,
  output reg [15:0]   size
);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ADD      <= 1'b0;
      CANCEL   <= 1'b0;
      EXEC     <= 1'b0;
      order_id <= 16'd0;
      price    <= 16'd0;
      size     <= 16'd0;
    end else begin
      // clear flags 
      ADD    <= 1'b0;
      CANCEL <= 1'b0;
      EXEC   <= 1'b0;

      if (msg_valid) begin
        // **DEBUG LINE**  
        $display("[%0t] Parser saw msg_valid, msg_type=%b, payload=%h",
                 $time, msg_type, msg_payload);

        case (msg_type)
          2'b00: begin
            ADD      <= 1'b1;
            order_id <= msg_payload[PAYLOAD_LEN*8-1 -:16];
            price    <= {8'd0, msg_payload[15:8]};
            size     <= {8'd0, msg_payload[7:0]};
          end

          2'b01: begin
            CANCEL   <= 1'b1;
            order_id <= msg_payload[PAYLOAD_LEN*8-1 -:16];
          end

          2'b10: begin
            EXEC     <= 1'b1;
            order_id <= msg_payload[PAYLOAD_LEN*8-1 -:16];
            size     <= {8'd0, msg_payload[7:0]};
          end
        endcase
      end
    end
  end

endmodule
