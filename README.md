<p align="center">
  <img src="assets/logo/lume.png" width="96" alt="Ícone do Lume: uma lua feita de páginas e um vaga-lume">
</p>

<p align="center">
  <img src="docs/screenshots/01_biblioteca.png" width="220" alt="Biblioteca do Lume">
</p>

<h1 align="center">Lume</h1>

<p align="center"><strong>Seu leitor de EPUB, PDF e TXT, calmo e offline.</strong><br>
Abra o livro, continue de onde parou, grife o que importa.</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3-02569B?logo=flutter&logoColor=white">
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3-0175C2?logo=dart&logoColor=white">
  <img alt="Android" src="https://img.shields.io/badge/Android-7%2B-3DDC84?logo=android&logoColor=white">
  <img alt="Offline" src="https://img.shields.io/badge/offline-sem%20conta-B85C38">
</p>

<p align="center">
  <a href="releases/Lume.apk"><strong>Baixar o APK</strong></a>
  · pacote <code>com.helio.lume</code>
  · interface em português do Brasil
</p>

---

## Por que o Lume

O Lume é um leitor para o celular, no espírito de um Kindle, feito para ler com calma. Não tem loja, não tem anúncios e não pede conta. Na primeira abertura o Lume cria a sua pasta, **Documentos/Lume**. Toque em **Importar** para copiar para ela os seus EPUBs, PDFs e TXTs (vários de uma vez), ou aponte outra pasta que você já tenha. A biblioteca aparece em lista, com capa, título, autor e o quanto você já leu.

Na primeira abertura há livros de demonstração em domínio público (Machado de Assis e José de Alencar), só para você ver o app funcionando. Depois, use a sua própria pasta.

## Download

O APK de release fica neste repositório:

- [releases/Lume.apk](releases/Lume.apk)

1. Baixe o arquivo no celular Android (7 ou mais novo).
2. Abra-o e permita **instalar apps desta fonte** quando o sistema pedir.
3. Abra o **Lume** e toque em **Importar** para copiar os seus livros para a pasta do Lume, ou use o **+** para escolher outra pasta.

A chave de assinatura fica só na máquina que gera o APK (`android/key.properties`) e **não** entra no git. Guarde um backup dessa chave: sem ela, uma atualização futura não pode ser instalada por cima desta.

## Próxima versão (1.3, em aprovação): pasta do Lume, Importar, TXT e ícone novo

> Ainda sem APK. Estas telas são para aprovação.

**A pasta do Lume.** Na primeira abertura o Lume cria uma pasta só dele:

1. **Documentos/Lume** (`/storage/emulated/0/Documents/Lume`), à vista em qualquer gerenciador de arquivos. É o padrão.
2. Se o Android não deixar criar a pasta em Documentos, ela fica na pasta do app: **Android/data/com.helio.lume/files/Livros**. *Ajustes* explica onde ela está e oferece **Usar Documentos/Lume** (pede o “Acesso a todos os arquivos” e muda os livros de lugar). Atenção: o Android apaga essa pasta se você desinstalar o Lume, e alguns gerenciadores de arquivos a escondem.
3. Em último caso, a pasta interna do app (invisível fora dele).

O caminho aparece em *Ajustes → Pasta do Lume* e no topo da biblioteca. Livros importados antes vão sozinhos para a pasta nova.

**Importar.** O botão **Importar** (e o **+ → Importar livros**) abre o seletor do Android com **vários arquivos de uma vez** (EPUB, PDF ou TXT). O Lume **copia** os arquivos para a pasta do Lume, mostra o progresso (*Importando 2 de 5…*, MB copiados) e um resumo. Se já existir um arquivo com o mesmo nome e outro conteúdo, a cópia vira `nome (2).pdf`; se o conteúdo for idêntico (mesmo hash), o arquivo é pulado como *Já estava na pasta*. Os livros aparecem na hora.

