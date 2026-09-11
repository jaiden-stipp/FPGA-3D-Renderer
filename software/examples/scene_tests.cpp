#include "fpga_renderer/renderer.hpp"

#include <chrono>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

using namespace fpga_renderer;

namespace {

constexpr float pi = 3.14159265358979323846F;
constexpr float defaultViewPitch = -20.0F * 2.0F * pi / 256.0F;

void configureCamera(CommandStream& commands) {
    commands.setViewMatrix(Mat4::translation(0.0F, 0.0F, 5.0F) *
                           Mat4::rotationX(defaultViewPitch));
    commands.setProjection({});
}

void setTestPalette(CommandStream& commands) {
    const Rgb colors[] = {
        {255, 48, 48}, {48, 255, 96}, {48, 96, 255}, {255, 224, 32},
        {255, 48, 224}, {32, 224, 255}, {255, 128, 32}, {160, 64, 255},
        {96, 255, 224}, {255, 96, 144}, {144, 255, 64}, {80, 144, 255},
        {255, 192, 96}, {192, 96, 255}, {96, 255, 160}, {240, 240, 240}
    };
    for (std::uint8_t index = 0; index < 16; ++index)
        commands.setPalette(static_cast<std::uint8_t>(index + 1), colors[index]);
}

void addFrontQuad(Mesh& mesh, float left, float bottom, float right, float top,
                  float z, std::uint8_t color) {
    const Vec3 lowerLeft{left, bottom, z};
    const Vec3 upperLeft{left, top, z};
    const Vec3 upperRight{right, top, z};
    const Vec3 lowerRight{right, bottom, z};
    mesh.addTriangle({lowerLeft, upperLeft, upperRight, color});
    mesh.addTriangle({lowerLeft, upperRight, lowerRight, color});
}

Mesh makeCube() {
    Mesh cube;
    cube.addTriangle({{-1, -1, -1}, {1, 1, -1}, {1, -1, -1}, 1});
    cube.addTriangle({{-1, -1, -1}, {-1, 1, -1}, {1, 1, -1}, 1});
    cube.addTriangle({{-1, -1, 1}, {1, -1, 1}, {1, 1, 1}, 2});
    cube.addTriangle({{-1, -1, 1}, {1, 1, 1}, {-1, 1, 1}, 2});
    cube.addTriangle({{1, -1, -1}, {1, 1, -1}, {1, 1, 1}, 3});
    cube.addTriangle({{1, -1, -1}, {1, 1, 1}, {1, -1, 1}, 3});
    cube.addTriangle({{-1, -1, -1}, {-1, -1, 1}, {-1, 1, 1}, 4});
    cube.addTriangle({{-1, -1, -1}, {-1, 1, 1}, {-1, 1, -1}, 4});
    cube.addTriangle({{-1, -1, -1}, {1, -1, -1}, {1, -1, 1}, 5});
    cube.addTriangle({{-1, -1, -1}, {1, -1, 1}, {-1, -1, 1}, 5});
    cube.addTriangle({{-1, 1, -1}, {-1, 1, 1}, {1, 1, 1}, 6});
    cube.addTriangle({{-1, 1, -1}, {1, 1, 1}, {1, 1, -1}, 6});
    return cube;
}

CommandStream makePaletteTest(std::uint32_t frameId) {
    CommandStream commands;
    setTestPalette(commands);
    configureCamera(commands);
    commands.beginFrame(frameId);
    Mesh tiles;
    for (int row = 0; row < 4; ++row) {
        for (int column = 0; column < 4; ++column) {
            const float left = -2.8F + column * 1.4F;
            const float bottom = 1.8F - row * 0.9F;
            addFrontQuad(tiles, left, bottom - 0.72F, left + 1.12F, bottom,
                         0.0F, static_cast<std::uint8_t>(row * 4 + column + 1));
        }
    }
    commands.drawMesh(tiles);
    commands.endFrame();
    return commands;
}

CommandStream makeDepthTest(std::uint32_t frameId) {
    CommandStream commands;
    setTestPalette(commands);
    configureCamera(commands);
    commands.beginFrame(frameId);
    commands.drawTriangle({{-1.25F, -0.8F, -1.2F}, {0.0F, 1.3F, -1.2F},
                           {1.25F, -0.8F, -1.2F}, 4});
    commands.drawTriangle({{-2.0F, -1.25F, 0.0F}, {0.0F, 1.9F, 0.0F},
                           {2.0F, -1.25F, 0.0F}, 1});
    commands.drawTriangle({{-2.8F, -1.75F, 1.2F}, {0.0F, 2.35F, 1.2F},
                           {2.8F, -1.75F, 1.2F}, 3});
    commands.endFrame();
    return commands;
}

CommandStream makeClippingTest(std::uint32_t frameId) {
    CommandStream commands;
    setTestPalette(commands);
    configureCamera(commands);
    commands.beginFrame(frameId);
    commands.drawTriangle({{-7.0F, -2.4F, 0.8F}, {0.0F, 3.8F, 0.8F},
                           {7.0F, -2.4F, 0.8F}, 8});
    commands.drawTriangle({{-3.0F, -1.4F, -0.2F}, {0.0F, 2.4F, -4.2F},
                           {3.0F, -1.4F, -0.2F}, 2});
    commands.drawTriangle({{-6.0F, -2.0F, -0.8F}, {-4.0F, 2.2F, -0.8F},
                           {-0.4F, -1.0F, -0.8F}, 4});
    commands.drawTriangle({{0.4F, -1.0F, -0.6F}, {4.0F, 2.2F, -0.6F},
                           {6.0F, -2.0F, -0.6F}, 5});
    commands.endFrame();
    return commands;
}

CommandStream makeStressTest(std::uint32_t frameId) {
    CommandStream commands;
    setTestPalette(commands);
    configureCamera(commands);
    commands.beginFrame(frameId);
    Mesh surface;
    constexpr int columns = 16;
    constexpr int rows = 10;
    constexpr float width = 6.4F;
    constexpr float height = 4.0F;
    for (int row = 0; row < rows; ++row) {
        for (int column = 0; column < columns; ++column) {
            const float x0 = -width / 2.0F + width * column / columns;
            const float x1 = -width / 2.0F + width * (column + 1) / columns;
            const float y0 = -height / 2.0F + height * row / rows;
            const float y1 = -height / 2.0F + height * (row + 1) / rows;
            const float z00 = 0.32F * std::sin(column * 0.55F + row * 0.35F);
            const float z01 = 0.32F * std::sin(column * 0.55F + (row + 1) * 0.35F);
            const float z11 = 0.32F * std::sin((column + 1) * 0.55F +
                                               (row + 1) * 0.35F);
            const float z10 = 0.32F * std::sin((column + 1) * 0.55F + row * 0.35F);
            const auto color = static_cast<std::uint8_t>(1 + (row + column) % 16);
            surface.addTriangle({{x0, y0, z00}, {x0, y1, z01},
                                 {x1, y1, z11}, color});
            surface.addTriangle({{x0, y0, z00}, {x1, y1, z11},
                                 {x1, y0, z10}, color});
        }
    }
    commands.drawMesh(surface);
    commands.endFrame();
    return commands;
}

CommandStream makeOrbitFrame(std::uint32_t frameId, float phase) {
    CommandStream commands;
    setTestPalette(commands);
    configureCamera(commands);
    commands.beginFrame(frameId);
    const Mat4 center = Mat4::rotationY(phase) * Mat4::rotationX(phase * 0.45F) *
                        Mat4::scale(0.62F, 0.62F, 0.62F);
    const Mat4 leftOrbit = Mat4::rotationY(phase) * Mat4::translation(2.1F, 0.0F, 0.0F) *
                           Mat4::rotationX(-phase * 1.7F) *
                           Mat4::scale(0.28F, 0.28F, 0.28F);
    const Mat4 rightOrbit = Mat4::rotationY(-phase * 1.45F) *
                            Mat4::translation(-2.35F, 0.25F, 0.0F) *
                            Mat4::rotationZ(phase * 1.2F) *
                            Mat4::scale(0.22F, 0.22F, 0.22F);
    commands.drawMesh(0, center);
    commands.drawMesh(0, leftOrbit);
    commands.drawMesh(0, rightOrbit);
    commands.endFrame();
    return commands;
}

void submitAndReport(RendererClient& renderer, const std::string& name,
                     const CommandStream& commands) {
    constexpr std::size_t chunkBytes = protocol::maximumDatagramBytes -
                                       protocol::transportHeaderBytes;
    const std::size_t packets = (commands.bytes().size() + chunkBytes - 1) /
                                chunkBytes;
    const auto start = std::chrono::steady_clock::now();
    const FrameResult status = renderer.submit(commands);
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start);
    std::cout << name << ": frame " << status.frameId << ", "
              << commands.bytes().size() << " command bytes, " << packets
              << " packet(s), " << elapsed.count() << " ms, FIFO free "
              << status.fifoFree << ", flags 0x" << std::hex << status.flags
              << std::dec << '\n' << "  "
              << formatFrameStatistics(status.statistics) << '\n';
    if (status.flags != 0)
        throw std::runtime_error(name + " returned an FPGA error status");
}

