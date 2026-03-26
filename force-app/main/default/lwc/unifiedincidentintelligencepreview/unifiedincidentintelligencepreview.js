import { LightningElement, api } from 'lwc';

export default class UnifiedIncidentIntelligencePreview extends LightningElement {

    _markdownText = '';

    @api
    get markdownText() {
        return this._markdownText;
    }
    set markdownText(value) {
        this._markdownText = value;
        if (this._rendered) {
            this.renderMarkdown();
        }
    }

    _rendered = false;

    renderedCallback() {
        if (!this._rendered) {
            this._rendered = true;
            this.renderMarkdown();
        }
    }

    renderMarkdown() {
        const container = this.template.querySelector('.markdown-body');
        if (!container) return;

        const html = this.parseMarkdown(this._markdownText || '');
        container.innerHTML = html;
    }

    /* ───────────────────────────────────────────
     * Helpers
     * ─────────────────────────────────────────── */

    isTableRow(line) {
        const trimmed = line.trim();
        return trimmed.startsWith('|') && trimmed.endsWith('|') && trimmed.includes('|');
    }

    isTableSeparator(line) {
        const trimmed = line.trim();
        if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) return false;
        const inner = trimmed.slice(1, -1);
        return inner.split('|').every(cell => /^[\s:]*-{2,}[\s:]*$/.test(cell));
    }

    parseTableCells(line) {
        const trimmed = line.trim();
        // Strip leading and trailing pipes, then split on inner pipes
        const inner = trimmed.startsWith('|') ? trimmed.slice(1) : trimmed;
        const stripped = inner.endsWith('|') ? inner.slice(0, -1) : inner;
        return stripped.split('|').map(cell => cell.trim());
    }

    parseTableAlignments(line) {
        const cells = this.parseTableCells(line);
        return cells.map(cell => {
            const left = cell.startsWith(':');
            const right = cell.endsWith(':');
            if (left && right) return 'center';
            if (right) return 'right';
            return 'left';
        });
    }

    buildTable(tableLines) {
        if (tableLines.length < 2) {
            // Not enough lines for a valid table, return as paragraphs
            return tableLines.map(l => `<p class="md-paragraph">${this.parseInline(l)}</p>`).join('');
        }

        const headerLine = tableLines[0];
        const separatorLine = tableLines[1];
        const dataLines = tableLines.slice(2);

        const headers = this.parseTableCells(headerLine);
        const alignments = this.isTableSeparator(separatorLine)
            ? this.parseTableAlignments(separatorLine)
            : headers.map(() => 'left');

        let html = '<div class="md-table-wrapper"><table class="md-table">';

        // Thead
        html += '<thead><tr>';
        headers.forEach((header, idx) => {
            const align = alignments[idx] || 'left';
            html += `<th style="text-align:${align}">${this.parseInline(header)}</th>`;
        });
        html += '</tr></thead>';

        // Tbody
        html += '<tbody>';
        dataLines.forEach(line => {
            const cells = this.parseTableCells(line);
            html += '<tr>';
            headers.forEach((_, idx) => {
                const align = alignments[idx] || 'left';
                const value = idx < cells.length ? cells[idx] : '';
                html += `<td style="text-align:${align}">${this.parseInline(value)}</td>`;
            });
            html += '</tr>';
        });
        html += '</tbody></table></div>';

        return html;
    }

    closeOpenBlock(state, output) {
        if (state.inUl) {
            output.push('</ul>');
            state.inUl = false;
        }
        if (state.inOl) {
            output.push('</ol>');
            state.inOl = false;
        }
        if (state.inBlockquote) {
            output.push('</blockquote>');
            state.inBlockquote = false;
        }
    }

    /* ───────────────────────────────────────────
     * Main parser
     * ─────────────────────────────────────────── */

    parseMarkdown(md) {
        if (!md) {
            return '<p class="md-empty">No analysis output available.</p>';
        }

        const lines = md.split('\n');
        const output = [];

        let inCodeBlock = false;
        let codeBuffer = [];

        const state = {
            inUl: false,
            inOl: false,
            inBlockquote: false
        };

        let i = 0;
        while (i < lines.length) {
            const line = lines[i];

            // ── Code block toggle ──
            if (line.trim().startsWith('```')) {
                if (inCodeBlock) {
                    output.push(
                        '<pre class="md-code-block"><code>' +
                        this.escapeHtml(codeBuffer.join('\n')) +
                        '</code></pre>'
                    );
                    codeBuffer = [];
                    inCodeBlock = false;
                } else {
                    this.closeOpenBlock(state, output);
                    inCodeBlock = true;
                }
                i++;
                continue;
            }

            if (inCodeBlock) {
                codeBuffer.push(line);
                i++;
                continue;
            }

            // ── Table detection ──
            // Look ahead: if current line is a table row and next line is a separator
            if (this.isTableRow(line) && i + 1 < lines.length && this.isTableSeparator(lines[i + 1])) {
                this.closeOpenBlock(state, output);

                // Collect all contiguous table lines
                const tableLines = [];
                while (i < lines.length && this.isTableRow(lines[i])) {
                    tableLines.push(lines[i]);
                    i++;
                }
                output.push(this.buildTable(tableLines));
                continue;
            }

            // ── Blank line ──
            if (line.trim() === '') {
                this.closeOpenBlock(state, output);
                i++;
                continue;
            }

            // ── Horizontal rule ──
            if (/^[-*_]{3,}$/.test(line.trim()) && !line.trim().match(/^[-*]\s/)) {
                this.closeOpenBlock(state, output);
                output.push('<hr class="md-hr"/>');
                i++;
                continue;
            }

            // ── Headers ──
            const headerMatch = line.match(/^(#{1,6})\s+(.+)$/);
            if (headerMatch) {
                this.closeOpenBlock(state, output);
                const level = headerMatch[1].length;
                const text = this.parseInline(headerMatch[2]);
                output.push(`<h${level} class="md-h${level}">${text}</h${level}>`);
                i++;
                continue;
            }

            // ── Blockquote ──
            const bqMatch = line.match(/^>\s?(.*)$/);
            if (bqMatch) {
                if (!state.inBlockquote) {
                    this.closeOpenBlock(state, output);
                    output.push('<blockquote class="md-blockquote">');
                    state.inBlockquote = true;
                }
                output.push(`<p class="md-paragraph">${this.parseInline(bqMatch[1])}</p>`);
                i++;
                continue;
            }

            // ── Ordered list (1. 2. etc.) ──
            const olMatch = line.match(/^[\s]*(\d+)[.)]\s+(.+)$/);
            if (olMatch) {
                if (state.inUl) { output.push('</ul>'); state.inUl = false; }
                if (state.inBlockquote) { output.push('</blockquote>'); state.inBlockquote = false; }
                if (!state.inOl) {
                    output.push('<ol class="md-olist">');
                    state.inOl = true;
                }
                output.push(`<li class="md-list-item">${this.parseInline(olMatch[2])}</li>`);
                i++;
                continue;
            }

            // ── Unordered list (- or *) ──
            const ulMatch = line.match(/^[\s]*[-*]\s+(.+)$/);
            if (ulMatch) {
                if (state.inOl) { output.push('</ol>'); state.inOl = false; }
                if (state.inBlockquote) { output.push('</blockquote>'); state.inBlockquote = false; }
                if (!state.inUl) {
                    output.push('<ul class="md-list">');
                    state.inUl = true;
                }
                output.push(`<li class="md-list-item">${this.parseInline(ulMatch[1])}</li>`);
                i++;
                continue;
            }

            // ── Regular paragraph ──
            this.closeOpenBlock(state, output);
            output.push(`<p class="md-paragraph">${this.parseInline(line)}</p>`);
            i++;
        }

        // Close any remaining open elements
        this.closeOpenBlock(state, output);
        if (inCodeBlock) {
            output.push(
                '<pre class="md-code-block"><code>' +
                this.escapeHtml(codeBuffer.join('\n')) +
                '</code></pre>'
            );
        }

        return output.join('');
    }

    /* ───────────────────────────────────────────
     * Inline parser
     * ─────────────────────────────────────────── */

    parseInline(text) {
        let result = this.escapeHtml(text);

        // Bold: **text**
        result = result.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

        // Italic: *text*
        result = result.replace(/\*(.+?)\*/g, '<em>$1</em>');

        // Inline code: `text`
        result = result.replace(/`(.+?)`/g, '<code class="md-inline-code">$1</code>');

        return result;
    }

    escapeHtml(text) {
        const map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        };
        return text.replace(/[&<>"']/g, (char) => map[char]);
    }
}