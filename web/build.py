#!/usr/bin/env python3
# build.py — gera o site de apresentação e documentação do msbos em web/.
#
# Lê os Markdown de docs/ (PT e EN), converte para HTML com um subconjunto de
# Markdown (títulos, listas, tabelas, código, citações, links) e monta as
# páginas com o design system de web/assets/css/site.css.
#
# Uso:
#   python3 web/build.py          # regenera todas as páginas
#   python3 web/build.py --check  # só relata links quebrados, sem escrever
#
# O site não depende de CDN: nenhuma fonte, CSS ou JS externo.

from __future__ import annotations

import html
import itertools
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "web"
REPO = "https://github.com/marcos2872/msbos"

# ─── documentos ──────────────────────────────────────────────────────────────
# (chave, arquivo pt, arquivo en, título no menu, descrição curta)
DOCS = [
    ("index", "docs/index.md", "docs/index.en.md",
     "Índice", "Index",
     "Ponto de entrada de toda a documentação.",
     "Entry point for all documentation."),
    ("instalacao", "docs/instalacao.md", "docs/instalacao.en.md",
     "Instalação", "Installation",
     "Base, ISOs, VM com 3D, bootstrap, opções e kickstart.",
     "Base, ISOs, VM with 3D, bootstrap, options and kickstart."),
    ("uso", "docs/uso.md", "docs/uso.en.md",
     "Uso diário", "Daily use",
     "Atalhos do niri, Noctalia, tema, wallpapers e greeter.",
     "niri shortcuts, Noctalia, theme, wallpapers and greeter."),
    ("arquitetura", "docs/arquitetura.md", "docs/arquitetura.en.md",
     "Arquitetura", "Architecture",
     "Fluxo dos scripts, as etapas, lib/common.sh e assets.",
     "Script flow, the steps, lib/common.sh and assets."),
    ("solucao-de-problemas", "docs/solucao-de-problemas.md", "docs/solucao-de-problemas.en.md",
     "Solução de problemas", "Troubleshooting",
     "dnf, VM/GPU, flatpak, Noctalia, greeter e recuperação.",
     "dnf, VM/GPU, flatpak, Noctalia, greeter and recovery."),
    ("migracao-msbos", "docs/migracao-msbos.md", "docs/migracao-msbos.en.md",
     "Migração", "Migration",
     "Sair de uma instalação anterior sem reinstalar o Fedora.",
     "Move from an earlier install without reinstalling Fedora."),
    ("historico", "docs/historico.md", "docs/historico.en.md",
     "Histórico de nomes", "Name history",
     "As gerações anteriores do nome do projeto.",
     "The earlier generations of the project name."),
    ("creditos", "docs/creditos.md", "docs/creditos.en.md",
     "Créditos", "Credits",
     "Fedora, KDE, niri, Noctalia, greetd e demais upstream.",
     "Fedora, KDE, niri, Noctalia, greetd and other upstreams."),
    ("tecnico", "docs/msbos/README.md", None,
     "Técnico", "Technical",
     "Documento de implementação: orquestrador, etapas, contratos e garantias.",
     "Implementation document: orchestrator, steps, contracts and guarantees."),
    ("tecnico-configuracoes", "docs/msbos/configuracoes.md", None,
     "Técnico · assets", "Technical · assets",
     "Inventário do que é instalado, onde e por qual etapa.",
     "Inventory of what is installed, where and by which step."),
]

BY_KEY = {d[0]: d for d in DOCS}
BY_SRC = {}
for _d in DOCS:
    if _d[1]:
        BY_SRC[_d[1]] = _d[0]
    if _d[2]:
        BY_SRC[_d[2]] = _d[0]

NAV = [
    ("index-page", "Início", "Home", "index.html", "en/index.html"),
    ("instalacao", "Instalação", "Install", "docs/instalacao.html", "en/docs/instalacao.html"),
    ("uso", "Uso", "Usage", "docs/uso.html", "en/docs/uso.html"),
    ("arquitetura", "Arquitetura", "Architecture", "docs/arquitetura.html", "en/docs/arquitetura.html"),
    ("solucao-de-problemas", "Problemas", "Troubleshoot", "docs/solucao-de-problemas.html", "en/docs/solucao-de-problemas.html"),
    ("tecnico", "Técnico", "Technical", "docs/tecnico.html", "docs/tecnico.html"),
]


# ─── utilidades ──────────────────────────────────────────────────────────────

def esc(text: str) -> str:
    return html.escape(text, quote=False)


def strip_tags(text: str) -> str:
    return re.sub(r"<[^>]+>", "", text)


def slugify(text: str) -> str:
    """Mesmo esquema de âncoras do GitHub: minúsculas, sem pontuação, espaços → hífen."""
    text = strip_tags(text)
    text = text.replace("`", "")
    text = text.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE)
    return re.sub(r"\s", "-", text)


def rel(from_page: str, target: str) -> str:
    """Caminho relativo entre duas páginas do site (ambas relativas a web/)."""
    base = os.path.dirname(from_page) or "."
    return os.path.relpath(target, base).replace(os.sep, "/")


# ─── Markdown → HTML ────────────────────────────────────────────────────────

