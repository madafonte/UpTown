/* UpTown - interface da Entrega 3. JS puro; toda a persistência passa pela API Java (JDBC). */
'use strict';

// ---------- utilidades ----------
const $main = document.getElementById('main');
const $modal = document.getElementById('modal');

/** Cria elementos sem innerHTML (os dados do banco entram sempre como texto). */
function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'value') el.value = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    el.append(c.nodeType ? c : document.createTextNode(String(c)));
  }
  return el;
}

async function api(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.erro || `Erro ${res.status}`);
  return data;
}

function toast(msg, err) {
  const t = h('div', { class: 'toast' + (err ? ' err' : ''), role: err ? 'alert' : 'status' }, msg);
  document.getElementById('toasts').append(t);
  setTimeout(() => t.remove(), err ? 6000 : 3000);
}

const brl = (v) => Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const num = (v, d = 0) => Number(v).toLocaleString('pt-BR', { minimumFractionDigits: d, maximumFractionDigits: d });
const dataBR = (iso) => (iso ? iso.split('-').reverse().join('/') : '');
const STATUS = ['Em separação', 'A caminho', 'Entregue', 'Cancelado'];
const STATUS_COR = { 'Entregue': '--s1', 'A caminho': '--s2', 'Em separação': '--s3', 'Cancelado': '--s8' };
const cssVar = (n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim();

function statusPill(s) {
  return h('span', { class: 'badge', style: `--dot: var(${STATUS_COR[s] || '--ink-3'})` }, s);
}

function abrirModal(titulo, corpo, botoes, largo) {
  $modal.className = largo ? 'wide' : '';
  $modal.replaceChildren(
    h('div', { class: 'modal-head' }, h('h2', {}, titulo),
      h('button', { class: 'small', onclick: () => $modal.close(), 'aria-label': 'Fechar' }, '✕')),
    h('div', { class: 'modal-body' }, corpo),
    h('div', { class: 'modal-foot' }, botoes));
  if (!$modal.open) $modal.showModal();
}

function confirmar(msg) { return window.confirm(msg); }

// ---------- componentes padrão das páginas ----------
/** Cabeçalho: título + subtítulo curto à esquerda, ações à direita. */
function cabecalho(titulo, sub, ...acoes) {
  return h('div', { class: 'pg-head' }, h('div', {}, h('h1', {}, titulo), h('p', { class: 'pg-sub' }, sub)), h('div', { class: 'tools' }, ...acoes));
}
/** Faixa de resumo: itens = [[rótulo, valor, dica?], ...]. */
function resumo(itens) {
  return h('div', { class: 'stats' }, itens.map(([l, v, d]) => h('div', { class: 'card stat' },
    h('div', { class: 'label' }, l), h('div', { class: 'value' }, v), d ? h('div', { class: 'hint' }, d) : null)));
}
/** Cartão de tabela: barra de ferramentas (filtros à esquerda, contagem à direita) sobre a tabela. */
function cartaoTabela(ferramentas, contagem, corpo) {
  return h('div', { class: 'card table-card' },
    h('div', { class: 'table-tools' }, h('div', { class: 'filters-inline' }, ferramentas), contagem), corpo);
}
const textoContagem = (vis, total, nome) => (vis === total ? `${num(total)} ${nome}` : `${num(vis)} de ${num(total)} ${nome}`);

// ---------- tabela genérica ----------
/** cols: [{key, label, num?, render?(row)}] */
function tabela(cols, rows, acoes) {
  if (!rows.length) return h('div', { class: 'empty' }, 'Nenhum registro encontrado.');
  return h('div', { class: 'table-wrap' }, h('table', {},
    h('thead', {}, h('tr', {}, cols.map((c) => h('th', { class: c.num ? 'num' : '' }, c.label)), acoes ? h('th', {}) : null)),
    h('tbody', {}, rows.map((r) => h('tr', {},
      cols.map((c) => h('td', { class: c.num ? 'num' : '' }, c.render ? c.render(r) : (r[c.key] ?? '')) ),
      acoes ? h('td', { class: 'actions' }, acoes(r)) : null)))));
}

// ---------- CRUD genérico ----------
/**
 * cfg: { titulo, sub, url, chave, cols, campos:[{nome,label,tipo,opcoes?,ajuda?}], vazio }
 * Usado por Clientes, Fornecedores e Categorias (INSERT / UPDATE / DELETE).
 */
async function viewCrud(cfg) {
  let dados = [];
  let filtro = '';
  const area = h('div');
  const resumoBox = h('div');
  const contagem = h('span', { class: 'count' });
  const busca = h('input', { type: 'search', placeholder: 'Buscar…', 'aria-label': 'Buscar', oninput: (e) => { filtro = e.target.value.toLowerCase(); desenhar(); } });

  async function carregar() {
    dados = await api('GET', cfg.url);
    if (cfg.resumo) resumoBox.replaceChildren(resumo(cfg.resumo(dados)));
    desenhar();
  }
  function desenhar() {
    const vis = dados.filter((r) => !filtro || Object.values(r).some((v) => String(v ?? '').toLowerCase().includes(filtro)));
    contagem.textContent = textoContagem(vis.length, dados.length, 'registros');
    area.replaceChildren(tabela(cfg.cols, vis, (r) => [
      h('button', { class: 'small', onclick: () => formulario(r) }, 'Editar'), ' ',
      h('button', { class: 'small danger', onclick: () => excluir(r) }, 'Excluir'),
    ]));
  }
  async function excluir(r) {
    if (!confirmar(`Excluir "${r.nome}"?`)) return;
    try { await api('DELETE', `${cfg.url}/${r[cfg.chave]}`); toast('Registro excluído.'); await carregar(); }
    catch (e) { toast(e.message, true); }
  }
  async function formulario(r) {
    const editando = !!r;
    const ctx = cfg.contexto ? await cfg.contexto() : {};
    const inputs = cfg.campos.map((c) => {
      const opcoes = typeof c.opcoes === 'function' ? c.opcoes(ctx, r) : c.opcoes;
      const valor = editando ? (r[c.origem || c.nome] ?? '') : '';
      const input = opcoes
        ? h('select', { id: 'f_' + c.nome }, opcoes.map((o) => h('option', { value: o.v, selected: String(o.v) === String(valor) }, o.t)))
        : h('input', { id: 'f_' + c.nome, type: c.tipo || 'text', value: valor, required: c.obrigatorio !== false, min: c.tipo === 'number' ? 1 : null });
      return h('div', { class: 'field' }, h('label', { for: 'f_' + c.nome }, c.label), input,
        c.ajuda ? h('div', { class: 'help' }, typeof c.ajuda === 'function' ? c.ajuda(r) : c.ajuda) : null);
    });
    async function salvar() {
      const corpo = {};
      for (const c of cfg.campos) {
        const v = document.getElementById('f_' + c.nome).value;
        corpo[c.nome] = c.tipo === 'number' ? (v === '' ? null : Number(v)) : (c.opcoes ? (v === '' ? null : Number(v)) : v);
      }
      if (cfg.antesDeSalvar) cfg.antesDeSalvar(corpo, r);
      try {
        if (editando) await api('PUT', `${cfg.url}/${r[cfg.chave]}`, corpo);
        else await api('POST', cfg.url, corpo);
        $modal.close(); toast(editando ? 'Registro atualizado.' : 'Registro criado.'); await carregar();
      } catch (e) { toast(e.message, true); }
    }
    abrirModal(editando ? `Editar ${cfg.singular}` : `Novo ${cfg.singular}`, inputs,
      [h('button', { onclick: () => $modal.close() }, 'Cancelar'), h('button', { class: 'primary', onclick: salvar }, 'Salvar')]);
  }

  $main.replaceChildren(
    cabecalho(cfg.titulo, cfg.sub, h('button', { class: 'primary', onclick: () => formulario(null) }, `+ Novo ${cfg.singular}`)),
    resumoBox,
    cartaoTabela([busca], contagem, area));
  await carregar();
}

const VIEW_CLIENTES = () => viewCrud({
  titulo: 'Clientes', singular: 'cliente', sub: 'Cadastre, edite e remova os clientes da loja.',
  resumo: (d) => [['Clientes', num(d.length)], ['Bairros atendidos', num(new Set(d.map((c) => c.bairro)).size)]],
  url: '/api/clientes', chave: 'codigo_cliente',
  cols: [{ key: 'codigo_cliente', label: 'Cód.', num: true }, { key: 'nome', label: 'Nome' }, { key: 'email', label: 'E-mail' },
    { key: 'rua', label: 'Rua' }, { key: 'numero', label: 'Nº', num: true }, { key: 'bairro', label: 'Bairro' }],
  campos: [{ nome: 'nome', label: 'Nome' }, { nome: 'email', label: 'E-mail', tipo: 'email' }, { nome: 'rua', label: 'Rua' },
    { nome: 'numero', label: 'Número', tipo: 'number' }, { nome: 'bairro', label: 'Bairro' }],
});

const VIEW_FORNECEDORES = () => viewCrud({
  titulo: 'Fornecedores', singular: 'fornecedor', sub: 'Fornecedores e a quantidade de roupas que cada um abastece.',
  resumo: (d) => [['Fornecedores', num(d.length)], ['Roupas fornecidas', num(d.reduce((s, f) => s + Number(f.qtd_roupas || 0), 0))], ['Sem roupas vinculadas', num(d.filter((f) => !Number(f.qtd_roupas)).length)]],
  url: '/api/fornecedores', chave: 'codigo_fornecedor',
  cols: [{ key: 'codigo_fornecedor', label: 'Cód.', num: true }, { key: 'nome', label: 'Nome' }, { key: 'qtd_roupas', label: 'Roupas fornecidas', num: true }],
  campos: [{ nome: 'nome', label: 'Nome do fornecedor' }],
});

const VIEW_CATEGORIAS = () => viewCrud({
  titulo: 'Categorias', singular: 'categoria',
  sub: 'Árvore de categorias e subcategorias. A categoria pai é gravada junto, na mesma transação.',
  resumo: (d) => [['Categorias', num(d.length)], ['Categorias raiz', num(d.filter((c) => !c.categoria_pai).length)], ['Subcategorias', num(d.filter((c) => c.categoria_pai).length)], ['Roupas classificadas', num(d.reduce((s, c) => s + Number(c.qtd_roupas || 0), 0))]],
  url: '/api/categorias', chave: 'codigo_categoria',
  cols: [{ key: 'codigo_categoria', label: 'Cód.', num: true }, { key: 'nome', label: 'Nome' }, { key: 'descricao', label: 'Descrição' },
    { key: 'categoria_pai', label: 'Categoria pai', render: (r) => r.categoria_pai || '—' }, { key: 'qtd_roupas', label: 'Roupas', num: true }],
  contexto: () => api('GET', '/api/categorias'),
  campos: [
    { nome: 'nome', label: 'Nome' },
    { nome: 'descricao', label: 'Descrição', obrigatorio: false },
    {
      nome: 'codigoPai', label: 'Categoria pai (opcional)', origem: 'codigo_pai',
      opcoes: (todas, r) => [{ v: '', t: '— nenhuma (categoria raiz) —' }]
        .concat(todas.filter((c) => !r || c.codigo_categoria !== r.codigo_categoria).map((c) => ({ v: c.codigo_categoria, t: c.nome }))),
      ajuda: (r) => (r && r.qtd_pais > 1 ? `Esta categoria tem ${r.qtd_pais} pais (${r.categoria_pai}). Só altere o campo se quiser substituí-los.` : ''),
    },
  ],
  antesDeSalvar: (corpo, r) => {
    const inicial = r ? (r.codigo_pai ?? null) : null;
    corpo.alterarPai = !r || corpo.codigoPai !== inicial;
  },
});

// ---------- catálogo (leitura) ----------
async function viewCatalogo() {
  const rows = await api('GET', '/api/roupas');
  let filtro = '';
  let tipo = '';
  const area = h('div');
  const contagem = h('span', { class: 'count' });
  const busca = h('input', { type: 'search', placeholder: 'Buscar roupa, categoria…', oninput: (e) => { filtro = e.target.value.toLowerCase(); desenhar(); } });
  const tipos = [...new Set(rows.map((r) => r.tipo))].sort();
  const selTipo = h('select', { 'aria-label': 'Filtrar por tipo', onchange: (e) => { tipo = e.target.value; desenhar(); } },
    h('option', { value: '' }, 'Todos os tipos'), tipos.map((t) => h('option', { value: t }, t)));
  const vendidas = rows.filter((r) => Number(r.unidades_vendidas) > 0).length;
  const desenhar = () => {
    const vis = rows.filter((r) => (!tipo || r.tipo === tipo) && (!filtro || Object.values(r).some((v) => String(v ?? '').toLowerCase().includes(filtro))));
    contagem.textContent = textoContagem(vis.length, rows.length, 'roupas');
    area.replaceChildren(tabela([
      { key: 'codigo_roupa', label: 'Cód.', num: true }, { key: 'nome', label: 'Roupa' }, { key: 'tipo', label: 'Tipo' },
      { key: 'categoria', label: 'Categoria' }, { key: 'tamanho', label: 'Tam.' }, { key: 'sexo', label: 'Sexo' },
      { key: 'ultimo_preco', label: 'Último preço', num: true, render: (r) => (r.ultimo_preco == null ? '—' : brl(r.ultimo_preco)) },
      { key: 'unidades_vendidas', label: 'Unid. vendidas', num: true, render: (r) => num(r.unidades_vendidas) },
    ], vis));
  };
  $main.replaceChildren(
    cabecalho('Catálogo de roupas', 'Roupas cadastradas, com o tipo (camisa, calça ou casaco) e as unidades vendidas, calculadas por função do banco.'),
    resumo([['Roupas no catálogo', num(rows.length)], ['Com venda', num(vendidas), 'ao menos 1 unidade'], ['Sem venda', num(rows.length - vendidas)],
      ['Unidades vendidas', num(rows.reduce((s, r) => s + Number(r.unidades_vendidas || 0), 0)), 'sem pedidos cancelados']]),
    cartaoTabela([busca, selTipo], contagem, area));
  desenhar();
}

// ---------- pedidos ----------
async function viewPedidos() {
  const area = h('div');
  const resumoBox = h('div');
  const abas = h('div', { class: 'tabs' });
  const contagem = h('span', { class: 'count' });
  let todos = [];
  let aba = '';
  let filtro = '';
  const busca = h('input', { type: 'search', placeholder: 'Buscar cliente ou nº do pedido…', oninput: (e) => { filtro = e.target.value.toLowerCase(); desenhar(); } });

  async function carregar() { todos = await api('GET', '/api/pedidos'); desenhar(); }

  function desenhar() {
    const validos = todos.filter((r) => r.status !== 'Cancelado');
    const fat = validos.reduce((s, r) => s + Number(r.valor_total), 0);
    const andamento = todos.filter((r) => r.status === 'Em separação' || r.status === 'A caminho').length;
    resumoBox.replaceChildren(resumo([['Pedidos', num(todos.length), `${num(validos.length)} não cancelados`], ['Faturamento', brl(fat), 'sem cancelados'],
      ['Ticket médio', brl(validos.length ? fat / validos.length : 0), 'por pedido'], ['Em andamento', num(andamento), 'em separação ou a caminho']]));
    abas.replaceChildren(...['', ...STATUS].map((s) => h('button', { class: 'tab' + (aba === s ? ' active' : ''), onclick: () => { aba = s; desenhar(); } },
      s || 'Todos', h('span', { class: 'tab-n' }, num(s ? todos.filter((r) => r.status === s).length : todos.length)))));
    const vis = todos.filter((r) => (!aba || r.status === aba) && (!filtro || `${r.codigo_pedido} ${r.cliente}`.toLowerCase().includes(filtro)));
    contagem.textContent = textoContagem(vis.length, todos.length, 'pedidos');
    area.replaceChildren(tabela([
      { key: 'codigo_pedido', label: 'Pedido', num: true }, { key: 'cliente', label: 'Cliente' },
      { key: 'data_pedido', label: 'Data', render: (r) => dataBR(r.data_pedido) },
      { key: 'status', label: 'Status', render: (r) => h('span', { class: 'pill status-cell', style: `--dot: var(${STATUS_COR[r.status] || '--ink-3'})` },
        h('select', { 'aria-label': 'Alterar status do pedido ' + r.codigo_pedido, onchange: (e) => mudarStatus(r, e.target.value) },
          STATUS.map((s) => h('option', { value: s, selected: s === r.status }, s)))) },
      { key: 'itens', label: 'Itens', num: true }, { key: 'valor_total', label: 'Valor total', num: true, render: (r) => brl(r.valor_total) },
      { key: 'total_itens_fn', label: 'Conferência', render: (r) => (Number(r.total_itens_fn) === Number(r.valor_total)
        ? h('span', { class: 'diff-ok', title: `fn_total_itens_pedido(${r.codigo_pedido}) = ${brl(r.total_itens_fn)}` }, '✓ confere')
        : h('span', { class: 'diff-bad', title: 'Diferença entre o total gravado e a soma dos itens' }, `≠ ${brl(r.total_itens_fn)}`)) },
    ], vis, (r) => [
      h('button', { class: 'small', onclick: () => verItens(r) }, 'Itens'), ' ',
      h('button', { class: 'small danger', onclick: () => excluir(r) }, 'Excluir'),
    ]));
  }
  async function mudarStatus(r, status) {
    try { await api('PATCH', `/api/pedidos/${r.codigo_pedido}/status`, { status }); toast(`Pedido ${r.codigo_pedido}: ${status}.`); }
    catch (e) { toast(e.message, true); }
    await carregar();
  }
  async function excluir(r) {
    if (!confirmar(`Excluir o pedido ${r.codigo_pedido} e seus itens?`)) return;
    try { await api('DELETE', `/api/pedidos/${r.codigo_pedido}`); toast('Pedido excluído.'); await carregar(); }
    catch (e) { toast(e.message, true); }
  }
  async function verItens(r) {
    const [itens, roupas, total] = await Promise.all([api('GET', `/api/pedidos/${r.codigo_pedido}/itens`), api('GET', '/api/roupas'),
      api('GET', `/api/rotinas/total-pedido/${r.codigo_pedido}`)]);
    const sel = h('select', { id: 'ni_roupa' }, roupas.map((x) => h('option', { value: x.codigo_roupa }, `${x.codigo_roupa} · ${x.nome} (${x.tamanho})`)));
    const qtd = h('input', { id: 'ni_qtd', type: 'number', min: '1', value: '1' });
    const preco = h('input', { id: 'ni_preco', type: 'number', min: '0', step: '0.01', placeholder: 'Preço' });
    async function incluir() {
      try {
        await api('POST', `/api/pedidos/${r.codigo_pedido}/itens`, { codigoRoupa: Number(sel.value), quantidade: Number(qtd.value), precoUnitario: preco.value === '' ? null : Number(preco.value) });
        toast('Item incluído.'); $modal.close(); await carregar(); await verItens(r);
      } catch (e) { toast(e.message, true); }
    }
    abrirModal(`Pedido ${r.codigo_pedido} — ${r.cliente} (${r.status})`, [
      tabela([
        { key: 'roupa', label: 'Roupa' }, { key: 'quantidade', label: 'Qtd', num: true },
        { key: 'preco_unitario', label: 'Preço unit.', num: true, render: (i) => brl(i.preco_unitario) },
        { key: 'subtotal', label: 'Subtotal', num: true, render: (i) => brl(i.subtotal) },
      ], itens),
      h('div', { class: 'note' }, `fn_total_itens_pedido(${r.codigo_pedido}) = ${brl(total.valor)}`),
      h('h2', { style: 'font-size:14px;margin:16px 0 6px' }, 'Incluir item neste pedido'),
      h('div', { style: 'display:grid;grid-template-columns:2fr 80px 110px;gap:8px' }, sel, qtd, preco),
      h('div', { class: 'note' }, 'Se o pedido estiver Entregue ou Cancelado, o trigger trg_item_impede_pedido_cancelado recusa o INSERT e o banco devolve a mensagem.'),
    ], [h('button', { onclick: () => $modal.close() }, 'Fechar'), h('button', { class: 'primary', onclick: incluir }, 'Incluir item')], true);
  }

  async function novoPedido() {
    const [clientes, roupas] = await Promise.all([api('GET', '/api/clientes'), api('GET', '/api/roupas')]);
    const hoje = new Date().toISOString().slice(0, 10);
    const linhas = h('div', { style: 'display:grid;gap:8px' });
    const total = h('div', { class: 'total-line' }, brl(0));

    function recalcular() {
      let t = 0;
      linhas.querySelectorAll('.item-row').forEach((l) => {
        const q = Number(l.querySelector('.q').value) || 0, p = Number(l.querySelector('.p').value) || 0;
        l.querySelector('.sub').textContent = brl(q * p); t += q * p;
      });
      total.textContent = 'Total: ' + brl(t);
    }
    function addLinha() {
      const sel = h('select', { class: 'r', 'aria-label': 'Roupa' },
        h('option', { value: '' }, 'Selecione a roupa…'),
        roupas.map((r) => h('option', { value: r.codigo_roupa }, `${r.codigo_roupa} · ${r.nome} (${r.tamanho})`)));
      const preco = h('input', { class: 'p', type: 'number', min: '0', step: '0.01', placeholder: 'Preço', 'aria-label': 'Preço unitário', oninput: recalcular });
      sel.addEventListener('change', () => {
        const r = roupas.find((x) => String(x.codigo_roupa) === sel.value);
        if (r && r.ultimo_preco != null && !preco.value) preco.value = r.ultimo_preco;
        recalcular();
      });
      const linha = h('div', { class: 'item-row' }, sel,
        h('input', { class: 'q', type: 'number', min: '1', value: '1', 'aria-label': 'Quantidade', oninput: recalcular }), preco,
        h('div', { class: 'sub' }, brl(0)),
        h('button', { class: 'small', 'aria-label': 'Remover item', onclick: () => { linha.remove(); recalcular(); } }, '✕'));
      linhas.append(linha);
    }
    addLinha();

    const cli = h('select', { id: 'p_cliente' }, h('option', { value: '' }, 'Selecione o cliente…'),
      clientes.map((c) => h('option', { value: c.codigo_cliente }, c.nome)));
    const data = h('input', { id: 'p_data', type: 'date', value: hoje });
    const st = h('select', { id: 'p_status' }, STATUS.map((s) => h('option', { value: s }, s)));

    async function salvar() {
      const itens = [...linhas.querySelectorAll('.item-row')].map((l) => ({
        codigoRoupa: l.querySelector('.r').value ? Number(l.querySelector('.r').value) : null,
        quantidade: Number(l.querySelector('.q').value),
        precoUnitario: l.querySelector('.p').value === '' ? null : Number(l.querySelector('.p').value),
      }));
      try {
        const res = await api('POST', '/api/pedidos', { codigoCliente: cli.value ? Number(cli.value) : null, dataPedido: data.value, status: st.value, itens });
        $modal.close(); toast(`Pedido ${res.codigo} criado.`); await carregar();
      } catch (e) { toast(e.message, true); }
    }
    abrirModal('Novo pedido', [
      h('div', { class: 'field' }, h('label', { for: 'p_cliente' }, 'Cliente'), cli),
      h('div', { style: 'display:grid;grid-template-columns:1fr 1fr;gap:12px' },
        h('div', { class: 'field' }, h('label', { for: 'p_data' }, 'Data'), data),
        h('div', { class: 'field' }, h('label', { for: 'p_status' }, 'Status'), st)),
      h('div', { class: 'field' }, h('label', {}, 'Itens do pedido (Roupa · quantidade · preço unitário)'), linhas,
        h('div', {}, h('button', { class: 'small', onclick: addLinha }, '+ Adicionar item'))),
      total,
    ], [h('button', { onclick: () => $modal.close() }, 'Cancelar'), h('button', { class: 'primary', onclick: salvar }, 'Registrar pedido')], true);
  }

  $main.replaceChildren(
    cabecalho('Pedidos', 'Registre pedidos, acompanhe o status e confira o total pela função do banco. Cada mudança de status fica na Auditoria.',
      h('button', { class: 'primary', onclick: novoPedido }, '+ Novo pedido')),
    resumoBox,
    cartaoTabela([abas, busca], contagem, area));
  await carregar();
}

// ---------- consultas ----------
const COR = (n) => cssVar('--s' + n);
const PALETA = () => [1, 2, 3, 4, 5, 6, 7, 8].map(COR);
let qChart = null;

/** Agrupa linhas por uma coluna e soma (ou conta) outra. */
function agrupar(rows, chave, valor) {
  const m = new Map();
  for (const r of rows) m.set(r[chave], (m.get(r[chave]) || 0) + (valor ? Number(r[valor]) || 0 : 1));
  return [...m.entries()];
}
const soma = (rows, col) => rows.reduce((s, r) => s + (Number(r[col]) || 0), 0);
const mini = (label, value, hint) => ({ label, value, hint });

function opcoesEixos(horizontal, moeda) {
  const grid = cssVar('--grid');
  const tick = moeda ? { callback: (v) => brl(v) } : { precision: 0 };
  return {
    x: { grid: { color: horizontal ? grid : 'transparent' }, border: { display: false }, beginAtZero: true, ticks: horizontal ? tick : {} },
    y: { grid: { color: horizontal ? 'transparent' : grid }, border: { display: false }, beginAtZero: true, ticks: horizontal ? {} : tick },
  };
}
function barras(labels, datasets, { horizontal = false, moeda = false, legenda = false } = {}) {
  return { type: 'bar', data: { labels, datasets: datasets.map((d, i) => ({ borderRadius: 4, maxBarThickness: 32, backgroundColor: COR(i === 0 ? 1 : 2), ...d })) },
    options: { indexAxis: horizontal ? 'y' : 'x', maintainAspectRatio: false, scales: opcoesEixos(horizontal, moeda),
      plugins: { legend: { display: legenda || datasets.length > 1, position: 'bottom' }, tooltip: moeda ? { callbacks: { label: (c) => ` ${c.dataset.label}: ${brl(c.parsed[horizontal ? 'x' : 'y'])}` } } : {} } } };
}
function rosca(labels, data, tipo = 'doughnut') {
  return { type: tipo, data: { labels, datasets: [{ data, backgroundColor: PALETA().slice(0, labels.length), borderColor: cssVar('--surface'), borderWidth: 2 }] },
    options: { maintainAspectRatio: false, cutout: tipo === 'doughnut' ? '58%' : undefined, plugins: { legend: { position: 'right', labels: { usePointStyle: true, boxWidth: 8 } } } } };
}

/**
 * Apresentação visual de cada consulta/view: indicadores + gráfico, calculados só com as linhas
 * que o SQL devolveu. ctx = { totalRoupas, totalClientes }.
 */
const VIZ = {
  1: (rows) => {
    const a = agrupar(rows, 'tamanho');
    return { kpis: [mini('Roupas encontradas', num(rows.length)), mini('Categorias distintas', num(new Set(rows.map((r) => r.categoria)).size))],
      chart: rosca(a.map((x) => 'Tamanho ' + x[0]), a.map((x) => x[1])), titulo: 'Roupas por tamanho' };
  },
  2: (rows) => {
    const semCor = rows.filter((r) => String(r.cores).startsWith('(sem')).length;
    const semFor = rows.filter((r) => String(r.fornecedores).startsWith('(sem')).length;
    return { kpis: [mini('Roupas listadas', num(rows.length)), mini('Sem cor cadastrada', num(semCor)), mini('Sem fornecedor', num(semFor))],
      chart: barras(['Com cor', 'Sem cor', 'Com fornecedor', 'Sem fornecedor'], [{ label: 'Roupas', data: [rows.length - semCor, semCor, rows.length - semFor, semFor],
        backgroundColor: [COR(1), COR(8), COR(2), COR(8)] }]), titulo: 'Cobertura de cores e fornecedores' };
  },
  3: (rows) => ({
    kpis: [mini('Pedidos do cliente', num(rows.length)), mini('Total gasto', brl(soma(rows, 'valor_total'))), mini('Unidades compradas', num(soma(rows, 'unidades')))],
    chart: barras(rows.slice().reverse().map((r) => `#${r.codigo_pedido} · ${dataBR(r.data_pedido)}`), [{ label: 'Valor do pedido', data: rows.slice().reverse().map((r) => r.valor_total) }], { moeda: true }),
    titulo: 'Valor de cada pedido (do mais antigo ao mais recente)' }),
  4: (rows) => ({
    kpis: [mini('Roupas no ranking', num(rows.length)), mini('Unidades vendidas', num(soma(rows, 'unidades_vendidas'))), mini('Líder', rows[0] ? rows[0].roupa : '—', rows[0] ? num(rows[0].unidades_vendidas) + ' un.' : '')],
    chart: barras(rows.slice(0, 10).map((r) => r.roupa), [{ label: 'Unidades', data: rows.slice(0, 10).map((r) => r.unidades_vendidas) }], { horizontal: true }),
    titulo: 'Top 10 do ranking' }),
  5: (rows) => {
    const det = rows.filter((r) => r.status !== 'TOTAL GERAL'), tot = rows.find((r) => r.status === 'TOTAL GERAL');
    return { kpis: [mini('Faturamento total', tot ? brl(tot.faturamento) : '—'), mini('Pedidos', tot ? num(tot.pedidos) : '0'), mini('Ticket médio', tot ? brl(tot.ticket_medio) : '—')],
      chart: det.length ? rosca(det.map((r) => r.status), det.map((r) => r.faturamento), 'pie') : null, titulo: 'Faturamento por status' };
  },
  6: (rows, ctx) => {
    const a = agrupar(rows, 'categoria').sort((x, y) => y[1] - x[1]);
    return { kpis: [mini('Roupas nunca vendidas', num(rows.length)), mini('% do catálogo', ctx.totalRoupas ? num(100 * rows.length / ctx.totalRoupas, 1) + '%' : '—', `de ${num(ctx.totalRoupas)} roupas`)],
      chart: barras(a.map((x) => x[0]), [{ label: 'Roupas sem venda', data: a.map((x) => x[1]) }], { horizontal: true }), titulo: 'Roupas sem venda por categoria' };
  },
  7: (rows) => ({
    kpis: [mini('Clientes acima da média', num(rows.length)), mini('Média geral', rows[0] ? brl(rows[0].media_geral) : '—'), mini('Maior gasto', rows[0] ? brl(rows[0].total_gasto) : '—', rows[0] ? rows[0].cliente : '')],
    chart: barras(rows.map((r) => r.cliente), [{ label: 'Total gasto', data: rows.map((r) => r.total_gasto) },
      { type: 'line', label: 'Média geral', data: rows.map((r) => r.media_geral), borderColor: COR(8), backgroundColor: COR(8), borderDash: [6, 4], pointRadius: 0, borderWidth: 2 }], { horizontal: false, moeda: true }),
    titulo: 'Gasto dos clientes acima da média' }),
  8: (rows) => ({
    kpis: [mini('Faturamento (3 tipos)', brl(soma(rows, 'faturamento'))), mini('Unidades', num(soma(rows, 'unidades')))],
    chart: rosca(rows.map((r) => r.tipo), rows.map((r) => r.faturamento), 'pie'), titulo: 'Faturamento por tipo de roupa' }),
  9: (rows, ctx) => ({
    kpis: [mini('Clientes sem pedido', num(rows.length)), mini('% da base', ctx.totalClientes ? num(100 * rows.length / ctx.totalClientes, 1) + '%' : '—', `de ${num(ctx.totalClientes)} clientes`)],
    chart: rosca(['Sem pedido no período', 'Com pedido no período'], [rows.length, Math.max(0, ctx.totalClientes - rows.length)]), titulo: 'Clientes inativos no período' }),
  10: (rows) => {
    const a = agrupar(rows, 'situacao');
    return { kpis: [mini('Roupas conciliadas', num(rows.length)), mini('Fornecedor sem venda', num(rows.filter((r) => r.situacao === 'Fornecedor sem venda ativa').length)),
      mini('Venda sem fornecedor', num(rows.filter((r) => r.situacao === 'Venda ativa sem fornecedor').length))],
      chart: rosca(a.map((x) => x[0]), a.map((x) => x[1])), titulo: 'Situação de cada roupa' };
  },
  11: (rows) => {
    const top = rows.slice().sort((a, b) => b.unidades_vendidas - a.unidades_vendidas).slice(0, 10);
    return { kpis: [mini('Roupas acima da média', num(rows.length)), mini('Unidades (soma)', num(soma(rows, 'unidades_vendidas')))],
      chart: barras(top.map((r) => r.roupa), [{ label: 'Unidades vendidas', data: top.map((r) => r.unidades_vendidas) },
        { label: 'Média da categoria', data: top.map((r) => Number(r.media_unidades_da_categoria)), backgroundColor: COR(3) }], { horizontal: true }),
      titulo: 'Top 10: unidades × média da categoria' };
  },
  12: (rows) => ({
    kpis: [mini('Categorias acima da média', num(rows.length)), mini('Média das categorias', rows[0] ? brl(rows[0].media_faturamento_categorias) : '—'), mini('Maior faturamento', rows[0] ? brl(rows[0].faturamento_ativo) : '—', rows[0] ? rows[0].categoria : '')],
    chart: barras(rows.map((r) => r.categoria), [{ label: 'Faturamento', data: rows.map((r) => r.faturamento_ativo) },
      { type: 'line', label: 'Média', data: rows.map((r) => Number(r.media_faturamento_categorias)), borderColor: COR(8), backgroundColor: COR(8), borderDash: [6, 4], pointRadius: 0, borderWidth: 2 }], { moeda: true }),
    titulo: 'Faturamento × média das categorias' }),
  13: (rows) => {
    const a = agrupar(rows, 'categoria', 'subtotal_item').sort((x, y) => y[1] - x[1]).slice(0, 10);
    return { kpis: [mini('Itens', num(rows.length)), mini('Pedidos distintos', num(new Set(rows.map((r) => r.codigo_pedido)).size)), mini('Soma dos subtotais', brl(soma(rows, 'subtotal_item')))],
      chart: barras(a.map((x) => x[0]), [{ label: 'Subtotal', data: a.map((x) => x[1]) }], { horizontal: true, moeda: true }), titulo: 'Subtotal por categoria (top 10)' };
  },
  14: (rows) => {
    const a = agrupar(rows, 'categoria', 'faturamento_ativo').sort((x, y) => y[1] - x[1]).slice(0, 10);
    return { kpis: [mini('Roupas na visão', num(rows.length)), mini('Faturamento ativo', brl(soma(rows, 'faturamento_ativo'))), mini('Unidades', num(soma(rows, 'unidades_vendidas_ativas')))],
      chart: barras(a.map((x) => x[0]), [{ label: 'Faturamento', data: a.map((x) => x[1]) }], { horizontal: true, moeda: true }), titulo: 'Faturamento ativo por categoria (top 10)' };
  },
};

async function viewConsultas() {
  const [lista, clientes, categorias, roupas] = await Promise.all([api('GET', '/api/consultas'), api('GET', '/api/clientes'), api('GET', '/api/categorias'), api('GET', '/api/roupas')]);
  const ctx = { totalRoupas: roupas.length, totalClientes: clientes.length };
  const painel = h('div', { class: 'card q-panel' });
  const itens = h('div', { class: 'q-list' });
  const botoes = [];

  function selecionar(q) {
    botoes.forEach((b, i) => b.classList.toggle('active', lista[i].id === q.id));
    const campos = q.params.map((p) => {
      let input;
      if (p.tipo === 'categoria' || p.tipo === 'categoria_opc') input = h('select', { name: p.nome },
        p.tipo === 'categoria_opc' ? h('option', { value: '' }, 'Todas') : null, categorias.map((c) => h('option', { value: c.codigo_categoria }, c.nome)));
      else if (p.tipo === 'cliente' || p.tipo === 'cliente_opc') input = h('select', { name: p.nome },
        p.tipo === 'cliente_opc' ? h('option', { value: '' }, 'Todos') : null, clientes.map((c) => h('option', { value: c.codigo_cliente }, c.nome)));
      else if (p.tipo === 'status') input = h('select', { name: p.nome }, h('option', { value: '' }, 'Todos'), STATUS.map((s) => h('option', { value: s }, s)));
      else input = h('input', { name: p.nome, type: p.tipo === 'numero' ? 'number' : p.tipo === 'data' ? 'date' : 'text', value: p.padrao || '', min: p.tipo === 'numero' ? '0' : null });
      return h('div', { class: 'field' }, h('label', {}, p.rotulo), input);
    });
    const resultado = h('div');
    const form = h('form', { class: 'q-params', onsubmit: (e) => { e.preventDefault(); executar(q, form, resultado); } },
      campos, h('button', { class: 'primary', type: 'submit' }, '▶ Executar'));
    if (!q.params.length) form.prepend(h('div', { class: 'q-noparams' }, 'Esta consulta não tem parâmetros.'));
    painel.replaceChildren(
      h('div', { class: 'q-head' }, h('div', { class: 'q-kicker' }, nomeConsulta(q)), h('h2', {}, q.titulo), h('p', { class: 'q-question' }, q.pergunta),
        h('span', { class: 'tag' }, q.tecnica)),
      form, resultado);
    executar(q, form, resultado);
  }

  async function executar(q, form, resultado) {
    const qs = new URLSearchParams(new FormData(form)).toString();
    if (qChart) { qChart.destroy(); qChart = null; }
    try {
      const r = await api('GET', `/api/consultas/${q.id}?${qs}`);
      const cols = r.colunas.map((c) => ({
        key: c, label: c.replaceAll('_', ' '),
        num: r.linhas.length > 0 && typeof r.linhas[0][c] === 'number',
        render: (row) => (typeof row[c] === 'number' ? num(row[c], Number.isInteger(row[c]) ? 0 : 2) : (row[c] ?? '—')),
      }));
      const viz = VIZ[q.id] ? VIZ[q.id](r.linhas, ctx) : null;
      const temGrafico = viz && viz.chart && r.linhas.length;
      const blocoViz = viz && h('div', { class: 'q-result' + (temGrafico ? '' : ' sem-grafico') },
        h('div', { class: 'q-kpis' }, viz.kpis.map((k) => h('div', { class: 'mini-kpi' }, h('div', { class: 'label' }, k.label), h('div', { class: 'value' }, k.value), h('div', { class: 'hint' }, k.hint || ' ')))),
        temGrafico ? h('div', { class: 'q-chart-card' }, h('h3', {}, viz.titulo), h('div', { class: 'q-chart' }, h('canvas', { id: 'q_canvas', role: 'img', 'aria-label': viz.titulo }))) : null);
      resultado.replaceChildren(
        blocoViz,
        h('div', { class: 'q-table' }, h('div', { class: 'q-meta' }, h('b', {}, 'Resultado'), h('span', {}, `${num(r.linhas.length)} linha(s)`)), tabela(cols, r.linhas)),
        h('details', { class: 'q-sql' }, h('summary', {}, 'Ver o SQL executado (via JDBC, com PreparedStatement)'), h('pre', { class: 'sql' }, r.sql)));
      if (viz && viz.chart && r.linhas.length) {
        Chart.defaults.font.family = '"Segoe UI", system-ui, sans-serif';
        Chart.defaults.color = cssVar('--ink-2');
        qChart = new Chart(document.getElementById('q_canvas'), viz.chart);
      }
    } catch (e) { resultado.replaceChildren(h('div', { class: 'empty' }, e.message)); toast(e.message, true); }
  }

  const nomeConsulta = (q) => (q.id <= 8 ? `Consulta ${q.id} · Etapa 3` : q.id <= 12 ? `Consulta ${q.id} · Etapa 4` : `Visão ${q.id - 12} · Etapa 4`);
  const grupos = [['Etapa 3 · Consultas', (q) => q.id <= 8], ['Etapa 4 · Consultas', (q) => q.id > 8 && q.id <= 12], ['Etapa 4 · Visões', (q) => q.id > 12]];
  for (const [titulo, pertence] of grupos) {
    itens.append(h('div', { class: 'q-group' }, titulo));
    for (const q of lista.filter(pertence)) {
      const b = h('button', { class: 'q-item', onclick: () => selecionar(q) }, h('span', { class: 'n' }, q.id <= 12 ? q.id : q.id - 12), h('span', { class: 't' }, q.titulo.replace(/^Visao: /, '')));
      botoes[lista.indexOf(q)] = b;
      itens.append(b);
    }
  }
  $main.replaceChildren(
    cabecalho('Consultas e visões', `${lista.length} consultas e visões das Etapas 3 e 4. Escolha uma na lista, ajuste os filtros e execute: o resultado vem com indicadores, gráfico e tabela.`),
    h('div', { class: 'q-layout' }, h('div', { class: 'card q-nav' }, itens), painel));
  selecionar(lista[0]);
}

// ---------- dashboard ----------
let charts = [];
let dashFiltro = { inicio: '', fim: '', categoria: '', status: '' };

async function viewDashboard() {
  const categorias = await api('GET', '/api/categorias');
  const conteudo = h('div');
  const campo = (rotulo, input) => h('div', { class: 'field' }, h('label', {}, rotulo), input);
  const aplicar = () => carregar();
  const inicio = h('input', { type: 'date', value: dashFiltro.inicio, onchange: (e) => { dashFiltro.inicio = e.target.value; aplicar(); } });
  const fim = h('input', { type: 'date', value: dashFiltro.fim, onchange: (e) => { dashFiltro.fim = e.target.value; aplicar(); } });
  const cat = h('select', { onchange: (e) => { dashFiltro.categoria = e.target.value; aplicar(); } },
    h('option', { value: '' }, 'Todas'),
    categorias.map((c) => h('option', { value: c.codigo_categoria, selected: String(c.codigo_categoria) === dashFiltro.categoria }, c.nome)));
  const st = h('select', { onchange: (e) => { dashFiltro.status = e.target.value; aplicar(); } },
    h('option', { value: '' }, 'Todos (sem cancelados)'),
    STATUS.map((s) => h('option', { value: s, selected: s === dashFiltro.status }, s)));
  const limpar = h('button', { onclick: () => { dashFiltro = { inicio: '', fim: '', categoria: '', status: '' };
    inicio.value = ''; fim.value = ''; cat.value = ''; st.value = ''; carregar(); } }, 'Limpar filtros');

  $main.replaceChildren(
    h('div', { class: 'dash-top' },
      h('div', {}, h('h1', {}, 'Visão geral das vendas'),
        h('div', { class: 'sub' }, 'Estatística descritiva dos dados do banco. Os filtros recalculam tudo por SQL.')),
      h('div', { class: 'dash-filters' }, campo('De', inicio), campo('Até', fim), campo('Categoria', cat), campo('Status', st), limpar)),
    conteudo);

  async function carregar() {
    const qs = new URLSearchParams(Object.fromEntries(Object.entries(dashFiltro).filter(([, v]) => v))).toString();
    try {
      const d = await api('GET', '/api/dashboard' + (qs ? '?' + qs : ''));
      desenharPainel(conteudo, d);
    } catch (e) { conteudo.replaceChildren(h('div', { class: 'card empty' }, e.message)); toast(e.message, true); }
  }
  await carregar();
}

/** Regressão linear simples y = a + b·x: devolve a inclinação (tendência) e r de Pearson. */
function regressao(xs, ys) {
  const n = xs.length;
  if (n < 2) return { b: null, r: null, a: null };
  const mx = xs.reduce((s, v) => s + v, 0) / n, my = ys.reduce((s, v) => s + v, 0) / n;
  let sxy = 0, sxx = 0, syy = 0;
  for (let i = 0; i < n; i++) { sxy += (xs[i] - mx) * (ys[i] - my); sxx += (xs[i] - mx) ** 2; syy += (ys[i] - my) ** 2; }
  if (sxx === 0) return { b: null, r: null, a: null };
  return { b: sxy / sxx, a: my - (sxy / sxx) * mx, r: syy === 0 ? null : sxy / Math.sqrt(sxx * syy) };
}

const mesCurto = (ym) => { const [a, m] = ym.split('-'); return `${m}/${a.slice(2)}`; };

function desenharPainel(conteudo, d) {
  const k = d.kpis;
  const meses = d.faturamentoMes;
  const reg = regressao(meses.map((_, i) => i), meses.map((m) => m.faturamento));
  const corr = regressao(d.dispersao.map((p) => p.preco), d.dispersao.map((p) => p.unidades));
  let variacao = null;
  if (meses.length >= 2 && meses[meses.length - 2].faturamento > 0) {
    variacao = 100 * (meses[meses.length - 1].faturamento - meses[meses.length - 2].faturamento) / meses[meses.length - 2].faturamento;
  }
  const pctCancel = k.pedidos ? 100 * k.cancelados / k.pedidos : 0;
  const cv = k.media > 0 ? 100 * k.desvio_padrao / k.media : 0;
  const nb = (s) => String(s).replace('-', '\u2011');
  const sinal = (v) => (v == null ? '—' : nb((v > 0 ? '+' : '') + num(v, 1) + '%'));
  const forcaCorr = (r) => (r == null ? 'sem dados' : Math.abs(r) < 0.3 ? 'fraca' : Math.abs(r) < 0.7 ? 'moderada' : 'forte');

  if (!k.pedidos) {
    charts.forEach((c) => c.destroy()); charts = [];
    conteudo.replaceChildren(h('div', { class: 'card empty' }, 'Nenhum pedido atende aos filtros escolhidos.'));
    return;
  }

  /** Cartão de indicador: valor grande, minigráfico opcional e duas métricas de apoio (como PY / YoY). */
  const kpi = (label, valor, apoio, spark) => h('div', { class: 'card kpi2' },
    h('div', { class: 'kpi2-top' }, h('div', {}, h('div', { class: 'label' }, label), h('div', { class: 'value' }, valor)),
      spark ? h('div', { class: 'spark' }, h('canvas', { id: spark, 'aria-hidden': 'true' })) : null),
    h('div', { class: 'kpi2-sub' }, apoio.map(([l, v]) => h('div', {}, h('span', {}, l), h('b', {}, v)))));
  const box = (titulo, desc, id, extra) => h('div', { class: 'card chart-card ' + (extra || '') }, h('div', { class: 'card-head' }, h('h2', {}, titulo), h('div', { class: 'desc' }, desc)),
    h('div', { class: 'chart-box' }, h('canvas', { id, role: 'img', 'aria-label': titulo })));
  const medida = (l, v, dica) => h('div', { class: 'medida', title: dica || '' }, h('span', {}, l), h('b', {}, v));

  conteudo.replaceChildren(
    h('div', { class: 'dash-kpis' },
      kpi('Pedidos', num(k.pedidos), [['Válidos', num(k.pedidos_validos)], ['Cancelados', `${num(k.cancelados)} (${num(pctCancel, 1)}%)`]], 'sp_ped'),
      kpi('Faturamento', brl(k.faturamento), [['Unidades', num(k.unidades)], ['Clientes', `${num(k.clientes_ativos)} de ${num(k.clientes)}`]], 'sp_fat'),
      kpi('Ticket médio', brl(k.media), [['Mediana', brl(k.mediana)], ['Desvio-padrão', brl(k.desvio_padrao)]], 'sp_tkt'),
      kpi('Variação mensal', sinal(variacao), [['Período', meses.length >= 2 ? `${mesCurto(meses[meses.length - 2].mes)} → ${mesCurto(meses[meses.length - 1].mes)}` : '—'],
        ['Tendência', reg.b == null ? '—' : nb((reg.b >= 0 ? '+' : '') + brl(reg.b) + '/mês')]]),
      kpi('Correlação preço × un.', corr.r == null ? '—' : num(corr.r, 2), [['Força', forcaCorr(corr.r)], ['Roupas · forn.', `${num(k.roupas)} · ${num(k.fornecedores)}`]])),
    h('div', { class: 'dash-grid' },
      box('Faturamento por mês', 'Série temporal com linha de tendência (regressão linear)', 'c_mes', 'span2'),
      box('Pedidos por status', 'Distribuição de frequência', 'c_status'),
      box('10 roupas mais vendidas', 'Unidades vendidas', 'c_top'),
      box('Unidades por categoria', 'Roupa → Categoria', 'c_cat'),
      box('Faturamento por tipo', 'Camisa, calça e casaco', 'c_tipo'),
      h('div', { class: 'card chart-card' }, h('div', { class: 'card-head' }, h('h2', {}, 'Estatística descritiva'), h('div', { class: 'desc' }, 'Valor dos pedidos que contam (R$)')),
        h('div', { class: 'medidas' },
          medida('Média', brl(k.media)), medida('Mediana', brl(k.mediana)),
          medida('Moda', k.moda_valor == null ? 'sem moda' : brl(k.moda_valor), 'Valor de pedido mais frequente (só existe se algum valor se repete)'),
          medida('Qtd. comum', k.moda_qtd == null ? '—' : num(k.moda_qtd) + ' un.', 'Quantidade mais frequente por item de pedido'),
          medida('Variância', num(k.variancia, 2) + ' R$²', 'Populacional'), medida('Desvio-padrão', brl(k.desvio_padrao)),
          medida('Coef. de variação', num(cv, 1) + '%'), medida('Amplitude', brl(k.maximo - k.minimo)),
          medida('Mínimo', brl(k.minimo)), medida('Máximo', brl(k.maximo)))),
      box('Distribuição do preço unitário', 'Histograma, faixas de R$ 25', 'c_hist'),
      box('Pedidos por dia da semana', 'Radar de frequência', 'c_dia'),
      box('Preço médio × unidades vendidas', `Cada ponto é uma roupa · r = ${corr.r == null ? '—' : num(corr.r, 2)} (${forcaCorr(corr.r)})`, 'c_disp', 'span2'),
      box('Unidades por sexo e tamanho', 'Distribuição cruzada', 'c_tam')));
  desenharGraficos(d, reg);
  desenharSparklines(d);
}

/** Minigráficos dos cartões (sem eixos): pedidos, faturamento e ticket médio por mês. */
function desenharSparklines(d) {
  const ink = cssVar('--s1');
  const cfg = (dados) => ({ type: 'line',
    data: { labels: d.faturamentoMes.map((r) => r.mes), datasets: [{ data: dados, borderColor: ink, backgroundColor: 'rgba(91, 134, 214, .22)', fill: true, borderWidth: 1.8, pointRadius: 0, tension: 0.3 }] },
    options: { maintainAspectRatio: false, animation: false, events: [], plugins: { legend: { display: false }, tooltip: { enabled: false } },
      scales: { x: { display: false }, y: { display: false } } } });
  const m = d.faturamentoMes;
  [['sp_ped', m.map((r) => r.pedidos)], ['sp_fat', m.map((r) => r.faturamento)], ['sp_tkt', m.map((r) => (r.pedidos ? r.faturamento / r.pedidos : 0))]]
    .forEach(([id, dados]) => { const el = document.getElementById(id); if (el && dados.length > 1) charts.push(new Chart(el, cfg(dados))); });
}

function desenharGraficos(d, reg) {
  charts.forEach((c) => c.destroy());
  charts = [];
  const ink2 = cssVar('--ink-2'), grid = cssVar('--grid'), surface = cssVar('--surface');
  Chart.defaults.font.family = '"Segoe UI", system-ui, sans-serif';
  Chart.defaults.color = ink2;
  const eixos = (horizontal) => ({
    x: { grid: { color: horizontal ? grid : 'transparent' }, border: { display: false }, beginAtZero: true, ticks: { precision: 0 } },
    y: { grid: { color: horizontal ? 'transparent' : grid }, border: { display: false }, beginAtZero: true, ticks: { precision: 0 } },
  });
  const mk = (id, cfg) => { charts.push(new Chart(document.getElementById(id), cfg)); };
  const s1 = cssVar('--s1');
  const bar = { borderRadius: 4, borderSkipped: 'start', maxBarThickness: 28 };

  mk('c_status', {
    type: 'pie',
    data: { labels: d.porStatus.map((r) => r.status),
      datasets: [{ data: d.porStatus.map((r) => r.pedidos), backgroundColor: d.porStatus.map((r) => cssVar(STATUS_COR[r.status])), borderColor: surface, borderWidth: 2 }] },
    options: { maintainAspectRatio: false, plugins: { legend: { position: 'right', labels: { usePointStyle: true, boxWidth: 8 } } } },
  });

  const rotulosMes = d.faturamentoMes.map((r) => { const [a, m] = r.mes.split('-'); return `${m}/${a}`; });
  const degrade = (ctx) => {
    const { ctx: g, chartArea } = ctx.chart;
    if (!chartArea) return null;
    const grad = g.createLinearGradient(0, chartArea.top, 0, chartArea.bottom);
    grad.addColorStop(0, 'rgba(91, 134, 214, .38)');
    grad.addColorStop(1, 'rgba(91, 134, 214, 0)');
    return grad;
  };
  const datasetsMes = [{ label: 'Faturamento', data: d.faturamentoMes.map((r) => r.faturamento), borderColor: s1, backgroundColor: degrade, fill: true, borderWidth: 2.5, pointRadius: 4, pointBackgroundColor: s1, pointBorderColor: surface, pointBorderWidth: 2, tension: 0.25 }];
  if (reg.b != null) datasetsMes.push({ label: 'Tendência', data: d.faturamentoMes.map((_, i) => reg.a + reg.b * i), borderColor: cssVar('--s8'), borderDash: [6, 4], borderWidth: 2, pointRadius: 0 });
  mk('c_mes', {
    type: 'line',
    data: { labels: rotulosMes, datasets: datasetsMes },
    options: { maintainAspectRatio: false, scales: { x: eixos(false).x, y: { ...eixos(false).y, ticks: { callback: (v) => brl(v) } } },
      plugins: { legend: { display: datasetsMes.length > 1, position: 'bottom' }, tooltip: { callbacks: { label: (c) => c.datasetIndex === 0
        ? ` ${brl(c.parsed.y)} · ${d.faturamentoMes[c.dataIndex].pedidos} pedido(s)` : ` Tendência: ${brl(c.parsed.y)}` } } } },
  });

  mk('c_top', {
    type: 'bar',
    data: { labels: d.topRoupas.map((r) => r.roupa), datasets: [{ label: 'Unidades', data: d.topRoupas.map((r) => r.unidades), backgroundColor: s1, ...bar }] },
    options: { indexAxis: 'y', maintainAspectRatio: false, scales: eixos(true), plugins: { legend: { display: false } } },
  });

  mk('c_cat', {
    type: 'bar',
    data: { labels: d.porCategoria.map((r) => r.categoria), datasets: [{ label: 'Unidades', data: d.porCategoria.map((r) => r.unidades), backgroundColor: s1, ...bar }] },
    options: { indexAxis: 'y', maintainAspectRatio: false, scales: eixos(true),
      plugins: { legend: { display: false }, tooltip: { callbacks: { afterLabel: (c) => `Faturamento: ${brl(d.porCategoria[c.dataIndex].faturamento)}` } } } },
  });

  const sexos = [...new Set(d.tamanhoSexo.map((r) => r.sexo))];
  const cores = [cssVar('--s1'), cssVar('--s2'), cssVar('--s3')];
  mk('c_tam', {
    type: 'bar',
    data: { labels: sexos, datasets: ['P', 'M', 'G'].map((t, i) => ({
      label: 'Tamanho ' + t, backgroundColor: cores[i], borderColor: surface, borderWidth: 2, borderRadius: 4, maxBarThickness: 64,
      data: sexos.map((s) => (d.tamanhoSexo.find((r) => r.sexo === s && r.tamanho === t) || { unidades: 0 }).unidades) })) },
    options: { maintainAspectRatio: false, scales: { x: { ...eixos(false).x, stacked: true }, y: { ...eixos(false).y, stacked: true } },
      plugins: { legend: { position: 'bottom', labels: { usePointStyle: true, boxWidth: 8 } } } },
  });

  mk('c_hist', {
    type: 'bar',
    data: { labels: d.histograma.map((r) => `R$ ${r.faixa_inicio}–${r.faixa_inicio + 24}`), datasets: [{ label: 'Itens', data: d.histograma.map((r) => r.itens), backgroundColor: s1, ...bar, borderSkipped: 'bottom' }] },
    options: { maintainAspectRatio: false, categoryPercentage: 1, barPercentage: 0.92, scales: eixos(false), plugins: { legend: { display: false } } },
  });

  mk('c_tipo', {
    type: 'doughnut',
    data: { labels: d.porTipo.map((r) => r.tipo), datasets: [{ data: d.porTipo.map((r) => r.faturamento), backgroundColor: [cssVar('--s1'), cssVar('--s2'), cssVar('--s3'), cssVar('--s8')], borderColor: surface, borderWidth: 2 }] },
    options: { maintainAspectRatio: false, cutout: '58%', plugins: { legend: { position: 'right', labels: { usePointStyle: true, boxWidth: 8 } },
      tooltip: { callbacks: { label: (c) => ` ${c.label}: ${brl(c.parsed)} · ${num(d.porTipo[c.dataIndex].unidades)} un.` } } } },
  });

  const dias = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
  mk('c_dia', {
    type: 'radar',
    data: { labels: dias, datasets: [{ label: 'Pedidos', data: dias.map((_, i) => (d.diaSemana.find((r) => r.dia === i + 1) || { pedidos: 0 }).pedidos),
      borderColor: s1, backgroundColor: s1 + '33', borderWidth: 2, pointBackgroundColor: s1 }] },
    options: { maintainAspectRatio: false, scales: { r: { beginAtZero: true, ticks: { precision: 0, backdropColor: 'transparent' }, grid: { color: grid }, angleLines: { color: grid } } },
      plugins: { legend: { display: false } } },
  });

  mk('c_disp', {
    type: 'scatter',
    data: { datasets: [{ label: 'Roupas', data: d.dispersao.map((p) => ({ x: p.preco, y: p.unidades, nome: p.roupa })), backgroundColor: s1, pointRadius: 5, pointHoverRadius: 7 }] },
    options: { maintainAspectRatio: false,
      scales: { x: { title: { display: true, text: 'Preço médio praticado (R$)' }, grid: { color: grid }, ticks: { callback: (v) => brl(v) } },
                y: { title: { display: true, text: 'Unidades vendidas' }, grid: { color: grid }, beginAtZero: true, ticks: { precision: 0 } } },
      plugins: { legend: { display: false }, tooltip: { callbacks: { label: (c) => ` ${c.raw.nome}: ${brl(c.raw.x)} · ${num(c.raw.y)} un.` } } } },
  });
}

// ---------- funções e procedimentos (Etapa 5) ----------
async function viewRotinas() {
  const [pedidos, roupas] = await Promise.all([api('GET', '/api/pedidos'), api('GET', '/api/roupas')]);
  const optPedido = () => pedidos.map((p) => h('option', { value: p.codigo_pedido }, `#${p.codigo_pedido} · ${p.cliente} · ${p.status}`));
  const optRoupa = () => roupas.map((r) => h('option', { value: r.codigo_roupa }, `${r.codigo_roupa} · ${r.nome} (${r.tamanho})`));

  function cartao(titulo, desc, sql, selects, rotuloBtn, chamar, mostrar) {
    const saida = h('div');
    const form = h('form', { onsubmit: async (e) => {
      e.preventDefault();
      try { mostrar(saida, await chamar(form)); } catch (err) { saida.replaceChildren(h('div', { class: 'result-box warn' }, err.message)); }
    } }, selects, h('button', { class: 'primary', type: 'submit' }, rotuloBtn));
    return h('div', { class: 'card rotina' }, h('div', { class: 'card-head' }, h('h2', {}, titulo), h('div', { class: 'desc' }, desc)),
      form, saida, h('pre', { class: 'sql' }, sql));
  }
  const campo = (rotulo, el) => h('div', { class: 'field' }, h('label', {}, rotulo), el);
  const selPedido = () => h('select', { name: 'pedido' }, optPedido());
  const chamada = (r, corpo) => h('div', { class: 'result-box' }, h('code', {}, r.chamada), corpo);

  $main.replaceChildren(
    cabecalho('Funções e procedimentos', 'Rotinas armazenadas da Etapa 5, executadas direto no banco. Escolha os valores e veja o resultado e o comando SQL.'),
    h('div', { class: 'rotinas' },
      cartao('fn_total_itens_pedido', 'Soma quantidade × preço dos itens de um pedido. Retorna NULL se o pedido não existe.',
        'SELECT fn_total_itens_pedido(?)', [campo('Pedido', selPedido())], 'Executar função',
        (f) => api('GET', `/api/rotinas/total-pedido/${f.pedido.value}`),
        (el, r) => el.replaceChildren(chamada(r, h('div', { class: 'big' }, brl(r.valor))))),
      cartao('fn_unidades_vendidas_ativas', 'Unidades vendidas de uma roupa, ignorando pedidos cancelados.',
        'SELECT fn_unidades_vendidas_ativas(?)', [campo('Roupa', h('select', { name: 'roupa' }, optRoupa()))], 'Executar função',
        (f) => api('GET', `/api/rotinas/unidades-roupa/${f.roupa.value}`),
        (el, r) => el.replaceChildren(chamada(r, h('div', { class: 'big' }, num(r.valor) + ' unidade(s)')))),
      cartao('sp_planejar_caixas', 'Procedimento com cursor e laço: distribui os itens do pedido em caixas com capacidade fixa de unidades.',
        'CALL sp_planejar_caixas(?, ?)', [campo('Pedido', selPedido()),
          campo('Capacidade da caixa (unidades)', h('input', { name: 'capacidade', type: 'number', min: '1', value: '3' }))], 'Planejar caixas',
        (f) => api('GET', `/api/rotinas/caixas?pedido=${f.pedido.value}&capacidade=${f.capacidade.value}`),
        (el, r) => el.replaceChildren(chamada(r, h('div', {}, h('div', { class: 'big' }, `${r.caixas} caixa(s)`), h('div', { class: 'note' }, `${num(r.unidades)} unidade(s) distribuídas`))),
          tabela([{ key: 'numero_caixa', label: 'Caixa', num: true }, { key: 'codigo_item', label: 'Item', num: true }, { key: 'roupa', label: 'Roupa' },
            { key: 'quantidade', label: 'Qtd', num: true }], r.linhas))),
      h('div', { class: 'card rotina rotina-larga' }, h('div', { class: 'card-head' }, h('h2', {}, 'sp_atualizar_status_pedido e os triggers'), h('div', { class: 'desc' }, 'Estas rotinas atuam na tela Pedidos:')),
        h('ul', { class: 'lista-info' },
          h('li', {}, 'Alterar o status de um pedido chama a procedure, que recusa status inválido e a mudança de pedido Entregue/Cancelado.'),
          h('li', {}, 'O trigger trg_pedido_log_status grava cada mudança em LogStatusPedido (veja em Auditoria).'),
          h('li', {}, 'Em Pedidos → Itens, incluir um item num pedido Entregue/Cancelado é bloqueado pelo trigger trg_item_impede_pedido_cancelado.')),
        h('div', { style: 'margin-top:12px' }, h('a', { href: '#pedidos' }, 'Ir para Pedidos →')))));
}

// ---------- auditoria (trigger trg_pedido_log_status) ----------
async function viewAuditoria() {
  const rows = await api('GET', '/api/auditoria');
  const porNovo = agrupar(rows, 'status_novo').sort((x, y) => y[1] - x[1]);
  const contagem = h('span', { class: 'count' }, textoContagem(rows.length, rows.length, 'mudanças'));
  $main.replaceChildren(
    cabecalho('Auditoria de status', 'Histórico de mudanças de status dos pedidos, gravado automaticamente pelo trigger a cada alteração.',
      h('button', { onclick: () => rotear() }, '↻ Atualizar')),
    resumo([['Mudanças registradas', num(rows.length), 'as 300 mais recentes'], ...porNovo.slice(0, 3).map(([s, n]) => ['Passaram para ' + s, num(n)])]),
    cartaoTabela([], contagem, tabela([
      { key: 'codigo_log', label: 'Log', num: true }, { key: 'codigo_pedido', label: 'Pedido', num: true }, { key: 'cliente', label: 'Cliente', render: (r) => r.cliente || '—' },
      { key: 'status_anterior', label: 'De', render: (r) => statusPill(r.status_anterior) }, { key: 'status_novo', label: 'Para', render: (r) => statusPill(r.status_novo) },
      { key: 'data_alteracao', label: 'Quando', render: (r) => r.data_alteracao.replace('T', ' ') }, { key: 'usuario_banco', label: 'Usuário do banco' },
    ], rows)));
}
function kpiSimples(label, valor, hint) {
  return h('div', { class: 'card kpi' }, h('div', { class: 'label' }, label), h('div', { class: 'value' }, valor), h('div', { class: 'hint' }, hint || ' '));
}

// ---------- roteador ----------
const VIEWS = {
  dashboard: viewDashboard, consultas: viewConsultas, clientes: VIEW_CLIENTES, fornecedores: VIEW_FORNECEDORES,
  categorias: VIEW_CATEGORIAS, pedidos: viewPedidos, catalogo: viewCatalogo, rotinas: viewRotinas, auditoria: viewAuditoria,
};

async function rotear() {
  const nome = (location.hash || '#dashboard').slice(1);
  const view = VIEWS[nome] || viewDashboard;
  document.querySelectorAll('#nav a').forEach((a) => a.classList.toggle('active', a.dataset.view === (VIEWS[nome] ? nome : 'dashboard')));
  try { await view(); }
  catch (e) { $main.replaceChildren(h('div', { class: 'card empty' }, 'Não foi possível carregar: ' + e.message)); toast(e.message, true); }
}
window.addEventListener('hashchange', rotear);
rotear();
