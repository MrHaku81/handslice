# Dummy FindOpenGL fuer Android-Cross-Compile der OrcaSlicer-Deps.
#
# Hintergrund: engine/OrcaSlicer/deps/CMakeLists.txt macht ein
# `include(GLEW/GLEW.cmake)` zur Configure-Zeit auch dann, wenn wir
# dep_GLEW nicht bauen. GLEW/GLEW.cmake:3 ruft `find_package(OpenGL REQUIRED)`.
# Auf Android gibt es kein Desktop-OpenGL, und wir brauchen weder GLEW
# noch GLFW noch OpenCSG fuer libslic3r (siehe Dep-Audit in
# docs/engine-integration.md).
#
# Dieser Shim wird ueber CMAKE_MODULE_PATH gefunden, bevor CMake sein
# eigenes Modules/FindOpenGL.cmake aufmacht. Setzt alle Variablen so,
# dass find_package_handle_standard_args zufrieden ist, erzeugt aber
# keine echten Linker-Flags – GLEW wird eh nie konfiguriert/gebaut.
#
# Keine Zeile an OrcaSlicer-Upstream geaendert.

set(OPENGL_FOUND TRUE)
set(OpenGL_FOUND TRUE)
set(OPENGL_XMESA_FOUND FALSE)
set(OPENGL_GLU_FOUND FALSE)
set(OpenGL_OpenGL_FOUND TRUE)
set(OpenGL_GLX_FOUND TRUE)
set(OpenGL_EGL_FOUND FALSE)

set(OPENGL_INCLUDE_DIR "${CMAKE_CURRENT_LIST_DIR}")
set(OPENGL_GLU_INCLUDE_DIR "${CMAKE_CURRENT_LIST_DIR}")
set(OPENGL_EGL_INCLUDE_DIRS "")

# Keine echten Libs: GLEW wird auf Android eh nicht gebaut, aber
# find_package_handle_standard_args prueft, dass die Variablen gesetzt
# sind. Ein nicht-existenter Pfad reicht, weil nichts gelinkt wird.
set(OPENGL_opengl_LIBRARY "${CMAKE_CURRENT_LIST_DIR}/OpenGL-dummy.cmake")
set(OPENGL_glx_LIBRARY   "${CMAKE_CURRENT_LIST_DIR}/OpenGL-dummy.cmake")
set(OPENGL_gl_LIBRARY    "${CMAKE_CURRENT_LIST_DIR}/OpenGL-dummy.cmake")
set(OPENGL_glu_LIBRARY   "")
set(OPENGL_egl_LIBRARY   "")
set(OPENGL_LIBRARIES     "")
set(OPENGL_LIBRARY       "")

if (NOT TARGET OpenGL::OpenGL)
    add_library(OpenGL::OpenGL INTERFACE IMPORTED)
endif ()
if (NOT TARGET OpenGL::GL)
    add_library(OpenGL::GL INTERFACE IMPORTED)
endif ()
if (NOT TARGET OpenGL::GLX)
    add_library(OpenGL::GLX INTERFACE IMPORTED)
endif ()
