# Agentic OS — Sistema operacional com UI de chat controlada por IA

> Documento de ideia e direção técnica. Não é o MyOS atual (rota C com scripts bash), mas uma
> variante/evolução: um OS onde o chat de IA é a interface central e controla o sistema com
> guardrails, sem sacrificar o uso "normal" de um desktop.

## 1. Visão

Um sistema GNU/Linux completo e usável no dia a dia (apps, jogos, multimídia, dev), mas cuja
interface primária é um **chat de IA** capaz de:

- instalar e desinstalar aplicativos;
- alterar configurações do sistema e da UI;
- criar e gerenciar rotinas (tarefas agendadas, automações);
- criar widgets e personalizações na interface via plugins.

O diferencial não é "um OS com um chatbot". É um OS onde **o estado desejado é descrito em
linguagem natural** e um agente traduz isso em ações seguras, verificáveis e reversíveis — com
guardrails que impedem que o agente ou o usuário matem o sistema.

## 2. Princípios de design

1. **Base imutável, camadas mutáveis.** O sistema base é uma imagem OCI com atualização
   transacional e rollback. Tudo que muda com frequência fica em camadas acima da base:
   Flatpak, containers (Distrobox), configs em `$HOME`, serviços de usuário.
2. **Privilégio mínimo para o agente.** O agente nunca tem shell root livre. Ele opera via um
   daemon com API restrita (D-Bus + polkit), allowlist de operações e auditoria.
3. **Toda mudança é reversível.** Antes de aplicar, gera plano + diff; guarda backup; oferece
   undo no chat e rollback de boot para mudanças de base.
4. **UI plugável.** Widgets e rotinas são plugins instaláveis/atualizáveis sem tocar no core.
5. **Usável sem o agente.** Se a IA falhar, estiver offline ou o usuário quiser, o desktop
   continua 100% funcional como um OS normal.
6. **O sistema se adapta ao usuário no primeiro boot.** Onboarding guiado por perguntas monta
   um sistema já personalizado, eliminando a instalação manual de apps e ajustes.

## 3. Base Linux — pesquisa e decisão

| Opção | Estável para agente? | Facilitada? | Observações |
|---|---|---|---|
| **Fedora bootc / Atomic** (Silverblue, Kinoite, uBlue) | Sim | Sim | `/usr` somente leitura, updates transacionais + rollback, Flatpak e Toolbx/Distrobox nativos, SELinux, build de imagem via OCI | 
| NixOS | Sim (rollback e declarativo excelentes) | Não | Curva alta, ecossistema Flatpak fraco, IA gera Nix com erro com frequência |
| openSUSE Aeon / Vanilla OS | Médio | Médio | Conceito similar, ecossistema menor, menos imagens prontas e menos documentação |
| Arch / Fedora Workstation tradicional | Não | Sim (para dev) | `dnf` direto na base + agente = boot quebrado sem rollback |

**Decisão: Fedora bootc** (sucessor do rpm-ostree):

- imagem própria com `FROM quay.io/fedora/fedora-bootc`;
- o agente nunca roda `dnf` na base. Ações permitidas: `flatpak`, `distrobox`, `bootc upgrade`,
  configs de usuário e `systemctl --user`;
- operações privilegiadas via daemon com allowlist + polkit + confirmação no chat;
- rollback no boot resolve o pior caso ("agente quebrou o sistema").

O MyOS atual (scripts bash idempotentes) vira a **base da imagem bootc**: o que hoje é
`10-gpu.sh`…`50-configs.sh` passa a ser construído na imagem, e o que é personalização vira
camada de runtime.

## 4. Ambiente gráfico — pesquisa e decisão

