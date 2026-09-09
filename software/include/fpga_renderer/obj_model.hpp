#pragma once

#include "fpga_renderer/renderer.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <istream>
#include <string>
#include <vector>

namespace fpga_renderer {

struct IndexedModel {
    std::vector<Vec3> vertices;
    std::vector<std::array<std::size_t, 3>> faces;
};

struct ModelNormalization {
    Vec3 center;
    float scale;
};

struct ModelSimplification {
    std::size_t originalVertices;
    std::size_t originalFaces;
    std::size_t simplifiedVertices;
    std::size_t simplifiedFaces;
    float clusterSize;
};

IndexedModel parseObj(std::istream& input,
                      const std::string& sourceName = "OBJ stream");
IndexedModel loadObj(const std::filesystem::path& path);
ModelNormalization normalizeModel(IndexedModel& model,
                                   float largestDimension = 2.0F);
ModelSimplification simplifyModelToFit(IndexedModel& model,
                                       std::size_t maximumHandles = 16);
std::vector<Mesh> buildMeshChunks(const IndexedModel& model,
                                  std::uint8_t firstColor = 1,
                                  std::uint8_t colorCount = 16);

}
