# 00 — Product Brief

## Produto

Softphone white label para macOS/MacBook, voltado para clientes, revendas e tenants da Flux.

O app deve permitir que usuários realizem e recebam chamadas VoIP/SIP diretamente no computador, com uma experiência estável, limpa e profissional.

## Público-alvo

1. Empresas que usam telefonia Flux.
2. Operações comerciais e atendimento.
3. Clientes com PABX hospedado/multi-tenant.
4. Revendas que querem entregar softphone com marca própria.
5. Usuários corporativos que precisam de telefonia no desktop.

## Objetivos de negócio

- Criar ativo próprio de software para o ecossistema Flux.
- Reduzir dependência de softphones terceiros.
- Permitir white label para revendas e clientes estratégicos.
- Aumentar percepção de valor da telefonia Flux.
- Preparar base para integrações futuras com CRM, PABX, omnichannel e relatórios.

## MVP funcional

O MVP deve conter:

- Tela de boas-vindas/login/provisionamento.
- Cadastro manual de conta SIP.
- Registro SIP com status claro.
- Discador numérico.
- Chamada de saída.
- Recebimento de chamada.
- Atender, recusar e encerrar.
- Mudo/unmute.
- Seleção de microfone e saída de áudio.
- Histórico básico de chamadas.
- Persistência segura de credenciais.
- Configuração white label básica: nome, logo, cor principal, domínio/API base.

## Pós-MVP

- Provisionamento via QR code ou link.
- Login Flux por usuário/tenant.
- Busca de contatos.
- Integração com PABX multi-tenant.
- Transferência assistida e cega.
- Hold/resume.
- DTMF durante chamada.
- Gravação quando permitida pelo servidor.
- Presença/status.
- Click-to-call via CRM.
- Deep links `fluxphone://call/{number}`.
- Auto-update.
- Relatórios e telemetria operacional.

## Restrições importantes

- O app não deve depender de credenciais hardcoded.
- O core de chamada deve ser independente da UI.
- White label deve ser configurável sem fork pesado do código.
- O app deve ser preparado para múltiplas marcas sem duplicação estrutural.
- O usuário final deve conseguir diagnosticar estado básico: registrado, desconectado, erro de senha, erro de rede, chamada ativa.

## Métrica de sucesso inicial

- Registrar conta SIP real.
- Completar chamada de saída com áudio bidirecional.
- Receber chamada de entrada.
- Manter estabilidade em uso diário.
- Gerar build instalável para teste em macOS.
