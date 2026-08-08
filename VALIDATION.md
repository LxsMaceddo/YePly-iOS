# Validação realizada

Data: 8 de agosto de 2026

- 21 arquivos Swift analisados por parser Tree-sitter Swift: sem nós de erro.
- `Info.plist`, `AppConfig.plist`, entitlements e Privacy Manifest analisados: válidos.
- Catálogos JSON de assets analisados: válidos.
- AppIcon confirmado em 1024 × 1024.
- Quatro migrações PostgreSQL analisadas pelo parser `pglast`: sintaxe válida.
- RLS confirmada nas cinco tabelas expostas.
- Buckets `audio`, `covers` e `avatars` confirmados como privados.
- Código Swift verificado para ausência de `service_role`.
- Chamadas de Auth, Storage, URLs assinadas e RPC comparadas com `supabase-swift` 2.54.1.
- Grade da biblioteca conferida com duas colunas flexíveis e largura igual por cartão.
- Menus de faixa conferidos para tocar agora, tocar a seguir, adicionar à fila, exportar MP3, ver informações e excluir quando autorizado.
- Mini player, tela completa, busca na linha do tempo, controles anterior/próxima, repetição e visualização da fila analisados pelo parser.
- Workflow atualizado para `actions/checkout@v5`, `actions/upload-artifact@v6` e artefato `YePly-1.2.0-unsigned.ipa`.
- Saudação conferida usando `profiles.username`, removendo o arroba e exibindo em maiúsculas.
- Mini player reposicionado acima da barra de abas, com gesto vertical para esconder e controle para restaurar.
- Novo logo conferido nos componentes SwiftUI e no AppIcon de 1024 × 1024, RGB e sem transparência.
- Manifests offline vinculados por usuário e playlist, com arquivos protegidos e excluídos do backup do iCloud.
- Fallback local conferido na biblioteca, capas, player, fila, tela bloqueada e exportação de MP3.
- Modo offline e progresso de download conferidos no estado observável do aplicativo.
- Perfil social conferido com nome editável, username imutável, biografia, gostos e avatar privado.
- Versão atualizada para 1.2.0 (build 4).

## Limite desta validação

Este ambiente é Windows e não possui Xcode nem os SDKs do iOS. A compilação, execução no simulador, assinatura e teste em dispositivo precisam ser feitos em um Mac ou pelo workflow incluído do GitHub Actions. O projeto inclui `project.yml` como rota alternativa para regeneração com XcodeGen.
