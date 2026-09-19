`default_nettype none

// Note Frequency Defines
`define C2   241
`define E2   191
`define G2   161
`define A2   143 
`define B2   127
`define C3   120
`define E3   95
`define F3   90
`define G3   80
`define A3   72
`define C4   60
`define D4   54
`define E4   48
`define G4   40
`define C5   30
`define E5   24
`define G5   20

module tt_um_vga_seasons (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high)
    input  wire       ena,      // Always 1 when design is enabled
    input  wire       clk,      // System clock (25.175 MHz for VGA)
    input  wire       rst_n     // reset_n - low to reset
);

    // ==========================================
    // INPUT CONTROLS
    // ==========================================
    wire [1:0] season       = ui_in[1:0];
    wire       animate      = ui_in[2]; 
    wire       en_ufo       = ui_in[3]; 
    wire       en_volcano   = ui_in[4]; 
    wire       en_thunder   = ui_in[5]; 
    wire       en_quake     = ui_in[6]; 
    wire       en_mascots   = ui_in[7]; 

    // Gamepad D-PAD Mapping from ui_in[3:0] when Mascot/Game mode (ui_in[7]) is ON
    wire btn_left  = en_mascots & ui_in[2]; // Left arrow
    wire btn_right = en_mascots & ui_in[3]; // Right arrow
    wire btn_up    = en_mascots & ui_in[0]; // Up arrow
    wire btn_down  = en_mascots & ui_in[1]; // Down arrow

    // Internal VGA signals
    wire [9:0] x, y;
    wire hsync, vsync, video_active;

    hsync_generator sync_gen (
        .clk(clk), .rst_n(rst_n),
        .hsync(hsync), .vsync(vsync), .video_active(video_active),
        .x(x), .y(y)
    );

    // ==========================================
    // FRAME COUNTER & MARIO GAMEPAD MOVEMENT
    // ==========================================
    reg [11:0] frame_ctr;
    reg [9:0]  ma_x;
    reg [9:0]  ma_y;
    wire frame_tick = (x == 0 && y == 0); 
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_ctr <= 0;
            ma_x <= 10'd280;
            ma_y <= 10'd300;
        end else if (frame_tick) begin
            frame_ctr <= frame_ctr + 1;
            
            if (en_mascots) begin
                if (btn_left  && ma_x > 10)  ma_x <= ma_x - 10'd3; 
                if (btn_right && ma_x < 600) ma_x <= ma_x + 10'd3; 
                if (btn_up    && ma_y > 10)  ma_y <= ma_y - 10'd3; 
                if (btn_down  && ma_y < 440) ma_y <= ma_y + 10'd3; 
            end else begin
                // Reset Mario's position when Mascot mode is toggled off
                ma_x <= 10'd280;
                ma_y <= 10'd300;
            end
        end
    end

    // ==========================================
    // AUDIO ENGINE
    // ==========================================
    reg [7:0] note_counter;
    reg       note;
    reg [7:0] note_freq;

    reg [12:0] lfsr;
    wire feedback = lfsr[12] ^ lfsr[8] ^ lfsr[2] ^ lfsr[0] + 1'b1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lfsr <= 13'h1FFF;
        else lfsr <= {lfsr[11:0], feedback};
    end
    wire noise = lfsr[0];

    wire [3:0] beat = frame_ctr[7:4]; 
    wire note_active = (frame_ctr[3:0] < 4'd10); 

    always @(*) begin
        if (en_mascots) begin
            case (beat[2:0])
                3'd0: note_freq = `C4;
                3'd1: note_freq = `D4;
                3'd2: note_freq = `E4;
                3'd3: note_freq = 0;   
                3'd4: note_freq = `C4;
                3'd5: note_freq = `E4;
                default: note_freq = 0;
            endcase
        end else if (en_ufo) begin
            note_freq = `C3 - frame_ctr[5:1];
        end else if (en_quake) begin
            note_freq = 250; 
        end else begin
            case (season)
                2'b00: begin 
                    case (beat[1:0])
                        2'b00: note_freq = `E5;
                        2'b01: note_freq = `G5;
                        2'b10: note_freq = `C5;
                        2'b11: note_freq = 0;
                    endcase
                end
                2'b01: begin 
                    case (beat[1:0])
                        2'b00: note_freq = `C3;
                        2'b01: note_freq = 0;
                        2'b10: note_freq = `G3;
                        2'b11: note_freq = 0;
                    endcase
                end
                2'b10: begin 
                    case (beat[2:0])
                        3'd0: note_freq = `A3;
                        3'd1: note_freq = `G3;
                        3'd2: note_freq = `F3;
                        3'd3: note_freq = `E3;
                        default: note_freq = 0;
                    endcase
                end
                2'b11: begin 
                    case (beat[2:0])
                        3'd0: note_freq = `C5;
                        3'd4: note_freq = `E5;
                        default: note_freq = 0; 
                    endcase
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            note_counter <= 0;
            note <= 0;
        end else if (x == 0) begin
            if (note_freq == 0) begin
                note <= 0; 
            end else if (note_counter >= note_freq) begin
                note_counter <= 0;
                note <= ~note;
            end else begin
                note_counter <= note_counter + 1'b1;
            end
        end
    end

    wire final_tone = note & note_active; 
    wire crackle = noise & frame_ctr[2];  
    wire sound = (en_thunder || en_volcano) ? crackle : (en_ufo ? note : final_tone);

    assign uio_out = {sound, 7'b0000000}; 
    assign uio_oe  = 8'hFF;

    // ==========================================
    // GRAPHICS & SPRITE RENDERING ENGINE
    // ==========================================
    wire [9:0] anim_offset = animate ? (frame_ctr[9:0] >> 1) : 10'd0;
    wire [9:0] shake_x = en_quake ? (frame_ctr[2] ? 10'd5 : -10'd5) : 10'd0;
    wire [9:0] shake_y = en_quake ? (frame_ctr[3] ? 10'd3 : -10'd3) : 10'd0;
    wire [9:0] x_eq = x + shake_x;
    wire [9:0] y_eq = y + shake_y;

    wire [9:0] ufo_x            = (frame_ctr[9:0] % 640);
    wire [9:0] dist_from_center = (x_eq > 320) ? (x_eq - 320) : (320 - x_eq);
    wire [9:0] person1_x        = anim_offset % 640;
    wire [9:0] person2_x        = 640 - ((anim_offset * 2) % 640);
    wire [9:0] person_y_base    = en_quake ? 360 : 330; 
    
    wire [9:0] jb_x = 100;
    wire [9:0] jb_y = 300 + (frame_ctr[4] ? 5 : 0); 
    wire [9:0] mc_x = 480 + (frame_ctr[5] ? 2 : 0); 
    wire [9:0] mc_y = 300;

    wire jb_active, mc_active, ma_active;
    wire [3:0] jb_r, jb_g, jb_b;
    wire [3:0] mc_r, mc_g, mc_b;
    wire [3:0] ma_r, ma_g, ma_b;

    jollibee_sprite jb_inst (
        .draw_x(x_eq), .draw_y(y_eq),
        .player_x(jb_x), .player_y(jb_y),
        .sprite_active(jb_active),
        .red(jb_r), .green(jb_g), .blue(jb_b)
    );

    ronald_mcdonald_sprite mc_inst (
        .draw_x(x_eq), .draw_y(y_eq),
        .player_x(mc_x), .player_y(mc_y),
        .sprite_active(mc_active),
        .red(mc_r), .green(mc_g), .blue(mc_b)
    );

    mario_sprite ma_inst (
        .draw_x(x_eq), .draw_y(y_eq),
        .player_x(ma_x), .player_y(ma_y), // Driven directly by ui_in[3:0] gamepad buttons!
        .sprite_active(ma_active),
        .red(ma_r), .green(ma_g), .blue(ma_b)
    );

    reg [1:0] r, g, b;

    always @(*) begin
        r = 2'b00; g = 2'b00; b = 2'b00;

        if (video_active) begin
            case (season)
                2'b00: begin
                    b = 2'b11; g = 2'b10; r = y_eq[7:6]; 
                    if (x_eq > 120 && x_eq < 180 && y_eq > 60 && y_eq < 120) {r, g, b} = 6'b11_11_00; 
                    if (animate) begin
                        if (x_eq > (100 + anim_offset) && x_eq < (180 + anim_offset) && y_eq > 80 && y_eq < 100) {r, g, b} = 6'b11_11_11;
                        if (x_eq > (400 + anim_offset[8:1]) && x_eq < (450 + anim_offset[8:1]) && y_eq > 50 && y_eq < 70) {r, g, b} = 6'b11_11_11;
                    end
                    if (y_eq > 340) {r, g, b} = 6'b00_11_00; 
                end
                2'b01: begin 
                    b = 2'b11; g = 2'b11; r = 2'b01; 
                    if (x_eq > 300 && x_eq < 380 && y_eq > 80 && y_eq < 160) {r, g, b} = 6'b11_10_00; 
                    if (y_eq > 300 && y_eq < 400) begin
                        {r, g, b} = 6'b00_10_11; 
                        if (animate && ((x_eq + anim_offset) % 32 < 16) && (y_eq % 16 < 8)) {r, g, b} = 6'b01_11_11; 
                    end
                    if (y_eq >= 400) {r, g, b} = 6'b11_11_01; 
                end
                2'b10: begin 
                    r = 2'b11; g = 2'b01; b = 2'b00; 
                    if (x_eq > 450 && x_eq < 510 && y_eq > 250 && y_eq < 310) {r, g, b} = 6'b11_01_00; 
                    if (y_eq > 340) {r, g, b} = 6'b10_01_00; 
                    if (animate && ((x_eq + y_eq + (anim_offset << 1)) % 32 == 0) && (x_eq % 8 == 0)) {r, g, b} = 6'b01_01_11; 
                end
                2'b11: begin 
                    r = 2'b00; g = 2'b00; b = 2'b01; 
                    if (x_eq > 200 && x_eq < 240 && y_eq > 100 && y_eq < 140) {r, g, b} = 6'b10_10_11; 
                    if (y_eq > 340) {r, g, b} = 6'b11_11_11; 
                    if (animate && (((x_eq ^ y_eq) & 10'b0001111111) == 0) && (((y_eq - anim_offset) & 10'b0000011111) == 0)) {r, g, b} = 6'b11_11_11; 
                end
            endcase

            if (en_ufo) begin
                if (y_eq < 340) begin
                    r = 2'b00; g = 2'b00; b = 2'b01;
                    if (((x_eq ^ y_eq) & 10'b0001111111) == 0) {r,g,b} = 6'b11_11_11;
                end
                if (x_eq > ufo_x && x_eq < ufo_x + 60 && y_eq > 60 && y_eq < 80) begin
                    {r, g, b} = frame_ctr[3] ? 6'b11_00_00 : 6'b01_11_01; 
                end
            end

            if (en_volcano) begin
                if (y_eq > 480 - dist_from_center) {r, g, b} = 6'b01_00_00;
                if (x_eq > 300 && x_eq < 340 && y_eq < 400 && y_eq > 200) begin
                    if (((x_eq ^ y_eq) & frame_ctr[5:2]) == 4'b0000) {r, g, b} = 6'b11_01_00;
                end
            end

            if (en_thunder) begin
                if (frame_ctr[6] && frame_ctr[4]) {r, g, b} = 6'b11_11_11; 
                else if (((x_eq ^ y_eq) & 10'b0001111111) == 0 && (x_eq % 64 < 8)) {r, g, b} = 6'b11_11_11;
            end

            if (((x_eq > person1_x && x_eq < person1_x + 10) || 
                 (x_eq > person2_x && x_eq < person2_x + 10)) && 
                (y_eq > person_y_base && y_eq < person_y_base + 30)) begin
                {r, g, b} = 6'b00_00_00; 
            end

            if (en_mascots) begin
                if (jb_active) begin
                    r = jb_r[3:2]; g = jb_g[3:2]; b = jb_b[3:2];
                end else if (mc_active) begin
                    r = mc_r[3:2]; g = mc_g[3:2]; b = mc_b[3:2];
                end else if (ma_active) begin
                    r = ma_r[3:2]; g = ma_g[3:2]; b = ma_b[3:2];
                end
            end
        end
    end

    assign uo_out = {hsync, b[0], g[0], r[0], vsync, b[1], g[1], r[1]};

endmodule

// ==========================================
// EXTERNAL SPRITE MODULES
// ==========================================

module mario_sprite (
    input wire [9:0] draw_x,     
    input wire [9:0] draw_y,     
    input wire [9:0] player_x,   
    input wire [9:0] player_y,   
    output reg       sprite_active,
    output reg [3:0] red,        
    output reg [3:0] green,      
    output reg [3:0] blue        
);
    parameter WIDTH = 32;
    parameter HEIGHT = 32;
    wire [5:0] local_x = draw_x - player_x;
    wire [5:0] local_y = draw_y - player_y;

    localparam [11:0] COLOR_RED   = 12'hF_0_0; 
    localparam [11:0] COLOR_BLUE  = 12'h0_0_F; 
    localparam [11:0] COLOR_SKIN  = 12'hF_C_9; 
    localparam [11:0] COLOR_BROWN = 12'h6_3_0; 
    localparam [11:0] COLOR_GOLD  = 12'hF_D_0; 

    always @(*) begin
        if ((draw_x >= player_x) && (draw_x < player_x + WIDTH) &&
            (draw_y >= player_y) && (draw_y < player_y + HEIGHT)) begin
            sprite_active = 1'b1;
            
            if (local_y >= 2 && local_y <= 6) begin
                if ((local_x >= 8 && local_x <= 22) || (local_y == 6 && local_x >= 6 && local_x <= 26)) 
                    {red, green, blue} = COLOR_RED;
                else sprite_active = 1'b0; 
            end else if (local_y >= 7 && local_y <= 16) begin
                if (local_x >= 6 && local_x <= 24) begin
                    if ((local_x >= 6 && local_x <= 9 && local_y <= 12) || 
                        (local_y >= 13 && local_y <= 15 && local_x >= 14 && local_x <= 22))
                        {red, green, blue} = COLOR_BROWN;
                    else if (local_y >= 8 && local_y <= 11 && local_x == 18)
                        {red, green, blue} = COLOR_BROWN;
                    else if (local_y >= 10 && local_y <= 12 && local_x >= 20 && local_x <= 25)
                        {red, green, blue} = COLOR_SKIN;
                    else
                        {red, green, blue} = COLOR_SKIN;
                end else sprite_active = 1'b0;
            end else if (local_y >= 17 && local_y <= 27) begin
                if (local_x >= 4 && local_x <= 26) begin
                    if (local_y >= 21 && local_y <= 23 && (local_x == 10 || local_x == 20))
                        {red, green, blue} = COLOR_GOLD;
                    else if ((local_x >= 10 && local_x <= 20) || (local_y >= 24))
                        {red, green, blue} = COLOR_BLUE;
                    else
                        {red, green, blue} = COLOR_RED;
                end else sprite_active = 1'b0;
            end else if (local_y >= 28 && local_y <= 31) begin
                if ((local_x >= 2 && local_x <= 12) || (local_x >= 18 && local_x <= 28)) 
                    {red, green, blue} = COLOR_BROWN;
                else sprite_active = 1'b0;
            end else begin
                sprite_active = 1'b0; {red, green, blue} = 12'h0_0_0;
            end
        end else begin
            sprite_active = 1'b0; {red, green, blue} = 12'h0_0_0;
        end
    end
endmodule

module jollibee_sprite (
    input wire [9:0] draw_x,     
    input wire [9:0] draw_y,     
    input wire [9:0] player_x,   
    input wire [9:0] player_y,   
    output reg       sprite_active,
    output reg [3:0] red,        
    output reg [3:0] green,      
    output reg [3:0] blue        
);
    parameter WIDTH = 32;
    parameter HEIGHT = 32;
    wire [5:0] local_x = draw_x - player_x;
    wire [5:0] local_y = draw_y - player_y;

    localparam [11:0] COLOR_HAT   = 12'hF_F_F; 
    localparam [11:0] COLOR_FACE  = 12'hF_D_C; 
    localparam [11:0] COLOR_EYES  = 12'h1_1_1; 
    localparam [11:0] COLOR_SUIT  = 12'hE_0_0; 
    localparam [11:0] COLOR_ACCENT= 12'hF_A_0; 

    always @(*) begin
        if ((draw_x >= player_x) && (draw_x < player_x + WIDTH) &&
            (draw_y >= player_y) && (draw_y < player_y + HEIGHT)) begin
            sprite_active = 1'b1;
            
            if (local_y >= 0 && local_y <= 6) begin
                if (local_x >= 10 && local_x <= 21) {red, green, blue} = COLOR_HAT;
                else sprite_active = 1'b0; 
            end else if (local_y >= 7 && local_y <= 16) begin
                if (local_x >= 7 && local_x <= 24 && !(local_y == 7 && (local_x == 7 || local_x == 24))) begin
                    if (local_y >= 10 && local_y <= 12 && ((local_x >= 10 && local_x <= 12) || (local_x >= 19 && local_x <= 21))) 
                        {red, green, blue} = COLOR_EYES;
                    else if (local_y == 14 && local_x >= 14 && local_x <= 17) 
                        {red, green, blue} = 12'hD_3_3; 
                    else {red, green, blue} = COLOR_FACE;
                end else sprite_active = 1'b0;
            end else if (local_y >= 17 && local_y <= 19) begin
                if (local_x >= 8 && local_x <= 23) begin
                    if (local_y == 18 && local_x >= 13 && local_x <= 18) {red, green, blue} = COLOR_ACCENT;
                    else {red, green, blue} = COLOR_SUIT;
                end else sprite_active = 1'b0;
            end else if (local_y >= 20 && local_y <= 29) begin
                if (local_x >= 6 && local_x <= 25) begin
                    if (local_y == 23 && local_x == 15) {red, green, blue} = COLOR_ACCENT;
                    else {red, green, blue} = COLOR_SUIT;
                end else sprite_active = 1'b0;
            end else if (local_y >= 30 && local_y <= 31) begin
                if ((local_x >= 8 && local_x <= 12) || (local_x >= 19 && local_x <= 23)) {red, green, blue} = 12'h2_1_1; 
                else sprite_active = 1'b0;
            end else begin
                sprite_active = 1'b0; {red, green, blue} = 12'h0_0_0;
            end
        end else begin
            sprite_active = 1'b0; {red, green, blue} = 12'h0_0_0;
        end
    end
endmodule

module ronald_mcdonald_sprite (
    input wire [9:0] draw_x,     
    input wire [9:0] draw_y,     
    input wire [9:0] player_x,   
    input wire [9:0] player_y,   
    output reg       sprite_active,
    output reg [3:0] red,        
    output reg [3:0] green,      
    output reg [3:0] blue        
);
    parameter WIDTH = 32;
    parameter HEIGHT = 32;
    wire [5:0] local_x = draw_x - player_x;
    wire [5:0] local_y = draw_y - player_y;

    localparam [11:0] COLOR_HAIR        = 12'hF_0_0; 
    localparam [11:0] COLOR_FACE        = 12'hF_E_D; 
    localparam [11:0] COLOR_SUIT        = 12'hF_F_F; 
    localparam [11:0] COLOR_OVERALLS    = 12'hF_0_0; 
    localparam [11:0] COLOR_ARCH        = 12'hF_D_0; 
    localparam [11:0] COLOR_SHOES       = 12'h5_2_1; 

    always @(*) begin
        if ((draw_x >= player_x) && (draw_x < player_x + WIDTH) &&
            (draw_y >= player_y) && (draw_y < player_y + HEIGHT)) begin
            sprite_active = 1'b1;
            
            if (local_y >= 0 && local_y <= 8) begin
                if ((local_x >= 4 && local_x <= 27) && !(local_y == 0 && (local_x < 8 || local_x > 23))) {red, green, blue} = COLOR_HAIR;
                else sprite_active = 1'b0; 
            end else if (local_y >= 9 && local_y <= 18) begin
                if (local_x >= 8 && local_x <= 23) begin
                    if ((local_y == 11 && (local_x == 11 || local_x == 20)) || (local_y == 15 && (local_x >= 13 && local_x <= 18))) 
                        {red, green, blue} = 12'h2_1_1; 
                    else {red, green, blue} = COLOR_FACE; 
                end else sprite_active = 1'b0;
            end else if (local_y >= 19 && local_y <= 27) begin
                if (local_x >= 6 && local_x <= 25) begin
                    if (local_y >= 21 && local_y <= 24 && ((local_x >= 14 && local_x <= 15) || (local_x >= 16 && local_x <= 17))) {red, green, blue} = COLOR_ARCH;
                    else if (local_x <= 9 || local_x >= 22 || local_y >= 23) {red, green, blue} = COLOR_OVERALLS;
                    else {red, green, blue} = COLOR_SUIT;
                end else sprite_active = 1'b0;
            end else if (local_y >= 28 && local_y <= 31) begin
                if ((local_x >= 7 && local_x <= 12) || (local_x >= 19 && local_x <= 24)) {red, green, blue} = COLOR_SHOES;
                else sprite_active = 1'b0;
            end else begin
                sprite_active = 1'b0; {red, green, blue} = 12'h0_0_0;
            end
        end else begin
            sprite_active = 1'b0; {red, green, blue} = 12'h0_0_0; 
        end
    end
endmodule