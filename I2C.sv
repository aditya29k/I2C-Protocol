`ifndef DATA_WIDTH 
	`define DATA_WIDTH 8
`endif

`ifndef ADDR_WIDTH
	`define ADDR_WIDTH 7
`endif

`ifndef CLK_FREQUENCY
	`define CLK_FREQUENCY 40000000 // 40MHz
`endif

`ifndef I2C_FREQUENCY
	`define I2C_FREQUENCY 100000 // 100KHz
`endif

`ifndef CLK_COUNT
	`define CLK_COUNT (`CLK_FREQUENCY/`I2C_FREQUENCY) // 400
`endif

`ifndef CLK_4
	`define CLK_4 (`CLK_COUNT/4) // 100
`endif

interface i2c_intf;
  logic clk, rst;
  logic [`ADDR_WIDTH-1:0] addr;
  logic [`DATA_WIDTH-1:0] din;
  logic start, oper, ack_err, busy, done; 
endinterface

module top(
  input clk, rst,
  input [`ADDR_WIDTH-1:0] addr,
  input [`DATA_WIDTH-1:0] din,
  input start,
  input oper,
  output ack_err, busy, done
);
  
  wire sda, scl;
  wire ack_errm, ack_errs, donem, dones, busym, busys;
  wire [`DATA_WIDTH-1:0] data_outm, data_outs;
  
  i2c_master m0(clk, rst, start, addr, din, oper, sda, scl, ack_errm, busym, donem, data_outm);
  i2c_slave s0(clk, rst, scl, sda, dones, ack_errs, busys, data_outs);
  
  assign ack_err = ack_errm||ack_errs;
  assign done = donem&&dones;
  assign busy = busym&&busys;
  
endmodule

