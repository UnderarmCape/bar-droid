// BAR Droid: mobile versions of Beyond All Reason's S3O models (far fewer triangles, the same look), made on the laptop.
//
//   mobile_models build  --src <folder with objects3d/ and unittextures/> --out <folder> [options]
//   mobile_models render --a <model.s3o> [--b <mobile.s3o>] --tex <unittextures folder> --png <file> [--size N]
//
// Each model keeps BAR's piece tree exactly (names, order, offsets, texture names, header); only the pieces' vertices
// and triangles change, and every piece keeps its first two vertices at the front (the engine aims weapons and effects
// along a piece's vertex 0 -> 1). The engine branch loads these for drawing only (BarDroidModelOverrideDir): sizes,
// bounds and collision volumes stay those of BAR's own model.
//
// The cut: half-edge collapses (a vertex moved onto a neighbour, so every kept vertex is one of BAR's, with its own
// normal and texture coordinates) in the order of the least change of shape (Garland-Heckbert quadrics, open borders
// and texture seams kept straight by extra planes), each checked before it is made:
//  - the surface stays manifold, no triangle turns over (in space or on the texture), none turns far from where it
//    pointed in BAR's model;
//  - texture islands stay whole: corners that move along a seam take the matching vertex on the other end; a collapse
//    that would push one island over another (its texture coordinates carried on past its edge) is taken only where
//    the texture is the same colour on both;
//  - the new triangles are sampled (12 points each) against BAR's model: each point's nearest point on BAR's surface,
//    the distance to it (max --dist elmos), and the colour BAR's texture shows there against the colour the new
//    triangle shows (team-colour mask included; mean at most --color, few points far off).
// Pieces under --min-tris triangles are left as they are. Then meshoptimizer's vertex cache and fetch order.
//
// Build: build.bat (w64devkit's g++, meshoptimizer 0.23's vertex cache and fetch optimizers). README.md: the whole road.

#define _USE_MATH_DEFINES
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <numeric>
#include <queue>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "meshoptimizer.h"

namespace fs = std::filesystem;

