# YePly para iPhone

YePly é uma biblioteca musical privada e compartilhável feita em SwiftUI. O projeto inclui o aplicativo iOS, banco PostgreSQL, autenticação, armazenamento privado, políticas RLS e arquivos de Universal Links.

## O que está pronto

- Entrada, criação de conta e confirmação de e-mail
- Biblioteca minimalista com Tudo, Minhas e Compartilhadas
- Grade estável com duas playlists por linha e ordenação por data, nome ou artista
- Pesquisa e grade de capas adaptada ao iPhone
- Criação de playlists públicas, não listadas ou privadas
- Upload de MP3 pelo app Arquivos, limitado a 200 MB
- Upload de capa pela fototeca
- Player com fila, avançar/voltar e controles na tela bloqueada
- Player completo com capa, progresso, repetição e lista de próximas músicas
- Mini player acima das abas, com gesto para baixo e botão compacto para restaurá-lo
- Menu de faixa para tocar agora, tocar a seguir, adicionar à fila, ver informações e salvar o MP3
- Saudação da biblioteca usando o nome de usuário do perfil
- Logo oficial do YePly aplicado no aplicativo e no ícone do iPhone
- Download completo de playlists para reprodução offline com progresso visual
- Modo offline automático mostrando somente playlists disponíveis no iPhone
- Indicadores nas playlists e faixas já baixadas
- Reprodução local, capas e fila funcionando sem consultar o Supabase
- Perfil social editável com foto, nome, biografia e até 12 gostos musicais
- Busca integrada de usuários, artistas e playlists na aba Descobrir
- Créditos separados por vírgula tratados como artistas independentes na busca, nas páginas e nos contadores
- Ranking das músicas de playlists públicas mais reproduzidas, com contagem global agregada
- Sistema de seguir usuários, artistas e playlists, com contadores sociais
- Curtidas e comentários em cada música, incluindo curtidas nos comentários
- Visualizações únicas nas playlists e indicadores de curtidas nas faixas
- Tratamento automático da orientação da foto de perfil antes do upload
- Histórico de reprodução privado e sincronizado por usuário
- Player com forma de onda navegável gerada a partir da intensidade real dos novos MP3
- Comentários associados a momentos específicos da música, com retorno direto ao minuto
- Reprodução sem atraso com pré-carregamento da próxima faixa e fade configurável
- Selo azul de artista verificado administrado somente por contas admin
- Central de notificações e pop-ups para seguidores, curtidas e comentários
- Aba Cartas com coleção em duas colunas, cinco raridades e visual detalhado próprio do YePly
- Packs de três cartas por streak diário, códigos administrativos e tempo real de reprodução
- Packs especiais de cinco cartas ao resgatar conquistas com um artista favorito
- XP, níveis, ciclos de sete dias e oito conquistas iniciais
- Progresso por álbum, badges permanentes e três posições equipáveis no perfil
- Trocas atômicas entre usuários, cartas repetidas e bloqueio seguro somente da oferta
- Catálogo de teste de Kanye West criado a partir das faixas públicas já cadastradas no YePly
- Raridade baseada nas reproduções verificadas dentro do YePly, sem depender de contadores externos
- Termos de Serviço e Política de Direitos Autorais pesquisáveis no cadastro e no perfil
- Nome de usuário permanente protegido também por trigger no PostgreSQL
- Reprodução em segundo plano
- Links `https://yeply.app/p/<token>` e fallback `yeply://playlist/<token>`
- Área administrativa por função protegida no JWT
- Áudios e capas em buckets privados com URLs assinadas por 10 minutos
- Logs de abertura de links
- Modo demonstração quando o backend ainda não está configurado

## Requisitos para publicar

- Um Mac com Xcode 16 ou superior
- Uma conta Apple Developer
- Um projeto Supabase
- Um domínio seu para os Universal Links

## Configuração rápida

1. Crie um projeto no Supabase.
2. Em uma instalação nova, execute em ordem os arquivos de `supabase/migrations`. Em um projeto YePly já existente, execute as migrations pendentes em ordem, terminando em `202608090007_collectible_cards.sql`.
3. Crie sua conta pelo aplicativo e depois execute `supabase/promote-admin.sql`, substituindo o e-mail.
4. Em `YePly/Support/AppConfig.plist`, informe a URL e a **publishable key** do projeto. Nunca coloque a `service_role` no aplicativo.
5. No Supabase Auth, mantenha a confirmação de e-mail ativada e adicione `yeply://auth/callback` aos Redirect URLs.
6. Para produção, configure SMTP próprio, limites de Auth e proteção contra abuso no painel do Supabase.
7. Abra `YePly.xcodeproj`, selecione sua equipe em Signing & Capabilities e ajuste `com.yeply.app` se necessário.
8. Substitua `yeply.app` no entitlement e em `AppConfig.plist` pelo seu domínio.
9. Publique `web/.well-known/apple-app-site-association` sem extensão e com `Content-Type: application/json`. Troque `TEAM_ID` pelo Team ID da Apple.
10. Execute no simulador ou iPhone. Para TestFlight, use Product → Archive.
11. Antes de publicar, substitua os três e-mails entre colchetes em `YePly/Support/TermsOfService.md` e faça a revisão jurídica e de LGPD.

Se preferir regenerar o projeto, `project.yml` é compatível com XcodeGen.

## Gerar IPA sem assinatura pelo GitHub

O workflow `.github/workflows/build-unsigned-ipa.yml` compila em um runner macOS. Depois de enviar esta pasta para a raiz de um repositório, abra **Actions → Build YePly IPA → Run workflow**. O artefato `YePly-IPA` conterá o arquivo `.ipa` sem assinatura.

Um IPA sem assinatura é adequado para inspeção e posterior assinatura pelo AltStore ou outro serviço de sideloading.

## Administração

Administradores acessam **Perfil → Administração** para gerenciar o catálogo. Na aba **Cartas**, também podem sincronizar o catálogo de Kanye West e criar códigos de packs. A função administrativa vem de `raw_app_meta_data`, que não pode ser alterada pelo usuário. A `service_role` deve existir somente em serviços confiáveis ou no painel do Supabase.

## Direitos autorais

O YePly foi criado para músicas próprias, licenciadas, em domínio público ou cuja distribuição tenha sido autorizada. Os termos fornecidos estão incluídos no aplicativo, mas ainda contêm três contatos legais pendentes e precisam de revisão profissional antes da publicação. Nomes, capas, fotos e metadados de artistas também exigem as permissões aplicáveis.