module i2c_master(
  input clk, rst,
  input start,
  input [`ADDR_WIDTH-1:0] addr,
  input [`DATA_WIDTH-1:0] data_in,
  input oper,
  inout sda,
  output scl,
  output reg ack_err, busy, done,
  output [`DATA_WIDTH-1:0] data_out
);
  
  // Generation of Pulse
  
  reg [1:0] pulse;
  integer count;
  
  always@(posedge clk) begin
    if(rst) begin
      pulse <= 0;
      count <= 0;
    end
    else if(!busy) begin
      pulse <= 0;
      count <= 0;
    end
    else if(count == `CLK_4 - 1) begin // 0-99
      pulse <= 2'b01;
      count <= count + 1;
    end
    else if(count == `CLK_4*2 - 1) begin // 100-199
      pulse <= 2'b10;
      count <= count + 1;
    end
    else if(count == `CLK_4*3 - 1) begin // 200-299
      pulse <= 2'b11;
      count <= count + 1;
    end
    else if(count == `CLK_4*4 - 1) begin // 300-399
      pulse <= 0;
      count <= 0;
    end
    else begin
      count <= count + 1;
    end
  end
  
  // FSM FOR I2C MASTER
  
  reg [`DATA_WIDTH-1:0] temp_din, temp_addr, temp_dout;
  reg sda_temp, scl_temp;
  reg recv_ack;
  reg wr_en;
  integer data_count;
  
  typedef enum bit [3:0] {IDLE, START, ADDR, ADDR_ACK, WRITE, WRITE_ACK, READ, READ_NACK, STOP} states;
  states state;
  
  always@(posedge clk) begin
    if(rst) begin
      state <= IDLE;
      temp_din <= 0;
      temp_dout <= 0;
      temp_addr <= 0;
      sda_temp <= 1'b1;
      scl_temp <= 1'b1;
      recv_ack <= 1'b0; 
      wr_en <= 1'b0;
      data_count <= 0;
      ack_err <= 1'b0;
      done <= 1'b0;
      busy <= 1'b0;
    end
    else begin
      case(state) 
        
        IDLE: begin
          temp_dout <= 0;
          recv_ack <= 1'b0;
          data_count <= 0;
          ack_err <= 1'b0;
          done <= 1'b0;
          if(start) begin
            state <= START;
            temp_din <= data_in;
            temp_addr <= {addr, oper};
            wr_en <= 1'b1;
            busy <= 1'b1;
          end
          else begin
            state <= IDLE;
            temp_din <= 0;
            temp_addr <= 0;
            wr_en <= 1'b0;
            busy <= 1'b0;
          end
        end
        
        START: begin
          case(pulse)
            0: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b1;
            end
            1: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b1;
            end
            2: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b0;
            end
            3: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b0;
            end
          endcase
          if(count == `CLK_4*4-1) begin
            state <= ADDR;
            wr_en <= 1'b1;
            scl_temp <= 1'b0;
          end
          else begin
            state <= START;
          end
        end
        
        ADDR: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
                scl_temp <= 1'b0;
                sda_temp <= 1'b0;
              end
              1: begin
                scl_temp <= 1'b0;
                sda_temp <= temp_addr[7-data_count]; // data can be sent through pulse 0 or 1
              end
              2: begin
                scl_temp <= 1'b1;
                if(sda !== temp_addr[7-data_count]) begin
                  ack_err <= 1'b1;
                end
              end
              3: begin
                scl_temp <= 1'b1;
              end
            endcase
            if(count == `CLK_4*4 - 1) begin
              if(ack_err) begin
                wr_en <= 1'b1;
                state <= STOP;
                scl_temp <= 1'b0;
              end
              else begin
              	data_count <= data_count + 1;
              	state <= ADDR;
              	scl_temp <= 1'b0;
              end
            end
            else begin
              state <= ADDR;
            end
          end
          else begin
            state <= ADDR_ACK;
            data_count <= 0;
            wr_en <= 1'b0;
          end
        end
        
        ADDR_ACK: begin
          case(pulse)
            0: begin
              scl_temp <= 1'b0;
            end
            1: begin
              scl_temp <= 1'b0;
            end
            2: begin
              scl_temp <= 1'b1;
              recv_ack <= sda; // we can receive at 2 or 3 
            end
            3: begin
              scl_temp <= 1'b1;
            end
          endcase
          if(count == `CLK_4*4 - 1) begin
            if(!recv_ack) begin
              if(temp_addr[0] == 1'b0) begin // WRITE
                state <= WRITE;
                wr_en <= 1'b1;
                scl_temp <= 1'b0; // SCL is low after every state change because data change happens only on low scl
              end
              else begin // READ
                state <= READ;
                wr_en <= 1'b0;
                scl_temp <= 1'b0;
              end
            end
            else begin
              ack_err <= 1'b1; 
              state <= STOP;
              wr_en <= 1'b1;
              scl_temp <= 1'b0;
            end
          end
          else begin
            state <= ADDR_ACK;
          end
        end
        
        WRITE: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
                scl_temp <= 1'b0;
                sda_temp <= 1'b0;
              end
              1: begin
                scl_temp <= 1'b0;
                sda_temp <= temp_din[7-data_count];
              end
              2: begin
                scl_temp <= 1'b1;
                if(sda != temp_din[7-data_count]) begin
                  ack_err <= 1'b1;
                end
              end
              3: begin
                scl_temp <= 1'b1;
              end
            endcase
            if(count == `CLK_4*4 - 1) begin
              if(ack_err) begin
                scl_temp <= 1'b0;
                wr_en <= 1'b1;
                state <= STOP;
              end
              else begin
                state <= WRITE;
              	scl_temp <= 1'b0;
              	data_count <= data_count + 1;
              end
            end
            else begin
              state <= WRITE;
            end
          end
          else begin
            wr_en <= 1'b0;
            state <= WRITE_ACK;
            scl_temp <= 1'b0;
            data_count <= 0;
          end
        end
        
        WRITE_ACK: begin
          case(pulse)
            0: begin
              scl_temp <= 1'b0;
            end
            1: begin
              scl_temp <= 1'b0;
            end
            2: begin
              scl_temp <= 1'b1;
              recv_ack <= sda;
            end
            3: begin
              scl_temp <= 1'b1;
            end
          endcase
          if(count == `CLK_4*4 - 1) begin
            if(!recv_ack) begin
              state <= STOP;
              scl_temp <= 1'b0;
              wr_en <= 1'b1; 
            end
            else begin
              ack_err <= 1'b1;
              state <= STOP;
              scl_temp <= 1'b0;
              wr_en <= 1'b1;
            end
          end
          else begin
            state <= WRITE_ACK;
          end
        end
        
        READ: begin
          if(data_count<=7) begin
            case(pulse)
              0: begin
                scl_temp <= 1'b0;
              end
              1: begin
                scl_temp <= 1'b0;
              end
              2: begin
                scl_temp <= 1'b1;
                temp_dout[7:0] <= (count == `CLK_4*2)? {temp_dout[6:0], sda}:temp_dout[7:0];
              end
              3: begin
                scl_temp <= 1'b1;
              end
            endcase
            if(count == `CLK_4*4 - 1) begin
              data_count <= data_count + 1;
              state <= READ;
              scl_temp <= 1'b0;
            end
            else begin
              state <= READ;
            end
          end
          else begin
            state <= READ_NACK;
            wr_en <= 1'b1;
            scl_temp <= 1'b0;
            data_count <= 0;
          end
        end
        
        READ_NACK: begin
          case(pulse) 
            0: begin
              scl_temp <= 1'b0;
            end
            1: begin
              scl_temp <= 1'b0;
              sda_temp <= 1'b1; // negative acknowledgment
            end
            2: begin
              scl_temp <= 1'b1;
            end
            3: begin
              scl_temp <= 1'b1;
            end
          endcase
          if(count == `CLK_4*4 - 1) begin
            state <= STOP;
            wr_en <= 1'b1;
            scl_temp <= 1'b0;
          end
          else begin
            state <= READ_NACK;
          end
        end
        
        STOP: begin
          case(pulse) 
            0: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b0;
            end
            1: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b0;
            end
            2: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b1;
            end
            3: begin
              scl_temp <= 1'b1;
              sda_temp <= 1'b1;
            end
          endcase
          if(count == `CLK_4*4 - 1) begin
            done <= 1'b1;
            wr_en <= 1'b0;
            state <= IDLE;
          end
          else begin
            state <= STOP;
          end
        end
        
        default: state <= IDLE;
        
      endcase
    end
  end
  
  assign scl = scl_temp;
  assign sda = (wr_en) ? sda_temp:1'bz;
  assign data_out = temp_dout;
  
endmodule

module i2c_slave( // can add a address comparing logic
  input clk, rst,
  input scl,
  inout sda,
  output reg done, ack_err, busy,
  output [`DATA_WIDTH-1:0] data_recv
);
  
  // Generation of Pulse
  
  reg [1:0] pulse;
  integer count;
  
  always@(posedge clk) begin
    if(rst) begin
      pulse <= 0;
      count <= 0;
    end
    else if(!busy) begin
      pulse <= 2;
      count <= 200;
    end
    else if(count == `CLK_4 - 1) begin // 0-99
      pulse <= 2'b01;
      count <= count + 1;
    end
    else if(count == `CLK_4*2 - 1) begin // 100-199
      pulse <= 2'b10;
      count <= count + 1;
    end
    else if(count == `CLK_4*3 - 1) begin // 200-299
      pulse <= 2'b11;
      count <= count + 1;
    end
    else if(count == `CLK_4*4 - 1) begin // 300-399
      pulse <= 0;
      count <= 0;
    end
    else begin
      count <= count + 1;
    end
  end
  
  // FSM for I2C SLAVE
  
  typedef enum bit [3:0] {IDLE, START, ADDR, ADDR_ACK, WRITE, WRITE_ACK, READ, READ_NACK, STOP} states;
  states state;
  
  reg sda_temp;
  reg wr_en;
  
  integer data_count;
  
  localparam mem = 8'b01101101;
  
  reg [`DATA_WIDTH-1:0] temp_addr, temp_dout;
  reg recv_ack;
  
  always@(posedge clk) begin
    if(rst) begin
      recv_ack <= 1'b0;
      temp_addr <= 0;
      temp_dout <= 0;
      data_count <= 0;
      wr_en <= 1'b0;
      sda_temp <= 1'b1;
      state <= IDLE;
      ack_err <= 1'b0;
      done <= 1'b0;
      busy <= 1'b0;
    end
    else begin
      case(state)
        
        IDLE: begin
          recv_ack <= 1'b0;
          temp_addr <= 0;
          temp_dout <= 0;
          data_count <= 0;
          wr_en <= 1'b0;
          sda_temp <= 1'b1;
          ack_err <= 1'b0;
          done <= 1'b0;
          if(scl == 1'b1 && sda == 1'b0) begin
            state <= START;
            busy <= 1'b1;
          end
          else begin
            state <= IDLE;
            busy <= 1'b0;
          end
        end
        
        START: begin
          if(count == `CLK_4*4 - 1) begin
            state <= ADDR;
          end
          else begin
            state <= START;
          end
        end
        
        ADDR: begin
          if(data_count <= 7) begin
          	case(pulse)
            	2: begin
                  temp_addr[7:0] <= (count == `CLK_4*2) ? {temp_addr[6:0], sda}:temp_addr[7:0];
            	end
          	endcase
            if(count == `CLK_4*4 - 1) begin
              data_count <= data_count + 1;
              state <= ADDR;
            end
            else begin
              state <= ADDR;
            end
          end
          else begin
            state <= ADDR_ACK;
            wr_en <= 1'b1;
            data_count <= 0;
          end
        end
        
        ADDR_ACK: begin
          case(pulse)
            1: begin
              sda_temp <= 1'b0; // sending ACK
            end
          endcase
          if(count == `CLK_4*4 - 1) begin
            if(temp_addr[0] == 1'b0) begin // WRITE w.r.t master
              wr_en <= 1'b0;
              state <= WRITE;
            end
            else begin // READ w.r.t master
              wr_en <= 1'b1;
              state <= READ;
            end
          end
          else begin
            state <= ADDR_ACK;
          end
        end
        
        WRITE: begin
          if(data_count<=7) begin
            case(pulse)
              2: begin
                temp_dout[7:0] <= (count == `CLK_4*2)? {temp_dout[6:0], sda}:temp_dout[7:0];
              end
            endcase
            if(count == `CLK_4*4 - 1) begin
              data_count <= data_count + 1;
              state <= WRITE;
            end
            else begin
              state <= WRITE;
            end
          end
          else begin
            state <= WRITE_ACK;
            wr_en <= 1'b1;
            data_count <= 0;
          end
        end
        
        WRITE_ACK: begin
          case(pulse) 
            1: begin
              sda_temp <= 1'b0; // sending ACK
            end
          endcase
          if(count == `CLK_4*4 - 1) begin
            state <= STOP;
            wr_en <= 1'b0;
          end
          else begin
            state <= WRITE_ACK;
          end
        end
        
        READ: begin
          if(data_count<=7) begin
            case(pulse)
              1: begin
                sda_temp <= mem[7-data_count];
              end
            endcase
            if(count == `CLK_4*4 - 1) begin
              data_count <= data_count + 1;
              state <= READ;
            end
            else begin
              state <= READ;
            end
          end
          else begin
            state <= READ_NACK;
            wr_en <= 1'b0;
            data_count <= 0;
          end
        end
        
        READ_NACK: begin
          case(pulse) 
            2: begin
              recv_ack <= sda; // receiving NACK
            end
          endcase
          if(count == `CLK_4*4 - 1) begin
            if(recv_ack == 1'b1) begin
              state <= STOP;
            end
            else begin
              ack_err <= 1'b1;
              state <= STOP;
            end
          end
        end
        
        STOP: begin
          if(count == `CLK_4*4 - 1) begin
            state <= IDLE;
            done <= 1'b1;
          end
          else begin
            state <= STOP;
          end
        end
        
        default: state <= IDLE;
        
      endcase
    end
  end
  
  assign sda = (wr_en) ? sda_temp: 1'bz;
  
  assign data_recv = temp_dout;
  
endmodule
