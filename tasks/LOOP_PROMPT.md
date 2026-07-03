# Prompt para rodar no Claude Code

Leia todos os arquivos `.md` deste projeto, começando por `CLAUDE.md`, `README.md` e depois a pasta `docs/` e `tasks/`.

Você está desenvolvendo um softphone white label para macOS/MacBook para a Flux.

Não comece com plano teórico longo. Primeiro faça uma auditoria rápida do estado atual do repositório, identifique se já existe projeto macOS/SwiftUI ou se deve criar o bootstrap inicial, e então implemente o próximo incremento real seguindo os documentos.

## Objetivo geral

Construir um app macOS nativo, profissional e white label, com arquitetura limpa, preparado para SIP real, chamadas, áudio, histórico, configurações, provisionamento e futuras integrações Flux.

## Regras obrigatórias

- Sempre preservar a arquitetura descrita nos MDs.
- Não misturar UI com SIP engine.
- Não salvar senha fora do Keychain.
- Não criar hardcode de marca, cor, domínio ou credenciais.
- Não apagar funcionalidades existentes sem necessidade.
- Não inventar API Flux concreta sem criar abstraction/protocol.
- Não deixar build quebrado.
- Não finalizar ciclo sem resumo técnico.

## Modo de execução

Trabalhe em ciclos. Em cada execução:

1. Leia o contexto dos MDs.
2. Audite rapidamente o projeto.
3. Escolha o próximo ciclo mais lógico em `tasks/DEVELOPMENT_LOOP.md`.
4. Implemente apenas esse ciclo ou uma parte coerente dele.
5. Rode build/testes/lint disponíveis.
6. Corrija erros gerados pela própria alteração.
7. Atualize documentação se necessário.
8. Finalize com resumo objetivo.

## Prioridade atual

Se o projeto ainda não existir, começar pelo Ciclo 1:

- Criar projeto macOS SwiftUI.
- Criar estrutura de pastas.
- Criar modelos base.
- Criar AppState.
- Criar tela inicial funcional mockada.
- Garantir que compila.

Se o projeto já existir, não recriar. Auditar e seguir o próximo ciclo coerente.

## Saída esperada ao final de cada execução

Retorne exatamente estas seções:

```text
## O que foi feito
- ...

## Arquivos alterados/criados
- ...

## Como validar
- ...

## Riscos ou pendências
- ...

## Próximo ciclo recomendado
- ...
```

## Critério principal

A cada loop, o projeto deve ficar mais próximo de um softphone real, comercial, white label e estável. Não priorize estética antes de chamada, registro, áudio e segurança.
