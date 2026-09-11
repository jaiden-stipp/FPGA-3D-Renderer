#include "fpga_renderer/renderer.hpp"

#include <chrono>
#include <cstdint>
#include <iostream>
#include <string>

using namespace fpga_renderer;

namespace {

void addQuad(Mesh& mesh, Vec3 a, Vec3 b, Vec3 c, Vec3 d, std::uint8_t color) {
    mesh.addTriangle({a, b, c, color});
    mesh.addTriangle({a, c, d, color});
}

Mesh makeCube() {
    Mesh cube;
    addQuad(cube, {-1, -1, -1}, {1, -1, -1}, {1, 1, -1}, {-1, 1, -1}, 1);
    addQuad(cube, {-1, -1, 1}, {-1, 1, 1}, {1, 1, 1}, {1, -1, 1}, 2);
    addQuad(cube, {-1, -1, -1}, {-1, 1, -1}, {-1, 1, 1}, {-1, -1, 1}, 3);
    addQuad(cube, {1, -1, -1}, {1, -1, 1}, {1, 1, 1}, {1, 1, -1}, 4);
    addQuad(cube, {-1, 1, -1}, {1, 1, -1}, {1, 1, 1}, {-1, 1, 1}, 5);
    addQuad(cube, {-1, -1, -1}, {-1, -1, 1}, {1, -1, 1}, {1, -1, -1}, 6);
    return cube;
}

}

int main(int argc, char** argv) {
    try {
        const std::string address = argc > 1 ? argv[1] : "192.168.7.2";
        const auto port = static_cast<std::uint16_t>(argc > 2 ? std::stoul(argv[2]) : 4000);

        CommandStream commands;
        commands.setPalette(1, {255, 48, 48});
        commands.setPalette(2, {48, 255, 48});
        commands.setPalette(3, {48, 48, 255});
        commands.setPalette(4, {255, 255, 48});
        commands.setPalette(5, {255, 48, 255});
        commands.setPalette(6, {48, 255, 255});
        constexpr float pi = 3.14159265358979323846F;
        constexpr float defaultViewPitch = -20.0F * 2.0F * pi / 256.0F;
        commands.setViewMatrix(Mat4::translation(0.0F, 0.0F, 5.0F) *
                               Mat4::rotationX(defaultViewPitch));
        commands.setProjection({});
        const auto frameId = static_cast<std::uint32_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
        commands.beginFrame(frameId);
        commands.drawMesh(makeCube(), Mat4::rotationY(24.0F * 2.0F * pi / 256.0F) *
                                      Mat4::scale(0.65F, 0.65F, 0.65F));
        commands.endFrame();
        RendererClient renderer(address, port);
        const FrameResult status = renderer.submit(commands);

        std::cout << "Displayed frame " << status.frameId << " after sending "
                  << commands.bytes().size() << " command bytes to " << address << ':'
                  << port << "; FIFO free: " << status.fifoFree << ", flags: 0x"
                  << std::hex << status.flags << std::dec << '\n'
                  << formatFrameStatistics(status.statistics) << '\n';
    } catch (const std::exception& error) {
        std::cerr << "Error: " << error.what() << '\n';
        return 1;
    }
}
