# Validação realizada

Data: 8 de agosto de 2026

- 20 arquivos Swift analisados por parser Tree-sitter Swift: sem nós de erro.
- `Info.plist`, `AppConfig.plist`, entitlements e Privacy Manifest analisados: válidos.
- Catálogos JSON de assets analisados: válidos.
- AppIcon confirmado em 1024 × 1024.
- Migração PostgreSQL analisada pelo parser `pglast`: sintaxe válida.
- RLS confirmada nas cinco tabelas expostas.
- Buckets `audio` e `covers` confirmados como privados.
- Código Swift verificado para ausência de `service_role`.
- Chamadas de Auth, Storage, URLs assinadas e RPC comparadas com `supabase-swift` 2.54.1.
- Grade da biblioteca conferida com duas colunas flexíveis e largura igual por cartão.
- Menus de faixa conferidos para tocar agora, tocar a seguir, adicionar à fila, exportar MP3, ver informações e excluir quando autorizado.
- Mini player, tela completa, busca na linha do tempo, controles anterior/próxima, repetição e visualização da fila analisados pelo parser.
- Workflow atualizado para `actions/checkout@v5`, `actions/upload-artifact@v6` e artefato `YePly-1.1.0-unsigned.ipa`.

## Limite desta validação

Este ambiente é Windows e não possui Xcode nem os SDKs do iOS. A compilação, execução no simulador, assinatura e teste em dispositivo precisam ser feitos em um Mac ou pelo workflow incluído do GitHub Actions. O projeto inclui `project.yml` como rota alternativa para regeneração com XcodeGen.
