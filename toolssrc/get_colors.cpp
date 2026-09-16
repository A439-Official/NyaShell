#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <random>
#include <algorithm>
#include <limits>

struct Color
{
    float r, g, b;
};

static inline float dist2(const Color &a, const Color &b)
{
    float dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b;
    return dr * dr + dg * dg + db * db;
}

static unsigned char *resize_rgb(const unsigned char *src, int sw, int sh, int *dw, int *dh)
{
    float ratio = 1.0f;
    if (sw > 640 || sh > 360)
        ratio = std::min(640.0f / sw, 360.0f / sh);

    int w = std::max(1, (int)std::round(sw * ratio));
    int h = std::max(1, (int)std::round(sh * ratio));

    unsigned char *dst = (unsigned char *)std::malloc((size_t)w * h * 3);
    if (!dst)
        return nullptr;

    for (int y = 0; y < h; ++y)
    {
        float sy = (y + 0.5f) * sh / h - 0.5f;
        int y0 = (int)std::floor(sy);
        int y1 = y0 + 1;
        float fy = sy - y0;
        if (y0 < 0)
        {
            y0 = 0;
            fy = 0.0f;
        }
        if (y1 >= sh)
        {
            y1 = sh - 1;
            fy = 0.0f;
        }

        for (int x = 0; x < w; ++x)
        {
            float sx = (x + 0.5f) * sw / w - 0.5f;
            int x0 = (int)std::floor(sx);
            int x1 = x0 + 1;
            float fx = sx - x0;
            if (x0 < 0)
            {
                x0 = 0;
                fx = 0.0f;
            }
            if (x1 >= sw)
            {
                x1 = sw - 1;
                fx = 0.0f;
            }

            for (int c = 0; c < 3; ++c)
            {
                float v00 = src[((size_t)y0 * sw + x0) * 3 + c];
                float v01 = src[((size_t)y0 * sw + x1) * 3 + c];
                float v10 = src[((size_t)y1 * sw + x0) * 3 + c];
                float v11 = src[((size_t)y1 * sw + x1) * 3 + c];
                float v0 = v00 * (1.0f - fx) + v01 * fx;
                float v1 = v10 * (1.0f - fx) + v11 * fx;
                float v = v0 * (1.0f - fy) + v1 * fy;
                int iv = (int)std::round(v);
                if (iv < 0)
                    iv = 0;
                if (iv > 255)
                    iv = 255;
                dst[((size_t)y * w + x) * 3 + c] = (unsigned char)iv;
            }
        }
    }

    *dw = w;
    *dh = h;
    return dst;
}

static void kmeans_plus_plus(const std::vector<Color> &pts, int k,
                             std::mt19937 &rng, std::vector<Color> &cent)
{
    std::uniform_int_distribution<size_t> pick(0, pts.size() - 1);
    cent[0] = pts[pick(rng)];

    std::vector<float> d2(pts.size(), 0.0f);
    for (int c = 1; c < k; ++c)
    {
        double sum = 0.0;
        for (size_t i = 0; i < pts.size(); ++i)
        {
            float best = dist2(pts[i], cent[c - 1]);
            if (c > 1 && d2[i] < best)
                best = d2[i];
            d2[i] = best;
            sum += best;
        }

        if (sum <= 0.0)
        {
            cent[c] = pts[pick(rng)];
            continue;
        }

        std::uniform_real_distribution<double> dist(0.0, sum);
        double target = dist(rng);
        double acc = 0.0;
        size_t idx = 0;
        for (size_t i = 0; i < pts.size(); ++i)
        {
            acc += d2[i];
            if (acc >= target)
            {
                idx = i;
                break;
            }
        }
        cent[c] = pts[idx];
    }
}

