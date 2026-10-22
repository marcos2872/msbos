#!/usr/bin/env bash
# tests/agent-skill/run.sh — rotina de validação da skill omyfedora + helper.
#
# Uso:
#   ./run.sh --phase 0 --phase 1            # sem senha (preflight + dry-run)
#   ./run.sh --all                          # fases 0-2 (a fase 2 pede senha; não altera nada)
#   ./run.sh --all --mutating --yes         # fases 0-3 (a fase 3 altera e restaura; só com aprovação)
#   ./run.sh --all --known-issues           # baseline: falhas conhecidas contam como KNOWN
#
# Rode como o usuário-alvo (NÃO como root). O teste NÃO usa sudo: as ações
# privilegiadas passam por pkexec + /usr/local/libexec/omyfedora-priv, como
# manda a skill. A senha é digitada pelo usuário na janela do polkit.
#
# Fases:
#   0  preflight (somente leitura)
#   1  validação estática + dry-run (sem senha)
#   2  simulações e validações via pkexec (senha; não altera nada)
#   3  instala/remove um pacote de teste e habilita/desabilita um serviço
#      (muta de forma reversível; exige --mutating e confirmação/--yes)
#   4  cenários manuais da skill (scenarios.md; agente + usuário)
#   5  conferência da trilha de auditoria (manual; sudo tail)
#
# Códigos de saída: 0 = sem falhas inesperadas; 1 = falhas; 2 = erro de uso.
#
# Opções:
#   --phase N          roda a fase N (0-5; pode repetir)
#   --all              fases 0, 1 e 2
#   --mutating         inclui a fase 3 (muta; use --yes ou confirme no terminal)
#   --yes, -y          pula a confirmação da fase 3 (só depois de o usuário aprovar)
#   --known-issues     falhas já conhecidas/documentadas contam como KNOWN, não FAIL
#   --helper CAMINHO   helper a testar (padrão: /usr/local/libexec/omyfedora-priv)
#   --skill-dir DIR    skill a inspecionar (padrão: ~/.agents/skills/omyfedora)
#   --policy ARQUIVO   .policy a validar (padrão: /usr/share/polkit-1/actions/...)
#   --report ARQUIVO   relatório (padrão: ${TMPDIR:-/tmp}/omyfedora-agent-skill-<data>.log)
#   --no-color         desliga cores
#   -h, --help         esta ajuda

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_HELPER="/usr/local/libexec/omyfedora-priv"
DEFAULT_POLICY="/usr/share/polkit-1/actions/org.omyfedora.priv.policy"
DEFAULT_SKILL_DIR="${HOME}/.agents/skills/omyfedora"
CONF_DIR="/etc/omyfedora"
LOG_DIR="/var/log/omyfedora"

HELPER="$DEFAULT_HELPER"
POLICY_FILE="$DEFAULT_POLICY"
SKILL_DIR="$DEFAULT_SKILL_DIR"
STAGE="$REPO_ROOT/scripts/60-agent-skill.sh"
REPORT="${TMPDIR:-/tmp}/omyfedora-agent-skill-$(date +%Y%m%d-%H%M%S).log"
KNOWN_MODE=0
MUTATING=0
YES=0
NO_COLOR=0
PHASES=()

# IDs que o branch atual (baseline) ainda não passa. Ver tests/agent-skill/README.md.
KNOWN_IDS=" STATIC-PATH STATIC-UNITS STATIC-PROTECTED STATIC-DNF STATIC-INTEGRATION DRY-REMOVE-DOLPHIN DRY-REMOVE-BASH DRY-REMOVE-NIRI DRY-REMOVE-SYSTEMD DRY-SVC-OOMD DRY-SVC-PPD PRE-SELINUX-BIN "

PASS=0
FAIL=0
SKIP=0
KNOWN=0
FAILED_IDS=()
KNOWN_SEEN=()

die() { printf 'erro: %s\n' "$*" >&2; exit 2; }

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

