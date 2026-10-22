# Integração com niri

## O que existe (e o que não existe)

O niri **não tem API de plugin** nem carrega Luau. Um “plugin do niri” na prática é um plugin do **Noctalia** que conversa com o niri por:

1. **IPC**: `niri msg ...` (com `--json` para leitura).
2. **Configuração**: `~/.config/niri/config.kdl`, validada com `niri validate`.
3. **Processos**: `niri msg action spawn -- ...` para abrir apps/comandos no compositor.

O plugin roda no Noctalia; o niri só recebe comandos e devolve estado. Não presuma que o plugin está dentro do processo do niri.

## Pré-requisitos

```bash
niri --version
niri msg version
niri msg --json focused-output
niri msg --json workspaces
```

- `NIRI_SOCKET` precisa estar no ambiente do Noctalia (sessão niri ativa).
- `niri` precisa estar no `PATH`; declare `dependencies = ["niri"]` no manifesto.
- Use `noctalia.runAsync({ "niri", ... })` com argv, nunca concatene strings de shell.

## Leituras úteis

```bash
niri msg --json outputs          # conectores, modos, escala, posição
niri msg --json focused-output   # output focado
niri msg --json workspaces       # id, idx, name, output, is_active, is_focused
niri msg --json windows          # janelas, app_id, título, workspace
niri msg --json focused-window   # janela focada
niri msg --json layers           # layer-shell surfaces
niri msg --json overview-state
```

Formatos observados (niri 26.04):

```json
// focused-output
{
  "name": "HDMI-A-1",
  "make": "LG Electronics",
  "model": "25UM58G",
  "serial": "0x0005E569",
  "physical_size": [530, 300],
  "modes": [{ "width": 2560, "height": 1080, "refresh_rate": 74973, "is_preferred": true }]
}
```

```json
// workspaces
[
  {
    "id": 3,
    "idx": 2,
    "name": null,
    "output": "HDMI-A-1",
    "is_urgent": false,
    "is_active": true,
    "is_focused": true,
    "active_window_id": 8
  }
]
```

Campos podem variar com a versão do niri; trate campos opcionais com `if value ~= nil`.

## Ações

```bash
niri msg action focus-workspace 2
niri msg action focus-window --id 123
niri msg action close-window --id 123
niri msg action spawn -- alacritty
niri msg action spawn -- sh -c 'comando'
niri msg action move-window-to-workspace 2
```

Verifique a sintaxe/argumentos exatos com:

```bash
niri msg action --help
niri msg action focus-workspace --help
niri msg action spawn --help
```

- `spawn -- <cmd> [args...]` executa direto; `spawn-sh` usa shell.
- Para dados dinâmicos, prefira argv (`spawn -- alacritty --working-directory ...`) e evite `sh -c`.
- Ações que mudam foco/janela são visíveis ao usuário: confirme antes quando a skill exigir.

## Outputs (monitores)

```bash
niri msg output DP-3 mode 2560x1440@60
niri msg output DP-3 scale 1.25
niri msg output DP-3 transform 90
niri msg output DP-3 position 0,0
niri msg output DP-3 on
niri msg output DP-3 off
```

Mudanças via `niri msg output` são **temporárias** e não são gravadas no `config.kdl`. Para persistir, edite o bloco `output` no config do usuário com confirmação e backup, e rode `niri validate`.

## Configuração KDL

- Config do usuário: `~/.config/niri/config.kdl`.
- Fallback do sistema: `/etc/xdg/niri/config.kdl` (não edite; o projeto omyfedora pode sobrescrever).
- Valide sempre: `niri validate`.
- Para aplicar sem reiniciar o compositor, salvar o config normalmente dispara reload; se necessário, use o comando de reload do niri.
- `spawn-at-startup` no config para processos persistentes; `binds` para atalhos.
- O niri não oferece “always on top” para janelas comuns; para overlay, use o painel layer-shell do Noctalia.

## Padrão de plugin Noctalia + niri

```text
service.luau  --(niri msg --json)-->  niri
     |
     +-- noctalia.state.set("niri", snapshot)
                 |
       +---------+---------+
       |                   |
  bar.luau            panel.luau
  (mostra)            (ações via niri msg action)
```

### Serviço de leitura

