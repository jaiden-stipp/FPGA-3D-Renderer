#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>

namespace model_viewer {

enum class Control {
    None,
    YawLeft,
    YawRight,
    PitchUp,
    PitchDown,
    MoveLeft,
    MoveRight,
    MoveUp,
    MoveDown,
    MoveForward,
    MoveBackward,
    ScaleUp,
    ScaleDown,
    ToggleAnimation,
    Reset,
    Quit
};

class Keyboard {
public:
    Keyboard();
    ~Keyboard();
    Keyboard(const Keyboard&) = delete;
    Keyboard& operator=(const Keyboard&) = delete;
    Control poll();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

struct ViewerState {
    float x = 0.0F;
    float y = 0.0F;
    float z = 0.0F;
    float yaw = 0.0F;
    float pitch = 0.0F;
    float scale = 1.0F;
    bool animate = true;
    bool quit = false;
};

struct ViewerOptions {
    std::filesystem::path modelPath;
    std::string address = "192.168.7.2";
    std::uint16_t port = 4000;
    int frameLimit = 0;
    std::size_t instanceCount = 0;
    bool inspectOnly = false;
    bool showHelp = false;
};

void applyControl(ViewerState& state, Control control);
ViewerOptions parseOptions(int argc, char** argv);
void printControls();
void printUsage(const char* executable);

}