// ------------------------------------------------------------------------------------------------ small maths
struct V3 {
	double x = 0, y = 0, z = 0;
	V3() = default;
	V3(double a, double b, double c) : x(a), y(b), z(c) {}
	V3 operator+(const V3& o) const { return {x + o.x, y + o.y, z + o.z}; }
	V3 operator-(const V3& o) const { return {x - o.x, y - o.y, z - o.z}; }
	V3 operator*(double s) const { return {x * s, y * s, z * s}; }
	double& operator[](int i) { return (&x)[i]; }
	double operator[](int i) const { return (&x)[i]; }
};
static double Dot(const V3& a, const V3& b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static V3 Cross(const V3& a, const V3& b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
static double Len(const V3& a) { return std::sqrt(Dot(a, a)); }
static V3 Norm(const V3& a) { const double l = Len(a); return l > 0 ? a * (1.0 / l) : V3(); }

struct Quadric {
	double a[10] = {0};   // xx xy xz xw yy yz yw zz zw ww
	void AddPlane(const V3& n, double d, double w) {
		const double v[4] = {n.x, n.y, n.z, d};
		int k = 0;
		for (int i = 0; i < 4; ++i)
			for (int j = i; j < 4; ++j)
				a[k++] += w * v[i] * v[j];
	}
	void Add(const Quadric& o) { for (int i = 0; i < 10; ++i) a[i] += o.a[i]; }
	double Eval(const V3& p) const {
		const double x = p.x, y = p.y, z = p.z;
		return a[0] * x * x + 2 * a[1] * x * y + 2 * a[2] * x * z + 2 * a[3] * x + a[4] * y * y + 2 * a[5] * y * z
			+ 2 * a[6] * y + a[7] * z * z + 2 * a[8] * z + a[9];
	}
};

// ------------------------------------------------------------------------------------------------ S3O files
struct S3OVertex { float p[3], n[3], uv[2]; };
struct S3OPiece {
	std::string name;
	float off[3] = {0, 0, 0};
	int primType = 0, vertexType = 0;
	std::vector<S3OVertex> verts;
	std::vector<int> idx;
	std::vector<int> children;   // piece numbers
	std::vector<int> lod;        // the coarse level's triangles (mobile files only; empty: none)
};
struct S3OModel {
	char magic[12];
	int version = 0;
	float radius = 0, height = 0, mid[3] = {0, 0, 0};
	std::string tex1, tex2;
	std::vector<S3OPiece> pieces;   // pieces[0] is the root, then depth first in the file's order
	uint64_t sourceHash = 0;        // FNV-1a 64 of the file's bytes (a mobile file: of BAR's file it was made from)
};

static uint64_t Fnv1a64(const uint8_t* d, size_t n)
{
	uint64_t h = 1469598103934665603ull;
	for (size_t i = 0; i < n; ++i) { h ^= d[i]; h *= 1099511628211ull; }
	return h;
}

static bool ReadFile(const fs::path& p, std::vector<uint8_t>& out)
{
	std::ifstream f(p, std::ios::binary);
	if (!f)
		return false;
	f.seekg(0, std::ios::end);
	out.resize(size_t(f.tellg()));
	f.seekg(0);
	f.read(reinterpret_cast<char*>(out.data()), out.size());
	return bool(f);
}

template<typename T> static bool Get(const std::vector<uint8_t>& b, size_t off, T& v)
{
	if (off + sizeof(T) > b.size())
		return false;
	memcpy(&v, &b[off], sizeof(T));
	return true;
}
static std::string GetStr(const std::vector<uint8_t>& b, int off)
{
	if (off <= 0 || size_t(off) >= b.size())
		return "";
	size_t e = off;
	while (e < b.size() && b[e])
		++e;
	return std::string(reinterpret_cast<const char*>(&b[off]), e - off);
}

static bool LoadPiece(const std::vector<uint8_t>& b, int off, S3OModel& m, int depth, std::string& err)
{
	if (depth > 64) { err = "piece tree too deep"; return false; }
	int f[10]; float o[3];
	for (int i = 0; i < 10; ++i)
		if (!Get(b, off + 4 * i, f[i])) { err = "piece header past the end"; return false; }
	for (int i = 0; i < 3; ++i)
		Get(b, off + 40 + 4 * i, o[i]);
	const int me = int(m.pieces.size());
	m.pieces.emplace_back();
	{
		S3OPiece& p = m.pieces.back();
		p.name = GetStr(b, f[0]);
		p.off[0] = o[0]; p.off[1] = o[1]; p.off[2] = o[2];
		p.vertexType = f[5];
		p.primType = f[6];
		if (f[3] > 0) {
			if (size_t(f[4]) + size_t(f[3]) * 32 > b.size()) { err = "vertices past the end"; return false; }
			p.verts.resize(f[3]);
			memcpy(p.verts.data(), &b[f[4]], size_t(f[3]) * 32);
		}
		if (f[7] > 0) {
			if (size_t(f[8]) + size_t(f[7]) * 4 > b.size()) { err = "indices past the end"; return false; }
			p.idx.resize(f[7]);
			memcpy(p.idx.data(), &b[f[8]], size_t(f[7]) * 4);
		}
		int n = 0;   // (a mobile file's coarse level: "BDL1", count, indices)
		if (f[9] > 0 && size_t(f[9]) + 8 <= b.size() && !memcmp(&b[f[9]], "BDL1", 4) && Get(b, f[9] + 4, n) && n > 0 &&
			size_t(f[9]) + 8 + size_t(n) * 4 <= b.size()) {
			p.lod.resize(n);
			memcpy(p.lod.data(), &b[f[9] + 8], size_t(n) * 4);
		}
	}
	for (int c = 0; c < f[1]; ++c) {
		int co;
		if (!Get(b, f[2] + 4 * c, co)) { err = "child table past the end"; return false; }
		const int child = int(m.pieces.size());
		m.pieces[me].children.push_back(child);
		if (!LoadPiece(b, co, m, depth + 1, err))
			return false;
	}
	return true;
}

static bool LoadS3O(const fs::path& path, S3OModel& m, std::string& err)
{
	std::vector<uint8_t> b;
	if (!ReadFile(path, b)) { err = "cannot read"; return false; }
	if (b.size() < 52) { err = "short header"; return false; }
	m.sourceHash = Fnv1a64(b.data(), b.size());
	memcpy(m.magic, b.data(), 12);
	int root, t1, t2;
	Get(b, 12, m.version); Get(b, 16, m.radius); Get(b, 20, m.height);
	Get(b, 24, m.mid[0]); Get(b, 28, m.mid[1]); Get(b, 32, m.mid[2]);
	Get(b, 36, root); Get(b, 44, t1); Get(b, 48, t2);
	m.tex1 = GetStr(b, t1);
	m.tex2 = GetStr(b, t2);
	return LoadPiece(b, root, m, 0, err);
}

struct Writer {
	std::vector<uint8_t> b;
	size_t Pos() const { return b.size(); }
	template<typename T> void Put(const T& v) { const size_t p = b.size(); b.resize(p + sizeof(T)); memcpy(&b[p], &v, sizeof(T)); }
	template<typename T> void PutAt(size_t at, const T& v) { memcpy(&b[at], &v, sizeof(T)); }
	void PutBytes(const void* d, size_t n) { const size_t p = b.size(); b.resize(p + n); if (n) memcpy(&b[p], d, n); }
	int PutStr(const std::string& s) { const int at = int(b.size()); PutBytes(s.c_str(), s.size() + 1); return at; }
};

static int WritePiece(Writer& w, const S3OModel& m, int pi)
{
	const S3OPiece& p = m.pieces[pi];
	const int at = int(w.Pos());
	w.b.resize(w.b.size() + 52);
	const int nameAt = w.PutStr(p.name);
	const int childAt = int(w.Pos());
	w.b.resize(w.b.size() + 4 * p.children.size());
	const int vertAt = int(w.Pos());
	w.PutBytes(p.verts.data(), p.verts.size() * 32);
	const int idxAt = int(w.Pos());
	w.PutBytes(p.idx.data(), p.idx.size() * 4);
	// BAR Droid: the coarse level in the piece's (unused) collision data: "BDL1", count, triangles' indices
	int lodAt = 0;
	if (!p.lod.empty()) {
		lodAt = int(w.Pos());
		w.PutBytes("BDL1", 4);
		w.Put(int(p.lod.size()));
		w.PutBytes(p.lod.data(), p.lod.size() * 4);
	}
	const int f[10] = {nameAt, int(p.children.size()), p.children.empty() ? 0 : childAt, int(p.verts.size()),
		p.verts.empty() ? 0 : vertAt, p.vertexType, p.primType, int(p.idx.size()), p.idx.empty() ? 0 : idxAt, lodAt};
	for (int i = 0; i < 10; ++i)
		w.PutAt(at + 4 * i, f[i]);
	for (int i = 0; i < 3; ++i)
		w.PutAt(at + 40 + 4 * i, p.off[i]);
	for (size_t c = 0; c < p.children.size(); ++c) {
		const int co = WritePiece(w, m, p.children[c]);
		w.PutAt(childAt + 4 * c, co);
	}
	return at;
}

static bool SaveS3O(const fs::path& path, const S3OModel& m)
{
	Writer w;
	w.PutBytes(m.magic, 12);
	w.Put(m.version); w.Put(m.radius); w.Put(m.height); w.Put(m.mid[0]); w.Put(m.mid[1]); w.Put(m.mid[2]);
	w.Put(int(0)); w.Put(int(0)); w.Put(int(0)); w.Put(int(0));   // root, collision data, textures: below
	const int root = WritePiece(w, m, 0);
	const int t1 = m.tex1.empty() ? 0 : w.PutStr(m.tex1);
	const int t2 = m.tex2.empty() ? 0 : w.PutStr(m.tex2);
	// BAR Droid: the mark of a mobile file in the header's (unused) collision data: "BDMOBIL1", BAR's file's hash,
	// flags (1: pieces may have a coarse level), 0
	const int mark = int(w.Pos());
	w.PutBytes("BDMOBIL1", 8);
	w.Put(m.sourceHash);
	w.Put(uint32_t(1)); w.Put(uint32_t(0));
	w.PutAt(36, root); w.PutAt(40, mark); w.PutAt(44, t1); w.PutAt(48, t2);
	fs::create_directories(path.parent_path());
	std::ofstream f(path, std::ios::binary);
	f.write(reinterpret_cast<const char*>(w.b.data()), w.b.size());
	return bool(f);
}

// The engine's triangles of a piece (S3OParser.cpp Trianglize; strips without flipping, as the engine draws them)
static std::vector<int> Triangles(const S3OPiece& p)
{
	std::vector<int> t;
	if (p.primType == 0) {
		t.assign(p.idx.begin(), p.idx.end() - (p.idx.size() % 3));
	} else if (p.primType == 1) {
		for (size_t i = 0; i + 2 < p.idx.size(); ++i) {
			if (p.idx[i] == -1 || p.idx[i + 1] == -1 || p.idx[i + 2] == -1)
				continue;
			t.insert(t.end(), {p.idx[i], p.idx[i + 1], p.idx[i + 2]});
		}
	} else if (p.primType == 2) {
		if (p.idx.size() % 4 == 0)
			for (size_t i = 0; i < p.idx.size(); i += 4)
				t.insert(t.end(), {p.idx[i], p.idx[i + 1], p.idx[i + 2], p.idx[i], p.idx[i + 2], p.idx[i + 3]});
	}
	return t;
}

// ------------------------------------------------------------------------------------------------ textures
struct Texture {
	int w = 0, h = 0;
	std::vector<uint8_t> rgba;   // rows top down, as stored in the file
	// S3O texture coordinates: v = 0 is the image's bottom row (the engine flips DDS images on load)
	void Sample(double u, double v, double out[4]) const {
		double x = u * w - 0.5, y = (1.0 - v) * h - 0.5;
		x -= std::floor(x / w) * w; y -= std::floor(y / h) * h;
		const int x0 = int(x) % w, y0 = int(y) % h, x1 = (x0 + 1) % w, y1 = (y0 + 1) % h;
		const double fx = x - std::floor(x), fy = y - std::floor(y);
		const uint8_t* a = &rgba[4 * (size_t(y0) * w + x0)];
		const uint8_t* b = &rgba[4 * (size_t(y0) * w + x1)];
		const uint8_t* c = &rgba[4 * (size_t(y1) * w + x0)];
		const uint8_t* d = &rgba[4 * (size_t(y1) * w + x1)];
		for (int i = 0; i < 4; ++i)
			out[i] = ((a[i] * (1 - fx) + b[i] * fx) * (1 - fy) + (c[i] * (1 - fx) + d[i] * fx) * fy) / 255.0;
	}
};

static void Rgb565(uint16_t c, int o[3]) { o[0] = ((c >> 11) & 31) * 255 / 31; o[1] = ((c >> 5) & 63) * 255 / 63; o[2] = (c & 31) * 255 / 31; }

static void DecodeColorBlock(const uint8_t* s, uint8_t out[16][4], bool dxt1)
{
	const uint16_t c0 = s[0] | (s[1] << 8), c1 = s[2] | (s[3] << 8);
	int p[4][4];
	Rgb565(c0, p[0]); Rgb565(c1, p[1]);
	p[0][3] = p[1][3] = 255;
	if (c0 > c1 || !dxt1) {
		for (int i = 0; i < 3; ++i) { p[2][i] = (2 * p[0][i] + p[1][i]) / 3; p[3][i] = (p[0][i] + 2 * p[1][i]) / 3; }
		p[2][3] = p[3][3] = 255;
	} else {
		for (int i = 0; i < 3; ++i) { p[2][i] = (p[0][i] + p[1][i]) / 2; p[3][i] = 0; }
		p[2][3] = 255; p[3][3] = 0;
	}
	const uint32_t bits = s[4] | (s[5] << 8) | (s[6] << 16) | (uint32_t(s[7]) << 24);
	for (int i = 0; i < 16; ++i) {
		const int k = (bits >> (2 * i)) & 3;
		for (int j = 0; j < 4; ++j)
			out[i][j] = uint8_t(p[k][j]);
	}
}

static bool LoadDDS(const std::vector<uint8_t>& b, int maxSize, Texture& t)
{
	if (b.size() < 128 || memcmp(b.data(), "DDS ", 4) != 0)
		return false;
	uint32_t h, w, mips, pfFlags, bits, rmask, gmask, bmask, amask;
	char cc[5] = {0};
	Get(b, 12, h); Get(b, 16, w); Get(b, 28, mips); Get(b, 80, pfFlags); memcpy(cc, &b[84], 4);
	Get(b, 88, bits); Get(b, 92, rmask); Get(b, 96, gmask); Get(b, 100, bmask); Get(b, 104, amask);
	if (mips == 0)
		mips = 1;
	size_t off = 128;
	int fmt = 0;   // 1 DXT1, 3 DXT3, 5 DXT5, 32/24 uncompressed
	if (pfFlags & 4) {
		if (!strcmp(cc, "DXT1")) fmt = 1;
		else if (!strcmp(cc, "DXT3")) fmt = 3;
		else if (!strcmp(cc, "DXT5")) fmt = 5;
		else if (!strcmp(cc, "DX10")) {
			uint32_t dxgi; Get(b, 128, dxgi); off += 20;
			if (dxgi == 71 || dxgi == 72) fmt = 1; else if (dxgi == 74 || dxgi == 75) fmt = 3; else if (dxgi == 77 || dxgi == 78) fmt = 5;
		}
	} else if (bits == 32 || bits == 24) {
		fmt = int(bits);
	}
	if (!fmt)
		return false;
	auto levelSize = [&](uint32_t lw, uint32_t lh) -> size_t {
		if (fmt == 1) return size_t(std::max(1u, (lw + 3) / 4)) * std::max(1u, (lh + 3) / 4) * 8;
		if (fmt == 3 || fmt == 5) return size_t(std::max(1u, (lw + 3) / 4)) * std::max(1u, (lh + 3) / 4) * 16;
		return size_t(lw) * lh * (fmt / 8);
	};
	uint32_t lw = w, lh = h;
	for (uint32_t m = 0; m + 1 < mips && std::max(lw, lh) > uint32_t(maxSize); ++m) {
		off += levelSize(lw, lh);
		lw = std::max(1u, lw / 2); lh = std::max(1u, lh / 2);
	}
	if (off + levelSize(lw, lh) > b.size())
		return false;
	t.w = int(lw); t.h = int(lh);
	t.rgba.assign(size_t(lw) * lh * 4, 255);
	const uint8_t* s = &b[off];
	if (fmt == 32 || fmt == 24) {
		auto shiftOf = [](uint32_t m) { int s = 0; if (!m) return -1; while (!(m & 1)) { m >>= 1; ++s; } return s; };
		const int rs = shiftOf(rmask), gs = shiftOf(gmask), bs = shiftOf(bmask), as = shiftOf(amask);
		for (size_t i = 0; i < size_t(lw) * lh; ++i) {
			uint32_t px = 0;
			memcpy(&px, s + i * (fmt / 8), fmt / 8);
			t.rgba[4 * i + 0] = uint8_t(rs >= 0 ? (px >> rs) & 255 : 0);
			t.rgba[4 * i + 1] = uint8_t(gs >= 0 ? (px >> gs) & 255 : 0);
			t.rgba[4 * i + 2] = uint8_t(bs >= 0 ? (px >> bs) & 255 : 0);
			t.rgba[4 * i + 3] = uint8_t(as >= 0 ? (px >> as) & 255 : 255);
		}
		return true;
	}
	const uint32_t bw = std::max(1u, (lw + 3) / 4), bh = std::max(1u, (lh + 3) / 4);
	const int bs = (fmt == 1) ? 8 : 16;
	for (uint32_t by = 0; by < bh; ++by) {
		for (uint32_t bx = 0; bx < bw; ++bx) {
			const uint8_t* blk = s + (size_t(by) * bw + bx) * bs;
			uint8_t px[16][4];
			DecodeColorBlock(blk + (fmt == 1 ? 0 : 8), px, fmt == 1);
			if (fmt == 3) {
				for (int i = 0; i < 16; ++i)
					px[i][3] = uint8_t(((blk[i / 2] >> (4 * (i & 1))) & 15) * 17);
			} else if (fmt == 5) {
				int a[8]; a[0] = blk[0]; a[1] = blk[1];
				if (a[0] > a[1]) for (int i = 1; i < 7; ++i) a[i + 1] = ((7 - i) * a[0] + i * a[1]) / 7;
				else { for (int i = 1; i < 5; ++i) a[i + 1] = ((5 - i) * a[0] + i * a[1]) / 5; a[6] = 0; a[7] = 255; }
				uint64_t abits = 0;
				for (int i = 0; i < 6; ++i) abits |= uint64_t(blk[2 + i]) << (8 * i);
				for (int i = 0; i < 16; ++i)
					px[i][3] = uint8_t(a[(abits >> (3 * i)) & 7]);
			}
			for (int i = 0; i < 16; ++i) {
				const uint32_t x = bx * 4 + (i & 3), y = by * 4 + (i >> 2);
				if (x < lw && y < lh)
					memcpy(&t.rgba[4 * (size_t(y) * lw + x)], px[i], 4);
			}
		}
	}
	return true;
}

static bool LoadTGA(const std::vector<uint8_t>& b, Texture& t)
{
	if (b.size() < 18)
		return false;
	const int idLen = b[0], type = b[2], w = b[12] | (b[13] << 8), h = b[14] | (b[15] << 8), bpp = b[16], desc = b[17];
	if ((type != 2 && type != 10) || (bpp != 24 && bpp != 32) || w <= 0 || h <= 0)
		return false;
	const int n = bpp / 8;
	size_t s = 18 + idLen;
	t.w = w; t.h = h;
	t.rgba.assign(size_t(w) * h * 4, 255);
	std::vector<uint8_t> px(size_t(w) * h * n);
	if (type == 2) {
		if (s + px.size() > b.size()) return false;
		memcpy(px.data(), &b[s], px.size());
	} else {
		size_t o = 0;
		while (o < px.size() && s < b.size()) {
			const int hd = b[s++], cnt = (hd & 127) + 1;
			if (hd & 128) { for (int i = 0; i < cnt && o < px.size(); ++i, o += n) memcpy(&px[o], &b[s], n); s += n; }
			else { for (int i = 0; i < cnt && o < px.size(); ++i, o += n, s += n) memcpy(&px[o], &b[s], n); }
		}
	}
	const bool top = (desc & 32) != 0;
	for (int y = 0; y < h; ++y)
		for (int x = 0; x < w; ++x) {
			const uint8_t* p = &px[(size_t(top ? y : h - 1 - y) * w + x) * n];
			uint8_t* d = &t.rgba[4 * (size_t(y) * w + x)];
			d[0] = p[2]; d[1] = p[1]; d[2] = p[0]; d[3] = (n == 4) ? p[3] : 255;
		}
	return true;
}

struct TextureCache {
	fs::path dir;
	int maxSize = 1024;
	std::mutex mtx;
	std::map<std::string, std::shared_ptr<Texture>> cache;
	std::map<std::string, fs::path> files;   // lower-case name -> file
	void Index() {
		if (dir.empty() || !fs::exists(dir))
			return;
		for (auto& e : fs::recursive_directory_iterator(dir)) {
			if (!e.is_regular_file()) continue;
			std::string rel = fs::relative(e.path(), dir).generic_string();
			std::transform(rel.begin(), rel.end(), rel.begin(), ::tolower);
			files[rel] = e.path();
		}
	}
	std::shared_ptr<Texture> Get(std::string name) {
		std::transform(name.begin(), name.end(), name.begin(), ::tolower);
		std::lock_guard<std::mutex> lk(mtx);
		auto it = cache.find(name);
		if (it != cache.end())
			return it->second;
		std::shared_ptr<Texture> t;
		auto f = files.find(name);
		if (f != files.end()) {
			std::vector<uint8_t> b;
			auto tex = std::make_shared<Texture>();
			if (ReadFile(f->second, b) && (LoadDDS(b, maxSize, *tex) || LoadTGA(b, *tex)))
				t = tex;
		}
		cache[name] = t;
		return t;
	}
};

// ------------------------------------------------------------------------------------------------ nearest point
struct Tri { V3 p[3]; double uv[3][2]; V3 n; };

static V3 ClosestOnTri(const V3& p, const V3& a, const V3& b, const V3& c, double& u, double& v, double& w)
{
	// Ericson, Real-Time Collision Detection 5.1.5
	const V3 ab = b - a, ac = c - a, ap = p - a;
	const double d1 = Dot(ab, ap), d2 = Dot(ac, ap);
	if (d1 <= 0 && d2 <= 0) { u = 1; v = 0; w = 0; return a; }
	const V3 bp = p - b;
	const double d3 = Dot(ab, bp), d4 = Dot(ac, bp);
	if (d3 >= 0 && d4 <= d3) { u = 0; v = 1; w = 0; return b; }
	const double vc = d1 * d4 - d3 * d2;
	if (vc <= 0 && d1 >= 0 && d3 <= 0) { const double t = d1 / (d1 - d3); u = 1 - t; v = t; w = 0; return a + ab * t; }
	const V3 cp = p - c;
	const double d5 = Dot(ab, cp), d6 = Dot(ac, cp);
	if (d6 >= 0 && d5 <= d6) { u = 0; v = 0; w = 1; return c; }
	const double vb = d5 * d2 - d1 * d6;
	if (vb <= 0 && d2 >= 0 && d6 <= 0) { const double t = d2 / (d2 - d6); u = 1 - t; v = 0; w = t; return a + ac * t; }
	const double va = d3 * d6 - d5 * d4;
	if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) {
		const double t = (d4 - d3) / ((d4 - d3) + (d5 - d6)); u = 0; v = 1 - t; w = t; return b + (c - b) * t;
	}
	const double den = 1.0 / (va + vb + vc);
	v = vb * den; w = vc * den; u = 1 - v - w;
	return a + ab * v + ac * w;
}

struct BVH {
	struct Node { V3 lo, hi; int left = -1, right = -1, first = 0, count = 0; };
	std::vector<Tri> tris;
	std::vector<int> order;
	std::vector<Node> nodes;
	void Build() {
		order.resize(tris.size());
		std::iota(order.begin(), order.end(), 0);
		nodes.clear();
		nodes.reserve(tris.size() * 2 + 1);
		if (!tris.empty())
			BuildNode(0, int(tris.size()));
	}
	int BuildNode(int first, int count) {
		const int id = int(nodes.size());
		nodes.emplace_back();
		V3 lo(1e30, 1e30, 1e30), hi(-1e30, -1e30, -1e30);
		for (int i = first; i < first + count; ++i)
			for (const V3& p : tris[order[i]].p)
				for (int k = 0; k < 3; ++k) { lo[k] = std::min(lo[k], p[k]); hi[k] = std::max(hi[k], p[k]); }
		nodes[id].lo = lo; nodes[id].hi = hi;
		if (count <= 4) { nodes[id].first = first; nodes[id].count = count; return id; }
		int axis = 0;
		for (int k = 1; k < 3; ++k) if (hi[k] - lo[k] > hi[axis] - lo[axis]) axis = k;
		auto cen = [&](int t) { const Tri& r = tris[t]; return r.p[0][axis] + r.p[1][axis] + r.p[2][axis]; };
		std::nth_element(order.begin() + first, order.begin() + first + count / 2, order.begin() + first + count,
			[&](int a, int b) { return cen(a) < cen(b); });
		const int l = BuildNode(first, count / 2);
		const int r = BuildNode(first + count / 2, count - count / 2);
		nodes[id].left = l; nodes[id].right = r;
		return id;
	}
	static double BoxDist2(const Node& n, const V3& p) {
		double d = 0;
		for (int k = 0; k < 3; ++k) {
			const double v = p[k] < n.lo[k] ? n.lo[k] - p[k] : (p[k] > n.hi[k] ? p[k] - n.hi[k] : 0);
			d += v * v;
		}
		return d;
	}
	// nearest point on a triangle facing the same way as n (not BAR's back side of a thin plate); -1: none
	int Nearest(const V3& p, const V3& n, double& bestD2, double bary[3]) const {
		int best = -1;
		bestD2 = 1e30;
		if (nodes.empty()) return -1;
		int stack[128]; int sp = 0;
		stack[sp++] = 0;
		while (sp) {
			const Node& nd = nodes[stack[--sp]];
			if (BoxDist2(nd, p) >= bestD2) continue;
			if (nd.left < 0) {
				for (int i = nd.first; i < nd.first + nd.count; ++i) {
					const Tri& t = tris[order[i]];
					if (Dot(t.n, n) < -0.2) continue;
					double u, v, w;
					const V3 q = ClosestOnTri(p, t.p[0], t.p[1], t.p[2], u, v, w);
					const V3 d = q - p;
					const double d2 = Dot(d, d);
					if (d2 < bestD2) { bestD2 = d2; best = order[i]; bary[0] = u; bary[1] = v; bary[2] = w; }
				}
			} else if (sp + 2 <= 128) {
				const double dl = BoxDist2(nodes[nd.left], p), dr = BoxDist2(nodes[nd.right], p);
				if (dl < dr) { stack[sp++] = nd.right; stack[sp++] = nd.left; }
				else { stack[sp++] = nd.left; stack[sp++] = nd.right; }
			}
		}
		return best;
	}
};

// ------------------------------------------------------------------------------------------------ the cut
struct Params {
	double maxDist = 1.5;           // elmos: the farthest a new surface point may be from BAR's
	double relDist = 0.03;          // and at most this share of the model's radius (small models: small changes)
	double maxColor = 0.04;         // mean colour difference of the new triangles (0..1 RGB, + team mask)
	double farColor = 0.15;         // a sample point this far off in colour counts as off
	double farShare = 0.05;         // at most this share of the sample points off
	double lineContrast = 0.08;     // a seam whose two sides differ more than this in colour is an outline to keep
	double lineDist = 0.5;          // share of maxDist BAR's seams and borders may move (texture outlines keep their shape)
	double maxTurn = 50.0;          // degrees a triangle may turn from where it pointed in BAR's model
	double minShare = 0.0;          // never under this share of a piece's triangles
	int minTris = 12;               // pieces with fewer triangles are left alone
	int hiddenDirs = 320, hiddenRes = 320;
	bool lod = true;                // the coarse level for units small on the screen, with its own limits:
	double lodDist = 4.0, lodRelDist = 0.07, lodColor = 0.08, lodFarColor = 0.3, lodLineDist = 1.0;
	int lodQaSize = 64;   // the hidden-triangle search: directions, pixels (0 directions: off)
	bool cross = true;              // islands may grow over each other where the texture is the same
	double crossCost = 2.0;         // and those collapses cost this much more
	double borderWeight = 8.0, seamWeight = 1.5;
};

struct Wedge { int pid; float n[3]; float uv[2]; };
struct Face { int p[3], w[3]; bool alive = true; V3 n0; };   // n0: BAR's own normal of the face
struct PosV {
	V3 x; Quadric q, qc; double area = 0; bool alive = true; bool locked = false; int version = 0; std::vector<int> faces;
	std::vector<V3> kept;   // BAR's points merged into this one: each must stay within reach of the new surface
	std::vector<V3> keptLine;   // those on BAR's texture seams and open borders: within reach of the new ones
};

struct Cand { float cost; int a, b, va, vb; bool operator<(const Cand& o) const { return cost > o.cost; } };

struct PieceStats { size_t trisIn = 0, trisOut = 0, vertsIn = 0, vertsOut = 0, collapses = 0, crossings = 0, rejTex = 0, rejGeo = 0; };

class Simplifier {
public:
	Simplifier(const Params& P, const Texture* tex) : P(P), tex(tex) {}
	bool scanBlockers = false;

	// in: the piece's vertices and triangles; out: new vertices (BAR's vertex 0 and 1 first) and triangles, and with
	// lod (the coarser level's limits) a second, coarser list of triangles over the same vertices (for units small on
	// the screen; empty: none coarser)
	bool Run(const std::vector<S3OVertex>& vin, const std::vector<int>& tin, const Params* lod, std::vector<S3OVertex>& vout,
		std::vector<int>& tout, std::vector<int>& tlod, PieceStats& st)
	{
		st.trisIn = tin.size() / 3;
		st.vertsIn = vin.size();
		if (!Setup(vin, tin))
			return false;
		Simplify(st);
		if (scanBlockers) ScanBlockers(st);
		std::vector<std::array<int, 3>> lod0 = Snapshot(), lod1;
		if (lod) {
			P = *lod;
			Simplify(st);
			lod1 = Snapshot();
		}
		Output(vin, lod0, lod1, vout, tout, tlod);
		st.trisOut = tout.size() / 3;
		st.vertsOut = vout.size();
		return true;
	}

private:
	Params P;

	void Simplify(PieceStats& st)
	{
		std::priority_queue<Cand>().swap(queue);
		for (int a = 0; a < int(pv.size()); ++a)
			PushAll(a);
		while (!queue.empty()) {
			const Cand c = queue.top();
			queue.pop();
			if (!pv[c.a].alive || !pv[c.b].alive || pv[c.a].version != c.va || pv[c.b].version != c.vb)
				continue;
			Plan plan;
			if (!Prepare(c.a, c.b, plan))
				continue;
			if (!Check(plan, st))
				continue;
			Apply(plan);
			++st.collapses;
			st.crossings += plan.crossing;
		}
		++reasons[19];
	}

	std::vector<std::array<int, 3>> Snapshot() const
	{
		std::vector<std::array<int, 3>> out;
		for (const Face& f : faces)
			if (f.alive) out.push_back({f.w[0], f.w[1], f.w[2]});
		return out;
	}
	const Texture* tex;
	std::vector<PosV> pv;
	std::vector<Wedge> wedges;
	std::vector<Face> faces;
	BVH bvh;
	std::priority_queue<Cand> queue;
public:
	long reasons[24] = {0};   // why collapses were not taken (Prepare 0-10, Check 11-17, stop 18-19)
	long blockers[24] = {0};  // at the end: what stops each edge left (20: too costly, 21: would pass)
	bool blockerScan = false;
private:
	bool Rej(int r) { ++(blockerScan ? blockers : reasons)[r]; return false; }
	void ScanBlockers(PieceStats& st) {
		blockerScan = true;
		std::vector<int> nb;
		for (int a = 0; a < int(pv.size()); ++a) {
			if (!pv[a].alive) continue;
			Neighbours(a, nb);
			for (int b : nb) {
				Plan plan;
				if (!Prepare(a, b, plan)) continue;
				if (!Check(plan, st)) continue;
				++blockers[21];
			}
		}
		blockerScan = false;
	}

	size_t AliveFaces() const { size_t n = 0; for (const Face& f : faces) n += f.alive; return n; }

	// positions within 1e-4 elmo are one point of the surface
	static std::tuple<int64_t, int64_t, int64_t> Key3(float x, float y, float z) {
		auto q = [](float v) { return int64_t(std::llround(double(v) * 1e4)); };
		return {q(x), q(y), q(z)};
	}

	bool Setup(const std::vector<S3OVertex>& vin, const std::vector<int>& tin)
	{
		std::map<std::tuple<int64_t, int64_t, int64_t>, int> posKey;
		std::vector<int> vPid(vin.size()), vWid(vin.size());
		std::map<std::tuple<int, float, float, float, float, float>, int> wedgeKey;
		for (size_t i = 0; i < vin.size(); ++i) {
			const S3OVertex& v = vin[i];
			const auto k = Key3(v.p[0], v.p[1], v.p[2]);
			auto it = posKey.find(k);
			int pid;
			if (it == posKey.end()) {
				pid = int(pv.size());
				posKey[k] = pid;
				pv.emplace_back();
				pv.back().x = V3(v.p[0], v.p[1], v.p[2]);
				pv.back().kept.push_back(pv.back().x);
			} else {
				pid = it->second;
			}
			vPid[i] = pid;
			const auto wk = std::make_tuple(pid, v.n[0], v.n[1], v.n[2], v.uv[0], v.uv[1]);
			auto wi = wedgeKey.find(wk);
			if (wi == wedgeKey.end()) {
				wedgeKey[wk] = int(wedges.size());
				Wedge w; w.pid = pid;
				memcpy(w.n, v.n, sizeof(w.n)); memcpy(w.uv, v.uv, sizeof(w.uv));
				wedges.push_back(w);
				vWid[i] = int(wedges.size()) - 1;
			} else {
				vWid[i] = wi->second;
			}
		}
		for (size_t t = 0; t + 2 < tin.size(); t += 3) {
			Face f;
			bool ok = true;
			for (int k = 0; k < 3; ++k) {
				const int vi = tin[t + k];
				if (vi < 0 || size_t(vi) >= vin.size()) { ok = false; break; }
				f.p[k] = vPid[vi]; f.w[k] = vWid[vi];
			}
			if (!ok) return false;   // (an index past the vertices: the piece is left as it is)
			if (f.p[0] == f.p[1] || f.p[1] == f.p[2] || f.p[0] == f.p[2])
				continue;            // (no area: never drawn)
			f.n0 = Cross(pv[f.p[1]].x - pv[f.p[0]].x, pv[f.p[2]].x - pv[f.p[0]].x);
			faces.push_back(f);
		}
		if (faces.empty())
			return false;
		// drop exact duplicate faces (same three corners): they draw the same pixels twice
		{
			std::map<std::array<int, 3>, int> seen;
			for (Face& f : faces) {
				std::array<int, 3> k = {f.w[0], f.w[1], f.w[2]};
				const int m = int(std::min_element(k.begin(), k.end()) - k.begin());
				std::rotate(k.begin(), k.begin() + m, k.end());
				if (seen.count(k)) f.alive = false; else seen[k] = 1;
			}
		}
		for (int fi = 0; fi < int(faces.size()); ++fi)
			if (faces[fi].alive)
				for (int k = 0; k < 3; ++k)
					pv[faces[fi].p[k]].faces.push_back(fi);
		// quadrics: each face's plane (by area), and planes along open borders, seams and hard edges
		std::map<std::pair<int, int>, std::vector<std::pair<int, int>>> edges;   // (pid lo, hi) -> (face, corner)
		for (int fi = 0; fi < int(faces.size()); ++fi) {
			const Face& f = faces[fi];
			if (!f.alive) continue;
			const double area2 = Len(f.n0);
			if (area2 > 1e-12) {
				const V3 n = f.n0 * (1.0 / area2);
				const double d = -Dot(n, pv[f.p[0]].x);
				for (int k = 0; k < 3; ++k) {
					pv[f.p[k]].q.AddPlane(n, d, area2 * 0.5);
					pv[f.p[k]].area += area2 * 0.5 / 3.0;
				}
			}
			for (int k = 0; k < 3; ++k) {
				const int a = f.p[k], b = f.p[(k + 1) % 3];
				edges[{std::min(a, b), std::max(a, b)}].push_back({fi, k});
			}
		}
		for (auto& [e, list] : edges) {
			bool constrain = false, visible = true;
			double weight = 0;
			if (list.size() == 1) { constrain = true; weight = P.borderWeight; }
			else if (list.size() > 2) { pv[e.first].locked = pv[e.second].locked = true; continue; }
			else {
				const Face& f = faces[list[0].first];
				const Face& g = faces[list[1].first];
				auto wedgeAt = [](const Face& h, int pid) { for (int k = 0; k < 3; ++k) if (h.p[k] == pid) return h.w[k]; return -1; };
				if (wedgeAt(f, e.first) != wedgeAt(g, e.first) || wedgeAt(f, e.second) != wedgeAt(g, e.second)) {
					constrain = true; weight = P.seamWeight;
					// a seam is an outline to keep where the texture differs across it (a panel's edge, the team
					// colour's); where both sides show the same colour it may move like any other edge
					if (tex) {
						double contrast = 0;
						for (double t : {0.15, 0.5, 0.85}) {
							double col[2][4];
							for (int side = 0; side < 2; ++side) {
								const Face& h = side ? g : f;
								double uv[2] = {0, 0};
								for (int k = 0; k < 3; ++k) {
									const double wgt = h.p[k] == e.first ? 0.92 * (1 - t) : (h.p[k] == e.second ? 0.92 * t : 0.08);
									uv[0] += wgt * wedges[h.w[k]].uv[0]; uv[1] += wgt * wedges[h.w[k]].uv[1];
								}
								tex->Sample(uv[0], uv[1], col[side]);
							}
							contrast = std::max(contrast, (std::fabs(col[0][0] - col[1][0]) + std::fabs(col[0][1] - col[1][1]) +
								std::fabs(col[0][2] - col[1][2])) / 3.0 + std::fabs(col[0][3] - col[1][3]));
						}
						visible = contrast > P.lineContrast;
					}
				}
			}
			if (!constrain) continue;
			for (int x : {e.first, e.second})
				if (visible && pv[x].keptLine.empty()) pv[x].keptLine.push_back(pv[x].x);
			for (auto& [fi, k] : list) {
				const Face& f = faces[fi];
				const V3 pa = pv[f.p[k]].x, pb = pv[f.p[(k + 1) % 3]].x;
				const V3 dir = pb - pa;
				const V3 n = Norm(Cross(dir, Norm(f.n0)));
				if (Len(n) < 0.5) continue;
				const double len2 = Dot(dir, dir);
				pv[e.first].qc.AddPlane(n, -Dot(n, pa), weight * len2);
				pv[e.second].qc.AddPlane(n, -Dot(n, pa), weight * len2);
			}
		}
		// BAR's surface, for the checks
		bvh.tris.clear();
		for (const Face& f : faces) {
			if (!f.alive) continue;
			Tri t;
			for (int k = 0; k < 3; ++k) {
				t.p[k] = pv[f.p[k]].x;
				t.uv[k][0] = wedges[f.w[k]].uv[0]; t.uv[k][1] = wedges[f.w[k]].uv[1];
			}
			t.n = Norm(f.n0);
			bvh.tris.push_back(t);
		}
		bvh.Build();
		return true;
	}

	struct Plan {
		bool ok = false;
		int a = -1, b = -1;
		double cost = 0;
		bool crossing = false;
		std::vector<int> removed, moved;
		std::vector<int> newWedge;          // per moved face: the wedge its corner at a takes
		std::vector<Wedge> created;         // wedges made for islands that grow over others (newWedge < 0: -1 - index)
	};

	int CornerOf(const Face& f, int pid) const { for (int k = 0; k < 3; ++k) if (f.p[k] == pid) return k; return -1; }

	void Neighbours(int a, std::vector<int>& out) const {
		out.clear();
		for (int fi : pv[a].faces) {
			const Face& f = faces[fi];
			if (!f.alive) continue;
			for (int k = 0; k < 3; ++k) if (f.p[k] != a) out.push_back(f.p[k]);
		}
		std::sort(out.begin(), out.end());
		out.erase(std::unique(out.begin(), out.end()), out.end());
	}

	// the topology of a -> b and where each moved corner goes; cost from the quadrics
	bool Prepare(int a, int b, Plan& plan)
	{
		plan = Plan();
		plan.a = a; plan.b = b;
		if (pv[a].locked || a == b) return Rej(0);
		std::vector<int> fa;
		for (int fi : pv[a].faces) if (faces[fi].alive) fa.push_back(fi);
		for (int fi : fa) (CornerOf(faces[fi], b) >= 0 ? plan.removed : plan.moved).push_back(fi);
		if (plan.removed.empty() || plan.removed.size() > 2) return Rej(1);
		// a's edges: border edges, fans
		std::map<int, std::vector<int>> byEdge;   // other vertex -> faces of a with that edge
		for (int fi : fa) {
			const Face& f = faces[fi];
			for (int k = 0; k < 3; ++k) if (f.p[k] != a) byEdge[f.p[k]].push_back(fi);
		}
		int borderEdges = 0;
		bool abBorder = false;
		for (auto& [o, list] : byEdge) {
			if (list.size() > 2) return Rej(2);
			if (list.size() == 1) { ++borderEdges; if (o == b) abBorder = true; }
		}
		if (borderEdges > 0 && !abBorder) return Rej(3);     // a on an open border moves only along it
		if (borderEdges > 2) return Rej(4);
		// one fan only (a is not where two separate surfaces touch)
		std::unordered_map<int, int> idx;
		for (size_t i = 0; i < fa.size(); ++i) idx[fa[i]] = int(i);
		std::vector<int> geo(fa.size()), att(fa.size());
		std::iota(geo.begin(), geo.end(), 0); std::iota(att.begin(), att.end(), 0);
		auto find = [](std::vector<int>& u, int x) { while (u[x] != x) { u[x] = u[u[x]]; x = u[x]; } return x; };
		for (auto& [o, list] : byEdge) {
			if (list.size() != 2) continue;
			const int i = idx[list[0]], j = idx[list[1]];
			geo[find(geo, i)] = find(geo, j);
			const Face& f = faces[list[0]];
			const Face& g = faces[list[1]];
			if (f.w[CornerOf(f, a)] == g.w[CornerOf(g, a)] && f.w[CornerOf(f, o)] == g.w[CornerOf(g, o)])
				att[find(att, i)] = find(att, j);
		}
		int fans = 0;
		for (size_t i = 0; i < fa.size(); ++i) fans += (find(geo, int(i)) == int(i));
		if (fans != 1) return Rej(5);
		// link condition: the vertices a and b share are those of the removed faces only
		std::vector<int> na, nb, common, opp;
		Neighbours(a, na); Neighbours(b, nb);
		std::set_intersection(na.begin(), na.end(), nb.begin(), nb.end(), std::back_inserter(common));
		for (int fi : plan.removed) { const Face& f = faces[fi]; for (int k = 0; k < 3; ++k) if (f.p[k] != a && f.p[k] != b) opp.push_back(f.p[k]); }
		std::sort(opp.begin(), opp.end());
		opp.erase(std::unique(opp.begin(), opp.end()), opp.end());
		if (common != opp) return Rej(6);
		if (plan.moved.empty()) return Rej(7);   // (a's faces all go: a small part, or the end of a strip, would vanish)
		// each island around a: the wedge it takes at b
		std::map<int, int> target;          // attribute sector -> wedge at b
		for (int fi : plan.removed) {
			const Face& f = faces[fi];
			const int s = find(att, idx[fi]);
			const int wb = f.w[CornerOf(f, b)];
			auto it = target.find(s);
			if (it != target.end() && it->second != wb) return Rej(8);
			target[s] = wb;
		}
		std::map<int, int> made;            // sector -> created wedge
		for (int fi : plan.moved) {
			const int s = find(att, idx[fi]);
			auto it = target.find(s);
			if (it != target.end()) { plan.newWedge.push_back(it->second); continue; }
			if (!P.cross || !tex) return Rej(9);
			auto m = made.find(s);
			if (m == made.end()) {
				// the island carried on to b: its texture coordinates at b from its own triangles' mapping
				double uv[2] = {0, 0}, wsum = 0;
				Wedge nw = wedges[faces[fi].w[CornerOf(faces[fi], a)]];
				for (int gi : plan.moved) {
					if (find(att, idx[gi]) != s) continue;
					double u2[2]; double w;
					if (!Extrapolate(faces[gi], pv[b].x, u2, w)) return Rej(10);
					uv[0] += u2[0] * w; uv[1] += u2[1] * w; wsum += w;
				}
				if (wsum <= 0) return false;
				nw.pid = b; nw.uv[0] = float(uv[0] / wsum); nw.uv[1] = float(uv[1] / wsum);
				plan.created.push_back(nw);
				m = made.emplace(s, -1 - int(plan.created.size() - 1)).first;
			}
			plan.newWedge.push_back(m->second);
			plan.crossing = true;
		}
		// BAR's surface planes (area-weighted): their mean square distance from b, a bound on the change of shape;
		// with the border and seam planes: the order to go in
		Quadric q = pv[a].q; q.Add(pv[b].q);
		Quadric qc = pv[a].qc; qc.Add(pv[b].qc);
		const double area = std::max(pv[a].area + pv[b].area, 1e-12);
		const double shape = std::max(q.Eval(pv[b].x), 0.0), lines = std::max(qc.Eval(pv[b].x), 0.0);
		plan.cost = std::sqrt((shape + lines) / area) * (plan.crossing ? P.crossCost : 1.0);
		plan.ok = true;
		return true;
	}

	// texture coordinates of face f's plane mapping at point x (any point, also outside it); w: its weight (area)
	bool Extrapolate(const Face& f, const V3& x, double uv[2], double& w) const
	{
		const V3 p0 = pv[f.p[0]].x, p1 = pv[f.p[1]].x, p2 = pv[f.p[2]].x;
		const V3 e1 = p1 - p0, e2 = p2 - p0, d = x - p0;
		const double a = Dot(e1, e1), b = Dot(e1, e2), c = Dot(e2, e2), det = a * c - b * b;
		if (det <= 1e-14) return false;
		const double s = (c * Dot(d, e1) - b * Dot(d, e2)) / det, t = (a * Dot(d, e2) - b * Dot(d, e1)) / det;
		const Wedge &w0 = wedges[f.w[0]], &w1 = wedges[f.w[1]], &w2 = wedges[f.w[2]];
		for (int k = 0; k < 2; ++k) uv[k] = w0.uv[k] + s * (w1.uv[k] - w0.uv[k]) + t * (w2.uv[k] - w0.uv[k]);
		w = std::sqrt(det);
		return true;
	}

	const Wedge& WedgeOf(const Plan& plan, int w) const { return w >= 0 ? wedges[w] : plan.created[-1 - w]; }

	// the moved faces as they would be: no flips (space, texture), no far turn, close to BAR's surface and colours
	bool Check(const Plan& plan, PieceStats& st)
	{
		const double cosTurn = std::cos(P.maxTurn * M_PI / 180.0);
		double colorSum = 0, weightSum = 0;
		// the way a's surface faces (for triangles that had no area of their own: one turning over leaves a hole)
		V3 fanN;
		for (int fi : pv[plan.a].faces) {
			const Face& f = faces[fi];
			if (f.alive) fanN = fanN + Cross(pv[f.p[1]].x - pv[f.p[0]].x, pv[f.p[2]].x - pv[f.p[0]].x);
		}
		const double lFan = Len(fanN);
		int samples = 0, far = 0;
		static const double S[12][3] = {
			{1 / 3., 1 / 3., 1 / 3.}, {0.6, 0.2, 0.2}, {0.2, 0.6, 0.2}, {0.2, 0.2, 0.6}, {0.45, 0.45, 0.1}, {0.45, 0.1, 0.45},
			{0.1, 0.45, 0.45}, {0.8, 0.1, 0.1}, {0.1, 0.8, 0.1}, {0.1, 0.1, 0.8}, {0.3, 0.3, 0.4}, {0.15, 0.425, 0.425}};
		for (size_t m = 0; m < plan.moved.size(); ++m) {
			const Face& f = faces[plan.moved[m]];
			V3 p[3]; const Wedge* w[3];
			for (int k = 0; k < 3; ++k) {
				const bool isA = (f.p[k] == plan.a);
				p[k] = pv[isA ? plan.b : f.p[k]].x;
				w[k] = isA ? &WedgeOf(plan, plan.newWedge[m]) : &wedges[f.w[k]];
			}
			const V3 nNew = Cross(p[1] - p[0], p[2] - p[0]);
			const double lNew = Len(nNew);
			const V3 nOld = Cross(pv[f.p[1]].x - pv[f.p[0]].x, pv[f.p[2]].x - pv[f.p[0]].x);
			const double lOld = Len(nOld), l0 = Len(f.n0);
			if (lNew < 1e-9 * std::max(1.0, lOld)) { ++st.rejGeo; return Rej(11); }
			if (lOld > 1e-12 && Dot(nNew, nOld) < cosTurn * lNew * lOld) { ++st.rejGeo; return Rej(12); }
			if (l0 > 1e-12 && Dot(nNew, f.n0) < cosTurn * lNew * l0) { ++st.rejGeo; return Rej(13); }
			if ((lOld <= 1e-9 * lNew || l0 <= 1e-9 * lNew) && (lFan <= 1e-12 || Dot(nNew, fanN) < cosTurn * lNew * lFan)) { ++st.rejGeo; return Rej(12); }
			// texture: the same winding on the image, not squashed to nothing
			auto uvArea = [](const Wedge* a, const Wedge* b, const Wedge* c) {
				return double(b->uv[0] - a->uv[0]) * (c->uv[1] - a->uv[1]) - double(b->uv[1] - a->uv[1]) * (c->uv[0] - a->uv[0]);
			};
			const Wedge* wo[3] = {&wedges[f.w[0]], &wedges[f.w[1]], &wedges[f.w[2]]};
			const double ua = uvArea(wo[0], wo[1], wo[2]), ub = uvArea(w[0], w[1], w[2]);
			if (std::fabs(ua) > 1e-12 && (ua > 0) != (ub > 0)) { ++st.rejGeo; return Rej(14); }
			// against BAR's surface
			const V3 n = nNew * (1.0 / lNew);
			const double area = lNew * 0.5;
			for (const auto& s : S) {
				const V3 x = p[0] * s[0] + p[1] * s[1] + p[2] * s[2];
				double d2, bc[3];
				const int t = bvh.Nearest(x, n, d2, bc);
				if (t < 0 || d2 > P.maxDist * P.maxDist) { ++st.rejGeo; return Rej(15); }
				if (!tex) continue;
				const Tri& o = bvh.tris[t];
				const double uo = o.uv[0][0] * bc[0] + o.uv[1][0] * bc[1] + o.uv[2][0] * bc[2];
				const double vo = o.uv[0][1] * bc[0] + o.uv[1][1] * bc[1] + o.uv[2][1] * bc[2];
				const double un = w[0]->uv[0] * s[0] + w[1]->uv[0] * s[1] + w[2]->uv[0] * s[2];
				const double vn = w[0]->uv[1] * s[0] + w[1]->uv[1] * s[1] + w[2]->uv[1] * s[2];
				double co[4], cn[4];
				tex->Sample(uo, vo, co);
				tex->Sample(un, vn, cn);
				const double diff = (std::fabs(co[0] - cn[0]) + std::fabs(co[1] - cn[1]) + std::fabs(co[2] - cn[2])) / 3.0
					+ std::fabs(co[3] - cn[3]);
				colorSum += diff * area; weightSum += area;
				++samples; far += (diff > P.farColor);
			}
		}
		if (tex && weightSum > 0) {
			if (colorSum / weightSum > P.maxColor) { ++st.rejTex; return Rej(16); }
			if (far > P.farShare * samples) { ++st.rejTex; return Rej(17); }
		}
		// and the other way: BAR's points merged into a and b near the new surface (a cut corner, a lost bump)
		{
			std::vector<int> around, nb;
			for (int x : {plan.a, plan.b}) {
				around.insert(around.end(), pv[x].faces.begin(), pv[x].faces.end());
				Neighbours(x, nb);
				for (int n : nb) around.insert(around.end(), pv[n].faces.begin(), pv[n].faces.end());
			}
			std::sort(around.begin(), around.end());
			around.erase(std::unique(around.begin(), around.end()), around.end());
			std::vector<std::array<V3, 3>> tris;
			for (int fi : around) {
				const Face& f = faces[fi];
				if (!f.alive || std::find(plan.removed.begin(), plan.removed.end(), fi) != plan.removed.end()) continue;
				std::array<V3, 3> t;
				for (int k = 0; k < 3; ++k) t[k] = pv[f.p[k] == plan.a ? plan.b : f.p[k]].x;
				tris.push_back(t);
			}
			const double lim2 = P.maxDist * P.maxDist;
			for (int x : {plan.a, plan.b}) {
				for (const V3& q : pv[x].kept) {
					double best = 1e30, u, v, w;
					for (const auto& t : tris) {
						const V3 c = ClosestOnTri(q, t[0], t[1], t[2], u, v, w) - q;
						best = std::min(best, Dot(c, c));
						if (best <= lim2) break;
					}
					if (best > lim2) { ++st.rejGeo; return Rej(22); }
				}
			}
			// the seams and borders as they would be: edges whose two sides differ in texture or normal, or open
			std::map<std::pair<int, int>, std::vector<std::pair<int, int>>> sides;   // (pid lo, hi) -> wedges at lo, hi
			for (int fi : around) {
				const Face& f = faces[fi];
				if (!f.alive || std::find(plan.removed.begin(), plan.removed.end(), fi) != plan.removed.end()) continue;
				int p[3], w[3];
				for (int k = 0; k < 3; ++k) {
					p[k] = f.p[k] == plan.a ? plan.b : f.p[k];
					w[k] = f.w[k];
					if (f.p[k] == plan.a) {
						const size_t m = std::find(plan.moved.begin(), plan.moved.end(), fi) - plan.moved.begin();
						w[k] = plan.newWedge[m] >= 0 ? plan.newWedge[m] : -1000 - (-1 - plan.newWedge[m]);
					}
				}
				for (int k = 0; k < 3; ++k) {
					const int u = p[k], v = p[(k + 1) % 3], wu = w[k], wv = w[(k + 1) % 3];
					if (u < v) sides[{u, v}].push_back({wu, wv}); else sides[{v, u}].push_back({wv, wu});
				}
			}
			std::vector<std::pair<V3, V3>> lines;
			for (auto& [e, list] : sides)
				if (list.size() != 2 || list[0] != list[1]) lines.push_back({pv[e.first].x, pv[e.second].x});
			const double lineLim = P.lineDist * P.maxDist, lineLim2 = lineLim * lineLim;
			for (int x : {plan.a, plan.b}) {
				for (const V3& q : pv[x].keptLine) {
					double best = 1e30;
					for (const auto& [u, v] : lines) {
						const V3 d = v - u;
						const double l2 = Dot(d, d);
						const double t = l2 > 0 ? std::clamp(Dot(q - u, d) / l2, 0.0, 1.0) : 0.0;
						const V3 c = u + d * t - q;
						best = std::min(best, Dot(c, c));
						if (best <= lineLim2) break;
					}
					if (best > lineLim2) { ++st.rejGeo; return Rej(23); }
				}
			}
		}
		return true;
	}

	void Apply(const Plan& plan)
	{
		const int a = plan.a, b = plan.b;
		std::vector<int> created(plan.created.size());
		for (size_t i = 0; i < plan.created.size(); ++i) { created[i] = int(wedges.size()); wedges.push_back(plan.created[i]); }
		for (int fi : plan.removed) faces[fi].alive = false;
		for (size_t m = 0; m < plan.moved.size(); ++m) {
			Face& f = faces[plan.moved[m]];
			const int k = CornerOf(f, a);
			f.p[k] = b;
			const int w = plan.newWedge[m];
			f.w[k] = w >= 0 ? w : created[-1 - w];
			pv[b].faces.push_back(plan.moved[m]);
		}
		pv[b].q.Add(pv[a].q);
		pv[b].qc.Add(pv[a].qc);
		pv[b].area += pv[a].area;
		pv[b].kept.insert(pv[b].kept.end(), pv[a].kept.begin(), pv[a].kept.end());
		pv[b].keptLine.insert(pv[b].keptLine.end(), pv[a].keptLine.begin(), pv[a].keptLine.end());
		pv[b].locked = pv[b].locked || false;
		pv[a].alive = false;
		pv[a].faces.clear();
		auto& fb = pv[b].faces;
		fb.erase(std::remove_if(fb.begin(), fb.end(), [&](int fi) { return !faces[fi].alive; }), fb.end());
		std::vector<int> ring;
		Neighbours(b, ring);
		ring.push_back(b);
		for (int x : ring) {
			++pv[x].version;
			auto& fx = pv[x].faces;
			fx.erase(std::remove_if(fx.begin(), fx.end(), [&](int fi) { return !faces[fi].alive; }), fx.end());
		}
		for (int x : ring) PushAll(x);
	}

	void PushAll(int a)
	{
		if (!pv[a].alive) return;
		std::vector<int> nb;
		Neighbours(a, nb);
		Plan plan;
		for (int b : nb) {
			if (Prepare(a, b, plan)) queue.push({float(plan.cost), a, b, pv[a].version, pv[b].version});
			if (Prepare(b, a, plan)) queue.push({float(plan.cost), b, a, pv[b].version, pv[a].version});
		}
	}

	void Output(const std::vector<S3OVertex>& vin, const std::vector<std::array<int, 3>>& lod0,
		const std::vector<std::array<int, 3>>& lod1, std::vector<S3OVertex>& vout, std::vector<int>& tout, std::vector<int>& tlod)
	{
		std::vector<int> map(wedges.size(), -1);
		std::vector<S3OVertex> vs;
		std::vector<unsigned int> idx0, idx1;
		for (int level = 0; level < 2; ++level) {
			for (const auto& f : level ? lod1 : lod0) {
				for (int k = 0; k < 3; ++k) {
					int& m = map[f[k]];
					if (m < 0) {
						m = int(vs.size());
						S3OVertex v;
						const Wedge& w = wedges[f[k]];
						const V3& x = pv[w.pid].x;
						v.p[0] = float(x.x); v.p[1] = float(x.y); v.p[2] = float(x.z);
						memcpy(v.n, w.n, sizeof(v.n)); memcpy(v.uv, w.uv, sizeof(v.uv));
						vs.push_back(v);
					}
					(level ? idx1 : idx0).push_back(unsigned(m));
				}
			}
		}
		meshopt_optimizeVertexCache(idx0.data(), idx0.data(), idx0.size(), vs.size());
		if (!idx1.empty()) meshopt_optimizeVertexCache(idx1.data(), idx1.data(), idx1.size(), vs.size());
		// vertices in the order the fine list first uses them, then those only the coarse one uses
		std::vector<unsigned int> both(idx0);
		both.insert(both.end(), idx1.begin(), idx1.end());
		std::vector<unsigned int> remap(vs.size());
		const size_t unique = meshopt_optimizeVertexFetchRemap(remap.data(), both.data(), both.size(), vs.size());
		vout.clear();
		const int lead = int(std::min<size_t>(2, vin.size()));
		for (int i = 0; i < lead; ++i) vout.push_back(vin[i]);   // BAR's vertex 0 and 1 (weapon and effect aim)
		vout.resize(lead + unique);
		for (size_t i = 0; i < vs.size(); ++i) if (remap[i] != ~0u) vout[lead + remap[i]] = vs[i];
		tout.resize(idx0.size());
		for (size_t i = 0; i < idx0.size(); ++i) tout[i] = int(lead + remap[idx0[i]]);
		tlod.clear();
		if (idx1.size() < idx0.size()) {
			tlod.resize(idx1.size());
			for (size_t i = 0; i < idx1.size(); ++i) tlod[i] = int(lead + remap[idx1[i]]);
		}
	}
};

// ------------------------------------------------------------------------------------------------ renderer
struct Image {
	int w = 0, h = 0;
	std::vector<uint8_t> rgb;
	std::vector<float> z;
	std::vector<uint8_t> cover;
	void Init(int W, int H) { w = W; h = H; rgb.assign(size_t(w) * h * 3, 0); z.assign(size_t(w) * h, 1e30f); cover.assign(size_t(w) * h, 0); }
};

struct View { double az, el; };

// each piece's place in the model (the engine's goffset: its offset plus its parent's)
static void PieceWorldOffsets(const S3OModel& m, std::vector<V3>& off)
{
	off.assign(m.pieces.size(), V3());
	off[0] = V3(m.pieces[0].off[0], m.pieces[0].off[1], m.pieces[0].off[2]);
	std::vector<int> stack = {0};
	while (!stack.empty()) {
		const int p = stack.back(); stack.pop_back();
		for (int c : m.pieces[p].children) {
			off[c] = off[p] + V3(m.pieces[c].off[0], m.pieces[c].off[1], m.pieces[c].off[2]);
			stack.push_back(c);
		}
	}
}

static double gZoom = 1.0;
static int gCull = 1;   // which screen winding is a back face (+1: the engine's, counter-clockwise fronts), 0: none
static void Bounds(const S3OModel& m, V3& c, double& r)
{
	// the unit's own sphere (the header's, as the engine uses it), when it has one: hidden extras (hats) stay out
	if (m.radius > 0.01f) {
		c = V3(m.mid[0], m.mid[1], m.mid[2]);
		r = m.radius / gZoom;
		return;
	}
	std::vector<V3> off;
	PieceWorldOffsets(m, off);
	V3 lo(1e30, 1e30, 1e30), hi(-1e30, -1e30, -1e30);
	bool any = false;
	for (size_t p = 0; p < m.pieces.size(); ++p) {
		const std::vector<int> t = Triangles(m.pieces[p]);
		for (int i : t) {
			if (i < 0 || size_t(i) >= m.pieces[p].verts.size()) continue;
			const S3OVertex& v = m.pieces[p].verts[i];
			const V3 x = off[p] + V3(v.p[0], v.p[1], v.p[2]);
			for (int k = 0; k < 3; ++k) { lo[k] = std::min(lo[k], x[k]); hi[k] = std::max(hi[k], x[k]); }
			any = true;
		}
	}
	if (!any) { c = V3(); r = 1; return; }
	c = (lo + hi) * 0.5;
	r = std::max(Len(hi - lo) * 0.5, 1e-3) / gZoom;
}

static void Render(const S3OModel& m, const Texture* tex, const V3& c, double r, const View& view, Image& img, uint64_t* tris = nullptr)
{
	const double az = view.az * M_PI / 180, el = view.el * M_PI / 180;
	const V3 fwd(-std::cos(el) * std::sin(az), -std::sin(el), -std::cos(el) * std::cos(az));   // camera looks along fwd
	const V3 right = Norm(Cross(fwd, V3(0, 1, 0)));
	const V3 up = Cross(right, fwd);
	const V3 light = Norm(V3(0.4, 1.0, 0.5));
	const double team[3] = {0.15, 0.45, 1.0};
	std::vector<V3> off;
	PieceWorldOffsets(m, off);
	const double scale = img.w * 0.5 / (r * 1.05);
	for (size_t p = 0; p < m.pieces.size(); ++p) {
		const S3OPiece& pc = m.pieces[p];
		const std::vector<int> t = Triangles(pc);
		for (size_t i = 0; i + 2 < t.size(); i += 3) {
			double sx[3], sy[3], sz[3];
			const S3OVertex* v[3];
			bool ok = true;
			for (int k = 0; k < 3; ++k) {
				if (t[i + k] < 0 || size_t(t[i + k]) >= pc.verts.size()) { ok = false; break; }
				v[k] = &pc.verts[t[i + k]];
				const V3 x = off[p] + V3(v[k]->p[0], v[k]->p[1], v[k]->p[2]) - c;
				sx[k] = img.w * 0.5 + Dot(x, right) * scale;
				sy[k] = img.h * 0.5 - Dot(x, up) * scale;
				sz[k] = Dot(x, fwd);
			}
			if (!ok) continue;
			if (tris) ++*tris;
			const double area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0]);
			if (std::fabs(area) < 1e-12) continue;
			if (gCull != 0 && (area > 0) == (gCull > 0)) continue;   // (the engine culls S3O back faces)
			const int x0 = std::max(0, int(std::floor(std::min({sx[0], sx[1], sx[2]})))), x1 = std::min(img.w - 1, int(std::ceil(std::max({sx[0], sx[1], sx[2]}))));
			const int y0 = std::max(0, int(std::floor(std::min({sy[0], sy[1], sy[2]})))), y1 = std::min(img.h - 1, int(std::ceil(std::max({sy[0], sy[1], sy[2]}))));
			for (int y = y0; y <= y1; ++y) {
				for (int x = x0; x <= x1; ++x) {
					const double px = x + 0.5, py = y + 0.5;
					const double b0 = ((sx[1] - px) * (sy[2] - py) - (sx[2] - px) * (sy[1] - py)) / area;
					const double b1 = ((sx[2] - px) * (sy[0] - py) - (sx[0] - px) * (sy[2] - py)) / area;
					const double b2 = 1 - b0 - b1;
					if (b0 < 0 || b1 < 0 || b2 < 0) continue;
					const double zz = b0 * sz[0] + b1 * sz[1] + b2 * sz[2];
					const size_t pi = size_t(y) * img.w + x;
					if (zz >= img.z[pi]) continue;
					img.z[pi] = float(zz);
					img.cover[pi] = 1;
					V3 n(b0 * v[0]->n[0] + b1 * v[1]->n[0] + b2 * v[2]->n[0], b0 * v[0]->n[1] + b1 * v[1]->n[1] + b2 * v[2]->n[1],
						b0 * v[0]->n[2] + b1 * v[1]->n[2] + b2 * v[2]->n[2]);
					n = Norm(n);
					if (Dot(n, fwd) > 0) n = n * -1.0;
					double col[4] = {0.7, 0.7, 0.7, 0};
					if (tex) {
						const double u = b0 * v[0]->uv[0] + b1 * v[1]->uv[0] + b2 * v[2]->uv[0];
						const double vv = b0 * v[0]->uv[1] + b1 * v[1]->uv[1] + b2 * v[2]->uv[1];
						tex->Sample(u, vv, col);
					}
					const double lit = 0.38 + 0.72 * std::max(0.0, Dot(n, light));
					for (int k = 0; k < 3; ++k) {
						const double base = col[k] * (1 - col[3]) + team[k] * col[3];
						img.rgb[3 * pi + k] = uint8_t(std::clamp(base * lit * 255.0, 0.0, 255.0));
					}
				}
			}
		}
	}
}

