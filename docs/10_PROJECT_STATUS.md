# 10 — Status do Projeto

Registro do progresso por ciclo (`tasks/DEVELOPMENT_LOOP.md`). Atualizar ao final de cada ciclo.

## Ciclo 1 — Bootstrap do projeto — CONCLUÍDO (2026-07-02)

Entregue:

- Pacote Swift (SPM) com camadas em targets separados: `FluxDomain`, `FluxInfrastructure`, `FluxWhiteLabel`, `FluxSoftphone` (executável).
- Modelos base do domínio: `SIPAccount`, `CallSession`, `CallHistoryEntry`, `Contact`, `AudioDevice`, `RegistrationState`, `CallState`, `SIPTransport`.
- Protocolos: `SIPClientProtocol` (com `SIPEvent`/`SIPClientError`), `AudioDeviceServiceProtocol`, `SecureCredentialsStoreProtocol`, `CallHistoryRepositoryProtocol`.
- `MockSIPClient` (actor): registro simulado, chamada de saída com progressão de estados, simulação de chamada de entrada e de falhas.
- White label: `BrandConfig`/`BrandTheme`/`BrandLoader` carregando `brand-config.json` embarcado, com validação de cores e fallback neutro.
- `AppState` (@MainActor) consumindo `AsyncStream<SIPEvent>` — a UI nunca fala com a engine.
- Tela inicial: sidebar (Visão geral, Discador, Histórico, Ajustes — respeitando feature flags), badge de status SIP no header, painel de demonstração da engine simulada.
- Logging estruturado (`os.Logger`) + `LogSanitizer` (máscara de usuário/número, redação de segredos).
- 35 testes unitários (Swift Testing) cobrindo domínio, mock SIP, sanitização e white label.
- Revisão multi-agente pós-implementação (arquitetura, segurança, corretude) com 9 achados confirmados e corrigidos, entre eles: reentrância de actor no `register()` do mock (unregister durante registro era sobrescrito), chamadas encerradas podiam ser "ressuscitadas" via `answer`, sanitizador não cobria JSON/`senha`/`api_key`/senhas com espaço, `Task` de eventos sem cancelamento no `deinit` do AppState, e cor de contraste `onPrimary` ausente do tema (texto branco hardcoded sobre a cor primária da marca).

Decisões estruturais:

- **SPM em vez de .xcodeproj**: o ambiente de desenvolvimento tem apenas Command Line Tools. O pacote compila com `swift build` e abre nativamente no Xcode quando disponível. A geração de bundle `.app` assinado (Info.plist, ícone, entitlements) fica para o Ciclo 12 (release).
- **Senha nunca aparece em `description`**: `SIPAccount` implementa `CustomStringConvertible` mascarado por design, protegendo contra interpolação acidental em log.
- **`brand-config.json` é a única fonte de marca**: se ausente/corrompido, o app cai em fallback neutro sem identidade (nunca identidade errada).
- **Logging é exceção transversal de camada**: `AppLog` (os.Logger) pode ser importado por qualquer camada do app; engines e stores continuam restritos ao composition root (`AppComposition`).
- **Tema tem `onPrimaryColor` opcional**: quando ausente no JSON, a cor de texto sobre a primária é calculada por luminância — marca com primária clara nunca rende texto invisível.

Pendências conhecidas:

- `swift run` abre a janela sem bundle `.app` (sem ícone no Dock, sem menu completo). Esperado até o ciclo de release.
- `AsyncStream` de eventos suporta um único consumidor (AppState). Documentado no protocolo; revisitar se surgir segundo consumidor.

## Ciclo 3 — Conta SIP e Keychain — CONCLUÍDO (2026-07-02)

Entregue:

- `KeychainCredentialsStore` (Security framework): conta inteira em um único item de senha genérica, com service único por marca (`<bundle>.<brandId>.sip-account` — docs/05, isolamento entre tenants). `SIPAccount` segue não-Codable de propósito; só o DTO interno do store sabe serializá-la.
- Tela de Ajustes real: resumo da conta com status, editar/remover (com diálogo de confirmação), grupo Sobre com dados da marca. Erros de persistência aparecem na própria tela; o formulário só fecha se o Keychain aceitou (dados digitados não se perdem).
- `AccountFormView`: cadastro/edição com validação (`SIPAccountValidator` + mensagens pt-BR), campos avançados (auth username, proxy, transporte, porta) e trim consistente.
- `AppState`: restaura conta do Keychain na abertura e registra automaticamente; salvar/remover/registrar/desregistrar com operações serializadas (cada nova operação cancela a anterior — o comando mais recente do usuário vence).
- Visão geral com cartão de conta real (registrar/desregistrar/gerenciar) e CTA de configuração quando não há conta.
- 42 testes (novos: roundtrip Keychain com senha unicode, sobrescrita, isolamento por service, limpeza idempotente, varredura de órfãos + regressões de concorrência do mock).

