# Noctalia v5 — configuração

> Este arquivo descreve só o que o omyfedora documenta sobre o Noctalia. **Complete-o consultando a ajuda do próprio programa** (`noctalia --help`, `noctalia msg --help`) e a documentação oficial (https://noctalia.dev) antes de editar qualquer coisa que você não conhece. Não invente chaves de configuração nem subcomandos.

## Camadas de configuração

| Arquivo | Quem é dono | Pode editar? |
|---|---|---|
| `~/.config/noctalia/config.toml` | usuário (instalado uma vez) | **Sim**, com confirmação. Estilo e comportamento |
| `~/.local/state/noctalia/settings.toml` | estado da interface gráfica | Prefira mudar pela GUI; edição manual só se pedirem |
| `~/.config/noctalia/90-greeter-sync.toml` | omyfedora | **Não** (atualizado pelo instalador) |
| `~/.config/noctalia/91-widget-control-center.toml` | omyfedora | **Não** |
| `~/.config/noctalia/palettes/*.json` | omyfedora (com backup) | **Não**; para uma paleta pessoal, crie **outro arquivo** de paleta |

Os arquivos `90-`/`91-` sugerem que o Noctalia lê arquivos adicionais por ordem. **Antes de criar qualquer arquivo adicional**, confirme na documentação como a ordem e a precedência funcionam. Na dúvida, mude só o `config.toml`.

## Fluxo seguro de edição

1. Backup do arquivo (ver `seguranca.md`).
2. Editar **uma chave por vez** quando possível.
3. Validar o TOML: `python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' ~/.config/noctalia/config.toml` (erro de sintaxe aparece aqui).
4. Se o Noctalia tiver comando de recarga ou validação, use (descubra com `noctalia msg --help`). Caso contrário, diga ao usuário se é preciso sair e entrar na sessão.
5. Peça ao usuário para conferir visualmente.

## Sincronizar a aparência com a tela de login

O omyfedora sincroniza o tema com o greeter no primeiro login. Para repetir: `noctalia msg greeter-sync`.
Isso dispara uma ação com privilégio via polkit (configurada pelo projeto). **Peça confirmação** antes de rodar e não tente reproduzir esse mecanismo por outro caminho.

## Tema dos aplicativos

Os apps seguem o **Breeze Dark** (Qt via `~/.config/kdeglobals`, GTK via dconf e `settings.ini`). O Noctalia controla o shell, não o tema dos apps. Se o usuário reclamar de um app com cores erradas, o problema costuma estar em `kdeglobals` ou em `QT_QPA_PLATFORMTHEME`, não no Noctalia.