FENCE_RE = re.compile(r"^(\s*)(```+|~~~+)\s*([\w+-]*)\s*$")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
LIST_RE = re.compile(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$")
TABLE_SEP_RE = re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$")
HTML_BLOCK_RE = re.compile(r"^\s*<a\s+id=")
CODE_LANG_LABEL = {"": "texto", "text": "texto", "bash": "bash", "sh": "sh",
                   "console": "console", "kdl": "kdl", "toml": "toml",
                   "json": "json", "python": "python", "ini": "ini", "yaml": "yaml"}


class Markdown:
    def __init__(self, src_path: str, page_path: str, lang: str, linkmap):
        self.src = src_path
        self.page = page_path
        self.lang = lang
        self.linkmap = linkmap  # callable(href) -> href
        self.toc: list[tuple[int, str, str]] = []
        self._inline_seq = itertools.count()

    # ── inline ────────────────────────────────────────────────────────────
    def inline(self, text: str) -> str:
        # Cada chamada (inclusive a recursiva do rótulo de link) usa um prefixo
        # de placeholder próprio: assim o texto aninhado não colide com o
        # índice dos fragmentos da chamada externa.
        prefix = f"\x00{next(self._inline_seq)}\x01"
        slots: list[str] = []

        def keep(fragment: str) -> str:
            slots.append(fragment)
            return f"{prefix}{len(slots) - 1}{prefix}"

        # 1. spans de código
        def code_span(m: re.Match) -> str:
            body = m.group(2).strip() if m.group(2).strip() else m.group(2)
            return keep(f"<code>{esc(body)}</code>")

        text = re.sub(r"(`+)(.+?)\1", code_span, text, flags=re.S)

        # 2. autolinks <https://...>
        text = re.sub(
            r"<(https?://[^>\s]+)>",
            lambda m: keep(f'<a href="{esc(m.group(1))}" rel="noopener">{esc(m.group(1))}</a>'),
            text,
        )

        # 3. imagens e links (o rótulo do link recebe a mesma formatação inline)
        def image(m: re.Match) -> str:
            alt, url = m.group(1), m.group(2)
            return keep(f'<img src="{esc(url)}" alt="{esc(alt)}" loading="lazy">')

        def link(m: re.Match) -> str:
            label, url = m.group(1), m.group(2).strip()
            href = self.linkmap(url)
            return keep(f'<a href="{esc(href)}">{self.inline(label)}</a>')

        text = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)", image, text)
        text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)

        # 4. escapa o resto
        text = esc(text)

        # 5. ênfase
        text = re.sub(r"\*\*(?=\S)(.+?)(?<=\S)\*\*", r"<strong>\1</strong>", text, flags=re.S)
        text = re.sub(r"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])", r"<em>\1</em>", text, flags=re.S)
        text = re.sub(r"~~(?=\S)(.+?)(?<=\S)~~", r"<del>\1</del>", text, flags=re.S)

        # 6. restaura os fragmentos desta chamada
        pattern = re.compile(re.escape(prefix) + r"(\d+)" + re.escape(prefix))
        while prefix in text:
            text = pattern.sub(lambda m: slots[int(m.group(1))], text)
        return text

    # ── blocos ────────────────────────────────────────────────────────────
    def render(self, lines: list[str]) -> str:
        out: list[str] = []
        i = 0
        n = len(lines)
        while i < n:
            line = lines[i]
            if not line.strip():
                i += 1
                continue

            m = FENCE_RE.match(line)
            if m:
                indent, marker, lang = len(m.group(1)), m.group(2), m.group(3)
                i += 1
                code: list[str] = []
                while i < n:
                    fm = FENCE_RE.match(lines[i])
                    if fm and fm.group(2)[0] == marker[0] and len(fm.group(1)) <= indent:
                        i += 1
                        break
                    raw = lines[i]
                    cut = min(indent, len(raw) - len(raw.lstrip())) if raw.strip() else 0
                    code.append(raw[cut:] if cut else raw)
                    i += 1
                out.append(self.codeblock("\n".join(code), lang))
                continue

            m = HEADING_RE.match(line)
            if m:
                level = len(m.group(1))
                body = self.inline(m.group(2))
                anchor = slugify(m.group(2))
                if level > 1:
                    self.toc.append((level, anchor, strip_tags(body)))
                out.append(f'<h{level} id="{esc(anchor)}">{body}</h{level}>')
                i += 1
                continue

            if HTML_BLOCK_RE.match(line):
                out.append(line.strip())
                i += 1
                continue

            if line.lstrip().startswith(">"):
                quote: list[str] = []
                while i < n and lines[i].lstrip().startswith(">"):
                    quote.append(re.sub(r"^\s*>\s?", "", lines[i]))
                    i += 1
                inner = self.render(quote)
                out.append(f"<blockquote>{inner}</blockquote>")
                continue

            if line.lstrip().startswith("|") and i + 1 < n and TABLE_SEP_RE.match(lines[i + 1]):
                table, i = self.table(lines, i)
                out.append(table)
                continue

            if LIST_RE.match(line):
                block, i = self.list_block(lines, i)
                out.append(block)
                continue

            # parágrafo
            para: list[str] = []
            while i < n and lines[i].strip():
                nxt = lines[i]
                if FENCE_RE.match(nxt) or HEADING_RE.match(nxt) or HTML_BLOCK_RE.match(nxt):
                    break
                if nxt.lstrip().startswith("|") and i + 1 < n and TABLE_SEP_RE.match(lines[i + 1]):
                    break
                if LIST_RE.match(nxt) and not para:
                    break
                para.append(nxt.strip())
                i += 1
            text = " ".join(para)
            if re.fullmatch(r"\[(Português|English)\]\([^)]+\)\s*·\s*\[(Português|English)\]\([^)]+\)", text):
                continue  # o seletor de idioma do .md vira o toggle do cabeçalho
            out.append(f"<p>{self.inline(text)}</p>")
        return "\n".join(out)

    def codeblock(self, code: str, lang: str) -> str:
        if lang == "mermaid":
            svg = mermaid_svg(code, self.lang)
            if svg:
                return svg
        label = CODE_LANG_LABEL.get(lang, lang or "texto")
        copy_label = "copiar" if (self.lang or "pt") == "pt" else "copy"
        return (
            '<div class="codeblock">'
            '<div class="codeblock__head">'
            f'<span class="codeblock__lang">{esc(label)}</span>'
            f'<button type="button" class="codeblock__copy" data-copy>{copy_label}</button>'
            "</div>"
            f"<pre><code>{esc(code)}</code></pre>"
            "</div>"
        )

    def table(self, lines: list[str], i: int) -> tuple[str, int]:
        def cells(row: str) -> list[str]:
            row = row.strip()
            if row.startswith("|"):
                row = row[1:]
            if row.endswith("|"):
                row = row[:-1]
            return [c.replace("\\|", "|").strip() for c in re.split(r"(?<!\\)\|", row)]

        header = cells(lines[i])
        aligns = []
        for spec in cells(lines[i + 1]):
            if spec.startswith(":") and spec.endswith(":"):
                aligns.append("center")
            elif spec.endswith(":"):
                aligns.append("right")
            else:
                aligns.append(None)
        i += 2
        rows: list[list[str]] = []
        while i < len(lines) and lines[i].strip().startswith("|"):
            rows.append(cells(lines[i]))
            i += 1

        def style(idx: int) -> str:
            a = aligns[idx] if idx < len(aligns) else None
            return f' style="text-align:{a}"' if a else ""

        thead = "".join(f"<th{style(c)}>{self.inline(h)}</th>" for c, h in enumerate(header))
        body = []
        for row in rows:
            tds = []
            for c in range(len(header)):
                val = row[c] if c < len(row) else ""
                tds.append(f"<td{style(c)}>{self.inline(val)}</td>")
            body.append("<tr>" + "".join(tds) + "</tr>")
        return (
            '<div class="table-wrap"><table><thead><tr>'
            + thead
            + "</tr></thead><tbody>"
            + "".join(body)
            + "</tbody></table></div>"
        ), i

    def list_block(self, lines: list[str], i: int) -> tuple[str, int]:
        n = len(lines)
        first = LIST_RE.match(lines[i])
        base_indent = len(first.group(1))
        ordered = first.group(2)[0].isdigit()
        items: list[list[str]] = []

        while i < n:
            line = lines[i]
            m = LIST_RE.match(line)
            if m and len(m.group(1)) == base_indent and m.group(2)[0].isdigit() == ordered:
                items.append([m.group(3)])
                i += 1
                continue
            if not line.strip():
                # linha em branco só continua a lista se o próximo item/indentação pertencer a ela
                j = i + 1
                while j < n and not lines[j].strip():
                    j += 1
                if j < n:
                    nm = LIST_RE.match(lines[j])
                    ind = len(lines[j]) - len(lines[j].lstrip())
                    if (nm and len(nm.group(1)) == base_indent and nm.group(2)[0].isdigit() == ordered) or ind > base_indent:
                        if items:
                            items[-1].append("")
                        i += 1
                        continue
                break
            ind = len(line) - len(line.lstrip())
            if ind > base_indent and items:
                items[-1].append(line[min(ind, base_indent + 2):])
                i += 1
                continue
            break

        rendered = []
        for body in items:
            inner = self.render(body)
            if inner.startswith("<p>") and inner.count("<p>") == 1 and "<div" not in inner:
                inner = inner[3:].split("</p>", 1)[0]
            rendered.append(f"<li>{inner}</li>")

        tag = "ol" if ordered else "ul"
        start = first.group(2).rstrip(".)")
        attr = f' start="{start}"' if ordered and start.isdigit() and start != "1" else ""
        return f"<{tag}{attr}>" + "".join(rendered) + f"</{tag}>", i


class _Proxy:
    """Reservado para uso futuro; mantido para compatibilidade do módulo."""


# ─── Mermaid (subconjunto estático) ─────────────────────────────────────────
#
# Os diagramas do projeto usam só `flowchart TD|LR` com nós de rótulo simples e
# arestas opcionalmente rotuladas. Renderizamos isso como SVG inline — nada de
# carregar mermaid.js de CDN (o site não tem dependências externas).

MERMAID_NODE_RE = re.compile(r'^\s*([A-Za-z_][\w]*)\s*(\[|\(|\{)?\s*(?:"([^"]*)"|([^\[\](){}<>]*))?\s*(\]|\)|\})?\s*$')


def _mermaid_parse(code: str):
    """Extrai direção, nós e arestas de um flowchart simples."""
    direction = "TD"
    nodes: dict[str, str] = {}
    edges: list[tuple[str, str, str]] = []

    def node(token: str) -> str:
        token = token.strip()
        m = MERMAID_NODE_RE.match(token)
        if not m:
            ident = re.sub(r"[^\w]", "_", token) or "n"
            nodes.setdefault(ident, token)
            return ident
        ident, label = m.group(1), (m.group(3) if m.group(3) is not None else m.group(4))
        label = (label or ident).strip()
        # remove a formatação inline que o Mermaid aceitaria
        label = re.sub(r"<br\s*/?>", " ", label)
        label = label.replace('"', "").strip()
        if ident not in nodes:
            nodes[ident] = label
        return ident

    for raw in code.splitlines():
        line = raw.strip()
        if not line or line.startswith(("%%", "subgraph", "end", "classDef", "class ", "style ", "linkStyle")):
            continue
        m = re.match(r"^(flowchart|graph)\s+(TD|TB|BT|LR|RL)\s*$", line)
        if m:
            direction = "TD" if m.group(2) in ("TD", "TB", "BT") else "LR"
            continue

        # separa a linha em nós e arestas: A[..] -->|rot| B[..] --> C[..]
        parts = re.split(r"\s*-{2,}>\s*(?:\|([^|]*)\|\s*)?", line)
        chain: list[str] = []
        labels: list[str] = []
        for idx, chunk in enumerate(parts):
            if idx % 2 == 0:
                if chunk.strip():
                    chain.append(node(chunk))
            else:
                labels.append((chunk or "").strip())
        for idx in range(len(chain) - 1):
            edges.append((chain[idx], chain[idx + 1], labels[idx] if idx < len(labels) else ""))

    return direction, nodes, edges


