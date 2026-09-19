`default_nettype none

module hsync_generator(
    input  wire clk,
    input  wire rst_n,
    output reg  hsync,
    output reg  vsync,
    output reg  video_active,
    output reg  [9:0] x,
    output reg  [9:0] y
);
    // 640x480 @ 60Hz VGA timing parameters
    parameter H_ACTIVE = 640;
    parameter H_FRONT  = 16;
    parameter H_SYNC   = 96;
    parameter H_BACK   = 48;
    parameter H_TOTAL  = 800;

    parameter V_ACTIVE = 480;
    parameter V_FRONT  = 10;
    parameter V_SYNC   = 2;
    parameter V_BACK   = 33;
    parameter V_TOTAL  = 525;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 0;
            y <= 0;
            hsync <= 1;
            vsync <= 1;
            video_active <= 0;
        end else begin
            // Horizontal and Vertical Counters
            if (x == H_TOTAL - 1) begin
                x <= 0;
                if (y == V_TOTAL - 1)
                    y <= 0;
                else
                    y <= y + 1;
            end else begin
                x <= x + 1;
            end

            // Sync pulse generation (Active Low for standard VGA)
            hsync <= ~(x >= (H_ACTIVE + H_FRONT) && x < (H_ACTIVE + H_FRONT + H_SYNC));
            vsync <= ~(y >= (V_ACTIVE + V_FRONT) && y < (V_ACTIVE + V_FRONT + V_SYNC));

            // Determine if we are in the drawable screen area
            video_active <= (x < H_ACTIVE) && (y < V_ACTIVE);
        end
    end
endmodule