**Arquivos colocados pelo gerenciador.** A pasta do Lume é relida ao abrir o app e ao voltar para ele (e vigiada enquanto ele está aberto), com subpastas. No Android 11 ou mais novo, para ver arquivos que *outro* app colocou em Documentos/Lume, o Lume precisa do “Acesso a todos os arquivos” (botão **Liberar acesso** em *Ajustes*); o que o próprio Lume importou aparece sempre.

**Outra pasta.** Continua dando para escolher uma pasta qualquer (*Usar outra pasta*): os livros dela são lidos onde estão, sem cópia, junto com os da pasta do Lume.

**TXT.** Arquivos `.txt` abrem no leitor de texto, com fonte, temas, destaques e notas. O Lume reconhece UTF-8 (com ou sem BOM), UTF-16 com BOM e, se não for UTF-8, Latin-1/Windows-1252. Parágrafos são separados por linha em branco, títulos como *CAPÍTULO I* viram sumário e o cabeçalho e a licença do Project Gutenberg ficam de fora do texto.

**Ícone novo.** Uma lua feita de páginas com um vaga-lume, sobre terracota: ícone adaptativo (fundo `#D46950`, lua dentro da zona segura), versões redonda e quadrada, camada monocromática para os ícones temáticos do Android 13, splash e tela *Sobre*. Gerado por `tool/make_icon.py` a partir de `branding/lume-logo.jpg`.

| Biblioteca com Importar | Importando | Resumo |
|---|---|---|
| <img src="docs/screenshots/29_biblioteca_importar.png" width="230" alt="Biblioteca com o botão Importar"> | <img src="docs/screenshots/31_importando.png" width="230" alt="Importando 2 de 5"> | <img src="docs/screenshots/32_importado.png" width="230" alt="4 livros importados, 1 já estava na pasta"> |

| Depois de importar | Pasta do Lume em Ajustes | Pasta do app (alternativa) |
|---|---|---|
| <img src="docs/screenshots/33_biblioteca_depois.png" width="230" alt="Biblioteca com EPUB, PDF e TXT"> | <img src="docs/screenshots/34_ajustes_pasta_lume.png" width="230" alt="Pasta do Lume em Documentos e outra pasta"> | <img src="docs/screenshots/35_ajustes_pasta_app.png" width="230" alt="Explicação da pasta do app"> |

| TXT no leitor | Botão + | Sobre |
|---|---|---|
| <img src="docs/screenshots/37_txt_leitor.png" width="230" alt="Iracema em TXT no leitor"> | <img src="docs/screenshots/30_adicionar_livros.png" width="230" alt="Importar livros, usar outra pasta"> | <img src="docs/screenshots/36_sobre.png" width="230" alt="Tela Sobre com o ícone"> |

| Ícone no celular | Splash |
|---|---|
| <img src="docs/screenshots/38_icone_launcher.png" width="230" alt="Ícone na tela inicial e na gaveta de apps"> | <img src="docs/screenshots/39_splash.png" width="230" alt="Splash terracota com a lua"> |

A prévia do ícone e da splash é desenhada por `tool/make_icon_previews.py`; as outras são telas reais do app (testes de golden).

## Novidades da versão 1.1: PDF e pasta inteira

> Ainda não está no APK de `releases/` (que é a 1.0). Estas telas são para aprovação.

O Lume agora abre **PDF**. A página aparece como no original (o PDF é desenhado pelo PDFium, no próprio celular), com zoom com pinça, rolagem contínua ou página a página, barra de páginas, *Ir para a página*, sumário do PDF, marcadores e os mesmos temas do leitor de EPUB. Também dá para **escolher uma pasta**: o Lume procura PDFs e EPUBs nela e em todas as subpastas, mostra o progresso, ignora repetidos e lembra a pasta para você atualizar depois.