def mermaid_svg(code: str, lang: str = "pt") -> str:
    """SVG estático para o subconjunto de flowchart usado na documentação."""
    direction, nodes, edges = _mermaid_parse(code)
    if not nodes:
        return ""

    if direction == "TD":
        # grades simples: um nível por ordem de aparição das arestas
        level: dict[str, int] = {}
        for src, dst, _ in edges:
            level.setdefault(src, 0)
            level[dst] = max(level.get(dst, 0), level[src] + 1)
        for n in nodes:
            level.setdefault(n, 0)
        rows: dict[int, list[str]] = {}
        for n in nodes:
            rows.setdefault(level[n], []).append(n)
        order = sorted(rows)
        cols = max(len(v) for v in rows.values())
        cell_w, cell_h = 230, 88
        gap_x, gap_y = 26, 60
        pad = 18
        width = pad * 2 + cols * cell_w + (cols - 1) * gap_x
        height = pad * 2 + len(order) * cell_h + (len(order) - 1) * gap_y
        pos: dict[str, tuple[float, float]] = {}
        for r_i, lvl in enumerate(order):
            row = rows[lvl]
            total = len(row) * cell_w + (len(row) - 1) * gap_x
            start = (width - total) / 2
            for c_i, ident in enumerate(row):
                pos[ident] = (start + c_i * (cell_w + gap_x), pad + r_i * (cell_h + gap_y))
    else:
        # LR: quebra em linhas (snake) para não esmagar os nós num SVG largo.
        cell_w, cell_h = 165, 70
        gap_x, gap_y = 30, 40
        pad = 18
        ident_list = list(nodes)
        per_row = min(len(ident_list), 4)
        rows_n = (len(ident_list) + per_row - 1) // per_row
        cols = min(per_row, len(ident_list))
        width = pad * 2 + cols * cell_w + (cols - 1) * gap_x
        height = pad * 2 + rows_n * cell_h + (rows_n - 1) * gap_y
        # todas as linhas fluem da esquerda para a direita; a virada de linha é
        # desenhada como uma seta de "quebra" (desce, volta à esquerda, entra).
        pos = {}
        for i, ident in enumerate(ident_list):
            row_i, col_i = divmod(i, per_row)
            pos[ident] = (pad + col_i * (cell_w + gap_x), pad + row_i * (cell_h + gap_y))

    def wrap(label: str, limit: int) -> list[str]:
        words = label.split()
        lines: list[str] = []
        cur = ""
        for w in words:
            if cur and len(cur) + 1 + len(w) > limit:
                lines.append(cur)
                cur = w
            else:
                cur = f"{cur} {w}".strip()
        if cur:
            lines.append(cur)
        return lines or [""]

    edge_svg = []
    for src, dst, label in edges:
        x1, y1 = pos[src]
        x2, y2 = pos[dst]
        label_anchor = "middle"
        if direction == "TD":
            ax, ay = x1 + cell_w / 2, y1 + cell_h
            bx, by = x2 + cell_w / 2, y2
            mid_y = (ay + by) / 2
            d = f"M {ax:.1f} {ay:.1f} L {ax:.1f} {mid_y:.1f} L {bx:.1f} {mid_y:.1f} L {bx:.1f} {by - 8:.1f}"
            lx, ly = ax + 12, mid_y + 5
            label_anchor = "start"
            head = f"M {bx - 4.5:.1f} {by - 8:.1f} L {bx + 4.5:.1f} {by - 8:.1f} L {bx:.1f} {by:.1f} Z"
        else:
            same_row = abs(y1 - y2) < 1
            if same_row:  # sai à direita, entra à esquerda
                ax, ay = x1 + cell_w, y1 + cell_h / 2
                bx, by = x2, y2 + cell_h / 2
                mid_x = (ax + bx) / 2
                d = f"M {ax:.1f} {ay:.1f} L {mid_x:.1f} {ay:.1f} L {mid_x:.1f} {by:.1f} L {bx - 8:.1f} {by:.1f}"
                lx, ly = mid_x, by - 9
                label_anchor = "middle"
                head = f"M {bx - 8:.1f} {by - 4.5:.1f} L {bx - 8:.1f} {by + 4.5:.1f} L {bx:.1f} {by:.1f} Z"
            else:  # quebra de linha: desce, corre na horizontal e entra pelo topo
                ax, ay = x1 + cell_w / 2, y1 + cell_h
                bx, by = x2 + cell_w / 2, y2
                mid_y = (ay + by) / 2
                d = f"M {ax:.1f} {ay:.1f} L {ax:.1f} {mid_y:.1f} L {bx:.1f} {mid_y:.1f} L {bx:.1f} {by - 8:.1f}"
                lx, ly = (ax + bx) / 2, mid_y - 7
                head = f"M {bx - 4.5:.1f} {by - 8:.1f} L {bx + 4.5:.1f} {by - 8:.1f} L {bx:.1f} {by:.1f} Z"
        edge_svg.append(
            f'<path d="{d}" fill="none" stroke="rgba(163,161,248,.55)" stroke-width="1.4"/>'
            f'<path d="{head}" fill="rgba(163,161,248,.85)"/>'
        )
        if label:
            lines = wrap(label, 20)
            box_w = max(len(t) for t in lines) * 6.3 + 14
            box_h = len(lines) * 13 + 6
            box_x = lx if label_anchor == "start" else lx - box_w / 2
            edge_svg.append(
                f'<rect x="{box_x:.1f}" y="{ly - 11:.1f}" width="{box_w:.1f}" '
                f'height="{box_h:.1f}" rx="4" fill="#111116" stroke="rgba(255,255,255,.09)" '
                f'stroke-width="1"/>'
            )
            for k, text in enumerate(lines):
                edge_svg.append(
                    f'<text x="{box_x + 7:.1f}" y="{ly + k * 13:.1f}" text-anchor="start" '
                    f'class="mm-edge-label">{esc(text)}</text>'
                )

    node_svg = []
    for ident, label in nodes.items():
        x, y = pos[ident]
        is_endpoint = all(ident not in (s, d) for s, d, _ in edges) or ident in ("E",)
        stroke = "rgba(124,122,242,.55)" if not is_endpoint else "rgba(124,122,242,.9)"
        fill = "rgba(124,122,242,.13)" if not is_endpoint else "rgba(124,122,242,.2)"
        lines = wrap(label, 22 if direction == "TD" else 15)
        node_svg.append(
            f'<rect x="{x:.1f}" y="{y:.1f}" width="{cell_w}" height="{cell_h}" rx="10" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="1.2"/>'
        )
        start_y = y + cell_h / 2 - (len(lines) - 1) * 8 + 1
        for k, text in enumerate(lines):
            node_svg.append(
                f'<text x="{x + cell_w / 2:.1f}" y="{start_y + k * 16:.1f}" text-anchor="middle" '
                f'class="mm-node-label">{esc(text)}</text>'
            )

    return (
        f'<figure class="mermaid"><svg viewBox="0 0 {width:.0f} {height:.0f}" '
        f'role="img" aria-label="Diagrama de fluxo" preserveAspectRatio="xMidYMid meet">'
        + "".join(edge_svg) + "".join(node_svg) + "</svg></figure>"
    )


# ─── mapa de links entre documentos ─────────────────────────────────────────

def make_linkmap(src_path: str, current_page: str, current_lang: str):
    src_dir = os.path.dirname(src_path)

    def resolve(url: str) -> str:
        if re.match(r"^(https?:|mailto:|#|/)", url):
            return url
        path, _, frag = url.partition("#")
        if not path:
            return url
        target = os.path.normpath(os.path.join(src_dir, path)).replace(os.sep, "/")

        if target in ("LICENSE",):
            return f"{REPO}/blob/main/LICENSE"
        if target == "README.md":
            page = "index.html" if current_lang == "pt" else "en/index.html"
            href = rel(current_page, page)
        elif target == "README.en.md":
            href = rel(current_page, "en/index.html")
        else:
            key = BY_SRC.get(target)
            if not key:
                return url  # link externo ao site: deixa como está
            data = BY_KEY[key]
            if current_lang == "pt" and data[2]:
                page = f"docs/{key}.html"
            elif current_lang == "pt":
                page = f"docs/{key}.html"
            elif data[2]:
                page = f"en/docs/{key}.html"
            else:
                page = f"en/docs/{key}.html" if data[2] else f"docs/{key}.html"
            href = rel(current_page, page)
        return f"{href}#{frag}" if frag else href

    return resolve


# ─── template ───────────────────────────────────────────────────────────────