static uint32_t Crc32(const uint8_t* d, size_t n, uint32_t c = 0)
{
	static uint32_t table[256];
	static bool init = false;
	if (!init) {
		for (uint32_t i = 0; i < 256; ++i) { uint32_t k = i; for (int j = 0; j < 8; ++j) k = (k & 1) ? 0xEDB88320u ^ (k >> 1) : k >> 1; table[i] = k; }
		init = true;
	}
	c = ~c;
	for (size_t i = 0; i < n; ++i) c = table[(c ^ d[i]) & 255] ^ (c >> 8);
	return ~c;
}

static bool SavePNG(const fs::path& path, int w, int h, const std::vector<uint8_t>& rgb)
{
	std::vector<uint8_t> raw;
	raw.reserve(size_t(h) * (w * 3 + 1));
	for (int y = 0; y < h; ++y) { raw.push_back(0); raw.insert(raw.end(), rgb.begin() + size_t(y) * w * 3, rgb.begin() + size_t(y + 1) * w * 3); }
	std::vector<uint8_t> z = {0x78, 0x01};
	uint32_t s1 = 1, s2 = 0;
	for (uint8_t v : raw) { s1 = (s1 + v) % 65521; s2 = (s2 + s1) % 65521; }
	for (size_t i = 0; i < raw.size(); i += 65535) {
		const size_t n = std::min<size_t>(65535, raw.size() - i);
		z.push_back(i + n == raw.size() ? 1 : 0);
		z.push_back(uint8_t(n)); z.push_back(uint8_t(n >> 8)); z.push_back(uint8_t(~n)); z.push_back(uint8_t((~n) >> 8));
		z.insert(z.end(), raw.begin() + i, raw.begin() + i + n);
	}
	const uint32_t ad = (s2 << 16) | s1;
	z.push_back(uint8_t(ad >> 24)); z.push_back(uint8_t(ad >> 16)); z.push_back(uint8_t(ad >> 8)); z.push_back(uint8_t(ad));
	std::vector<uint8_t> out = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
	auto chunk = [&](const char* type, const std::vector<uint8_t>& data) {
		const uint32_t n = uint32_t(data.size());
		out.push_back(uint8_t(n >> 24)); out.push_back(uint8_t(n >> 16)); out.push_back(uint8_t(n >> 8)); out.push_back(uint8_t(n));
		std::vector<uint8_t> td(type, type + 4);
		td.insert(td.end(), data.begin(), data.end());
		out.insert(out.end(), td.begin(), td.end());
		const uint32_t c = Crc32(td.data(), td.size());
		out.push_back(uint8_t(c >> 24)); out.push_back(uint8_t(c >> 16)); out.push_back(uint8_t(c >> 8)); out.push_back(uint8_t(c));
	};
	std::vector<uint8_t> ihdr = {uint8_t(w >> 24), uint8_t(w >> 16), uint8_t(w >> 8), uint8_t(w), uint8_t(h >> 24), uint8_t(h >> 16), uint8_t(h >> 8), uint8_t(h), 8, 2, 0, 0, 0};
	chunk("IHDR", ihdr);
	chunk("IDAT", z);
	chunk("IEND", {});
	fs::create_directories(path.parent_path());
	std::ofstream f(path, std::ios::binary);
	f.write(reinterpret_cast<const char*>(out.data()), out.size());
	return bool(f);
}

