{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:

# Queues and retries Nix post-build-hook runs, so a slow hook doesn't hold up builds.
# Not in nixpkgs. Modeled on upstream's default.nix. Pinned rather than taken from
# upstream's flake: its code hasn't changed since 2024, but its lock file is bumped twice
# a week. The dotfiles repo has a copy of this file; keep the two in step.
buildGoModule {
  pname = "queued-build-hook";
  version = "0-unstable-2026-07-29";

  src = fetchFromGitHub {
    owner = "nix-community";
    repo = "queued-build-hook";
    rev = "0e7b194d7e7a7155c9fb6c37b36f3300c91d5194";
    hash = "sha256-alKEIVRdYSK6vSSlm3qmjp91C+s9LQApDbb+1yQ9PuU=";
  };

  vendorHash = null;

  meta = {
    description = "Queue and retry Nix post-build-hook";
    homepage = "https://github.com/nix-community/queued-build-hook";
    license = lib.licenses.mit;
    mainProgram = "queued-build-hook";
  };
}
