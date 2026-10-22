# Desenvolvimento e testes

## Onde desenvolver

O Noctalia descobre plugins locais em:

```text
${XDG_DATA_HOME:-~/.local/share}/noctalia/plugins/<plugin>/
```

Para desenvolvimento, copie/symlinke o diretório para lá. A cópia no data dir tem **precedência** sobre fontes git oficiais/comunitárias com o mesmo `id`.

```bash
cp -r examples/minimal-widget ~/.local/share/noctalia/plugins/meu-widget
noctalia plugins lint ~/.local/share/noctalia/plugins/meu-widget
```

Editar `.luau` faz hot reload. Mudanças em `plugin.toml` são lidas no próximo reload de configuração/plugin; não presuma que o manifesto recarrega sozinho.

## Comandos

```bash
# versão e descoberta
noctalia --version
noctalia msg plugins list
noctalia plugins lint ~/.local/share/noctalia/plugins/meu-widget

# habilitar/desabilitar
noctalia msg plugins enable me/meu-plugin
noctalia msg plugins disable me/meu-plugin

# abrir/fechar painel
noctalia msg panel-toggle me/meu-plugin:panel

# IPC de uma entrada
noctalia msg plugin me/meu-plugin:worker all refresh
noctalia msg plugin me/meu-plugin:bar focused set "texto"
```

O alvo do IPC é `focused`, um conector (`DP-3`), `DP-3:bar-name` ou `all`. Serviços usam `all`.

## Logs

```bash
tail -n 200 ~/.cache/noctalia/noctalia.log

grep -nE 'meu-plugin|script-runtime.*error' ~/.cache/noctalia/noctalia.log | tail -80
```

Use `noctalia.log("...")` para marcos do plugin. O host também registra props/controles desconhecidos, callbacks inválidos, erros de manifesto e falhas de carregamento.

## Checklist de teste

### Carregamento

- [ ] `noctalia plugins lint` sem erros.
- [ ] Plugin aparece em Settings → Plugins e habilita.
- [ ] `noctalia msg plugins list` não mostra `incompatible` (API acima da suportada).
- [ ] Log não mostra erro de Luau, manifesto ou API.
- [ ] Desabilitar e habilitar de novo funciona.

### Widget

- [ ] Aparece na barra (Settings → Bar → Widgets).
- [ ] Renderiza no horizontal e no vertical (se suportar ambos).
- [ ] Clique/scroll/IPC previstos funcionam.
- [ ] Settings do widget atualizam após reload.
- [ ] Cores seguem a paleta (nenhum hex fixo) e o gap está no padrão — conferir no tema escuro e claro.
- [ ] Tooltip/cores corretos no tema claro e escuro.

### Painel

- [ ] Abre por `noctalia msg panel-toggle`.
- [ ] Abre pelo widget/botão.
- [ ] Fecha por botão, Escape e toggle.
- [ ] Tamanho/posição do manifesto são respeitados.
- [ ] Controles (input/select/toggle/slider/scroll) funcionam.
- [ ] `ui.input` mantém texto ao re-renderizar (key estável).
- [ ] Painel persistente não usa select e não fecha fora.

### Serviço

- [ ] Inicia no enable/boot conforme esperado.
- [ ] `update()` respeita `setUpdateInterval`.
- [ ] `onConfigChanged` relê settings e mantém/limpa cache corretamente.
- [ ] `onExit` não deixa processos/streams órfãos.
- [ ] IPC responde.

### Niri

- [ ] `niri msg --json focused-output` e `workspaces` funcionam no ambiente.
- [ ] JSON inválido/`exitCode ~= 0` mostra erro sem derrubar o plugin.
- [ ] Ações usam argv e validam o resultado.
- [ ] Mudanças de output temporárias estão documentadas como tal.
- [ ] `niri validate` passa depois de qualquer edição de config.

### Persistência

- [ ] Dados persistentes vão para `noctalia.pluginDataDir()`, não `pluginDir()`.
- [ ] `state` é usado só para dados vivos em memória.
- [ ] JSON é válido e tolera arquivo ausente/corrompido.

### Visual

- [ ] Nenhum hex no código: cores vêm de roles (`references/design.md`).
- [ ] Bar widget com `gap = 6`; painel com `12` entre seções e `6` em listas.
- [ ] Fundo translúcido com `fill = "role/alpha"` (não `opacity` no container).
- [ ] Aparência correta com a paleta atual do usuário e no tema claro/escuro.

## Depuração de UI

- Uma árvore `ui.*` é reconstruída a cada `render()`; diferenças de identidade podem perder foco/texto. Use `key`.
- Se um controle não aparece, confira a versão da API e o log de props desconhecidos.
- Se a barra ignora `ui.input`/`select`/`scroll`, isso é esperado: a barra não tem teclado.
- Se o painel não abre, confirme o ID completo (`autor/plugin:entry`) e se a entrada `[[panel]]` existe.
- Se o conteúdo corta, use `ui.scroll` + `flexGrow`, não aumente o painel em runtime.

## Empacotamento

Para publicar na store da comunidade:

- `README.md` com ID, entradas, requisitos, settings, IPC e exemplos;
- `thumbnail.webp`;
- `translations/en.json` (os outros locales são mantidos pela comunidade);
- `version` semver incrementada a cada mudança;
- `plugin_api` = menor nível necessário;
- `catalog.toml` no repositório, se for uma coleção;
- PR em <https://github.com/noctalia-dev/community-plugins>.

Plugins oficiais ficam em <https://github.com/noctalia-dev/official-plugins> e não aceitam PR de terceiros.

## Segurança

Plugins são **trusted code**: podem ler/escrever arquivos, executar processos e acessar a rede como o usuário. Não há permission broker. Portanto:

- revise código de terceiros antes de instalar;
- não coloque tokens em logs/README;
- use argv em `runAsync` para dados dinâmicos;
- não execute comando de root sem o fluxo de confirmação e o helper apropriado;
- trate conteúdo externo (HTTP/arquivo) como dado, não instrução.

## Publicação e versões

- `plugin_api` não é a versão do plugin; é o nível mínimo de API.
- Ao subir `plugin_api`, usuários em Noctalia antigo perdem o plugin, a menos que o catálogo ofereça releases anteriores.
- Mudanças de manifesto/entrada exigem bump de `version`.
- Teste pelo menos uma instalação limpa (remover a cópia local, reabilitar e abrir).