| Biblioteca com PDFs | Só os PDFs | Botão + |
|---|---|---|
| <img src="docs/screenshots/12_biblioteca_pdf.png" width="230" alt="Biblioteca com PDFs e EPUBs"> | <img src="docs/screenshots/13_biblioteca_filtro_pdf.png" width="230" alt="Filtro PDF"> | <img src="docs/screenshots/14_adicionar_livros.png" width="230" alt="Adicionar livros"> |

| Permissão da pasta | Lendo a pasta | Resultado |
|---|---|---|
| <img src="docs/screenshots/15_permissao_pasta.png" width="230" alt="Explicação da permissão"> | <img src="docs/screenshots/16_pasta_progresso.png" width="230" alt="Encontrados 34 livros"> | <img src="docs/screenshots/17_pasta_resultado.png" width="230" alt="Resumo da pasta"> |

| PDF em sépia | PDF no tema preto | Página a página |
|---|---|---|
| <img src="docs/screenshots/18_pdf_leitor_sepia.png" width="230" alt="Leitor de PDF sépia"> | <img src="docs/screenshots/19_pdf_leitor_preto.png" width="230" alt="Leitor de PDF preto"> | <img src="docs/screenshots/20_pdf_pagina_a_pagina.png" width="230" alt="Página a página"> |

| Zoom | Barra de páginas | Ir para a página |
|---|---|---|
| <img src="docs/screenshots/21_pdf_zoom.png" width="230" alt="Zoom com pinça"> | <img src="docs/screenshots/22_pdf_barra_paginas.png" width="230" alt="Barra de páginas"> | <img src="docs/screenshots/23_pdf_ir_para_pagina.png" width="230" alt="Ir para a página"> |

| Sumário do PDF | Marcadores | Aparência do PDF |
|---|---|---|
| <img src="docs/screenshots/24_pdf_sumario.png" width="230" alt="Sumário do PDF"> | <img src="docs/screenshots/25_pdf_marcadores.png" width="230" alt="Marcadores do PDF"> | <img src="docs/screenshots/26_pdf_aparencia.png" width="230" alt="Aparência do PDF"> |

### Modo texto para PDF

Muitos PDFs (sobretudo os de livro feitos para papel carta ou A4) ficam com a letra miúda no celular. Quando o PDF tem texto selecionável, o Lume abre no **modo texto**: o texto do PDF é refeito em parágrafos (junta as linhas, desfaz a hifenização, tira cabeçalhos, rodapés e números de página e reconhece os títulos dos capítulos) e aparece no mesmo leitor dos EPUBs, com a fonte, o tamanho, o espaçamento, as margens e os temas que você escolher, além de destaques e notas. A posição é a mesma nos dois modos: trocar para a *Página original* (no painel de aparência) abre a página que você estava lendo, e vice-versa. O texto é extraído uma vez, fora da tela, com progresso, e fica guardado no aparelho. PDF escaneado (páginas que são só imagens) abre na página original, com um aviso. Na página original, as margens brancas são cortadas para o texto ocupar a largura da tela (dá para desligar).

| Modo texto | Aparência com a troca de modo |
|---|---|
| <img src="docs/screenshots/27_pdf_modo_texto.png" width="230" alt="Modo texto do PDF"> | <img src="docs/screenshots/28_pdf_modo_texto_aparencia.png" width="230" alt="Troca entre modo texto e página original"> |

## Telas

| Biblioteca | Pasta nos ajustes | Leitor (sépia) |
|---|---|---|
| <img src="docs/screenshots/01_biblioteca.png" width="230" alt="Biblioteca em lista"> | <img src="docs/screenshots/02_ajustes_pasta.png" width="230" alt="Escolha da pasta"> | <img src="docs/screenshots/04_leitor_sepia.png" width="230" alt="Leitor em sépia"> |