while (($#)); do
  case "$1" in
    --phase)
      shift
      (($# > 0)) || die "--phase exige um número (0-5)"
      PHASES+=("$1")
      ;;
    --all)          PHASES+=(0 1 2) ;;
    --mutating)     MUTATING=1 ;;
    --yes|-y)       YES=1 ;;
    --known-issues) KNOWN_MODE=1 ;;
    --helper)
      shift; (($# > 0)) || die "--helper exige um caminho"; HELPER="$1" ;;
    --skill-dir)
      shift; (($# > 0)) || die "--skill-dir exige um caminho"; SKILL_DIR="$1" ;;
    --policy)
      shift; (($# > 0)) || die "--policy exige um caminho"; POLICY_FILE="$1" ;;
    --report)
      shift; (($# > 0)) || die "--report exige um caminho"; REPORT="$1" ;;
    --no-color)     NO_COLOR=1 ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "opção desconhecida: $1 (use --help)" ;;
  esac
  shift
done

if ((EUID == 0)); then
  die "rode como o usuário-alvo, não como root (o teste usa pkexec e a sessão do usuário)"
fi

((MUTATING == 1)) && PHASES+=(3)
((${#PHASES[@]} > 0)) || PHASES=(0 1)

declare -A _seen=()
SELECTED=()
for p in "${PHASES[@]}"; do
  [[ $p =~ ^[0-5]$ ]] || die "fase inválida: '$p' (use 0-5)"
  if ((p == 3)) && ((MUTATING == 0)); then
    die "a fase 3 altera o sistema; use --mutating (e confirme com o usuário)"
  fi
  [[ -n ${_seen[$p]:-} ]] && continue
  _seen[$p]=1
  SELECTED+=("$p")
done
unset _seen
mapfile -t SELECTED < <(printf '%s\n' "${SELECTED[@]}" | sort -n)

# caminhos relativos viram absolutos (o run é chamado de qualquer diretório)
abs_path() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *)  printf '%s/%s' "$PWD" "$1" ;;
  esac
}
HELPER="$(abs_path "$HELPER")"
SKILL_DIR="$(abs_path "$SKILL_DIR")"
POLICY_FILE="$(abs_path "$POLICY_FILE")"

mkdir -p "$(dirname "$REPORT")" 2>/dev/null || true
: > "$REPORT" 2>/dev/null || die "não consigo escrever o relatório: $REPORT"
# tudo (stdout+stderr) vai para o terminal e para o relatório
exec > >(tee -a "$REPORT") 2>&1

if [[ -t 1 && $NO_COLOR == 0 ]]; then
  C_PASS=$'\033[0;32m' C_FAIL=$'\033[0;31m' C_SKIP=$'\033[0;33m'
  C_KNOWN=$'\033[0;36m' C_HEAD=$'\033[1m' C_RST=$'\033[0m'
else
  C_PASS='' C_FAIL='' C_SKIP='' C_KNOWN='' C_HEAD='' C_RST=''
fi

section() {
  printf '\n%s──── %s ────%s\n' "$C_HEAD" "$1" "$C_RST"
}

pass() { PASS=$((PASS + 1)); printf '%s[PASS ]%s %s — %s\n' "$C_PASS" "$C_RST" "$1" "$2"; }
skip() { SKIP=$((SKIP + 1)); printf '%s[SKIP ]%s %s — %s\n' "$C_SKIP" "$C_RST" "$1" "$2"; }
known() {
  KNOWN=$((KNOWN + 1)); KNOWN_SEEN+=("$1")
  printf '%s[KNOWN]%s %s — %s\n' "$C_KNOWN" "$C_RST" "$1" "$2"
  if [[ -n ${3:-} ]]; then printf '%s\n' "$3" | sed -n '1,20p' | sed 's/^/       /'; fi
}
fail() {
  FAIL=$((FAIL + 1)); FAILED_IDS+=("$1")
  printf '%s[FAIL ]%s %s — %s\n' "$C_FAIL" "$C_RST" "$1" "$2"
  if [[ -n ${3:-} ]]; then printf '%s\n' "$3" | sed -n '1,20p' | sed 's/^/       /'; fi
}

is_known_id() { [[ " $KNOWN_IDS " == *" $1 "* ]]; }

fail_or_known() {
  local id="$1" desc="$2" detail="${3:-}"
  if ((KNOWN_MODE == 1)) && is_known_id "$id"; then
    known "$id" "$desc" "$detail"
  else
    fail "$id" "$desc" "$detail"
  fi
}

LAST_OUT=""
LAST_RC=0
# Captura saída e código sem depender de "$?" depois do assignment (SC2181).
run() {
  LAST_RC=0
  LAST_OUT="$("$@" 2>&1)" || LAST_RC=$?
}

assert_cmd() {
  local id="$1" desc="$2" want="$3" text="${4:-}"
  local ok=1 detail=""
  if [[ $want == 0 ]]; then
    ((LAST_RC == 0)) || { ok=0; detail="rc=$LAST_RC (esperava sucesso)"; }
  else
    ((LAST_RC != 0)) || { ok=0; detail="rc=$LAST_RC (esperava recusa/falha)"; }
  fi
  if ((ok == 1)) && [[ -n $text && $LAST_OUT != *"$text"* ]]; then
    ok=0; detail="saída sem '$text'"
  fi
  if ((ok == 1)); then
    pass "$id" "$desc"
  else
    fail_or_known "$id" "$desc" "$detail"$'\n'"$LAST_OUT"
  fi
}

assert_file() {
  [[ -f $3 ]] && pass "$1" "$2" || fail_or_known "$1" "$2" "arquivo ausente: $3"
}
assert_exec() {
  [[ -x $3 ]] && pass "$1" "$2" || fail_or_known "$1" "$2" "não executável: $3"
}
assert_owner_root() {
  local u
  u="$(stat -c %u "$3" 2>/dev/null || true)"
  [[ $u == 0 ]] && pass "$1" "$2" || fail_or_known "$1" "$2" "dono=${u:-?} (esperado root): $3"
}
assert_mode_secure() {
  local m
  m="$(stat -c %a "$3" 2>/dev/null || true)"
  if [[ -n $m ]] && (( (8#$m & 8#022) == 0 )); then
    pass "$1" "$2"
  else
    fail_or_known "$1" "$2" "modo=${m:-?} gravável por grupo/outros: $3"
  fi
}
assert_grep() {
  if [[ -f $4 ]] && grep -q -- "$3" "$4"; then
    pass "$1" "$2"
  else
    fail_or_known "$1" "$2" "'$3' não encontrado em $4"
  fi
}
# ─── fase 0: preflight ──────────────────────────────────────────────────────
phase0() {
  section "Fase 0 — preflight do sistema instalado (somente leitura)"

  if [[ ${XDG_CURRENT_DESKTOP:-} == *niri* && ${XDG_SESSION_DESKTOP:-} == *niri* ]]; then
    pass "PRE-NIRI" "sessão niri (${XDG_CURRENT_DESKTOP})"
  else
    skip "PRE-NIRI" "sessão atual não é niri (${XDG_CURRENT_DESKTOP:-?}); fase 0 não se aplica"
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ ${ID:-} == fedora ]]; then
      pass "PRE-OS" "Fedora ${VERSION_ID:-?}"
    else
      fail "PRE-OS" "esperava Fedora, encontrei ${ID:-?}"
    fi
  else
    fail "PRE-OS" "/etc/os-release ausente"
  fi

  if [[ $HELPER == "$DEFAULT_HELPER" ]]; then
    assert_file "PRE-HELPER" "helper instalado" "$HELPER"
    assert_exec "PRE-HELPER-EXEC" "helper executável" "$HELPER"
    assert_owner_root "PRE-HELPER-OWNER" "helper de root" "$HELPER"
    assert_mode_secure "PRE-HELPER-MODE" "helper sem escrita de grupo/outros" "$HELPER"
    run "$HELPER" version
    assert_cmd "PRE-HELPER-VERSION" "helper responde version" 0 "omyfedora-priv"
    run "$HELPER" --help
    assert_cmd "PRE-HELPER-HELP" "helper responde --help" 0 "dnf-install"
  else
    skip "PRE-HELPER" "usando --helper $HELPER (modo repositório/CI); pulando checagens de instalação"
  fi

  if [[ $POLICY_FILE == "$DEFAULT_POLICY" ]]; then
    assert_file "PRE-POLICY" "política polkit instalada" "$POLICY_FILE"
    assert_owner_root "PRE-POLICY-OWNER" "política de root" "$POLICY_FILE"
    if [[ -n "$(stat -c %a "$POLICY_FILE" 2>/dev/null || true)" ]]; then
      local pmode
      pmode="$(stat -c %a "$POLICY_FILE")"
      if [[ $pmode == 644 ]]; then
        pass "PRE-POLICY-MODE" "política com modo 644"
      else
        fail "PRE-POLICY-MODE" "política com modo $pmode (esperava 644)"
      fi
    fi
    if command -v pkaction >/dev/null 2>&1; then
      local a
      for a in dnf-install dnf-simulate-remove dnf-remove svc-enable svc-disable svc-restart; do
        run pkaction --action-id "org.omyfedora.priv.${a}"
        assert_cmd "PRE-PKACTION-${a}" "ação ${a} carregada no polkit" 0
      done
      run pkaction --action-id org.omyfedora.priv.dnf-install --verbose
      assert_cmd "PRE-PKACTION-ANNOT" "ação usa a anotação exec.argv1" 0 "exec.argv1"
    else
      fail "PRE-PKACTION" "pkaction ausente (pacote polkit)"
    fi
  else
    skip "PRE-POLICY" "usando --policy $POLICY_FILE (modo repositório/CI)"
  fi

  if [[ -f "$CONF_DIR/allowed-units.list" && -f "$CONF_DIR/protected.list" ]]; then
    assert_owner_root "PRE-CONF-OWNER" "listas de /etc/omyfedora são de root" "$CONF_DIR/protected.list"
    assert_mode_secure "PRE-CONF-MODE" "listas sem escrita de grupo/outros" "$CONF_DIR/protected.list"
  else
    fail "PRE-CONF" "listas ausentes em $CONF_DIR"
  fi

  if [[ -d $LOG_DIR ]]; then
    assert_owner_root "PRE-LOG-OWNER" "diretório de log é de root" "$LOG_DIR"
    assert_mode_secure "PRE-LOG-MODE" "diretório de log sem escrita de grupo/outros" "$LOG_DIR"
  else
    fail "PRE-LOG" "diretório de log ausente: $LOG_DIR"
  fi

  if command -v pgrep >/dev/null 2>&1 \
     && pgrep -u "$(id -u)" -f 'polkit-kde-authentication-agent' >/dev/null 2>&1; then
    pass "PRE-POLKIT-AGENT" "agente polkit-kde rodando na sessão"
  else
    fail "PRE-POLKIT-AGENT" \
      "agente polkit-kde não está rodando; instale polkit-kde e adicione"$'\n' \
      '  spawn-at-startup "/usr/libexec/kf6/polkit-kde-authentication-agent-1"'$'\n' \
      'ao ~/.config/niri/config.kdl (fora do bloco binds)'
  fi

  if [[ -f "$HOME/.config/niri/config.kdl" ]]; then
    assert_grep "PRE-NIRI-POLKIT" \
      "config do niri inicia o agente polkit" \
      'polkit-kde-authentication-agent-1' "$HOME/.config/niri/config.kdl"
  else
    fail "PRE-NIRI-POLKIT" "config do niri ausente: $HOME/.config/niri/config.kdl"
  fi

  local missing=() p
  for p in niri noctalia greetd polkit polkit-kde tuned dolphin konsole; do
    rpm -q "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if ((${#missing[@]} == 0)); then
    pass "PRE-STACK" "stack essencial instalado (niri, Noctalia, greetd, polkit-kde, KDE apps)"
  else
    fail "PRE-STACK" "pacotes essenciais ausentes: ${missing[*]}"
  fi

  run dnf --version
  assert_cmd "PRE-DNF5" "dnf5 disponível" 0 "5."

  if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce 2>/dev/null || true)" == Enforcing ]]; then
    local ctx
    ctx="$(stat -c %C "$HELPER" 2>/dev/null || true)"
    if [[ $ctx == *":bin_t:"* ]]; then
      pass "PRE-SELINUX-BIN" "helper rotulado como bin_t ($ctx)"
    else
      fail_or_known "PRE-SELINUX-BIN" \
        "helper com contexto SELinux ${ctx:-?} (esperado bin_t)" \
        "corrija com: sudo semanage fcontext -a -t bin_t '$HELPER' && sudo restorecon -v '$HELPER'"
    fi
  else
    skip "PRE-SELINUX-BIN" "SELinux não está em enforcing"
  fi

  if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} && -n ${XDG_SESSION_ID:-} ]]; then
    pass "PRE-SESSION" "sessão D-Bus ativa (XDG_SESSION_ID=${XDG_SESSION_ID})"
  else
    fail "PRE-SESSION" "sem DBUS_SESSION_BUS_ADDRESS/XDG_SESSION_ID; rode de dentro da sessão niri"
  fi

  assert_file "PRE-SKILL" "SKILL.md instalada" "$SKILL_DIR/SKILL.md"
  assert_grep "PRE-SKILL-NAME" "frontmatter name: omyfedora" '^name: omyfedora' "$SKILL_DIR/SKILL.md"
  local ref
  for ref in niri noctalia fedora-dnf propriedade seguranca local; do
    assert_file "PRE-SKILL-REF-${ref}" "references/${ref}.md" "$SKILL_DIR/references/${ref}.md"
  done
  if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
    local owner uid
    uid="$(id -u)"
    owner="$(stat -c %u "$SKILL_DIR/SKILL.md" 2>/dev/null || true)"
    if [[ $owner == "$uid" ]]; then
      pass "PRE-SKILL-OWNER" "skill pertence ao usuário-alvo"
    else
      fail "PRE-SKILL-OWNER" "skill com dono ${owner:-?} (esperado uid $uid)"
    fi
  fi

  if command -v niri >/dev/null 2>&1 && [[ -f "$HOME/.config/niri/config.kdl" ]]; then
    run niri validate -c "$HOME/.config/niri/config.kdl"
    assert_cmd "PRE-NIRI-VALIDATE" "config atual do niri é válida" 0
  else
    skip "PRE-NIRI-VALIDATE" "niri ou config.kdl ausente"
  fi
}

# ─── fase 1: estática + dry-run (sem senha) ─────────────────────────────────
phase1() {
  section "Fase 1 — validação estática + dry-run (sem senha)"

  if command -v python3 >/dev/null 2>&1; then
    run python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' "$POLICY_FILE"
    assert_cmd "STATIC-POLICY-XML" ".policy é XML válido" 0
  elif command -v xmllint >/dev/null 2>&1; then
    run xmllint --noout "$POLICY_FILE"
    assert_cmd "STATIC-POLICY-XML" ".policy é XML válido" 0
  else
    skip "STATIC-POLICY-XML" "nem python3 nem xmllint disponíveis"
  fi

  # Caminho absoluto nos comandos de dry-run da skill.
  if [[ -f "$SKILL_DIR/SKILL.md" && -f "$SKILL_DIR/references/fedora-dnf.md" ]]; then
    local line bad=0 offending=""
    while IFS= read -r line; do
      if [[ $line != *"/usr/local/libexec/omyfedora-priv --dry-run"* ]]; then
        bad=1
        offending+="$line"$'\n'
      fi
    done < <(grep -h -- 'omyfedora-priv --dry-run' \
      "$SKILL_DIR/SKILL.md" "$SKILL_DIR/references/fedora-dnf.md" 2>/dev/null || true)
    if ((bad == 0)); then
      pass "STATIC-PATH" "dry-run documentado com caminho absoluto"
    else
      fail_or_known "STATIC-PATH" "dry-run sem /usr/local/libexec no caminho" "$offending"
    fi
  else
    skip "STATIC-PATH" "skill não encontrada em $SKILL_DIR"
  fi

  local bad_units=()
  grep -q -- 'systemd-oomd.service' "$HELPER" 2>/dev/null && bad_units+=("systemd-oomd")
  grep -q -- 'power-profiles-daemon.service' "$HELPER" 2>/dev/null && bad_units+=("power-profiles-daemon")
  if ((${#bad_units[@]} == 0)); then
    pass "STATIC-UNITS" "allowlist não expõe systemd-oomd nem power-profiles-daemon"
  else
    fail_or_known "STATIC-UNITS" \
      "allowlist permite unidades que o projeto não deveria expor: ${bad_units[*]}"
  fi

  local missing_prot=() p
  for p in kde-connect kfind dragon elisa-player plasma-systemmonitor kinfocenter \
           plasma-systemsettings pam-kwallet kde-gtk-config kglobalacceld kate \
           zsh python3 plasma-desktop plasmalogin; do
    grep -q -- "'$p'" "$HELPER" 2>/dev/null || missing_prot+=("$p")
  done
  grep -q -- "dolphin(-" "$HELPER" 2>/dev/null && missing_prot+=("dolphin(-.*) protege dolphin-emu")
  if ((${#missing_prot[@]} == 0)); then
    pass "STATIC-PROTECTED" "protegidos alinhados com o conjunto KDE/shell do projeto"
  else
    fail_or_known "STATIC-PROTECTED" \
      "protegidos ausentes/incorretos: ${missing_prot[*]}"
  fi

  local bad_dnf=()
  grep -q -- '--color=never' "$HELPER" 2>/dev/null || bad_dnf+=("--color=never")
  grep -q -- '--no-autoremove' "$HELPER" 2>/dev/null || bad_dnf+=("--no-autoremove")
  if ((${#bad_dnf[@]} == 0)); then
    pass "STATIC-DNF" "chamadas do dnf com cor desligada e sem autoremove explícito"
  else
    fail_or_known "STATIC-DNF" "faltam opções seguras no helper: ${bad_dnf[*]}"
  fi

  if [[ -f $STAGE ]]; then
    local bad_stage=()
    grep -q -- 'polkit-kde-authentication-agent' "$STAGE" 2>/dev/null || bad_stage+=("check do agente polkit")
    grep -qE -- 'semanage|chcon' "$STAGE" 2>/dev/null || bad_stage+=("contexto SELinux bin_t")
    grep -q -- 'skills/noctalia-plugin' "$STAGE" 2>/dev/null || bad_stage+=("skill noctalia-plugin")
    if ((${#bad_stage[@]} == 0)); then
      pass "STATIC-INTEGRATION" "etapa checa agente polkit, rótulo SELinux e instala as duas skills"
    else
      fail_or_known "STATIC-INTEGRATION" "etapa sem: ${bad_stage[*]}"
    fi
  else
    skip "STATIC-INTEGRATION" "etapa 60 não encontrada em $STAGE"
  fi

  # Skill noctalia-plugin: fonte no repositório (o CI não tem Noctalia instalado,
  # então aqui validamos estrutura/frontmatter; o lint de plugin exige o binário).
  local NP_SKILL="$REPO_ROOT/assets/agents/skills/noctalia-plugin"
  assert_file "STATIC-NP-SKILL" "SKILL.md da skill noctalia-plugin" "$NP_SKILL/SKILL.md"
  assert_grep "STATIC-NP-NAME" "frontmatter name: noctalia-plugin" '^name: noctalia-plugin' "$NP_SKILL/SKILL.md"
  assert_grep "STATIC-NP-DESC" "descrição cita o padrão de cores/gap" 'paleta do sistema' "$NP_SKILL/SKILL.md"
  local np_ref
  for np_ref in design manifest entries ui runtime niri testing search examples; do
    assert_file "STATIC-NP-REF-${np_ref}" "references/${np_ref}.md" "$NP_SKILL/references/${np_ref}.md"
  done
  local np_ex
  for np_ex in minimal-widget niri-panel theme-probe; do
    assert_file "STATIC-NP-EX-${np_ex}" "exemplo ${np_ex} com manifesto" "$NP_SKILL/examples/${np_ex}/plugin.toml"
  done

  if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
    assert_grep "STATIC-SKILL-NAME" "frontmatter da skill" '^name: omyfedora' "$SKILL_DIR/SKILL.md"
    assert_grep "STATIC-SKILL-DESC" "descrição da skill" '^description:' "$SKILL_DIR/SKILL.md"
  else
    skip "STATIC-SKILL-NAME" "SKILL.md ausente"
  fi

  # Matriz de validação de argumentos (não executa dnf/systemctl).
  run "$HELPER" --dry-run dnf-install htop
  assert_cmd "DRY-INSTALL-OK" "aceita pacote válido (htop)" 0 "dry-run"
  run "$HELPER" --dry-run dnf-install tuned
  assert_cmd "DRY-INSTALL-TUNED" "aceita pacote válido (tuned)" 0 "dry-run"
  run "$HELPER" --dry-run dnf-install 'libreoffice*'
  assert_cmd "DRY-INSTALL-GLOB" "recusa glob" 1 "inválido"
  run "$HELPER" --dry-run dnf-install -y
  assert_cmd "DRY-INSTALL-OPT" "recusa opção (-y)" 1 "inválido"
  run "$HELPER" --dry-run dnf-install 'https://exemplo/x.rpm'
  assert_cmd "DRY-INSTALL-URL" "recusa URL" 1 "inválido"
  run "$HELPER" --dry-run dnf-install '../etc/passwd'
  assert_cmd "DRY-INSTALL-PATH" "recusa caminho" 1 "inválido"
  run "$HELPER" --dry-run dnf-install 'tuned;reboot'
  assert_cmd "DRY-INSTALL-SEMI" "recusa metacaractere de shell" 1 "inválido"
  run "$HELPER" --dry-run dnf-install @core
  assert_cmd "DRY-INSTALL-GROUP" "recusa grupo (@core)" 1 "inválido"
  run "$HELPER" --dry-run dnf-install
  assert_cmd "DRY-INSTALL-EMPTY" "recusa lista vazia" 1 "informe"
  local many=() i
  for i in {1..21}; do many+=("pacote$i"); done
  run "$HELPER" --dry-run dnf-install "${many[@]}"
  assert_cmd "DRY-INSTALL-MAX" "recusa mais de 20 pacotes" 1 "máximo"

  run "$HELPER" --dry-run dnf-remove htop
  assert_cmd "DRY-REMOVE-NORMAL" "aceita remoção de nome válido (htop)" 0 "removeria"
  run "$HELPER" --dry-run dnf-remove dolphin
  assert_cmd "DRY-REMOVE-DOLPHIN" "recusa remover dolphin (protegido)" 1 "protegido"
  run "$HELPER" --dry-run dnf-remove bash
  assert_cmd "DRY-REMOVE-BASH" "recusa remover bash (protegido)" 1 "protegido"
  run "$HELPER" --dry-run dnf-remove niri
  assert_cmd "DRY-REMOVE-NIRI" "recusa remover niri (protegido)" 1 "protegido"
  run "$HELPER" --dry-run dnf-remove systemd
  assert_cmd "DRY-REMOVE-SYSTEMD" "recusa remover systemd (protegido)" 1 "protegido"

  run "$HELPER" --dry-run svc-enable tuned
  assert_cmd "DRY-SVC-ALLOWED" "aceita unidade permitida (tuned)" 0 "systemctl enable"
  run "$HELPER" --dry-run svc-enable greetd
  assert_cmd "DRY-SVC-GREETD" "recusa greetd" 1 "fora da lista"
  run "$HELPER" --dry-run svc-enable NetworkManager.service
  assert_cmd "DRY-SVC-NM" "recusa NetworkManager" 1 "fora da lista"
  run "$HELPER" --dry-run svc-disable systemd-oomd.service
  assert_cmd "DRY-SVC-OOMD" "recusa systemd-oomd (projeto depende dele)" 1 "fora da lista"
  run "$HELPER" --dry-run svc-enable power-profiles-daemon.service
  assert_cmd "DRY-SVC-PPD" "recusa power-profiles-daemon (conflita com tuned-ppd)" 1 "fora da lista"
  run "$HELPER" --dry-run svc-enable tuned.service firewalld.service
  assert_cmd "DRY-SVC-TWO" "recusa mais de uma unidade" 1 "exatamente uma"
  run "$HELPER" --dry-run svc-enable 'tuned.service; reboot'
  assert_cmd "DRY-SVC-INVALID" "recusa nome de unidade inválido" 1 "inválido"
  run "$HELPER" --dry-run comando-desconhecido
  assert_cmd "DRY-UNKNOWN" "recusa subcomando desconhecido" 1 "desconhecido"
}

# ─── fase 2: pkexec (senha; não altera nada) ────────────────────────────────
phase2() {
  section "Fase 2 — simulações e validações via pkexec (senha; não altera nada)"

  if [[ $HELPER != "$DEFAULT_HELPER" || ! -x $HELPER ]]; then
    skip "PK-*" "helper instalado não encontrado; fase 2 exige /usr/local/libexec/omyfedora-priv"
    return 0
  fi
  if ! command -v pkexec >/dev/null 2>&1; then
    fail "PK-PKEXEC" "pkexec ausente (pacote polkit)"
    return 0
  fi

  local simpkg=""
  local p
  for p in htop filelight kamoso skanpage; do
    if rpm -q "$p" >/dev/null 2>&1; then simpkg="$p"; break; fi
  done

  printf '%s\n' \
    "  A fase 2 vai abrir a janela do polkit. NÃO cancele; a senha é sua." \
    "  Só há simulação (dnf --assumeno) e validação de argumentos; nada é alterado." \
    "  A simulação usa auth_admin_keep por 5 min; as demais pedem senha a cada ação."

  if [[ -n $simpkg ]]; then
    printf '  → simulando remoção de %s\n' "$simpkg"
    run pkexec "$HELPER" dnf-simulate-remove "$simpkg"
    assert_cmd "PK-SIM-REMOVE" "simula remoção real ($simpkg) sem alterar" 0 "Seriam removidos"
    if rpm -q "$simpkg" >/dev/null 2>&1; then
      pass "PK-SIM-NOOP" "$simpkg continua instalado depois da simulação"
    else
      fail "PK-SIM-NOOP" "$simpkg desapareceu depois de uma simulação!"
    fi
  else
    skip "PK-SIM-REMOVE" "nenhum pacote de teste instalado (htop/filelight/kamoso/skanpage)"
  fi

  printf '  → testando recusa de remoção de pacote protegido (dolphin)\n'
  run pkexec "$HELPER" dnf-simulate-remove dolphin
  assert_cmd "PK-REFUSE-DOLPHIN" "recusa remover dolphin (protegido)" 1 "protegido"

  printf '  → testando recusa de remoção de pacote base (bash)\n'
  run pkexec "$HELPER" dnf-simulate-remove bash
  assert_cmd "PK-REFUSE-BASH" "recusa remover bash (protegido)" 1 "protegido"

  printf '  → testando recusa de remoção do compositor (niri)\n'
  run pkexec "$HELPER" dnf-simulate-remove niri
  assert_cmd "PK-REFUSE-NIRI" "recusa remover niri (protegido)" 1 "protegido"

  printf '  → testando validação de nome de pacote no pkexec\n'
  run pkexec "$HELPER" dnf-install 'libreoffice*'
  assert_cmd "PK-INVALID-PKG" "recusa glob antes de chamar o dnf" 1 "inválido"

  printf '  → testando validação de unidade no pkexec\n'
  run pkexec "$HELPER" svc-enable 'tuned.service; reboot'
  assert_cmd "PK-INVALID-UNIT" "recusa metacaractere antes de chamar o systemctl" 1 "inválido"

  skip "PK-UNITS-ALLOWLIST" \
    "recusas de greetd/NetworkManager testadas no dry-run; não executamos svc-* real aqui para não arriscar a sessão"
}

# ─── fase 3: mutações reversíveis ───────────────────────────────────────────
INSTALLED_BY_TEST=0
TEST_PKG=""
TEST_SVC=""
SVC_ORIG_ENABLED=""
SVC_ORIG_ACTIVE=""

pick_test_pkg() {
  local p
  for p in cowsay sl figlet tree; do
    rpm -q "$p" >/dev/null 2>&1 && continue
    dnf -q info "$p" >/dev/null 2>&1 && { printf '%s' "$p"; return 0; }
  done
  return 1
}

pick_test_svc() {
  local s en act
  for s in avahi-daemon.service cups.service; do
    systemctl list-unit-files --no-legend "$s" 2>/dev/null | grep -q "^${s}" || continue
    en="$(systemctl is-enabled "$s" 2>/dev/null || true)"
    act="$(systemctl is-active "$s" 2>/dev/null || true)"
    case "${en}:${act}" in
      enabled:active|disabled:inactive)
        printf '%s' "$s"; return 0 ;;
    esac
  done
  return 1
}

restore_service() {
  [[ -n $TEST_SVC && $SVC_ORIG_ENABLED == enabled ]] || return 0
  run pkexec "$HELPER" svc-enable "$TEST_SVC"
  assert_cmd "MUT-SVC-RESTORE" "restaura $TEST_SVC ao estado original (habilitado/ativo)" 0
}

phase3() {
  section "Fase 3 — mutações reversíveis (instala/remove pacote de teste; habilita/desabilita serviço)"

  if ((MUTATING == 0)); then
    skip "MUT-*" "fase 3 desabilitada (use --mutating)"
    return 0
  fi
  if [[ $HELPER != "$DEFAULT_HELPER" || ! -x $HELPER ]]; then
    skip "MUT-*" "helper instalado não encontrado"
    return 0
  fi

  TEST_PKG="$(pick_test_pkg || true)"
  TEST_SVC="$(pick_test_svc || true)"
  if [[ -z $TEST_PKG && -z $TEST_SVC ]]; then
    skip "MUT-*" "não encontrei pacote de teste nem serviço adequado; nada a mutar"
    return 0
  fi

  if ((YES == 0)); then
    if [[ ! -t 0 ]]; then
      fail "MUT-CONFIRM" "sem TTY; rode com --yes SÓ depois de o usuário aprovar as mutações"
      return 0
    fi
    printf '\n%sA fase 3 vai:%s\n' "$C_HEAD" "$C_RST"
    [[ -n $TEST_PKG ]] && printf '  • instalar e remover o pacote de teste: %s\n' "$TEST_PKG"
    [[ -n $TEST_SVC ]] && printf '  • habilitar/desabilitar e restaurar o serviço: %s\n' "$TEST_SVC"
    printf '  • reiniciar o tuned (sem mudar configuração), se estiver ativo\n'
    printf '  • deixar entradas no dnf history (desfazíveis) e no /var/log/omyfedora\n'
    read -r -p "Continuar? [s/N] " ans || ans=""
    if [[ ! $ans =~ ^[sSyY] ]]; then
      skip "MUT-*" "não confirmado pelo usuário"
      return 0
    fi
  fi

  printf '  A fase 3 abre a janela do polkit várias vezes (instalar, simular, remover, serviço).\n'

  if [[ -n $TEST_PKG ]]; then
    run pkexec "$HELPER" dnf-install "$TEST_PKG"
    if ((LAST_RC == 0)) && rpm -q "$TEST_PKG" >/dev/null 2>&1; then
      pass "MUT-INSTALL" "instalou o pacote de teste $TEST_PKG"
      INSTALLED_BY_TEST=1
      run pkexec "$HELPER" dnf-simulate-remove "$TEST_PKG"
      assert_cmd "MUT-SIM-REMOVE" "simula a remoção do pacote de teste" 0 "Seriam removidos"
      run pkexec "$HELPER" dnf-remove "$TEST_PKG"
      if ((LAST_RC == 0)) && ! rpm -q "$TEST_PKG" >/dev/null 2>&1; then
        pass "MUT-REMOVE" "removeu o pacote de teste $TEST_PKG"
        INSTALLED_BY_TEST=0
      else
        fail_or_known "MUT-REMOVE" "falhou ao remover o pacote de teste $TEST_PKG" "$LAST_OUT"
      fi
    else
      fail_or_known "MUT-INSTALL" "falhou ao instalar o pacote de teste $TEST_PKG" "$LAST_OUT"
    fi
  else
    skip "MUT-PKG" "nenhum pacote de teste disponível nos repositórios habilitados"
  fi

  if systemctl is-active --quiet tuned 2>/dev/null; then
    run pkexec "$HELPER" svc-restart tuned
    assert_cmd "MUT-RESTART-TUNED" "reiniciou tuned (unidade permitida)" 0
    if systemctl is-active --quiet tuned 2>/dev/null; then
      pass "MUT-RESTART-ACTIVE" "tuned continua ativo depois do restart"
    else
      fail "MUT-RESTART-ACTIVE" "tuned não está ativo depois do restart"
    fi
  else
    skip "MUT-RESTART-TUNED" "tuned não está ativo"
  fi

  if [[ -n $TEST_SVC ]]; then
    SVC_ORIG_ENABLED="$(systemctl is-enabled "$TEST_SVC" 2>/dev/null || true)"
    SVC_ORIG_ACTIVE="$(systemctl is-active "$TEST_SVC" 2>/dev/null || true)"
    printf '  → serviço de teste %s (original: %s/%s)\n' "$TEST_SVC" "$SVC_ORIG_ENABLED" "$SVC_ORIG_ACTIVE"
    run pkexec "$HELPER" svc-enable "$TEST_SVC"
    if ((LAST_RC == 0)) \
       && [[ "$(systemctl is-enabled "$TEST_SVC" 2>/dev/null || true)" == enabled ]] \
       && [[ "$(systemctl is-active "$TEST_SVC" 2>/dev/null || true)" == active ]]; then
      pass "MUT-SVC-ENABLE" "habilitou e iniciou $TEST_SVC"
    else
      fail_or_known "MUT-SVC-ENABLE" "falhou ao habilitar/iniciar $TEST_SVC" "$LAST_OUT"
    fi
    run pkexec "$HELPER" svc-disable "$TEST_SVC"
    if ((LAST_RC == 0)) \
       && [[ "$(systemctl is-enabled "$TEST_SVC" 2>/dev/null || true)" == disabled ]] \
       && [[ "$(systemctl is-active "$TEST_SVC" 2>/dev/null || true)" != active ]]; then
      pass "MUT-SVC-DISABLE" "desabilitou e parou $TEST_SVC"
    else
      fail_or_known "MUT-SVC-DISABLE" "falhou ao desabilitar/parar $TEST_SVC" "$LAST_OUT"
    fi
    if [[ $SVC_ORIG_ENABLED == enabled ]]; then
      restore_service
    else
      pass "MUT-SVC-RESTORE" "$TEST_SVC já estava desabilitado/inativo; estado final correto"
    fi
  else
    skip "MUT-SVC" "nenhum serviço de teste adequado (avahi-daemon/cups) encontrado"
  fi

  if ((INSTALLED_BY_TEST == 1)) && [[ -n $TEST_PKG ]] && rpm -q "$TEST_PKG" >/dev/null 2>&1; then
    printf '  Limpando o pacote de teste que ficou instalado após uma falha...\n'
    run pkexec "$HELPER" dnf-remove "$TEST_PKG"
    assert_cmd "MUT-CLEANUP" "removeu o pacote de teste após falha" 0
  fi
}

# ─── fase 4/5: manual ───────────────────────────────────────────────────────
phase4() {
  section "Fase 4 — comportamento da skill (manual)"
  cat <<EOF
  Abra e conduza com o usuário:

    $REPO_ROOT/tests/agent-skill/scenarios.md

  O agente deve seguir o SKILL.md: descrever → perguntar → backup → aplicar →
  validar → mostrar o diff → registrar. O usuário marca PASS/FAIL em cada
  cenário; os resultados são a evidência comportamental da skill.

  Não marque PASS sozinho: quem aprova é o usuário.
EOF
}

phase5() {
  section "Fase 5 — trilha de auditoria (manual)"
  cat <<EOF
  Peça ao usuário para rodar (o log é 0750 root, por isso o sudo):

    sudo tail -n 40 $LOG_DIR/actions.log

  Esperado: linhas "EXEC"/"SIMULATE-REMOVE"/"DENY" com o uid e o comando, e
  "RESULT rc=..." depois de cada execução. Confira que:
    • as recusas do teste aparecem como DENY;
    • o install/remove do pacote de teste aparece como EXEC + RESULT;
    • não há linha de outro usuário no intervalo do teste.
EOF
}

summary() {
  printf '\n%sResumo%s: %d PASS · %d FAIL · %d KNOWN · %d SKIP\n' \
    "$C_HEAD" "$C_RST" "$PASS" "$FAIL" "$KNOWN" "$SKIP"
  if ((${#FAILED_IDS[@]} > 0)); then
    printf 'Falhas: %s\n' "${FAILED_IDS[*]}"
  fi
  if ((${#KNOWN_SEEN[@]} > 0)); then
    printf 'Conhecidas (baseline): %s\n' "${KNOWN_SEEN[*]}"
  fi
  printf 'Relatório: %s\n' "$REPORT"
  if ((FAIL > 0)); then
    printf '\n%sHá falhas inesperadas.%s Corrija ou rode com --known-issues para separar o\n' "$C_FAIL" "$C_RST"
    printf 'que já está documentado em tests/agent-skill/README.md.\n'
    exit 1
  fi
  printf '\nNenhuma falha inesperada.\n'
  exit 0
}

for phase in "${SELECTED[@]}"; do
  case "$phase" in
    0) phase0 ;;
    1) phase1 ;;
    2) phase2 ;;
    3) phase3 ;;
    4) phase4 ;;
    5) phase5 ;;
  esac
done

summary
