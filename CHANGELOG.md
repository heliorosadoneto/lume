# Histórico de mudanças

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
