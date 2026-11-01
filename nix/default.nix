{
  rev,
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  makeFontsConf,
  fish,
  coreutils,
  util-linux,
  ddcutil,
  brightnessctl,
  findutils,
  git,
  lazygit,
  gnugrep,
  gnused,
  jq,
  networkmanager,
  lm_sensors,
  swappy,
  wl-clipboard,
  libqalculate,
  bash,
  hyprland,
  material-symbols,
  rubik,
  nerd-fonts,
  qt6,
  vimPlugins,
  quickshell,
  aubio,
  libcava,
  fftw,
  pipewire,
  xkeyboard-config,
  cmake,
  ninja,
  pkg-config,
  caelestia-cli,
  m3shapes,
  debug ? false,
  withCli ? false,
  extraRuntimeDeps ? [],
}: let
  version = "1.0.0";
  codediff = vimPlugins.codediff-nvim.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./patches/codediff-preserve-single-file-view.patch];
  });
  openvideLazygit = lazygit.overrideAttrs (old: {
    version = "0.48.0";
    src = fetchFromGitHub {
      owner = "jesseduffield";
      repo = "lazygit";
      rev = "v0.48.0";
      hash = "sha256-L3OcCkoSJZ6skzcjP2E3BrQ39cXyxcuHGthj8RHIGeQ=";
    };
    patches = (old.patches or []) ++ [./patches/lazygit-openvide-context.patch];
  });

  runtimeDeps =
    [
      fish
      coreutils
      util-linux
      ddcutil
      brightnessctl
      findutils
      git
      gnugrep
      gnused
      jq
      networkmanager
      lm_sensors
      swappy
      wl-clipboard
      libqalculate
      bash
      hyprland
    ]
    ++ extraRuntimeDeps
    ++ lib.optional withCli caelestia-cli;

  fontconfig = makeFontsConf {
    fontDirectories = [material-symbols rubik nerd-fonts.caskaydia-cove];
  };

  cmakeBuildType =
    if debug
    then "Debug"
    else "RelWithDebInfo";

  cmakeVersionFlags = [
    (lib.cmakeFeature "VERSION" version)
    (lib.cmakeFeature "GIT_REVISION" rev)
    (lib.cmakeFeature "DISTRIBUTOR" "nix-flake")
  ];

  # The build sandbox has no network access so add it as a flake input instead
  m3shapesFlag = lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_M3SHAPES_EXTERNAL" "${m3shapes}";

  extras = stdenv.mkDerivation {
    inherit cmakeBuildType;
    name = "caelestia-extras${lib.optionalString debug "-debug"}";
    src = lib.fileset.toSource {
      root = ./..;
      fileset = lib.fileset.union ./../CMakeLists.txt ./../extras;
    };

    nativeBuildInputs = [cmake ninja];

    cmakeFlags =
      [
        (lib.cmakeFeature "ENABLE_MODULES" "extras")
        (lib.cmakeFeature "INSTALL_LIBDIR" "${placeholder "out"}/lib")
      ]
      ++ cmakeVersionFlags;
  };

  plugin = stdenv.mkDerivation {
    inherit cmakeBuildType;
    name = "caelestia-qml-plugin${lib.optionalString debug "-debug"}";
    src = lib.fileset.toSource {
      root = ./..;
      fileset = lib.fileset.union ./../CMakeLists.txt ./../plugin;
    };

    nativeBuildInputs = [cmake ninja pkg-config];
    buildInputs = [qt6.qtbase qt6.qtdeclarative qt6.qtshadertools libqalculate pipewire aubio libcava fftw lm_sensors];

    dontWrapQtApps = true;
    cmakeFlags =
      [
        (lib.cmakeFeature "ENABLE_MODULES" "plugin")
        (lib.cmakeFeature "INSTALL_QMLDIR" qt6.qtbase.qtQmlPrefix)
      ]
      ++ cmakeVersionFlags;
  };

  m3shapesModule = stdenv.mkDerivation {
    inherit cmakeBuildType;
    name = "caelestia-m3shapes${lib.optionalString debug "-debug"}";
    src = lib.fileset.toSource {
      root = ./..;
      fileset = ./../CMakeLists.txt;
    };

    nativeBuildInputs = [cmake ninja];
    buildInputs = [qt6.qtbase qt6.qtdeclarative];

    dontWrapQtApps = true;
    cmakeFlags =
      [
        (lib.cmakeFeature "ENABLE_MODULES" "m3shapes")
        (lib.cmakeFeature "INSTALL_QMLDIR" qt6.qtbase.qtQmlPrefix)
        m3shapesFlag
      ]
      ++ cmakeVersionFlags;
  };
