# Flux Softphone White Label para macOS

Este repositório contém as diretrizes para desenvolver, no Claude Code, um softphone white label para MacBook/macOS voltado à operação da Flux.

O objetivo é construir uma aplicação robusta, moderna e comercialmente reutilizável, capaz de ser personalizada por marca, conectada ao ecossistema Flux e pronta para evoluir para revendas, tenants e clientes finais.

## Direção principal

- Produto: softphone desktop para macOS.
- Modelo comercial: white label / multi-brand / multi-tenant.
- Stack recomendada inicial: app nativo macOS com SwiftUI, camada SIP isolada e arquitetura preparada para futura integração com PABX/SBC/CRM Flux.
- Prioridade: estabilidade de chamada, experiência profissional, facilidade de provisionamento e manutenção.

## Documentos principais

1. `CLAUDE.md` — instruções centrais para o Claude Code.
2. `docs/00_PRODUCT_BRIEF.md` — visão do produto e objetivos.
3. `docs/01_ARCHITECTURE.md` — arquitetura técnica.
4. `docs/02_WHITE_LABEL_SYSTEM.md` — sistema de personalização por marca.
5. `docs/03_SIP_AUDIO_CALL_ENGINE.md` — camada SIP, áudio e chamadas.
6. `docs/04_UI_UX_GUIDELINES.md` — visual, navegação e experiência.
7. `docs/05_SECURITY_PRIVACY.md` — segurança, credenciais e privacidade.
8. `docs/06_INTEGRATIONS_FLUX.md` — integrações futuras com Flux.
9. `docs/07_TESTING_QA.md` — testes e critérios de qualidade.
10. `docs/08_MACOS_RELEASE.md` — build, distribuição e assinatura.
11. `docs/10_PROJECT_STATUS.md` — progresso por ciclo e decisões estruturais.
12. `tasks/LOOP_PROMPT.md` — prompt para rodar o loop no Claude Code.
13. `tasks/DEVELOPMENT_LOOP.md` — cadência de desenvolvimento por ciclos.
14. `tasks/ACCEPTANCE_CRITERIA.md` — critérios mínimos para considerar uma etapa pronta.

## Como usar no Claude Code

Copie este pacote para a raiz do projeto e rode o Claude Code usando `tasks/LOOP_PROMPT.md` como prompt principal.

O Claude deve sempre ler `CLAUDE.md` antes de modificar qualquer arquivo.

## Estado atual do código

O projeto é um pacote Swift (SPM) com targets separados por camada — violações de camada são erro de compilação:

- `Sources/FluxDomain` — entidades, value objects e protocolos (sem dependências).
- `Sources/FluxInfrastructure` — implementações técnicas (engine SIP mock, logging sanitizado).
- `Sources/FluxWhiteLabel` — configuração de marca declarativa (`brand-config.json` + tema).
- `Sources/FluxSoftphone` — executável: App + Presentation (SwiftUI).
- `Tests/` — testes unitários por camada (Swift Testing).

O progresso por ciclo está registrado em `docs/10_PROJECT_STATUS.md`.

### Compilar, testar e rodar

O projeto compila apenas com Command Line Tools (não exige Xcode completo):

```bash
swift build        # compila
swift test         # roda os testes unitários
swift run          # abre o app (janela SwiftUI)
```

Com Xcode instalado, basta abrir a pasta do projeto (`Package.swift`) diretamente.

### Testar chamadas com áudio real

O app usa **exclusivamente a engine SIP real** (a simulada existe apenas na suíte de testes). O áudio do microfone exige um app empacotado e assinado (o macOS bloqueia o microfone de binários sem bundle). Gere o `.app`:

```bash
Scripts/build-app.sh        # compila em release, empacota e abre o app
```

No app: preencha a conta SIP real em Ajustes e registre. Na primeira chamada o macOS pede permissão de microfone (conceder). Recomenda-se fone de ouvido (ainda não há cancelamento de eco). A tela **Diagnóstico → Eventos SIP e mídia** mostra cada passo real (REGISTER, challenge, INVITE, respostas do servidor, mídia).

Notas de teste:

- Se o Keychain pedir acesso ao abrir (builds de desenvolvimento re-assinados), clique **"Sempre Permitir"** — negar impede o app de carregar a conta salva.
- Resposta `503 ... blocked` numa chamada = **política de rota do PABX** (o ramal não tem permissão para aquele destino, ex.: DDI móvel). Teste primeiro um ramal interno; para externos, libere a rota no servidor.
- Via `swift run` o registro e o fluxo funcionam, mas o microfone fica mudo — use o `.app` para o teste de áudio completo.
