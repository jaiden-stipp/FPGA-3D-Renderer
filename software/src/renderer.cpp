#include "fpga_renderer/renderer.hpp"

#include <algorithm>
#include <cmath>
#include <fstream>
#include <limits>
#include <stdexcept>
#include <unordered_map>

namespace fpga_renderer {

namespace {

void appendFixed(std::vector<std::uint8_t>& output, float value) {
    const auto fixed = static_cast<std::uint16_t>(toQ8_8(value));
    output.push_back(static_cast<std::uint8_t>(fixed >> 8));
    output.push_back(static_cast<std::uint8_t>(fixed));
}

struct FixedVertex {
    std::int16_t x;
    std::int16_t y;
    std::int16_t z;
};

std::uint64_t vertexKey(const FixedVertex& vertex) {
    return (static_cast<std::uint64_t>(static_cast<std::uint16_t>(vertex.x)) << 32) |
           (static_cast<std::uint64_t>(static_cast<std::uint16_t>(vertex.y)) << 16) |
           static_cast<std::uint16_t>(vertex.z);
}

std::uint8_t findVertex(std::vector<FixedVertex>& vertices,
                        std::unordered_map<std::uint64_t, std::uint8_t>& indices,
                        const Vec3& vertex) {
    const FixedVertex fixed{toQ8_8(vertex.x), toQ8_8(vertex.y), toQ8_8(vertex.z)};
    const auto found = indices.find(vertexKey(fixed));
    if (found != indices.end())
        return found->second;
    if (vertices.size() >= 128)
        throw std::length_error("mesh exceeds 128 unique vertices");
    const auto index = static_cast<std::uint8_t>(vertices.size());
    vertices.push_back(fixed);
    indices.emplace(vertexKey(fixed), index);
    return index;
}

void appendFixed(std::vector<std::uint8_t>& output, std::int16_t value) {
    const auto fixed = static_cast<std::uint16_t>(value);
    output.push_back(static_cast<std::uint8_t>(fixed >> 8));
    output.push_back(static_cast<std::uint8_t>(fixed));
}

}

Mat4 Mat4::identity() {
    Mat4 result;
    result.values[0] = 1.0F;
    result.values[5] = 1.0F;
    result.values[10] = 1.0F;
    result.values[15] = 1.0F;
    return result;
}

Mat4 Mat4::translation(float x, float y, float z) {
    Mat4 result = identity();
    result.values[3] = x;
    result.values[7] = y;
    result.values[11] = z;
    return result;
}

Mat4 Mat4::scale(float x, float y, float z) {
    Mat4 result = identity();
    result.values[0] = x;
    result.values[5] = y;
    result.values[10] = z;
    return result;
}

Mat4 Mat4::rotationX(float radians) {
    Mat4 result = identity();
    const float cosine = std::cos(radians);
    const float sine = std::sin(radians);
    result.values[5] = cosine;
    result.values[6] = -sine;
    result.values[9] = sine;
    result.values[10] = cosine;
    return result;
}

Mat4 Mat4::rotationY(float radians) {
    Mat4 result = identity();
    const float cosine = std::cos(radians);
    const float sine = std::sin(radians);
    result.values[0] = cosine;
    result.values[2] = sine;
    result.values[8] = -sine;
    result.values[10] = cosine;
    return result;
}

Mat4 Mat4::rotationZ(float radians) {
    Mat4 result = identity();
    const float cosine = std::cos(radians);
    const float sine = std::sin(radians);
    result.values[0] = cosine;
    result.values[1] = -sine;
    result.values[4] = sine;
    result.values[5] = cosine;
    return result;
}

Vec3 Mat4::transformPoint(const Vec3& point) const {
    const float x = values[0] * point.x + values[1] * point.y +
                    values[2] * point.z + values[3];
    const float y = values[4] * point.x + values[5] * point.y +
                    values[6] * point.z + values[7];
    const float z = values[8] * point.x + values[9] * point.y +
                    values[10] * point.z + values[11];
    const float w = values[12] * point.x + values[13] * point.y +
                    values[14] * point.z + values[15];
    if (std::abs(w) < std::numeric_limits<float>::epsilon())
        throw std::runtime_error("transform produced a zero w coordinate");
    return {x / w, y / w, z / w};
}

Mat4 operator*(const Mat4& left, const Mat4& right) {
    Mat4 result;
    for (std::size_t row = 0; row < 4; ++row) {
        for (std::size_t column = 0; column < 4; ++column) {
            float value = 0.0F;
            for (std::size_t index = 0; index < 4; ++index)
                value += left.values[row * 4 + index] * right.values[index * 4 + column];
            result.values[row * 4 + column] = value;
        }
    }
    return result;
}

void Mesh::reserve(std::size_t triangleCount) {
    triangles_.reserve(triangleCount);
}

void Mesh::addTriangle(const Triangle& triangle) {
    triangles_.push_back(triangle);
}

const std::vector<Triangle>& Mesh::triangles() const {
    return triangles_;
}

void CommandStream::clear() {
    bytes_.clear();
    frame_open_ = false;
    has_frame_id_ = false;
    frame_id_ = 0;
}

void CommandStream::setRotation(std::uint8_t angle) {
    if (frame_open_)
        throw std::logic_error("rotation can only change between frames");
    append(Opcode::SetRotation, {angle});
}

void CommandStream::setPalette(std::uint8_t index, Rgb color) {
    if (frame_open_)
        throw std::logic_error("palette entries can only change between frames");
    append(Opcode::SetPalette, {index, color.red, color.green, color.blue});
}

void CommandStream::uploadMesh(std::uint8_t handle, const Mesh& mesh) {
    if (frame_open_)
        throw std::logic_error("meshes can only be uploaded between frames");
    if (handle >= 16)
        throw std::out_of_range("mesh handle must be between 0 and 15");
    if (mesh.triangles().empty())
        throw std::invalid_argument("cannot upload an empty mesh");
    if (mesh.triangles().size() > 256)
        throw std::length_error("mesh exceeds 256 triangles");

    struct IndexedTriangle {
        std::uint8_t index0;
        std::uint8_t index1;
        std::uint8_t index2;
        std::uint8_t color;
    };
    std::vector<FixedVertex> vertices;
    std::unordered_map<std::uint64_t, std::uint8_t> vertexIndices;
    std::vector<IndexedTriangle> triangles;
    vertices.reserve(128);
    vertexIndices.reserve(128);
    triangles.reserve(mesh.triangles().size());
    for (const Triangle& triangle : mesh.triangles()) {
        triangles.push_back({findVertex(vertices, vertexIndices, triangle.v0),
                             findVertex(vertices, vertexIndices, triangle.v1),
                             findVertex(vertices, vertexIndices, triangle.v2),
                             triangle.color});
    }

    append(Opcode::DefineMesh, {
        handle,
        static_cast<std::uint8_t>(vertices.size() >> 8),
        static_cast<std::uint8_t>(vertices.size()),
        static_cast<std::uint8_t>(triangles.size() >> 8),
        static_cast<std::uint8_t>(triangles.size())
    });
    constexpr std::size_t verticesPerCommand = 42;
    for (std::size_t first = 0; first < vertices.size(); first += verticesPerCommand) {
        const std::size_t count = (std::min)(verticesPerCommand, vertices.size() - first);
        std::vector<std::uint8_t> payload{
            handle, static_cast<std::uint8_t>(first), static_cast<std::uint8_t>(count)};
        payload.reserve(3 + count * 6);
        for (std::size_t offset = 0; offset < count; ++offset) {
            const FixedVertex& vertex = vertices[first + offset];
            appendFixed(payload, vertex.x);
            appendFixed(payload, vertex.y);
            appendFixed(payload, vertex.z);
        }
        append(Opcode::UploadVertices, payload);
    }
    constexpr std::size_t indicesPerCommand = 62;
    for (std::size_t first = 0; first < triangles.size(); first += indicesPerCommand) {
        const std::size_t count = (std::min)(indicesPerCommand, triangles.size() - first);
        std::vector<std::uint8_t> payload{
            handle, static_cast<std::uint8_t>(first >> 8),
            static_cast<std::uint8_t>(first), static_cast<std::uint8_t>(count)};
        payload.reserve(4 + count * 4);
        for (std::size_t offset = 0; offset < count; ++offset) {
            const IndexedTriangle& triangle = triangles[first + offset];
            payload.push_back(triangle.index0);
            payload.push_back(triangle.index1);
            payload.push_back(triangle.index2);
            payload.push_back(triangle.color);
        }
        append(Opcode::UploadIndices, payload);
    }
}

void CommandStream::beginFrame(std::uint32_t frameId) {
    if (frame_open_)
        throw std::logic_error("a frame is already open");
    append(Opcode::BeginFrame, {
        static_cast<std::uint8_t>(frameId >> 24),
        static_cast<std::uint8_t>(frameId >> 16),
        static_cast<std::uint8_t>(frameId >> 8),
        static_cast<std::uint8_t>(frameId)
    });
    frame_open_ = true;
    has_frame_id_ = true;
    frame_id_ = frameId;
}

void CommandStream::drawTriangle(const Triangle& triangle) {
    if (!frame_open_)
        throw std::logic_error("draw commands require an open frame");
    std::vector<std::uint8_t> payload;
    payload.reserve(19);
    appendFixed(payload, triangle.v0.x);
    appendFixed(payload, triangle.v0.y);
    appendFixed(payload, triangle.v0.z);
    appendFixed(payload, triangle.v1.x);
    appendFixed(payload, triangle.v1.y);
    appendFixed(payload, triangle.v1.z);
    appendFixed(payload, triangle.v2.x);
    appendFixed(payload, triangle.v2.y);
    appendFixed(payload, triangle.v2.z);
    payload.push_back(triangle.color);
    append(Opcode::DrawTriangle, payload);
}

void CommandStream::drawMesh(const Mesh& mesh, const Mat4& transform) {
    for (const auto& triangle : mesh.triangles()) {
        drawTriangle({
            transform.transformPoint(triangle.v0),
            transform.transformPoint(triangle.v1),
            transform.transformPoint(triangle.v2),
            triangle.color
        });
    }
}

void CommandStream::drawMesh(std::uint8_t handle, const Mat4& transform) {
    if (!frame_open_)
        throw std::logic_error("draw commands require an open frame");
    if (handle >= 16)
        throw std::out_of_range("mesh handle must be between 0 and 15");
    constexpr float epsilon = 0.00001F;
    if (std::abs(transform.values[12]) > epsilon ||
        std::abs(transform.values[13]) > epsilon ||
        std::abs(transform.values[14]) > epsilon ||
        std::abs(transform.values[15] - 1.0F) > epsilon)
        throw std::invalid_argument("hardware mesh transforms must be affine");

    std::vector<std::uint8_t> payload;
    payload.reserve(25);
    payload.push_back(handle);
    for (std::size_t row = 0; row < 3; ++row) {
        for (std::size_t column = 0; column < 4; ++column)
            appendFixed(payload, transform.values[row * 4 + column]);
    }
    append(Opcode::DrawMesh, payload);
}

void CommandStream::endFrame() {
    if (!frame_open_)
        throw std::logic_error("there is no open frame to end");
    append(Opcode::EndFrame, {});
    frame_open_ = false;
}

const std::vector<std::uint8_t>& CommandStream::bytes() const {
    return bytes_;
}

std::uint32_t CommandStream::frameId() const {
    if (!has_frame_id_)
        throw std::logic_error("command stream does not contain a frame");
    if (frame_open_)
        throw std::logic_error("command stream frame has not been ended");
    return frame_id_;
}

void CommandStream::save(const std::filesystem::path& path) const {
    std::ofstream output(path, std::ios::binary);
    if (!output)
        throw std::runtime_error("could not open command stream output file");
    output.write(reinterpret_cast<const char*>(bytes_.data()),
                 static_cast<std::streamsize>(bytes_.size()));
    if (!output)
        throw std::runtime_error("could not write command stream output file");
}

void CommandStream::append(Opcode opcode, const std::vector<std::uint8_t>& payload) {
    if (payload.size() > 255)
        throw std::length_error("command payload exceeds 255 bytes");

    const std::size_t start = bytes_.size();
    bytes_.push_back(0x47);
    bytes_.push_back(0x46);
    bytes_.push_back(0x01);
    bytes_.push_back(static_cast<std::uint8_t>(opcode));
    bytes_.push_back(static_cast<std::uint8_t>(payload.size()));
    bytes_.insert(bytes_.end(), payload.begin(), payload.end());
    const std::uint16_t crc = crc16Ccitt(bytes_.data() + start, bytes_.size() - start);
    bytes_.push_back(static_cast<std::uint8_t>(crc >> 8));
    bytes_.push_back(static_cast<std::uint8_t>(crc));
}

std::int16_t toQ8_8(float value) {
    constexpr float minimum = -128.0F;
    constexpr float maximum = 127.99609375F;
    if (!std::isfinite(value) || value < minimum || value > maximum)
        throw std::out_of_range("coordinate cannot be represented as signed Q8.8");
    return static_cast<std::int16_t>(std::lround(value * 256.0F));
}

std::uint16_t crc16Ccitt(const std::uint8_t* data, std::size_t size) {
    std::uint16_t crc = 0xFFFF;
    for (std::size_t byte = 0; byte < size; ++byte) {
        crc ^= static_cast<std::uint16_t>(data[byte]) << 8;
        for (int bit = 0; bit < 8; ++bit)
            crc = (crc & 0x8000) ? static_cast<std::uint16_t>((crc << 1) ^ 0x1021)
                                 : static_cast<std::uint16_t>(crc << 1);
    }
    return crc;
}

}