in
  stdenv.mkDerivation {
    inherit version cmakeBuildType;
    pname = "caelestia-shell${lib.optionalString debug "-debug"}";
    src = ./..;

    nativeBuildInputs = [cmake ninja makeWrapper qt6.wrapQtAppsHook];
    buildInputs = [quickshell extras plugin m3shapesModule xkeyboard-config qt6.qtbase];
    propagatedBuildInputs = runtimeDeps;

    cmakeFlags =
      [
        (lib.cmakeFeature "ENABLE_MODULES" "shell")
        (lib.cmakeFeature "INSTALL_QSCONFDIR" "${placeholder "out"}/share/caelestia-shell")
      ]
      ++ cmakeVersionFlags;

    dontStrip = debug;

    prePatch = ''
      substituteInPlace assets/pam.d/fprint \
        --replace-fail pam_fprintd.so /run/current-system/sw/lib/security/pam_fprintd.so
      substituteInPlace assets/pam.d/howdy \
        --replace-fail pam_howdy.so /run/current-system/sw/lib/security/pam_howdy.so
    '';

    postInstall = ''
      mkdir -p "$out/share/caelestia-shell/assets/bin"
      ln -s ${openvideLazygit}/bin/lazygit "$out/share/caelestia-shell/assets/bin/lazygit"
      mkdir -p "$out/share/caelestia-shell/assets/nvim-plugins"
      ln -s ${codediff} "$out/share/caelestia-shell/assets/nvim-plugins/codediff.nvim"
      ln -s ${vimPlugins.nui-nvim} "$out/share/caelestia-shell/assets/nvim-plugins/nui.nvim"

      makeWrapper ${quickshell}/bin/qs $out/bin/caelestia-shell \
      	--prefix PATH : "${lib.makeBinPath runtimeDeps}" \
      	--set FONTCONFIG_FILE "${fontconfig}" \
      	--set CAELESTIA_LIB_DIR ${extras}/lib \
        --set CAELESTIA_XKB_RULES_PATH ${xkeyboard-config}/share/xkeyboard-config-2/rules/base.lst \
      	--add-flags "-p $out/share/caelestia-shell"

      cat > $out/bin/caelestia-ipc <<'EOF'
      #!/bin/sh
      set -eu

      if [ "$#" -lt 2 ]; then
        echo "Usage: caelestia-ipc <target> <function> [args...]" >&2
        exit 1
      fi

      instance_id=$(${quickshell}/bin/qs list --all | while read -r label id; do
        if [ "$label" = "Instance" ]; then
          printf '%s\n' "''${id%:}"
          break
        fi
      done)

      if [ -z "$instance_id" ]; then
        systemctl --user start caelestia-shell.service >/dev/null 2>&1 || true
        sleep 1
        instance_id=$(${quickshell}/bin/qs list --all | while read -r label id; do
          if [ "$label" = "Instance" ]; then
            printf '%s\n' "''${id%:}"
            break
          fi
        done)
      fi

      if [ -z "$instance_id" ]; then
        echo "No running Caelestia/Quickshell instance found" >&2
        exit 1
      fi

      exec ${quickshell}/bin/qs ipc --id "$instance_id" call "$@"
      EOF
      chmod +x $out/bin/caelestia-ipc

      mkdir -p $out/lib
      ln -s ${extras}/lib/* $out/lib/
    '';

    passthru = {
      inherit plugin extras m3shapesModule;
    };

    meta = {
      description = "A very segsy desktop shell";
      homepage = "https://github.com/caelestia-dots/shell";
      license = lib.licenses.gpl3Only;
      mainProgram = "caelestia-shell";
    };
  }
