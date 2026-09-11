if(MSVC)
    add_compile_options(/W4 /permissive-)
else()
    add_compile_options(-Wall -Wextra -Wpedantic)
endif()

option(FPGA_RENDERER_ENABLE_SANITIZERS "Enable address and undefined behavior sanitizers" OFF)
if(FPGA_RENDERER_ENABLE_SANITIZERS AND NOT MSVC)
    add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address,undefined)
endif()

add_library(fpga_renderer
    src/renderer.cpp
    src/protocol_codec.cpp
    src/udp_transport.cpp
    src/obj_model.cpp)
target_include_directories(fpga_renderer PUBLIC include)
target_compile_features(fpga_renderer PUBLIC cxx_std_17)
if(WIN32)
    target_link_libraries(fpga_renderer PUBLIC ws2_32)
endif()

add_executable(renderer_example examples/basic_scene.cpp)
target_link_libraries(renderer_example PRIVATE fpga_renderer)

add_executable(renderer_udp_demo examples/ethernet_demo.cpp)
target_link_libraries(renderer_udp_demo PRIVATE fpga_renderer)

add_executable(renderer_scene_tests examples/scene_tests.cpp)
target_link_libraries(renderer_scene_tests PRIVATE fpga_renderer)

add_executable(renderer_model_viewer examples/model_viewer.cpp examples/model_viewer_support.cpp)
target_link_libraries(renderer_model_viewer PRIVATE fpga_renderer)
add_custom_command(TARGET renderer_model_viewer POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${CMAKE_CURRENT_SOURCE_DIR}/assets
            $<TARGET_FILE_DIR:renderer_model_viewer>/assets)

add_executable(renderer_tests tests/renderer_tests.cpp)
target_link_libraries(renderer_tests PRIVATE fpga_renderer)
add_test(NAME renderer_tests COMMAND renderer_tests)

add_executable(obj_model_tests tests/obj_model_tests.cpp)
target_link_libraries(obj_model_tests PRIVATE fpga_renderer)
add_test(NAME obj_model_tests COMMAND obj_model_tests)