static const View kViews[] = {{30, 35}, {150, 35}, {270, 20}, {45, 70}, {210, 55}};

// the looks of two models side by side: mean colour difference over their pixels (0..1) and the share of pixels only
// one of them covers
static void Compare(const S3OModel& a, const S3OModel& b, const Texture* tex, int size, double& colour, double& outline, double& changed)
{
	V3 c; double r;
	Bounds(a, c, r);
	colour = outline = changed = 0;
	for (const View& v : kViews) {
		Image A, B;
		A.Init(size, size); B.Init(size, size);
		Render(a, tex, c, r, v, A);
		Render(b, tex, c, r, v, B);
		double sum = 0; size_t n = 0, x = 0, ch = 0;
		for (size_t i = 0; i < A.cover.size(); ++i) {
			if (!A.cover[i] && !B.cover[i]) continue;
			++n;
			if (A.cover[i] != B.cover[i]) { ++x; ++ch; continue; }
			const double d = (std::abs(A.rgb[3 * i] - B.rgb[3 * i]) + std::abs(A.rgb[3 * i + 1] - B.rgb[3 * i + 1]) + std::abs(A.rgb[3 * i + 2] - B.rgb[3 * i + 2])) / (3 * 255.0);
			sum += d;
			ch += (d > 0.1);
		}
		if (n) { colour = std::max(colour, sum / n); outline = std::max(outline, double(x) / n); changed = std::max(changed, double(ch) / n); }
	}
}

