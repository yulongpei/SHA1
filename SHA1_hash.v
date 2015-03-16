module SHA1_hash (       
	clk, 		
	nreset, 	
	start_hash,  
	message_addr,	
	message_size, 	
	hash, 	
	done, 		
	port_A_clk,
        port_A_data_in,
        port_A_data_out,
        port_A_addr,
        port_A_we
	);
input	clk;
input	nreset;		 // Initializes the SHA1_hash module
input	start_hash;	 // Tells SHA1_hash to start hashing the given frame
input [31:0] message_addr; 
// Starting address of the messagetext frame
// i.e., specifies from where SHA1_hash must read the messagetext frame
input	[31:0] message_size;	 // Length of the message in bytes
output [159:0] hash; // hash results
input  [31:0] port_A_data_out;// read data from the dpsram (messagetext)
output [31:0] port_A_data_in; // write data to the dpsram (ciphertext)
output [15:0] port_A_addr;// address of dpsram being read/written 
output  port_A_clk;   // clock to dpsram (drive this with the input clk) 
output  port_A_we;  // read/write selector for dpsram
output reg done; // done is a signal to indicate that hash  is complete

reg [3:0] state;
reg [15:0] read_addr; 
reg [31:0] w [0:15];
reg [6:0] n;

reg [31:0] h0 = 32'h67452301;
reg [31:0] h1 = 32'hEFCDAB89;
reg [31:0] h2 = 32'h98BADCFE;
reg [31:0] h3 = 32'h10325476;
reg [31:0] h4 = 32'hC3D2E1F0;
reg [31:0] f;
reg [31:0] k;
reg [31:0] temp;
reg [31:0] a;
reg [31:0] b;
reg [31:0] c;
reg [31:0] d;
reg [31:0] e;
reg [3:0] block;
reg [31:0] len;
reg [31:0] pad_length;
reg reading;
reg skip;

parameter IDLE = 0;
parameter READ = 1;
parameter COMPUTE = 2;
parameter COMPUTE2 = 3;
parameter PRE = 4;
parameter POST = 5;

assign port_A_clk = clk;
assign port_A_we = 0;
assign port_A_addr = read_addr;
assign hash = {h0, h1, h2, h3, h4};

function [31:0] changeEndian;
    input [31:0] value;
    changeEndian = {value[7:0], value[15:8], value[23:16], value[31:24]};
endfunction


always @(posedge clk or negedge nreset)begin
	if(!nreset)begin
		state <= IDLE; 
		n <= 8'h0;
		block <= 0;
		skip <= 0;
		reading <= 1;
		read_addr <= 0;
	end
	else begin
		case(state)
			IDLE: begin
				if(start_hash)begin
					state <= PRE;
					read_addr <= message_addr[15:0];
					block <= 0;
					len <= message_size/4;
					reading <= 1;
					n <= 0;
					skip <= 0;
					if ( (message_size + 1) % 64 <= 56 && (message_size + 1) % 64 > 0)
						pad_length = (message_size/64)*64 + 56;
					else
						pad_length = (message_size/64+1)*64 + 56;
					pad_length <= pad_length + 8;
				end
			end
			PRE: begin
				a <= h0;
				b <= h1;
				c <= h2;
				d <= h3;
				e <= h4;
				f <= (h1 & h2) | ((h1 ^ 32'hFFFFFFFF) & h3);
				k <= 32'h5A827999 + h4 + ((h1 & h2) | ((h1 ^ 32'hFFFFFFFF) & h3));
				if(reading) state <= READ;
				else state <= COMPUTE;

			end
			READ: begin
				state <= COMPUTE;
				read_addr <= read_addr+4;
			end
			COMPUTE: begin
				if(len == 0 && reading) begin
					reading = 0;
					len = pad_length/4 - message_size/4 - 1;
					case (message_size % 4)
   						0: w[n] = 32'h80000000;
    						1: w[n] = changeEndian(port_A_data_out) & 32'h FF000000 | 32'h 00800000;
    						2: w[n] = changeEndian(port_A_data_out) & 32'h FFFF0000 | 32'h 00008000;
    						3: w[n] = changeEndian(port_A_data_out) & 32'h FFFFFF00 | 32'h 00000080;
    					endcase
					skip = 0;
				end
				else if(len == 1 &&!reading) begin
					skip = 0;
					w[n] = message_size >> 29;
				end
				else if(len == 0 &&!reading) begin
					skip = 0;
					w[n] = message_size * 8;
				end

				
				if (n <= 18) begin
                			f = (a & ((b << 30)|(b >> 2))) | ((a ^ 32'hFFFFFFFF) & c);
                			k <= 32'h5A827999 + d + f;
            			end else if (n<=38) begin
                			f = a ^ ((b << 30)|(b >> 2)) ^ c;
                			k <= 32'h6ED9EBA1 + d + f;
            			end else if (n<=58) begin
                			f = (a & ((b << 30)|(b >> 2))) | (a & c) | (((b << 30)|(b >> 2)) & c);
               				k <= 32'h8F1BBCDC + d + f;
            			end else begin
                			f = a ^ ((b << 30)|(b >> 2)) ^ c;
                			k <= 32'hCA62C1D6 + d + f;
            			end

				if(n < 16) begin
					if(reading) begin
						w[n] = changeEndian(port_A_data_out);
					end
					else begin
						if(skip) begin
							w[n] = 32'h00000000;
						end
						skip <= 1;
					end
					len <= len - 1;
				end
				else begin
					w[n%16] = w[(n-3)%16] ^ w[(n-8)%16] ^ w[(n-14)%16] ^ w[(n-16)%16];
           				w[n%16] = (w[n%16] << 1) | (w[n%16] >> 31);
 				end
				
				a <= ((a << 5)|(a >> 27)) + k + w[n%16];
            			e <= d;
				d <= c;
            			c <= ((b << 30)|(b >> 2));
            			b <= a;

$display("a = %h\n",a);
$display("b = %h\n",b);
$display("c = %h\n",c);
$display("d = %h\n",d);
$display("e = %h\n",e);
$display("f = %h\n",f);
$display("k = %h\n",k);
$display("w[%d] = %h\n",n,w[n%16]);
				if(reading) begin
					if(n < 15)
						state <= READ;
					else
						state <= COMPUTE;
				end
				else begin
					state <= COMPUTE;
				end
				if(n == 79) begin
					n <= 0;
					block <= block + 1;
					state <= POST;
				end
				else n <= n + 1;
			end
			POST: begin
				h0 <= h0 + a;
				h1 <= h1 + b;
			      	h2 <= h2 + c;
			      	h3 <= h3 + d;
			      	h4 <= h4 + e;
				state <= PRE;
				if(block == pad_length/64) done <= 1;//done
			end
		endcase
	end
end


endmodule

