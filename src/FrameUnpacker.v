`timescale 1ns/1ps

module FrameUnpacker #(
  parameter PAYLOAD_LEN = 4
)(
  input                        clk,
  input                        rst_n,
  input             [7:0]      rx_data,
  input                        rx_data_valid,
  output reg       [1:0]       msg_type,
  output reg                   msg_valid,
  output reg [PAYLOAD_LEN*8-1:0] msg_payload
);

  // FSM states
  localparam IDLE      = 2'd0,
             READ_TYPE = 2'd1,
             READ_PAY  = 2'd2,
             DONE      = 2'd3;

  reg [1:0] state, next_state;
  reg [2:0] payload_cnt;

  // State register
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state <= IDLE;
    else
      state <= next_state;
  end

  // Next-state + msg_valid logic
  always @(*) begin
    if(rx_data_valid)
        begin
           $display("[%0t] FSM state=%0d, rx_data=%02h", $time, state, rx_data);
        end
    next_state = state;
    msg_valid   = 1'b0;
    case (state)
      IDLE: if (rx_data_valid && rx_data == 8'h7E)
              next_state = READ_TYPE;

      READ_TYPE: if (rx_data_valid)
                   next_state = READ_PAY;

      READ_PAY: if (rx_data_valid) begin
                    if((payload_cnt) == PAYLOAD_LEN-1)
                        next_state = DONE;
                    else
                        next_state = READ_PAY;
                    end

      DONE: begin
        msg_valid   = 1'b1;   
        next_state  = IDLE;
      end
    endcase
  end

  // Data registers + debug prints
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      msg_type     <= 2'b00;
      payload_cnt  <= 0;
      msg_payload  <= {(PAYLOAD_LEN*8){1'b0}};
    end else begin
      case (state)
        READ_TYPE: if (rx_data_valid) begin
          msg_type <= rx_data[1:0];
          $display("[%0t] got TYPE byte = %h", $time, rx_data);
        end

        READ_PAY: if (rx_data_valid) begin
          // pack into flat bus
          msg_payload[(PAYLOAD_LEN*8-1) - payload_cnt*8 -: 8] <= rx_data;
          $display("[%0t] got PAYLOAD[%0d] = %h", $time, payload_cnt, rx_data);
          payload_cnt <= payload_cnt + 1;
        end

        IDLE: begin
          payload_cnt <= 0;
        end

        DONE: begin
          $display("[%0t] entering DONE, msg_type=%b payload=%h",
                   $time, msg_type, msg_payload);
          // msg_valid will be asserted combinationally
        end
      endcase
    end
  end

endmodule