static void SheetPNG(const fs::path& out, const std::vector<const S3OModel*>& rows, const Texture* tex, int size)
{
	V3 c; double r;
	Bounds(*rows[0], c, r);
	const int nv = int(sizeof(kViews) / sizeof(kViews[0]));
	const int W = size * nv, H = size * int(rows.size());
	std::vector<uint8_t> rgb(size_t(W) * H * 3, 0);
	for (size_t ri = 0; ri < rows.size(); ++ri) {
		for (int vi = 0; vi < nv; ++vi) {
			Image img;
			img.Init(size, size);
			Render(*rows[ri], tex, c, r, kViews[vi], img);
			for (int y = 0; y < size; ++y)
				for (int x = 0; x < size; ++x) {
					const size_t s = (size_t(y) * size + x) * 3;
					const size_t d = ((size_t(ri) * size + y) * W + size_t(vi) * size + x) * 3;
					const bool cov = img.cover[size_t(y) * size + x];
					for (int k = 0; k < 3; ++k) rgb[d + k] = cov ? img.rgb[s + k] : uint8_t(40 + 8 * ri);
				}
		}
	}
	SavePNG(out, W, H, rgb);
}

// ------------------------------------------------------------------------------------------------ hidden triangles
// Triangles of a piece that no camera can see: from every one of many directions each is either facing away (the
// engine culls S3O back faces) or behind the piece's own front faces. A piece moves as one, so what hides a triangle
// inside its own piece hides it in every animation; other pieces are not counted on. Sample points of each triangle
// (its middle, its corners and edges pulled in a little) are tested against the depth of the nearest front faces with a
// little slack (and the deepest of the 3x3 pixels around), so a triangle is called hidden only when clearly so.
static std::vector<char> VisibleTriangles(const std::vector<S3OVertex>& v, const std::vector<int>& t, int dirs, int res)
{
	const size_t nt = t.size() / 3;
	std::vector<char> vis(nt, 0);
	if (nt == 0) return vis;
	V3 lo(1e30, 1e30, 1e30), hi(-1e30, -1e30, -1e30);
	for (int i : t) for (int k = 0; k < 3; ++k) { lo[k] = std::min(lo[k], double(v[i].p[k])); hi[k] = std::max(hi[k], double(v[i].p[k])); }
	const V3 c = (lo + hi) * 0.5;
	const double r = std::max(Len(hi - lo) * 0.5, 1e-4);
	const double scale = res * 0.5 / (r * 1.02), eps = 0.004 * r;
	std::vector<V3> pos(v.size());
	for (size_t i = 0; i < v.size(); ++i) pos[i] = V3(v[i].p[0], v[i].p[1], v[i].p[2]) - c;
	std::vector<V3> fn(nt);
	for (size_t i = 0; i < nt; ++i) fn[i] = Cross(pos[t[3 * i + 1]] - pos[t[3 * i]], pos[t[3 * i + 2]] - pos[t[3 * i]]);
	std::vector<float> z(size_t(res) * res);
	std::vector<double> sx(v.size()), sy(v.size()), sz(v.size());
	const double golden = M_PI * (3.0 - std::sqrt(5.0));
	for (int d = 0; d < dirs; ++d) {
		const double yy = 1.0 - 2.0 * (d + 0.5) / dirs, rr = std::sqrt(std::max(0.0, 1 - yy * yy)), th = golden * d;
		const V3 fwd(-rr * std::cos(th), -yy, -rr * std::sin(th));   // the camera looks along fwd
		const V3 helper = std::fabs(fwd.y) < 0.9 ? V3(0, 1, 0) : V3(1, 0, 0);
		const V3 right = Norm(Cross(fwd, helper)), up = Cross(right, fwd);
		for (size_t i = 0; i < v.size(); ++i) {
			sx[i] = res * 0.5 + Dot(pos[i], right) * scale;
			sy[i] = res * 0.5 - Dot(pos[i], up) * scale;
			sz[i] = Dot(pos[i], fwd);
		}
		std::fill(z.begin(), z.end(), 1e30f);
		for (size_t f = 0; f < nt; ++f) {
			if (Dot(fn[f], fwd) >= 0) continue;   // facing away: culled
			const int a = t[3 * f], b = t[3 * f + 1], e = t[3 * f + 2];
			const double area = (sx[b] - sx[a]) * (sy[e] - sy[a]) - (sx[e] - sx[a]) * (sy[b] - sy[a]);
			if (std::fabs(area) < 1e-12) continue;
			const int x0 = std::max(0, int(std::floor(std::min({sx[a], sx[b], sx[e]})))), x1 = std::min(res - 1, int(std::ceil(std::max({sx[a], sx[b], sx[e]}))));
			const int y0 = std::max(0, int(std::floor(std::min({sy[a], sy[b], sy[e]})))), y1 = std::min(res - 1, int(std::ceil(std::max({sy[a], sy[b], sy[e]}))));
			for (int y = y0; y <= y1; ++y)
				for (int x = x0; x <= x1; ++x) {
					const double px = x + 0.5, py = y + 0.5;
					const double b0 = ((sx[b] - px) * (sy[e] - py) - (sx[e] - px) * (sy[b] - py)) / area;
					const double b1 = ((sx[e] - px) * (sy[a] - py) - (sx[a] - px) * (sy[e] - py)) / area;
					const double b2 = 1 - b0 - b1;
					if (b0 < 0 || b1 < 0 || b2 < 0) continue;
					const float zz = float(b0 * sz[a] + b1 * sz[b] + b2 * sz[e]);
					float& zb = z[size_t(y) * res + x];
					if (zz < zb) zb = zz;
				}
		}
		static const double S[7][3] = {{1 / 3., 1 / 3., 1 / 3.}, {0.9, 0.05, 0.05}, {0.05, 0.9, 0.05}, {0.05, 0.05, 0.9},
			{0.475, 0.475, 0.05}, {0.05, 0.475, 0.475}, {0.475, 0.05, 0.475}};
		for (size_t f = 0; f < nt; ++f) {
			if (vis[f] || Dot(fn[f], fwd) >= 0) continue;
			const int a = t[3 * f], b = t[3 * f + 1], e = t[3 * f + 2];
			for (const auto& w : S) {
				const double px = w[0] * sx[a] + w[1] * sx[b] + w[2] * sx[e], py = w[0] * sy[a] + w[1] * sy[b] + w[2] * sy[e];
				const double pz = w[0] * sz[a] + w[1] * sz[b] + w[2] * sz[e];
				const int ix = int(px), iy = int(py);
				float deepest = -1e30f;
				for (int dy = -1; dy <= 1; ++dy)
					for (int dx = -1; dx <= 1; ++dx) {
						const int qx = std::clamp(ix + dx, 0, res - 1), qy = std::clamp(iy + dy, 0, res - 1);
						const float zb = z[size_t(qy) * res + qx];
						deepest = std::max(deepest, zb >= 1e29f ? 1e29f : zb);
					}
				if (pz <= deepest + eps) { vis[f] = 1; break; }
			}
		}
	}
	return vis;
}

