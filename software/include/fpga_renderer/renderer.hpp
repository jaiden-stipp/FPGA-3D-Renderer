#pragma once

#include "fpga_renderer/protocol_generated.hpp"

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace fpga_renderer {

using Opcode = protocol::Opcode;

using StatusEvent = protocol::StatusEvent;
inline constexpr std::uint32_t StatusAccepted = protocol::statusAccepted;
inline constexpr std::uint32_t StatusDuplicate = protocol::statusDuplicate;
inline constexpr std::uint32_t StatusBusy = protocol::statusBusy;
inline constexpr std::uint32_t StatusSequenceError = protocol::statusSequenceError;
inline constexpr std::uint32_t StatusMalformed = protocol::statusMalformed;
inline constexpr std::uint32_t StatusOverflow = protocol::statusOverflow;
inline constexpr std::uint32_t StatusDecoderError = protocol::statusDecoderError;
inline constexpr std::uint32_t StatusCommandError = protocol::statusCommandError;
inline constexpr std::uint32_t StatusReceiveOverflow = protocol::statusReceiveOverflow;

struct FrameStatistics {
    std::uint32_t trianglesSubmitted = 0;
    std::uint32_t trianglesClipped = 0;
    std::uint32_t trianglesCulled = 0;
    std::uint32_t boundingBoxPixels = 0;
    std::uint32_t pixelsInside = 0;
    std::uint32_t depthRejected = 0;
    std::uint32_t pixelsWritten = 0;
    std::uint32_t geometryCycles = 0;
    std::uint32_t geometryStallCycles = 0;
    std::uint32_t rasterCycles = 0;
    std::uint32_t clearCycles = 0;
    std::uint32_t totalCycles = 0;
    std::uint32_t swapWaitCycles = 0;
};

struct PacketAcknowledgement {
    std::uint32_t submissionId = 0;
    std::uint16_t sequence = 0;
    std::uint16_t fifoFree = 0;
    std::uint32_t flags = 0;
};

struct FrameResult {
    std::uint32_t frameId = 0;
    std::uint16_t fifoFree = 0;
    std::uint32_t flags = 0;
    FrameStatistics statistics;
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

struct Projection {
    std::int16_t focalX = 256;
    std::int16_t focalY = 256;
    std::int16_t centerX = 160;
    std::int16_t centerY = 120;
    float nearPlane = 2.0F;
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
    void reserve(std::size_t triangleCount);
    void addTriangle(const Triangle& triangle);
    const std::vector<Triangle>& triangles() const;

private:
    std::vector<Triangle> triangles_;
};

class CommandStream {
public:
    void clear();
    void setViewMatrix(const Mat4& view);
    void setProjection(const Projection& projection);
    void setPalette(std::uint8_t index, Rgb color);
    void uploadMesh(std::uint8_t handle, const Mesh& mesh);
    void beginFrame(std::uint32_t frameId);
    void drawTriangle(const Triangle& triangle);
    void drawMesh(const Mesh& mesh, const Mat4& transform = Mat4::identity());
    void drawMesh(std::uint8_t handle,
                  const Mat4& transform = Mat4::identity());
    void endFrame();
    const std::vector<std::uint8_t>& bytes() const;
    std::uint32_t frameId() const;
    void save(const std::filesystem::path& path) const;

private:
    void append(Opcode opcode, const std::vector<std::uint8_t>& payload);
    std::vector<std::uint8_t> bytes_;
    bool frame_open_ = false;
    bool has_frame_id_ = false;
    std::uint32_t frame_id_ = 0;
};

struct TransportOptions {
    std::string host;
    std::uint16_t port = protocol::defaultUdpPort;
    std::chrono::milliseconds packetTimeout{300};
    std::chrono::milliseconds frameTimeout{30000};
    unsigned packetAttempts = 8;
};

class RendererClient {
public:
    explicit RendererClient(TransportOptions options);
    RendererClient(std::string host,
                   std::uint16_t port = protocol::defaultUdpPort);
    ~RendererClient();
    RendererClient(RendererClient&&) noexcept;
    RendererClient& operator=(RendererClient&&) noexcept;
    RendererClient(const RendererClient&) = delete;
    RendererClient& operator=(const RendererClient&) = delete;

    FrameResult submit(const CommandStream& commands);
    PacketAcknowledgement uploadMesh(std::uint8_t handle, const Mesh& mesh);
    FrameResult drawMesh(std::uint32_t frameId, std::uint8_t handle,
                         const Mat4& transform = Mat4::identity());

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

std::int16_t toQ8_8(float value);
std::uint16_t crc16Ccitt(const std::uint8_t* data, std::size_t size);
std::string formatFrameStatistics(const FrameStatistics& statistics);

}