ICON = {
    "github": '<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8a8 8 0 0 0 5.47 7.59c.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.4 7.4 0 0 1 2-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>',
    "menu": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
    "arrow": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 8h10M9 4l4 4-4 4"/></svg>',
    "external": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6.5 3.5H13v6.5M13 3.5 7 9.5M11 10.5v2.5h-8v-8h2.5"/></svg>',
    "doc": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 1.5h5l3 3V14a.5.5 0 0 1-.5.5h-7A.5.5 0 0 1 4 14V2a.5.5 0 0 1 .5-.5ZM9 1.5V5h3"/></svg>',
    "check": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m3 8.5 3 3 7-7"/></svg>',
    "cross": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8"/></svg>',
    "chip": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" aria-hidden="true"><rect x="4.5" y="4.5" width="7" height="7" rx="1.5"/><path d="M6.5 1.5v3M9.5 1.5v3M6.5 11.5v3M9.5 11.5v3M1.5 6.5h3M1.5 9.5h3M11.5 6.5h3M11.5 9.5h3"/></svg>',
    "layers": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 1.8 14 5 8 8.2 2 5l6-3.2ZM2 8l6 3.2L14 8M2 11l6 3.2L14 11"/></svg>',
    "shield": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 1.5 13.5 3.5v4.2c0 3-2.2 5.5-5.5 6.8-3.3-1.3-5.5-3.8-5.5-6.8V3.5L8 1.5Z"/><path d="m5.6 7.8 1.8 1.8 3.2-3.2"/></svg>',
    "terminal": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="2"/><path d="m4.5 6.5 2 1.5-2 1.5M8.5 10h3"/></svg>',
    "keyboard": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="1.5" y="4" width="13" height="8" rx="1.6"/><path d="M4 6.5h.01M6.5 6.5h.01M9 6.5h.01M11.5 6.5h.01M4 9.5h8"/></svg>',
    "gauge": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2.5 11.5a6 6 0 1 1 11 0"/><path d="m8 8 2.6-2.6"/><circle cx="8" cy="8" r="1.1"/></svg>',
    "palette": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 1.8a6.2 6.2 0 1 0 0 12.4c1 0 1.4-.6 1.4-1.3 0-.9-.8-1-.8-1.9 0-.7.6-1.3 1.5-1.3h1.3c1.6 0 2.4-1 2.4-2.6C13.8 4.2 11.2 1.8 8 1.8Z"/><circle cx="5.2" cy="6" r=".8" fill="currentColor"/><circle cx="8" cy="4.6" r=".8" fill="currentColor"/></svg>',
    "lock": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3.5" y="7" width="9" height="7" rx="1.6"/><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2"/></svg>',
}

TEXT = {
    "pt": {
        "html_lang": "pt-BR",
        "skip": "Pular para o conteúdo",
        "nav_label": "Navegação principal",
        "menu": "Menu",
        "github": "Repositório no GitHub",
        "docs": "Documentação",
        "docs_short": "Docs",
        "on_this_page": "Nesta página",
        "doc_index": "Todos os documentos",
        "prev": "Anterior",
        "next": "Próximo",
        "source": "Fonte",
        "edit": "Ver no GitHub",
        "read": "min de leitura",
        "language_missing": "Somente em português",
        "index_title": "Índice",
        "footer_note": "Projeto pessoal e não oficial. Fedora, KDE, niri, Noctalia e greetd pertencem aos seus respectivos projetos; o msbos não é afiliado, endossado ou mantido por eles.",
        "footer_docs": "Documentação",
        "footer_project": "Projeto",
        "footer_upstream": "Upstream",
        "copy": "copiar",
        "copied": "copiado",
        "toc_empty": "",
    },
    "en": {
        "html_lang": "en",
        "skip": "Skip to content",
        "nav_label": "Main navigation",
        "menu": "Menu",
        "github": "GitHub repository",
        "docs": "Documentation",
        "docs_short": "Docs",
        "on_this_page": "On this page",
        "doc_index": "All documents",
        "prev": "Previous",
        "next": "Next",
        "source": "Source",
        "edit": "View on GitHub",
        "read": "min read",
        "language_missing": "Portuguese only",
        "index_title": "Index",
        "footer_note": "Personal, unofficial project. Fedora, KDE, niri, Noctalia and greetd belong to their respective projects; msbos is not affiliated with, endorsed by or maintained by them.",
        "footer_docs": "Documentation",
        "footer_project": "Project",
        "footer_upstream": "Upstream",
        "copy": "copy",
        "copied": "copied",
        "toc_empty": "",
    },
}


def header(page: str, lang: str, active: str, has_en: bool) -> str:
    t = TEXT[lang]
    root = rel(page, ".")
    nav_items = []
    for key, pt, en, pt_href, en_href in NAV:
        href = pt_href if lang == "pt" else en_href
        label = pt if lang == "pt" else en
        cur = ' aria-current="page"' if key == active else ""
        nav_items.append(f'<a href="{rel(page, href)}"{cur}>{label}</a>')

    if lang == "pt":
        other_href = rel(page, "en/" + page)
        if not has_en:
            lang_switch = (
                '<span class="lang-switch" role="group" aria-label="Idioma">'
                '<span aria-current="true">PT</span>'
                f'<span title="{t["language_missing"]}" style="opacity:.45">EN</span></span>'
            )
        else:
            lang_switch = (
                '<span class="lang-switch" role="group" aria-label="Idioma">'
                '<span aria-current="true">PT</span>'
                f'<a href="{other_href}" hreflang="en" lang="en">EN</a></span>'
            )
    else:
        other = page[len("en/"):]
        lang_switch = (
            '<span class="lang-switch" role="group" aria-label="Language">'
            f'<a href="{rel(page, other)}" hreflang="pt-BR" lang="pt-BR">PT</a>'
            '<span aria-current="true">EN</span></span>'
        )

    return f"""<a class="skip-link" href="#conteudo">{t['skip']}</a>
<header class="site-header" data-header>
  <div class="container container--wide">
    <div class="header-inner">
      <a class="brand" href="{rel(page, 'index.html')}">
        <img src="{root}/assets/img/msbos-logo.png" alt="" width="30" height="30">
        <span class="brand-word">msbos<small>niri + Noctalia</small></span>
      </a>
      <nav class="nav" id="menu" aria-label="{t['nav_label']}">
        {''.join(nav_items)}
      </nav>
      <div class="header-tools">
        {lang_switch}
        <a class="icon-link" href="{REPO}" rel="noopener" aria-label="{t['github']}" title="{t['github']}">{ICON['github']}</a>
        <button class="menu-btn" type="button" data-menu aria-expanded="false" aria-controls="menu" aria-label="{t['menu']}">{ICON['menu']}</button>
      </div>
    </div>
  </div>
</header>"""


def footer(page: str, lang: str) -> str:
    t = TEXT[lang]
    root = rel(page, ".")
    if lang == "pt":
        col_docs = [
            ("docs/index.html", "Índice da documentação"),
            ("docs/instalacao.html", "Instalação"),
            ("docs/uso.html", "Uso diário"),
            ("docs/arquitetura.html", "Arquitetura"),
            ("docs/solucao-de-problemas.html", "Solução de problemas"),
            ("docs/tecnico.html", "Documentação técnica"),
        ]
        col_proj = [
            (f"{REPO}", "GitHub"),
            (f"{REPO}/issues", "Issues"),
            (f"{REPO}/blob/main/LICENSE", "Licença MIT"),
            ("docs/creditos.html", "Créditos"),
            ("docs/historico.html", "Histórico de nomes"),
            ("docs/migracao-msbos.html", "Migração"),
        ]
        upstream = [
            ("https://fedoraproject.org", "Fedora Project"),
            ("https://kde.org", "KDE"),
            ("https://github.com/YaLTeR/niri", "niri"),
            ("https://noctalia.dev", "Noctalia"),
            ("https://github.com/kennylevinsen/greetd", "greetd"),
        ]
        tagline = "Distro pessoal baseada no Fedora, com niri e Noctalia v5."
        rights = "Projeto pessoal · licença MIT"
    else:
        col_docs = [
            ("en/docs/index.html", "Documentation index"),
            ("en/docs/instalacao.html", "Installation"),
            ("en/docs/uso.html", "Daily use"),
            ("en/docs/arquitetura.html", "Architecture"),
            ("en/docs/solucao-de-problemas.html", "Troubleshooting"),
            ("docs/tecnico.html", "Technical docs (PT)"),
        ]
        col_proj = [
            (f"{REPO}", "GitHub"),
            (f"{REPO}/issues", "Issues"),
            (f"{REPO}/blob/main/LICENSE", "MIT License"),
            ("en/docs/creditos.html", "Credits"),
            ("en/docs/historico.html", "Name history"),
            ("en/docs/migracao-msbos.html", "Migration"),
        ]
        upstream = [
            ("https://fedoraproject.org", "Fedora Project"),
            ("https://kde.org", "KDE"),
            ("https://github.com/YaLTeR/niri", "niri"),
            ("https://noctalia.dev", "Noctalia"),
            ("https://github.com/kennylevinsen/greetd", "greetd"),
        ]
        tagline = "A personal Fedora-based distro with niri and Noctalia v5."
        rights = "Personal project · MIT license"

    def links(items):
        out = []
        for h, l in items:
            if h.startswith("http"):
                out.append(f'<li><a href="{h}" rel="noopener">{l}</a></li>')
            else:
                out.append(f'<li><a href="{rel(page, h)}">{l}</a></li>')
        return "".join(out)

    return f"""<footer class="site-footer">
  <div class="container container--wide">
    <div class="footer-grid">
      <div class="footer-brand">
        <a class="brand" href="{rel(page, 'index.html')}">
          <img src="{root}/assets/img/msbos-logo.png" alt="" width="30" height="30">
          <span class="brand-word">msbos</span>
        </a>
        <p>{tagline} {rights}.</p>
      </div>
      <div class="footer-col"><h4>{t['footer_docs']}</h4><ul>{links(col_docs)}</ul></div>
      <div class="footer-col"><h4>{t['footer_project']}</h4><ul>{links(col_proj)}</ul></div>
      <div class="footer-col"><h4>{t['footer_upstream']}</h4><ul>{links(upstream)}</ul></div>
    </div>
    <div class="footer-bottom">
      <span>© 2026 msbos</span>
      <p class="disclaimer">{t['footer_note']}</p>
    </div>
  </div>
</footer>"""