// ------------------------------------------------------------------------------------------------ the models
struct ModelResult {
	std::string rel;
	bool ok = false;
	std::string error;
	size_t pieces = 0, trisIn = 0, trisOut = 0, vertsIn = 0, vertsOut = 0, cut = 0, crossings = 0, hidden = 0, lodTris = 0;
	double colour = 0, outline = 0, changed = 0, lodChanged = 0, seconds = 0;
	bool tex = false;
};

static std::atomic<long> gReasons[24], gBlockers[24];
static bool gScanBlockers = false;
static const char* kReasons[24] = {"locked", "edge faces", "a edge >2", "border off-edge", "border >2", "fans", "link", "all removed",
	"sector conflict", "cross off", "extrapolate", "degenerate", "turn now", "turn orig", "uv flip", "distance", "colour mean", "colour far",
	"stop cost", "stop empty", "too costly", "would pass", "shape lost", "outline lost"};

static size_t CountTris(const S3OModel& m) { size_t n = 0; for (const auto& p : m.pieces) n += Triangles(p).size() / 3; return n; }
static size_t CountVerts(const S3OModel& m) { size_t n = 0; for (const auto& p : m.pieces) n += p.verts.size(); return n; }

static ModelResult MakeMobile(const fs::path& src, const fs::path& dst, const std::string& rel, TextureCache& tc, const Params& P, bool qa, int qaSize)
{
	ModelResult r;
	r.rel = rel;
	const auto t0 = std::chrono::steady_clock::now();
	S3OModel m;
	if (!LoadS3O(src, m, r.error))
		return r;
	r.pieces = m.pieces.size();
	r.trisIn = CountTris(m);
	r.vertsIn = CountVerts(m);
	std::shared_ptr<Texture> tex = tc.Get("" + m.tex1);
	if (!tex && !m.tex1.empty()) {
		std::string base = m.tex1;
		tex = tc.Get(base);
	}
	r.tex = bool(tex);
	S3OModel out = m;   // (sourceHash: BAR's file's, which the engine compares with the model it loaded)
	Params PM = P;
	{
		V3 c; double rad;
		const double z = gZoom; gZoom = 1.0;
		Bounds(m, c, rad);
		gZoom = z;
		PM.maxDist = std::min(P.maxDist, P.relDist * rad);
	}
	Params PL = PM;   // the coarse level, for units small on the screen
	{
		V3 c; double rad;
		const double z = gZoom; gZoom = 1.0;
		Bounds(m, c, rad);
		gZoom = z;
		PL.maxDist = std::min(P.lodDist, P.lodRelDist * rad);
		PL.maxColor = P.lodColor; PL.farColor = P.lodFarColor; PL.lineDist = P.lodLineDist;
	}
	for (size_t pi = 0; pi < m.pieces.size(); ++pi) {
		const S3OPiece& p = m.pieces[pi];
		S3OPiece& q = out.pieces[pi];
		std::vector<int> t = Triangles(p);
		bool idxOk = true;
		for (int i : t) idxOk &= (i >= 0 && size_t(i) < p.verts.size());
		if (!idxOk) continue;   // (BAR's own, as it is: an index past its vertices)
		q.idx = t;              // (triangles only from here on; strips and quads as the engine turns them into triangles)
		q.primType = 0;
		if (P.hiddenDirs > 0 && t.size() >= 3) {
			const std::vector<char> vis = VisibleTriangles(p.verts, t, P.hiddenDirs, P.hiddenRes);
			std::vector<int> kept;
			for (size_t f = 0; f < vis.size(); ++f) if (vis[f]) kept.insert(kept.end(), t.begin() + 3 * f, t.begin() + 3 * f + 3);
			if (!kept.empty() && kept.size() < t.size()) { r.hidden += (t.size() - kept.size()) / 3; t.swap(kept); q.idx = t; }
		}
		if (t.size() / 3 < size_t(P.minTris) || p.verts.size() < 3)
			continue;
		Simplifier s(PM, tex.get());
		std::vector<S3OVertex> vo;
		std::vector<int> to, tl;
		PieceStats st;
		s.scanBlockers = gScanBlockers;
		const bool ran = s.Run(p.verts, t, P.lod ? &PL : nullptr, vo, to, tl, st);
		for (int k = 0; k < 24; ++k) { gReasons[k] += s.reasons[k]; gBlockers[k] += s.blockers[k]; }
		if (!ran || to.size() < 3)
			continue;
		q.verts = vo;
		q.idx = to;
		q.lod = tl;
		++r.cut;
		r.crossings += st.crossings;
	}	r.trisOut = CountTris(out);
	r.vertsOut = CountVerts(out);
	r.lodTris = 0;
	for (const auto& p : out.pieces) r.lodTris += (p.lod.empty() ? p.idx.size() : p.lod.size()) / 3;
	if (!SaveS3O(dst, out)) { r.error = "cannot write"; return r; }
	if (qa) {
		Compare(m, out, tex.get(), qaSize, r.colour, r.outline, r.changed);
		if (P.lod) {   // the coarse level as it is drawn: small (P.lodQaSize pixels)
			S3OModel coarse = out;
			for (auto& p : coarse.pieces) if (!p.lod.empty()) p.idx = p.lod;
			double c2, o2;
			Compare(m, coarse, tex.get(), P.lodQaSize, c2, o2, r.lodChanged);
		}
	}
	r.ok = true;
	r.seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
	return r;
}