static double kmeans_run(const std::vector<Color> &pts, int k,
                         std::mt19937 &rng, std::vector<Color> &cent)
{
    kmeans_plus_plus(pts, k, rng, cent);

    std::vector<int> label(pts.size());
    std::vector<double> sr(k), sg(k), sb(k);
    std::vector<long long> cnt(k);

    const int MAX_ITER = 300;
    const double TOL = 1e-4;

    for (int iter = 0; iter < MAX_ITER; ++iter)
    {
        std::fill(sr.begin(), sr.end(), 0.0);
        std::fill(sg.begin(), sg.end(), 0.0);
        std::fill(sb.begin(), sb.end(), 0.0);
        std::fill(cnt.begin(), cnt.end(), 0);

        for (size_t i = 0; i < pts.size(); ++i)
        {
            int best = 0;
            float bd = dist2(pts[i], cent[0]);
            for (int c = 1; c < k; ++c)
            {
                float d = dist2(pts[i], cent[c]);
                if (d < bd)
                {
                    bd = d;
                    best = c;
                }
            }
            label[i] = best;
            sr[best] += pts[i].r;
            sg[best] += pts[i].g;
            sb[best] += pts[i].b;
            ++cnt[best];
        }

        double shift = 0.0;
        for (int c = 0; c < k; ++c)
        {
            Color nc;
            if (cnt[c] == 0)
            {
                std::uniform_int_distribution<size_t> pick(0, pts.size() - 1);
                nc = pts[pick(rng)];
            }
            else
            {
                nc = {(float)(sr[c] / cnt[c]),
                      (float)(sg[c] / cnt[c]),
                      (float)(sb[c] / cnt[c])};
            }
            shift += dist2(nc, cent[c]);
            cent[c] = nc;
        }
        if (std::sqrt(shift) < TOL)
            break;
    }

    double inertia = 0.0;
    for (size_t i = 0; i < pts.size(); ++i)
    {
        float bd = dist2(pts[i], cent[0]);
        for (int c = 1; c < k; ++c)
        {
            float d = dist2(pts[i], cent[c]);
            if (d < bd)
                bd = d;
        }
        inertia += bd;
    }
    return inertia;
}

int main(int argc, char **argv)
{
    if (argc < 3)
    {
        printf("Usage: get_colors.exe <image_path> <color_count>\n");
        printf("Example: get_colors.exe photo.jpg 5\n");
        return 1;
    }

    const char *path = argv[1];
    int k = atoi(argv[2]);
    if (k <= 0)
    {
        printf("Error: color_count must be a positive integer.\n");
        return 1;
    }
    if (k > 64)
        k = 64;

    int w = 0, h = 0, comp = 0;
    unsigned char *data = stbi_load(path, &w, &h, &comp, 3);
    if (!data)
    {
        printf("Error: failed to load image '%s': %s\n", path, stbi_failure_reason());
        return 1;
    }

    int rw = 0, rh = 0;
    unsigned char *resized = resize_rgb(data, w, h, &rw, &rh);
    stbi_image_free(data);
    if (!resized)
    {
        printf("Error: resize failed.\n");
        return 1;
    }

    std::vector<Color> pts;
    pts.reserve((size_t)rw * rh);
    for (int y = 0; y < rh; ++y)
    {
        for (int x = 0; x < rw; ++x)
        {
            const unsigned char *p = resized + ((size_t)y * rw + x) * 3;
            pts.push_back({(float)p[0], (float)p[1], (float)p[2]});
        }
    }
    std::free(resized);

    if (pts.empty())
    {
        printf("Error: no valid pixel found.\n");
        return 1;
    }
    if ((int)pts.size() < k)
        k = (int)pts.size();

    std::vector<Color> best_cent(k);
    double best_inertia = std::numeric_limits<double>::max();
    std::mt19937 rng(42);
    const int N_INIT = 20;

    for (int run = 0; run < N_INIT; ++run)
    {
        std::vector<Color> cent(k);
        std::mt19937 run_rng(rng());
        double inertia = kmeans_run(pts, k, run_rng, cent);
        if (inertia < best_inertia)
        {
            best_inertia = inertia;
            best_cent = cent;
        }
    }

    struct FinalColor
    {
        int r, g, b;
        float lum;
    };

    std::vector<FinalColor> colors;
    colors.reserve(k);
    for (int i = 0; i < k; ++i)
    {
        int R = (int)best_cent[i].r;
        int G = (int)best_cent[i].g;
        int B = (int)best_cent[i].b;
        if (R < 0)
            R = 0;
        if (R > 255)
            R = 255;
        if (G < 0)
            G = 0;
        if (G > 255)
            G = 255;
        if (B < 0)
            B = 0;
        if (B > 255)
            B = 255;
        float lum = 0.299f * R + 0.587f * G + 0.114f * B;
        colors.push_back({R, G, B, lum});
    }

    std::sort(colors.begin(), colors.end(),
              [](const FinalColor &a, const FinalColor &b)
              { return a.lum > b.lum; });

    for (const auto &c : colors)
    {
        printf("#%02X%02X%02X\n", c.r, c.g, c.b);
    }

    return 0;
}