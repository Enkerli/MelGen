//
//  Kernel.cpp
//  Kernel
//
//  The kernel is header-only — a non-ObjC C++ class, which is what makes it safe
//  to touch from the render thread — and SwiftPM will not build a target with no
//  source file in it. So this exists to give the target something to compile,
//  and it includes both headers so that a syntax error in either one fails the
//  build rather than waiting for a Swift file to import it.
//

#include "include/PluginDSPKernel.hpp"
#include "include/PluginAUProcessHelper.hpp"
