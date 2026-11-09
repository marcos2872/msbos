#!/usr/bin/env bash
# build-in-container.sh — roda DENTRO do container Fedora do 55-niri-zoom.sh.
#
# Recebe como argumentos a lista de dependências de build do niri, instala,
# aplica o patch local do msbos e compila o compositor. O binário pronto fica
# em /work/niri-built (o /work é o diretório temporário montado pela etapa).
set -euo pipefail

dnf -y --setopt=install_weak_deps=0 install "$@"

# O patch foi gerado com `git diff` (prefixos a/ e b/), então -p1.
patch -p1 -i /work/niri-zoom.patch

# O tarball do commit inclui Cargo.lock. --locked garante que a build não
# resolva versões diferentes das testadas; se o lock estiver incompleto (por
# exemplo, numa atualização futura do fork), cai para a resolução normal.
if [[ -f Cargo.lock ]]; then
  if ! cargo build --release --locked; then
    echo "aviso: cargo build --locked falhou; tentando sem --locked" >&2
    cargo build --release
  fi
else
  cargo build --release
fi

install -m 0755 target/release/niri /work/niri-built
