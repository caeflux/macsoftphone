# Development Loop — Claude Code

## Objetivo

Rodar o desenvolvimento em ciclos curtos, sempre entregando incremento funcional e evitando mexer em muitas áreas ao mesmo tempo.

## Regra de ciclo

Cada ciclo deve focar em apenas uma frente principal:

- Estrutura base do projeto.
- White label.
- Conta SIP.
- Registro.
- Discador.
- Chamada de saída.
- Chamada de entrada.
- Áudio.
- Histórico.
- Configurações.
- Diagnóstico.
- Build/release.

## Ordem recomendada dos ciclos

### Ciclo 1 — Bootstrap do projeto

- Criar projeto macOS SwiftUI.
- Criar estrutura de pastas.
- Criar modelos base.
- Criar AppState.
- Criar tela inicial mockada.
- Confirmar build.

### Ciclo 2 — White label base

- Criar BrandConfig.
- Carregar `brand-config.json`.
- Aplicar nome, cores e logo mockado.
- Remover hardcodes de marca.

### Ciclo 3 — Conta SIP e Keychain

- Criar modelo SIPAccount.
- Criar tela de cadastro manual.
- Salvar credenciais no Keychain.
- Carregar conta salva.
- Limpar credenciais.

### Ciclo 4 — SIP engine mockável

- Criar SIPClientProtocol.
- Criar implementação mock.
- Criar estados de registro.
- Conectar UI ao estado.

### Ciclo 5 — Registro SIP real

- Integrar biblioteca/engine SIP escolhida.
- Encapsular dependência.
- Registrar conta real.
- Exibir erros.
- Não quebrar mock.

### Ciclo 6 — Discador

- Criar input de número.
- Criar teclado numérico.
- Criar validação básica.
- Preparar ação de chamada.

### Ciclo 7 — Chamada de saída

- Implementar makeCall.
- Estados dialing/ringing/active/ended.
- Encerrar chamada.
- Registrar no histórico.

### Ciclo 8 — Chamada de entrada

- Receber evento de chamada.
- Exibir tela/modal de entrada.
- Atender.
- Recusar.
- Registrar chamada perdida.

### Ciclo 9 — Áudio

- Permissão de microfone.
- Mute/unmute.
- Seleção de input/output.
- Diagnóstico de áudio.

### Ciclo 10 — Histórico

- Persistência local.
- Lista de chamadas.
- Chamar novamente.
- Limpar histórico, se necessário.

### Ciclo 11 — Diagnóstico e suporte

- Tela de diagnóstico.
- Copiar diagnóstico sanitizado.
- Último erro.
- Estado SIP.
- Versão do app.

### Ciclo 12 — Release interno

- Ajustar versão.
- Revisar white label padrão.
- Gerar build.
- Checklist QA.

## Em cada ciclo, Claude deve entregar

- Implementação pequena e funcional.
- Build/test executado quando possível.
- Resumo objetivo.
- Próximo ciclo recomendado.
- Riscos técnicos identificados.

## Proibido em ciclos normais

- Reescrever o projeto inteiro sem necessidade.
- Trocar stack sem justificar.
- Misturar 5 features no mesmo ciclo.
- Inserir credenciais reais no código.
- Ignorar falhas de build.
- Criar UI bonita sem fluxo funcional.

## Quando encontrar bloqueio

Se uma biblioteca, permissão ou API impedir avanço:

1. Documentar o bloqueio.
2. Criar interface mockável.
3. Implementar fallback temporário.
4. Deixar TODO explícito.
5. Não travar todo o projeto.
