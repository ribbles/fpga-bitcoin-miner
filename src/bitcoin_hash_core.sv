`default_nettype wire

module bitcoin_hash_core #(
    parameter [31:0] START_NONCE = 32'd0,
    parameter [31:0] NONCE_STRIDE = 32'd1
) (
    input clk,
    input start,
    input stop,
    input [255:0] midstate,
    input [95:0] tail,
    input [255:0] target,
    output reg running = 1'b0,
    output reg found = 1'b0,
    output reg [31:0] found_nonce = 32'd0,
    output reg [255:0] found_hash = 256'd0,
    output reg [31:0] current_nonce = 32'd0,
    output reg result_valid = 1'b0,
    output reg [31:0] result_nonce = 32'd0,
    output reg [255:0] result_hash = 256'd0,
    output [7:0] report_byte_out,
    input report_load,
    input report_shift,
    input report_select,
    input [8:0] report_bit_index,
    output report_bit_out
);
    localparam [255:0] SHA256_IV = {
        32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
        32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
    };
    localparam integer EPOCH_WIDTH = 8;
    localparam integer TAG_WIDTH = EPOCH_WIDTH + 32;

    reg [255:0] job_midstate = 256'd0;
    reg [95:0] job_tail = 96'd0;
    reg [255:0] job_target = 256'd0;
    reg [EPOCH_WIDTH-1:0] job_epoch = {EPOCH_WIDTH{1'b0}};
    reg [287:0] report_shift_reg = 288'd0;

    wire inject_valid = running && !found;
    wire [511:0] first_block = {
        job_tail[95:64], job_tail[63:32], job_tail[31:0], current_nonce,
        32'h80000000, 32'h00000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00000000, 32'h00000280
    };
    wire [TAG_WIDTH-1:0] first_tag_in = {job_epoch, current_nonce};
    wire first_valid_out;
    wire [255:0] first_digest;
    wire [TAG_WIDTH-1:0] first_tag_out;

    sha256_compress_pipeline #(
        .TAG_WIDTH(TAG_WIDTH)
    ) first_compression (
        .clk(clk),
        .valid_in(inject_valid),
        .state_in(job_midstate),
        .block_in(first_block),
        .tag_in(first_tag_in),
        .valid_out(first_valid_out),
        .state_out(first_digest),
        .tag_out(first_tag_out)
    );

    wire [511:0] second_block = {
        first_digest,
        32'h80000000, 32'h00000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00000000, 32'h00000100
    };
    wire final_valid;
    wire [255:0] final_digest;
    wire [TAG_WIDTH-1:0] final_tag;

    sha256_compress_pipeline #(
        .TAG_WIDTH(TAG_WIDTH)
    ) second_compression (
        .clk(clk),
        .valid_in(first_valid_out),
        .state_in(SHA256_IV),
        .block_in(second_block),
        .tag_in(first_tag_out),
        .valid_out(final_valid),
        .state_out(final_digest),
        .tag_out(final_tag)
    );

    function [255:0] reverse_bytes_256;
        input [255:0] value;
        integer byte_index;
        begin
            for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1) begin
                reverse_bytes_256[(31 - byte_index) * 8 +: 8] = value[byte_index * 8 +: 8];
            end
        end
    endfunction

    wire [255:0] final_hash_be = reverse_bytes_256(final_digest);
    reg compare_word_valid = 1'b0;
    reg [255:0] compare_word_digest = 256'd0;
    reg [31:0] compare_word_nonce = 32'd0;
    reg [EPOCH_WIDTH-1:0] compare_word_epoch = {EPOCH_WIDTH{1'b0}};
    reg [7:0] compare_word_lt = 8'd0;
    reg [7:0] compare_word_eq = 8'd0;

    reg compare_half_valid = 1'b0;
    reg [255:0] compare_half_digest = 256'd0;
    reg [31:0] compare_half_nonce = 32'd0;
    reg [EPOCH_WIDTH-1:0] compare_half_epoch = {EPOCH_WIDTH{1'b0}};
    reg compare_high_lt = 1'b0;
    reg compare_high_eq = 1'b0;
    reg compare_low_lt = 1'b0;

    wire compare_hash_meets_target =
        compare_high_lt || (compare_high_eq && compare_low_lt);

    wire [287:0] report_payload = {found_nonce, found_hash};
    assign report_byte_out = report_shift_reg[287:280];
    assign report_bit_out = report_select ? report_payload[9'd287 - report_bit_index] : 1'b0;

    always @(posedge clk) begin
        result_valid <= 1'b0;

        // Split the 256-bit target comparison into parallel word compares and
        // a registered two-half priority reduction for the 600 MHz build.
        compare_word_valid <= final_valid;
        if (final_valid) begin
            compare_word_digest <= final_digest;
            compare_word_nonce <= final_tag[31:0];
            compare_word_epoch <= final_tag[TAG_WIDTH-1:32];
            compare_word_lt[7] <= final_hash_be[255:224] < job_target[255:224];
            compare_word_lt[6] <= final_hash_be[223:192] < job_target[223:192];
            compare_word_lt[5] <= final_hash_be[191:160] < job_target[191:160];
            compare_word_lt[4] <= final_hash_be[159:128] < job_target[159:128];
            compare_word_lt[3] <= final_hash_be[127:96] < job_target[127:96];
            compare_word_lt[2] <= final_hash_be[95:64] < job_target[95:64];
            compare_word_lt[1] <= final_hash_be[63:32] < job_target[63:32];
            compare_word_lt[0] <= final_hash_be[31:0] < job_target[31:0];
            compare_word_eq[7] <= final_hash_be[255:224] == job_target[255:224];
            compare_word_eq[6] <= final_hash_be[223:192] == job_target[223:192];
            compare_word_eq[5] <= final_hash_be[191:160] == job_target[191:160];
            compare_word_eq[4] <= final_hash_be[159:128] == job_target[159:128];
            compare_word_eq[3] <= final_hash_be[127:96] == job_target[127:96];
            compare_word_eq[2] <= final_hash_be[95:64] == job_target[95:64];
            compare_word_eq[1] <= final_hash_be[63:32] == job_target[63:32];
            compare_word_eq[0] <= final_hash_be[31:0] == job_target[31:0];
        end

        compare_half_valid <= compare_word_valid;
        if (compare_word_valid) begin
            compare_half_digest <= compare_word_digest;
            compare_half_nonce <= compare_word_nonce;
            compare_half_epoch <= compare_word_epoch;
            compare_high_lt <=
                compare_word_lt[7] ||
                (compare_word_eq[7] && compare_word_lt[6]) ||
                (compare_word_eq[7] && compare_word_eq[6] && compare_word_lt[5]) ||
                (compare_word_eq[7] && compare_word_eq[6] &&
                 compare_word_eq[5] && compare_word_lt[4]);
            compare_high_eq <= &compare_word_eq[7:4];
            compare_low_lt <=
                compare_word_lt[3] ||
                (compare_word_eq[3] && compare_word_lt[2]) ||
                (compare_word_eq[3] && compare_word_eq[2] && compare_word_lt[1]) ||
                (compare_word_eq[3] && compare_word_eq[2] &&
                 compare_word_eq[1] && compare_word_lt[0]);
        end

        if (report_select && report_load) begin
            report_shift_reg <= report_payload;
        end else if (report_select && report_shift) begin
            report_shift_reg <= {report_shift_reg[279:0], 8'h00};
        end

        if (start) begin
            job_midstate <= midstate;
            job_tail <= tail;
            job_target <= target;
            job_epoch <= job_epoch + {{(EPOCH_WIDTH-1){1'b0}}, 1'b1};
            current_nonce <= START_NONCE;
            running <= 1'b1;
            found <= 1'b0;
        end else if (stop) begin
            job_epoch <= job_epoch + {{(EPOCH_WIDTH-1){1'b0}}, 1'b1};
            running <= 1'b0;
            found <= 1'b0;
        end else begin
            if (inject_valid) begin
                current_nonce <= current_nonce + NONCE_STRIDE;
            end

            if (compare_half_valid &&
                (compare_half_epoch == job_epoch) &&
                compare_hash_meets_target) begin
                result_valid <= 1'b1;
                result_nonce <= compare_half_nonce;
                result_hash <= compare_half_digest;
                if (!found) begin
                    found_nonce <= compare_half_nonce;
                    found_hash <= compare_half_digest;
                    found <= 1'b1;
                    running <= 1'b0;
                end
            end
        end
    end
endmodule
`default_nettype wire
