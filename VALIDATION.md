# Validação realizada

Data: 9 de agosto de 2026

- 33 arquivos Swift analisados por parser Tree-sitter Swift: sem nós de erro.
- `Info.plist`, `AppConfig.plist`, entitlements e Privacy Manifest analisados: válidos.
- Catálogos JSON de assets analisados: válidos.
- AppIcon confirmado em 1024 × 1024.
- Oito migrações PostgreSQL analisadas pelo parser `pglast`: sintaxe válida.
- RLS confirmada nas tabelas expostas, incluindo histórico, notificações e todo o estado privado do jogo de cartas.
- Buckets `audio`, `covers` e `avatars` confirmados como privados.
- Código Swift verificado para ausência de `service_role`.
- Chamadas de Auth, Storage, URLs assinadas e RPC comparadas com `supabase-swift` 2.54.1.
- Grade da biblioteca conferida com duas colunas flexíveis e largura igual por cartão.
- Menus de faixa conferidos para tocar agora, tocar a seguir, adicionar à fila, exportar MP3, ver informações e excluir quando autorizado.
- Mini player, tela completa, busca na linha do tempo, controles anterior/próxima, repetição e visualização da fila analisados pelo parser.
- Workflow atualizado para `actions/checkout@v5`, `actions/upload-artifact@v6` e artefato `YePly-2.0.0-unsigned.ipa`.
- Saudação conferida usando `profiles.username`, removendo o arroba e exibindo em maiúsculas.
- Mini player reposicionado acima da barra de abas, com gesto vertical para esconder e controle para restaurar.
- Novo logo conferido nos componentes SwiftUI e no AppIcon de 1024 × 1024, RGB e sem transparência.
- Manifests offline vinculados por usuário e playlist, com arquivos protegidos e excluídos do backup do iCloud.
- Fallback local conferido na biblioteca, capas, player, fila, tela bloqueada e exportação de MP3.
- Modo offline e progresso de download conferidos no estado observável do aplicativo.
- Perfil social conferido com nome editável, username imutável, biografia, gostos e avatar privado.
- Busca e páginas públicas conferidas para usuários, artistas e playlists.
- Créditos com vírgulas conferidos como identidades de artista independentes no Swift e no PostgreSQL.
- Ranking agregado limitado a playlists públicas, sem expor a identidade de quem reproduziu.
- Seguidores, curtidas, comentários e visualizações protegidos por RLS e funções autenticadas.
- Normalização da foto de perfil conferida antes do recorte e upload, preservando a orientação visual.
- Forma de onda analisada a partir do PCM do MP3, limitada a 96 amostras por faixa.
- Comentários temporais validados também pelo PostgreSQL contra a duração da música.
- Histórico privado, selo administrativo e notificações protegidos por RLS.
- Pré-carregamento da próxima faixa e fade configurável persistidos no aparelho.
- Catálogo colecionável limitado inicialmente a créditos exatos de Kanye West nas faixas públicas existentes.
- Raridades calculadas por reproduções agregadas internas; nenhuma credencial ou métrica do Spotify é armazenada.
- Packs, códigos SHA-256, drops de reprodução, streak, XP, níveis e conquistas auditados no servidor.
- Instâncias de cartas com UUID e número serial, incluindo repetidas e conclusão de álbuns.
- Badges equipáveis em três posições e recompensas de conquista limitadas aos artistas favoritos.
- Trocas atômicas auditadas com reserva apenas das cartas oferecidas e revalidação das solicitadas na aceitação.
- RPCs do aplicativo comparadas com os nomes e parâmetros exatos da migration `202608090007_collectible_cards.sql`.
- Termos completos incluídos como recurso Markdown, pesquisáveis e com aceite obrigatório no cadastro.
- Versão atualizada para 2.0.0 (build 8).

## Limite desta validação

Este ambiente é Windows e não possui Xcode nem os SDKs do iOS. A compilação, execução no simulador, assinatura e teste em dispositivo precisam ser feitos em um Mac ou pelo workflow incluído do GitHub Actions. O projeto inclui `project.yml` como rota alternativa para regeneração com XcodeGen. A migration reduz fraudes casuais de reprodução com heartbeats e limites do servidor, mas atestado forte exigiria um backend de streaming confiável ou App Attest.
