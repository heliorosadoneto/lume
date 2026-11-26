# Histórico de mudanças

## 1.4.0 — 26 de novembro de 2026

- **Virar página de verdade.** O modo “Virar página” não passava de uma rolagem com duas faixas invisíveis nas bordas: não deslizava, cortava linhas no meio e não mostrava em que página você estava. Agora o livro é dividido em páginas do tamanho da tela (o texto é medido com a mesma fonte, tamanho e largura usados para desenhar), sem cortar linha e sem deixar uma linha sozinha no começo ou no fim da página. Toque no terço direito da tela avança, no esquerdo volta, e deslizar para o lado também vira a página. A barra de baixo mostra “Página x de y”. A posição (inclusive o ponto exato dentro de um parágrafo longo) é salva e volta ao reabrir; mudar a fonte, o tamanho, a largura ou o tema refaz as páginas no mesmo trecho. Vale para EPUB, TXT, Markdown e o modo texto do PDF.
- **Texto na largura toda.** O padrão passou a usar a tela inteira, com só 10 dp de margem em cada lado. Em Ajustes (e no painel Aparência do leitor) a “Largura do texto” vai de 70% a 100%, vale na hora, em rolagem e em páginas, e fica salva. Substitui as margens estreita/média/larga.
- **Tela cheia ao ler.** Com a opção “Tela cheia ao ler” (ligada por padrão, em Ajustes e em Aparência), o leitor esconde as barras de status e de navegação do Android e os botões. Um toque curto no centro da tela mostra e esconde os botões (por cima, sem mexer no texto); no modo página, as laterais continuam virando a página. Ao sair do leitor as barras do Android voltam. Também vale para o PDF em página original. Uma dica aparece na primeira vez.
- **Cores do aplicativo.** Em Ajustes → Cores do aplicativo: **Normal** (papel creme e terracota), **P&B claro** e **P&B escuro**. Toda a interface e as páginas do leitor (branco, sépia, verde e preto viram tons de cinza) mudam na hora e a escolha fica salva.
- Um toque simples no texto não deixa mais a alça do cursor na tela.
- Testes novos: divisão em páginas (sem Flutter e com livros de verdade, checando que o que foi medido cabe na página desenhada), toque e deslize, largura, tela cheia (texto e PDF, barras do Android) e cores.

## 1.3.0 — 13 de novembro de 2026

- Pasta do Lume criada na primeira abertura: Documentos/Lume ou, se o Android não deixar, Android/data/com.helio.lume/files/Livros (com explicação e botão “Usar Documentos/Lume”). Caminho em Ajustes e no topo da biblioteca. Livros importados antes são movidos para ela.
- Botão “Importar” (e “+ → Importar livros”): escolhe vários EPUB, PDF ou TXT de uma vez e copia para a pasta do Lume, com progresso e resumo. Nome repetido vira “nome (2)”; arquivo idêntico (mesmo hash) é pulado.
- A pasta do Lume é relida ao abrir e ao voltar para o app (com subpastas), então arquivos colocados pelo gerenciador de arquivos aparecem.
- Várias pastas: Ajustes → Pastas mostra a pasta do Lume (fixa) e quantas outras pastas você quiser, cada uma com caminho e número de livros. Adicionar pelo seletor de pastas, Remover só tira os livros da biblioteca (os arquivos ficam). A pasta escolhida na versão anterior entra na lista. Todas são lidas com subpastas, com o nome da pasta/subpasta em cada livro e sem repetidos entre pastas. Aviso na tela sobre o “Acesso a todos os arquivos” e as pastas que o seletor bloqueia no Android 11+ (Android/data, raiz de Downloads).
- Apagar livros: toque longo entra no modo de seleção (marcas, contagem, selecionar todos, cancelar) e cada livro tem o menu ⋮ com Apagar…. O diálogo oferece “Tirar só da biblioteca” (o arquivo fica, não volta ao reler as pastas, Desfazer no aviso e Ajustes → Livros ocultos) ou “Apagar o arquivo também” (apaga do celular e limpa posição, destaques, notas, marcadores, capa e cache de texto do PDF; se o Android não deixar, explica na tela).
- TXT: abre no leitor de texto, com UTF-8, UTF-16 (BOM) e Latin-1/Windows-1252 reconhecidos sozinhos, parágrafos, capítulos no sumário e sem o cabeçalho do Project Gutenberg. Filtro TXT na biblioteca.
- Markdown (.md e .markdown): no Importar, nas pastas e no filtro MD; título do cabeçalho YAML, do primeiro # ou do nome do arquivo. Abre formatado no leitor de texto (títulos e sumário, negrito, itálico, listas, tarefas, citações, código em fonte monoespaçada, tabelas, linhas, imagens locais com aviso se faltarem), com destaques, notas e posição salva. Links internos saltam; externos abrem depois de confirmar.
- Ícone novo (lua de páginas com vaga-lume, fundo terracota): ícone adaptativo, redondo, monocromático (Android 13), splash e tela Sobre em Ajustes.

## 1.2.0 — 13 de novembro de 2026

- Modo texto para PDF com texto selecionável: o texto é refeito em parágrafos (linhas juntas, hifenização desfeita, sem cabeçalhos, rodapés e números de página, capítulos reconhecidos) e lido no mesmo leitor dos EPUBs, com fonte, tamanho, espaçamento, margens, temas, destaques e notas. É o padrão para esses PDFs.
- Troca entre “Modo texto” e “Página original” no painel de aparência, com a posição sincronizada entre os dois.
- Extração fora da tela, com progresso, guardada em cache. PDF escaneado abre na página original com um aviso.
- Página original: as margens brancas são cortadas e o texto ocupa a largura da tela (opção “Cortar margens brancas”); zoom com pinça continua.

## 1.1.0 — 12 de novembro de 2026 (APK de teste)

- Leitor de PDF (pdfrx/PDFium, offline): página fiel ao original, rolagem contínua ou página a página, zoom com pinça e toque duplo, barra de páginas, “Ir para a página”, sumário do PDF, marcadores e posição salva.
- Temas sépia, verde claro e preto também no PDF (preto inverte a página), com a opção “Cores originais da página”.
- PDFs na biblioteca, com capa gerada da primeira página, título e autor dos metadados (ou do nome do arquivo), número de páginas e progresso.
- Escolher pasta: procura PDFs e EPUBs na pasta e em todas as subpastas, com progresso e resumo, ignora repetidos (mesmo conteúdo com outro nome) e lembra a pasta. Novo “Atualizar pasta”.
- Explicação antes de pedir “Acesso a todos os arquivos” no Android 11+.
- Filtro Todos · PDF · EPUB e subpasta de cada livro na lista.

## 1.0.0 — 11 de novembro de 2026

Primeira versão pública do Lume:

- Biblioteca em lista, com capa, título, autor e prateleira “Continuar leitura”.
- Pasta de livros nas configurações, com atualização automática.
- Leitor EPUB offline, com retomada da posição.
- Marca-texto em amarelo, laranja, rosa e azul, com notas.
- Caderno de destaques e marcadores.
- Temas branco, sépia, verde claro e preto, e ajustes de tipografia.
- Sumário e barra de progresso.
- APK de release em `releases/Lume.apk`.