def shell(page: str, lang: str, title: str, description: str, body: str,
          active: str = "", has_en: bool = True, body_class: str = "") -> str:
    t = TEXT[lang]
    root = rel(page, ".")
    cls = f' class="{body_class}"' if body_class else ""
    return f"""<!DOCTYPE html>
<html lang="{t['html_lang']}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)}</title>
<meta name="description" content="{esc(description)}">
<meta name="color-scheme" content="dark">
<meta property="og:type" content="website">
<meta property="og:title" content="{esc(title)}">
<meta property="og:description" content="{esc(description)}">
<meta property="og:image" content="https://marcos2872.github.io/msbos/assets/img/msbos-logo.png">
<meta property="og:url" content="https://marcos2872.github.io/msbos/{page}">
<link rel="icon" href="{root}/assets/img/favicon.png" type="image/png">
<link rel="stylesheet" href="{root}/assets/css/site.css">
</head>
<body{cls}>
{header(page, lang, active, has_en)}
<main id="conteudo">
{body}
</main>
{footer(page, lang)}
<script src="{root}/assets/js/site.js" defer></script>
</body>
</html>
"""


# ─── páginas de documentação ────────────────────────────────────────────────

def doc_page(key: str, lang: str) -> str | None:
    data = BY_KEY[key]
    src = data[1] if lang == "pt" else data[2]
    if not src:
        return None
    page = f"docs/{key}.html" if lang == "pt" else f"en/docs/{key}.html"
    text = (ROOT / src).read_text(encoding="utf-8")
    lines = text.splitlines()

    title = None
    for line in lines:
        m = HEADING_RE.match(line)
        if m and len(m.group(1)) == 1:
            title = re.sub(r"[`*]", "", m.group(2)).strip()
            break
    title = title or data[3 if lang == "pt" else 4]

    md = Markdown(src, page, lang, make_linkmap(src, page, lang))
    body_html = md.render(lines)
    # remove o H1 do corpo: o cabeçalho da página já o mostra
    body_html = re.sub(r"<h1[^>]*>.*?</h1>", "", body_html, count=1, flags=re.S)

    desc = data[5 if lang == "pt" else 6]
    words = len(strip_tags(body_html).split())
    minutes = max(1, round(words / 210))

    # navegação lateral
    side = []
    for k, *_ in DOCS:
        d = BY_KEY[k]
        if lang == "en" and not d[2]:
            continue
        label = d[3] if lang == "pt" else d[4]
        href = f"{k}.html"
        cur = ' aria-current="page"' if k == key else ""
        side.append(f'<li><a href="{href}"{cur}>{label}</a></li>')

    # sumário da página
    toc_items = []
    for level, anchor, label in md.toc:
        if level > 3:
            continue
        toc_items.append(
            f'<li class="depth-{level}"><a href="#{esc(anchor)}">{esc(label)}</a></li>'
        )
    toc = (
        f'<aside class="toc" aria-label="{TEXT[lang]["on_this_page"]}">'
        f'<h2>{TEXT[lang]["on_this_page"]}</h2><ul>{"".join(toc_items)}</ul></aside>'
        if toc_items else "<aside></aside>"
    )

    # paginador
    order = [k for k, *_ in DOCS if lang == "pt" or BY_KEY[k][2]]
    idx = order.index(key)
    pager = []
    if idx > 0:
        prev_key = order[idx - 1]
        pager.append(
            f'<a href="{prev_key}.html" class="prev"><span>{TEXT[lang]["prev"]}</span>'
            f'{BY_KEY[prev_key][3] if lang == "pt" else BY_KEY[prev_key][4]}</a>'
        )
    if idx + 1 < len(order):
        next_key = order[idx + 1]
        pager.append(
            f'<a href="{next_key}.html" class="next"><span>{TEXT[lang]["next"]}</span>'
            f'{BY_KEY[next_key][3] if lang == "pt" else BY_KEY[next_key][4]}</a>'
        )

    meta = [
        f'<span>{minutes} {TEXT[lang]["read"]}</span>',
        f'<a href="{REPO}/blob/main/{src}" rel="noopener">{TEXT[lang]["edit"]}</a>',
    ]

    body = f"""<div class="container container--wide">
  <div class="doc-shell">
    <nav class="doc-side" aria-label="{TEXT[lang]['docs']}">
      <h2>{TEXT[lang]['doc_index']}</h2>
      <ul>{''.join(side)}</ul>
    </nav>
    <article class="doc-main">
      <header class="doc-head">
        <span class="eyebrow eyebrow--accent">msbos · {esc(data[3] if lang == 'pt' else data[4])}</span>
        <h1>{esc(title)}</h1>
        <p>{esc(desc)}</p>
        <div class="doc-meta">{''.join(meta)}</div>
      </header>
      <div class="prose">
{body_html}
      </div>
      <nav class="doc-pager" aria-label="Paginação">{''.join(pager)}</nav>
    </article>
    {toc}
  </div>
</div>"""

    full_title = f"{title} · msbos" if key != "index" else f"{TEXT[lang]['docs']} · msbos"
    return shell(page, lang, full_title, desc, body, active=key, has_en=bool(data[2]))


# ─── página inicial ─────────────────────────────────────────────────────────