| Tema preto | Seleção e cores | Caderno |
|---|---|---|
| <img src="docs/screenshots/05_leitor_preto.png" width="230" alt="Leitor no tema preto"> | <img src="docs/screenshots/07_selecao_cores.png" width="230" alt="Marca-texto"> | <img src="docs/screenshots/08_caderno_destaques.png" width="230" alt="Caderno de destaques"> |

| Aparência | Sumário | Ajustes de leitura |
|---|---|---|
| <img src="docs/screenshots/10_aparencia.png" width="230" alt="Painel de aparência"> | <img src="docs/screenshots/11_sumario.png" width="230" alt="Sumário"> | <img src="docs/screenshots/03_ajustes_leitura.png" width="230" alt="Ajustes de leitura"> |

Há ainda o tema verde claro e a aba de marcadores (`docs/screenshots/06_leitor_verde_lora.png` e `09_caderno_marcadores.png`). Os prints são das telas reais do app, no tamanho do moto g 9 plus (1080×2400), com livros de demonstração.

## O que o app faz

- **Biblioteca em lista.** Capa (a do EPUB ou a primeira página do PDF), título, autor, etiqueta EPUB, PDF ou TXT, pasta de onde veio, número de páginas do PDF, barra de progresso ou a etiqueta *Novo*. Filtro *Todos · PDF · EPUB · TXT*. Puxe para baixo para atualizar.
- **Continuar leitura.** Uma prateleira no topo com os livros em andamento, do mais recente para o mais antigo.
- **Pasta do Lume.** Criada na primeira abertura (Documentos/Lume, ou a pasta do app). Tudo o que você importa vai para lá, e o que você colocar nela pelo gerenciador de arquivos também entra na biblioteca.
- **Outra pasta.** No **+** (ou em *Ajustes*) você escolhe uma pasta do celular. O Lume procura arquivos `.epub`, `.pdf` e `.txt` nela e em todas as subpastas, mostra o progresso (*Encontrados 34 livros…*), ignora o resto e não lista o mesmo livro duas vezes (mesmo arquivo com outro nome também conta como repetido). Os arquivos não são copiados: ficam onde estão. O caminho fica salvo e **Atualizar pasta** pega os livros novos.
- **Atualizar automaticamente.** Com a opção ligada, livros novos na pasta entram sozinhos na biblioteca. A pasta também é relida quando o app volta à tela.
- **Importar.** O botão **Importar** copia vários EPUBs, PDFs ou TXTs de uma vez para a pasta do Lume, com progresso; nomes iguais viram `nome (2)` e arquivos idênticos são pulados.
- **TXT.** Texto puro no mesmo leitor dos EPUBs, com UTF-8 ou Latin-1 reconhecidos sozinhos.
- **Retomar a posição.** Cada livro guarda o parágrafo e o ponto da leitura. Ao reabrir, você volta exatamente dali.
- **Marca-texto.** Selecione um trecho e escolha amarelo, laranja, rosa ou azul (como no Kindle). Dá para anexar uma nota, copiar ou remover. Destaques com nota ficam sublinhados. Tudo é salvo no celular.
- **Caderno.** Lista os destaques (com filtro por cor) e os marcadores. Tocar num item salta para aquele trecho. Dá para editar a nota, mudar a cor ou apagar.
- **Aparência.** Temas de página branco, sépia, verde claro e preto; fontes Literata, Lora ou Source Sans; tamanho, espaçamento, margens, alinhamento e modo de leitura (rolagem contínua ou virar página, tocando nas bordas).
- **Sumário.** Capítulos do livro, com o atual marcado e a porcentagem de cada um.
- **Barra de progresso.** Mostra a % do livro e uma estimativa do tempo restante no capítulo.
- **Leitor de PDF.** Página fiel ao original, sem internet. Rolagem contínua ou página a página (deslizar ou tocar nas bordas), zoom com pinça e toque duplo, barra para pular páginas, *Ir para a página*, sumário do próprio PDF, marcadores por página e a posição salva. Os temas sépia, verde claro e preto tingem a página (no preto ela se inverte); *Cores originais da página* desliga isso para fotos e mapas.
- **Modo texto para PDF.** PDFs com texto abrem refeitos em parágrafos no leitor de EPUB (fonte, tamanho, temas, destaques e notas), com a posição sincronizada com a página original. Tabelas, fórmulas e imagens só aparecem na página original.