void printUsage(const char* executable) {
    std::cout << "Usage: " << executable
              << " <palette|depth|clipping|stress|orbit|all> [address] [port] [frames]\n";
}

}

int main(int argc, char** argv) {
    try {
        const std::string test = argc > 1 ? argv[1] : "all";
        const std::string address = argc > 2 ? argv[2] : "192.168.7.2";
        const auto port = static_cast<std::uint16_t>(argc > 3 ? std::stoul(argv[3]) : 4000);
        const int animationFrames = argc > 4 ? std::stoi(argv[4]) : 180;
        if (animationFrames < 1)
            throw std::invalid_argument("frame count must be positive");

        RendererClient renderer(address, port);
        std::uint32_t frameId = static_cast<std::uint32_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
        if (test == "palette" || test == "all") {
            submitAndReport(renderer, "palette", makePaletteTest(frameId++));
            if (test == "all")
                std::this_thread::sleep_for(std::chrono::seconds(2));
        }
        if (test == "depth" || test == "all") {
            submitAndReport(renderer, "depth", makeDepthTest(frameId++));
            if (test == "all")
                std::this_thread::sleep_for(std::chrono::seconds(2));
        }
        if (test == "clipping" || test == "all") {
            submitAndReport(renderer, "clipping", makeClippingTest(frameId++));
            if (test == "all")
                std::this_thread::sleep_for(std::chrono::seconds(2));
        }
        if (test == "stress" || test == "all") {
            submitAndReport(renderer, "stress", makeStressTest(frameId++));
            if (test == "all")
                std::this_thread::sleep_for(std::chrono::seconds(2));
        }
        if (test == "orbit" || test == "all") {
            const PacketAcknowledgement upload = renderer.uploadMesh(0, makeCube());
            std::cout << "uploaded cube mesh as handle 0; FIFO free "
                      << upload.fifoFree << ", flags 0x" << std::hex
                      << upload.flags << std::dec << '\n';
            if ((upload.flags & StatusAccepted) == 0 ||
                (upload.flags & ~(StatusAccepted | StatusDuplicate)) != 0)
                throw std::runtime_error("cube mesh upload was rejected");
            for (int frame = 0; frame < animationFrames; ++frame) {
                const float phase = 2.0F * pi * frame / 180.0F;
                submitAndReport(renderer, "orbit", makeOrbitFrame(frameId++, phase));
            }
        } else if (test != "palette" && test != "depth" && test != "clipping" &&
                   test != "stress") {
            printUsage(argv[0]);
            return 2;
        }
    } catch (const std::exception& error) {
        std::cerr << "Error: " << error.what() << '\n';
        return 1;
    }
}
