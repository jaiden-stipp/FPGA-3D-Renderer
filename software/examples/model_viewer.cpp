#include "fpga_renderer/obj_model.hpp"
#include "model_viewer_support.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <stdexcept>

using namespace fpga_renderer;

namespace {

void setPalette(CommandStream& commands) {
    constexpr std::array<Rgb, 16> colors{{
        {238, 72, 72}, {255, 145, 61}, {255, 216, 74}, {159, 230, 86},
        {62, 214, 132}, {54, 207, 203}, {67, 157, 240}, {92, 104, 230},
        {142, 88, 224}, {207, 83, 218}, {237, 92, 165}, {230, 124, 142},
        {194, 148, 105}, {161, 174, 190}, {207, 218, 230}, {245, 245, 245}
    }};
    for (std::size_t index = 0; index < colors.size(); ++index)
        commands.setPalette(static_cast<std::uint8_t>(index + 1), colors[index]);
}

void checkUpload(const RendererStatus& status, std::size_t handle) {
    if ((status.flags & StatusAccepted) == 0 ||
        (status.flags & ~(StatusAccepted | StatusDuplicate)) != 0)
        throw std::runtime_error("FPGA rejected mesh handle " +
                                 std::to_string(handle));
}

}

int main(int argc, char** argv) {
    try {
        const model_viewer::ViewerOptions options = model_viewer::parseOptions(argc, argv);
        if (options.showHelp) {
            model_viewer::printUsage(argv[0]);
            return 0;
        }

        IndexedModel model = loadObj(options.modelPath);
        const std::size_t sourceVertexCount = model.vertices.size();
        const std::size_t sourceFaceCount = model.faces.size();
        const ModelNormalization normalization = normalizeModel(model);
        const ModelSimplification simplification = simplifyModelToFit(model);
        const std::vector<Mesh> chunks = buildMeshChunks(model);
        std::cout << "Loaded " << options.modelPath.string() << '\n'
                  << "  " << sourceVertexCount << " vertices\n"
                  << "  " << sourceFaceCount << " triangles after triangulation\n"
                  << "  original center: " << normalization.center.x << ", "
                  << normalization.center.y << ", " << normalization.center.z << '\n'
                  << "  normalization scale: " << normalization.scale << '\n'
                  << "  FPGA mesh handles: " << chunks.size() << "\n\n";
        if (simplification.clusterSize > 0.0F)
            std::cout << "Simplified to fit the FPGA:\n  "
                      << simplification.originalVertices << " -> "
                      << simplification.simplifiedVertices << " vertices\n  "
                      << simplification.originalFaces << " -> "
                      << simplification.simplifiedFaces << " triangles\n  cluster size: "
                      << simplification.clusterSize << "\n\n";
        if (options.inspectOnly) {
            for (std::size_t handle = 0; handle < chunks.size(); ++handle)
                std::cout << "  handle " << handle << ": "
                          << chunks[handle].triangles().size() << " triangles\n";
            std::cout << "Model fits the FPGA mesh store.\n";
            return 0;
        }

        RendererClient renderer(options.address, options.port);
        for (std::size_t handle = 0; handle < chunks.size(); ++handle) {
            const RendererStatus status = renderer.uploadMesh(
                static_cast<std::uint8_t>(handle), chunks[handle]);
            checkUpload(status, handle);
            std::cout << "Uploaded handle " << handle << " with "
                      << chunks[handle].triangles().size() << " triangles; FIFO free "
                      << status.fifoFree << '\n';
        }

        model_viewer::printControls();
        model_viewer::Keyboard keyboard;
        model_viewer::ViewerState view;
        std::uint32_t frameId = static_cast<std::uint32_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
        const std::size_t instanceCount = options.instanceCount != 0
            ? options.instanceCount : (chunks.size() > 4 ? 1U : 3U);
        auto reportStart = std::chrono::steady_clock::now();
        auto previousFrame = reportStart;
        std::size_t reportFrames = 0;
        int framesRendered = 0;
        float phase = 0.0F;

        while (!view.quit &&
               (options.frameLimit == 0 || framesRendered < options.frameLimit)) {
            for (int count = 0; count < 32; ++count) {
                const model_viewer::Control control = keyboard.poll();
                if (control == model_viewer::Control::None)
                    break;
                model_viewer::applyControl(view, control);
            }

            const auto now = std::chrono::steady_clock::now();
            const float elapsedSeconds = std::chrono::duration<float>(
                now - previousFrame).count();
            previousFrame = now;
            if (view.animate)
                phase += elapsedSeconds * 0.65F;

            CommandStream frame;
            if (framesRendered == 0)
                setPalette(frame);
            frame.setRotation(0);
            frame.beginFrame(frameId++);
            for (std::size_t instance = 0; instance < instanceCount; ++instance) {
                const float centeredInstance = static_cast<float>(instance) -
                    (static_cast<float>(instanceCount) - 1.0F) * 0.5F;
                const float instanceScale = instanceCount == 1 ? 0.85F :
                    (centeredInstance == 0.0F ? 0.72F : 0.52F);
                const float instanceSpeed = 1.0F + centeredInstance * 0.35F;
                const Mat4 transform =
                    Mat4::translation(view.x + centeredInstance * 1.8F, view.y, view.z) *
                    Mat4::rotationY(view.yaw + phase * instanceSpeed) *
                    Mat4::rotationX(view.pitch) *
                    Mat4::scale(view.scale * instanceScale,
                                view.scale * instanceScale,
                                view.scale * instanceScale);
                for (std::size_t handle = 0; handle < chunks.size(); ++handle)
                    frame.drawMesh(static_cast<std::uint8_t>(handle), transform);
            }
            frame.endFrame();

            const RendererStatus status = renderer.submit(frame);
            if (status.flags != 0)
                throw std::runtime_error("frame " + std::to_string(status.frameId) +
                                         " returned FPGA status " +
                                         std::to_string(status.flags));
            ++framesRendered;
            ++reportFrames;

            const auto reportNow = std::chrono::steady_clock::now();
            const float reportSeconds = std::chrono::duration<float>(
                reportNow - reportStart).count();
            if (reportSeconds >= 1.0F) {
                const float framesPerSecond = reportFrames / reportSeconds;
                const std::size_t packets = (frame.bytes().size() + 1387) / 1388;
                std::cout << '\r' << "Frame " << status.frameId << " | "
                          << std::fixed << std::setprecision(1) << framesPerSecond
                          << " FPS | " << frame.bytes().size() << " bytes | "
                          << packets << " packet(s) | FIFO free " << status.fifoFree
                          << "      " << std::flush;
                reportStart = reportNow;
                reportFrames = 0;
            }

        }
        std::cout << "\nStopped after " << framesRendered << " frames.\n";
    } catch (const std::exception& error) {
        std::cerr << "Error: " << error.what() << '\n';
        return 1;
    }
}
