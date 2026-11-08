# OpenCode Go (Noctalia)

Cotas do plano **OpenCode Go** na barra do Noctalia: ícone único que abre um painel com as
janelas de 5 horas, semanal e mensal.

```
OpenCode Go                    [● ok]
Créditos disponíveis                       US$ 3.65
5 horas  [████░░░░░░░░]   6% usado   reseta em 2h14m
Semanal  [██████░░░░░░]  27% usado   reseta em 3d2h
Mensal   [████░░░░░░░░]  13% usado   reseta em 12d

[Atualizar]                    [Abrir dashboard]
```

## Entradas

| ID | Tipo | Função |
|---|---|---|
| `msbos/opencode-go:status` | widget | Ícone na barra (clique abre o painel) |
| `msbos/opencode-go:panel` | panel | Cotas, botão de atualizar e dashboard |
| `msbos/opencode-go:poll` | service | Auth, consulta e cache |

## Fonte dos dados

`GET https://opencode.ai/zen/go/v1/usage` com `Authorization: Bearer <token>` — percentual e reset
das janelas de 5 horas, semanal e mensal.

`GET https://opencode.ai/console/api/billing/status` com a mesma credencial — "Available credits"
(`availableMicroCents`), exibido no topo do painel.

A credencial é relida a cada poll, nesta ordem:

1. `OPENCODE_API_KEY` (env)
2. `opencode.db` — `credential.integration_id='opencode'`, campo `access` (OAuth do
   `opencode auth login`); fallback `integration_id='opencode-go'`, campo `key`
3. `~/.local/share/opencode/auth.json` (`opencode-go`, depois `opencode`)

O token não é guardado em memória nem no log: o log registra só a fonte (`env`, `opencode.db`,
`auth.json`). Em 401/403 o painel pede para rodar `opencode auth login` de novo.

## Settings

| Chave | Tipo | Padrão | Descrição |
|---|---|---|---|
| `refresh` | int (60–900) | `300` | Segundos entre consultas |

## IPC

```bash
noctalia msg plugin msbos/opencode-go:poll all refresh   # força atualização
noctalia msg panel-toggle msbos/opencode-go:panel        # abre/fecha o painel
```

## Requisitos

- `opencode` autenticado (`opencode auth login`)
- `sqlite3` para ler o `opencode.db`

O painel mantém o último resultado em `pluginDataDir()/cache.json` e continua exibindo as cotas
quando a consulta falha.