```lua
--!nonstrict
local interval = (tonumber(noctalia.getConfig("interval")) or 2) * 1000
local snapshot = { output = nil, workspaces = {}, error = nil }

local function publish()
  noctalia.state.set("niri_snapshot", snapshot)
end

local function fetchWorkspaces()
  noctalia.runAsync({ "niri", "msg", "--json", "workspaces" }, function(result)
    if result.exitCode ~= 0 then
      snapshot.error = noctalia.string.trim(result.stderr or "")
      publish()
      return
    end
    local data = noctalia.json.decode(result.stdout or "")
    if type(data) ~= "table" then
      snapshot.error = "JSON inválido"
      publish()
      return
    end
    snapshot.workspaces = data
    snapshot.error = nil
    publish()
  end, 5000)
end

local function fetchOutput()
  noctalia.runAsync({ "niri", "msg", "--json", "focused-output" }, function(result)
    if result.exitCode ~= 0 then
      snapshot.error = noctalia.string.trim(result.stderr or "")
      publish()
      return
    end
    snapshot.output = noctalia.json.decode(result.stdout or "")
    fetchWorkspaces()
  end, 5000)
end

function update()
  fetchOutput()
end

function onIpc(event)
  if event == "refresh" then
    fetchOutput()
  end
end

noctalia.setUpdateInterval(interval)
fetchOutput()
```

### Painel de ações

```lua
local function focusWorkspace(ws)
  noctalia.runAsync(
    { "niri", "msg", "action", "focus-workspace", tostring(ws.idx) },
    function(result)
      if result.exitCode ~= 0 then
        noctalia.notifyError("niri", result.stderr)
      end
    end,
    5000
  )
end
```

Use `ui.row`/`ui.column` clicáveis para cada workspace; recarregue pelo estado do serviço. Não chame `niri msg` a cada frame.

## Eventos em tempo real

```lua
local stream = noctalia.runStream("niri msg --json event-stream", function(line)
  local event = noctalia.json.decode(line)
  if event ~= nil then
    noctalia.state.set("niri_event", event)
  end
end)
```

- `runStream` roda uma string via shell; o comando é fixo, sem interpolação.
- O stream é encerrado no reload/stop do plugin.
- Eventos brutos podem ser frequentes; faça debounce/throttle antes de publicar/renderizar.
- Faça fallback por polling se o stream cair; não dependa de todos os eventos.

## IPC do plugin

```bash
# serviço singleton
noctalia msg plugin me/niri-status:niri all refresh

# widget em um output
noctalia msg plugin me/niri-status:bar focused set "texto"
```

No script, `onIpc(event, payload)` recebe payload string. Para JSON, `noctalia.json.decode(payload)`.

## Erros e armadilhas

| Situação | Tratamento |
|---|---|
| `niri` não encontrado | `dependencies = ["niri"]`; `noctalia.commandExists("niri")`; mostre erro no widget. |
| `NIRI_SOCKET` ausente | O plugin está fora da sessão niri; informe o usuário; não tente “adivinhar” o socket. |
| `focusedOutputName()` retorna `nil` | Acontece no 5.3.0 mesmo com output focado; caia para `noctalia.outputs()` e pegue o item com `focused = true`. |
| `exitCode ~= 0` | Mostre `stderr`; não descarte o último snapshot bom sem indicar erro. |
| JSON inválido | `noctalia.json.decode` pode retornar `nil`; valide antes de indexar. |
| Saída grande | `runAsync` trunca stdout; use `--json` e campos específicos. |
| Ação de output “não colou” | Mudanças IPC são temporárias; persista no config se necessário. |
| `niri validate` falhou | Restaure backup e valide de novo; não reinicie o compositor no escuro. |
| `spawn` com shell | Entrada dinâmica → injeção; use argv ou `spawn-sh` com comando fixo. |

## Plugins de referência

- `raycursive/niri-displays` em `~/.local/share/noctalia/plugins/niri-displays/`: polling + outputs + ações de monitor.
- Exemplo `niri-panel` desta skill: serviço + widget + painel com foco de workspace.

## Links

- niri: <https://github.com/YaLTeR/niri>
- IPC/wiki: <https://github.com/YaLTeR/niri/wiki/IPC>
- Configuração: <https://yalter.github.io/niri/Configuration%3A-Introduction.html>
- `niri msg --help` e `niri msg action --help` locais são a fonte mais confiável para a versão instalada.