Revisão multi-agente do ciclo: 9 achados brutos, 6 confirmados e corrigidos — corrida de `register()` concorrente no mock (resolvida com token de geração por tentativa), ordenação de `register`/`removeAccount` no AppState (Tasks canceláveis serializadas), engine retinha credenciais após desregistro, falha de Keychain invisível em Ajustes, campos sem trim, porta customizada oculta na edição. 3 refutados com prova (ex.: `kSecUseDataProtectionKeychain` exige app assinado — pertence ao Ciclo 12).

Pendências conhecidas:

- Keychain usa o login keychain legado (ACL por binário); migrar para data protection keychain (`kSecUseDataProtectionKeychain`) quando o app for assinado com entitlements (Ciclo 12).
- Binário de dev não assinado: recompilar pode disparar prompt do Keychain ao ler item criado por build anterior.

## Ciclo 6 — Discador — CONCLUÍDO (2026-07-02)

Entregue:

- `PhoneNumberNormalizer` no domínio: remove separadores visuais preservando ramais curtos, códigos de serviço (`*142#`) e `+` internacional; validação `isDiallable` rejeita letras/vazio em vez de "consertar" a entrada. 7 testes.
- `DialerView`: campo de destino com colar nativo e Enter para ligar, teclado 1-9/*/0/#, apagar, botão Ligar habilitado apenas com conta registrada + destino válido + sem chamada ativa, com dica textual do motivo quando desabilitado.
- `AppState.startOutgoingCall`: normaliza, valida, origina na engine e loga com número mascarado (`LogSanitizer`). `hangupActiveCall` encerra.
- Indicador mínimo de chamada em andamento no discador (número, estado, Encerrar) — decisão de escopo: sem ele, uma chamada do mock ficaria presa sem controle; a tela de chamada completa (duração, mute, DTMF) permanece no Ciclo 7.

## Ciclo 7 — Chamada de saída completa — CONCLUÍDO (2026-07-02)

Entregue:

- `ActiveCallBar`: barra de chamada ativa visível em qualquer seção (via `safeAreaInset`), com interlocutor, estado, duração correndo (`TimelineView`), mute e encerrar. Substituiu o banner inline do discador.
- Mute: `AppState.toggleMute` → `setMuted` na engine; reseta ao encerrar a chamada.
- `CallHistoryEntry(session:accountURI:)` no domínio: mapeia sessão terminada → registro (atendida = `completed` com duração; saída não atendida = `cancelled`; entrada não atendida = `missed`; `rejected`/`failed`). Sessões vivas retornam `nil`.
- `FileCallHistoryRepository` (actor): JSON em `Application Support/<bundle>/<brandId>/call-history.json`, mais novo primeiro, teto de 500 registros, arquivo corrompido recomeça vazio sem travar, escrita atômica. Nunca grava senha/payload (testado).
- `AppState` grava no histórico ao receber estado terminal (com guarda anti-duplicata) e respeita a feature flag `callHistory` da marca.
- `HistoryView`: lista somente-leitura (direção, nome/número, resultado pt-BR, data, duração). Redial/filtros/limpar ficam no Ciclo 10.
- 60 testes no total (11 novos: repositório em disco e mapeamento sessão→registro).

## Ciclo 8 — Chamada de entrada — CONCLUÍDO (2026-07-02)

Entregue:

- `IncomingCallOverlay`: modal de chamada recebida sobre a janela inteira, com nome/número, Atender (Enter, verde) e Recusar (Esc, vermelho). Não é dispensável de outra forma — sai atendendo, recusando ou quando o chamador desiste.
- `AppState.answerIncomingCall`/`rejectIncomingCall`; atendida vira chamada ativa na barra (com mute/duração/encerrar do Ciclo 7); recusada/perdida vai ao histórico como "Recusada"/"Perdida" (mapeamento do Ciclo 7 reutilizado).
- Expiração de chamada não atendida no mock (`missedAfter`): como um CANCEL do chamador, encerra como perdida; atender/recusar antes cancela a expiração.
- Protocolo `SIPCallSimulating` (Infrastructure): menu "Desenvolvimento" (⌘⇧I simula recebida; item extra simula perdida em 3 s) aparece apenas quando a engine conforma — a engine real do Ciclo 5 não conforma e o menu some sozinho, sem flag manual.
- 63 testes (3 novos: expiração como perdida, atender cancela expiração, recusar → rejeitada).

## Ciclo 9 — Áudio — CONCLUÍDO (2026-07-02)

Entregue:

- `CoreAudioDeviceService` (actor): lista dispositivos reais de entrada/saída via CoreAudio (UID estável como id, marcação do padrão do sistema) e persiste a preferência do usuário em UserDefaults. NÃO altera o padrão do sistema — a preferência é do softphone e será aplicada pela engine real (Ciclo 5).
- `AVFMicrophonePermissionService`: status via AVFoundation/TCC. Solicitar exige `NSMicrophoneUsageDescription` no Info.plist; no build de dev sem bundle o serviço responde `.unsupported` em vez de pedir (TCC mataria o processo).
- `AudioDeviceServiceProtocol` evoluído: async, `nil` = padrão do sistema, preferência consultável. Novo `MicrophonePermissionServiceProtocol` com estados granted/denied/restricted/undetermined/unsupported.
- Seção Áudio real nos Ajustes: linha de permissão com ação contextual ("Solicitar acesso" / "Abrir Ajustes do Sistema" quando negada), pickers de microfone e saída com "Padrão do sistema" + dispositivos reais.
- `AppState.refreshAudioState` no start, ao abrir Ajustes e no evento `audioRouteChanged`.
- 66 testes (3 novos contra o CoreAudio real: listagem, roundtrip de preferência, rejeição de dispositivo inexistente).

Pendências conhecidas:

- Sem listener de mudança de hardware (kAudioHardwarePropertyDevices) — a lista atualiza ao abrir Ajustes; plugar/desplugar fone com Ajustes aberto exige reabrir a seção.
- Solicitação real de permissão de microfone só funcionará no app empacotado (Ciclo 12) com `NSMicrophoneUsageDescription`.
- Campainha/notificação de chamada recebida ainda não implementadas.

## Ciclo 10 — Histórico completo — CONCLUÍDO (2026-07-02)

Entregue:

- Ligar novamente: botão por linha + menu de contexto. Se não é possível ligar agora (sem registro ou chamada em andamento), leva ao discador pré-preenchido, onde o motivo fica visível — nunca disca às cegas (princípio do docs/06 aplicado ao redial).
- O número do discador migrou para `AppState.dialerNumber`: sobrevive à troca de seção e recebe o pré-preenchimento do redial.
- Filtro segmentado Todas/Perdidas com estados vazios próprios.
- Limpar histórico com diálogo de confirmação; erros de persistência aparecem na própria tela.
- Menu de contexto com "Copiar número".

## Ciclo 11 — Diagnóstico — CONCLUÍDO (2026-07-02)

Entregue:

- Seção Diagnóstico na sidebar (gated pela feature flag `diagnostics`): estado do registro, usuário mascarado, domínio/transporte, último erro com horário (persistido no AppState mesmo depois da UI limpar a mensagem), permissão de microfone, dispositivos, versão, engine SIP ativa e versão do macOS.
- "Copiar diagnóstico": relatório em texto passa por `LogSanitizer.redactSecrets` como última defesa antes do clipboard.

## Ciclo 5 — Engine SIP real (etapa 1: registro) — CONCLUÍDO (2026-07-02)

Entregue:

- `NativeSIPClient` (actor, Network.framework): REGISTER real com digest auth (RFC 3261/2617 — 401 e 407, MD5 com e sem `qop=auth`), re-registro automático antes do expirar (expira → estado `.expired` + erro visível), desregistro com `Expires: 0`, UDP/TCP/TLS, timeouts com watchdog, proteção de reentrância por geração de tentativa (mesmo padrão do mock).
- Componentes puros e testados: `SIPDigestAuthenticator` (validado contra o vetor canônico da RFC 2617), `SIPDigestChallenge` (parser tolerante a vírgulas em aspas), `SIPRequestBuilder` (senha jamais aparece na mensagem — testado), `SIPResponse` (headers case-insensitive).
- Chamadas na engine nativa respondem `SIPClientError.notSupported` (novo caso no domínio) até a etapa de mídia/RTP; mock continua a engine padrão e completa.
- Seletor de engine em Ajustes ("Simulada" / "Real — registro SIP", persistido em UserDefaults, aplicado ao reabrir). Menu Desenvolvimento some sozinho na engine real (não conforma `SIPCallSimulating`).
- Teste de integração de ponta a ponta: servidor SIP fake em UDP loopback que emite challenge e VALIDA o digest recebido — cobre 401→200, senha errada→403→authenticationFailed, servidor inalcançável (`.invalid`, RFC 2606) e paridade de contrato com o mock. 80 testes no total.

Pendências conhecidas (registro real):

- Sem retransmissão RFC 3261 Timer A para UDP (timeout único de 6 s por tentativa).
- `outboundProxy` no formato `host:porta` ainda não é parseado (usa só o host com a porta da conta).
- TLS usa validação de certificado padrão do sistema (sem pinning/config por tenant).
- Falha de rede é detectada na operação (registro/renovação), não por monitoramento contínuo de conectividade.

## Correção pós-QA visual (2026-07-02)

Feedback de QA em macOS com modo escuro revelou: o tema white label define apenas paleta clara, e textos sem cor explícita herdavam o branco do dark mode sobre superfícies claras do tema — dígitos do teclado e campo do discador invisíveis, ícone de mute idem.

- **Decisão**: `.preferredColorScheme(.light)` forçado na raiz até `BrandTheme` ganhar variante escura por marca (dark mode é opcional em docs/04). Remover quando a paleta escura existir.
- Cores explícitas do tema nos dígitos/campo do discador (defesa em profundidade).
- Selo **"SIMULAÇÃO"** na barra de chamada ativa quando a engine é o mock — chamada simulada não pode passar por chamada real (feedback: usuário achou que a chamada real estava "sendo processada errado" quando era o mock por design).

## Ciclo 5 — etapa 2 (chamadas com áudio real) — CONCLUÍDO (2026-07-02)

Entregue:

- Mídia: `G711` (µ-law/A-law puro, testado com roundtrip), `RTPPacket` (RFC 3550, build/parse), `SDP` (oferta/resposta G.711, parse de mídia remota) — tudo puro e testável.
- `RTPMediaSession` (`MediaSessionProtocol`): socket UDP BSD para RTP simétrico + `AVAudioEngine` (captura mic → AVAudioConverter 8 kHz Int16 → RTP; recepção → decode → AVAudioSourceNode), timer de 20 ms/160 amostras, mute, silêncio em underrun. Abstraída por protocolo para os testes rodarem sem hardware.
- `NativeSIPClient` estendido para chamadas: INVITE/SDP com digest auth, ACK (2xx e não-2xx), BYE, CANCEL, chamadas de ENTRADA (INVITE recebido → 180 → 200 com SDP), atender/recusar/encerrar, busy quando já em chamada. Loop de recepção contínuo roteia respostas por transação (`branch|método`) e trata requisições do servidor (INVITE/BYE/CANCEL/OPTIONS).
- Reescrita das mensagens SIP: `SIPRequest`/`SIPResponse` unificados, `SIPHeaderTools` (tag/uri/user/branch/cseq/display-name), builder genérico de requisição/resposta.
- Empacotamento `.app` (`Scripts/build-app.sh`): bundle assinado ad-hoc com `NSMicrophoneUsageDescription` + entitlement `audio-input` — necessário porque `swift run` não tem bundle e o macOS bloqueia o microfone.
- 93 testes (novos: G.711/RTP/SDP puros + chamada de saída de ponta a ponta INVITE→180→200→mídia→BYE contra servidor SIP fake com validação de digest).

Pendências conhecidas (chamadas reais):

- Áudio de microfone exige o `.app` empacotado (`Scripts/build-app.sh`); via `swift run` o macOS entrega silêncio no microfone (playback do remoto funciona).
- Sem cancelamento de eco (AEC) — usar fone de ouvido; sem jitter buffer adaptativo (buffer fixo de 600 ms); sem PLC (perda de pacote = silêncio).
- DTMF (RFC 2833), hold e transferência ainda pendentes na engine nativa.
- Uma chamada por vez (como o mock); sem re-INVITE.
- Sem Timer A (retransmissão UDP); TLS com validação padrão do sistema.

## Revisão pós-implementação (Ciclo 5 etapa 2) — 2026-07-02

Revisão multi-agente (SIP, RTP/áudio, concorrência). A verificação adversarial foi interrompida por limite de sessão dos agentes, então os achados foram avaliados manualmente contra o código. Corrigidos os reais:

- **INVITE retransmitido após atender**: respondia 486 Busy e o PABX derrubava a chamada (ACK se perde em UDP). Agora guarda o 200 OK do atendimento e o retransmite. Teste de regressão adicionado.
- **render() em thread de tempo real**: fazia alocação + `removeFirst` O(n) sob lock compartilhado com a rede (glitches/inversão de prioridade). Substituído por `AudioRingBuffer` de capacidade fixa (push/pop O(1), sem alocação no caminho quente); mesma troca no envio e recepção.
- **teardown() da mídia**: tornado idempotente e guardado, evitando race no encerramento.
- **CANCEL antes de provisional**: violava a RFC 3261 (CANCEL exige 1xx). Agora, se o usuário desiste em `.dialing`, o CANCEL é adiado até o primeiro 180/183.
- Cobertura nova: chamada de ENTRADA de ponta a ponta (servidor origina INVITE → atender → mídia) e retransmissão. Removidos probes órfãos deixados pelos agentes. 95 testes.

## Correções pós-teste do usuário — 2026-07-02

Feedback: app mostrava "SIMULAÇÃO", chamada não conectava de verdade, e o discador "ficava branco" (não dava para ver/digitar) após encerrar.

- **Causa 1 — engine não trocava**: a seleção "Real" só valia ao reiniciar o processo, mas fechar a janela no macOS não reinicia o app. Corrigido: `AppState.setEngine` troca a engine SIP em tempo de execução (encerra a atual, sobe a nova, re-registra a conta salva). O picker de Ajustes aplica na hora.
- **Causa 2 — discador "branco"**: o sistema estava em modo escuro; o tema white label só tem paleta clara, então o macOS pintava textos padrão de branco sobre superfícies claras (dígitos invisíveis). O `.preferredColorScheme(.light)` do SwiftUI não bastava; agora força-se `NSApp.appearance = .aqua` no AppKit (confiável). Reverter quando `BrandTheme` ganhar variante escura por marca.
- `SIPEngineKind` promovido a tipo próprio; `AppState` recebe uma fábrica de engine por tipo em vez do cliente pronto.

## Registro de eventos no Diagnóstico — 2026-07-02

Feedback: o Diagnóstico não trazia nada sobre chamadas nem evidência do que a engine fez — impossível distinguir simulação de tráfego real (usuário viu senha falsa "registrar" e concluiu, corretamente na ocasião, que era o mock).

- `DiagnosticLog` (Infrastructure): ring buffer de eventos sanitizados com stream para a UI.
- As duas engines narram o que fazem: o mock com prefixo **"SIMULAÇÃO"** em toda linha ("registro fictício — NENHUM servidor é contactado; a senha não é validada"); a nativa com **"SIP real"** mostrando o diálogo com o servidor (REGISTER → challenge digest com realm → 200/403; INVITE → respostas → codec/endpoint RTP; BYE; quedas de conexão).
- Caso especial evidenciado: **200 OK sem challenge** = o servidor aceitou sem validar a senha (auth por IP/ACL no PABX) — o log explica, em vez de deixar parecer bug.
- Diagnóstico ganhou a seção "Eventos SIP e mídia" (auto-scroll) e o "Copiar diagnóstico" inclui os últimos 80 eventos.
- Flake identificado e corrigido: o teste de INVITE retransmitido checava `media.didStop` imediatamente, mas a parada da mídia é assíncrona (Task interno do endCall) — agora usa polling como os demais. 6 execuções seguidas verdes.
- Correções da sessão de QA visual: linha de arranque do log não aparecia (o stream agora reproduz o histórico ao assinar); badge de status global mostra "(simulação)" quando a engine é o mock — "Registrado (simulação)" nunca passa por registro real.

## Primeiro teste real contra PABX + engine única — 2026-07-02

O log de diagnóstico do teste do usuário provou a engine real funcionando de ponta a ponta:
`REGISTER → 401 challenge digest → 200 OK validado pelo servidor`, e INVITEs chegando ao PABX — que recusou com `503 Mobile/Fixed DDI calls blocked` (política de rota do ramal, não defeito do app).

Mudanças a partir do teste:

- **Engine simulada REMOVIDA do app** (decisão de produto a pedido do usuário): "Registrado (simulação)" parecia produto quebrado, não recurso de dev. `MockSIPClient` permanece exclusivamente na suíte de testes (dezenas de testes dependem dele como referência de contrato). Removidos: picker de engine, menu Desenvolvimento, selos de simulação, `SIPEngineKind`, troca em runtime.
- **Motivo do servidor agora chega à UI**: novo `SIPClientError.serverRejected(code:reason:)` — chamada recusada mostra "O servidor recusou (503): Mobile DDI calls blocked" em vez de falha genérica (era isso que fazia o teste parecer sem sentido).
- **Bug de SDP corrigido**: sess-id levava timestamp com ".0" (RFC 4566 exige dígitos) — causa provável do `400 Bad Session Description` observado.
- README ganhou notas de teste: prompt do Keychain em builds re-assinados ("Sempre Permitir"), 503 = rota bloqueada no PABX (testar ramal interno primeiro).

## MARCO: áudio bidirecional validado em campo + fix da queda em ~5 s — 2026-07-02

Teste do usuário contra PABX real: **áudio bidirecional G.711 (PCMA) funcionando** — mas a chamada caía com BYE do servidor ~4-5 s após o atendimento, consistentemente.

Diagnóstico: após o atendimento, PABX/SBC enviam requisições EM DIÁLOGO (re-INVITE de renegociação de mídia, UPDATE de session-timer). O cliente ignorava re-INVITE em chamada ativa e respondia 501 a UPDATE → servidor desiste e derruba com BYE. Correções:

- **re-INVITE em diálogo**: respondido com 200 OK + SDP; se a oferta muda destino/porta/codec da mídia, o RTP é redirecionado ao vivo (`MediaSessionProtocol.retarget` — re-connect do socket UDP sem parar o áudio). Retransmissão (mesmo CSeq) reenvia o 200 guardado; CSeq novo renegocia.
- **UPDATE em diálogo**: 200 OK (com SDP se a oferta trouxer; sem corpo para refresh puro). Fora de diálogo: 481.
- **NOTIFY/INFO/MESSAGE**: 200 OK (501 fazia servidores estritos derrubarem o diálogo). REFER segue 501 (transferência ainda não suportada).
- **200 OK de INVITE retransmitido** (ACK perdido): ACK reenviado (RFC 3261 §13.2.2.4).
- **Todo request recebido agora é logado**, e o BYE loga o header `Reason`/causa do PABX quando presente — o próximo diagnóstico mostra a causa exata de qualquer queda.
- 97 testes (2 novos: re-INVITE renegocia sem derrubar + retarget de mídia; UPDATE→200) — 4 execuções verdes.

Limitação conhecida: resposta a re-INVITE/UPDATE sempre anuncia `a=sendrecv` (oferta com `a=sendonly`/hold não é espelhada — hold formal fica com o recurso de hold).

## Fix definitivo da queda: route-set (Record-Route) — 2026-07-02

Segundo teste em campo: áudio OK, mas BYE do servidor com **`Reason: SIP;cause=408;text="ACK Timeout"`** — o log de eventos entregou a causa exata. Nossos ACKs eram enviados (e re-enviados a cada 200 retransmitido), mas nunca chegavam ao UAS: o proxy do PABX faz **record-routing** e requisições em diálogo sem headers `Route` não eram encaminhadas ao servidor de mídia.

- Implementado o route-set da RFC 3261 §12: `Record-Route` do 200 OK capturado e invertido (originador) / do INVITE na ordem (atendedor), armazenado no diálogo e emitido como `Route:` em **ACK e BYE**. O route-set aparece no log de diagnóstico.
- Teste de regressão: servidor fake com dois Record-Route valida ACK e BYE com `Route` na ordem invertida. 98 testes, 4 execuções verdes.
- Nota: o prompt do Keychain a cada rebuild (binário ad-hoc muda de identidade) segue sendo esperado em dev — "Sempre Permitir"; resolve-se com Developer ID no Ciclo 12.

## ✅ MVP DE TELEFONIA REAL VALIDADO EM CAMPO — 2026-07-02

Confirmado pelo usuário contra PABX de produção (177.70.30.x):

- Registro SIP real com digest auth validado pelo servidor.
- Chamada de saída completa: INVITE → 200 → ACK (com route-set) → conversa.
- **Áudio bidirecional G.711/PCMA estável**.
- Chamada permanece ativa até desligamento real; encerramento limpo.

A métrica de sucesso inicial do docs/00_PRODUCT_BRIEF.md está cumprida no que depende do app: registra conta real, completa chamada com áudio bidirecional, gera build instalável. (Chamada de entrada real aguarda teste em campo; o fluxo é coberto por testes automatizados.)

Aprendizados de interop que viraram teste de regressão: digest com qop, route-set/Record-Route, re-INVITE/UPDATE em diálogo, retransmissões UDP (200/INVITE/ACK), sess-id numérico no SDP, motivo de recusa do servidor na UI.

## DTMF (RFC 2833) + UX do discador — 2026-07-02

Entregue (feedback direto do usuário no teste de campo):

- **DTMF fora de banda (RFC 2833/4733)**: oferta `telephone-event` PT 101 no SDP (e espelho do PT remoto ao atender/renegociar); parser extrai o PT remoto mesmo quando ≠ 101; `RTPMediaSession.sendDTMF` enfileira o evento no ticker de 20 ms (6 pacotes de duração crescente + fim retransmitido 3×, marker no primeiro, timestamp do início do tom — E-bit pode se perder em UDP); pacotes de evento substituem o áudio do tick.
- **Teclado DTMF em chamada**: botão na barra de chamada ativa abre popover 4×3; cada dígito envia RFC 2833 e toca o tom local.
- **Tom de tecla local no discador**: `DTMFTonePlayer` (AVAudioEngine leve, dual-tone real de 120 ms com fade) toca a cada dígito acrescentado — teclado físico, botão ou o que for (detecção via onChange do número).
- **Teclado físico disca direto**: o campo do discador foca sozinho ao entrar na seção (e ao encerrar chamada); digitou → aparece; **Enter liga**. Clique nos botões devolve o foco ao campo.
- `SIPClientError.notSupported` para DTMF agora significa "telephone-event não negociado nesta chamada" (aparece como mensagem ao usuário); sem chamada ativa → `callNotFound`.
- 103 testes (5 novos: SDP com/sem telephone-event, payload RFC 4733 bit a bit, negociação chegando à mídia + envio de dígitos fim-a-fim com servidor fake). 4 execuções verdes.

Pendências: DTMF recebido (URA raramente exige, telefone físico→app é raro) não é decodificado; tom local não soa DTMF de entrada.

Refinamento por feedback do usuário (mesmo dia): **teclado único, modo contextual** — em vez de um teclado DTMF separado na barra de chamada, o próprio DISCADOR envia DTMF quando a chamada está ativa (botões e teclado físico; dígitos enviados exibidos; backspace desabilitado — dígito enviado é enviado; o número discado fica intacto). O botão de grade na barra de chamada virou atalho para a seção Discador. `DTMFPadView` removido.

## Editor white label + glassmorphism — 2026-07-02

Etapa visual sobre a V1 comercial (branch `feature/white-label-theme-editor`).
Nenhuma linha de SIP/áudio/chamadas/histórico foi alterada.

- **`WhiteLabelTheme` + `ThemeStore`** (FluxWhiteLabel): tema editável em
  runtime com persistência JSON no container da marca e imagens (logo/fundo)
  como arquivos relativos. Decodificação tolerante, validação de cores,
  export/import JSON pronto (API; UI futura). Fallback garantido: sem arquivo
  ou corrompido → tema padrão derivado do `brand-config.json`.
- **Seção "Aparência"** (`BrandingSettingsView`): nome da marca, logo
  (fileImporter, limite 20 MB), 4 ColorPickers, fundo sólido/gradiente (2–3
  cores)/imagem, sliders de opacidade do vidro, desfoque do fundo e raio dos
  cantos, aviso de contraste baixo (não bloqueante) e restaurar padrão com
  confirmação. Preview em tempo real (`ThemePreviewView`) lê o mesmo store.
- **Glassmorphism**: `GlassPhoneShell` (corpo de smartphone flutuante — o
  discador vive dentro dele), `GlassCard` (visão geral), `ThemedBackgroundView`
  (fundo por estilo, com blur configurável), `BrandLogoView` (logo custom com
  fallback na inicial sobre a cor primária).
- **Aplicação do tema**: `resolvedBrandTheme(base:)` projeta as cores custom
  sobre o `BrandTheme` — views seguem consumindo `BrandTheme`; patch de 2–3
  linhas por view (Dialer/Overview/MainView/ActiveCallBar/IncomingCallOverlay/
  History/Settings). Cores semânticas de chamada permanecem fixas.
- 124 testes (21 novos: modelo, resolução, clamps, store, imagens,
  export/import). Verificado ao vivo: edição reflete no preview e na UI na
  hora, JSON persistido em disco, restaurar padrão funciona.
- Nota de dev: rebuild ad-hoc muda a identidade do binário → Keychain nega a
  conta salva na primeira abertura ("Não foi possível carregar a conta salva")
  — comportamento já documentado, resolve-se com Developer ID no Ciclo 12.

## Modo compacto — 2026-07-02

Feedback direto do usuário na mesma etapa: depois de registrado e
personalizado, o app deve poder "virar" só o discador personalizado.

- **`CompactModeView`**: a janela vira o "aparelho" (420×640, tamanho fixo via
  `.windowResizability(.contentSize)`) — só o discador temático no shell de
  vidro. Reusa DialerView/ActiveCallBar/IncomingCallOverlay: chamada continua
  100% controlável (atender, recusar, mute, DTMF, encerrar) no modo compacto.
- **Alternância**: botão na toolbar (modo completo → compacto), botão de
  expandir no canto do aparelho (compacto → completo), atalho ⇧⌘M nos dois
  sentidos. Preferência persistida (`@AppStorage "ui.compact-mode"`) — quem usa
  o app como aparelho reabre direto no aparelho.
- Verificado ao vivo nos dois sentidos; janela encolhe/cresce corretamente.

Refinamento por feedback do usuário (2026-07-03): **sem moldura quadrada** —
no modo compacto a janela é transparente e sem título (`WindowChromeConfigurator`
+ `.windowStyle(.hiddenTitleBar)`); só o aparelho arredondado flutua no desktop,
com o fundo do tema DENTRO do corpo (`GlassPhoneShell.embedsThemedBackdrop`).
Aprendizados de AppKit que viraram regra no código:

- `isMovableByWindowBackground` com NSHostingView engole TODOS os cliques como
  arrasto de janela (teclado do discador morto) — nunca usar; o arrasto é uma
  alça explícita no header do aparelho (`WindowDragHandle` + `performDrag`).
- A sombra da NSWindow desenha o contorno do retângulo transparente —
  `hasShadow = false` no compacto (a sombra é do shell, via SwiftUI).
- Launch direto no modo compacto herda chrome restaurado da sessão anterior
  (faixa de titlebar) — `.hiddenTitleBar` na cena resolve na criação da janela;
  o véu do overlay de chamada recebida vira quadrado sobre o desktop em janela
  transparente (`IncomingCallOverlay(showsBackdrop: false)` no compacto).

## Bug de release V1 corrigido: brand-config fora do .app — 2026-07-03

Descoberto ao repackagear durante esta etapa: o acessor `Bundle.module` gerado
pelo SwiftPM procura o bundle de recursos APENAS na raiz do executável e no
caminho absoluto de `.build` DA MÁQUINA DE DEV — nunca em `Contents/Resources`.
O `.app` da V1 só carregava a marca Flux porque rodava na máquina de
desenvolvimento; em qualquer outro Mac abriria com fallback neutro ou
`fatalError`. Correção: `BrandLoader.brandResourceBundle()` resolve o bundle
explicitamente (Contents/Resources → diretório do executável → contexto de
testes), sem `Bundle.module`, falhando gracioso (fallback neutro). Verificado
com o bundle de `.build` renomeado: o `.app` carrega a marca do próprio pacote.

## Controle de codecs + cancelamento de eco/supressão de ruído — 2026-07-03

Primeira etapa funcional da V2 (Ajustes → Áudio):

- **Controle de codec G.711**: `MediaPreferences` (FluxDomain) com codec
  preferido (PCMA padrão — mercado BR), persistido em UserDefaults. A oferta
  SDP anuncia o preferido primeiro (ambos sempre ofertados); em resposta e
  re-INVITE, `negotiatedCodec(preferring:)` escolhe o nosso quando o remoto o
  oferece. Preferências lidas a cada negociação — valem na próxima chamada.
- **Eco/ruído/ganho**: Voice Processing I/O da Apple no `RTPMediaSession`
  (`AudioProcessingOptions` por chamada): AEC + supressão de ruído (recurso
  único do sistema, um toggle) e AGC (toggle próprio). Habilitado antes de
  ler formatos (o VPIO os troca); falha vira log + mídia sem processamento —
  nunca silêncio. Padrão do produto: ligado.
- UI: Ajustes → Áudio ganhou picker de codec e os dois toggles, com nota de
  que alterações valem a partir da próxima chamada (chamada ativa intocada).
- 130 testes (6 novos: round-trip do store, fallback de codec desconhecido,
  preferência local honrada/fallback na negociação, ordem da oferta SDP).
- Pendente de validação em campo: qualidade do AEC/NS contra PABX real em
  alto-falante (teste unitário não cobre acústica).

### Incidente no teste de campo (mesmo dia): chamada muda com VP ligado

Primeira chamada com o Voice Processing LIGADO POR PADRÃO ficou muda (sem
ringback, sem áudio nos dois sentidos). Causas prováveis: (a) o bloco de
ativação seguia com engine MEIO-CONFIGURADO se a entrada ativasse e a saída
falhasse (entrada VPIO + saída normal = mudez); (b) VPIO pode não funcionar
em qualquer combinação de hardware/dispositivo mesmo "ativando com sucesso".

Correções:
- Falha em QUALQUER passo do VP descarta o engine inteiro e reconstrói um
  limpo no caminho validado da V1 (nunca híbrido).
- Padrão voltou a DESLIGADO (`MediaPreferences.standard`) — AEC/NS é opt-in
  nos Ajustes até ser validado em campo; a UI avisa "em validação".
- Log do modo + formato de entrada no start do engine, para depuração.
- Lição de processo: recurso que altera o caminho de áudio validado NUNCA
  entra ligado por padrão antes do teste de campo (docs/00: estabilidade é
  a prioridade nº 1).

Nota: o ringback da V1 vem em banda (após o 200); a engine não reproduz
early media (183 com SDP) — suporte a early media fica como evolução futura.

## ✅ CANCELAMENTO DE ECO VALIDADO EM CAMPO — 2026-07-05

Depuração de dois dias fechada com confirmação do usuário: com o eco ligado,
a voz que retornava pelo alto-falante→microfone do MacBook desapareceu para
o interlocutor; áudio bidirecional intacto. VAD e controle de codec (PCMU e
PCMA) também validados em campo. AGC segue em observação (clipping pontual).

Três descobertas de macOS 15 pagaram a etapa (todas provadas por reprodução
local com scripts, sem queimar chamadas de teste):

1. **VPIO exige grafo de saída pré-existente**: `setVoiceProcessingEnabled`
   em engine "virgem" → `engine.start()` falha com -10875 na unidade de
   saída assim que um nó de reprodução é conectado. Tocar o `mainMixerNode`
   ANTES do VP resolve. (Não documentado pela Apple.)
2. **Entrada multicanal com VP**: o inputNode vira 5 canais no MacBook Air —
   todos cópias idênticas do sinal JÁ processado pelo AEC.
3. **Downmix implícito do AVAudioConverter multicanal→mono produz silêncio
   absoluto sem reportar erro** — o canal 0 precisa ser extraído manualmente.

Também na etapa: TCC de microfone invalidado a cada re-assinatura ad-hoc
(entrega zeros com status "Permitida"; resolve com Developer ID no Ciclo 12);
oferta PCMA-first inicialmente suspeita foi inocentada (era o microfone).

Instrumentação permanente no Diagnóstico que viabilizou tudo: contadores RTP
(tx/rx/PT/descartados), pico do microfone, tempo de subida do engine e
estado REAL do AEC (ativo/indisponível/desligado).

Pendências da frente de áudio: G.729 (decisão de negócio — licença comercial
bcg729 vs transcodificação no PABX vs Opus), AGC/clipping em observação,
preferência de dispositivo dos Ajustes ainda não aplicada ao engine.

## Early media (ringback do servidor) — 2026-07-05

Campo: sem ringback no softswitch wholesale mesmo com "tratamento de mídia"
ligado (MicroSIP com a mesma conta ouvia). Causa: o softswitch entrega o
ringback como **early media** (183 Session Progress com SDP + RTP antes do
atendimento) e a engine ignorava o corpo dos provisionais — mídia só no 200.

- `handleInviteProvisional`: 183/180 com SDP liga o RTP imediatamente
  (RFC 3960) — flag `mediaStarted` no contexto da chamada.
- 200 OK com mídia já rodando vira `retarget` (nunca segundo `start`, que
  duplicaria engine/timers da sessão).
- Falha no start do early media não derruba a chamada: reverte a flag e o
  200 faz o start normal (caminho validado).
- Diagnóstico: "← 183 com SDP — early media PCMU de X:Y" / "← 183 sem SDP".
- Teste de regressão: servidor fake com 183+SDP (porta própria) → start
  único no early media + retarget para a mídia definitiva no 200. 132 testes.

Também: logo do aparelho 20% maior (discador 46 pt, preview 41, visão 62).

## Próximo ciclo

1. **Validar em campo**: chamada de entrada (celular → ramal do app). DTMF contra URA real ✅ validado em 2026-07-05 (navegação de menu com o teclado contextual).
2. **Hold/resume** — completa a telefonia básica.
3. **Robustez de rede**: Timer A (retransmissão UDP), jitter buffer adaptativo, reconexão pós-sleep.
4. **Ciclo 12 — Release**: ícone, Developer ID + notarização, DMG.
