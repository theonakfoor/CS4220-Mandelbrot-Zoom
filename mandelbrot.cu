#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <unistd.h>
#include <string.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <arpa/inet.h>

#define WIDTH 		800
#define HEIGHT		800
#define MAX_ITER	1500
#define NUM_FRAMES	100
#define ZOOM_START	1.5
#define ZOOM_FACTOR	0.85
#define TARGET_X   -0.7435669
#define TARGET_Y    0.1314023
#define OUTPUT_FILE	"frame.ppm"

typedef struct {
	unsigned char r;
	unsigned char g;
	unsigned char b;
} RGB;

double myCPUTimer() {
    struct timeval time;
    gettimeofday(&time, NULL);
    
    return (double) time.tv_sec + (double) time.tv_usec * 1.0e-6;
}

__host__ __device__ RGB iterToColor(int iter, int max_iter, double x, double y) {
	if (iter == max_iter) {
		return RGB{0, 0, 0};
	}

	double log_z = log(x * x + y * y) / 2.0;
	double normalized = log(log_z / log(2.0)) / log(2.0);
	double smooth = (double) iter + 1.0 - normalized;
	double out = smooth / (double) max_iter;

	double r, g, b;
	if (out < 0.5) {
		double s = out / 0.5;
		r = 9.0 * (1-s) * s * s * s;
		g = 15.0 * (1-s) * (1-s) * s * s;
		b = 8.5 * (1-s) * (1-s) * (1-s) * s;
	} else {
		double s = (out - 0.5) / 0.5;
		r = 0.5 + 0.5 * sin(3.14159 * s);
		g = 0.3 + 0.5 * s;
		b = 0.1 + 0.2 * s;
	}

	RGB res = {
		(unsigned char)(fmin(r, 1.0) * 255),
		(unsigned char)(fmin(g, 1.0) * 255),
		(unsigned char)(fmin(b, 1.0) * 255)
	};
	
	return res;
}

int mandelbrot_h(double c_real, double c_imaginary, int max_iter, double* out_x, double* out_y) {
	double x = 0.0, y = 0.0;
	int iter = 0;
	while (x * x + y * y <= 4.0 && iter < max_iter) {
		double xtemp = x * x - y * y + c_real;
		y = 2.0 * x * y + c_imaginary;
		x = xtemp;
		iter++;
	}
	*out_x = x;
	*out_y = y;
	return iter;
}

/* 
Render a full frame on the CPU in a caller-allocated buffer.
pixels		- output buffer of width * height RGB values
width, height 	- width and height of output frame 
cx, xy		- center of view in a complex plane
zoom		- width of view in complex plane units
max_iter	- max iterations for escape-time loop calculations
*/
void render_h(RGB* pixels, int width, int height, double cx, double cy, double zoom, int max_iter,
		double* renderTime) {
	double view_w = zoom;
	double view_h = zoom / ((double) width / height);

	double renderStart = myCPUTimer();
	for(int py = 0; py < height; py++) {
		for(int px = 0; px < width; px++) {
			double c_real = cx + (px - width / 2.0) / width * view_w;
			double c_imaginary = cy + (py - height / 2.0) / height * view_h;
			double x, y;
			int iter = mandelbrot_h(c_real, c_imaginary, max_iter, &x, &y);
			pixels[py * width + px] = iterToColor(iter, max_iter, x, y);
		}
	}
	double renderEnd = myCPUTimer();
	*renderTime += renderEnd - renderStart;
}

__global__ void mandelbrot_d(RGB* pixels, int width, int height, double cx, double cy, double zoom, double max_iter) {
       int px = blockIdx.x * blockDim.x + threadIdx.x;
       int py = blockIdx.y * blockDim.y + threadIdx.y;

       if (px >= width || py >= height) return;

       double view_w = zoom;
       double view_h = zoom / ((double) width / height);

       double c_real = cx + (px - width / 2.0) / width * view_w;
       double c_imaginary = cy + (py - height / 2.0) / height * view_h;

       double x = 0.0, y = 0.0;
       int iter = 0;
       
       while (x * x + y * y <= 4.0 && iter < max_iter) {
		double xtemp = x * x - y * y + c_real;
		y = 2.0 * x * y + c_imaginary;
		x = xtemp;
		iter++;
       }

       pixels[py * width + px] = iterToColor(iter, max_iter, x, y);
}	       

/*
Render a full frame on the GPU with one thread per output pixel.
pixels          - output buffer of width * height RGB values
width, height   - width and height of output frame 
cx, xy          - center of view in a complex plane
zoom            - width of view in complex plane units
max_iter        - max iterations for escape-time loop calculations
*/
void render_d(RGB* pixels, int width, int height, double cx, double cy, double zoom, int max_iter,
		double* cudaMallocTime, double* renderTime, double* cudaMemcpyTime) {
	RGB* d_pixels;
	size_t size = width * height * sizeof(RGB);

	double cudaMallocStart = myCPUTimer();
	cudaMalloc(&d_pixels, size);
	double cudaMallocEnd = myCPUTimer();
	*cudaMallocTime += (cudaMallocEnd - cudaMallocStart);

	dim3 block(16, 16);
	dim3 grid((width + block.x - 1) / block.x,
		  (height + block.y - 1) / block.y);

	double renderStart = myCPUTimer();
	mandelbrot_d<<<grid, block>>>(d_pixels, width, height, cx, cy, zoom, max_iter);
	cudaDeviceSynchronize();
	double renderEnd = myCPUTimer();
	*renderTime += (renderEnd - renderStart);

	double cudaMemcpyStart = myCPUTimer();
	cudaMemcpy(pixels, d_pixels, size, cudaMemcpyDeviceToHost);
	double cudaMemcpyEnd = myCPUTimer();
	*cudaMemcpyTime += (cudaMemcpyEnd - cudaMemcpyStart);
	cudaFree(d_pixels);
}

