# PDF no Lume: escolha do pacote

O Lume desenha os PDFs com o **[pdfrx](https://pub.dev/packages/pdfrx)** (versão 2.12, licença **MIT**), que usa o **PDFium** (o motor de PDF do Chrome, licenças BSD-3 e Apache-2.0). O PDFium vem dentro do APK (pacotes `pdfium_flutter` e `pdfium_dart`), então a leitura é toda offline.

Por que esse pacote:

- **Licença livre.** MIT no pacote e BSD/Apache no PDFium. Não há licença comercial, chave nem limite de receita. O Syncfusion Flutter PDF Viewer, por exemplo, exige licença comercial ou a "community license", que tem condições de receita e de tamanho da empresa. Por isso ficou de fora.
- **Mantido.** Tem lançamentos frequentes e suporta Android, iOS, desktop e web.
- **Qualidade.** Renderiza em blocos conforme o zoom, então o texto continua nítido mesmo ampliado. Também lê o sumário (outline), o texto da página, links e PDFs grandes com carregamento progressivo.
- **Controle.** Expõe a API de página (`PdfPageView`, `PdfPage.render`). Com ela o Lume faz o modo página a página, a capa da primeira página e o filtro de cor dos temas (`pageImageColorFilter`).

Alternativas consideradas:

| Pacote | Por que não |
|---|---|
| `syncfusion_flutter_pdfviewer` | Licença comercial ou community license com restrições |
| `flutter_pdfview` / `android_pdf_viewer` | Usa o PdfRenderer nativo, tem menos controle sobre zoom e temas e é menos ativo |
| `pdfx` | Menos ativo e com API de visualização mais limitada |
| PDF.js em WebView | Mais pesado e não é nativo |

Os metadados (título e autor) são lidos direto do arquivo em Dart puro (`lib/pdf.dart`), sem abrir o PDFium. Assim, a leitura de uma pasta grande fica rápida e roda fora da thread de interface. A capa (primeira página) é gerada depois, com o PDFium, e fica em cache.