| Opção | Estável? | Widget/plugin por IA? | Observações |
|---|---|---|---|
| **KDE Plasma 6 (Kinoite)** | Sim | Sim (Plasmoids em QML/JS, KRunner, D-Bus) | Melhor custo-benefício para MVP; Wayland maduro; IA gera QML com facilidade |
| **Niri + Noctalia/Quickshell** | Médio | Sim (plugins Noctalia em QML/JS) | Leve (<600 MB idle, alvo do MyOS), mas nicho: todo bug do compositor é seu |
| COSMIC (System76) | Alpha | Médio (applets em Rust) | Promissor, sem base Fedora oficial e toolchain mais dura para IA |
| GNOME Shell | Sim | Não | Extensions quebram a cada versão; inviável para widgets gerados por IA |
| Hyprland | Não | Não | Quebra com updates, config manual, portais/polkit imaturos |

**Decisão em duas fases:**

- **Fase 1 (MVP estável): Fedora Kinoite bootc + Plasma 6**
  - chat como app/painel lateral sempre visível (Kirigami/QML ou Tauri);
  - widgets = Plasmoids; rotinas = systemd `--user` timers + D-Bus;
  - onboarding = `plasma-welcome` customizado com as perguntas;
  - valida agente, permissões e guardrails sem brigar com o compositor.
- **Fase 2 (porta leve): Fedora bootc minimal + Niri + Noctalia**
  - reaproveita o daemon do agente e o modelo de permissões do MVP;
  - busca o alvo de baixo uso de RAM e a shell chat-first 100% custom.

Regra: **não fazer agente + compositor custom + imutabilidade ao mesmo tempo**. Primeiro o
agente seguro no Plasma; depois a shell leve.

## 5. Arquitetura do agente e guardrails

```
Usuário ⇄ UI de chat (QML)
              │  intenção em linguagem natural
              ▼
      Orquestrador LLM (intenção → plano de ações)
              │  ações estruturadas (não shell)
              ▼
   Daemon de políticas (D-Bus) ──── polkit / auditoria / backup
              │
   ┌──────────┼──────────────┬───────────────┐
   ▼          ▼              ▼               ▼
 Flatpak   Distrobox   systemctl --user   $HOME/.config
 (apps)    (dev/CLI)   (rotinas/serviços) (configs, plugins)
```

- O LLM **não executa shell**. Ele emite um plano de ações estruturadas que o daemon valida.
- Toda ação tem: validação de sintaxe/tipo, dry-run quando possível, backup e registro de undo.

### Matriz de permissões (exemplo)

| Nível | Exemplos | Comportamento |
|---|---|---|
| Verde | `flatpak install/remove`, criar widget, editar `~/.config`, cron `--user` | Executa direto, com log |
| Amarelo | `bootc upgrade`, habilitar serviço de sistema, mudar tema/portais globalmente | Confirmação no chat com diff + explicação |
| Vermelho | Comandos na base (`rpm-ostree`/`dnf` em `/usr`), `rm -rf` fora de `$HOME`, alterar PAM/SELinux/kernel, drivers | Bloqueado; no máximo sugere procedimento manual documentado |

## 6. Apps: como instalar sem quebrar a base

- **GUI**: Flatpak (containerizado, permissões por app via `flatpak override` — o agente pode
  ajustar as permissões e explicar o que está concedendo).
- **Dev/CLI/stack**: Distrobox (ou Toolbx), com `.desktop` exportado.
- **Drivers/hardware**: por perfil na imagem (Intel/AMD/NVIDIA/hybrid), como o `10-gpu.sh` do
  MyOS já faz; mudança de driver = nova imagem + rollback.

## 7. Onboarding no primeiro boot

Wizard com perguntas que geram um **manifesto de personalização** (declarativo), aplicado pelo
mesmo daemon do agente:

- idioma, layout de teclado, fuso, wifi;
- perfil: dev / design / escritório / gaming / estudo / multiuso;
- apps que já usa (checklist agrupado por categoria) e stack de desenvolvimento;
- estética: tema, ícones, wallpapers, accent color, densidade;
- rotinas iniciais: backup, atualizações, limpeza, notificações;
- confirmação final com "plano de instalação" revisável antes de aplicar.

