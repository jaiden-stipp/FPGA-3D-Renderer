#include "fpga_renderer/renderer.hpp"

#include <filesystem>
#include <iostream>

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
    const std::filesystem::path output = argc > 1 ? argv[1] : "scene.gfx";
    CommandStream commands;
    commands.setPalette(1, {255, 48, 48});
    commands.setPalette(2, {48, 255, 48});
    commands.setPalette(3, {48, 48, 255});
    commands.setPalette(4, {255, 255, 48});
    commands.setPalette(5, {255, 48, 255});
    commands.setPalette(6, {48, 255, 255});
    commands.setRotation(0);
    commands.beginFrame();
    commands.drawMesh(makeCube(), Mat4::scale(0.75F, 0.75F, 0.75F));
    commands.endFrame();
    commands.save(output);
    std::cout << "Wrote " << commands.bytes().size() << " bytes to " << output << '\n';
}