def landing(lang: str) -> str:
    page = "index.html" if lang == "pt" else "en/index.html"
    root = rel(page, ".")
    L = (lambda pt, en: pt if lang == "pt" else en)

    chips = ["Fedora 44/45", "niri", "Noctalia v5", "greetd", "Breeze Dark",
             "zram zstd", "SELinux", "bash idempotente"]

    layers = [
        ("01", L("Aplicativos", "Applications"),
         L("Dolphin, Konsole, Kate… Zed, Brave, ONLYOFFICE, alacritty", "Dolphin, Konsole, Kate… Zed, Brave, ONLYOFFICE, alacritty"),
         "apps", "layer--mid"),
        ("02", L("Shell do desktop", "Desktop shell"),
         L("Noctalia v5 — barra, launcher, OSD, lock screen, wallpaper", "Noctalia v5 — bar, launcher, OSD, lock screen, wallpaper"),
         "shell", "layer--mid"),
        ("03", L("Sessão gráfica", "Graphical session"),
         L("niri — compositor Wayland com tiling rolável", "niri — Wayland compositor with scrollable tiling"),
         "session", "layer--top"),
        ("04", L("Login", "Login"),
         L("greetd + Noctalia Greeter", "greetd + Noctalia Greeter"),
         "login", "layer--base"),
        ("05", L("Sistema", "System"),
         L("Fedora 44/45, systemd, SELinux, dnf", "Fedora 44/45, systemd, SELinux, dnf"),
         "base", "layer--base"),
    ]
    layers_html = "".join(
        f'<div class="layer {cls}"><span class="layer-idx">{idx}</span>'
        f'<span class="layer-name">{name}<small>{desc}</small></span>'
        f'<span class="layer-tag">{tag}</span></div>'
        for idx, name, desc, tag, cls in layers
    )

    stages_pt = [
        ("10-gpu.sh", "Detecta a GPU", "Intel/AMD/NVIDIA (inclusive híbrida) e instala o driver; RPM Fusion e <code>nvidia-drm.modeset=1</code> no NVIDIA."),
        ("20-stack.sh", "Monta o stack", "niri, Noctalia, greetd, áudio, portais, apps; curadoria dos apps KDE e agendamento da remoção do shell do Plasma."),
        ("25-devtools.sh", "Ferramentas", "gcc/make, GitHub CLI, Rust (rustup), Node LTS via nvm, pnpm/yarn e KVM/libvirt."),
        ("30-services.sh", "Serviços e login", "greetd assume o boot, outros DMs mascarados, daemons dispensáveis desligados."),
        ("40-tuning.sh", "Memória", "zram zstd, sysctl, <code>compress=zstd:1</code> no btrfs, oomd e perfil de energia."),
        ("50-configs.sh", "Configuração", "niri, Noctalia, Breeze Dark, greetd/PAM, wallpapers, zsh, apps padrão e atalhos."),
        ("60-agent-skill.sh", "Privilégio", "Helper polkit para agentes de IA, listas de root e skills em <code>~/.agents/skills/</code>."),
        ("55-niri-zoom.sh", "Zoom por output", "Opcional: compila o fork do niri com zoom por monitor e instala em <code>/usr/local/bin/niri</code>."),
    ]
    stages_en = [
        ("10-gpu.sh", "Detects the GPU", "Intel/AMD/NVIDIA (including hybrid) and installs the driver; RPM Fusion and <code>nvidia-drm.modeset=1</code> on NVIDIA."),
        ("20-stack.sh", "Builds the stack", "niri, Noctalia, greetd, audio, portals, apps; KDE app curation and schedules the Plasma shell removal."),
        ("25-devtools.sh", "Tooling", "gcc/make, GitHub CLI, Rust (rustup), Node LTS via nvm, pnpm/yarn and KVM/libvirt."),
        ("30-services.sh", "Services and login", "greetd takes over boot, other DMs masked, dispensable daemons disabled."),
        ("40-tuning.sh", "Memory", "zram zstd, sysctl, <code>compress=zstd:1</code> on btrfs, oomd and power profile."),
        ("50-configs.sh", "Configuration", "niri, Noctalia, Breeze Dark, greetd/PAM, wallpapers, zsh, default apps and shortcuts."),
        ("60-agent-skill.sh", "Privilege", "polkit helper for AI agents, root lists and skills in <code>~/.agents/skills/</code>."),
        ("55-niri-zoom.sh", "Per-output zoom", "Optional: builds the niri fork with per-monitor zoom into <code>/usr/local/bin/niri</code>."),
    ]
    stages = stages_pt if lang == "pt" else stages_en
    stages_html = "".join(
        f'<div class="stage{" stage--optin" if i == 7 else ""}">'
        f'<h3><code>{name}</code></h3><p><strong>{title}</strong> — {desc}</p></div>'
        for i, (name, title, desc) in enumerate(stages)
    )

    keys = [
        ("Super + T", L("Terminal (alacritty)", "Terminal (alacritty)")),
        ("Super + Space", L("Launcher do Noctalia", "Noctalia launcher")),
        ("Super + S", L("Control center", "Control center")),
        ("Super + P", L("Monitores (Niri Displays)", "Displays (Niri Displays)")),
        ("Super + O", L("Overview", "Overview")),
        ("Super + Q", L("Fechar a janela", "Close window")),
        ("Super + 1…9", L("Área de trabalho 1…9", "Workspace 1…9")),
        ("Alt + Tab", L("Window switcher", "Window switcher")),
        ("Super + Alt + L", L("Bloquear a sessão", "Lock the session")),
        ("Super + Shift + /", L("Overlay de atalhos", "Shortcut overlay")),
    ]
    keys_html = "".join(
        '<li class="kbd-item"><span>'
        + " ".join(f'<kbd>{k.strip()}</kbd>' for k in combo.split("+"))
        + f"</span><span>{label}</span></li>"
        for combo, label in keys
    )

    doc_cards = []
    for k, *_ in DOCS:
        d = BY_KEY[k]
        if lang == "en" and not d[2]:
            continue
        if k in ("index",):
            continue
        label = d[3] if lang == "pt" else d[4]
        desc = d[5] if lang == "pt" else d[6]
        href = f"docs/{k}.html" if lang == "pt" else f"en/docs/{k}.html"
        doc_cards.append(
            f'<a class="doc-card" href="{rel(page, href)}">'
            f'<span class="doc-card__title">{ICON["doc"]}{esc(label)}</span>'
            f'<span class="doc-card__desc">{esc(desc)}</span>'
            f'<span class="doc-card__more">{L("Ler", "Read")} →</span></a>'
        )

    install_cmd = """curl -fsSL https://raw.githubusercontent.com/marcos2872/msbos/main/bootstrap.sh -o /tmp/msbos.sh
sudo bash /tmp/msbos.sh --dry-run   # simula tudo
sudo bash /tmp/msbos.sh             # instala
sudo reboot"""

    quote_before = [
        L("Shell do Plasma no login", "Plasma shell on login"),
        L("Plasma Login Manager", "Plasma Login Manager"),
        L("Barra e painéis do Plasma", "Plasma bar and panels"),
        L("Jogos, PIM, LibreOffice", "Games, PIM, LibreOffice"),
        L("Wallpaper e tema do Plasma", "Plasma wallpaper and theme"),
    ]
    quote_after = [
        L("greetd + Noctalia Greeter", "greetd + Noctalia Greeter"),
        L("niri com tiling rolável", "niri with scrollable tiling"),
        L("Noctalia v5: barra, launcher, OSD", "Noctalia v5: bar, launcher, OSD"),
        L("Apps KDE mantidos, Breeze Dark", "KDE apps kept, Breeze Dark"),
        L("zram zstd, oomd, trimmed services", "zram zstd, oomd, trimmed services"),
    ]

    title = L("msbos — distro pessoal Fedora com niri + Noctalia",
              "msbos — personal Fedora distro with niri + Noctalia")
    desc = L("Suíte de scripts bash idempotentes que transforma um Fedora 44/45 já instalado "
             "em um desktop enxuto com niri (Wayland) e Noctalia v5, mantendo os apps do KDE.",
             "A suite of idempotent bash scripts that turns an existing Fedora 44/45 install "
             "into a lean desktop with niri (Wayland) and Noctalia v5, keeping the KDE apps.")

    hero = f"""<section class="hero">
  <div class="hero-bg" aria-hidden="true">
    <picture>
      <source srcset="{root}/assets/img/wallpaper.webp" type="image/webp">
      <img src="{root}/assets/img/wallpaper.jpg" alt="" width="1920" height="1080" fetchpriority="high">
    </picture>
  </div>
  <div class="container">
    <img class="hero-mark" src="{root}/assets/img/msbos-logo.png" alt="Logo do msbos" width="104" height="104">
    <span class="eyebrow">{L("Fedora 44/45 · niri · Noctalia v5", "Fedora 44/45 · niri · Noctalia v5")}</span>
    <h1>msbos</h1>
    <p class="hero-tagline">{L("Um desktop <strong>enxuto e de baixo consumo</strong> montado sobre o Fedora que você já tem.", "A <strong>lean, low-footprint desktop</strong> built on top of the Fedora you already have.")}</p>
    <p class="hero-sub">{L("Rota C, sem ISO própria: um orquestrador de scripts idempotentes troca o shell do Plasma pelo niri e pelo Noctalia v5, instala o driver da GPU e ajusta memória e desempenho — mantendo os apps do KDE.", "Route C, no custom ISO: an orchestrator of idempotent scripts swaps the Plasma shell for niri and Noctalia v5, installs the GPU driver and tunes memory and performance — while keeping the KDE apps.")}</p>
    <div class="hero-actions">
      <a class="btn btn--primary" href="{rel(page, 'docs/instalacao.html' if lang == 'pt' else 'en/docs/instalacao.html')}">{L("Começar a instalação", "Get started")}{ICON['arrow']}</a>
      <a class="btn" href="{rel(page, 'docs/arquitetura.html' if lang == 'pt' else 'en/docs/arquitetura.html')}">{ICON['layers']}{L("Ver a arquitetura", "See the architecture")}</a>
      <a class="btn" href="{REPO}" rel="noopener">{ICON['github']}GitHub</a>
    </div>
    <ul class="chips">{''.join(f'<li>{esc(c)}</li>' for c in chips)}</ul>
  </div>
</section>"""

    what = f"""<section class="section" id="o-que-e">
  <div class="container">
    <div class="section-head section-head--center">
      <span class="eyebrow eyebrow--accent">{L("O que é", "What it is")}</span>
      <h2>{L("A cola pessoal entre projetos excelentes", "The personal glue between excellent projects")}</h2>
      <p>{L("O msbos não reescreve o Fedora: ele aplica uma camada pessoal sobre a base, o kernel e os apps que já existem. O resultado é um desktop Wayland enxuto, com login próprio e os aplicativos do dia a dia intactos.", "msbos does not rewrite Fedora: it applies a personal layer on top of the existing base, kernel and apps. The result is a lean Wayland desktop with its own login, and your daily applications untouched.")}</p>
    </div>
    <div class="grid grid--3">
      <article class="card card--hover">
        <span class="card-icon">{ICON['terminal']}</span>
        <span class="card-kicker">{L("Sem ISO", "No ISO")}</span>
        <h3>{L("Rota C", "Route C")}</h3>
        <p>{L("Nada de infraestrutura de build: um script de bootstrap baixa o repositório e aplica a configuração sobre um Fedora 44/45 já instalado.", "No build infrastructure: a bootstrap script downloads the repository and applies the configuration onto an already installed Fedora 44/45.")}</p>
      </article>
      <article class="card card--hover">
        <span class="card-icon">{ICON['layers']}</span>
        <span class="card-kicker">niri + Noctalia</span>
        <h3>{L("Desktop enxuto", "Lean desktop")}</h3>
        <p>{L("Compositor Wayland com tiling rolável e um shell completo: barra, launcher, notificações, OSD, control center, lock screen e wallpaper.", "A Wayland compositor with scrollable tiling and a complete shell: bar, launcher, notifications, OSD, control center, lock screen and wallpaper.")}</p>
      </article>
      <article class="card card--hover">
        <span class="card-icon">{ICON['palette']}</span>
        <span class="card-kicker">KDE</span>
        <h3>{L("Apps mantidos", "Apps kept")}</h3>
        <p>{L("Dolphin, Konsole, Kate/KWrite, Okular, Gwenview, Spectacle, Dragon, Elisa… seguem instalados e usam o Breeze Dark, o tema dark padrão do KDE.", "Dolphin, Konsole, Kate/KWrite, Okular, Gwenview, Spectacle, Dragon, Elisa… stay installed and use Breeze Dark, KDE's default dark theme.")}</p>
      </article>
    </div>
  </div>
</section>"""

    layers_section = f"""<section class="section" id="camadas">
  <div class="container">
    <div class="section-head">
      <span class="eyebrow">{L("Em camadas", "Layered")}</span>
      <h2>{L("O que fica em cima do quê", "What sits on top of what")}</h2>
      <p>{L("A troca acontece na camada de sessão e de shell. O sistema continua sendo Fedora — systemd, SELinux, dnf e o kernel que já estavam lá.", "The swap happens at the session and shell layers. The system is still Fedora — the systemd, SELinux, dnf and kernel that were already there.")}</p>
    </div>
    <div class="layers">{layers_html}</div>
    <div class="flow" aria-label="{L('Fluxo de execução', 'Execution flow')}">
      <span class="flow-step">install.sh</span><span class="flow-arrow">→</span>
      <span class="flow-step">scripts/NN-*.sh</span><span class="flow-arrow">→</span>
      <span class="flow-step">lib/common.sh</span><span class="flow-arrow">+</span>
      <span class="flow-step">assets/**</span><span class="flow-arrow">→</span>
      <span class="flow-step">/etc · /usr · /var · ~</span>
    </div>
  </div>
</section>"""

    swap_section = f"""<section class="section" id="antes-depois">
  <div class="container">
    <div class="section-head">
      <span class="eyebrow">{L("Antes e depois", "Before and after")}</span>
      <h2>{L("O que sai e o que entra", "What leaves and what arrives")}</h2>
      <p>{L("O instalador remove apenas o shell do Plasma — e agenda a remoção para o próximo boot, fora da sessão viva.", "The installer removes only the Plasma shell — and schedules it for the next boot, outside the live session.")}</p>
    </div>
    <div class="swap">
      <div class="swap-col swap-col--before">
        <div class="swap-head"><span class="dot"></span>{L("Fedora KDE", "Fedora KDE")}</div>
        <ul class="swap-list">{''.join(f'<li>{ICON["cross"]}<span>{esc(x)}</span></li>' for x in quote_before)}</ul>
      </div>
      <div class="swap-col swap-col--after">
        <div class="swap-head"><span class="dot"></span>msbos</div>
        <ul class="swap-list">{''.join(f'<li>{ICON["check"]}<span>{esc(x)}</span></li>' for x in quote_after)}</ul>
      </div>
    </div>
  </div>
</section>"""

    stages_section = f"""<section class="section" id="etapas">
  <div class="container">
    <div class="section-head">
      <span class="eyebrow eyebrow--accent">{L("Como funciona", "How it works")}</span>
      <h2>{L("Sete etapas base, uma opt-in e duas de migração", "Seven base steps, one opt-in and two migration steps")}</h2>
      <p>{L("O install.sh descobre scripts/NN-*.sh em ordem e para na primeira falha. Toda etapa detecta antes de agir: rodar de novo é seguro.", "install.sh discovers scripts/NN-*.sh in order and stops at the first failure. Every step detects before acting: re-running is safe.")}</p>
    </div>
    <div class="pipeline">{stages_html}</div>
    <p style="margin-top:1.25rem;color:var(--muted);font-size:.9rem">{L("Além dessas, <code>00-migrate-names.sh</code> prepara uma instalação antiga e <code>99-cleanup-legacy.sh</code> remove os artefatos legados depois que os novos existem. Em instalação nova, as duas são no-op.", "Besides these, <code>00-migrate-names.sh</code> prepares an old install and <code>99-cleanup-legacy.sh</code> removes legacy artifacts once the new ones exist. On a fresh install both are no-ops.")}</p>
  </div>
</section>"""

    numbers = [
        ("118", L("arquivos em assets/", "files in assets/")),
        ("10", L("etapas no fluxo", "steps in the flow")),
        ("7", L("ações de polkit no helper", "polkit actions in the helper")),
        ("5", L("jobs de CI a cada push", "CI jobs per push")),
    ]
    numbers_html = "".join(
        f'<div class="card" style="text-align:center;padding:1.5rem 1rem">'
        f'<div style="font-size:clamp(2rem,5vw,2.8rem);font-weight:600;letter-spacing:-.04em;'
        f'background:linear-gradient(180deg,#fff,#b9b8fb);-webkit-background-clip:text;background-clip:text;color:transparent">{n}</div>'
        f'<div style="color:var(--muted);font-size:.83rem;margin-top:.3rem">{esc(l)}</div></div>'
        for n, l in numbers
    )

    guarantees = f"""<section class="section" id="garantias">
  <div class="container">
    <div class="section-head section-head--center">
      <span class="eyebrow">{L("Garantias", "Guarantees")}</span>
      <h2>{L("Seguro de rodar de novo", "Safe to run again")}</h2>
    </div>
    <div class="grid grid--4" style="margin-bottom:1.25rem">{numbers_html}</div>
    <div class="grid grid--3">
      <article class="card"><span class="card-icon">{ICON['shield']}</span><h3>{L("Idempotente e com backup", "Idempotent and backed up")}</h3><p>{L("Cada etapa detecta o que já existe. Arquivos sobrescritos ganham um backup <code>.msbos-bak</code> na primeira vez.", "Each step detects what already exists. Overwritten files get a <code>.msbos-bak</code> backup the first time.")}</p></article>
      <article class="card"><span class="card-icon">{ICON['terminal']}</span><h3>--dry-run</h3><p>{L("Simula tudo: não instala, não remove, não escreve e não acessa a rede. É a primeira verificação recomendada.", "Simulates everything: no installs, removals, writes or network access. The recommended first check.")}</p></article>
      <article class="card"><span class="card-icon">{ICON['lock']}</span><h3>{L("Privilégio com portão", "Gated privilege")}</h3><p>{L("Operações destrutivas passam por <code>exige_ok</code>; o helper para agentes de IA só aceita ações da lista, com senha de administrador.", "Destructive operations go through <code>exige_ok</code>; the AI-agent helper only accepts listed actions, behind an admin password.")}</p></article>
    </div>
  </div>
</section>"""

    keys_section = f"""<section class="section" id="atalhos">
  <div class="container">
    <div class="section-head">
      <span class="eyebrow">{L("No dia a dia", "Every day")}</span>
      <h2>{L("Atalhos essenciais", "Essential shortcuts")}</h2>
      <p>{L("Os padrões instalados em <code>~/.config/niri/config.kdl</code>. Suas edições são preservadas nas reexecuções.", "The defaults installed in <code>~/.config/niri/config.kdl</code>. Your edits are preserved across re-runs.")}</p>
    </div>
    <ul class="kbd-grid">{keys_html}</ul>
    <p style="margin-top:1.1rem;color:var(--muted);font-size:.9rem">{L('<a href="' + rel(page, 'docs/uso.html') + '">Tabela completa de atalhos →</a>', '<a href="' + rel(page, 'en/docs/uso.html') + '">Full shortcut table →</a>')}</p>
  </div>
</section>"""

    docs_section = f"""<section class="section" id="documentacao">
  <div class="container">
    <div class="section-head">
      <span class="eyebrow eyebrow--accent">{TEXT[lang]['docs']}</span>
      <h2>{L("Tudo documentado, por assunto", "Everything documented, by topic")}</h2>
      <p>{L("Instalação passo a passo, uso diário, arquitetura das etapas, solução de problemas e a documentação técnica de implementação.", "Step-by-step installation, daily use, step architecture, troubleshooting and the technical implementation docs.")}</p>
    </div>
    <div class="grid grid--3">{''.join(doc_cards)}</div>
  </div>
</section>"""

    install_section = f"""<section class="section" id="instalar">
  <div class="container">
    <div class="grid grid--2" style="align-items:center;gap:2rem">
      <div>
        <span class="eyebrow eyebrow--accent">{L("Instalação", "Installation")}</span>
        <h2 style="font-size:clamp(1.6rem,3vw,2.2rem);margin-top:.6rem">{L("Do Fedora ao login do msbos", "From Fedora to the msbos login")}</h2>
        <p style="color:var(--fg-dim);margin-top:.9rem">{L("Sem clonar o repositório: o bootstrap baixa o .tar.gz, extrai e chama o install.sh. A troca do shell vale no próximo boot — nada é parado na sessão atual.", "Without cloning: the bootstrap downloads the .tar.gz, extracts it and runs install.sh. The shell swap takes effect on the next boot — nothing is stopped in the live session.")}</p>
        <ul class="spec-list" style="margin-top:1.1rem">
          <li><span>{L("Base recomendada: <strong>Fedora KDE</strong> (ou instalação mínima)", "Recommended base: <strong>Fedora KDE</strong> (or a minimal install)")}</span></li>
          <li><span>{L("Em VM: virtio-gpu com aceleração 3D e GL no Spice", "In a VM: virtio-gpu with 3D acceleration and GL on Spice")}</span></li>
          <li><span>{L("Requisitos: Fedora 44/45 x86_64, internet e sudo", "Requirements: Fedora 44/45 x86_64, internet and sudo")}</span></li>
        </ul>
        <div class="hero-actions" style="justify-content:flex-start;margin-top:1.5rem">
          <a class="btn btn--primary" href="{rel(page, 'docs/instalacao.html' if lang == 'pt' else 'en/docs/instalacao.html')}">{L("Guia de instalação", "Installation guide")}{ICON['arrow']}</a>
        </div>
      </div>
      <div class="codeblock"><div class="codeblock__head"><span class="codeblock__lang">bash</span><button type="button" class="codeblock__copy" data-copy>{TEXT[lang]['copy']}</button></div><pre><code>{esc(install_cmd)}</code></pre></div>
    </div>
  </div>
</section>"""

    credits = f"""<section class="section" id="creditos">
  <div class="container">
    <div class="section-head section-head--center">
      <span class="eyebrow">{L("Créditos", "Credits")}</span>
      <h2>{L("Feito de trabalho de muita gente", "Built on many people's work")}</h2>
      <p>{L("O msbos é só a cola pessoal entre projetos excelentes. Obrigado a quem mantém cada um deles.", "msbos is just the personal glue between excellent projects. Thanks to everyone who maintains them.")}</p>
    </div>
    <div class="grid grid--4">
      <a class="card card--hover" href="https://fedoraproject.org" rel="noopener"><span class="card-kicker">Base</span><h3>Fedora</h3><p>{L("Sistema, pacotes, dnf, SELinux e systemd.", "System, packages, dnf, SELinux and systemd.")}</p></a>
      <a class="card card--hover" href="https://github.com/YaLTeR/niri" rel="noopener"><span class="card-kicker">{L("Compositor", "Compositor")}</span><h3>niri</h3><p>{L("Tiling rolável, por YaLTeR.", "Scrollable tiling, by YaLTeR.")}</p></a>
      <a class="card card--hover" href="https://noctalia.dev" rel="noopener"><span class="card-kicker">Shell</span><h3>Noctalia</h3><p>{L("Barra, launcher, OSD, lock screen e greeter.", "Bar, launcher, OSD, lock screen and greeter.")}</p></a>
      <a class="card card--hover" href="https://kde.org" rel="noopener"><span class="card-kicker">Apps</span><h3>KDE</h3><p>{L("Aplicativos e Breeze Dark.", "Applications and Breeze Dark.")}</p></a>
    </div>
    <p style="text-align:center;margin-top:1.5rem;color:var(--muted);font-size:.9rem">{L('<a href="' + rel(page, 'docs/creditos.html') + '">Créditos completos</a>', '<a href="' + rel(page, 'en/docs/creditos.html') + '">Full credits</a>')}</p>
  </div>
</section>"""

    mascot_section = f"""<section class="section" id="mascote" style="padding-block:0">
  <div class="container">
    <div class="mascot">
      <div>
        <span class="eyebrow eyebrow--accent">{L("Um sistema, um nome", "One system, one name")}</span>
        <h2 style="margin-top:.55rem">{L("Um nome, uma família de scripts", "One name, one family of scripts")}</h2>
        <p>{L('O projeto teve outros nomes antes de chegar ao <strong>msbos</strong> — <em>M</em>arcos <em>S</em>ouza <em>B</em>rito + <em>OS</em>. Quem vem de uma instalação antiga migra sem reinstalar o Fedora: os scripts <code>00-migrate-names.sh</code> e <code>99-cleanup-legacy.sh</code> levam os caminhos, serviços e configurações para o nome atual.', 'The project had other names before <strong>msbos</strong> — <em>M</em>arcos <em>S</em>ouza <em>B</em>rito + <em>OS</em>. Coming from an older install, you migrate without reinstalling Fedora: <code>00-migrate-names.sh</code> and <code>99-cleanup-legacy.sh</code> move paths, services and settings to the current name.')}</p>
        <div class="mascot-actions">
          <a class="btn" href="{rel(page, 'docs/historico.html' if lang == 'pt' else 'en/docs/historico.html')}">{ICON['doc']}{L("Histórico de nomes", "Name history")}</a>
          <a class="btn" href="{rel(page, 'docs/migracao-msbos.html' if lang == 'pt' else 'en/docs/migracao-msbos.html')}">{L("Como migrar", "How to migrate")}{ICON['arrow']}</a>
        </div>
      </div>
      <img src="{root}/assets/img/msbos-mascot.webp" alt="{L('Mascote do msbos', 'msbos mascot')}" width="520" height="520" loading="lazy">
    </div>
  </div>
</section>"""

    body = (hero + what + layers_section + swap_section + stages_section
            + guarantees + keys_section + docs_section + mascot_section
            + install_section + credits)
    return shell(page, lang, title, desc, body, active="index-page", has_en=True)


