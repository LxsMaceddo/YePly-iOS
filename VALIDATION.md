# Validação realizada

Data: 8 de agosto de 2026

- 29 arquivos Swift analisados por parser Tree-sitter Swift: sem nós de erro.
- `Info.plist`, `AppConfig.plist`, entitlements e Privacy Manifest analisados: válidos.
- Catálogos JSON de assets analisados: válidos.
- AppIcon confirmado em 1024 × 1024.
- Seis migrações PostgreSQL analisadas pelo parser `pglast`: sintaxe válida.
- RLS confirmada nas quinze tabelas expostas, incluindo histórico, verificações e notificações.
- Buckets `audio`, `covers` e `avatars` confirmados como privados.
- Código Swift verificado para ausência de `service_role`.
- Chamadas de Auth, Storage, URLs assinadas e RPC comparadas com `supabase-swift` 2.54.1.
- Grade da biblioteca conferida com duas colunas flexíveis e largura igual por cartão.
- Menus de faixa conferidos para tocar agora, tocar a seguir, adicionar à fila, exportar MP3, ver informações e excluir quando autorizado.
- Mini player, tela completa, busca na linha do tempo, controles anterior/próxima, repetição e visualização da fila analisados pelo parser.
- Workflow atualizado para `actions/checkout@v5`, `actions/upload-artifact@v6` e artefato `YePly-1.4.0-unsigned.ipa`.
- Saudação conferida usando `profiles.username`, removendo o arroba e exibindo em maiúsculas.
- Mini player reposicionado acima da barra de abas, com gesto vertical para esconder e controle para restaurar.
- Novo logo conferido nos componentes SwiftUI e no AppIcon de 1024 × 1024, RGB e sem transparência.
- Manifests offline vinculados por usuário e playlist, com arquivos protegidos e excluídos do backup do iCloud.
- Fallback local conferido na biblioteca, capas, player, fila, tela bloqueada e exportação de MP3.
- Modo offline e progresso de download conferidos no estado observável do aplicativo.
- Perfil social conferido com nome editável, username imutável, biografia, gostos e avatar privado.
- Busca e páginas públicas conferidas para usuários, artistas e playlists.
- Seguidores, curtidas, comentários e visualizações protegidos por RLS e funções autenticadas.
- Normalização da foto de perfil conferida antes do recorte e upload, preservando a orientação visual.
- Forma de onda analisada a partir do PCM do MP3, limitada a 96 amostras por faixa.
- Comentários temporais validados também pelo PostgreSQL contra a duração da música.
- Histórico privado, selo administrativo e notificações protegidos por RLS.
- Pré-carregamento da próxima faixa e fade configurável persistidos no aparelho.
- Versão atualizada para 1.4.0 (build 6).

## Limite desta validação

Este ambiente é Windows e não possui Xcode nem os SDKs do iOS. A compilação, execução no simulador, assinatura e teste em dispositivo precisam ser feitos em um Mac ou pelo workflow incluído do GitHub Actions. O projeto inclui `project.yml` como rota alternativa para regeneração com XcodeGen.
