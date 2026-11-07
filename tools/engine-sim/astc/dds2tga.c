/* BAR Droid (docs/ENGINE-SIM.md, ASTC unit textures): a DDS model texture's mipmap levels as 32-bit TGA files, the
 * way the engine uploads them (nv_dds flips unit textures vertically: the first row written is the file's last), from
 * the first level no larger than <maxside> on a side down to 1x1. astcenc then encodes each level.
 *   dds2tga <in.dds> <out-prefix> <maxside>     writes <out-prefix>.<n>.tga, prints "levels <n> <w> <h> <fourcc>"
 * DXT1, DXT3, DXT5 and uncompressed 32/24-bit RGB(A). Build: gcc -O2 -o dds2tga.exe dds2tga.c (w64devkit). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t rd32(const uint8_t* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24); }

static void rgb565(uint16_t c, uint8_t* o) {
	o[0] = (uint8_t)(((c >> 11) & 31) * 255 / 31);
	o[1] = (uint8_t)(((c >> 5) & 63) * 255 / 63);
	o[2] = (uint8_t)((c & 31) * 255 / 31);
}

/* one 4x4 colour block into px (rgba, stride in pixels); dxt1: 3-colour mode with transparent black allowed */
static void color_block(const uint8_t* b, uint8_t* px, int stride, int w, int h, int x0, int y0, int dxt1) {
	uint16_t c0 = b[0] | (b[1] << 8), c1 = b[2] | (b[3] << 8);
	uint8_t c[4][4];
	rgb565(c0, c[0]); rgb565(c1, c[1]);
	c[0][3] = c[1][3] = 255;
	if (c0 > c1 || !dxt1) {
		for (int i = 0; i < 3; i++) {
			c[2][i] = (uint8_t)((2 * c[0][i] + c[1][i] + 1) / 3);
			c[3][i] = (uint8_t)((c[0][i] + 2 * c[1][i] + 1) / 3);
		}
		c[2][3] = c[3][3] = 255;
	} else {
		for (int i = 0; i < 3; i++) c[2][i] = (uint8_t)((c[0][i] + c[1][i]) / 2);
		c[2][3] = 255;
		c[3][0] = c[3][1] = c[3][2] = 0; c[3][3] = 0;
	}
	uint32_t idx = rd32(b + 4);
	for (int y = 0; y < 4; y++)
		for (int x = 0; x < 4; x++) {
			int sel = (idx >> (2 * (y * 4 + x))) & 3;
			int X = x0 + x, Y = y0 + y;
			if (X < w && Y < h) memcpy(px + 4 * ((size_t)Y * stride + X), c[sel], dxt1 ? 4 : 3);
		}
}

static void alpha_dxt3(const uint8_t* b, uint8_t* px, int stride, int w, int h, int x0, int y0) {
	for (int y = 0; y < 4; y++)
		for (int x = 0; x < 4; x++) {
			int n = y * 4 + x, v = (b[n / 2] >> (4 * (n & 1))) & 15;
			int X = x0 + x, Y = y0 + y;
			if (X < w && Y < h) px[4 * ((size_t)Y * stride + X) + 3] = (uint8_t)(v * 17);
		}
}

static void alpha_dxt5(const uint8_t* b, uint8_t* px, int stride, int w, int h, int x0, int y0) {
	uint8_t a[8];
	a[0] = b[0]; a[1] = b[1];
	if (a[0] > a[1]) {
		for (int i = 1; i < 7; i++) a[i + 1] = (uint8_t)(((7 - i) * a[0] + i * a[1] + 3) / 7);
	} else {
		for (int i = 1; i < 5; i++) a[i + 1] = (uint8_t)(((5 - i) * a[0] + i * a[1] + 2) / 5);
		a[6] = 0; a[7] = 255;
	}
	uint64_t bits = 0;
	for (int i = 0; i < 6; i++) bits |= (uint64_t)b[2 + i] << (8 * i);
	for (int y = 0; y < 4; y++)
		for (int x = 0; x < 4; x++) {
			int sel = (int)((bits >> (3 * (y * 4 + x))) & 7);
			int X = x0 + x, Y = y0 + y;
			if (X < w && Y < h) px[4 * ((size_t)Y * stride + X) + 3] = a[sel];
		}
}

static int shift_of(uint32_t m) { int s = 0; if (!m) return 0; while (!(m & 1)) { m >>= 1; s++; } return s; }

