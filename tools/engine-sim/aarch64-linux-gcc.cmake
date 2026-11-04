# Cross toolchain for the engine branch (docs/ENGINE-SIM.md): Arm's GCC 13.2 (mingw-hosted, aarch64-none-linux-gnu),
# the official arm64 engine's compiler family, so the floating-point results match it (Recoil's CMake adds
# -march=armv8-a+simd -ffp-contract=off -fsingle-precision-constant -frounding-math for GCC on arm64). Libraries and
# headers from the Debian trixie arm64 sysroot of the 2026-10-27 research (hailmary-work\sysroot: the phone's
# container's own versions) and Recoil's official static libs (spring-static-libs 18.04-arm).
# Debian keeps glibc's headers, crt files and libraries in multiarch folders, which this GCC does not search.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(HM C:/Tools/BARANDROID/hailmary-work)
set(SR ${HM}/sysroot)
# (a short folder: the compiler's own header paths passed Windows' 260-character limit under Arm's long name)
set(ARMGCC C:/Tools/BARANDROID/toolchain/hosttools/agcc13/bin)
set(CMAKE_SYSROOT ${SR})
set(CMAKE_C_COMPILER ${ARMGCC}/aarch64-none-linux-gnu-gcc.exe)
set(CMAKE_CXX_COMPILER ${ARMGCC}/aarch64-none-linux-gnu-g++.exe)
set(CMAKE_AR ${ARMGCC}/aarch64-none-linux-gnu-gcc-ar.exe CACHE FILEPATH "")
set(CMAKE_RANLIB ${ARMGCC}/aarch64-none-linux-gnu-gcc-ranlib.exe CACHE FILEPATH "")
set(CMAKE_NM ${ARMGCC}/aarch64-none-linux-gnu-gcc-nm.exe CACHE FILEPATH "")
set(CMAKE_OBJCOPY ${ARMGCC}/aarch64-none-linux-gnu-objcopy.exe CACHE FILEPATH "")
set(CMAKE_STRIP ${ARMGCC}/aarch64-none-linux-gnu-strip.exe CACHE FILEPATH "")
set(CMAKE_LIBRARY_ARCHITECTURE aarch64-linux-gnu)
# (after the standard folders: libstdc++'s #include_next must still find glibc's headers). The multiarch link
# folders go with the compiler flags, which CMake also puts on every link line, its compiler tests' too
# (build-engine.ps1 sets the linker flags itself, and a set value leaves the toolchain's *_INIT unused).
set(MULTIARCH_INC "-idirafter ${SR}/usr/include/aarch64-linux-gnu")
set(MULTIARCH_LD "-B${SR}/usr/lib/aarch64-linux-gnu -L${SR}/usr/lib/aarch64-linux-gnu -L${SR}/lib/aarch64-linux-gnu -Wl,-rpath-link,${SR}/usr/lib/aarch64-linux-gnu -Wl,-rpath-link,${SR}/lib/aarch64-linux-gnu")
set(CMAKE_C_FLAGS_INIT "${MULTIARCH_INC} ${MULTIARCH_LD}")
set(CMAKE_CXX_FLAGS_INIT "${MULTIARCH_INC} ${MULTIARCH_LD}")
set(CMAKE_FIND_ROOT_PATH ${HM}/static-libs ${SR})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_DISABLE_PRECOMPILE_HEADERS ON)
