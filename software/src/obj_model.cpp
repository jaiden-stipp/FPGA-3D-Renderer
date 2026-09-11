#include "fpga_renderer/obj_model.hpp"

#include <algorithm>
#include <cmath>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <unordered_map>
#include <unordered_set>
#include <utility>

namespace fpga_renderer {

namespace {

constexpr std::size_t maximumVerticesPerMesh = protocol::verticesPerMesh;
constexpr std::size_t maximumTrianglesPerMesh = protocol::trianglesPerMesh;

struct GridPoint {
    long long x;
    long long y;
    long long z;

    bool operator==(const GridPoint& other) const {
        return x == other.x && y == other.y && z == other.z;
    }
};

struct GridPointHash {
    std::size_t operator()(const GridPoint& point) const {
        std::size_t value = std::hash<long long>{}(point.x);
        value ^= std::hash<long long>{}(point.y) + 0x9E3779B9U +
                 (value << 6) + (value >> 2);
        value ^= std::hash<long long>{}(point.z) + 0x9E3779B9U +
                 (value << 6) + (value >> 2);
        return value;
    }
};

struct FaceKeyHash {
    std::size_t operator()(const std::array<std::size_t, 3>& face) const {
        std::size_t value = std::hash<std::size_t>{}(face[0]);
        value ^= std::hash<std::size_t>{}(face[1]) + 0x9E3779B9U +
                 (value << 6) + (value >> 2);
        value ^= std::hash<std::size_t>{}(face[2]) + 0x9E3779B9U +
                 (value << 6) + (value >> 2);
        return value;
    }
};

std::runtime_error parseError(const std::string& sourceName,
                              std::size_t lineNumber,
                              const std::string& message) {
    return std::runtime_error(sourceName + ":" + std::to_string(lineNumber) +
                              ": " + message);
}

std::size_t parseVertexReference(const std::string& token,
                                 std::size_t vertexCount,
                                 const std::string& sourceName,
                                 std::size_t lineNumber) {
    const std::string vertexPart = token.substr(0, token.find('/'));
    if (vertexPart.empty())
        throw parseError(sourceName, lineNumber, "face has no vertex index");

    std::size_t parsedCharacters = 0;
    long long index = 0;
    try {
        index = std::stoll(vertexPart, &parsedCharacters);
    } catch (const std::exception&) {
        throw parseError(sourceName, lineNumber,
                         "invalid face vertex index '" + vertexPart + "'");
    }
    if (parsedCharacters != vertexPart.size() || index == 0)
        throw parseError(sourceName, lineNumber,
                         "invalid face vertex index '" + vertexPart + "'");

    const long long resolved = index > 0
        ? index - 1
        : static_cast<long long>(vertexCount) + index;
    if (resolved < 0 || resolved >= static_cast<long long>(vertexCount))
        throw parseError(sourceName, lineNumber,
                         "face vertex index is outside the vertex list");
    return static_cast<std::size_t>(resolved);
}

IndexedModel clusterModel(const IndexedModel& source, float clusterSize) {
    std::unordered_map<GridPoint, std::size_t, GridPointHash> clusters;
    std::vector<std::array<double, 3>> sums;
    std::vector<std::size_t> counts;
    std::vector<std::size_t> remap(source.vertices.size());
    clusters.reserve(source.vertices.size());
    sums.reserve(source.vertices.size());
    counts.reserve(source.vertices.size());
    for (std::size_t index = 0; index < source.vertices.size(); ++index) {
        const Vec3& vertex = source.vertices[index];
        const GridPoint key{
            static_cast<long long>(std::llround(vertex.x / clusterSize)),
            static_cast<long long>(std::llround(vertex.y / clusterSize)),
            static_cast<long long>(std::llround(vertex.z / clusterSize))
        };
        const auto inserted = clusters.emplace(key, clusters.size());
        const std::size_t cluster = inserted.first->second;
        if (inserted.second) {
            sums.push_back({0.0, 0.0, 0.0});
            counts.push_back(0);
        }
        sums[cluster][0] += vertex.x;
        sums[cluster][1] += vertex.y;
        sums[cluster][2] += vertex.z;
        ++counts[cluster];
        remap[index] = cluster;
    }

    IndexedModel clustered;
    clustered.vertices.resize(sums.size());
    for (std::size_t index = 0; index < sums.size(); ++index) {
        clustered.vertices[index] = {
            static_cast<float>(sums[index][0] / counts[index]),
            static_cast<float>(sums[index][1] / counts[index]),
            static_cast<float>(sums[index][2] / counts[index])
        };
    }

    std::unordered_set<std::array<std::size_t, 3>, FaceKeyHash> uniqueFaces;
    uniqueFaces.reserve(source.faces.size());
    clustered.faces.reserve(source.faces.size());
    for (const auto& face : source.faces) {
        std::array<std::size_t, 3> mapped{
            remap[face[0]], remap[face[1]], remap[face[2]]
        };
        if (mapped[0] == mapped[1] || mapped[1] == mapped[2] ||
            mapped[0] == mapped[2])
            continue;

        std::array<std::size_t, 3> canonical = mapped;
        std::sort(canonical.begin(), canonical.end());
        if (!uniqueFaces.insert(canonical).second)
            continue;

        const Vec3& a = clustered.vertices[mapped[0]];
        const Vec3& b = clustered.vertices[mapped[1]];
        const Vec3& c = clustered.vertices[mapped[2]];
        const float abx = b.x - a.x;
        const float aby = b.y - a.y;
        const float abz = b.z - a.z;
        const float acx = c.x - a.x;
        const float acy = c.y - a.y;
        const float acz = c.z - a.z;
        const float crossX = aby * acz - abz * acy;
        const float crossY = abz * acx - abx * acz;
        const float crossZ = abx * acy - aby * acx;
        if (crossX * crossX + crossY * crossY + crossZ * crossZ < 1.0e-10F)
            continue;
        clustered.faces.push_back(mapped);
    }

    std::vector<bool> referenced(clustered.vertices.size(), false);
    for (const auto& face : clustered.faces) {
        referenced[face[0]] = true;
        referenced[face[1]] = true;
        referenced[face[2]] = true;
    }
    std::vector<std::size_t> compactRemap(clustered.vertices.size());
    IndexedModel compact;
    compact.vertices.reserve(clustered.vertices.size());
    for (std::size_t index = 0; index < clustered.vertices.size(); ++index) {
        if (referenced[index]) {
            compactRemap[index] = compact.vertices.size();
            compact.vertices.push_back(clustered.vertices[index]);
        }
    }
    compact.faces.reserve(clustered.faces.size());
    for (const auto& face : clustered.faces)
        compact.faces.push_back({compactRemap[face[0]], compactRemap[face[1]],
                                 compactRemap[face[2]]});
    return compact;
}

struct ChunkRange {
    std::size_t firstFace;
    std::size_t faceCount;
};

std::size_t countNewVertices(
    const std::array<std::size_t, 3>& face,
    const std::unordered_set<std::size_t>& currentVertices) {
    std::size_t count = 0;
    for (std::size_t position = 0; position < face.size(); ++position) {
        if (currentVertices.find(face[position]) != currentVertices.end())
            continue;
        bool repeatedInFace = false;
        for (std::size_t earlier = 0; earlier < position; ++earlier)
            repeatedInFace = repeatedInFace || face[earlier] == face[position];
        if (!repeatedInFace)
            ++count;
    }
    return count;
}

std::vector<ChunkRange> planMeshChunks(const IndexedModel& model) {
    if (model.vertices.empty() || model.faces.empty())
        throw std::invalid_argument("cannot build mesh chunks from an empty model");

    std::vector<ChunkRange> ranges;
    ranges.reserve((model.faces.size() + maximumTrianglesPerMesh - 1) /
                   maximumTrianglesPerMesh);
    std::unordered_set<std::size_t> currentVertices;
    currentVertices.reserve(maximumVerticesPerMesh);
    std::size_t firstFace = 0;
    std::size_t currentTriangleCount = 0;

    for (std::size_t faceNumber = 0; faceNumber < model.faces.size(); ++faceNumber) {
        const auto& face = model.faces[faceNumber];
        for (const std::size_t index : face) {
            if (index >= model.vertices.size())
                throw std::out_of_range("model face references a missing vertex");
        }

        const std::size_t additions = countNewVertices(face, currentVertices);
        if (currentTriangleCount != 0 &&
            (currentTriangleCount == maximumTrianglesPerMesh ||
             currentVertices.size() + additions > maximumVerticesPerMesh)) {
            ranges.push_back({firstFace, currentTriangleCount});
            firstFace = faceNumber;
            currentVertices.clear();
            currentTriangleCount = 0;
        }

        for (const std::size_t index : face)
            currentVertices.insert(index);
        ++currentTriangleCount;
    }

    if (currentTriangleCount != 0)
        ranges.push_back({firstFace, currentTriangleCount});
    return ranges;
}

}

IndexedModel parseObj(std::istream& input, const std::string& sourceName) {
    IndexedModel model;
    std::string line;
    std::size_t lineNumber = 0;
    while (std::getline(input, line)) {
        ++lineNumber;
        std::istringstream values(line);
        std::string keyword;
        if (!(values >> keyword) || keyword[0] == '#')
            continue;

        if (keyword == "v") {
            Vec3 vertex{};
            if (!(values >> vertex.x >> vertex.y >> vertex.z))
                throw parseError(sourceName, lineNumber,
                                 "vertex requires X, Y, and Z coordinates");
            if (!std::isfinite(vertex.x) || !std::isfinite(vertex.y) ||
                !std::isfinite(vertex.z))
                throw parseError(sourceName, lineNumber,
                                 "vertex coordinates must be finite");
            model.vertices.push_back(vertex);
        } else if (keyword == "f") {
            std::vector<std::size_t> polygon;
            std::string reference;
            while (values >> reference) {
                if (reference[0] == '#')
                    break;
                polygon.push_back(parseVertexReference(
                    reference, model.vertices.size(), sourceName, lineNumber));
            }
            if (polygon.size() < 3)
                throw parseError(sourceName, lineNumber,
                                 "face requires at least three vertices");
            for (std::size_t index = 1; index + 1 < polygon.size(); ++index)
                model.faces.push_back({polygon[0], polygon[index], polygon[index + 1]});
        }
    }

    if (!input.eof() && input.fail())
        throw std::runtime_error("could not read " + sourceName);
    if (model.vertices.empty())
        throw std::runtime_error(sourceName + " contains no vertices");
    if (model.faces.empty())
        throw std::runtime_error(sourceName + " contains no faces");
    return model;
}

IndexedModel loadObj(const std::filesystem::path& path) {
    std::ifstream input(path);
    if (!input)
        throw std::runtime_error("could not open OBJ file " + path.string());
    return parseObj(input, path.string());
}

ModelNormalization normalizeModel(IndexedModel& model, float largestDimension) {
    if (model.vertices.empty())
        throw std::invalid_argument("cannot normalize a model with no vertices");
    if (!std::isfinite(largestDimension) || largestDimension <= 0.0F)
        throw std::invalid_argument("normalized model size must be positive");

    Vec3 minimum = model.vertices.front();
    Vec3 maximum = model.vertices.front();
    for (const Vec3& vertex : model.vertices) {
        minimum.x = (std::min)(minimum.x, vertex.x);
        minimum.y = (std::min)(minimum.y, vertex.y);
        minimum.z = (std::min)(minimum.z, vertex.z);
        maximum.x = (std::max)(maximum.x, vertex.x);
        maximum.y = (std::max)(maximum.y, vertex.y);
        maximum.z = (std::max)(maximum.z, vertex.z);
    }

    const Vec3 center{
        (minimum.x + maximum.x) * 0.5F,
        (minimum.y + maximum.y) * 0.5F,
        (minimum.z + maximum.z) * 0.5F
    };
    const float sourceSize = (std::max)({maximum.x - minimum.x,
                                         maximum.y - minimum.y,
                                         maximum.z - minimum.z});
    if (sourceSize <= 0.0F || !std::isfinite(sourceSize))
        throw std::invalid_argument("cannot normalize a model with zero size");
    const float scale = largestDimension / sourceSize;
    for (Vec3& vertex : model.vertices) {
        vertex.x = (vertex.x - center.x) * scale;
        vertex.y = (vertex.y - center.y) * scale;
        vertex.z = (vertex.z - center.z) * scale;
    }
    return {center, scale};
}

ModelSimplification simplifyModelToFit(IndexedModel& model,
                                       std::size_t maximumHandles) {
    if (maximumHandles == 0)
        throw std::invalid_argument("maximum mesh handle count must be positive");
    const std::size_t originalVertices = model.vertices.size();
    const std::size_t originalFaces = model.faces.size();
    if (planMeshChunks(model).size() <= maximumHandles)
        return {originalVertices, originalFaces, originalVertices, originalFaces, 0.0F};

    for (float clusterSize = 1.0F / 512.0F; clusterSize <= 0.5F;
         clusterSize *= 1.25F) {
        IndexedModel candidate = clusterModel(model, clusterSize);
        if (candidate.faces.empty())
            continue;
        if (planMeshChunks(candidate).size() <= maximumHandles) {
            const std::size_t simplifiedVertices = candidate.vertices.size();
            const std::size_t simplifiedFaces = candidate.faces.size();
            model = std::move(candidate);
            return {originalVertices, originalFaces, simplifiedVertices,
                    simplifiedFaces, clusterSize};
        }
    }
    throw std::length_error("model could not be simplified to fit the mesh store");
}

std::vector<Mesh> buildMeshChunks(const IndexedModel& model,
                                  std::uint8_t firstColor,
                                  std::uint8_t colorCount) {
    if (colorCount == 0 || static_cast<unsigned>(firstColor) + colorCount > 256U)
        throw std::invalid_argument("palette color range is invalid");

    const std::vector<ChunkRange> ranges = planMeshChunks(model);
    std::vector<Mesh> chunks;
    chunks.reserve(ranges.size());
    for (const ChunkRange& range : ranges) {
        Mesh chunk;
        chunk.reserve(range.faceCount);
        for (std::size_t offset = 0; offset < range.faceCount; ++offset) {
            const std::size_t faceNumber = range.firstFace + offset;
            const auto& face = model.faces[faceNumber];
            const auto color = static_cast<std::uint8_t>(
                static_cast<unsigned>(firstColor) + faceNumber % colorCount);
            chunk.addTriangle({model.vertices[face[0]], model.vertices[face[1]],
                               model.vertices[face[2]], color});
        }
        chunks.push_back(std::move(chunk));
    }
    return chunks;
}

}
