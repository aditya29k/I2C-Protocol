`timescale 1ns/1ps

module I2C_master#(
    parameter clk_frequency = 40000000, // 40MHz
    parameter i2c_frequency = 100000 // 100KHz
)(
    input clk, rst, op,
    inout sda,
    output scl,
    input [7:0] din,
    input [6:0] addr,
    output [7:0] dout,
    output reg ack_err, done, busy,
    input start_bit
);

    // GENERATING CLOCK
    parameter clk_count = clk_frequency/i2c_frequency;
    parameter clk4 = clk_count/4;

    reg [2:0] pulse;
    integer count;

    always@(posedge clk) begin

        if(rst) begin
            pulse <= 0;
            count <= 0;
        end
        else if(busy == 1'b0) begin
            pulse <= 0;
            count <= 0;
        end
        else if(count == clk4 - 1) begin
            pulse <= 1;
            count <= count + 1;
        end
        else if(count == clk4*2 - 1) begin
            pulse <= 2;
            count <= count + 1;
        end
        else if(count == clk4*3 - 1) begin
            pulse <= 3;
            count <= count + 1;
        end
        else if(count == clk4*4 - 1) begin
            pulse <= 0;
            count <= 0;
        end
        else begin
            count <= count + 1;
        end


    end

    // MASTER FSM

    parameter IDLE = 0;
    parameter START = 1;
    parameter ADDR = 2;
    parameter ADDR_ACK = 3;
    parameter WRITE = 4;
    parameter READ = 5;
    parameter SLAVE_ACK = 6;
    parameter MASTER_ACK = 7;
    parameter STOP = 8;

    reg [3:0] NS;

    reg [7:0] temp_data, temp_addr, temp_dout;

    reg recv_ack;

    integer data_count;

    reg wr_en;
    reg scl_temp, sda_temp;

    always@(posedge clk) begin

        if(rst) begin

            busy <= 1'b0;
            temp_data <= 0;
            temp_addr <= 0;
            temp_dout <= 0;
            ack_err <= 0;
            done <= 0;
            data_count <= 0;
            wr_en <= 1'b0;
            NS <= IDLE;
            scl_temp <= 1'b1;
            sda_temp <= 1'b1;

        end
        else begin
            case(NS)

                IDLE: begin
                    done <= 1'b0;
                    temp_dout <= 0;
                    if(start_bit) begin
                        NS <= START;
                        wr_en <= 1'b1;
                        busy <= 1'b1;
                        temp_data <= din;
                        temp_addr <= {addr, op};
                    end
                    else begin
                        NS <= IDLE;
                        wr_en <= 1'b0;
                        temp_data <= 0;
                        busy <= 1'b0;
                        temp_addr <= 0;
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

                    if(count == clk4*4 - 1) begin
                        NS <= ADDR;
                        scl_temp <= 1'b0;
                    end
                    else begin
                        NS <= START;
                    end

                end

                ADDR: begin
                    
                    wr_en <= 1'b1;

                    if(data_count<=7) begin
                        case(pulse)
                            0: begin
                                scl_temp <= 1'b0;
                                sda_temp <= 1'd0;
                            end
                            1: begin
                                scl_temp <= 1'b0;
                                sda_temp <= temp_addr[7-data_count];
                            end
                            2: begin
                                scl_temp <= 1'b1;
                                if(sda != temp_addr[7-data_count]) begin // arbitration
                                    NS <= STOP;
                                    ack_err <= 1'b1;
                                end
                            end
                            3: begin
                                scl_temp <= 1'b1;
                            end
                        endcase

                        if(count == clk4*4 - 1) begin

                            NS <= ADDR;
                            scl_temp <= 1'b0;
                            data_count <= data_count + 1;

                        end
                        else begin
                            NS <= ADDR;
                        end

                    end
                    else begin
                        NS <= ADDR_ACK;
                        wr_en <= 1'b0;
                        data_count <= 0;
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
                            recv_ack <= sda;
                        end
                        3: begin
                            scl_temp <= 1'b1;
                        end

                    endcase

                    if(count == clk4*4 - 1) begin
                        if(recv_ack == 1'b0 && temp_addr[0] == 1'b0) begin
                            NS <= WRITE;
                            wr_en <= 1'b1;
                          sda_temp <= 1'b0;
                        end
                        else if(recv_ack == 1'b0 && temp_addr[0] == 1'b1) begin
                            NS <= READ;
                            wr_en <= 1'b0;
                        end
                        else begin
                            NS <= STOP;
                            ack_err <= 1'b1;
                            wr_en <= 1'b1;
                        end
                    end
                    else begin
                        NS <= ADDR_ACK;
                    end

                end

                WRITE: begin

                    if(data_count <= 7) begin

                        case(pulse)
                            0: begin
                                scl_temp <= 1'b0;
                                sda_temp <= 1'b0;
                            end
                            1: begin
                                scl_temp <= 1'b0;
                                sda_temp <= temp_data[7-data_count];
                            end
                            2: begin
                                scl_temp <= 1'b1;
                            end
                            3: begin
                                scl_temp <= 1'b1;
                            end
                        endcase

                        if(count == clk4*4 - 1) begin
                            NS <= WRITE;
                            data_count <= data_count + 1;
                            scl_temp <= 1'b0;
                        end
                        else begin
                            NS <= WRITE;
                        end

                    end
                    else begin
                        NS <= SLAVE_ACK;
                        wr_en <= 1'b0;
                        data_count <= 0;
                    end

                end

                READ: begin

                    if(data_count <= 7) begin

                        case(pulse)
                            0: begin
                                scl_temp <= 1'b0;
                            end
                            1: begin
                                scl_temp <= 1'b0;
                            end
                            2: begin
                                scl_temp <= 1'b1;
                                temp_dout[7:0] <= (count == 200)? {temp_dout[6:0], sda}:temp_dout;
                            end
                            3: begin
                                scl_temp <= 1'b1;
                            end
                        endcase

                        if(count == clk4*4 - 1) begin
                            NS <= READ;
                            data_count <= data_count + 1;
                            scl_temp <= 1'b0;
                        end
                        else begin
                            NS <= READ;
                        end

                    end
                    else begin
                        NS <= MASTER_ACK;
                        data_count <= 0;
                        wr_en <= 1'b1;
                    end

                end

                SLAVE_ACK: begin

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

                    if(count == clk4*4 - 1) begin
                        if(recv_ack == 1'b0) begin
                            sda_temp <= 1'b0;
                            wr_en <= 1'b1;
                            NS <= STOP;
                            ack_err <= 1'b0;
                        end
                        else begin
                            NS <= STOP;
                            ack_err <= 1'b1;
                            wr_en <= 1'b1;
                            sda_temp <= 1'b0;
                        end
                    end
                    else begin
                        NS <= SLAVE_ACK;
                    end

                end

                MASTER_ACK: begin

                    case(pulse)

                        0: begin
                            scl_temp <= 1'b0;
                            sda_temp <= 1'b1;
                        end
                        1: begin
                            scl_temp <= 1'b0;
                            sda_temp <= 1'b1;
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

                    if(count == clk4*4 - 1) begin
                        sda_temp <= 1'b0;
                        wr_en <= 1'b1;
                        NS <= STOP;
                    end
                    else begin
                        NS <= MASTER_ACK;
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

                    if(count == clk4*4 - 1) begin
                        NS <= IDLE;
                        scl_temp <= 1'b0;
                        busy <= 1'b0;
                        done <= 1'b1; 
                    end
                    else begin
                        NS <= STOP;
                    end

                end

                default: NS <= IDLE;

            endcase
        end

    end

    assign sda = (wr_en == 1'b1) ? sda_temp:1'bz;
    assign scl = scl_temp;
    assign dout = temp_dout;

endmodule

module I2C_slave #(
    parameter clk_frequency = 40000000, //40 MHz
    parameter i2c_frequency = 100000 // 100KHz
)(
    input clk, rst, scl,
    inout sda,
    output reg ack_err, done
);

    // GENERATION OF CLOCK

    reg busy;

    parameter clk_count = clk_frequency/i2c_frequency;
    parameter clk4 = clk_count/4;

    reg [2:0] pulse;
    integer count;

    always@(posedge clk) begin

        if(rst) begin
            pulse <= 0;
            count <= 0;
        end
        else if(~busy) begin
            pulse <= 2;
            count <= 201; // add constant delay for better clock catching
        end
        else if(count == clk4 - 1) begin
            pulse <= 1;
            count <= count + 1;
        end
        else if(count == clk4*2 - 1) begin
            pulse <= 2;
            count <= count + 1;
        end
        else if(count == clk4*3 - 1) begin
            pulse <= 3;
            count <= count + 1;
        end
        else if(count == clk4*4 - 1) begin
            pulse <= 0;
            count <= 0;
        end
        else begin
            count <= count + 1;
        end

    end

    // MEMORY FOR SLAVE

    reg [7:0] dout;
    reg [6:0] addr;
    reg [7:0] din;
    reg [7:0] mem [0:127];
    integer i;
    reg read_mem = 1'b0;
    reg write_mem = 1'b0;

    always@(posedge clk) begin
        if(rst) begin
            dout <= 0;
            for(i = 0; i<128; i = i + 1) begin
                mem[i] <= i;
            end
        end
        else if(read_mem) begin
            dout <= mem[addr];
        end
        else if(write_mem) begin
            mem[addr] <= din;
        end
    end

    // FSM FOR THE SLAVE

    parameter IDLE = 0;
    parameter START = 1;
    parameter ADDR = 2;
    parameter ADDR_ACK = 3;
    parameter READ = 4;
    parameter WRITE = 5;
    parameter SLAVE_ACK = 6;
    parameter MASTER_ACK = 7;
    parameter STOP = 8;

    reg [3:0] state;

    reg [7:0] temp_data, temp_dout, temp_addr;
    reg recv_ack;

    int data_count;

    reg sda_temp;
    reg scl_temp;

    reg wr_en;

    always@(posedge clk) begin
        scl_temp <= scl;
    end

    always@(posedge clk) begin
        if(rst) begin
            data_count <= 0;
            temp_data <= 0;
            temp_addr <= 0;
            temp_dout <= 0;
            addr <= 0;
            state <= IDLE;
            wr_en <= 1'b0;
            ack_err <= 1'b0;
            done <= 1'b0;
            busy <= 1'b0;
        end
        else begin

            case(state)

                IDLE: begin
                    if(scl == 1'b1 && sda == 1'b0) begin
                        busy <= 1'b1;
                        state <= START;
                    end
                    else begin
                        state <= IDLE;
                    end
                end

                START: begin

                    if(count == 399 && pulse == 3) begin
                        state <= ADDR;
                        wr_en <= 1'b0;
                    end
                    else begin
                        state <= START;
                    end

                end

                ADDR: begin
                    if(data_count <= 7) begin
                        case(pulse)
                            0: begin
                            end
                            1: begin
                            end
                            2: begin
                                temp_addr[7:0] <= (count == 200)? {temp_addr[6:0], sda}:temp_addr;
                            end
                            3: begin
                            end
                        endcase

                        if(count == clk4*4 - 1) begin
                            state <= ADDR;
                            data_count <= data_count + 1;
                        end
                        else begin
                            state <= ADDR;
                        end
                    end
                    else begin
                        state <= ADDR_ACK;
                        data_count <= 0;
                        wr_en <= 1'b1;
                        addr <= temp_addr[7:1];
                    end
                end
                
                ADDR_ACK: begin
                    case(pulse)
                    
                        0: begin
                            sda_temp <= 1'b0;
                        end
                        1: begin
                        end
                        2: begin
                        end
                        3: begin
                        end

                    endcase
                    if(count == clk4*4 - 1) begin
                        if(temp_addr[0] == 1'b1) begin
                            state <= WRITE;
                            read_mem <= 1'b1;
                            wr_en <= 1'b1;
                        end
                        else begin
                            state <= READ;
                            wr_en <= 1'b0;
                        end
                    end
                    else begin
                        state <= ADDR_ACK;
                    end
                end

                WRITE: begin
                    read_mem <= 1'b0;
                    if(data_count <= 7) begin
                        case(pulse)

                            0: begin
                            end
                            1: begin
                                sda_temp <= (count == 100)? dout[7-data_count]:sda_temp;
                            end
                            2: begin
                            end
                            3: begin
                            end

                        endcase
                        if(count == clk4*4 - 1) begin
                            state <= WRITE;
                            data_count <= data_count + 1;
                        end
                        else begin
                            state <= WRITE;
                        end
                    end
                    else begin
                        state <= MASTER_ACK;
                        data_count <= 0;
                        wr_en <= 1'b0;
                    end
                end

                MASTER_ACK: begin
                    case(pulse)
                        0: begin
                        end
                        1: begin
                        end
                        2: begin
                            recv_ack <= (count == 200) ? sda:recv_ack;
                        end
                        3: begin
                        end
                    endcase

                    if(count == clk4*4 - 1) begin
                        if(recv_ack) begin
                            ack_err <= 1'b0;
                            state <= STOP;
                            wr_en <= 1'b0;
                        end
                        else begin
                            ack_err <= 1'b1;
                            state <= STOP;
                            wr_en <= 1'b0;
                        end
                    end
                    else begin
                        state <= MASTER_ACK;
                    end
                end

                READ: begin
                    if(data_count <= 7) begin
                        case(pulse)
                            0: begin
                            end
                            1: begin
                            end
                            2: begin
                                din <= (count == 200) ? {din[6:0], sda}: din;
                            end
                            3: begin
                            end
                        endcase
                        if(count == clk4*4 - 1) begin
                            state <= READ;
                            data_count <= data_count + 1;
                        end
                        else begin
                            state <= READ;
                        end
                    end
                    else begin
                        state <= SLAVE_ACK;
                        data_count <= 0;
                        wr_en <= 1'b1;
                        write_mem <= 1'b1;
                    end
                end

                SLAVE_ACK: begin
                    case(pulse)
                        0: begin
                            sda_temp <= 1'b0;
                        end
                        1: begin
                            write_mem <= 1'b0;
                        end
                        2: begin
                        end
                        3: begin
                        end
                    endcase
                    if(count == clk4*4 - 1) begin
                        state <= STOP;
                        wr_en <= 1'b0;
                    end
                    else begin
                        state <= SLAVE_ACK;
                    end
                end

                STOP: begin
                    if(pulse == 3 && count == 399) begin
                        state <= IDLE;
                        busy <= 1'b0;
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

    assign sda = (wr_en == 1'b1)? sda_temp:1'bz;

endmodule

module top(
    input clk, rst, start_bit, op,
    input [6:0] addr,
    input [7:0] din,
    output [7:0] dout,
    output busy, ack_err,
    output done
);

    wire sda, scl;
    wire ack_errm, ack_errs;

    I2C_master DUT0(.clk(clk), .rst(rst), .sda(sda), .scl(scl), .addr(addr), .din(din), .dout(dout), .busy(busy), .ack_err(ack_errm), .done(done), .start_bit(start_bit), .op(op));
    I2C_slave DUT1(.clk(clk), .rst(rst), .sda(sda), .scl(scl), .done(done), .ack_err(ack_errs));

    assign ack_err = ack_errm|ack_errs;

endmodule

interface I2C_intf;

    logic clk, rst;
    logic sda, scl;
    logic [7:0] din, dout;
    logic [6:0] addr;
    logic busy, done, ack_err;
    logic start_bit, op;

endinterface