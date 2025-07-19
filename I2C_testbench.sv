class transaction;

    rand bit [7:0] din;
    rand bit [6:0] addr;
    rand bit op;
    bit [7:0] dout;
    bit sda, scl;
    bit busy;
    bit done, ack_err;
    bit start_bit;

    constraint din_cons { din>0; din<15; }
    constraint addr_cons { addr>0; addr<10; }
  constraint op_cons { op dist { 1:=50, 0:=50 }; }
  

    task display(string s);

        $display("[%0s] op:%0d din:%0d addr: %0d", s, op, din, addr);

    endtask

endclass

class generator;

    transaction trans;

    mailbox #(transaction) mbxgd;

    event done;
    event drvnxt, sconxt;

    int count;

    function new(mailbox #(transaction) mbxgd);

        this.mbxgd = mbxgd;
        trans = new();

    endfunction

    task run();

        repeat(count) begin
			
          $display("-----------");
            assert(trans.randomize()) else $error("[GEN] RANDOMIZATION FAILED");
            mbxgd.put(trans);
            trans.display("GEN");
            @(drvnxt);
            @(sconxt);

        end
        -> done;

    endtask

endclass

class driver;

    transaction trans;

    virtual I2C_intf intf;

    mailbox #(transaction) mbxgd;

    event drvnxt;

    function new(mailbox #(transaction) mbxgd);
        this.mbxgd = mbxgd;
    endfunction

    task reset();

        intf.rst <= 1'b1;
        intf.op <= 1'b0;
        intf.din <= 0;
        intf.addr <= 0;
        intf.start_bit <= 0;
        repeat(10)@(posedge intf.clk);
        intf.rst <= 1'b0;
        $display("[DRV] SYSTEM RESET");
        $display("---------------------");

    endtask

    task read();

        intf.rst <= 1'b0;
        intf.start_bit <= 1'b1;
        intf.op <= 1'b1;
        intf.addr <= trans.addr;
        intf.din <= 0;
        repeat(5)@(posedge intf.clk);
        @(posedge intf.done);
        intf.start_bit <= 1'b0;
      $display("[DRV] op: %0d, addr: %0d, din: %0d", intf.op, intf.addr ,intf.din);
      
    endtask

    task write();

        intf.rst <= 1'b0;
        intf.start_bit <= 1'b1;
        intf.op <= 1'b0;
        intf.addr <= trans.addr;
        intf.din <= trans.din;
        repeat(5)@(posedge intf.clk);
        @(posedge intf.done);
        intf.start_bit <= 1'b0;
        trans.display("DRV");

    endtask

    task run();

        forever begin
          mbxgd.get(trans);
            if(trans.op) begin
                read();
            end
            else begin
                write();
            end
            ->drvnxt;
        end

    endtask

endclass

class monitor;

    transaction trans;

    event parnxt;

    mailbox #(transaction) mbxms;

    virtual I2C_intf intf;

    function new(mailbox #(transaction) mbxms);
        this.mbxms = mbxms;
    endfunction

    task run();

        trans = new();

        forever begin
            @(posedge intf.done);
            trans.op = intf.op;
            trans.din = intf.din;
            trans.addr = intf.addr;
            trans.dout = intf.dout;
            trans.ack_err = intf.ack_err;
            repeat(5) @(posedge intf.clk);
            mbxms.put(trans);
            $display("[MON] op:%0d, addr: %0d, din : %0d, dout:%0d", trans.op, trans.addr, trans.din, trans.dout);
            //->parnxt;
        end

    endtask

endclass

class scoreboard;

    transaction trans;

    mailbox #(transaction) mbxms;

    event sconxt;

    reg [7:0] data_hold;
    reg [7:0] mem [0:127];

    function new(mailbox #(transaction) mbxms);
        this.mbxms = mbxms;
        for(int i = 0; i<128; i++) begin
            mem[i] = 0;
        end
    endfunction
    
    task run();

        forever begin

            mbxms.get(trans);
            data_hold = mem[trans.addr];
            if(trans.op) begin
                if(data_hold == trans.dout) begin
                    $display("[SCO] DATA READ: DATA MATCHED");
                    $display("--------------------");
                end
                else begin
                    $display("[SCO] DATA READ: DATA MISMATCHED");
                    $display("--------------------");
                end
            end
            else begin
                mem[trans.addr] = trans.din;
                $display("[SCO] DATA WRITE DONE: %0d AT ADDR: %0d", trans.din, trans.addr);
            end

            ->sconxt;

        end

    endtask

endclass

class environment;

    transaction trans;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;

    mailbox #(transaction) mbxgd;
    mailbox #(transaction) mbxms;

    event done;

    virtual I2C_intf intf;

    function new(virtual I2C_intf intf);

        mbxgd = new();
        mbxms = new();

        trans = new();
        gen = new(mbxgd);
        drv = new(mbxgd);
        mon = new(mbxms);
        sco = new(mbxms);

        gen.count = 20;

        gen.done = done;
        gen.drvnxt = drv.drvnxt;
       // gen.sconxt = mon.parnxt;
       gen.sconxt = sco.sconxt;


        this.intf = intf;
        drv.intf = intf;
        mon.intf = intf;

    endfunction

    task pre_test();

        drv.reset();

    endtask

    task test();

        fork
            
            gen.run();
            drv.run();
            mon.run();
            sco.run();

        join_any

    endtask

    task post_test();

        wait(done.triggered);
        $finish();

    endtask

    task run();

        pre_test();
        test();
        post_test();

    endtask

endclass

module tb;

    I2C_intf intf();

    environment env;

    top DUT(.clk(intf.clk), .rst(intf.rst), .op(intf.op), .start_bit(intf.start_bit), .addr(intf.addr), .din(intf.din), .dout(intf.dout), .busy(intf.busy), .ack_err(intf.ack_err), .done(intf.done));

    initial begin

        intf.clk <= 1'b0;

    end

    always #5 intf.clk <= ~intf.clk;

    initial begin
        env = new(intf);
        env.run();
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end

endmodule

interface I2C_intf;

    logic clk, rst;
    logic sda, scl;
    logic [7:0] din, dout;
    logic [6:0] addr;
    logic busy, done, ack_err;
    logic start_bit, op;

endinterface