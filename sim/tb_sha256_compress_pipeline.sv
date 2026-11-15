`timescale 1ns/1ps

module tb_sha256_compress_pipeline;
    reg clk = 1'b0;
    reg valid_in = 1'b0;
    reg [255:0] state_in;
    reg [511:0] block_in;
    reg [31:0] tag_in = 32'h12345678;
    wire valid_out;
    wire [255:0] state_out;
    wire [31:0] tag_out;

    sha256_compress_pipeline dut (
        .clk(clk),
        .valid_in(valid_in),
        .state_in(state_in),
        .block_in(block_in),
        .tag_in(tag_in),
        .valid_out(valid_out),
        .state_out(state_out),
        .tag_out(tag_out)
    );

    always #5 clk = ~clk;

    initial begin
        state_in = {
            32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
            32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
        };
        block_in = {
            32'h61626380, 32'h00000000, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000018
        };

        repeat (4) @(posedge clk);
        @(negedge clk);
        valid_in = 1'b1;
        @(negedge clk);
        valid_in = 1'b0;

        wait(valid_out);
        #1;
        if (tag_out !== 32'h12345678) begin
            $display("FAIL pipeline tag: %h", tag_out);
            $finish(1);
        end
        if (state_out !== 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad) begin
            $display("FAIL pipeline sha256 abc: %h", state_out);
            $finish(1);
        end

        $display("PASS pipelined sha256 abc");
        $finish(0);
    end
endmodule

