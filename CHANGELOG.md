# Histórico de mudanças

## Próxima versão — 1.3.0, em aprovação (ainda sem APK)

- Pasta do Lume criada na primeira abertura: Documentos/Lume ou, se o Android não deixar, Android/data/com.helio.lume/files/Livros (com explicação e botão “Usar Documentos/Lume”). Caminho em Ajustes e no topo da biblioteca. Livros importados antes são movidos para ela.
- Botão “Importar” (e “+ → Importar livros”): escolhe vários EPUB, PDF ou TXT de uma vez e copia para a pasta do Lume, com progresso e resumo. Nome repetido vira “nome (2)”; arquivo idêntico (mesmo hash) é pulado.
- A pasta do Lume é relida ao abrir e ao voltar para o app (com subpastas), então arquivos colocados pelo gerenciador de arquivos aparecem. A outra pasta continua opcional, lida sem cópia.
- TXT: abre no leitor de texto, com UTF-8, UTF-16 (BOM) e Latin-1/Windows-1252 reconhecidos sozinhos, parágrafos, capítulos no sumário e sem o cabeçalho do Project Gutenberg. Filtro TXT na biblioteca.
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