static std::string Arg(int argc, char** argv, const char* name, const char* def = "")
{
	for (int i = 1; i + 1 < argc; ++i) if (!strcmp(argv[i], name)) return argv[i + 1];
	return def;
}
static bool Flag(int argc, char** argv, const char* name) { for (int i = 1; i < argc; ++i) if (!strcmp(argv[i], name)) return true; return false; }

static void ReadParams(int argc, char** argv, Params& P)
{
	auto d = [&](const char* n, double& v) { const std::string s = Arg(argc, argv, n); if (!s.empty()) v = atof(s.c_str()); };
	d("--dist", P.maxDist); d("--rel-dist", P.relDist); d("--color", P.maxColor); d("--far-color", P.farColor); d("--far-share", P.farShare);
	d("--turn", P.maxTurn); d("--line-dist", P.lineDist); d("--line-contrast", P.lineContrast); d("--min-share", P.minShare); d("--cross-cost", P.crossCost);
	d("--border-weight", P.borderWeight); d("--seam-weight", P.seamWeight);
	const std::string mt = Arg(argc, argv, "--min-tris"); if (!mt.empty()) P.minTris = atoi(mt.c_str());
	const std::string hd = Arg(argc, argv, "--hidden-dirs"); if (!hd.empty()) P.hiddenDirs = atoi(hd.c_str());
	const std::string hr = Arg(argc, argv, "--hidden-res"); if (!hr.empty()) P.hiddenRes = atoi(hr.c_str());
	if (Flag(argc, argv, "--no-cross")) P.cross = false;
	if (Flag(argc, argv, "--no-lod")) P.lod = false;
	d("--lod-dist", P.lodDist); d("--lod-rel-dist", P.lodRelDist); d("--lod-color", P.lodColor); d("--lod-far-color", P.lodFarColor);
	d("--lod-line-dist", P.lodLineDist);
	const std::string lq = Arg(argc, argv, "--lod-qa-size"); if (!lq.empty()) P.lodQaSize = atoi(lq.c_str());
}

