#pragma once

#include <cstddef>
#include <cstdint>

namespace fpga_renderer::protocol {

inline constexpr std::uint8_t transportVersion = 2;
inline constexpr std::uint8_t commandVersion = 2;
inline constexpr std::uint8_t statusVersion = 2;
inline constexpr std::size_t maximumDatagramBytes = 1400;
inline constexpr std::size_t transportHeaderBytes = 12;
inline constexpr std::size_t packetAcknowledgementBytes = 20;
inline constexpr std::size_t frameStatusBytes = 68;
inline constexpr std::size_t receiveFifoBytes = 2048;
inline constexpr std::size_t meshHandleCount = 16;
inline constexpr std::size_t verticesPerMesh = 128;
inline constexpr std::size_t trianglesPerMesh = 256;
inline constexpr std::uint32_t systemClockHz = 50000000;
inline constexpr std::size_t renderWidth = 320;
inline constexpr std::size_t renderHeight = 240;
inline constexpr std::size_t displayWidth = 640;
inline constexpr std::size_t displayHeight = 480;
inline constexpr std::uint16_t defaultUdpPort = 4000;
inline constexpr std::uint8_t commandMagic0 = 71;
inline constexpr std::uint8_t commandMagic1 = 70;
inline constexpr std::uint8_t transportMagic0 = 71;
inline constexpr std::uint8_t transportMagic1 = 80;
inline constexpr std::uint8_t statusMagic0 = 71;
inline constexpr std::uint8_t statusMagic1 = 83;

enum class StatusEvent : std::uint8_t {
    PacketAcknowledged = 1,
    FrameDisplayed = 2
};

inline constexpr std::uint32_t statusAccepted = 1;
inline constexpr std::uint32_t statusDuplicate = 2;
inline constexpr std::uint32_t statusBusy = 4;
inline constexpr std::uint32_t statusSequenceError = 8;
inline constexpr std::uint32_t statusMalformed = 16;
inline constexpr std::uint32_t statusOverflow = 32;
inline constexpr std::uint32_t statusDecoderError = 256;
inline constexpr std::uint32_t statusCommandError = 512;
inline constexpr std::uint32_t statusReceiveOverflow = 1024;

namespace payloadBytes {
inline constexpr std::size_t beginFrame = 4;
inline constexpr std::size_t drawTriangle = 19;
inline constexpr std::size_t endFrame = 0;
inline constexpr std::size_t setPalette = 4;
inline constexpr std::size_t defineMesh = 5;
inline constexpr std::size_t uploadVertex = 8;
inline constexpr std::size_t uploadIndex = 7;
inline constexpr std::size_t drawMesh = 25;
inline constexpr std::size_t setViewMatrix = 24;
inline constexpr std::size_t setProjection = 10;
}

enum class Opcode : std::uint8_t {
    BeginFrame = 1,
    DrawTriangle = 2,
    EndFrame = 3,
    SetPalette = 4,
    DefineMesh = 5,
    UploadVertex = 6,
    UploadIndex = 7,
    DrawMesh = 8,
    UploadVertices = 9,
    UploadIndices = 10,
    SetViewMatrix = 11,
    SetProjection = 12
};

}
