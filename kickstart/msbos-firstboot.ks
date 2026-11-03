# msbos — exemplo de %post para instalação desatendida (kickstart/Anaconda).
#
# NÃO rode o install.sh aqui: o %post executa no chroot do sistema instalado, sem
# systemd como PID 1, e o msbos precisa de systemctl, runuser e dconf/gsettings.
# Este %post só instala e habilita o serviço de primeiro boot; a instalação de
# verdade acontece no primeiro boot, com a rede e o systemd no ar.
#
# Como usar: no seu kickstart, crie o usuário (linha `user ...`), aponte
# MSBOS_ALVO_USUARIO para ele e cole este bloco no fim do arquivo. A base
# recomendada continua sendo a do msbos: Fedora KDE, ou Fedora Everything com
# "Minimal Install" (veja docs/instalacao.md).

%post --interpreter=/bin/bash --erroronfail --log=/root/msbos-firstboot.log
set -euxo pipefail

# Usuário criado pela linha `user ...` do kickstart — o dono da configuração.
MSBOS_ALVO_USUARIO="marcos"
MSBOS_REF="main"
MSBOS_REPO="marcos2872/msbos"

curl -fsSL --retry 3 --retry-delay 2 \
  "https://raw.githubusercontent.com/${MSBOS_REPO}/${MSBOS_REF}/bootstrap.sh" \
  -o /tmp/msbos-bootstrap.sh
MSBOS_REF="${MSBOS_REF}" MSBOS_REPO="${MSBOS_REPO}" \
  bash /tmp/msbos-bootstrap.sh --firstboot --user "${MSBOS_ALVO_USUARIO}"
rm -f /tmp/msbos-bootstrap.sh
%end
