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

class object;
  
  rand bit [`ADDR_WIDTH-1:0] addr;
  rand bit [`DATA_WIDTH-1:0] din;
  bit start;
  rand bit oper;
  bit ack_err, busy, done;
  
  constraint oper_cons { oper dist {0:=70, 1:=30}; }
  constraint addr_cons { addr >0; addr<15; }
  constraint din_cons {din inside {[1:30]}; }
  
  function void display();
    $display("addr: %b, din: %b, oper: %b", addr, din, oper);
  endfunction
  
endclass

module tb;
  
  i2c_intf intf();
  
  object obj;
  
  top DUT (.clk(intf.clk), .rst(intf.rst), .addr(intf.addr), .din(intf.din), .start(intf.start), .oper(intf.oper), .ack_err(intf.ack_err), .busy(intf.busy), .done(intf.done));
  
  initial begin
    intf.clk <= 1'b0;
  end
  
  always #12.5 intf.clk <= ~intf.clk;
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  
  localparam mem = 8'b01101101; // Data which slave will send in READ MODE w.r.t Master
  
  task reset();
    intf.rst <= 1'b1;
    intf.start <= 1'b0;
    intf.addr <= 0;
    intf.din <= 0;
    intf.oper <= 1'b0;
    repeat(10)@(posedge intf.clk);
    intf.rst <= 1'b0;
    $display("SYSTEM RESETED");
    $display("----------");
  endtask
  
  task read(object obj);
    $display("----------");
    intf.start <= 1'b1;
    intf.oper <= 1'b1;
    intf.addr <= obj.addr;
    wait(DUT.m0.state == 8); // STOP STATE
    
    $display("DATA SENT BY SLAVE: %b", mem);
    $display("DATA RECEIVED BY MASTER: %b", DUT.data_outm);
    
    if(DUT.data_outm == mem) begin
      $display("READ DATA MATCHED");
    end
    else begin
      $display("READ DATA MISMATCHED");
    end
    $display("READING FINISH");
    $display("----------");
    intf.start <= 1'b0;
  endtask
  
  task write(object obj);
    $display("----------");
    intf.start <= 1'b1;
    intf.oper <= 1'b0;
    intf.addr <= obj.addr;
    intf.din <= obj.din;
    
    wait(DUT.m0.state == 8); // STOP STATE
    
    $display("DATA RECEIVED BY SLAVE: %b", DUT.data_outs);
    
    if(obj.din == DUT.data_outs) begin
      $display("WRITE DATA MATCHED");
    end
    else begin
      $display("WRITE DATA MISMATCHED");
    end
    
    $display("WRITING FINISH");
    $display("----------");
    intf.start <= 1'b0;
  endtask
  
  task run();
    obj = new();
    assert(obj.randomize()) else $error("RANDOMIZATION FAILED");
    obj.display();
    
    if(obj.oper) begin
      $display("MASTER READ MODE");
      read(obj);
    end
    else begin
      $display("MASTER WRITE MODE");
      write(obj);
    end
  endtask
  
  initial begin
    repeat(5) begin
    	reset();
    	run();
    end
    $finish();
  end
  
endmodule

