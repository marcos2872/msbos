# Agent Usage (Noctalia)

Uso dos agentes de IA na barra do Noctalia: um ícone único que abre um painel com **abas por
provider** — **OpenCode Go** (janelas de 5 horas, semanal e mensal + créditos do console) e
**GitHub Copilot** (créditos do ciclo, quanto foi usado, quanto resta e a data de reset).

```
[ OpenCode Go ] [ GitHub Copilot ]              ● ok
Créditos disponíveis                       US$ 3.65
5 horas  [████░░░░░░░░]   6% usado   reseta em 2h14m
Semanal  [██████░░░░░░]  27% usado   reseta em 3d2h
Mensal   [████░░░░░░░░]  13% usado   reseta em 12d

atualizado há 2m · fonte: opencode.db
[Atualizar]                    [Abrir dashboard]
```

A aba do Copilot só aparece quando há credencial dele. Com um provider só, a linha de abas não
aparece e o painel fica igual ao do antigo plugin OpenCode Go.

## Entradas

| ID | Tipo | Função |
|---|---|---|
| `msbos/agent-usage:status` | widget | Ícone na barra (clique abre o painel) |
| `msbos/agent-usage:panel` | panel | Abas por provider, botão de atualizar e link externo |
| `msbos/agent-usage:poll` | service | Auth, consulta e cache dos dois providers |

Este plugin substituiu o `msbos/opencode-go` (mesma função, agora com providers). A migração do
diretório antigo é feita pelo `scripts/50-configs.sh`.

## Fonte dos dados

### OpenCode Go

- `GET https://opencode.ai/zen/go/v1/usage` com `Authorization: Bearer <token>` — percentual e
  reset das janelas de 5 horas, semanal e mensal.
- `GET https://opencode.ai/console/api/billing/status` com a mesma credencial — "Available
  credits" (`availableMicroCents`), exibido no topo da aba.

Credencial relida a cada poll:

1. `OPENCODE_API_KEY` (env)
2. `opencode.db` — `credential.integration_id='opencode'`, campo `access` (OAuth do
   `opencode auth login`); fallback `integration_id='opencode-go'`, campo `key`
3. `~/.local/share/opencode/auth.json` (`opencode-go`, depois `opencode`)

### GitHub Copilot

- `GET https://api.github.com/copilot_internal/user` (enterprise: `https://api.<host>/…`) com
  `Authorization: Bearer <token>` — devolve `copilot_plan`, `quota_snapshots.premium_interactions`
  (`entitlement`, `credits_used`, `remaining`, `percent_remaining`, `unlimited`) e
  `quota_reset_date_utc`.
- É um **endpoint interno** do GitHub, o mesmo que os clientes oficiais usam para mostrar "quota
  usage": não é a API REST pública, não tem contrato de estabilidade e pode mudar sem aviso. Por
  isso o intervalo mínimo é de **10 minutos** (valores menores virariam 403 por excesso de
  consultas) e os erros têm mensagens próprias.
- Credencial: a mesma do OpenCode (`opencode auth login github-copilot`), lida do `opencode.db`
  (`integration_id='github-copilot'`, `access`/`refresh` + `metadata.enterpriseUrl`); fallback no
  `auth.json` legado.
- Os créditos são **1 crédito = US$ 0,01**. Em assento Business/Enterprise o `entitlement` pode ser
  o **pool da organização** (não a cota individual) — o valor exibido é o que a API reporta para a
  conta.

O token nunca é guardado em memória nem no log: o log registra só a fonte (`env`, `opencode.db`,
`auth.json`). Em 401/403 o painel pede para rodar `opencode auth login` de novo.

## Settings

| Chave | Tipo | Padrão | Descrição |
|---|---|---|---|
| `refresh` | int (60–900) | `300` | Segundos entre consultas do OpenCode Go |
| `background_mode` | select `dark`/`theme` | `dark` | Preto fixo ou fundo do tema |
| `background_opacity` | int (0–100) | `45` | Alfa do preto do painel |

## Fundo do painel

O modo `dark` replica o `msbos-ai-chat`: preto `#000000` com alfa por cima do painel inteiro
(padding negativo do inset do host) e **cores de texto travadas em tons claros**
(`#F5F7FA`/`#D2D7E1`) — com fundo fixo, um tema claro deixaria o texto escuro ilegível. Essa é a
exceção registrada ao padrão "só roles da paleta"; o modo `theme` volta ao fundo e às cores do
tema.

## IPC

```bash
noctalia msg plugin msbos/agent-usage:poll all refresh            # força os dois providers
noctalia msg plugin msbos/agent-usage:poll all provider cp        # força só um (go | cp)
noctalia msg panel-toggle msbos/agent-usage:panel                 # abre/fecha o painel
```

## Requisitos

- `opencode` autenticado (`opencode auth login`; `github-copilot` para a aba do Copilot)
- `sqlite3` para ler o `opencode.db`

O último resultado fica em `pluginDataDir()/cache.json` (versão 2) e continua sendo exibido quando
a consulta falha. O cache antigo do plugin OpenCode Go (versão 1) é migrado para a aba Go.
