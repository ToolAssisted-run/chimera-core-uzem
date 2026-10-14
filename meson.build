# chimera-core-uzem: uzem, the Uzebox's own emulator, in miniBox's sandbox,
# as a Chimera core.
#
# Native reference build (run-native + run-wbx under the build directory):
#     meson setup build/meson-native -Dminibox_dir=<miniBox> && ninja -C build/meson-native
# Guest (core.wbx) build via the cross file waterbox/setup-guest.sh writes
# (needs miniBox's C++ guest toolchain, build/meson-cpp):
#     sh waterbox/setup-guest.sh -m <miniBox> && ninja -C build/meson-guest core.wbx
#
# The files are upstream's tools/uzem Makefile's, without its debugger
# (NOGDB, as upstream allows) and without SDL: waterbox/cinterface.cpp takes
# the place of uzem.cpp, upstream's program around the machine. Both flavours
# compile the SAME sources; only emulibc.h differs (waterbox/native-shim for
# the reference).
project('chimera-core-uzem', ['c', 'cpp'],
  default_options: ['c_std=gnu11', 'cpp_std=gnu++11', 'optimization=2', 'debug=false', 'warning_level=0'])

uz = 'extern/uzebox/tools/uzem'

# the submodule pin is upstream as it is; the patches are laid over it
# (waterbox/apply-patches.sh does nothing to a tree that has them)
run_command(files('waterbox/apply-patches.sh'), check: true)

mb = get_option('minibox_dir')
if mb == ''
  mb_candidate = meson.current_source_dir() / '../chimera/extern/chimera-common-minibox'
  if import('fs').is_dir(mb_candidate)
    mb = mb_candidate
  else
    error('pass -Dminibox_dir=<miniBox checkout> (or keep one at ../chimera/extern/chimera-common-minibox)')
  endif
endif

# upstream's own defines (its Makefile), less SDL's and the GUI's; NOGDB
# leaves the debugger out; CHIMERA_CORE is what the patch tests for
defs = ['-DLINUX', '-D_GNU_SOURCE=1', '-DNOGDB=1', '-DCHIMERA_CORE', '-DNDEBUG']
# one answer from a floating-point expression on every machine (no fused
# multiply-adds); signed overflow wraps, as the AVR's arithmetic does
flags = ['-fwrapv', '-fno-strict-aliasing', '-ffp-contract=off']
add_project_arguments(defs + flags, language: ['c', 'cpp'])

inc = include_directories('waterbox', uz)

core_sources = files(
  'waterbox/cinterface.cpp',
  uz / 'avr8.cpp',
  uz / 'uzerom.cpp',
  uz / 'SDEmulator.cpp',
)

if meson.is_cross_build()
  # ---- the guest: core.wbx --------------------------------------------------
  # miniBox's musl and libstdc++ arrive through the cross file. The -u lines
  # name the pthread functions libgcc's unwinder refers to weakly: a weak
  # reference is not enough to pull them out of a static libc, and it would
  # call address zero.
  mbdir = meson.get_external_property('minibox_dir')
  mbuild = meson.get_external_property('minibox_build')
  sr = meson.get_external_property('guest_sysroot')

  executable('core', core_sources,
    name_suffix: 'wbx',
    include_directories: inc,
    link_args: [
      '-static', '-no-pie',
      '-Wl,--eh-frame-hdr', '-Wl,-O2', '-Wl,--no-relax', '-Wl,-z,stack-size=8388608',
      '-T', mbdir / 'source/guest/linkscript.T',
      '-Wl,-u,pthread_once', '-Wl,-u,pthread_cond_wait',
      '-Wl,-u,pthread_cond_broadcast', '-Wl,-u,pthread_key_create',
      '-Wl,-u,pthread_mutexattr_init', '-Wl,-u,pthread_mutexattr_settype',
      '-Wl,-u,pthread_mutexattr_destroy',
      mbuild / 'source/guest/cxxglue.c.o',
      mbuild / 'source/guest/emulibc.c.o',
      '-L' + sr / 'lib', '-lstdc++', '-lgcc', '-lgcc_eh', '-lc'])
else
  # ---- the native reference -------------------------------------------------
  m = meson.get_compiler('c').find_library('m', required: false)
  executable('run-native', core_sources + files('waterbox/run-native.c'),
    include_directories: [include_directories('waterbox/native-shim'), inc],
    c_args: ['-I' + mb / 'source/guest/include', '-I' + mb / 'extern/jsmn'],
    cpp_args: ['-I' + mb / 'source/guest/include', '-I' + mb / 'extern/jsmn'],
    dependencies: [m])

  mbhost = mb / 'build/meson-linux/source/host'
  executable('run-wbx', files('waterbox/run-wbx.c'),
    c_args: ['-I' + mb / 'source/host'],
    link_args: [mbhost / 'libminiboxhost.so'],
    build_rpath: mbhost)
endif
