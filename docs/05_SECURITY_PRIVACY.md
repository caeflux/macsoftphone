# 05 — Segurança e Privacidade

## Princípio central

Softphone lida com credenciais, chamadas, números e dados sensíveis. Segurança não deve ser adicionada depois; deve estar presente desde o MVP.

## Credenciais

Obrigatório:

- Salvar senha SIP no Keychain.
- Nunca salvar senha em UserDefaults.
- Nunca logar senha.
- Nunca exibir senha em diagnóstico.
- Permitir limpar credenciais.

## Configuração local

Pode ser salvo em UserDefaults ou armazenamento local:

- Último usuário SIP, se mascarado ou sem senha.
- Domínio SIP.
- Preferência de dispositivo de áudio.
- Tema selecionado.
- Feature flags não sensíveis.

Não pode ser salvo sem proteção:

- Senha.
- Token de API.
- Refresh token.
- Payload de autenticação.

## Logs

Logs devem ser sanitizados.

Antes de salvar ou copiar diagnóstico, mascarar:

- Usuários, quando necessário.
- Números completos, quando necessário.
- IPs sensíveis, se aplicável.
- Tokens.
- Senhas.
- Headers de autorização.

## Permissão de microfone

O app deve:

- Solicitar permissão de microfone apenas quando necessário.
- Explicar por que precisa da permissão.
- Mostrar caminho de correção caso o usuário bloqueie.

## Privacidade

O app não deve enviar telemetria, logs ou histórico para servidores externos sem decisão explícita de produto e aviso adequado.

Quando telemetria for implementada, deve existir:

- Política clara.
- Opt-in/opt-out, se necessário.
- Minimização de dados.
- Logs sem conteúdo de chamada.

## Dados de chamadas

Histórico local deve registrar apenas o necessário:

- Número/contato.
- Direção.
- Horário.
- Duração.
- Status.

Não registrar:

- Áudio.
- Conteúdo da chamada.
- Pacotes RTP.
- Payload SIP completo com dados sensíveis.

## Segurança em white label

Cada marca/tenant deve ter configuração separada.

Nunca permitir que uma marca acesse:

- Credenciais de outra marca.
- Configuração de outro tenant.
- Logs de outro cliente.

## Critério de aceite

Nenhuma senha ou token aparece em:

- Console.
- Arquivos de log.
- Histórico.
- Diagnóstico copiado.
- Crash report manual.