Resultado: sistema já com a cara, os apps e as ferramentas do usuário — e o manifesto fica salvo
para reinstalação/migração idêntica.

## 8. UI: chat + widgets como plugins

- O chat é a interface central: histórico, contexto do sistema (D-Bus expõe estado para o agente)
  e ações propostas clicáveis ("Instalar o Brave? [Confirmar]").
- Widgets personalizados são a extensão da UI:
  - Fase 1: Plasmoids (QML/JS) — a IA pode gerar/escaforar novos widgets a partir de templates
    validados;
  - Fase 2: plugins Noctalia (QML/JS) na shell do Niri.
- Instalação/atualização de plugin não altera a base: fica em `$HOME` e é gerenciável/removível.

## 9. Deploy e segurança

- Imagem bootc (OCI) construída em CI (GitHub Actions) e publicada em registry.
- `bootc upgrade` transacional + rollback no boot; kernel e drivers só mudam com a imagem.
- SELinux enforcing; política polkit dedicada para o daemon do agente.
- Sandbox do agente: acesso limitado por allowlist de D-Bus; nunca root direto.
- Auditoria: toda ação (prompt, plano, resultado, undo) registrada em log consultável no chat.

## 10. Desenvolvimento e testes

- `bootc-image-builder` gera QCOW2 para VM (KVM/QEMU) — ciclos de teste sem máquina física.
- Provar o protótipo em VM descartável (mesmo fluxo do `--dry-run`/`--yes` do MyOS atual).
- "Kanban" de confiabilidade: cada ação do agente precisa de teste de undo/rollback antes de
  virar ação "verde".

## 11. Roadmap por fases

| Fase | Escopo | Entrega |
|---|---|---|
| 0 | Decisões e protótipo do daemon de políticas (D-Bus + polkit + allowlist) | Prova de ações seguras de flatpak/config |
| 1 | Imagem Fedora Kinoite bootc com stack do MyOS + onboarding | VM instalável e usável |
| 2 | UI de chat integrada (painel sempre visível) + ações verdes/amarelas | Chat controla apps/config/rotinas |
| 3 | Widgets plugináveis (Plasmoids) + undo no chat | Personalização por IA |
| 4 | Porta leve: base bootc minimal + Niri + Noctalia | Alvo de RAM e shell chat-first |

## 12. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| LLM gera ação inválida ou nociva | Ações estruturadas (nunca shell), dry-run, backup, undo, rollback de boot |
| Flatpak quebra por permissions/parental controls | Manter pacotes protegidos (caso `malcontent`, já tratado no MyOS) |
| Update da base quebra plugins da UI | Plugins em `$HOME`; pinagem/calendário de upgrade; testar em VM antes |
| Custo de LLM | Provider escolhido pelo usuário; agente degrada para modo "sugerir script" |
| Escopo grande demais | Fases: Plasma antes de Niri; daemon antes de UI; VM antes de bare metal |

## 13. Relação com o MyOS atual

- **MyOS (hoje)**: rota C — scripts bash idempotentes sobre Fedora Workstation. Serve como
  fonte dos perfis de GPU, tuning, serviços e configs.
- **Agentic OS (ideia)**: evolução possível — empacotar o MyOS como imagem bootc, adicionar o
  daemon de agente e o chat. O noção de "plugáveis" e "reversível" já está no DNA dos scripts;
  a mudança principal é sair da base mutável e pôr o agente atrás de guardrails.

## 14. Questões abertas

- Provedor de LLM: local (privacidade, custo de hardware) vs nuvem (qualidade) — ou híbrido?
- Quanto de autonomia "verde" é aceitável no primeiro uso? Auto-confirmar rotinas de backup?
- UI do chat: app separado vs painel embutido no Plasma vs widget da shell?
- Como versionar/assinar plugins de widget gerados pela IA (supply chain)?
- Nome do projeto (Agentic OS é uma descrição, não um nome).
