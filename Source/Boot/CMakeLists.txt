# The CMake build configuration for the Helix boot loader.
# This project is separate from the main Helix OS project as it may
# require a different tool chain.
cmake_minimum_required(VERSION 3.22)

list(APPEND CMAKE_MESSAGE_CONTEXT Boot)

project(HelixBoot
        VERSION 0.1.0.0
        DESCRIPTION "The boot loader for the Helix operating system"
        HOMEPAGE_URL "https://github.com/GiantRobotLemur/Helix"
        LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS ON)

if(${CMAKE_SYSTEM_NAME} STREQUAL ${CMAKE_HOST_SYSTEM_NAME})
    # We're not cross-compiling, so we're building to run tests.
    message(STATUS "Configuring for testing...")
    enable_testing()

    find_package(GTest 1.12 REQUIRED)

    set(TEST_BUILD ON)
    add_compile_definitions(TEST_BUILD)
else()
    message(STATUS "Configuring for target build...")
    set(TEST_BUILD OFF)

    # Only enable assembly language when creating a target build.
    enable_language(ASM)

    # We're cross compiling for the target system.
    find_program(GEN_ISO_IMAGE "genisoimage" REQUIRED
                 DOC "Location of ISO9660 image creation tool")
endif()

if(isMultiConfig)
    # Limit build configurations to Release with Debug Info and Debug.
    set(CMAKE_CONFIGURATION_TYPES "Debug;RelWithDebInfo")
endif()

# Configure global compiler options.
if (DEFINED MSVC)
    add_compile_options("/W4")
else()
    add_compile_options(-Wall -Wextra -pedantic -Wshadow)

    # Ensure _DEBUG is defined for debug builds, this is done automatically
    # for MSVC.
    add_compile_definitions($<$<CONFIG:Debug>:_DEBUG>)
endif()

# Set the use of IDE folders before anything else.
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

cmake_path(APPEND BOOT_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}" "Include")

add_subdirectory(BootUtils)
add_subdirectory(x86)

if (GEN_ISO_IMAGE AND NOT TEST_BUILD)
    # Create a directory structure for the ISO image,
    # Paste Loader16.sys and Loader32.sys together to create Boot.sys
    # Create an ISO9660 image from the file system.
    cmake_path(APPEND IsoDir "${CMAKE_BINARY_DIR}" "IsoImage")
    cmake_path(APPEND IsoFile "${CMAKE_BINARY_DIR}" "Helix.iso")

    add_custom_target(IsoImage  ALL
                      COMMENT   "Create bootable ISO image"
                      BYPRODUCTS "${IsoFile}"
                      DEPENDS   BootSys
                      COMMAND   "${CMAKE_COMMAND}" -E make_directory "${IsoDir}"
                      COMMAND   "${CMAKE_COMMAND}" -E copy "$<TARGET_PROPERTY:BootSys,TARGET_PATH>"
                                                           "${IsoDir}"
                      COMMAND   "${GEN_ISO_IMAGE}" -J -r -b "$<TARGET_PROPERTY:BootSys,TARGET_FILE>"
                                -no-emul-boot -boot-info-table
                                -input-charset iso8859-1
                                -o "${IsoFile}" "${IsoDir}")

    find_program(BOCHS "bochs"
                 DOC "Location of Bochs emulator")

    find_program(BOCHS_I686 "bochs-i686"
                 DOC "Location of i686-specific Bochs emulator")

    find_program(BOCHS_I686_DEBUG "bochs-i686-debugger"
                 DOC "Location of i686-specific Bochs emulator with GUI debugger")

    cmake_path(RELATIVE_PATH    IsoFile
               BASE_DIRECTORY   "${CMAKE_BINARY_DIR}"
               OUTPUT_VARIABLE  IsoPath)


    if(BOCHS_I686)
        # Create a configuration file.
        set(GUI_DEBUG "")
        cmake_path(APPEND BochsConfigFile "${CMAKE_BINARY_DIR}" "bochsrc-i686")

        configure_file("bochsrc.cmake" "${BochsConfigFile}" @ONLY)

        add_custom_target(IsoBoot
                          COMMENT           "Boot ISO image in Bochs emulator"
                          WORKING_DIRECTRY  "${CMAKE_BINARY_DIR}"
                          DEPENDS           IsoImage
                          COMMAND           "${BOCHS_I686}" -f bochsrc-i686 -q
                          USES_TERMINAL)
    endif()

    if(BOCHS_I686_DEBUG)
        # Create a configuration file.
        set(GUI_DEBUG ", gui_debug")
        cmake_path(APPEND BochsConfigFile "${CMAKE_BINARY_DIR}" "bochsrc-i686-debug")

        configure_file("bochsrc.cmake" "${BochsConfigFile}" @ONLY)

        add_custom_target(IsoDebug
                          COMMENT           "Debug ISO image in Bochs emulator"
                          WORKING_DIRECTRY  "${CMAKE_BINARY_DIR}"
                          DEPENDS           IsoImage
                          COMMAND           "${BOCHS_I686_DEBUG}" -f bochsrc-i686-debug -q
                          USES_TERMINAL)
    endif()
endif()