# ─── main ───────────────────────────────────────────────────────────────────

def write(path: str, content: str, check: bool) -> None:
    target = WEB / path
    if check:
        print(f"  (check) {path}")
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    print(f"  {path}  ({len(content) // 1024} kB)")


def broken_links(files: list[Path]) -> list[str]:
    problems = []
    existing = {p.relative_to(WEB).as_posix() for p in WEB.rglob("*") if p.is_file()}
    id_cache: dict[str, set[str]] = {}

    def ids_of(target: Path) -> set[str]:
        key = target.as_posix()
        if key not in id_cache:
            src = target.read_text(encoding="utf-8")
            found = set(re.findall(r'\sid="([^"]+)"', src))
            id_cache[key] = found
        return id_cache[key]

    for f in files:
        text = f.read_text(encoding="utf-8")
        relf = f.relative_to(WEB).as_posix()
        for m in re.finditer(r'(?:href|src)="([^"]+)"', text):
            href = m.group(1)
            if href.startswith(("http://", "https://", "mailto:", "#", "data:")):
                continue
            path, _, frag = href.partition("#")
            target = (f.parent / path).resolve() if path else f.resolve()
            if not target.exists():
                problems.append(f"{relf}: {href} (arquivo não existe)")
                continue
            if frag and target.suffix == ".html":
                allowed = ids_of(target)
                if frag not in allowed and frag not in ("conteudo",):
                    problems.append(f"{relf}: {href} (âncora não existe)")
    return problems


def main() -> int:
    check = "--check" in sys.argv
    pages: list[str] = []

    print("msbos — gerando o site")
    land_pt = landing("pt")
    land_en = landing("en")
    write("index.html", land_pt, check)
    write("en/index.html", land_en, check)
    pages += ["index.html", "en/index.html"]

    for key, *_ in DOCS:
        for lang in ("pt", "en"):
            data = BY_KEY[key]
            if lang == "en" and not data[2]:
                continue
            page = f"docs/{key}.html" if lang == "pt" else f"en/docs/{key}.html"
            content = doc_page(key, lang)
            if content:
                write(page, content, check)
                pages.append(page)

    html_files = [WEB / p for p in pages] if not check else []
    if not check:
        problems = broken_links(html_files)
        if problems:
            print("\nlinks quebrados:")
            for p in problems:
                print("  " + p)
            return 1
        print(f"\n{len(pages)} páginas geradas; nenhum link quebrado.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
