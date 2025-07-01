`timescale 1ns/1ps
module Top #(
  parameter MAX_ORDER   = 1024,
  parameter ID_BITS     = 10,
  parameter DATA_BITS   = 16,
  parameter PAYLOAD_LEN = 4,
  parameter CLK_FREQ_MHZ= 27,
  parameter BAUD_RATE   = 115200
)(
  input                   clk,
  input                   rst_n,
  input                   uart_rx,    
  output                  uart_tx,    
  output [DATA_BITS-1:0]  size_out,
  output reg              LED_ADD,
  output reg              LED_CANCEL,
  output reg              LED_EXEC,
  output reg              LED_HEART
);
    
  //--- UART RX core
  wire [7:0] rx_data;
  wire       rx_valid;
  wire       rx_data_ready;
  assign     rx_data_ready  = 1'b1;

  uart_rx #(.CLK_FRE(CLK_FREQ_MHZ),.BAUD_RATE(BAUD_RATE))
  rx_i (
        .clk(clk), 
        .rst_n(rst_n),
        .rx_pin(uart_rx),
        .rx_data(rx_data),
        .rx_data_valid(rx_valid),
        .rx_data_ready(rx_data_ready)
        );

  // Blink LED_HEART on every rx_valid
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) LED_HEART <= 1'b1;
    else if (rx_valid) LED_HEART <= ~LED_HEART;
  end

  //--- Frame unpacker
  wire [1:0] msg_type;
  wire       msg_valid;
  wire [PAYLOAD_LEN*8-1:0] msg_payload;
  FrameUnpacker #(.PAYLOAD_LEN(PAYLOAD_LEN))
    unpack (
            .clk(clk), 
            .rst_n(rst_n),
            .rx_data(rx_data),
            .rx_data_valid(rx_valid),
            .msg_type(msg_type),
            .msg_valid(msg_valid),
            .msg_payload(msg_payload)
            );

  //--- Parser
  wire ev_add, ev_cancel, ev_exec;
  wire [15:0]    pid;
  wire [DATA_BITS-1:0]  price_field, size_field;
  Parser #(.PAYLOAD_LEN(PAYLOAD_LEN))
    parse (
           .clk(clk), 
           .rst_n(rst_n),
           .msg_type(msg_type),
           .msg_valid(msg_valid),
           .msg_payload(msg_payload),
           .ADD(ev_add),
           .CANCEL(ev_cancel),
           .EXEC(ev_exec),
           .order_id(pid),
           .price(price_field),
           .size(size_field)
          );

  //--- OrderBook
  wire [ID_BITS-1:0] pid_small = pid[ID_BITS-1:0];
  OrderBook #(.MAX_ORDER(MAX_ORDER),.ID_BITS(ID_BITS),.DATA_BITS(DATA_BITS))
    ob (
        .clk(clk), 
        .rst_n(rst_n),
        .ADD(ev_add),
        .CANCEL(ev_cancel),
        .EXEC(ev_exec),
        .price_in(price_field),
        .size_in(size_field),
        .order_id_in(pid_small),
        .size_out(size_out)
        );

  //--- LEDs
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) 
    begin
      LED_ADD    <= 1'b0;
      LED_CANCEL <= 1'b0;
      LED_EXEC   <= 1'b0;
    end else begin
      if (ev_add)    LED_ADD    <= 1'b1;
      if (ev_cancel) LED_CANCEL <= 1'b1;
      if (ev_exec)   LED_EXEC   <= 1'b1;
      if (ev_add) begin LED_CANCEL <= 1'b0; LED_EXEC <= 1'b0; end
      else if (ev_cancel) begin LED_ADD <= 1'b0; LED_EXEC <= 1'b0; end
      else if (ev_exec) begin LED_ADD <= 1'b0; LED_CANCEL <= 1'b0; end
    end
  end

  //--- UART TX logger ---
  wire        tx_ready;
  reg  [7:0]  tx_byte;
  reg         tx_valid;

  uart_tx #(.CLK_FRE(CLK_FREQ_MHZ),.BAUD_RATE(BAUD_RATE))
  tx_i (
        .clk(clk), 
        .rst_n(rst_n),
        .tx_data(tx_byte),
        .tx_data_valid(tx_valid),
        .tx_data_ready(tx_ready),
        .tx_pin(uart_tx)
        );

  reg [1:0] ev_type_reg;
  reg       ev_type_strobe;

  // capture which event just happened, one‐shot strobe
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ev_type_reg    <= 2'b00;
      ev_type_strobe <= 1'b0;
    end else begin
      ev_type_strobe <= 1'b0;
      if (ev_add) begin
        ev_type_reg    <= 2'b00;
        ev_type_strobe <= 1'b1;
      end else if (ev_cancel) begin
        ev_type_reg    <= 2'b01;
        ev_type_strobe <= 1'b1;
      end else if (ev_exec) begin
        ev_type_reg    <= 2'b10;
        ev_type_strobe <= 1'b1;
      end
    end
  end

  reg [2:0] log_st;
  localparam L_IDLE    = 3'd0,
             L_CHAR0   = 3'd1,
             L_CHAR1   = 3'd2,
             L_CHAR2   = 3'd3,
             L_NEWLINE = 3'd4;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      log_st   <= L_IDLE;
      tx_valid <= 1'b0;
    end else begin
      case (log_st)
        L_IDLE: begin
          tx_valid <= 1'b0;
          if (ev_type_strobe && tx_ready) begin
            // first character
            case (ev_type_reg)
              2'b00: tx_byte <= "A";  // ADD
              2'b01: tx_byte <= "C";  // CNL
              2'b10: tx_byte <= "E";  // EXE
            endcase
            tx_valid <= 1'b1;
            log_st   <= L_CHAR0;
          end
        end

        L_CHAR0: begin
          if (tx_ready) begin
            // second character
            case (ev_type_reg)
              2'b00: tx_byte <= "D";
              2'b01: tx_byte <= "N";
              2'b10: tx_byte <= "X";
            endcase
            tx_valid <= 1'b1;
            log_st   <= L_CHAR1;
          end else
            tx_valid <= 1'b0;
        end

        L_CHAR1: begin
          if (tx_ready) begin
            // third character
            case (ev_type_reg)
              2'b00: tx_byte <= "D";
              2'b01: tx_byte <= "L";
              2'b10: tx_byte <= "E";
            endcase
            tx_valid <= 1'b1;
            log_st   <= L_CHAR2;
          end else
            tx_valid <= 1'b0;
        end

        L_CHAR2: begin
          if (tx_ready) begin
            // carriage return
            tx_byte  <= "\r";
            tx_valid <= 1'b1;
            log_st   <= L_NEWLINE;
          end else 
            tx_valid <= 1'b0;
        end

        L_NEWLINE: begin
          if (tx_ready) begin
            // linefeed and back to idle
            tx_byte  <= "\n";
            tx_valid <= 1'b1;
            log_st   <= L_IDLE;
          end else
            tx_valid <= 1'b0;
        end

        default: begin
          log_st   <= L_IDLE;
          tx_valid <= 1'b0;
        end
      endcase
    end
  end
endmodule