int main(int argc, char** argv)
{
	if (argc < 2) {
		fprintf(stderr, "mobile_models build --src <dir> --out <dir> [--only text] [--jobs N] [--qa] [--dist e] [--color c] ...\n"
			"mobile_models render --a <s3o> [--b <s3o>] --tex <unittextures dir> --png <file> [--size N]\n");
		return 2;
	}
	const std::string cmd = argv[1];
	Params P;
	ReadParams(argc, argv, P);
	if (cmd == "render") {
		TextureCache tc;
		tc.dir = Arg(argc, argv, "--tex");
		tc.maxSize = 2048;
		tc.Index();
		std::vector<S3OModel> models;
		std::string err;
		for (const char* k : {"--a", "--b", "--c", "--d"}) {
			const std::string p = Arg(argc, argv, k);
			if (p.empty()) continue;
			models.emplace_back();
			if (!LoadS3O(p, models.back(), err)) { fprintf(stderr, "%s: %s\n", p.c_str(), err.c_str()); return 1; }
			// --lod b|c|d: that row drawn from its coarse level
			const std::string lod = Arg(argc, argv, "--lod");
			if (!lod.empty() && lod == std::string(k + 2))
				for (auto& p : models.back().pieces) if (!p.lod.empty()) p.idx = p.lod;
		}
		if (models.empty()) return 2;
		std::vector<const S3OModel*> rows;
		for (auto& m : models) rows.push_back(&m);
		gZoom = atof(Arg(argc, argv, "--zoom", "1").c_str());
		gCull = atoi(Arg(argc, argv, "--cull", "0").c_str());
		auto tex = tc.Get(models[0].tex1);
		SheetPNG(Arg(argc, argv, "--png"), rows, tex.get(), atoi(Arg(argc, argv, "--size", "320").c_str()));
		for (auto& m : models) printf("%zu triangles, %zu vertices\n", CountTris(m), CountVerts(m));
		return 0;
	}
	if (cmd == "texstat") {   // a texture's alpha: how much of it is under 0.5 (see-through where the engine tests it)
		std::vector<uint8_t> b; Texture t;
		if (!ReadFile(Arg(argc, argv, "--file"), b) || !(LoadDDS(b, 1024, t) || LoadTGA(b, t))) return 1;
		size_t lo = 0, mid = 0; double sum[4] = {0};
		for (size_t i = 0; i < size_t(t.w) * t.h; ++i) {
			for (int k = 0; k < 4; ++k) sum[k] += t.rgba[4 * i + k];
			lo += t.rgba[4 * i + 3] < 128; mid += t.rgba[4 * i + 3] > 8 && t.rgba[4 * i + 3] < 247;
		}
		const double n = double(t.w) * t.h;
		printf("%dx%d mean rgba %.0f %.0f %.0f %.0f, alpha<0.5 %.1f %%, partial %.1f %%\n", t.w, t.h, sum[0] / n, sum[1] / n, sum[2] / n, sum[3] / n, 100 * lo / n, 100 * mid / n);
		return 0;
	}
	if (cmd == "acmr") {   // vertex shader runs per triangle with a 16 / 32 entry cache: BAR's order and ours
		S3OModel a, b; std::string err;
		LoadS3O(Arg(argc, argv, "--a"), a, err);
		const bool hasB = !Arg(argc, argv, "--b").empty() && LoadS3O(Arg(argc, argv, "--b"), b, err);
		for (int which = 0; which < (hasB ? 2 : 1); ++which) {
			const S3OModel& m = which ? b : a;
			double inv16 = 0, inv32 = 0, invOpt = 0; size_t tris = 0, verts = 0;
			for (const auto& p : m.pieces) {
				std::vector<int> t = Triangles(p);
				if (t.empty()) continue;
				std::vector<unsigned> u(t.begin(), t.end());
				const auto s16 = meshopt_analyzeVertexCache(u.data(), u.size(), p.verts.size(), 16, 0, 0);
				const auto s32 = meshopt_analyzeVertexCache(u.data(), u.size(), p.verts.size(), 32, 0, 0);
				std::vector<unsigned> o(u.size());
				meshopt_optimizeVertexCache(o.data(), u.data(), u.size(), p.verts.size());
				const auto so = meshopt_analyzeVertexCache(o.data(), o.size(), p.verts.size(), 16, 0, 0);
				inv16 += s16.vertices_transformed; inv32 += s32.vertices_transformed; invOpt += so.vertices_transformed;
				tris += u.size() / 3; verts += p.verts.size();
			}
			printf("%s: %zu triangles %zu vertices; shaded (cache 16) %.0f, (32) %.0f, reordered (16) %.0f\n", which ? "b" : "a", tris, verts, inv16, inv32, invOpt);
		}
		return 0;
	}
	if (cmd != "build") return 2;
	const fs::path src = Arg(argc, argv, "--src"), out = Arg(argc, argv, "--out");
	const std::string only = Arg(argc, argv, "--only");
	const bool qa = Flag(argc, argv, "--qa");
	gScanBlockers = Flag(argc, argv, "--verbose");
	const int qaSize = atoi(Arg(argc, argv, "--qa-size", "192").c_str());
	int jobs = atoi(Arg(argc, argv, "--jobs", "0").c_str());
	if (jobs <= 0) jobs = int(std::max(1u, std::thread::hardware_concurrency()));
	TextureCache tc;
	tc.dir = src / "unittextures";
	tc.maxSize = 1024;
	tc.Index();
	std::vector<std::string> rels;
	for (auto& e : fs::recursive_directory_iterator(src / "objects3d")) {
		if (!e.is_regular_file()) continue;
		std::string rel = fs::relative(e.path(), src).generic_string();
		std::string low = rel;
		std::transform(low.begin(), low.end(), low.begin(), ::tolower);
		if (low.size() < 4 || low.substr(low.size() - 4) != ".s3o") continue;
		if (!only.empty() && low.find(only) == std::string::npos) continue;
		rels.push_back(rel);
	}
	std::sort(rels.begin(), rels.end());
	std::vector<ModelResult> results(rels.size());
	std::atomic<size_t> next{0};
	std::atomic<size_t> done{0};
	std::mutex logMtx;
	auto worker = [&]() {
		for (;;) {
			const size_t i = next++;
			if (i >= rels.size()) return;
			results[i] = MakeMobile(src / rels[i], out / rels[i], rels[i], tc, P, qa, qaSize);
			const size_t d = ++done;
			if (d % 100 == 0) { std::lock_guard<std::mutex> lk(logMtx); fprintf(stderr, "  %zu / %zu\n", d, rels.size()); }
		}
	};
	const auto t0 = std::chrono::steady_clock::now();
	std::vector<std::thread> th;
	for (int j = 0; j < jobs; ++j) th.emplace_back(worker);
	for (auto& t : th) t.join();
	const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
	// report
	fs::create_directories(out);
	std::ofstream rep(out / "report.tsv");
	rep << "model\tok\tpieces\tcut\ttris_in\ttris_out\tverts_in\tverts_out\tcrossings\thidden\tlod_tris\ttexture\tcolour\toutline\tchanged\tlod_changed\tseconds\terror\n";
	size_t ti = 0, to = 0, vi = 0, vo = 0, ok = 0;
	for (const auto& r : results) {
		rep << r.rel << '\t' << r.ok << '\t' << r.pieces << '\t' << r.cut << '\t' << r.trisIn << '\t' << r.trisOut << '\t' << r.vertsIn << '\t'
			<< r.vertsOut << '\t' << r.crossings << '\t' << r.hidden << '\t' << r.lodTris << '\t' << r.tex << '\t' << r.colour << '\t' << r.outline << '\t' << r.changed << '\t' << r.lodChanged << '\t' << r.seconds << '\t' << r.error << '\n';
		if (!r.ok) { fprintf(stderr, "FAILED %s: %s\n", r.rel.c_str(), r.error.c_str()); continue; }
		++ok; ti += r.trisIn; to += r.trisOut; vi += r.vertsIn; vo += r.vertsOut;
	}
	if (Flag(argc, argv, "--verbose"))
		for (int k = 0; k < 24; ++k) printf("  %-16s %8ld %8ld\n", kReasons[k], gReasons[k].load(), gBlockers[k].load());
	printf("%zu of %zu models in %.1f s: triangles %zu -> %zu (%.1f %%), vertices %zu -> %zu (%.1f %%)\n", ok, results.size(), secs,
		ti, to, ti ? 100.0 * to / ti : 0.0, vi, vo, vi ? 100.0 * vo / vi : 0.0);
	return ok == results.size() ? 0 : 1;
}