unsigned char* writePPM(const char* filename, RGB* pixels, int width, int height, int* out_size) {
	FILE* f = fopen(filename, "wb");
	if (!f) {
		fprintf(stderr, "Cannot open filename provided.\n");
		exit(1);
	}
	fprintf(f, "P6\n%d %d\n255\n", width, height);
	fwrite(pixels, sizeof(RGB), width * height, f);
	fclose(f);
	
	char header[64];
	int header_len = snprintf(header, sizeof(header), "P6\n%d %d\n255\n", width, height);

	int pixel_bytes = width * height * sizeof(RGB);
	
	unsigned char* buffer = (unsigned char*) malloc(header_len + pixel_bytes);

	memcpy(buffer, header, header_len);
	memcpy(buffer + header_len, pixels, pixel_bytes);

	*out_size = header_len + pixel_bytes;
	return buffer;
}

void sendFrame(int sock, unsigned char* buffer, int len) {
	uint32_t nlen = htonl(len);
	send(sock, &nlen, 4, 0);
	send(sock, buffer, len, 0);
}

int main(int argc, char* argv[]) {
	int sock = socket(AF_INET, SOCK_STREAM, 0);

	struct sockaddr_in addr;
	addr.sin_family = AF_INET;
	addr.sin_port = htons(9999);
	addr.sin_addr.s_addr = inet_addr("127.0.0.1");

	if (sock < 0) {
		printf("Error: Failed to open TCP socket.\n");
		return -1;
	}

	if (connect(sock, (struct sockaddr*) &addr, sizeof(addr)) < 0) {
		printf("Error: Failed to connect to 127.0.0.1:9999.\n");
		return -1;
	}

	int num_frames = NUM_FRAMES;
	int max_iter = MAX_ITER;

	if (argc < 2) {
		printf("Usage: ./mandelbrot [device/host] [frame width] [frame height]\n");
		return -1;
	}

	char* modality = argv[1];
	int width = WIDTH;
	int height = HEIGHT;

	if (argc == 4) {
		width = atoi(argv[2]);
		height = atoi(argv[3]);
	}

	RGB* pixels = (RGB*) malloc(width * height * sizeof(RGB));
	if (!pixels) {
		fprintf(stderr, "Unable to allocate pixels array.\n");
		return -1;
	}
	
	double zoom = ZOOM_START;

	double cudaMallocTime = 0.0;
	double renderTime = 0.0;
	double cudaMemcpyTime = 0.0;
	double wallTime = 0.0;

	double wallTimeStart = myCPUTimer();
	for (int frame = 0; frame < num_frames; frame++) {
		if (strcmp(modality, "host") == 0) {
			render_h(pixels, width, height, TARGET_X, TARGET_Y, zoom, max_iter,
					&renderTime);
		} else {
			render_d(pixels, width, height, TARGET_X, TARGET_Y, zoom, max_iter, 
					&cudaMallocTime, &renderTime, &cudaMemcpyTime);
		}

		int buffer_size = 0;
		unsigned char* buffer = writePPM(OUTPUT_FILE, pixels, width, height, &buffer_size);
	
		sendFrame(sock, buffer, buffer_size);	
		
		zoom *= ZOOM_FACTOR;
		printf("Wrote frame %d\n", frame + 1);
	}
	double wallTimeEnd = myCPUTimer();
	wallTime = wallTimeEnd - wallTimeStart;

	if (strcmp(modality, "host") == 0) {
		printf("\n");
		printf("HOST RENDER TIME SUMMARY\n");
		printf("TOTAL RENDER TIME:\t%.2fs\n", renderTime);
		printf("TOTAL WALL TIME:\t%.2fs\n", wallTime);
		printf("** Wall time includes disk writes, buffer building time and socket send time.");
		printf("\n\n");
	} else {
		printf("\n");
		printf("DEVICE RENDER TIME SUMMARY\n");
		printf("cudaMalloc Time:\t%.2fs\n", cudaMallocTime);
		printf("Render Time:\t\t%.2fs\n", renderTime);
		printf("cudaMemcpy Time:\t%.2fs\n", cudaMemcpyTime);
		printf("TOTAL RENDER TIME:\t\t%.2fs\n", cudaMallocTime + renderTime + cudaMemcpyTime);
		printf("TOTAL WALL TIME:\t\t%.2fs\n", wallTime);
		printf("** Wall time includes disk writes, buffer building time and socket send time.");
		printf("\n\n");
	}

	free(pixels);
	return 0;
}
