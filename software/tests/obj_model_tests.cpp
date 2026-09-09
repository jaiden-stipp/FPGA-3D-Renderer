#include "fpga_renderer/obj_model.hpp"

#include <cmath>
#include <sstream>
#include <stdexcept>
#include <string>

using namespace fpga_renderer;

namespace {

void require(bool condition, const std::string& message) {
    if (!condition)
        throw std::runtime_error(message);
}

void testParsingAndTriangulation() {
    std::istringstream input(
        "# quad with texture and normal fields\n"
        "v 10 0 0\n"
        "v 12 0 0\n"
        "v 12 2 0\n"
        "v 10 2 0\n"
        "f 1/4/7 2/5/7 3/6/7 4/7/7\n");
    const IndexedModel model = parseObj(input, "quad.obj");
    require(model.vertices.size() == 4, "OBJ vertex count is wrong");
    require(model.faces.size() == 2, "quad was not triangulated");
    require(model.faces[0][0] == 0 && model.faces[0][1] == 1 &&
            model.faces[0][2] == 2, "first triangle changed winding");
    require(model.faces[1][0] == 0 && model.faces[1][1] == 2 &&
            model.faces[1][2] == 3, "second triangle changed winding");
}

void testNegativeIndices() {
    std::istringstream input(
        "v 0 0 0\n"
        "v 1 0 0\n"
        "v 0 1 0\n"
        "f -3//1 -2//1 -1//1\n");
    const IndexedModel model = parseObj(input);
    require(model.faces[0][0] == 0 && model.faces[0][1] == 1 &&
            model.faces[0][2] == 2, "negative OBJ indices were resolved incorrectly");
}

void testNormalization() {
    IndexedModel model;
    model.vertices = {{10.0F, 20.0F, 30.0F},
                      {14.0F, 22.0F, 32.0F},
                      {10.0F, 24.0F, 34.0F}};
    model.faces.push_back({0, 1, 2});
    const ModelNormalization result = normalizeModel(model, 2.0F);
    require(std::abs(result.center.x - 12.0F) < 0.0001F &&
            std::abs(result.center.y - 22.0F) < 0.0001F &&
            std::abs(result.center.z - 32.0F) < 0.0001F,
            "normalization center is wrong");
    require(std::abs(result.scale - 0.5F) < 0.0001F,
            "normalization scale is wrong");
}

void testChunkLimits() {
    IndexedModel vertexLimited;
    for (std::size_t index = 0; index < 130; ++index)
        vertexLimited.vertices.push_back(
            {static_cast<float>(index) * 0.01F, 0.0F, 0.0F});
    for (std::size_t index = 1; index + 1 < 130; ++index)
        vertexLimited.faces.push_back({0, index, index + 1});
    const auto vertexChunks = buildMeshChunks(vertexLimited);
    require(vertexChunks.size() == 2, "vertex-limited model was not split");

    IndexedModel triangleLimited;
    triangleLimited.vertices = {{0, 0, 0}, {1, 0, 0}, {0, 1, 0}};
    for (int index = 0; index < 257; ++index)
        triangleLimited.faces.push_back({0, 1, 2});
    const auto triangleChunks = buildMeshChunks(triangleLimited);
    require(triangleChunks.size() == 2, "triangle-limited model was not split");
    require(triangleChunks[0].triangles().size() == 256 &&
            triangleChunks[1].triangles().size() == 1,
            "triangle chunks have the wrong sizes");

    for (std::size_t handle = 0; handle < vertexChunks.size(); ++handle) {
        CommandStream upload;
        upload.uploadMesh(static_cast<std::uint8_t>(handle), vertexChunks[handle]);
        require(!upload.bytes().empty(), "chunk did not encode as a mesh upload");
    }
}

void testInvalidIndex() {
    std::istringstream input("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 0\n");
    bool rejected = false;
    try {
        static_cast<void>(parseObj(input, "bad.obj"));
    } catch (const std::runtime_error&) {
        rejected = true;
    }
    require(rejected, "zero OBJ index was accepted");
}

void testSimplification() {
    IndexedModel model;
    constexpr std::size_t columns = 20;
    constexpr std::size_t rows = 20;
    for (std::size_t row = 0; row <= rows; ++row) {
        for (std::size_t column = 0; column <= columns; ++column) {
            model.vertices.push_back({column * 0.002F, row * 0.002F,
                                      0.001F * static_cast<float>((row + column) % 2)});
        }
    }
    for (std::size_t row = 0; row < rows; ++row) {
        for (std::size_t column = 0; column < columns; ++column) {
            const std::size_t lowerLeft = row * (columns + 1) + column;
            const std::size_t lowerRight = lowerLeft + 1;
            const std::size_t upperLeft = lowerLeft + columns + 1;
            const std::size_t upperRight = upperLeft + 1;
            model.faces.push_back({lowerLeft, upperLeft, upperRight});
            model.faces.push_back({lowerLeft, upperRight, lowerRight});
        }
    }
    const ModelSimplification result = simplifyModelToFit(model, 1);
    require(result.clusterSize > 0.0F, "oversized model was not simplified");
    require(!model.faces.empty(), "simplification removed every face");
    require(buildMeshChunks(model).size() == 1,
            "simplified model still exceeds its handle limit");
}

}

int main() {
    testParsingAndTriangulation();
    testNegativeIndices();
    testNormalization();
    testChunkLimits();
    testInvalidIndex();
    testSimplification();
}
