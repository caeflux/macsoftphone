# Acceptance Criteria

## Critério geral

Uma entrega só é aceita se:

- Compila.
- Mantém arquitetura limpa.
- Não expõe segredo.
- Tem comportamento verificável.
- Não quebra ciclos anteriores.
- Mantém documentação coerente.

## Ciclo 1 — Bootstrap

Aceito quando:

- Projeto macOS SwiftUI existe.
- Estrutura de pastas base existe.
- App abre em tela inicial.
- AppState existe.
- Build passa.

## Ciclo 2 — White label

Aceito quando:

- BrandConfig carrega configuração padrão.
- Nome, cor e logo são consumidos de configuração.
- Não há texto de marca hardcoded fora da configuração padrão.

## Ciclo 3 — Conta SIP e Keychain

Aceito quando:

- Usuário consegue inserir dados SIP.
- Dados são validados minimamente.
- Senha é salva no Keychain.
- Conta é carregada ao reabrir.
- Usuário consegue apagar credenciais.

## Ciclo 4 — SIP mockável

Aceito quando:

- Existe SIPClientProtocol.
- Existe implementação mock.
- UI reage aos estados de registro.
- Testes básicos de estado passam.

## Ciclo 5 — Registro real

Aceito quando:

- Conta SIP real registra em ambiente de teste.
- Erros principais são tratados.
- Logs não expõem senha.
- Mock continua disponível para desenvolvimento.

## Ciclo 6 — Discador

Aceito quando:

- Usuário digita número.
- Teclado numérico funciona.
- Colar número funciona.
- Botão ligar respeita estado de registro.

## Ciclo 7 — Chamada de saída

Aceito quando:

- Chamada de saída é iniciada.
- Estado visual muda corretamente.
- Encerrar funciona.
- Histórico recebe registro básico.

## Ciclo 8 — Chamada de entrada

Aceito quando:

- App exibe chamada recebida.
- Atender funciona.
- Recusar funciona.
- Chamada perdida é registrada.

## Ciclo 9 — Áudio

Aceito quando:

- App detecta permissão de microfone.
- Mute funciona.
- Dispositivos são listados quando possível.
- Troca de dispositivo não quebra chamada.

## Ciclo 10 — Histórico

Aceito quando:

- Histórico persiste localmente.
- Mostra direção, número, horário, duração e status.
- Permite ligar novamente.

## Ciclo 11 — Diagnóstico

Aceito quando:

- Tela de diagnóstico existe.
- Copiar diagnóstico funciona.
- Informações sensíveis são mascaradas.

## Ciclo 12 — Release interno

Aceito quando:

- Build instalável é gerado.
- Versão está correta.
- Marca padrão está correta.
- QA manual mínimo foi executado.