Loja de livros e conta na nuvem ficam de fora.

## Como funciona

```mermaid
flowchart LR
  I[Importar] --> L[Documentos/Lume]
  L --> B[Lume]
  A[Outra pasta<br>opcional] --> B
  B --> C[Biblioteca]
  C --> D[Leitor EPUB]
  C --> P[Leitor PDF<br>PDFium via pdfrx]
  D --> E[Posição, destaques<br>e marcadores no aparelho]
  P --> E
```

O Lume lê o EPUB no próprio app (é um ZIP com o texto do livro). Ele abre o pacote, lê o título, o autor e a capa, percorre os capítulos e mostra o texto em Flutter — sem internet.

O PDF é desenhado pelo [pdfrx](https://pub.dev/packages/pdfrx) (licença MIT), que usa o PDFium (o motor de PDF do Chrome, licença BSD/Apache) embutido no APK. O título e o autor vêm dos metadados do arquivo (ou do nome dele) e a capa é a primeira página, guardada em cache. Por que o pdfrx e não outro pacote: veja [docs/PDF.md](docs/PDF.md).

```
lib/
  epub.dart       lê o EPUB (OPF, capítulos, capa, sumário)
  pdf.dart        metadados, identificador e capa do PDF
  pdf_reflow.dart refaz parágrafos a partir das linhas do PDF (modo texto)
  pdf_analysis.dart extrai o texto e as margens com o PDFium e guarda em cache
  txt.dart        lê TXT (UTF-8, UTF-16, Latin-1/cp1252), parágrafos e capítulos
  importer.dart   copia para a pasta do Lume (nome (2), repetidos por hash, progresso)
  lume_folder.dart escolhe e cria a pasta do Lume (Documentos/Lume ou a do app)
  library.dart    lê a pasta do Lume e a outra pasta (e subpastas) com progresso
  store.dart      guarda posição, destaques, marcadores e preferências
  screens/        biblioteca, leitores EPUB e PDF, pasta, caderno, aparência e ajustes
assets/fonts/     Literata, Lora e Source Sans 3 (licença SIL OFL)
demo_folder/      4 EPUBs, 3 PDFs (pdf/) e 1 TXT (txt/) de exemplo para copiar ao celular
assets/logo/      ícone do app usado no Sobre
branding/         logo original (fonte do ícone)
docs/screenshots/ prints das telas
tool/             geradores dos PDFs de exemplo, do ícone e da prévia do ícone
releases/         APK de release
```

## Design

- Fundo cor de papel creme, tinta em carvão-marrom, acento terracota e âmbar.
- Texto do livro em fonte serifada (Literata, com Lora como opção); interface em Source Sans 3.
- Cartões suaves, margens generosas, entrelinha folgada e movimento discreto (Material 3).
- Cores do marca-texto alinhadas ao Kindle: amarelo, laranja, rosa e azul.

## Instalação e compilação

Requisitos para gerar o APK: Flutter 3, JDK 17 e Android SDK.

```bash
flutter pub get
flutter test
flutter build apk --release
# saída: build/app/outputs/flutter-apk/app-release.apk
# cópia: releases/Lume.apk
```

Para rodar no celular em modo de desenvolvimento:

```bash
flutter run
```

Toque em **Importar** e escolha arquivos de `demo_folder/` copiados para o aparelho, ou escolha a pasta em *Ajustes → Outra pasta*.

O build de release usa `android/key.properties` (ignorado pelo git). Sem esse arquivo, o Gradle usa a chave de debug, só para desenvolvimento.

Para atualizar os prints e o ícone:

```bash
flutter test --update-goldens
python3 tool/make_icon.py            # ícones, splash e assets/logo a partir de branding/lume-logo.jpg
python3 tool/make_icon_previews.py   # docs/screenshots/38 e 39
```

Os testes de PDF usam o PDFium no Linux. O pacote compila uma pequena biblioteca nativa na primeira vez e procura o `clang` no PATH (dá para usar o do Android NDK). A biblioteca do PDFium baixada fica em `.dart_tool/`, e os testes a encontram sozinhos (ou use `PDFIUM_PATH`).

## Limitações

- Um destaque não atravessa dois parágrafos.
- O leitor ignora o CSS e as imagens internas do livro e mantém títulos, parágrafos, itálico e negrito. A capa aparece na biblioteca.
- *Virar página* avança uma tela por toque, sem animação de folha e sem colunas de página.
- Se o arquivo EPUB for trocado por outra edição, a posição e os destaques podem cair em outro parágrafo (não usamos CFI).
- O tempo restante no capítulo é uma estimativa (cerca de 1.000 caracteres por minuto).
- No Android 11 ou mais novo, ler uma pasta qualquer pede *Acesso a todos os arquivos*. Sem essa permissão, a pasta Documentos/Lume mostra o que o Lume importou, mas não o que outro app colocou lá. Se o aparelho não deixar criar Documentos/Lume, a pasta fica em Android/data/com.helio.lume/files/Livros, que o Android apaga ao desinstalar o app. Para a Play Store, o caminho natural seria o seletor padrão de pastas do Android (SAF).
- PDF: não há marca-texto nem notas no PDF (só marcadores por página). Também não há busca de texto, e PDFs com senha ainda não abrem.
- PDF escaneado (só imagem) abre normalmente, mas os temas tingem a imagem também. Para fotos, use *Cores originais da página*.
- A posição no PDF é salva por página, não pelo ponto exato dentro da página.
- O título do PDF vem dos metadados quando o dicionário de informações não está comprimido; senão vem do nome do arquivo.
- TXT: o Lume reconhece UTF-8, UTF-16 com BOM e Latin-1/Windows-1252; outras codificações (UTF-16 sem BOM, Mac Roman…) podem trocar acentos. Títulos são achados por heurística (*Capítulo*, números romanos, linhas curtas em maiúsculas).
- A pasta do Lume ainda não foi testada num aparelho de verdade, só nos testes.
- Alguns EPUBs do Project Gutenberg abrem na página de licença em inglês antes do texto do livro.

## Segurança e privacidade

- Tudo roda no celular. Não há conta, servidor nem anúncio.
- Posição de leitura, destaques, notas, marcadores e o caminho da pasta ficam só no aparelho.
- A chave que assina o APK não é publicada neste repositório.

## Créditos

Livros de exemplo (domínio público), do [Project Gutenberg](https://www.gutenberg.org):

- *Dom Casmurro* (#55752), *Quincas Borba* (#55682) e *Memorias Posthumas de Braz Cubas* (#54829), de Machado de Assis
- *Iracema* (#67740), de José de Alencar (também em `demo_folder/txt/iracema-trecho.txt`, capítulos I a IV em Windows-1252)
- PDFs de exemplo (`demo_folder/pdf/`) gerados com `tool/make_sample_pdfs.py` a partir dos textos de *Helena* (#67162), *Esaú e Jacó* (#56737) e *Memorial de Aires* (#55797), de Machado de Assis. A capa é tipográfica, feita para a amostra.

Os arquivos mantêm o cabeçalho e a licença do Project Gutenberg. As fontes Literata, Lora e Source Sans 3 estão sob a SIL Open Font License 1.1 (`assets/fonts/OFL-*.txt`).

## Licença do código

© 2026 Hélio Rosado Neto. Ainda não foi escolhida uma licença de código aberto, então todos os direitos estão reservados.
