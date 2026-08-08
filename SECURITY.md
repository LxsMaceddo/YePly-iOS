# Modelo de segurança do YePly

## Controles implementados

- RLS habilitada em todas as tabelas expostas.
- Autorização administrativa baseada apenas em `app_metadata`, nunca em `user_metadata`.
- `service_role` ausente do aplicativo.
- Buckets `audio` e `covers` privados.
- URLs de reprodução assinadas e válidas por 10 minutos.
- Token de compartilhamento UUID aleatório e não sequencial.
- Abrir um link cria uma associação explícita entre usuário e playlist.
- Playlists privadas não podem ser liberadas apenas pelo token.
- Upload restrito ao proprietário/editor e validado novamente pelo banco.
- Extensão, MIME e tamanho limitados pelo Storage e pelo cliente.
- Campos de segurança (`owner_id`, `share_token`, `role`) protegidos por triggers.
- Exclusão de arquivos compensatória quando a gravação de metadados falha.

## Antes de produção

- Habilite confirmação de e-mail, CAPTCHA e limites de requisições no Auth.
- Configure SMTP próprio e MFA para administradores.
- Revise o Security Advisor do Supabase após cada migração.
- Ative logs, alertas e backups com restauração testada.
- Faça análise de malware e validação real do conteúdo dos uploads em uma Edge Function.
- Adicione moderação, denúncias e remoção por direitos autorais.
- Execute testes de penetração e revisão independente antes de armazenar conteúdo sensível.

Nenhum sistema pode garantir ausência absoluta de vulnerabilidades. Estas regras formam uma base de defesa em profundidade, não substituem auditoria contínua.
