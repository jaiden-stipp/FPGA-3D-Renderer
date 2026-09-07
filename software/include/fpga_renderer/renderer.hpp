#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace fpga_renderer {

enum class Opcode : std::uint8_t {
    SetRotation = 0,
    BeginFrame = 1,
    DrawTriangle = 2,
    EndFrame = 3,
    SetPalette = 4
};

struct Vec3 {
    float x;
    float y;
    float z;
};

struct Rgb {
    std::uint8_t red;
    std::uint8_t green;
    std::uint8_t blue;
};

struct Triangle {
    Vec3 v0;
    Vec3 v1;
    Vec3 v2;
    std::uint8_t color;
};

class Mat4 {
public:
    std::array<float, 16> values{};

    static Mat4 identity();
    static Mat4 translation(float x, float y, float z);
    static Mat4 scale(float x, float y, float z);
    static Mat4 rotationX(float radians);
    static Mat4 rotationY(float radians);
    static Mat4 rotationZ(float radians);

    Vec3 transformPoint(const Vec3& point) const;
};

Mat4 operator*(const Mat4& left, const Mat4& right);

class Mesh {
public:
    void addTriangle(const Triangle& triangle);
    const std::vector<Triangle>& triangles() const;

private:
    std::vector<Triangle> triangles_;
};

class CommandStream {
public:
    void clear();
    void setRotation(std::uint8_t angle);
    void setPalette(std::uint8_t index, Rgb color);
    void beginFrame();
    void drawTriangle(const Triangle& triangle);
    void drawMesh(const Mesh& mesh, const Mat4& transform = Mat4::identity());
    void endFrame();
    const std::vector<std::uint8_t>& bytes() const;
    void save(const std::filesystem::path& path) const;

private:
    void append(Opcode opcode, const std::vector<std::uint8_t>& payload);
    std::vector<std::uint8_t> bytes_;
    bool frame_open_ = false;
};

std::int16_t toQ8_8(float value);
std::uint16_t crc16Ccitt(const std::uint8_t* data, std::size_t size);
void sendUdp(const std::string& host, std::uint16_t port,
             const std::vector<std::uint8_t>& bytes);
void sendUdp(const std::string& host, std::uint16_t port,
             const CommandStream& commands);

}