int main(int argc, char** argv) {
	if (argc < 4) { fprintf(stderr, "dds2tga <in.dds> <out-prefix> <maxside>\n"); return 2; }
	FILE* f = fopen(argv[1], "rb");
	if (!f) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
	fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
	uint8_t* d = (uint8_t*)malloc(n);
	if (fread(d, 1, n, f) != (size_t)n) { fclose(f); return 1; }
	fclose(f);
	if (n < 128 || memcmp(d, "DDS ", 4)) { fprintf(stderr, "not a DDS\n"); return 1; }
	const uint8_t* hd = d + 4;
	uint32_t height = rd32(hd + 8), width = rd32(hd + 12), mips = rd32(hd + 24);
	uint32_t pfFlags = rd32(hd + 76), fourcc = rd32(hd + 80), bpp = rd32(hd + 84);
	uint32_t rm = rd32(hd + 88), gm = rd32(hd + 92), bm = rd32(hd + 96), am = rd32(hd + 100);
	uint32_t caps2 = rd32(hd + 108);
	if (caps2 & 0x200) { fprintf(stderr, "cubemap: not handled\n"); return 1; }
	if (mips == 0) mips = 1;
	int kind; /* 1 dxt1, 3 dxt3, 5 dxt5, 0 uncompressed */
	if (pfFlags & 4) {
		if (fourcc == 0x31545844) kind = 1; else if (fourcc == 0x33545844) kind = 3; else if (fourcc == 0x35545844) kind = 5;
		else { fprintf(stderr, "fourcc %.4s not handled\n", (char*)&fourcc); return 1; }
	} else if (bpp == 32 || bpp == 24) kind = 0;
	else { fprintf(stderr, "format not handled (%u bpp)\n", bpp); return 1; }
	int maxSide = atoi(argv[3]);
	size_t off = 128;
	int written = 0, firstW = 0, firstH = 0;
	for (uint32_t lv = 0; lv < mips; lv++) {
		int w = width >> lv, h = height >> lv;
		if (w < 1) w = 1;
		if (h < 1) h = 1;
		size_t size = kind ? (size_t)((w + 3) / 4) * ((h + 3) / 4) * (kind == 1 ? 8 : 16) : (size_t)w * h * (bpp / 8);
		if (off + size > (size_t)n) { fprintf(stderr, "file too short at level %u\n", lv); return 1; }
		if ((maxSide > 0 && (w > maxSide || h > maxSide))) { off += size; continue; }
		uint8_t* px = (uint8_t*)calloc((size_t)w * h, 4);
		const uint8_t* s = d + off;
		if (kind) {
			for (int by = 0; by < (h + 3) / 4; by++)
				for (int bx = 0; bx < (w + 3) / 4; bx++) {
					const uint8_t* b = s + ((size_t)by * ((w + 3) / 4) + bx) * (kind == 1 ? 8 : 16);
					if (kind == 1) color_block(b, px, w, w, h, bx * 4, by * 4, 1);
					else {
						color_block(b + 8, px, w, w, h, bx * 4, by * 4, 0);
						if (kind == 3) alpha_dxt3(b, px, w, w, h, bx * 4, by * 4);
						else alpha_dxt5(b, px, w, w, h, bx * 4, by * 4);
					}
				}
		} else {
			int rs = shift_of(rm), gs = shift_of(gm), bs = shift_of(bm), as = shift_of(am);
			for (size_t i = 0; i < (size_t)w * h; i++) {
				const uint8_t* p = s + i * (bpp / 8);
				uint32_t v = p[0] | (p[1] << 8) | (p[2] << 16) | (bpp == 32 ? ((uint32_t)p[3] << 24) : 0);
				px[4 * i + 0] = (uint8_t)((v & rm) >> rs);
				px[4 * i + 1] = (uint8_t)((v & gm) >> gs);
				px[4 * i + 2] = (uint8_t)((v & bm) >> bs);
				px[4 * i + 3] = am ? (uint8_t)((v & am) >> as) : 255;
			}
		}
		/* TGA, 32-bit BGRA, top-left origin (descriptor bit 5); rows written last first: the engine's flip */
		char name[1024];
		snprintf(name, sizeof(name), "%s.%d.tga", argv[2], written);
		FILE* o = fopen(name, "wb");
		if (!o) { fprintf(stderr, "cannot write %s\n", name); return 1; }
		uint8_t th[18] = { 0 };
		th[2] = 2; th[12] = (uint8_t)(w & 255); th[13] = (uint8_t)(w >> 8); th[14] = (uint8_t)(h & 255); th[15] = (uint8_t)(h >> 8);
		th[16] = 32; th[17] = 0x28;
		fwrite(th, 1, 18, o);
		uint8_t* row = (uint8_t*)malloc((size_t)w * 4);
		for (int y = h - 1; y >= 0; y--) {
			for (int x = 0; x < w; x++) {
				const uint8_t* p = px + 4 * ((size_t)y * w + x);
				row[4 * x + 0] = p[2]; row[4 * x + 1] = p[1]; row[4 * x + 2] = p[0]; row[4 * x + 3] = p[3];
			}
			fwrite(row, 1, (size_t)w * 4, o);
		}
		free(row);
		fclose(o);
		free(px);
		if (!written) { firstW = w; firstH = h; }
		written++;
		off += size;
	}
	printf("levels %d %d %d %s\n", written, firstW, firstH, kind == 1 ? "DXT1" : kind == 3 ? "DXT3" : kind == 5 ? "DXT5" : "RGBA");
	free(d);
	return written ? 0 : 1;
}
